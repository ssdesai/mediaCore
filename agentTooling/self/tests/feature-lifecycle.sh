#!/usr/bin/env bash
set -uo pipefail

# Self-test for the feature lifecycle scripts (LIFECYCLE.md;
# self/features/feature-lifecycle/README.md items 9–13). Run by self/gate.sh, or by
# hand: bash self/tests/feature-lifecycle.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d that is a real git repo with
# a bare `origin` beside it — the real feature-start.sh, feature-close.sh, run-review.sh,
# plan-runner-{lib,roots}.sh, self/pr.sh and analysis/*.py, plus a stub gate, a stub hook,
# a stub `claude` and a stub `gh` on PATH — and drives the whole loop with --self: start
# a feature, refuse its stub brief, review it, open its PR, merge it, close it. Under a
# redirected $HOME it synthesizes the transcripts close captures. No model, no network;
# a few seconds.
#
# The rule under test, for slug S and primary checkout R: branch S, worktree
# R/.worktrees/S — inside the primary, kept out of git by the common git dir's
# info/exclude — and every session a feature costs is launched in that worktree or in R
# and pinned by id. A feature started under the old layout keeps its sibling R-S (L).
#
# Asserts, in order:
#   S1. feature-start.sh --self S creates branch S and worktree R/.worktrees/S off
#       origin/main (nothing at the legacy R-S), leaves the primary on main and clean —
#       `git status --porcelain` empty with the worktree nested inside it, because
#       info/exclude now carries `/.worktrees/` exactly once and every entry it already
#       held, an unterminated last line included, is intact — writes the manifest
#       (branches [S], base main, `from` in UTC with a Z, `to` null, the running session
#       pinned from $CLAUDE_CODE_SESSION_ID), a review stub carrying @@TODO@@ numbered
#       next in the global sequence, commits `S: start`, ran the hook and the gate inside
#       the worktree, and prints the worktree path and the `feature: <repo>/S` line;
#   S2. it refuses a slug that fails the pattern, a slug whose branch exists, a slug
#       whose worktree path is already taken, and being run from a worktree's copy —
#       creating nothing in each case;
#   S3. --no-pin, --session, an unset environment, --method, --base, --no-gate, and a
#       red gate (refuses, worktree left in place, no manifest); and after seven more
#       starts the exclude entry is still there exactly once;
#   T1. run-review.sh files a brief whose line begins with @@TODO@@ to failed/ without
#       calling claude, and runs one that merely mentions the marker mid-sentence;
#   T2. a real brief runs, and on the clean pass the PR hook pushes S itself and calls
#       `pr create --base main --head S` — no review/ branch anywhere;
#   P1. pr.sh honours FEATURE_BASE, refuses on the base branch, and the template and
#       self/pr.sh carry the same logic below their REPO-SPECIFIC line;
#   C1. feature-close.sh refuses from a worktree, refuses an unmerged branch, and
#       refuses a dirty primary;
#   C2. an unclaimed delegate whose brief names this feature stops the close, and a
#       pin lets it through, while one briefed for `S-two` is never this feature's stray;
#   C3. a close captures the session launched in R-S by branch and the pinned session by
#       id (selected_by, cwd recorded), carries home the trailing timing stamps the review
#       pass wrote after the PR hook committed — `pr_opened`, with its URL, and `pass_end`
#       — stamps `to`, commits exactly the cost files as `S: cost records`, pushes main,
#       removes the worktree and the branch, and prints one `pinned` line instead of
#       telling the human to pin a delegate the manifest already pins
#       (self/features/recovered-duration-lower-bound/README.md, item 2);
#   C4. --keep-worktree --no-push keeps both, pushes nothing, and carries no line twice;
#   C5. a close that matches nothing writes nothing, stamps nothing, rolls its timing
#       carry back and so leaves the primary clean and re-runnable;
#   L.  a feature whose worktree is the legacy sibling R-S — the shape every feature
#       started before worktrees moved inside the primary still has — closes: the session
#       launched in R-S is claimed by branch, the worktree's trailing timing stamp is
#       carried home, the worktree and branch are removed, and a --recapture after that
#       still claims the session from the path it no longer finds on disk;
#   W1. a close whose only branch session ended hours ago stamps session_window.to one
#       second after the last instant of that session AND of its delegate, whichever ran
#       later, not at its own wall clock — and at second resolution, though the evidence
#       carried milliseconds;
#   W2. a feature with no branch session at all — only a pinned session off the branch —
#       stamps `to` at close time and says so in one line;
#   W3. --recapture over a `to` later than the evidence tightens it, printing old -> new;
#   W4. manifest.py set-window-to --tighten refuses a LATER instant with its own exit
#       code 3, naming both bounds and leaving the fence byte-identical, while the bound
#       it already carries is a no-op rather than a refusal; and it refuses a bound at or
#       before the fence's `from` — an empty window — as a plain exit 1;
#   W5. a close whose stamp fails for any reason but that refused widen refuses, names
#       what set-window-to printed, captures nothing and rolls its timing carry back;
#   W6. while a --recapture whose evidence would WIDEN the bound warns, captures anyway
#       and leaves the published bound untouched — the one code the close continues past,
#       which is written down in both scripts and so needs an assertion of its own.
#
# All RED until the scripts landed. A missing script fails its assertions loudly rather
# than aborting the run (no `set -e`; every cp below tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
ORIGIN="$TMP/origin.git"
mkdir -p "$AT/analysis" "$AT/self/features/old/review/complete" "$AT/templates/plans/features" "$TMP/bin"

