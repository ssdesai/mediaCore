#!/usr/bin/env bash
set -uo pipefail

# Self-test for sync-plans.sh --check, the template-version line, and update.sh
# (self/features/sweep-and-check/README.md). Run by self/gate.sh, or by hand:
# bash self/tests/sync-check.sh
#
# Copies the real sync-plans.sh, update.sh, templates/ and hooks/ (a missing update.sh is
# tolerated — RED until plan 77 lands, the cost-recovery.sh convention) into two
# throwaway fixtures. hooks/ rides along because sync-plans.sh calls
# hooks/wire-settings.py to wire .claude/settings.json; without it every --check would
# carry a SKIPPED line and never reach rc 0. No model, no network.
#
# Fixture A — a consuming repo at $TMP/consumer, git initted with one commit, holding
# copies of sync-plans.sh, update.sh, templates/ and hooks/ under agentTooling/. Asserts
# the --check contract: a fresh seed reports the five generated stubs, the three
# repo-owned scripts in-sync (template-version 2, 2, 1 in that order) and the hook
# wiring it just wrote in-sync, with only
# PROJECT_FACTS.md unfilled, rc 1, "needs attention: 1 item(s)"; the seeded BACKLOG.md
# is in-sync rather than a second unfilled item, since an empty backlog is a correct
# steady state, and the generated plans/README.md names it; filling
# PROJECT_FACTS.md brings it to rc 0 "is in sync"; a stub edited out from under the
# template reports STALE and --check writes nothing, while the plain sync repairs it;
# deleting a script's template-version line reports DRIFT (both under --check and the
# plain sync, which still keeps the file); a body-only edit below a script's
# REPO-SPECIFIC marker is not drift; a deleted repo-owned script reports missing and
# the plain sync recreates it; BACKLOG.md with a repo's own entry in it survives a sync
# byte-identical and is re-seeded when deleted; and an unknown flag is a usage error,
# exit 2. It also
# reads (never writes) the real checkout, asserting gate.sh/pr.sh/worktree-setup.sh
# carry the same template-version in templates/plans/ and in self/, and that the upstream
# URL is ONE string across the three places that mirror it by hand — analysis/roots.py's
# SELF_CORPUS_IDENTITY, update.sh's DEFAULT_REMOTE and the root README.md's git subtree
# commands (section 8b).
#
# Fixture B — a subtree cycle: a bare $TMP/upstream.git, a $TMP/work clone that commits
# the same three copies as main, and $TMP/consumer2, which `git subtree add`s it at
# agentTooling/, seeds plans/ and fills PROJECT_FACTS.md. Asserts update.sh: a pull with
# a clean tree brings across a new upstream file and re-runs sync-plans.sh, rc 0; a
# dirty tree refuses without pulling, naming the untracked file, rc 1; running it from
# the source checkout itself (no prefix to pull into) refuses naming "source checkout",
# rc 1; and an unknown flag is a usage error, exit 2.
#
# Depends on git subtree being available and on the three templates
# (templates/plans/{gate,pr,worktree-setup}.sh) carrying a `# template-version: <N>`
# line, which plan 77 adds — RED until then.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# tv <file> — the template-version integer, or empty if the line is absent.
tv() { sed -n 's/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1; }

echo "sync-check"

# ── Fixture A: a consuming repo ─────────────────────────────────────────────────
CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/agentTooling"
cp "$AT/sync-plans.sh" "$CONSUMER/agentTooling/sync-plans.sh" 2>/dev/null || true
cp "$AT/update.sh" "$CONSUMER/agentTooling/update.sh" 2>/dev/null || true
cp -r "$AT/templates" "$CONSUMER/agentTooling/templates" 2>/dev/null || true
cp -r "$AT/hooks" "$CONSUMER/agentTooling/hooks" 2>/dev/null || true
chmod +x "$CONSUMER/agentTooling/sync-plans.sh" "$CONSUMER/agentTooling/update.sh" 2>/dev/null || true
S="$CONSUMER/agentTooling/sync-plans.sh"

git -C "$CONSUMER" init -q
git -C "$CONSUMER" symbolic-ref HEAD refs/heads/main
git -C "$CONSUMER" config user.email test@example.invalid
git -C "$CONSUMER" config user.name "sync-check test"
git -C "$CONSUMER" add -A && git -C "$CONSUMER" commit -q -m "init"

"$S" >/dev/null 2>&1

# ── 1. fresh seed: everything in-sync except the unfilled skeleton ─────────────
out="$("$S" --check 2>&1)"; rc=$?
check "1a. --check rc 1 on a fresh seed (got $rc)" '[[ $rc -eq 1 ]]'
for rel in README.md interactive/README.md features/README.md features/TEMPLATE.md .gitignore; do
  check "1b. in-sync stub $rel" "grep -qF \"  in-sync    plans/$rel\" <<<\"\$out\""
done
check "1c. gate.sh in-sync (template-version 2)" 'grep -qF "  in-sync    plans/gate.sh (template-version 2)" <<<"$out"'
check "1d. pr.sh in-sync (template-version 2)" 'grep -qF "  in-sync    plans/pr.sh (template-version 2)" <<<"$out"'
check "1e. worktree-setup.sh in-sync (template-version 1)" 'grep -qF "  in-sync    plans/worktree-setup.sh (template-version 1)" <<<"$out"'
check "1f. gate.sh, pr.sh, worktree-setup.sh lines appear in that order" \
  '[[ "$out" == *"plans/gate.sh (template-version 2)"*"plans/pr.sh (template-version 2)"*"plans/worktree-setup.sh (template-version 1)"* ]]'
check "1g. unfilled PROJECT_FACTS.md" 'grep -qF "  unfilled   plans/PROJECT_FACTS.md" <<<"$out"'
check "1h. last line: needs attention 1 item(s)" '[[ "$(tail -1 <<<"$out")" == "needs attention: 1 item(s) above." ]]'
# BACKLOG.md, seeded beside PROJECT_FACTS.md. An EMPTY backlog is the correct steady
# state for a repo that has closed everything it found, so a present one is in-sync
# rather than "unfilled" — 1h is the assertion that says so, since a second unfilled
# item would have made it 2.
check "1i. in-sync plans/BACKLOG.md" 'grep -qF "  in-sync    plans/BACKLOG.md" <<<"$out"'
check "1j. the seeded BACKLOG.md is the skeleton header and no entries" \
  '[[ -f "$CONSUMER/plans/BACKLOG.md" ]] && head -1 "$CONSUMER/plans/BACKLOG.md" | grep -qF "# Backlog" && ! grep -q "^- " "$CONSUMER/plans/BACKLOG.md"'
# The other half of item 10: humanNetworkMap added this line to its generated
# plans/README.md by hand and the next sync overwrote it, because the stub is GENERATED
# and the template had no such entry.
check "1k. the generated plans/README.md names BACKLOG.md" 'grep -qF "BACKLOG.md" "$CONSUMER/plans/README.md"'

# ── 2. filling PROJECT_FACTS.md clears the only item ────────────────────────────
echo "extra fact" >> "$CONSUMER/plans/PROJECT_FACTS.md"
out="$("$S" --check 2>&1)"; rc=$?
check "2a. --check rc 0 after filling PROJECT_FACTS.md (got $rc)" '[[ $rc -eq 0 ]]'
check "2b. last line: in sync" '[[ "$(tail -1 <<<"$out")" == "plans/ and the hook wiring are in sync with agentTooling/." ]]'

# ── 3. a stale generated stub, --check writes nothing, plain sync repairs it ────
echo "extra readme line" >> "$CONSUMER/plans/README.md"
cp "$CONSUMER/plans/README.md" "$TMP/README.md.before"
out="$("$S" --check 2>&1)"; rc=$?
check "3a. --check rc 1 after README.md drift (got $rc)" '[[ $rc -eq 1 ]]'
check "3b. STALE plans/README.md line" 'grep -qF "  STALE      plans/README.md (differs from templates/plans/README.md; run sync-plans.sh)" <<<"$out"'
check "3c. --check wrote nothing (README.md unchanged)" 'cmp -s "$CONSUMER/plans/README.md" "$TMP/README.md.before"'
out2="$("$S" 2>&1)"
check "3d. plain sync prints synced README.md" 'grep -qF "  synced     plans/README.md" <<<"$out2"'
out3="$("$S" --check 2>&1)"; rc3=$?
check "3e. --check rc 0 again (got $rc3)" '[[ $rc3 -eq 0 ]]'

# ── 4. a repo-owned script missing its template-version line: DRIFT ─────────────
awk '!/^# template-version:/' "$CONSUMER/plans/pr.sh" > "$TMP/pr.sh.stripped" && mv "$TMP/pr.sh.stripped" "$CONSUMER/plans/pr.sh"
out="$("$S" --check 2>&1)"; rc=$?
check "4a. --check rc 1 after stripping pr.sh's version line (got $rc)" '[[ $rc -eq 1 ]]'
line="$(grep -F 'plans/pr.sh (template-version 0 < 2' <<<"$out")"
check "4b. DRIFT line for pr.sh" '[[ "$line" == "  DRIFT      plans/pr.sh (template-version 0 < 2;"* ]]'
out2="$("$S" 2>&1)"; rc2=$?
check "4c. plain sync also rc 1" '[[ $rc2 -eq 1 ]]'
line2="$(grep -F 'plans/pr.sh (template-version 0 < 2' <<<"$out2")"
check "4d. plain sync also prints the DRIFT line" '[[ "$line2" == "  DRIFT      plans/pr.sh (template-version 0 < 2;"* ]]'
check "4e. plain sync still prints kept pr.sh" 'grep -qF "  kept       plans/pr.sh" <<<"$out2"'
cp "$CONSUMER/agentTooling/templates/plans/pr.sh" "$CONSUMER/plans/pr.sh"
chmod +x "$CONSUMER/plans/pr.sh"

# ── 5. a body-only edit below REPO-SPECIFIC is not drift ────────────────────────
gate_ln="$(grep -n 'REPO-SPECIFIC' "$CONSUMER/plans/gate.sh" | head -n 1 | cut -d: -f1)"
awk -v ln="$gate_ln" 'NR==ln{print; print "# sync-check: appended body line"; next}1' \
  "$CONSUMER/plans/gate.sh" > "$TMP/gate.sh.edited" && mv "$TMP/gate.sh.edited" "$CONSUMER/plans/gate.sh"
out="$("$S" --check 2>&1)"; rc=$?
check "5a. --check rc 0 after a body-only edit to gate.sh (got $rc)" '[[ $rc -eq 0 ]]'

# ── 6. a missing repo-owned script ───────────────────────────────────────────────
rm -f "$CONSUMER/plans/worktree-setup.sh"
out="$("$S" --check 2>&1)"; rc=$?
check "6a. --check rc 1 after removing worktree-setup.sh (got $rc)" '[[ $rc -eq 1 ]]'
check "6b. missing line for worktree-setup.sh" 'grep -qF "  missing    plans/worktree-setup.sh (never seeded; run sync-plans.sh)" <<<"$out"'
out2="$("$S" 2>&1)"
check "6c. plain sync recreates it" 'grep -qF "  created    plans/worktree-setup.sh" <<<"$out2"'
out3="$("$S" --check 2>&1)"; rc3=$?
check "6d. --check rc 0 after recreate (got $rc3)" '[[ $rc3 -eq 0 ]]'

# ── 6b. BACKLOG.md is seeded once and never overwritten ─────────────────────────
# The whole point of the stub: a repo writes entries into it, and the next
# `subtree pull` must not take them away — which is exactly what happened to
# humanNetworkMap's hand-added plans/README.md line and is why the entry now ships in
# the template instead.
printf '\n- **A real entry somebody wrote.** Assertion 6e.\n' >> "$CONSUMER/plans/BACKLOG.md"
cp "$CONSUMER/plans/BACKLOG.md" "$TMP/BACKLOG.md.before"
out2="$("$S" 2>&1)"
check "6e. plain sync keeps BACKLOG.md" 'grep -qF "  kept       plans/BACKLOG.md" <<<"$out2"'
check "6f. ...byte-identical, with the repo's own entry still in it" 'cmp -s "$CONSUMER/plans/BACKLOG.md" "$TMP/BACKLOG.md.before"'
out="$("$S" --check 2>&1)"; rc=$?
check "6g. --check rc 0 — an entry is content, not drift (got $rc)" '[[ $rc -eq 0 ]]'
rm -f "$CONSUMER/plans/BACKLOG.md"
out="$("$S" --check 2>&1)"; rc=$?
check "6h. --check rc 1 with BACKLOG.md deleted (got $rc)" '[[ $rc -eq 1 ]]'
check "6i. missing line for BACKLOG.md" 'grep -qF "  missing    plans/BACKLOG.md (never seeded; run sync-plans.sh)" <<<"$out"'
out2="$("$S" 2>&1)"
check "6j. plain sync re-seeds it" 'grep -qF "  created    plans/BACKLOG.md" <<<"$out2"'
out3="$("$S" --check 2>&1)"; rc3=$?
check "6k. --check rc 0 after re-seed (got $rc3)" '[[ $rc3 -eq 0 ]]'

# ── 7. usage ──────────────────────────────────────────────────────────────────
"$S" --bogus >/dev/null 2>&1; rc=$?
check "7a. --bogus: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'

# ── 8. the real checkout's copies agree with its templates (read-only) ──────────
for f in gate.sh pr.sh worktree-setup.sh; do
  tver="$(tv "$AT/templates/plans/$f")"
  sver="$(tv "$AT/self/$f")"
  check "8. $f: template-version is a non-empty integer and self/$f matches (template=$tver self=$sver)" \
    '[[ "$tver" =~ ^[0-9]+$ ]] && [[ "$tver" == "$sver" ]]'
done

# ── 8b. one upstream URL across roots.py, update.sh and README.md (read-only) ────────
# The same string is written by hand in three places and all three comments say they move
# together; this is what enforces it. The failure mode is silent and is the one
# self-corpus-identity exists to stop: move the remote in update.sh and not in roots.py
# and every new --self ledger claim carries a `repo` matching none of the historical rows,
# so one feature deduplicates against nothing and is counted twice. Three literal sources,
# one check, no model and no network — the parse is a literal read of each file, never an
# import of the repo's own configuration through some other layer.
identity_expr='import sys; sys.path.insert(0, sys.argv[1]); import roots; print(roots.SELF_CORPUS_IDENTITY)'
roots_identity="$(python3 -c "$identity_expr" "$AT/analysis" 2>/dev/null)"
update_remote="$(sed -n 's/^DEFAULT_REMOTE="\(.*\)"$/\1/p' "$AT/update.sh" | head -n 1)"
check "8b. analysis/roots.py declares a non-empty SELF_CORPUS_IDENTITY (got '$roots_identity')" \
  '[[ -n "$roots_identity" ]]'
check "8c. update.sh's DEFAULT_REMOTE is the same string (got '$update_remote')" \
  '[[ -n "$update_remote" && "$update_remote" == "$roots_identity" ]]'
check "8d. the root README.md's git subtree commands name it too" \
  'grep -F "git subtree" "$AT/README.md" | grep -qF "$roots_identity"'

# ── Fixture B: a subtree cycle ───────────────────────────────────────────────────
UPSTREAM="$TMP/upstream.git"
WORK="$TMP/work"
CONSUMER2="$TMP/consumer2"

git init -q --bare "$UPSTREAM"
git clone -q "$UPSTREAM" "$WORK" 2>/dev/null
git -C "$WORK" symbolic-ref HEAD refs/heads/main
git -C "$WORK" config user.email test@example.invalid
git -C "$WORK" config user.name "sync-check test"
cp "$AT/sync-plans.sh" "$WORK/sync-plans.sh" 2>/dev/null || true
cp "$AT/update.sh" "$WORK/update.sh" 2>/dev/null || true
cp -r "$AT/templates" "$WORK/templates" 2>/dev/null || true
cp -r "$AT/hooks" "$WORK/hooks" 2>/dev/null || true
chmod +x "$WORK/sync-plans.sh" "$WORK/update.sh" 2>/dev/null || true
git -C "$WORK" add -A && git -C "$WORK" commit -q -m "upstream: sync-plans, update, templates"
git -C "$WORK" push -q origin main

mkdir -p "$CONSUMER2"
git -C "$CONSUMER2" init -q
git -C "$CONSUMER2" symbolic-ref HEAD refs/heads/main
git -C "$CONSUMER2" config user.email test@example.invalid
git -C "$CONSUMER2" config user.name "sync-check test"
echo "consumer2 root" > "$CONSUMER2/README.md"
git -C "$CONSUMER2" add -A && git -C "$CONSUMER2" commit -q -m "init"
git -C "$CONSUMER2" subtree add --prefix=agentTooling "$UPSTREAM" main --squash >/dev/null 2>&1
"$CONSUMER2/agentTooling/sync-plans.sh" >/dev/null 2>&1
echo "consumer2 fact" >> "$CONSUMER2/plans/PROJECT_FACTS.md"
git -C "$CONSUMER2" add -A && git -C "$CONSUMER2" commit -q -m "seed plans and fill facts"

echo "marker" > "$WORK/MARKER.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -q -m "add MARKER.txt"
git -C "$WORK" push -q origin main

# ── 9. a clean pull ────────────────────────────────────────────────────────────
out="$(cd "$CONSUMER2/plans" && ../agentTooling/update.sh --remote "$UPSTREAM" 2>&1)"; rc=$?
check "9a. update.sh --remote: rc 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "9b. MARKER.txt pulled in" '[[ -e "$CONSUMER2/agentTooling/MARKER.txt" ]]'
check "9c. output contains the pull line" 'grep -qF "  pull   agentTooling <- " <<<"$out"'
check "9d. output contains the sync line" 'grep -qF "  sync   agentTooling/sync-plans.sh" <<<"$out"'
subj="$(git -C "$CONSUMER2" log -1 --format=%s)"
check "9e. newest commit subject is a subtree merge or squash" '[[ "$subj" == "Merge commit"* || "$subj" == *"Squashed"* ]]'

# ── 10. a dirty tree refuses without pulling ─────────────────────────────────────
touch "$CONSUMER2/untracked.txt"
echo "marker2" > "$WORK/MARKER2.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -q -m "add MARKER2.txt"
git -C "$WORK" push -q origin main
out="$(cd "$CONSUMER2/plans" && ../agentTooling/update.sh --remote "$UPSTREAM" 2>&1)"; rc=$?
check "10a. update.sh --remote with a dirty tree: rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "10b. output names untracked.txt" 'grep -qF "untracked.txt" <<<"$out"'
check "10c. MARKER2.txt not pulled" '[[ ! -e "$CONSUMER2/agentTooling/MARKER2.txt" ]]'
rm -f "$CONSUMER2/untracked.txt"

# ── 11. run from the source checkout itself ──────────────────────────────────────
out="$("$WORK/update.sh" 2>&1)"; rc=$?
check "11a. update.sh from the source checkout: rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "11b. output mentions source checkout" 'grep -qF "source checkout" <<<"$out"'

# ── 12. usage ──────────────────────────────────────────────────────────────────
"$CONSUMER2/agentTooling/update.sh" --bogus >/dev/null 2>&1; rc=$?
check "12a. update.sh --bogus: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'

echo
if (( fails > 0 )); then echo "sync-check: $fails assertion(s) FAILED"; exit 1; fi
echo "sync-check: all assertions passed"
