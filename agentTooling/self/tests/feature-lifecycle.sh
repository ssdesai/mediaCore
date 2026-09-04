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
# The rule under test, for slug S and primary checkout R: branch S, worktree R-S, and
# every session a feature costs is either launched in R-S or pinned by id.
#
# Asserts, in order:
#   S1. feature-start.sh --self S creates branch S and worktree R-S off origin/main,
#       leaves the primary on main and clean, writes the manifest (branches [S], base
#       main, `from` in UTC with a Z, `to` null, the running session pinned from
#       $CLAUDE_CODE_SESSION_ID), a review stub carrying @@TODO@@ numbered next in the
#       global sequence, commits `S: start`, ran the hook and the gate inside R-S, and
#       prints the worktree path and the `feature: <repo>/S` line;
#   S2. it refuses a slug that fails the pattern, a slug whose branch exists, and being
#       run from a worktree's copy — creating nothing in each case;
#   S3. --no-pin, --session, an unset environment, --method, --base, --no-gate, and a
#       red gate (refuses, worktree left in place, no manifest);
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
#       removes the worktree and the branch;
#   C4. --keep-worktree --no-push keeps both, pushes nothing, and carries no line twice;
#   C5. a close that matches nothing writes nothing, stamps nothing, rolls its timing
#       carry back and so leaves the primary clean and re-runnable.
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
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/' '-')"; }

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
WT="$AT-$SLUG"
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

# ── S2. refusals create nothing ───────────────────────────────────────────────
before="$(branches)"
for bad in "Bad_Slug" "review/x" "-lead" "trail-" "two--dashes"; do
  start "$bad" >/dev/null 2>&1; rc=$?
  check "S2a. slug '$bad' is refused (got $rc)" '[[ $rc -ne 0 ]]'
done
check "S2b. no branch and no worktree was created for any of them" '[[ "$(branches)" == "$before" && ! -e "$AT-Bad_Slug" && ! -e "$AT-review/x" ]]'
start "$SLUG" >/dev/null 2>&1; rc=$?
check "S2c. a slug whose branch exists is refused (got $rc)" '[[ $rc -ne 0 ]]'
( cd "$TMP" && "$WT/feature-start.sh" --self another >/dev/null 2>&1 ); rc=$?
check "S2d. the copy inside a worktree refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "S2e. ... and created nothing" '[[ ! -e "$WT-another" && ! -e "$AT-another" && "$(branches)" == "$before" ]]'