for f in feature-start.sh feature-close.sh plan-runner-roots.sh plan-runner-lib.sh run-review.sh stamp-timing.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
for f in pricing.py roots.py transcript.py capture_planning.py report.py manifest.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md"
cp "$HERE/self/pr.sh" "$AT/self/pr.sh" 2>/dev/null || true
chmod +x "$AT"/*.sh "$AT/self/pr.sh" 2>/dev/null || true
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

# Stub hook: records the directory it ran in, outside the tree so nothing sweeps it up.
cat > "$AT/self/worktree-setup.sh" <<'STUB'
#!/usr/bin/env bash
pwd > "${HOOK_CWD_OUT:?}"
exit "${HOOK_STUB_RC:-0}"
STUB
# Stub gate: the real contract — exit 0, verdict in the report's last section.
cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$HERE/self/gate-report.txt"
{ echo "# Gate report"; echo ""; echo "# VERDICT"; echo "${GATE_STUB_VERDICT:-all checks passed}"; } > "$REPORT"
exit 0
STUB
# Stub claude: one result event; records that it was called.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
touch "${CLAUDE_CALLED_OUT:-/dev/null}"
printf '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"session_id":"stub","usage":{}}\n'
exit 0
STUB
# Stub gh: logs every argv line; no PR is ever already open.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_LOG:?}"
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view")     exit 1 ;;
  "pr create")   echo "https://example.invalid/pr/1"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$AT/self/worktree-setup.sh" "$AT/self/gate.sh" "$TMP/bin/claude" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"
export HOOK_CWD_OUT="$TMP/hook-cwd"
export CLAUDE_CALLED_OUT="$TMP/claude-called"

printf 'self/gate-report*.txt\nself/review-report.md\n' > "$AT/.gitignore"
echo "an older review plan, so the global sequence has something to continue" > "$AT/self/features/old/review/complete/07-review-opus.md"
printf '# old\n\n```json\n{"slug": "old", "plans": ["07-review-opus"], "branches": ["old"]}\n```\n' > "$AT/self/features/old/README.md"

git -C "$AT" init -q
git -C "$AT" symbolic-ref HEAD refs/heads/main
git -C "$AT" config user.email test@example.invalid
git -C "$AT" config user.name "lifecycle test"
git -C "$AT" add -A && git -C "$AT" commit -q -m "init"
git init -q --bare "$ORIGIN"
git -C "$AT" remote add origin "$ORIGIN"
git -C "$AT" push -q -u origin main 2>/dev/null
git -C "$AT" branch other && git -C "$AT" push -q origin other 2>/dev/null

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
# Claude Code's project directory for a launch cwd: every `/` and `.` becomes `-`, so the
# worktree R/.worktrees/S is filed under …-R--worktrees-S.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/.' '--')"; }
# The layout under test: a feature's worktree is R/.worktrees/<slug>.
WORKTREES_DIR=".worktrees"
wt_path() { echo "$AT/$WORKTREES_DIR/$1"; }
EXCLUDE="$AT/.git/info/exclude"
exclude_count() { grep -cxF "/$WORKTREES_DIR/" "$EXCLUDE" 2>/dev/null; }
# An entry of the repo's own, written with no trailing newline: the start must neither
# drop it nor glue its own entry onto the end of it.
KEEP_ENTRY="keep-me-entry"
mkdir -p "$(dirname "$EXCLUDE")"
printf '%s' "$KEEP_ENTRY" >> "$EXCLUDE"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# fence <readme> <python expr over d> — a field of the manifest's last json fence.
fence() {
  python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
start() { ( cd "$TMP" && "$AT/feature-start.sh" --self "$@" 2>&1 ); }
close() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT/feature-close.sh" --self "$@" 2>&1 ); }
branches() { git -C "$AT" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' '; }
now_z() { date -u '+%Y-%m-%dT%H:%M:%S.000Z'; }

PIN="pinpinpi-0000-0000-0000-000000000001"
MODEL="claude-sonnet-5"
export CLAUDE_CODE_SESSION_ID="$PIN"

echo "feature lifecycle"

# ── S1. a plain start ─────────────────────────────────────────────────────────
SLUG="lifecycle-one"
WT="$(wt_path "$SLUG")"
FD="$WT/self/features/$SLUG"
out="$(start "$SLUG")"; rc=$?
check "S1a. feature-start.sh exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "S1b. worktree R-S exists on branch S" '[[ -d "$WT" && "$(git -C "$WT" branch --show-current 2>/dev/null)" == "$SLUG" ]]'
check "S1c. the primary is still on main and clean" '[[ "$(git -C "$AT" branch --show-current)" == "main" && -z "$(git -C "$AT" status --porcelain)" ]]'
check "S1d. S branched from origin/main" '[[ "$(git -C "$WT" rev-parse HEAD~1 2>/dev/null)" == "$(git -C "$AT" rev-parse origin/main)" ]]'
check "S1e. manifest: slug, branches [S], base main" '[[ "$(fence "$FD/README.md" "d[\"slug\"]")" == "$SLUG" && "$(fence "$FD/README.md" "d[\"branches\"]")" == "['"'"'$SLUG'"'"']" && "$(fence "$FD/README.md" "d[\"base\"]")" == "main" ]]'
check "S1f. manifest: method direct by default, review stub in plans" '[[ "$(fence "$FD/README.md" "d[\"method\"]")" == "direct" && "$(fence "$FD/README.md" "d[\"plans\"]")" == "['"'"'08-review-opus'"'"']" ]]'
check "S1g. manifest: from ends in Z, to is null" '[[ "$(fence "$FD/README.md" "d[\"session_window\"][\"from\"]")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$(fence "$FD/README.md" "d[\"session_window\"][\"to\"]")" == "None" ]]'
check "S1h. manifest: the running session is pinned, subagents empty" '[[ "$(fence "$FD/README.md" "d[\"sessions\"]")" == "['"'"'$PIN'"'"']" && "$(fence "$FD/README.md" "d[\"subagents\"]")" == "[]" ]]'
check "S1i. review stub numbered next in the global sequence, carrying @@TODO@@" '[[ -f "$FD/review/incomplete/08-review-opus.md" ]] && grep -q "@@TODO@@" "$FD/review/incomplete/08-review-opus.md"'
check "S1j. first commit is 'S: start' and the worktree is clean" '[[ "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: start" && -z "$(git -C "$WT" status --porcelain)" ]]'
check "S1k. the hook ran inside the worktree" '[[ "$(cat "$HOOK_CWD_OUT" 2>/dev/null)" == "$WT" ]]'
check "S1l. the gate ran inside the worktree" '[[ -f "$WT/self/gate-report.txt" ]]'
check "S1m. output names the worktree and the feature line" 'grep -q "cd $WT" <<<"$out" && grep -q "feature: agentTooling/$SLUG" <<<"$out"'
check "S1n. output says the stub brief must be replaced" 'grep -q "@@TODO@@" <<<"$out"'
check "S1o. the worktree is inside the primary at R/$WORKTREES_DIR/S, and nothing is at the legacy R-S" '[[ -d "$WT" && ! -e "$AT-$SLUG" ]]'
check "S1p. info/exclude carries /$WORKTREES_DIR/ exactly once (got $(exclude_count))" '[[ "$(exclude_count)" == "1" ]]'
check "S1q. ... and the entry it already held, unterminated, is intact on a line of its own" 'grep -qxF "$KEEP_ENTRY" "$EXCLUDE"'
check "S1r. nothing tracked was touched to ignore it" '[[ -z "$(git -C "$AT" diff HEAD --name-only)" ]]'

# ── S2. refusals create nothing ───────────────────────────────────────────────
before="$(branches)"
for bad in "Bad_Slug" "review/x" "-lead" "trail-" "two--dashes"; do
  start "$bad" >/dev/null 2>&1; rc=$?
  check "S2a. slug '$bad' is refused (got $rc)" '[[ $rc -ne 0 ]]'
done
check "S2b. no branch and no worktree was created for any of them" '[[ "$(branches)" == "$before" && ! -e "$(wt_path Bad_Slug)" && ! -e "$(wt_path review/x)" ]]'
start "$SLUG" >/dev/null 2>&1; rc=$?
check "S2c. a slug whose branch exists is refused (got $rc)" '[[ $rc -ne 0 ]]'
( cd "$TMP" && "$WT/feature-start.sh" --self another >/dev/null 2>&1 ); rc=$?
check "S2d. the copy inside a worktree refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "S2e. ... and created nothing" '[[ ! -e "$WT/$WORKTREES_DIR/another" && ! -e "$(wt_path another)" && "$(branches)" == "$before" ]]'
mkdir -p "$(wt_path lifecycle-occupied)"
start lifecycle-occupied --no-gate >/dev/null 2>&1; rc=$?
check "S2f. a slug whose worktree path is already taken is refused, creating no branch (got $rc)" '[[ $rc -ne 0 && "$(branches)" == "$before" ]]'
rmdir "$(wt_path lifecycle-occupied)"

# ── S3. options ───────────────────────────────────────────────────────────────
start lifecycle-nopin --no-pin --no-gate >/dev/null 2>&1
check "S3a. --no-pin leaves sessions empty" '[[ "$(fence "$(wt_path lifecycle-nopin)/self/features/lifecycle-nopin/README.md" "d[\"sessions\"]")" == "[]" ]]'
start lifecycle-sess --session abc-123 --no-gate >/dev/null 2>&1
check "S3b. --session pins the id given" '[[ "$(fence "$(wt_path lifecycle-sess)/self/features/lifecycle-sess/README.md" "d[\"sessions\"]")" == "['"'"'abc-123'"'"']" ]]'
( cd "$TMP" && env -u CLAUDE_CODE_SESSION_ID "$AT/feature-start.sh" --self lifecycle-noenv --no-gate >/dev/null 2>&1 )
check "S3c. no session id in the environment means no pin" '[[ "$(fence "$(wt_path lifecycle-noenv)/self/features/lifecycle-noenv/README.md" "d[\"sessions\"]")" == "[]" ]]'
start lifecycle-hand --method hand --no-gate >/dev/null 2>&1
check "S3d. --method hand is recorded" '[[ "$(fence "$(wt_path lifecycle-hand)/self/features/lifecycle-hand/README.md" "d[\"method\"]")" == "hand" ]]'
start lifecycle-bad-method --method nope --no-gate >/dev/null 2>&1; rc=$?
check "S3e. an unknown --method is refused (got $rc)" '[[ $rc -ne 0 && ! -e "$(wt_path lifecycle-bad-method)" ]]'
start lifecycle-based --base other --no-gate >/dev/null 2>&1
check "S3f. --base other branches from origin/other" '[[ "$(git -C "$(wt_path lifecycle-based)" rev-parse HEAD~1 2>/dev/null)" == "$(git -C "$AT" rev-parse origin/other)" ]]'
check "S3g. ... and records base other" '[[ "$(fence "$(wt_path lifecycle-based)/self/features/lifecycle-based/README.md" "d[\"base\"]")" == "other" ]]'
check "S3h. --no-gate ran no gate" '[[ ! -f "$(wt_path lifecycle-based)/self/gate-report.txt" ]]'
GATE_STUB_VERDICT="one or more checks FAILED" start lifecycle-red >/dev/null 2>&1; rc=$?
check "S3i. a red gate refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "S3j. ... leaving the worktree in place and writing no manifest" '[[ -d "$(wt_path lifecycle-red)" && ! -e "$(wt_path lifecycle-red)/self/features/lifecycle-red" ]]'
HOOK_STUB_RC=3 start lifecycle-hookfail --no-gate >/dev/null 2>&1; rc=$?
check "S3k. a failing hook refuses, worktree left for inspection (got $rc)" '[[ $rc -ne 0 && -d "$(wt_path lifecycle-hookfail)" && ! -e "$(wt_path lifecycle-hookfail)/self/features/lifecycle-hookfail" ]]'
check "S3l. after every start above, info/exclude still carries /$WORKTREES_DIR/ exactly once (got $(exclude_count))" '[[ "$(exclude_count)" == "1" ]] && grep -qxF "$KEEP_ENTRY" "$EXCLUDE"'
check "S3m. ... and the primary is still clean with all of them nested inside it" '[[ -z "$(git -C "$AT" status --porcelain)" ]]'

# ── T1. a stub brief cannot run ───────────────────────────────────────────────
rm -f "$CLAUDE_CALLED_OUT"
( cd "$WT" && ./run-review.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "T1a. run-review.sh over a @@TODO@@ brief exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "T1b. the brief is filed to failed/" '[[ -f "$FD/review/failed/08-review-opus.md" ]]'
check "T1c. its progress log names the marker" 'grep -q "@@TODO@@" "$FD/review/failed/08-review-opus.progress.md" 2>/dev/null'
check "T1d. claude was never called" '[[ ! -e "$CLAUDE_CALLED_OUT" ]]'
check "T1e. no PR hook ran" '! grep -q "pr create" "$GH_LOG"'

# A brief that merely MENTIONS the marker — "replace `@@TODO@@` before the pass" — is not a
# stub. The refusal is anchored to a line that begins with it, which is how the stub is
# written; this feature's own review brief mentioned it mid-sentence and was refused.
printf '# 08 — review\n\nThe start script leaves a stub carrying `@@TODO@@`; hold the diff to the manifest.\n' > "$FD/review/failed/08-review-opus.md"
git -C "$WT" mv -q "$FD/review/failed/08-review-opus.md" "$FD/review/incomplete/08-review-opus.md" 2>/dev/null \
  || mv "$FD/review/failed/08-review-opus.md" "$FD/review/incomplete/08-review-opus.md"
rm -f "$FD/review/failed/08-review-opus.progress.md"
rm -f "$CLAUDE_CALLED_OUT"
( cd "$WT" && ./run-review.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "T1f. a brief that mentions the marker mid-line is not a stub: it runs (got $rc)" '[[ $rc -eq 0 && -e "$CLAUDE_CALLED_OUT" ]]'
# That pass was only about the refusal. Its clean run fired the PR hook and left its own
# trailing `pr_opened`/`pass_end` stamps uncommitted in the worktree; discard them, or
# they double the pr_opened count C3l pins — and, when two stamps land in the same
# second, collide with the carry's exact-line dedupe and hide T2's from the cost commit.
git -C "$WT" checkout -q -- "self/features/$SLUG/timing.jsonl"
: > "$GH_LOG"

# ── T2. a real brief runs, and the PR hook opens from S ───────────────────────
# T1f's pass filed the brief to complete/; re-queue a fresh one for the PR-hook phase.
rm -f "$FD/review/complete/08-review-opus"*
printf '# 08 — review\n\nA real brief. Hold the diff to the manifest.\n' > "$FD/review/incomplete/08-review-opus.md"
git -C "$WT" add -A && git -C "$WT" commit -q -m "$SLUG: review brief"
echo "a review-pass fix" > "$WT/fixed-by-review.txt"
before="$(branches)"
( cd "$WT" && ./run-review.sh --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "T2a. a real brief runs clean (got $rc)" '[[ $rc -eq 0 && -e "$CLAUDE_CALLED_OUT" ]]'
check "T2b. no branch was created — S is the head" '[[ "$(branches)" == "$before" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/review/$SLUG"'
# The pass's own closing stamps — `pr_opened`, carrying the PR URL, then `pass_end` from
# plan-runner-lib.sh's EXIT trap — are written after the hook has committed, so
# timing.jsonl is the one file a green pass leaves modified. That is the record's last
# word, not litter: feature-close.sh carries it home (C3l) rather than discarding it.
check "T2c. the review pass's edit was committed on S, and only its closing stamps are left" 'git -C "$WT" log -1 --format=%s | grep -q "$SLUG" && git -C "$WT" show --name-only --format= HEAD | grep -qx "fixed-by-review.txt" && [[ "$(git -C "$WT" status --porcelain)" == " M self/features/$SLUG/timing.jsonl" ]] && git -C "$WT" diff -- "self/features/$SLUG/timing.jsonl" | grep -q "\"event\":\"pr_opened\""'
check "T2d. S was pushed" '[[ "$(git -C "$AT" rev-parse "refs/remotes/origin/$SLUG" 2>/dev/null)" == "$(git -C "$WT" rev-parse HEAD)" ]]'
check "T2e. pr create --base main --head S" 'grep -q -- "pr create --base main --head $SLUG" "$GH_LOG"'

# ── P1. pr.sh on its own ──────────────────────────────────────────────────────
: > "$GH_LOG"
( cd "$(wt_path lifecycle-based)" && echo x > dirty.txt && FEATURE_BASE=other ./self/pr.sh lifecycle-based >/dev/null 2>&1 ); rc=$?
check "P1a. FEATURE_BASE names the PR base (got $rc)" '[[ $rc -eq 0 ]] && grep -q -- "pr create --base other --head lifecycle-based" "$GH_LOG"'
: > "$GH_LOG"
head_before="$(git -C "$AT" rev-parse HEAD)"
( cd "$AT" && echo y > dirty-main.txt && ./self/pr.sh nothing >/dev/null 2>&1 ); rc=$?
check "P1b. on the base branch pr.sh refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "P1c. ... committing nothing and opening nothing" '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" ]] && ! grep -q "pr create" "$GH_LOG"'
rm -f "$AT/dirty-main.txt"
check "P1d. templates/plans/pr.sh and self/pr.sh carry the same logic" 'diff -q <(sed -n "/REPO-SPECIFIC/,\$p" "$HERE/templates/plans/pr.sh") <(sed -n "/REPO-SPECIFIC/,\$p" "$HERE/self/pr.sh") >/dev/null'
check "P1e. neither copy creates a branch" '! grep -q "checkout -b" "$HERE/templates/plans/pr.sh" && ! grep -q "checkout -b" "$HERE/self/pr.sh"'

# ── C1. close refuses what it must ────────────────────────────────────────────
( cd "$TMP" && "$WT/feature-close.sh" --self "$SLUG" >/dev/null 2>&1 ); rc=$?
check "C1a. the copy inside a worktree refuses (got $rc)" '[[ $rc -ne 0 ]]'
out="$(close "$SLUG")"; rc=$?
check "C1b. an unmerged branch is refused (got $rc)" '[[ $rc -ne 0 ]] && grep -qi "not merged" <<<"$out"'
git -C "$AT" merge -q --no-ff -m "Merge $SLUG" "$SLUG" && git -C "$AT" push -q origin main 2>/dev/null
echo z > "$AT/dirty.txt"
close "$SLUG" >/dev/null 2>&1; rc=$?
check "C1c. a dirty primary is refused (got $rc)" '[[ $rc -ne 0 ]]'
rm -f "$AT/dirty.txt"

# ── C2. an unclaimed delegate naming this feature stops the close ─────────────
# The session launched in R-S, on branch S — claimable by branch once capture knows the
# rule — and a coordinator on main in the primary whose delegate's brief names S.
FROM="$(fence "$AT/self/features/$SLUG/README.md" "d['session_window']['from']")"
SESSION_W="wwwwwwww-0000-0000-0000-000000000002"
SESSION_M="mmmmmmmm-0000-0000-0000-000000000003"
AGENT_D="d1111111111111111"
AGENT_E="e1111111111111111"
WP="$(project_dir "$WT")"; MP="$(project_dir "$AT")"; EP="$(project_dir "/elsewhere/repo")"
mkdir -p "$WP" "$MP/$SESSION_M/subagents" "$EP"
T="$(now_z)"
session_line "$SESSION_W" "$WT" "$SLUG" "msg-w" "$MODEL" "$T" 100 5000 0 0 0 > "$WP/$SESSION_W.jsonl"
session_line "$SESSION_M" "$AT" "main" "msg-m" "$MODEL" "$T" 100 1000 0 0 0 > "$MP/$SESSION_M.jsonl"
# The `feature:` header on a line of its own, which is the shape `brief_feature_of` reads
# and `feature-start.sh` prints for a delegate's brief to copy.
{
  subagent_prompt_line "$SESSION_M" "$AGENT_D" "$AT" "main" "$T" "feature: agentTooling/$SLUG\\nbuild it"
  subagent_line "$SESSION_M" "$AGENT_D" "$AT" "main" "msg-d" "$MODEL" "$T" 100 2000 0 0 0
} > "$MP/$SESSION_M/subagents/agent-$AGENT_D.jsonl"
# A second delegate of the same coordinator, briefed for a *different* feature whose name
# begins with this one's. It is not this feature's stray and must not stop this close: the
# guard compares the (repo, slug) pair the brief carries, where a substring test over the
# printed table matched and sent the human to pin it into the wrong manifest — where the
# other feature's capture would then be refused for a claim it never made.
{
  subagent_prompt_line "$SESSION_M" "$AGENT_E" "$AT" "main" "$T" "feature: agentTooling/$SLUG-two\\nbuild the other one"
  subagent_line "$SESSION_M" "$AGENT_E" "$AT" "main" "msg-e" "$MODEL" "$T" 100 2000 0 0 0
} > "$MP/$SESSION_M/subagents/agent-$AGENT_E.jsonl"
# The pinned session: launched somewhere else entirely, on main, long before the window.
session_line "$PIN" "/elsewhere/repo" "main" "msg-p" "$MODEL" "2026-01-01T00:00:00.000Z" 100 3000 0 0 0 > "$EP/$PIN.jsonl"
out="$(close "$SLUG")"; rc=$?
check "C2a. an unclaimed delegate naming S stops the close (got $rc)" '[[ $rc -ne 0 ]] && grep -q "$AGENT_D" <<<"$out"'
check "C2b. ... writing nothing" '[[ ! -e "$AT/self/features/$SLUG/planning.json" && -z "$(git -C "$AT" status --porcelain)" ]]'
check "C2c. the one briefed for S-two is not S's stray and is never named" '! grep -q "$AGENT_E" <<<"$out"'
python3 - "$AT/self/features/$SLUG/README.md" "$AGENT_D" <<'PY'
import re, sys
path, agent = sys.argv[1], sys.argv[2]
text = open(path).read()
new, n = re.subn(r'"subagents":\s*\[\]', '"subagents": ["%s"]' % agent, text, count=1)
assert n == 1
open(path, "w").write(new)
PY
git -C "$AT" commit -q -am "$SLUG: pin the delegate" && git -C "$AT" push -q origin main 2>/dev/null

# ── C3. the close ─────────────────────────────────────────────────────────────
# With the real stray pinned this must go through, and AGENT_E — still unclaimed, still
# briefed for S-two — must still not stop it.
out="$(close "$SLUG")"; rc=$?
PJ="$AT/self/features/$SLUG/planning.json"
check "C3a. feature-close.sh exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C3b. the session launched in R-S is claimed by branch, cwd recorded" '[[ "$(pj "$PJ" "[(s[\"session_id\"], s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"]==\"$SESSION_W\"]")" == "[('"'"'$SESSION_W'"'"', '"'"'branch'"'"', '"'"'$WT'"'"')]" ]]'
check "C3c. the pinned session is claimed by id from another project directory" '[[ "$(pj "$PJ" "[(s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"]==\"$PIN\"]")" == "[('"'"'pinned'"'"', '"'"'/elsewhere/repo'"'"')]" ]]'
check "C3d. the coordinator on main is not claimed; its pinned delegate is" '[[ "$(pj "$PJ" "\"$SESSION_M\" in [s[\"session_id\"] for s in d[\"sessions\"]]")" == "False" && "$(pj "$PJ" "[s[\"agent_id\"] for s in d[\"subagents\"]]")" == "['"'"'$AGENT_D'"'"']" ]]'
check "C3e. the total is the three priced transcripts, non-zero" 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d[\"cost_usd\"][\"total\"] > 0 and len(d[\"priced\"]) == 3 else 1)" "$PJ"'
check "C3f. session_window.to is stamped in UTC with a Z" '[[ "$(fence "$AT/self/features/$SLUG/README.md" "d[\"session_window\"][\"to\"]")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]'
check "C3g. report.md and report.json were written" '[[ -f "$AT/self/features/$SLUG/report.md" && -f "$AT/self/features/$SLUG/report.json" ]]'
cost_files="$(git -C "$AT" show --name-only --format= HEAD | LC_ALL=C sort | tr "\n" " ")"
check "C3h. the commit is 'S: cost records' holding exactly the cost files (got: $cost_files)" '[[ "$(git -C "$AT" log -1 --format=%s)" == "$SLUG: cost records" && "$cost_files" == "self/features/$SLUG/README.md self/features/$SLUG/planning.json self/features/$SLUG/report.json self/features/$SLUG/report.md self/features/$SLUG/timing.jsonl " ]]'
check "C3i. main was pushed and the primary is clean" '[[ "$(git -C "$AT" rev-parse origin/main)" == "$(git -C "$AT" rev-parse main)" && -z "$(git -C "$AT" status --porcelain)" ]]'
check "C3j. the nested worktree and the local branch are gone" '[[ ! -e "$WT" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/$SLUG"'
check "C3k. the output lists what it claimed, by id and by how" 'grep -q "$SESSION_W" <<<"$out" && grep -q "$PIN" <<<"$out" && grep -q "pinned" <<<"$out"'
# The review pass's `pr_opened` line, written after the PR hook committed, reached main
# only because the close carried it — and exactly once, since the carry matches whole lines.
PRIMARY_TIMING="$AT/self/features/$SLUG/timing.jsonl"
check "C3l. the trailing pr_opened stamp is on main, with its URL, exactly once" '[[ "$(grep -c "\"event\":\"pr_opened\"" "$PRIMARY_TIMING")" == "1" ]] && grep -q "example.invalid/pr/1" "$PRIMARY_TIMING"'
# The delegate this close claimed was pinned in the manifest before the close ran, which
# is the ordinary case and the shape all seven closes of 2026-09-07 had. The close used
# to print it as unclaimed and then tell the human to pin what was already pinned.
check "C3m. a delegate already pinned in the manifest is not printed as unclaimed, nor is the pin instruction" '! grep -q "Pin each in" <<<"$out"'
check "C3n. ...it is one line saying how many are already pinned" 'grep -q "pinned    1 delegate(s) already pinned in the manifest" <<<"$out"'

# ── C4. --keep-worktree --no-push ─────────────────────────────────────────────
SLUG2="lifecycle-two"; WT2="$(wt_path "$SLUG2")"
start "$SLUG2" --no-gate --no-pin >/dev/null 2>&1
git -C "$AT" merge -q --no-ff -m "Merge $SLUG2" "$SLUG2" && git -C "$AT" push -q origin main 2>/dev/null
mkdir -p "$(project_dir "$WT2")"
session_line "s2s2s2s2-0000-0000-0000-000000000004" "$WT2" "$SLUG2" "msg-2" "$MODEL" "$(now_z)" 100 5000 0 0 0 > "$(project_dir "$WT2")/s2s2s2s2-0000-0000-0000-000000000004.jsonl"
# An uncommitted trailing stamp of the shape a runner's EXIT trap leaves, so the carry has
# something to do here and the second close below has something to double.
printf '{"at":"%s","event":"pass_end","queue":"review","reason":"all reviews complete"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  > "$WT2/self/features/$SLUG2/timing.jsonl"
close "$SLUG2" --keep-worktree --no-push >/dev/null 2>&1; rc=$?
check "C4a. close with --keep-worktree --no-push exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C4b. the worktree and branch remain" '[[ -d "$WT2" ]] && git -C "$AT" show-ref --quiet "refs/heads/$SLUG2"'
check "C4c. the cost commit exists locally and was not pushed" '[[ "$(git -C "$AT" log -1 --format=%s)" == "$SLUG2: cost records" && "$(git -C "$AT" rev-parse origin/main)" != "$(git -C "$AT" rev-parse main)" ]]'
# The kept worktree still holds that line, so a second close re-reads it: the carry
# matches whole lines, so it carries nothing twice.
T2_TIMING="$AT/self/features/$SLUG2/timing.jsonl"
lines_before="$(wc -l < "$T2_TIMING" | tr -d ' ')"
close "$SLUG2" --keep-worktree --no-push >/dev/null 2>&1; rc=$?
check "C4d. a second close over the kept worktree duplicates no timing line (got $rc)" '[[ $rc -eq 0 && "$(wc -l < "$T2_TIMING" | tr -d " ")" == "$lines_before" && "$lines_before" -gt 0 ]]'
git -C "$AT" push -q origin main 2>/dev/null

# ── C5. nothing matched: nothing written ──────────────────────────────────────
SLUG3="lifecycle-zero"; WT3="$(wt_path "$SLUG3")"
start "$SLUG3" --no-gate --no-pin >/dev/null 2>&1
# One committed stamp, so the primary has a copy of its own after the merge, and one
# uncommitted trailing stamp, so the carry has something real to do here. Without both,
# C5c passes vacuously: this worktree is never run in, so it has no timing.jsonl at all.
WT3_TIMING="$WT3/self/features/$SLUG3/timing.jsonl"
printf '{"at":"%s","event":"pass_start","queue":"review"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$WT3_TIMING"
git -C "$WT3" add -A && git -C "$WT3" commit -q -m "$SLUG3: a timing record of its own"
git -C "$AT" merge -q --no-ff -m "Merge $SLUG3" "$SLUG3" && git -C "$AT" push -q origin main 2>/dev/null
printf '{"at":"%s","event":"pass_end","queue":"review","reason":"nothing to do"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$WT3_TIMING"
P3_TIMING="$AT/self/features/$SLUG3/timing.jsonl"
cp "$P3_TIMING" "$TMP/zero-timing.before"
out="$(close "$SLUG3")"; rc=$?
check "C5a. a close that matches nothing exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "C5b. ... writes no planning.json and stamps no to" '[[ ! -e "$AT/self/features/$SLUG3/planning.json" && "$(fence "$AT/self/features/$SLUG3/README.md" "d[\"session_window\"][\"to\"]")" == "None" ]]'
check "C5c. ... and leaves the primary clean, worktree in place" '[[ -z "$(git -C "$AT" status --porcelain)" && -d "$WT3" ]]'
check "C5d. ... naming the three causes" 'grep -q "git branch --list" <<<"$out" && grep -qi "aged out" <<<"$out" && grep -qi "launched" <<<"$out"'
# Not vacuous: the carry ran, on a primary copy that already had a line of its own, and
# the refusal put that copy back byte for byte — a dirty primary here is what the next
# run refuses on, and the file it would name is a record that must not be discarded.
check "C5e. the carry really had something to carry" 'grep -q "carried 1 trailing stamp" <<<"$out" && [[ "$(wc -l < "$TMP/zero-timing.before" | tr -d " ")" == "1" && "$(wc -l < "$WT3_TIMING" | tr -d " ")" == "2" ]]'
check "C5f. ... and the refusal rolled it back: the primary timing.jsonl is byte-identical" 'cmp -s "$TMP/zero-timing.before" "$P3_TIMING" && grep -qi "rolled back" <<<"$out"'
out2="$(close "$SLUG3")"; rc2=$?
check "C5g. ... so the re-run refuses for the same reason, not for a dirty primary (got $rc2)" '[[ $rc2 -ne 0 ]] && ! grep -qi "is dirty" <<<"$out2" && grep -q "git branch --list" <<<"$out2" && [[ -z "$(git -C "$AT" status --porcelain)" ]]'

# ── L. a feature started under the legacy layout still closes ─────────────────
# Features started before worktrees moved inside the primary keep their sibling R-S until
# they close (self/features/in-repo-worktrees/README.md → "Deliberately excluded").
# `git worktree move` gives one exactly that shape: the branch, the manifest and the
# `S: start` commit feature-start.sh wrote, with the worktree at the old path.
SLUGL="lifecycle-legacy"; LWT="$AT-$SLUGL"
start "$SLUGL" --no-gate --no-pin >/dev/null 2>&1
git -C "$AT" worktree move "$(wt_path "$SLUGL")" "$LWT"
git -C "$AT" merge -q --no-ff -m "Merge $SLUGL" "$SLUGL" && git -C "$AT" push -q origin main 2>/dev/null
SESSION_L="llllllll-0000-0000-0000-000000000008"
mkdir -p "$(project_dir "$LWT")"
session_line "$SESSION_L" "$LWT" "$SLUGL" "msg-l" "$MODEL" "$(now_z)" 100 5000 0 0 0 \
  > "$(project_dir "$LWT")/$SESSION_L.jsonl"
LWT_STAMP="$(printf '{"at":"%s","event":"pass_end","queue":"review","reason":"legacy layout"}' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
printf '%s\n' "$LWT_STAMP" > "$LWT/self/features/$SLUGL/timing.jsonl"
check "L0. the fixture's premise: branch S is checked out at the legacy R-S and nothing is nested" \
  '[[ -d "$LWT" && ! -e "$(wt_path "$SLUGL")" && "$(git -C "$LWT" branch --show-current 2>/dev/null)" == "$SLUGL" ]]'
outl="$(close "$SLUGL")"; rcl=$?
PJL="$AT/self/features/$SLUGL/planning.json"
check "L1. a close of a legacy-layout feature exits 0 (got $rcl)" '[[ $rcl -eq 0 ]]'
check "L2. ... claiming the session launched in R-S by branch, cwd recorded" \
  '[[ "$(pj "$PJL" "[(s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"]==\"$SESSION_L\"]")" == "[('"'"'branch'"'"', '"'"'$LWT'"'"')]" ]]'
check "L3. ... carrying the legacy worktree's trailing timing stamp home" \
  'grep -q "carried 1 trailing stamp" <<<"$outl" && grep -qxF "$LWT_STAMP" "$AT/self/features/$SLUGL/timing.jsonl"'
check "L4. ... and removing the legacy worktree and the branch, leaving the primary clean" \
  '[[ ! -e "$LWT" && -z "$(git -C "$AT" status --porcelain)" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/$SLUGL"'
outl2="$(close "$SLUGL" --recapture)"; rcl2=$?
check "L5. --recapture with the legacy worktree gone still claims its session (got $rcl2)" \
  '[[ $rcl2 -eq 0 && "$(pj "$PJL" "[s[\"session_id\"] for s in d[\"sessions\"]]")" == "['"'"'$SESSION_L'"'"']" ]]'

# ── W. session_window.to is stamped from evidence, before the capture ─────────
# `feature-close.sh` used to stamp `to` at its own wall clock, after the capture, so
# every feature started from one coordinator closed with the same bound and the windows
# nested instead of chaining (../BACKLOG.md, the entry this closes). It now stamps one
# second after the last instant of the feature's own branch-selected sessions and their
# subagents, before the capture, so the share split runs against the real bound.

# set_bound <readme> <from|to> <value|null> — rewrite one session_window bound inside the
# manifest's LAST ```json fence, the one capture_planning.py reads. By hand rather than
# through manifest.py, because two of the shapes below (an earlier `from`, a `to` later
# than the evidence) are exactly what manifest.py refuses to write.
set_bound() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, re, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
match = list(re.finditer(r"```json\n(.*?)\n```", text, re.S))[-1]
fence = match.group(1)
new = json.dumps(None if value == "null" else value)
fence, n = re.subn(r'("%s"\s*:\s*)("[^"]*"|null)' % key, lambda m: m.group(1) + new, fence, count=1)
assert n == 1, "no %r bound in the fence of %s" % (key, path)
open(path, "w").write(text[: match.start(1)] + fence + text[match.end(1):])
PY
}

SLUGW="lifecycle-window"; WTW="$(wt_path "$SLUGW")"
start "$SLUGW" --no-gate --no-pin >/dev/null 2>&1
MW="$AT/self/features/$SLUGW/README.md"
# feature-start.sh opens `from` at its own wall clock, so a session hours in the past is
# only inside the window once `from` moves back with it. Both instants are fixed, which
# is what lets W1b assert an exact `to`: a bound stamped at close time carries today's
# date and can never equal this one.
set_bound "$WTW/self/features/$SLUGW/README.md" from "2026-06-01T00:00:00Z"
git -C "$WTW" commit -q -am "$SLUGW: an earlier window"
git -C "$AT" merge -q --no-ff -m "Merge $SLUGW" "$SLUGW" && git -C "$AT" push -q origin main 2>/dev/null
SESSION_WIN="wnwnwnwn-0000-0000-0000-000000000005"
AGENT_WIN="a1111111111111115"
mkdir -p "$(project_dir "$WTW")/$SESSION_WIN/subagents"
# The session opens at 12:00 and closes at 12:45; its DELEGATE runs on to 13:00, an hour
# past the parent's own opening line. That is the ordinary shape of a build — an
# implementer that ran for hours under a coordinator whose own last line came first — and
# a bound taken from the parent alone would close the window while the delegate was still
# working. The two instants that decide the bound both carry `.700`, so the bound is also
# evidence that the whole-second truncation happened: without it the fence would read
# `2026-06-01T13:00:01.700000Z`, which still parses everywhere and would therefore never
# fail anything else. The middle line at 12:45 is what W6 needs: it is the only line that
# can put a HAND-written bound between a selected session's start and its end, which is
# the one shape from which the evidence would widen rather than tighten.
{
  session_line "$SESSION_WIN" "$WTW" "$SLUGW" "msg-w1" "$MODEL" "2026-06-01T12:00:00.700Z" 100 5000 0 0 0
  session_line "$SESSION_WIN" "$WTW" "$SLUGW" "msg-w1b" "$MODEL" "2026-06-01T12:45:00.000Z" 100 1000 0 0 0
} > "$(project_dir "$WTW")/$SESSION_WIN.jsonl"
subagent_line "$SESSION_WIN" "$AGENT_WIN" "$WTW" "$SLUGW" "msg-w1a" "$MODEL" "2026-06-01T13:00:00.700Z" 100 2000 0 0 0 \
  > "$(project_dir "$WTW")/$SESSION_WIN/subagents/agent-$AGENT_WIN.jsonl"
outw="$(close "$SLUGW" --keep-worktree)"; rcw=$?
to_w="$(fence "$MW" "d[\"session_window\"][\"to\"]")"
check "W1a. a close whose branch session ended hours ago exits 0 (got $rcw)" '[[ $rcw -eq 0 ]]'
check "W1b. session_window.to is one second past the last instant of the session's DELEGATE, not of the session or of the close's clock (got $to_w)" '[[ "$to_w" == "2026-06-01T13:00:01Z" ]]'
check "W1c. ... and the session and delegate it was derived from are both still captured — the bound is exclusive" '[[ "$(pj "$AT/self/features/$SLUGW/planning.json" "[s[\"session_id\"] for s in d[\"sessions\"]]")" == "['"'"'$SESSION_WIN'"'"']" && "$(pj "$AT/self/features/$SLUGW/planning.json" "[a[\"agent_id\"] for a in d[\"subagents\"]]")" == "['"'"'$AGENT_WIN'"'"']" ]]'
check "W1d. ... and the bound is at second resolution though the evidence carried milliseconds" '[[ "$to_w" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]'

# W2. No branch session at all: the pinned session is off the branch and in another
# checkout, so it is claimed by id and is not evidence of when work on the branch
# stopped. The close falls back to its own clock and announces it.
SLUGN="lifecycle-nobranch"
PIN_N="nbnbnbnb-0000-0000-0000-000000000006"
start "$SLUGN" --no-gate --session "$PIN_N" >/dev/null 2>&1
git -C "$AT" merge -q --no-ff -m "Merge $SLUGN" "$SLUGN" && git -C "$AT" push -q origin main 2>/dev/null
session_line "$PIN_N" "/elsewhere/repo" "main" "msg-n" "$MODEL" "2026-02-02T00:00:00.000Z" 100 3000 0 0 0 \
  > "$EP/$PIN_N.jsonl"
before_z="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
outn="$(close "$SLUGN")"; rcn=$?
to_n="$(fence "$AT/self/features/$SLUGN/README.md" "d[\"session_window\"][\"to\"]")"
check "W2a. a feature whose only session is pinned off the branch closes 0 (got $rcn)" '[[ $rcn -eq 0 ]]'
check "W2b. ... announcing that to was stamped at close time" 'grep -q "no branch session — to stamped at close time" <<<"$outn"'
check "W2c. ... with to at this run's clock, not the pinned session's instant (got $to_n)" '[[ "$to_n" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && [[ ! "$to_n" < "$before_z" ]]'

# W3. The repair path for every `to` already written at close time in both corpora:
# --recapture re-derives the evidence and TIGHTENS the bound onto it.
set_bound "$MW" to "2026-06-02T00:00:00Z"
git -C "$AT" commit -q -am "$SLUGW: a bound stamped at close time"
git -C "$AT" push -q origin main 2>/dev/null
outt="$(close "$SLUGW" --recapture --keep-worktree)"; rct=$?
check "W3a. --recapture over a to later than the evidence exits 0 (got $rct)" '[[ $rct -eq 0 ]]'
check "W3b. ... printing old -> new" 'grep -q "2026-06-02T00:00:00Z -> 2026-06-01T13:00:01Z" <<<"$outt"'
check "W3c. ... and the fence carries the tightened bound" '[[ "$(fence "$MW" "d[\"session_window\"][\"to\"]")" == "2026-06-01T13:00:01Z" ]]'

# W4. A bound is never widened, by any path, and it is never written at or before its own
# `from` either. The refusal must name both instants: with --tighten unimplemented,
# argparse also exits non-zero, so exit code alone is vacuous — and the two refusals carry
# DIFFERENT codes, because feature-close.sh continues past exactly one of them (W5).
cp "$MW" "$TMP/window-manifest.before"
outr="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2027-01-01T00:00:00Z 2>&1)"; rcr=$?
check "W4a. set-window-to --tighten refuses a later instant, with the widen refusal's own exit code (got $rcr, want 3)" '[[ $rcr -eq 3 ]]'
check "W4b. ... naming the bound it holds and the one it was offered" 'grep -q "2026-06-01T13:00:01Z" <<<"$outr" && grep -q "2027-01-01T00:00:00Z" <<<"$outr"'
check "W4c. ... and leaving the fence byte-identical" 'cmp -s "$TMP/window-manifest.before" "$MW"'
# The bound it already carries is a no-op, not a refusal: feature-close.sh --recapture
# re-derives the same evidence on every repair run (recover-at-close.sh C12).
oute="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-06-01T13:00:01Z 2>&1)"; rce=$?
check "W4d. ... while the bound it already carries is a no-op, exit 0 (got $rce)" '[[ $rce -eq 0 ]] && cmp -s "$TMP/window-manifest.before" "$MW"'
# The other end of the same fence. Tightening is inwards, and far enough inwards is an
# EMPTY window: `is_empty_window` drops such a claim from every other feature's split, so
# the feature would own nothing and only a WARN at the next capture would say so. It is a
# plain failure, not the widen refusal — the close must stop on it — and it is unreachable
# from evidence, since a branch-selected session starts at or after `from`.
outf="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-05-31T23:00:00Z 2>&1)"; rcf=$?
check "W4e. ... and refuses a bound BEFORE the fence's from, as a plain failure not the widen code (got $rcf, want 1)" '[[ $rcf -eq 1 ]]'
check "W4f. ... naming the from it holds and the bound it was offered" 'grep -q "2026-06-01T00:00:00Z" <<<"$outf" && grep -q "2026-05-31T23:00:00Z" <<<"$outf"'
check "W4g. ... and leaving the fence byte-identical" 'cmp -s "$TMP/window-manifest.before" "$MW"'
outb="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-06-01T00:00:00Z 2>&1)"; rcb=$?
check "W4h. ... and a bound exactly AT from is refused too — an empty window owns nothing (got $rcb)" '[[ $rcb -eq 1 ]] && cmp -s "$TMP/window-manifest.before" "$MW"'
# The manifest these four wrote to is a tracked file in the primary checkout, so a refusal
# that wrote anyway leaves the primary dirty — which is what the next close refuses on,
# and what W5 below would then be measuring instead of its own subject.
check "W4i. ... and none of the four refusals dirtied the primary" '[[ -z "$(git -C "$AT" status --porcelain)" ]]'

# ── W5. a stamp that fails for any other reason stops the close ───────────────
# `set-window-to` exits non-zero for three different reasons, and only one of them —
# the refused widen above — is this close's business to continue past: the bound it
# declined to widen is the one already published. A fence with no `to` key at all, or a
# bound that will not parse, leaves the window OPEN on a feature that is about to be
# captured, committed, pushed and have its branch deleted, which is the permanent
# double-count AGENT_PLANS.md warns about. The close refuses, names what set-window-to
# printed rather than a cause that did not happen, and rolls back what it had already
# done to the primary — exactly as the capture refusal does.
SLUGK="lifecycle-nokey"; WTK="$(wt_path "$SLUGK")"
start "$SLUGK" --no-gate --no-pin >/dev/null 2>&1
python3 - "$WTK/self/features/$SLUGK/README.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
match = list(re.finditer(r"```json\n(.*?)\n```", text, re.S))[-1]
fence, n = re.subn(r',\s*"to":\s*(?:"[^"]*"|null)', "", match.group(1), count=1)
assert n == 1, "no `to` bound to drop from %s" % path
open(path, "w").write(text[: match.start(1)] + fence + text[match.end(1):])
PY
# A committed timing line, so the primary has a copy of its own after the merge, and an
# uncommitted trailing one, so the carry has something real to roll back — the C5e/C5f
# shape. Without both, W5d passes vacuously.
WTK_TIMING="$WTK/self/features/$SLUGK/timing.jsonl"
printf '{"at":"%s","event":"pass_start","queue":"review"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$WTK_TIMING"
git -C "$WTK" add -A && git -C "$WTK" commit -q -m "$SLUGK: a fence with no to bound"
git -C "$AT" merge -q --no-ff -m "Merge $SLUGK" "$SLUGK" && git -C "$AT" push -q origin main 2>/dev/null
printf '{"at":"%s","event":"pass_end","queue":"review","reason":"all reviews complete"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$WTK_TIMING"
# A real branch session, so the capture this close never reaches WOULD have succeeded:
# without it the close would refuse at the capture for matching nothing and W5a would pass
# whatever the stamp did.
SESSION_K="kkkkkkkk-0000-0000-0000-000000000007"
mkdir -p "$(project_dir "$WTK")"
session_line "$SESSION_K" "$WTK" "$SLUGK" "msg-k" "$MODEL" "$(now_z)" 100 5000 0 0 0 \
  > "$(project_dir "$WTK")/$SESSION_K.jsonl"
PK_TIMING="$AT/self/features/$SLUGK/timing.jsonl"
cp "$PK_TIMING" "$TMP/nokey-timing.before"
outk="$(close "$SLUGK")"; rck=$?
check "W5a. a close whose stamp fails for anything but a refused widen exits non-zero (got $rck)" '[[ $rck -ne 0 ]]'
check "W5b. ... naming what set-window-to printed, not the widen refusal that did not happen" 'grep -q "bound in the fence" <<<"$outk" && ! grep -q "never widened" <<<"$outk"'
check "W5c. ... writing no planning.json — the capture was never reached" '[[ ! -e "$AT/self/features/$SLUGK/planning.json" ]]'
check "W5d. ... and rolling the carry back: the primary is clean and its timing.jsonl byte-identical" '[[ -z "$(git -C "$AT" status --porcelain)" ]] && cmp -s "$TMP/nokey-timing.before" "$PK_TIMING"'
check "W5e. ... which is not vacuous — the carry had a line to roll back" 'grep -q "carried 1 trailing stamp" <<<"$outk" && grep -qi "rolled back" <<<"$outk"'

# ── W6. ... and the one code it does continue past ────────────────────────────
# The complement of W5, and the reason it exists: the tolerated code is written down
# TWICE — WIDEN_REFUSED_EXIT in manifest.py, WIDEN_REFUSED_RC in feature-close.sh, since
# bash cannot import it — so nothing but an assertion keeps the two in step, and a drift
# would turn every declined widen into a refused close. Move SLUGW's bound EARLIER than
# its evidence by hand, so --recapture's tighten would have to widen it: the close must
# warn, capture anyway, and leave the published bound exactly where it found it.
set_bound "$MW" to "2026-06-01T12:30:00Z"
git -C "$AT" commit -q -am "$SLUGW: a bound tighter than the evidence"
git -C "$AT" push -q origin main 2>/dev/null
outv="$(close "$SLUGW" --recapture --keep-worktree)"; rcv=$?
check "W6a. --recapture whose evidence would WIDEN the bound still closes 0 (got $rcv)" '[[ $rcv -eq 0 ]]'
check "W6b. ... warning that the bound was left as it is" 'grep -q "never widened" <<<"$outv"'
check "W6c. ... and leaving the published bound untouched" '[[ "$(fence "$MW" "d[\"session_window\"][\"to\"]")" == "2026-06-01T12:30:00Z" ]]'

echo
if (( fails > 0 )); then echo "feature-lifecycle: $fails assertion(s) FAILED"; exit 1; fi
echo "feature-lifecycle: all assertions passed"
