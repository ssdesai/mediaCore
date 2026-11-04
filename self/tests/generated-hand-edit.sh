#!/usr/bin/env bash
set -uo pipefail

# Self-test for sync-plans.sh telling a hand edit of a generated stub from an upstream
# template change (self/features/generated-readme-repo-owned/). Run by self/gate.sh, or by
# hand: bash self/tests/generated-hand-edit.sh
#
# Each fixture is a throwaway consuming repo holding copies of the real sync-plans.sh,
# templates/, hooks/ and env-profile.sh under a prefix, committed, synced and committed
# again — the state a pull leaves. A stub byte-identical to a template version the repo
# once committed is an upstream change (STALE under --check, "synced … (template changed
# upstream)" on the write path, no extra item); one matching none is a hand edit (EDITED
# under --check, OVERWROTE on the write path, an item, with the lines it drops printed);
# with no history to ask, it is reported like an edit, never assumed upstream.
#
#   1. one upstream template change: STALE, no dropped lines, write path rc 0
#   2. a stub three template versions behind is still upstream
#   3. a committed hand edit (humanNetworkMap's taxonomy-migration/ entry): EDITED with the
#      line, --check writes nothing; OVERWROTE with the line, rc 1, file = template
#   4. a hand edit on top of a stale stub, uncommitted: EDITED, and the dropped lines are
#      the stub's own, never the template's new ones
#   5. a stub in a subdirectory (features/README.md)
#   6. a hand edit that only deletes lines: EDITED, nothing dropped, write path rc 0
#   7. a prefix other than agentTooling
#   8. no git at all: STALE naming why, with the dropped lines; OVERWROTE on write
#   9. a shallow clone missing the version the stub came from: unknown, never "edited"
#  10. a real `git subtree add/pull --squash` cycle: the pulled change is upstream, and a
#      hand edit made before the next pull is still EDITED after it
#
# No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
unset GATE_RESUME

# The repo-specific entry humanNetworkMap hand-added to its generated plans/README.md.
HAND_LINE='- `taxonomy-migration/` — this repo'"'"'s own entry, hand-added'
UPSTREAM_LINE='upstream template line'
# sync-plans.sh's own STATUS_COL_WIDTH and DROPPED_LINE_PREFIX.
STATUS_COL_WIDTH=11
DROPPED_LINE_PREFIX="| "

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# status <word> <rest> — a status line exactly as sync-plans.sh prints it.
status() { printf "  %-${STATUS_COL_WIDTH}s%s" "$1" "$2"; }
# dropped <line> — a dropped line exactly as sync-plans.sh prints it.
dropped() { printf "  %-${STATUS_COL_WIDTH}s%s" "" "$DROPPED_LINE_PREFIX$1"; }

git_id() {
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name "generated-hand-edit test"
}

# commit_all <repo> <msg>
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# vendor_into <dir> — the four things sync-plans.sh needs, at <dir>.
vendor_into() {
  mkdir -p "$1"
  cp "$AT/sync-plans.sh" "$1/sync-plans.sh"
  cp -r "$AT/templates" "$1/templates"
  cp -r "$AT/hooks" "$1/hooks"
  cp "$AT/env-profile.sh" "$1/env-profile.sh"
  chmod +x "$1/sync-plans.sh"
}

# make_consumer <repo> <prefix> — vendored, committed, synced, facts filled, committed.
make_consumer() {
  local repo="$1" prefix="$2"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  git_id "$repo"
  vendor_into "$repo/$prefix"
  commit_all "$repo" "vendor"
  "$repo/$prefix/sync-plans.sh" >/dev/null 2>&1
  echo "a filled fact" >> "$repo/plans/PROJECT_FACTS.md"
  commit_all "$repo" "seed plans"
}

# bump_template <repo> <prefix> <rel> <line> — an upstream change to one template, committed.
bump_template() {
  echo "$4" >> "$1/$2/templates/plans/$3"
  commit_all "$1" "pull: $4"
}

echo "generated-hand-edit"