# ── S3. options ───────────────────────────────────────────────────────────────
start lifecycle-nopin --no-pin --no-gate >/dev/null 2>&1
check "S3a. --no-pin leaves sessions empty" '[[ "$(fence "$AT-lifecycle-nopin/self/features/lifecycle-nopin/README.md" "d[\"sessions\"]")" == "[]" ]]'
start lifecycle-sess --session abc-123 --no-gate >/dev/null 2>&1
check "S3b. --session pins the id given" '[[ "$(fence "$AT-lifecycle-sess/self/features/lifecycle-sess/README.md" "d[\"sessions\"]")" == "['"'"'abc-123'"'"']" ]]'
( cd "$TMP" && env -u CLAUDE_CODE_SESSION_ID "$AT/feature-start.sh" --self lifecycle-noenv --no-gate >/dev/null 2>&1 )
check "S3c. no session id in the environment means no pin" '[[ "$(fence "$AT-lifecycle-noenv/self/features/lifecycle-noenv/README.md" "d[\"sessions\"]")" == "[]" ]]'
start lifecycle-hand --method hand --no-gate >/dev/null 2>&1
check "S3d. --method hand is recorded" '[[ "$(fence "$AT-lifecycle-hand/self/features/lifecycle-hand/README.md" "d[\"method\"]")" == "hand" ]]'
start lifecycle-bad-method --method nope --no-gate >/dev/null 2>&1; rc=$?
check "S3e. an unknown --method is refused (got $rc)" '[[ $rc -ne 0 && ! -e "$AT-lifecycle-bad-method" ]]'
start lifecycle-based --base other --no-gate >/dev/null 2>&1
check "S3f. --base other branches from origin/other" '[[ "$(git -C "$AT-lifecycle-based" rev-parse HEAD~1 2>/dev/null)" == "$(git -C "$AT" rev-parse origin/other)" ]]'
check "S3g. ... and records base other" '[[ "$(fence "$AT-lifecycle-based/self/features/lifecycle-based/README.md" "d[\"base\"]")" == "other" ]]'
check "S3h. --no-gate ran no gate" '[[ ! -f "$AT-lifecycle-based/self/gate-report.txt" ]]'
GATE_STUB_VERDICT="one or more checks FAILED" start lifecycle-red >/dev/null 2>&1; rc=$?
check "S3i. a red gate refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "S3j. ... leaving the worktree in place and writing no manifest" '[[ -d "$AT-lifecycle-red" && ! -e "$AT-lifecycle-red/self/features/lifecycle-red" ]]'
HOOK_STUB_RC=3 start lifecycle-hookfail --no-gate >/dev/null 2>&1; rc=$?
check "S3k. a failing hook refuses, worktree left for inspection (got $rc)" '[[ $rc -ne 0 && -d "$AT-lifecycle-hookfail" && ! -e "$AT-lifecycle-hookfail/self/features/lifecycle-hookfail" ]]'

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
( cd "$AT-lifecycle-based" && echo x > dirty.txt && FEATURE_BASE=other ./self/pr.sh lifecycle-based >/dev/null 2>&1 ); rc=$?
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
check "C3j. the worktree and the local branch are gone" '[[ ! -e "$WT" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/$SLUG"'
check "C3k. the output lists what it claimed, by id and by how" 'grep -q "$SESSION_W" <<<"$out" && grep -q "$PIN" <<<"$out" && grep -q "pinned" <<<"$out"'
# The review pass's `pr_opened` line, written after the PR hook committed, reached main
# only because the close carried it — and exactly once, since the carry matches whole lines.
PRIMARY_TIMING="$AT/self/features/$SLUG/timing.jsonl"
check "C3l. the trailing pr_opened stamp is on main, with its URL, exactly once" '[[ "$(grep -c "\"event\":\"pr_opened\"" "$PRIMARY_TIMING")" == "1" ]] && grep -q "example.invalid/pr/1" "$PRIMARY_TIMING"'

# ── C4. --keep-worktree --no-push ─────────────────────────────────────────────
SLUG2="lifecycle-two"; WT2="$AT-$SLUG2"
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
SLUG3="lifecycle-zero"; WT3="$AT-$SLUG3"
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
check "C5c. ... and leaves the primary clean, worktree in place" '[[ -z "$(git -C "$AT" status --porcelain)" && -d "$AT-$SLUG3" ]]'
check "C5d. ... naming the three causes" 'grep -q "git branch --list" <<<"$out" && grep -qi "aged out" <<<"$out" && grep -qi "launched" <<<"$out"'
# Not vacuous: the carry ran, on a primary copy that already had a line of its own, and
# the refusal put that copy back byte for byte — a dirty primary here is what the next
# run refuses on, and the file it would name is a record that must not be discarded.
check "C5e. the carry really had something to carry" 'grep -q "carried 1 trailing stamp" <<<"$out" && [[ "$(wc -l < "$TMP/zero-timing.before" | tr -d " ")" == "1" && "$(wc -l < "$WT3_TIMING" | tr -d " ")" == "2" ]]'
check "C5f. ... and the refusal rolled it back: the primary timing.jsonl is byte-identical" 'cmp -s "$TMP/zero-timing.before" "$P3_TIMING" && grep -qi "rolled back" <<<"$out"'
out2="$(close "$SLUG3")"; rc2=$?
check "C5g. ... so the re-run refuses for the same reason, not for a dirty primary (got $rc2)" '[[ $rc2 -ne 0 ]] && ! grep -qi "is dirty" <<<"$out2" && grep -q "git branch --list" <<<"$out2" && [[ -z "$(git -C "$AT" status --porcelain)" ]]'

echo
if (( fails > 0 )); then echo "feature-lifecycle: $fails assertion(s) FAILED"; exit 1; fi
echo "feature-lifecycle: all assertions passed"