# ── 1. one upstream template change ─────────────────────────────────────────────
C1="$TMP/c1"
make_consumer "$C1" agentTooling
S1="$C1/agentTooling/sync-plans.sh"
bump_template "$C1" agentTooling README.md "$UPSTREAM_LINE 1"
out="$("$S1" --check 2>&1)"; rc=$?
check "1a. --check rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "1b. STALE, unedited" 'grep -qxF "$(status STALE "plans/README.md (an earlier template'"'"'s copy, unedited; run sync-plans.sh)")" <<<"$out"'
check "1c. no EDITED line and no dropped lines" '! grep -q "EDITED" <<<"$out" && ! grep -qF "$DROPPED_LINE_PREFIX" <<<"$out"'
out="$("$S1" 2>&1)"; rc=$?
check "1d. write path rc 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "1e. synced, template changed upstream" 'grep -qxF "$(status synced "plans/README.md (template changed upstream)")" <<<"$out"'
check "1f. the stub is the new template" 'cmp -s "$C1/agentTooling/templates/plans/README.md" "$C1/plans/README.md"'
commit_all "$C1" "sync"

# ── 2. three template versions behind is still upstream ─────────────────────────
for v in 2 3 4; do bump_template "$C1" agentTooling README.md "$UPSTREAM_LINE $v"; done
out="$("$S1" --check 2>&1)"
check "2a. STALE, unedited, three versions behind" 'grep -qxF "$(status STALE "plans/README.md (an earlier template'"'"'s copy, unedited; run sync-plans.sh)")" <<<"$out"'
out="$("$S1" 2>&1)"; rc=$?
check "2b. write path rc 0 (got $rc)" '[[ $rc -eq 0 ]]'
commit_all "$C1" "sync"

# ── 3. a committed hand edit ────────────────────────────────────────────────────
echo "$HAND_LINE" >> "$C1/plans/README.md"
commit_all "$C1" "hand edit"
cp "$C1/plans/README.md" "$TMP/readme.before"
out="$("$S1" --check 2>&1)"; rc=$?
check "3a. --check rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "3b. EDITED, one line to move" 'grep -qxF "$(status EDITED "plans/README.md (hand-edited; sync-plans.sh would drop the 1 line(s) below — move them to plans/PROJECT_FACTS.md first)")" <<<"$out"'
check "3c. ...followed by the line itself" '[[ "$out" == *"$(status EDITED "plans/README.md (")"*$'"'"'\n'"'"'"$(dropped "$HAND_LINE")"* ]]'
check "3d. never called STALE" '! grep -q "STALE      plans/README.md" <<<"$out"'
check "3e. --check wrote nothing" 'cmp -s "$TMP/readme.before" "$C1/plans/README.md"'
out="$("$S1" 2>&1)"; rc=$?
check "3f. write path rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "3g. OVERWROTE, naming PROJECT_FACTS.md" 'grep -qxF "$(status OVERWROTE "plans/README.md (hand-edited; dropped the 1 line(s) below — they belong in plans/PROJECT_FACTS.md, and git has them only if they were committed)")" <<<"$out"'
check "3h. ...followed by the line" 'grep -qxF "$(dropped "$HAND_LINE")" <<<"$out"'
check "3i. needs attention: 1 item(s)" '[[ "$(tail -1 <<<"$out")" == "needs attention: 1 item(s) above." ]]'
check "3j. the stub is the template again" 'cmp -s "$C1/agentTooling/templates/plans/README.md" "$C1/plans/README.md"'
check "3k. git diff still holds the committed line" 'git -C "$C1" diff -- plans/README.md | grep -qxF -- "-$HAND_LINE"'
out="$("$S1" --check 2>&1)"; rc=$?
check "3l. --check rc 0 afterwards (got $rc)" '[[ $rc -eq 0 ]]'
commit_all "$C1" "sync"

# ── 4. a hand edit on a stale stub, uncommitted ─────────────────────────────────
bump_template "$C1" agentTooling README.md "$UPSTREAM_LINE 5"
echo "$HAND_LINE" >> "$C1/plans/README.md"
out="$("$S1" --check 2>&1)"
check "4a. EDITED, one line" 'grep -qxF "$(status EDITED "plans/README.md (hand-edited; sync-plans.sh would drop the 1 line(s) below — move them to plans/PROJECT_FACTS.md first)")" <<<"$out"'
check "4b. the hand line is printed" 'grep -qxF "$(dropped "$HAND_LINE")" <<<"$out"'
check "4c. the template's new line is not" '! grep -qF "$DROPPED_LINE_PREFIX$UPSTREAM_LINE 5" <<<"$out"'
"$S1" >/dev/null 2>&1
commit_all "$C1" "sync"

# ── 5. a stub in a subdirectory ─────────────────────────────────────────────────
echo "$HAND_LINE" >> "$C1/plans/features/README.md"
out="$("$S1" --check 2>&1)"
check "5a. EDITED plans/features/README.md" 'grep -qF "$(status EDITED "plans/features/README.md (hand-edited; sync-plans.sh would drop the 1 line(s)")" <<<"$out"'
check "5b. plans/README.md still in-sync" 'grep -qxF "$(status in-sync plans/README.md)" <<<"$out"'
"$S1" >/dev/null 2>&1

# ── 6. a hand edit that only deletes ────────────────────────────────────────────
sed '1d' "$C1/plans/README.md" > "$TMP/readme.cut"
cp "$TMP/readme.cut" "$C1/plans/README.md"
out="$("$S1" --check 2>&1)"; rc=$?
check "6a. --check rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "6b. EDITED, adding nothing" 'grep -qxF "$(status EDITED "plans/README.md (hand-edited, adding nothing the template lacks; run sync-plans.sh to restore it)")" <<<"$out"'
out="$("$S1" 2>&1)"; rc=$?
check "6c. write path rc 0 — nothing was lost (got $rc)" '[[ $rc -eq 0 ]]'
check "6d. synced, restored" 'grep -qxF "$(status synced "plans/README.md (restored the template'"'"'s lines; it held none of its own)")" <<<"$out"'

# ── 7. a prefix other than agentTooling ─────────────────────────────────────────
C7="$TMP/c7"
make_consumer "$C7" tooling
S7="$C7/tooling/sync-plans.sh"
bump_template "$C7" tooling .gitignore "# $UPSTREAM_LINE"
out="$("$S7" --check 2>&1)"
check "7a. upstream under prefix tooling/: STALE, unedited" 'grep -qxF "$(status STALE "plans/.gitignore (an earlier template'"'"'s copy, unedited; run sync-plans.sh)")" <<<"$out"'
"$S7" >/dev/null 2>&1
echo "$HAND_LINE" >> "$C7/plans/.gitignore"
out="$("$S7" --check 2>&1)"
check "7b. hand edit under prefix tooling/: EDITED" 'grep -qF "$(status EDITED "plans/.gitignore (hand-edited;")" <<<"$out"'

# ── 8. no git at all ────────────────────────────────────────────────────────────
C8="$TMP/c8"
cp -r "$C1" "$C8"
rm -rf "$C8/.git"
S8="$C8/agentTooling/sync-plans.sh"
echo "$HAND_LINE" >> "$C8/plans/README.md"
out="$("$S8" --check 2>&1)"; rc=$?
check "8a. --check rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "8b. STALE, saying why it cannot tell" 'grep -qxF "$(status STALE "plans/README.md (differs from templates/plans/README.md; no git history of the vendored templates to compare it with, so it may be a hand edit — sync-plans.sh would drop the 1 line(s) below)")" <<<"$out"'
check "8c. ...with the line" 'grep -qxF "$(dropped "$HAND_LINE")" <<<"$out"'
out="$("$S8" 2>&1)"; rc=$?
check "8d. write path rc 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "8e. OVERWROTE, saying why" 'grep -qxF "$(status OVERWROTE "plans/README.md (no git history of the vendored templates to compare it with, so it may have been a hand edit; dropped the 1 line(s) below — move any of this repo'"'"'s own to plans/PROJECT_FACTS.md)")" <<<"$out"'
check "8f. ...with the line" 'grep -qxF "$(dropped "$HAND_LINE")" <<<"$out"'

# ── 9. a shallow clone missing the version the stub came from ───────────────────
C9SRC="$TMP/c9src"
make_consumer "$C9SRC" agentTooling
bump_template "$C9SRC" agentTooling README.md "$UPSTREAM_LINE shallow"
C9="$TMP/c9"
git clone -q --depth 1 "file://$C9SRC" "$C9" 2>/dev/null
out="$("$C9/agentTooling/sync-plans.sh" --check 2>&1)"
check "9a. the clone is shallow" '[[ "$(git -C "$C9" rev-parse --is-shallow-repository)" == true ]]'
check "9b. STALE, naming the shallow clone, never EDITED" 'grep -qF "$(status STALE "plans/README.md (differs from templates/plans/README.md; this clone is shallow")" <<<"$out" && ! grep -q EDITED <<<"$out"'

# ── 10. a real squashed subtree cycle ───────────────────────────────────────────
UP="$TMP/upstream.git"
WORK="$TMP/work"
git init -q --bare "$UP"
git -C "$UP" symbolic-ref HEAD refs/heads/main
git clone -q "$UP" "$WORK" 2>/dev/null
git -C "$WORK" symbolic-ref HEAD refs/heads/main
git_id "$WORK"
vendor_into "$WORK"
commit_all "$WORK" "upstream v1"
git -C "$WORK" push -q origin main 2>/dev/null
C10="$TMP/c10"
mkdir -p "$C10"
git -C "$C10" init -q
git -C "$C10" symbolic-ref HEAD refs/heads/main
git_id "$C10"
echo "consumer" > "$C10/README.md"
commit_all "$C10" "init"
git -C "$C10" subtree add -q --prefix=agentTooling "$UP" main --squash >/dev/null 2>&1
"$C10/agentTooling/sync-plans.sh" >/dev/null 2>&1
echo "a filled fact" >> "$C10/plans/PROJECT_FACTS.md"
commit_all "$C10" "seed plans"
echo "$UPSTREAM_LINE subtree" >> "$WORK/templates/plans/README.md"
commit_all "$WORK" "upstream v2"
git -C "$WORK" push -q origin main 2>/dev/null
git -C "$C10" subtree pull -q --prefix=agentTooling "$UP" main --squash -m "pull v2" >/dev/null 2>&1
check "10a. the pull brought the new template in" 'grep -qxF "$UPSTREAM_LINE subtree" "$C10/agentTooling/templates/plans/README.md"'
out="$("$C10/agentTooling/sync-plans.sh" --check 2>&1)"
check "10b. after a squashed pull: STALE, unedited" 'grep -qxF "$(status STALE "plans/README.md (an earlier template'"'"'s copy, unedited; run sync-plans.sh)")" <<<"$out"'
"$C10/agentTooling/sync-plans.sh" >/dev/null 2>&1
echo "$HAND_LINE" >> "$C10/plans/README.md"
commit_all "$C10" "sync, and a hand edit"
echo "$UPSTREAM_LINE subtree 3" >> "$WORK/templates/plans/README.md"
commit_all "$WORK" "upstream v3"
git -C "$WORK" push -q origin main 2>/dev/null
git -C "$C10" subtree pull -q --prefix=agentTooling "$UP" main --squash -m "pull v3" >/dev/null 2>&1
out="$("$C10/agentTooling/sync-plans.sh" --check 2>&1)"
check "10c. a hand edit across a squashed pull: EDITED with the line" \
  'grep -qF "$(status EDITED "plans/README.md (hand-edited;")" <<<"$out" && grep -qxF "$(dropped "$HAND_LINE")" <<<"$out"'

echo
if (( fails > 0 )); then echo "generated-hand-edit: $fails assertion(s) FAILED"; exit 1; fi
echo "generated-hand-edit: all assertions passed"
