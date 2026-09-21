#!/usr/bin/env bash
set -uo pipefail

# Self-test for the feature lifecycle scripts (LIFECYCLE.md;
# self/features/feature-lifecycle/README.md items 9–13;
# self/DESIGN-2026-09-16-lifecycle-restructure.md §3.1–§3.3, §4). Run by self/gate.sh, or
# by hand: bash self/tests/feature-lifecycle.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d that is a real git repo with
# a bare `origin` beside it — the real feature-start.sh, feature-capture.sh,
# feature-close.sh, the four runners, plan-runner-{lib,roots}.sh, stamp-timing.sh,
# self/pr.sh and analysis/*.py, plus a stub gate, a stub hook, a stub `claude` and a stub
# `gh` on PATH — and drives the whole loop with --self: start a feature, refuse its stub
# brief, capture its cost on the branch, review it (which records a verdict and stops),
# close it — PR, stamp, capture, merge request, in that order — merge it, and watch the
# next start prune it. Under a redirected $HOME it synthesizes the transcripts the
# captures read. No model, no network; a few seconds.
#
# The rule under test, for slug S and primary checkout R: branch S, worktree
# R/.worktrees/S — inside the primary, kept out of git by the common git dir's
# info/exclude — and every session a feature costs is launched in that worktree, where it
# is claimed by branch, or pinned by id. The cost capture runs IN that worktree, on the
# branch, before the merge, and the merge is the freeze.
#
# Asserts, in order:
#   S1. feature-start.sh --self S creates branch S and worktree R/.worktrees/S off
#       origin/main (nothing at the legacy R-S), leaves the primary on main and clean —
#       `git status --porcelain` empty with the worktree nested inside it, because
#       info/exclude now carries `/.worktrees/` exactly once and every entry it already
#       held, an unterminated last line included, is intact — writes the manifest
#       (branches [S], base main, `from` in UTC with a Z, `to` null, and NO pin: the
#       session that runs the start is a router, never a claimant), a review stub carrying
#       @@TODO@@ numbered 01 whatever another feature's corpus holds, a routing record naming S
#       INSIDE the feature directory at self/features/S/routing.json, commits both as `S: start`, ran the hook and the
#       gate inside the worktree, and prints the worktree path, the `feature: <repo>/S`
#       line, feature-close.sh as what opens the PR, and a last step that says merging the
#       PR is the end of it;
#   S2. it refuses a slug that fails the pattern, a slug whose branch exists, a slug
#       whose worktree path is already taken, and being run from a worktree's copy —
#       creating nothing in each case;
#   S3. --pin (the opt-in that restores the old behaviour), --no-pin (an accepted no-op),
#       --session with and without --pin, an unset environment, --method, --base,
#       --no-gate, and a red gate (refuses, worktree left in place, no manifest); and
#       after seven more starts the exclude entry is still there exactly once;
#   S4. the prune: a start removes every worktree under .worktrees/ whose branch is an
#       ancestor of origin/main and whose tree is clean, deletes that local branch, leaves
#       a dirty merged one and an unmerged one alone, and pushes nothing — including when
#       the merge happened on the REMOTE and the primary's own main lags, where the first
#       start only fast-forwards main and exits 3 with the rerun command, and the rerun
#       prunes; a diverged main, a primary behind while off main, and a fast-forward git
#       refuses (an untracked file in its way) are refused with nothing moved or started;
#   S5. --open runs the repo's open-session.sh hook with the worktree path as its only
#       argument, a start without it runs nothing, and both copies of the hook read as
#       text (S5d–S5f) to send that path through both escaping layers — the shell quoting,
#       then the AppleScript escaping — with the bare single-quoted path gone.
#       self/tests/open-session.sh runs the body and checks the path survives them;
#   S6. a --self start from an agentTooling VENDORED one directory inside the primary
#       (REL_REPO non-empty) commits agentTooling/self/features/<slug>/ with the routing
#       record inside it in `S: start`;
#   T1. run-review.sh files a brief whose line begins with @@TODO@@ to failed/ without
#       calling claude, and opens no PR;
#   C1. feature-capture.sh run from the worktree, after a commit of work, stamps `to` from
#       evidence, captures and reports, commits the cost records on the branch as
#       `S: cost records` and pushes the BRANCH: the remote's S carries planning.json,
#       report.*, the manifest with `to` set and the routing record the capture refreshed,
#       the remote's main is unchanged, and the worktree is clean and still there; a
#       delegate whose brief names S and that no route claims is a WARNING naming its id
#       and how to pin it, never a refusal, and a sibling briefed for S-two is not named;
#   C3. the capture prints the residue the retired weekly sweep used to print (design
#       §3.5), after what planning.json claims and before its commit: the rate table's
#       date, and the corpus-wide sessions and delegates no feature claims — the `main`
#       session with no `feature-start.sh` call is listed, the router that started S is
#       not, and neither listing makes the capture exit non-zero;
#   C2. a second capture after more work — a later transcript instant — moves `to`
#       LATER, rewrites planning.json, and meets no refusal about a frozen prior record;
#   N1. a feature no routing record names captures without a word about routing;
#   V1. a clean review pass records its verdict and stops: the pass is committed as
#       `S: review round 1` carrying its own fix, `plan_end` carries verdict=clean,
#       head=HEAD and round=1, there is exactly one plan_end and one pass_end, no PR is
#       opened, nothing is pushed, no capture runs, the only dirty path left is the
#       pass's own closing stamps, and the output names the close as the next step;
#   T3. a brief that merely MENTIONS the marker mid-line is not a stub and runs; the
#       CLOSE after it finds no session to capture, and that failure is advisory to the
#       PR but not to the merge — the refusal is printed with the re-run command, the PR
#       stays open, no merge is ever requested, the stamped `to` is rolled back, and the
#       close exits non-zero;
#   T4. where pr.sh takes its `skip` path and opens nothing (the forge CLI present but not
#       authenticated), the close still captures: the review pass made no forge call at
#       all, the runner committed its own pass, and the records are committed over it with
#       no "capture exited 1" and a clean worktree;
#   T5. and on the base branch itself the runner commits nothing: it says so, the
#       primary's work in progress is left uncommitted, and no forge or capture is touched;
#   P1. pr.sh honours FEATURE_BASE, refuses on the base branch, and the template and
#       self/pr.sh carry the same logic below their REPO-SPECIFIC line;
#   P2. PR_AUTO_MERGE lives behind `--merge-request` and only there: the OPEN path makes
#       no merge call even with it set; `--merge-request` with it set makes exactly one
#       `gh pr merge --auto`, asking for `--merge` and never `--squash` (both the prune
#       and the post-merge capture decide "merged" by ancestry, which a squash never
#       gives) and opens no PR of its own; unset, it exits 0 saying nothing was
#       requested; self/pr.sh never calls it; and both copies read template-version 4;
#   X1. the close refuses every tree no clean review judged: from the primary, on a
#       feature with no completed review (naming run-review.sh), and after a commit whose
#       subject is not the harness's own follows the judged head (naming its sha) — each
#       before any PR is opened;
#   V2. an escalated review: `plan_end` carries verdict=escalated, the report becomes the
#       rework brief at escalations/<stem>.md byte for byte and rides the pass commit, no
#       PR and no capture, the output names the file and the next round's steps, and the
#       close refuses;
#   V3. a report with no verdict line is `unreadable` and is treated exactly like
#       escalated, saying so;
#   RD. a rework is a new round: round 1 escalates, a by-hand checkpoint stamp during the
#       rework reads round 2, a second brief at a cheaper model reports clean with every
#       stamp carrying round 2, the pass commit is `S: review round 2`, and the close then
#       succeeds and stamps `pr_opened` with the round that closed;
#   X2. the close's order, with the template pr.sh and PR_AUTO_MERGE=1: pr create before
#       pr merge, the cost records committed on the branch and pushed, `pr_opened` riding
#       that commit with the PR url, the origin head at the merge request already carrying
#       the cost commit — the PR_AUTO_MERGE race, closed by ordering — exactly one merge
#       request, and a closing line naming the PR;
#   X3. a second close run ends at the same place: exit 0, the PR already open and no
#       second one, one record, the cost commit on top and a clean worktree;
#   X4. the close refuses exactly what the capture would, and before the PR: an untracked
#       NOTES.md.tmp inside the feature directory is not a cost record, so the close names
#       it, makes no forge call at all, and exits 0 again once it is gone;
#   X5. a seeded pr.sh at template-version 3 has no --merge-request entry point: the close
#       says so naming 3 and 4, opens the PR (one create call), asks for no merge, commits
#       the records and exits 0;
#   RC. the close's round is the one the review stamped: a round-2 review capped after
#       writing a clean report sits in review/failed/, so the completed count says 1 while
#       the banner and the pr_opened stamp both say 2;
#   RF. ... and with no `round` on the plan_end — a timing.jsonl from before rounds — the
#       close falls back to that count, and says 1;
#   B1/B2. run-batch.sh reads the verdict the same way: clean → it calls the close (PR
#       opened, records committed); escalated → exit 1, no PR, no capture, naming the
#       rework brief;
#   M1. merge S into the remote's main, start another feature: S's worktree and local
#       branch are gone, and the start pushed nothing;
#   MR. two features one router starts from the same main — the second started BEFORE the
#       first merges — merge in turn with no conflict, main carries a routing.json in each
#       feature directory, and report.py --all's Routing table holds ONE row for that
#       router naming both slugs (design 2026-09-18 §1: the defect this location fixes);
#   R1. `feature-capture.sh --recapture` post-merge from the primary refuses to widen
#       `to` (manifest unchanged), tightens an earlier bound, writes locally, commits
#       nothing and leaves the remote's refs byte-identical;
#   L1. a feature merged under the old flow and never closed — its worktree the legacy
#       sibling R-S — captures from the primary after the merge: the session launched in
#       R-S claimed by branch, `to` stamped, written locally, nothing committed or pushed;
#   C4. a rate table older than its staleness threshold warns in that residue and still
#       captures: every figure depends on the table, and a table nobody re-checked is not
#       a reason to leave a feature uncaptured while its transcripts exist;
#   W1. a capture whose only branch session ended hours ago stamps session_window.to one
#       second after the last instant of that session AND of its delegate, whichever ran
#       later, at second resolution, not at its own wall clock;
#   W7. before the merge that bound is provisional and moves EITHER way: a hand-written
#       `to` later than the evidence is replaced by the earlier evidence;
#   W2. a feature with no branch session at all — only a pinned session off the branch —
#       stamps `to` at capture time and says so in one line;
#   W5. a capture whose stamp fails for any reason but a refused widen refuses, names what
#       set-window-to printed, captures nothing and leaves the worktree clean;
#   W3. post-merge, --recapture over a `to` later than the evidence tightens it, printing
#       old -> new;
#   W4. manifest.py set-window-to --tighten refuses a LATER instant with its own exit
#       code 3, naming both bounds and leaving the fence byte-identical, while the bound
#       it already carries is a no-op rather than a refusal; and it refuses a bound at or
#       before the fence's `from` — an empty window — as a plain exit 1;
#   W6. while a --recapture whose evidence would WIDEN the bound warns, captures anyway
#       and leaves the published bound untouched — the one code the capture continues
#       past, which is written down in both scripts and so needs an assertion of its own;
#   A1. the frozen-record annotation runs AT CAPTURE, not in a weekly sweep: two features
#       pin one session, and capturing the second writes `also_claimed_by` onto the first's
#       frozen planning.json — every other byte of it identical — regenerates that
#       feature's report, and commits both with this feature's own cost records;
#   A2. while a sibling's record dirtied BEFORE the run — not by that annotation — refuses
#       the capture by name and leaves the tree exactly as it found it.
#
# A missing script fails its assertions loudly rather than aborting the run (no `set -e`;
# every cp below tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
ORIGIN="$TMP/origin.git"
mkdir -p "$AT/analysis" "$AT/self/features/old/review/complete" "$AT/templates/plans/features" "$TMP/bin"

for f in feature-start.sh feature-capture.sh feature-close.sh plan-runner-roots.sh plan-runner-lib.sh \
         run-plans.sh run-verify.sh run-review.sh run-batch.sh stamp-timing.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
for f in pricing.py roots.py transcript.py capture_planning.py report.py manifest.py routing.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md"
cp "$HERE/self/pr.sh" "$AT/self/pr.sh" 2>/dev/null || true
# The seeded template, outside the repo: P2 runs it as a consuming repo's plans/pr.sh.
PR_TEMPLATE="$TMP/pr-template.sh"
cp "$HERE/templates/plans/pr.sh" "$PR_TEMPLATE" 2>/dev/null || true
chmod +x "$AT"/*.sh "$AT/self/pr.sh" "$PR_TEMPLATE" 2>/dev/null || true
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

# Stub hook: records the directory it ran in, outside the tree so nothing sweeps it up.
cat > "$AT/self/worktree-setup.sh" <<'STUB'
#!/usr/bin/env bash
pwd > "${HOOK_CWD_OUT:?}"
exit "${HOOK_STUB_RC:-0}"
STUB
# Stub open-session hook: records the one argument it was handed. The seeded script's own
# body talks to Terminal.app and is never run by a test.
cat > "$AT/self/open-session.sh" <<'STUB'
#!/usr/bin/env bash
echo "$1" > "${OPEN_ARG_OUT:?}"
exit "${OPEN_STUB_RC:-0}"
STUB
# Stub gate: the real contract — exit 0, verdict in the report's last section.
cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$HERE/self/gate-report.txt"
{ echo "# Gate report"; echo ""; echo "# VERDICT"; echo "${GATE_STUB_VERDICT:-all checks passed}"; } > "$REPORT"
exit 0
STUB
# Stub claude: one result event; records that it was called, and writes the review
# executor's report where the runner will read it back. The report's FIRST LINE is the
# verdict (design §3, run-review.sh prompt step 10): CLAUDE_REPORT_OUT says where this
# run's report goes and CLAUDE_REPORT_FIRST_LINE what it opens with — empty for V3's
# report, which carries no verdict at all.
#
# CLAUDE_STUB_BUDGET_CAP=1 reports budget exhaustion AFTER writing that report, which is
# how RC drives the one shape where a round's verdict lives in review/failed/: the cap cut
# off the turns after the verdict, so the plan is filed failed while the round it decided
# is complete (run-review.sh → capped_after_report). The same switch tiered-gates.sh uses.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
touch "${CLAUDE_CALLED_OUT:-/dev/null}"
if [[ -n "${CLAUDE_REPORT_OUT:-}" ]]; then
  {
    if [[ -n "${CLAUDE_REPORT_FIRST_LINE:-}" ]]; then echo "$CLAUDE_REPORT_FIRST_LINE"; fi
    echo ""
    echo "## What the batch was supposed to do"
    echo "the stub review's body"
  } > "$CLAUDE_REPORT_OUT"
fi
if [[ "${CLAUDE_STUB_BUDGET_CAP:-0}" == 1 ]]; then
  printf '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":7,"num_turns":9,"session_id":"stub","usage":{}}\n'
  exit 1
fi
printf '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"session_id":"stub","usage":{}}\n'
exit 0
STUB
# Stub gh: logs every argv line, and remembers per branch that a PR was created, so a
# second run over the same branch finds it already open the way a forge would (X3).
# GH_AUTH_RC is what T4 flips
# to reach pr.sh's `skip` path — the forge CLI present but not logged in, which is the
# shape every consuming repo without `gh auth login` has, and the one where pr.sh returns
# 0 having committed nothing.
#
# `pr merge` also records the ORIGIN branch's head at the instant it was asked to merge,
# when GH_MERGE_HEAD_OUT names a file: that is what X2 asserts the cost commit is already
# inside, which is the whole of the PR_AUTO_MERGE race the close closes by ordering.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_LOG:?}"
# The branch a `pr view <branch>` asks about, and the `--head <branch>` a `pr create`
# names: one marker file per branch under $GH_PR_DIR is the whole of this stub's memory.
pr_marker() { echo "${GH_PR_DIR:?}/$1"; }
case "$1 $2" in
  "auth status") exit "${GH_AUTH_RC:-0}" ;;
  "pr view")
    if [[ -f "$(pr_marker "$3")" ]]; then cat "$(pr_marker "$3")"; exit 0; fi
    exit 1 ;;
  "pr create")
    url="https://example.invalid/pr/1"
    head=""
    while (( $# )); do
      if [[ "$1" == "--head" ]]; then head="$2"; fi
      shift
    done
    if [[ -n "$head" ]]; then echo "$url" > "$(pr_marker "$head")"; fi
    echo "$url"; exit 0 ;;
  "pr merge")
    if [[ -n "${GH_MERGE_HEAD_OUT:-}" ]]; then
      git -C "${GH_ORIGIN:-.}" rev-parse "refs/heads/$3" > "$GH_MERGE_HEAD_OUT" 2>/dev/null
    fi
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$AT/self/worktree-setup.sh" "$AT/self/open-session.sh" "$AT/self/gate.sh" "$TMP/bin/claude" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"
export GH_ORIGIN="$ORIGIN"
export GH_PR_DIR="$TMP/gh-prs"; mkdir -p "$GH_PR_DIR"
export HOOK_CWD_OUT="$TMP/hook-cwd"
export OPEN_ARG_OUT="$TMP/open-arg"
export CLAUDE_CALLED_OUT="$TMP/claude-called"
# The environment switch P2 flips, and the forge call it must (or must not) produce.
unset PR_AUTO_MERGE
AUTO_MERGE_CALL_RE='^pr merge .*--auto'
# Where the stub gh records the origin branch's head at the moment of a `pr merge` (X2).
export GH_MERGE_HEAD_OUT="$TMP/merge-head"
# The first line of a review report, which is the verdict the runner reads back
# (design §3; VERDICT_PREFIX and friends in plan-runner-roots.sh).
VERDICT_LINE_CLEAN="Verdict: clean"
VERDICT_LINE_ESCALATED="Verdict: escalated"

printf 'self/gate-report*.txt\nself/review-report.md\n' > "$AT/.gitignore"
# Another feature's corpus, numbered under the rule that ran before this one: a plan
# number is a feature's own, so what this holds must not move the stub number below (S1f).
echo "an older feature's review plan, at a number nothing else may inherit" > "$AT/self/features/old/review/complete/07-review-opus.md"
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
# $HOME is redirected for the start too: it writes a routing record derived from the
# router's transcript, and no test may read the machine's own ~/.claude (README.md).
start() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT/feature-start.sh" --self "$@" 2>&1 ); }
# A start with no session id in the environment writes no routing record — the shape of a
# start run by a human at a shell rather than by a session, and the cheaper fixture for
# every phase below that only needs a feature to exist.
start_unrouted() { HOME="$FAKE_HOME" env -u CLAUDE_CODE_SESSION_ID "$AT/feature-start.sh" --self "$@" 2>&1; }
# start_as <session-id> <slug> [flags] — a start attributed to a named router session,
# which is what MR needs two of from one id.
start_as() {
  local id="$1"; shift
  ( cd "$TMP" && HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$id" "$AT/feature-start.sh" --self "$@" 2>&1 )
}
# The routing record a start writes for the session that ran it: inside the feature
# directory it links, one per feature, never a path two features share
# (design 2026-09-18 §1). routing_record <checkout> <slug>.
routing_record() { echo "$1/self/features/$2/routing.json"; }
# capture <checkout> <slug> [flags] — THAT checkout's feature-capture.sh: a worktree's
# before the merge, the primary's after it. Run from $TMP, outside every checkout: the
# script derives every path from its own location, which is the property under test, and
# a cwd-relative git command inside it must never reach the repo running this test.
capture() {
  local checkout="$1"; shift
  (
    cd "$TMP"
    HOME="$FAKE_HOME" "$checkout/feature-capture.sh" --self "$@" 2>&1
  )
}
# review <checkout> <slug> [first-report-line] — that checkout's run-review.sh, which
# cd's to its own root. The stub claude writes REVIEW_REPORT for it — under --self that is
# <checkout>/self/review-report.md — opening with the third argument, `Verdict: clean` by
# default and empty for a report with no verdict line at all.
review() {
  local checkout="$1" slug="$2" first="${3-$VERDICT_LINE_CLEAN}"
  HOME="$FAKE_HOME" CLAUDE_REPORT_OUT="$checkout/self/review-report.md" \
    CLAUDE_REPORT_FIRST_LINE="$first" "$checkout/run-review.sh" --self "$slug" 2>&1
}
# close <checkout> <slug> [flags] — THAT checkout's feature-close.sh, run from $TMP like
# the capture: the script derives every path from its own location, and a cwd-relative git
# command inside it must never reach the repo running this test.
close() {
  local checkout="$1"; shift
  (
    cd "$TMP"
    HOME="$FAKE_HOME" "$checkout/feature-close.sh" --self "$@" 2>&1
  )
}
# batch <checkout> <slug> [first-report-line] — that checkout's run-batch.sh, whose build
# and verify queues are empty here, so what it exercises is the review pass and what the
# batch does with its verdict (B1/B2).
batch() {
  local checkout="$1" slug="$2" first="${3-$VERDICT_LINE_CLEAN}"
  HOME="$FAKE_HOME" CLAUDE_REPORT_OUT="$checkout/self/review-report.md" \
    CLAUDE_REPORT_FIRST_LINE="$first" "$checkout/run-batch.sh" --self "$slug" 2>&1
}
# plan_end_field <feature-dir> <plan-stem> <key> — a detail of the LAST `plan_end` stamp
# for that plan in timing.jsonl: the line the close, run-batch.sh and analysis/report.py
# all read a round's verdict and judged head from.
plan_end_field() {
  python3 -c "
import json, sys
value = ''
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get('event') == 'plan_end' and event.get('plan') == sys.argv[2]:
        value = event.get(sys.argv[3]) or ''
print(value)" "$1/timing.jsonl" "$2" "$3" 2>/dev/null
}
# last_event_field <feature-dir> <event> <key> — the same, for any event name.
last_event_field() {
  python3 -c "
import json, sys
value = ''
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get('event') == sys.argv[2]:
        value = event.get(sys.argv[3]) or ''
print(value)" "$1/timing.jsonl" "$2" "$3" 2>/dev/null
}
# fixture_session <worktree> <slug> <session-id> — one transcript for a session launched in
# that worktree, so the capture the close runs has a session to claim and does not refuse.
fixture_session() {
  mkdir -p "$(project_dir "$1")"
  session_line "$3" "$1" "$2" "msg-$3" "$MODEL" "$(now_z)" 100 3000 0 0 0 \
    > "$(project_dir "$1")/$3.jsonl"
}
# review_ready <slug> <session-id> — a started feature with a real brief in place of the
# stub, its build committed and a transcript to capture: the state every review pass below
# begins from. Echoes nothing; the caller already knows the paths.
review_ready() {
  local slug="$1" id="$2" wt fd stem
  wt="$(wt_path "$slug")"; fd="$wt/self/features/$slug"
  stem="$(fence "$fd/README.md" "d[\"plans\"][0]")"
  printf '# review\n\nA real brief for %s. Hold the diff to the manifest.\n' "$slug" \
    > "$fd/review/incomplete/$stem.md"
  echo "the build" > "$wt/work.txt"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "$slug: the build"
  fixture_session "$wt" "$slug" "$id"
}
# dirty_names <checkout> — the dirty paths, one per line, sorted: what a close or a capture
# is allowed to find is exactly the harness's own records.
dirty_names() { git -C "$1" status --porcelain --untracked-files=all | awk '{print $2}' | sort -u; }
branches() { git -C "$AT" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' '; }
origin_refs() { git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)' | sort; }
now_z() { date -u '+%Y-%m-%dT%H:%M:%S.000Z'; }
# shift_z <iso> <seconds> — an instant that many seconds after another, in transcript form.
shift_z() {
  python3 -c "import sys,datetime as t; m=t.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')); print((m+t.timedelta(seconds=int(sys.argv[2]))).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1" "$2"
}
# bound_after <iso> — the `to` a capture stamps from that last instant: whole seconds, +1s, Z.
bound_after() {
  python3 -c "import sys,datetime as t; m=t.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).replace(microsecond=0); print((m+t.timedelta(seconds=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"
}
# remote_has <slug> <file>... — every named file of the feature directory is on the
# REMOTE's branch <slug>.
remote_has() {
  local slug="$1" f; shift
  for f in "$@"; do
    git -C "$ORIGIN" cat-file -e "refs/heads/$slug:self/features/$slug/$f" 2>/dev/null || return 1
  done
}
# remote_fence <slug> <python expr over d> — a field of the manifest on the REMOTE's branch.
remote_fence() {
  git -C "$ORIGIN" show "refs/heads/$1:self/features/$1/README.md" > "$TMP/remote-manifest.md" 2>/dev/null
  fence "$TMP/remote-manifest.md" "$2"
}

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
check "S1f. manifest: method direct by default, review stub in plans" '[[ "$(fence "$FD/README.md" "d[\"method\"]")" == "direct" && "$(fence "$FD/README.md" "d[\"plans\"]")" == "['"'"'01-review-opus'"'"']" ]]'
check "S1g. manifest: from ends in Z, to is null" '[[ "$(fence "$FD/README.md" "d[\"session_window\"][\"from\"]")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$(fence "$FD/README.md" "d[\"session_window\"][\"to\"]")" == "None" ]]'
check "S1h. manifest: a plain start pins nothing — the router is never a claimant" '[[ "$(fence "$FD/README.md" "d[\"sessions\"]")" == "[]" && "$(fence "$FD/README.md" "d[\"subagents\"]")" == "[]" ]]'
check "S1i. review stub numbered 01 — a feature's own numbering, whatever the corpus holds — carrying @@TODO@@" '[[ -f "$FD/review/incomplete/01-review-opus.md" ]] && grep -q "@@TODO@@" "$FD/review/incomplete/01-review-opus.md"'
check "S1j. first commit is 'S: start' and the worktree is clean" '[[ "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: start" && -z "$(git -C "$WT" status --porcelain)" ]]'
check "S1k. the hook ran inside the worktree" '[[ "$(cat "$HOOK_CWD_OUT" 2>/dev/null)" == "$WT" ]]'
check "S1l. the gate ran inside the worktree" '[[ -f "$WT/self/gate-report.txt" ]]'
# The one place to coordinate from, named as a path and never as `cd <path> && claude`:
# the Next block is read by agents, and a chained cd taught there is the shape
# CONVENTIONS.md § Shell commands and the hook both refuse.
check "S1m. output names the worktree and the feature line" 'grep -q "$WT" <<<"$out" && grep -q "feature: agentTooling/$SLUG" <<<"$out"'
check "S1m2. ... without teaching a chained cd" '! grep -qE "cd [^ ]+ (&&|;)" <<<"$out"'
check "S1n. output says the stub brief must be replaced" 'grep -q "@@TODO@@" <<<"$out"'
# The review pass records the round's verdict and stops; the close is what opens the PR
# and captures on the branch, and merging it is still the last step of a feature.
check "S1n2. the Next block names the close as what opens the PR, and ends at the merge" \
  'grep -q "feature-close.sh --self $SLUG" <<<"$out" && grep -qi "merge the PR" <<<"$out"'
check "S1o. the worktree is inside the primary at R/$WORKTREES_DIR/S, and nothing is at the legacy R-S" '[[ -d "$WT" && ! -e "$AT-$SLUG" ]]'
check "S1p. info/exclude carries /$WORKTREES_DIR/ exactly once (got $(exclude_count))" '[[ "$(exclude_count)" == "1" ]]'
check "S1q. ... and the entry it already held, unterminated, is intact on a line of its own" 'grep -qxF "$KEEP_ENTRY" "$EXCLUDE"'
check "S1r. nothing tracked was touched to ignore it" '[[ -z "$(git -C "$AT" diff HEAD --name-only)" ]]'
S1_RECORD="$(routing_record "$WT" "$SLUG")"
check "S1s. a routing record for the running session is written inside the feature directory" '[[ -f "$S1_RECORD" ]]'
check "S1s2. ... and nothing is written beside the corpus at self/routing/" '[[ ! -e "$WT/self/routing" ]]'
check "S1t. ... naming this slug in features_started, and the router's own id" \
  '[[ "$(pj "$S1_RECORD" "[f[\"slug\"] for f in d[\"features_started\"]]")" == *"'"'"'$SLUG'"'"'"* && "$(pj "$S1_RECORD" "d[\"session_id\"]")" == "$PIN" ]]'
check "S1u. ... and it is part of the S: start commit" \
  'git -C "$WT" show --name-only --format= HEAD | grep -qx "self/features/$SLUG/routing.json"'

# ── S2. refusals create nothing ───────────────────────────────────────────────
before="$(branches)"
for bad in "Bad_Slug" "review/x" "-lead" "trail-" "two--dashes"; do
  start "$bad" >/dev/null 2>&1; rc=$?
  check "S2a. slug '$bad' is refused (got $rc)" '[[ $rc -ne 0 ]]'
done
check "S2b. no branch and no worktree was created for any of them" '[[ "$(branches)" == "$before" && ! -e "$(wt_path Bad_Slug)" && ! -e "$(wt_path review/x)" ]]'
start "$SLUG" >/dev/null 2>&1; rc=$?
check "S2c. a slug whose branch exists is refused (got $rc)" '[[ $rc -ne 0 ]]'
HOME="$FAKE_HOME" "$WT/feature-start.sh" --self another >/dev/null 2>&1; rc=$?
check "S2d. the copy inside a worktree refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "S2e. ... and created nothing" '[[ ! -e "$WT/$WORKTREES_DIR/another" && ! -e "$(wt_path another)" && "$(branches)" == "$before" ]]'
mkdir -p "$(wt_path lifecycle-occupied)"
start lifecycle-occupied --no-gate >/dev/null 2>&1; rc=$?
check "S2f. a slug whose worktree path is already taken is refused, creating no branch (got $rc)" '[[ $rc -ne 0 && "$(branches)" == "$before" ]]'
rmdir "$(wt_path lifecycle-occupied)"

# ── S3. options ───────────────────────────────────────────────────────────────
start lifecycle-nopin --no-pin --no-gate >/dev/null 2>&1
check "S3a. --no-pin is an accepted no-op and leaves sessions empty" '[[ "$(fence "$(wt_path lifecycle-nopin)/self/features/lifecycle-nopin/README.md" "d[\"sessions\"]")" == "[]" ]]'
start lifecycle-pin --pin --no-gate >/dev/null 2>&1
check "S3a2. --pin restores the old behaviour and pins the running session" '[[ "$(fence "$(wt_path lifecycle-pin)/self/features/lifecycle-pin/README.md" "d[\"sessions\"]")" == "['"'"'$PIN'"'"']" ]]'
start lifecycle-sess --pin --session abc-123 --no-gate >/dev/null 2>&1
check "S3b. --session with --pin pins the id given" '[[ "$(fence "$(wt_path lifecycle-sess)/self/features/lifecycle-sess/README.md" "d[\"sessions\"]")" == "['"'"'abc-123'"'"']" ]]'
start lifecycle-sess-nopin --session def-456 --no-gate >/dev/null 2>&1
check "S3b2. --session without --pin pins nothing, and names the router's record" \
  '[[ "$(fence "$(wt_path lifecycle-sess-nopin)/self/features/lifecycle-sess-nopin/README.md" "d[\"sessions\"]")" == "[]" ]] && [[ "$(pj "$(routing_record "$(wt_path lifecycle-sess-nopin)" lifecycle-sess-nopin)" "d[\"session_id\"]")" == "def-456" ]]'
start_unrouted lifecycle-noenv --no-gate >/dev/null
check "S3c. no session id in the environment means no pin" '[[ "$(fence "$(wt_path lifecycle-noenv)/self/features/lifecycle-noenv/README.md" "d[\"sessions\"]")" == "[]" ]]'
check "S3c2. ... and no routing record, there being no router to record" \
  '[[ ! -e "$(routing_record "$(wt_path lifecycle-noenv)" lifecycle-noenv)" ]]'
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

# ── S4. the prune removes merged worktrees and nothing else ───────────────────
# The whole of post-merge teardown (design 2026-09-16 §3.1): every worktree under
# .worktrees/ whose branch is an ancestor of origin/main goes, and nothing else does. The
# fixture merges two of the features above into origin/main — one left clean, one made
# dirty — and leaves lifecycle-based unmerged as the control. Both candidates are started
# unrouted (see start_unrouted).
PRUNE_CLEAN="lifecycle-merged-clean"; PRUNE_DIRTY="lifecycle-merged-dirty"
PRUNE_UNMERGED="lifecycle-based"
for slug in "$PRUNE_CLEAN" "$PRUNE_DIRTY"; do
  start_unrouted "$slug" --no-gate >/dev/null
  git -C "$AT" merge -q --no-ff -m "Merge $slug" "$slug"
done
git -C "$AT" push -q origin main 2>/dev/null
echo "work in progress" > "$(wt_path "$PRUNE_DIRTY")/uncommitted.txt"
origin_refs_before="$(origin_refs)"
out="$(start lifecycle-prunes --no-gate)"
check "S4a. the merged, clean worktree and its branch are gone" \
  '[[ ! -e "$(wt_path "$PRUNE_CLEAN")" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/$PRUNE_CLEAN"'
check "S4b. ... and the start said so" 'grep -q "$PRUNE_CLEAN" <<<"$out"'
check "S4c. the merged but dirty one is left in place, with its branch" \
  '[[ -d "$(wt_path "$PRUNE_DIRTY")" ]] && git -C "$AT" show-ref --quiet "refs/heads/$PRUNE_DIRTY"'
check "S4d. ... named in one line of its own" 'grep -q "$PRUNE_DIRTY" <<<"$out"'
check "S4e. the unmerged worktree is untouched" \
  '[[ -d "$(wt_path "$PRUNE_UNMERGED")" ]] && git -C "$AT" show-ref --quiet "refs/heads/$PRUNE_UNMERGED"'
check "S4f. the primary checkout itself is never a candidate" \
  '[[ -d "$AT" && "$(git -C "$AT" branch --show-current)" == "main" && -z "$(git -C "$AT" status --porcelain)" ]]'
check "S4g. the prune pushed nothing" '[[ "$(origin_refs)" == "$origin_refs_before" ]]'

# The merge happened on the REMOTE and the primary's own main was never pulled — the
# ordinary shape after a PR merges on the forge. The fixture reproduces it exactly as the
# real loop makes it: self/pr.sh pushes the branch with `-u`, so its upstream is
# origin/<slug>; a second clone stands in for the forge, merging into origin/main and
# deleting the remote branch; the primary's fetch (with fetch.prune, which this checkout
# sets as many real ones do) then drops the remote-tracking ref, leaving the branch with a
# dangling upstream and the primary's main behind origin/main.
#
# `git branch -d` gets this wrong: with no upstream left it re-decides "merged" against
# HEAD — the lagging local main — and refuses, which is how a worktree came to be removed
# while the output claimed its branch had gone with it. The prune already proves ancestry
# against origin/main before it deletes anything, so the delete is `git branch -D`.
PRUNE_REMOTE="lifecycle-merged-remote"
FORGE_CLONE="$TMP/forge-clone"
git -C "$AT" config fetch.prune true
start_unrouted "$PRUNE_REMOTE" --no-gate >/dev/null
git -C "$(wt_path "$PRUNE_REMOTE")" push -q -u origin "$PRUNE_REMOTE" 2>/dev/null
git clone -q "$ORIGIN" "$FORGE_CLONE" 2>/dev/null
git -C "$FORGE_CLONE" config user.email test@example.invalid
git -C "$FORGE_CLONE" config user.name "forge"
git -C "$FORGE_CLONE" merge -q --no-ff -m "Merge $PRUNE_REMOTE" "origin/$PRUNE_REMOTE"
git -C "$FORGE_CLONE" push -q origin main 2>/dev/null
git -C "$FORGE_CLONE" push -q origin --delete "$PRUNE_REMOTE" 2>/dev/null
# A primary behind origin/main is fast-forwarded and the run stops (exit 3) before
# anything is pruned or created: the process that ran is the old copy of the script. The
# rerun is the prune.
out="$(start lifecycle-prunes-remote --no-gate)"; rc=$?
check "S4h. a primary behind origin/main: main fast-forwarded, exit 3 (got $rc)" \
  '[[ $rc -eq 3 && "$(git -C "$AT" rev-parse main)" == "$(git -C "$AT" rev-parse origin/main)" ]]'
check "S4h2. ... nothing started or pruned, and the rerun command printed" \
  '[[ ! -e "$(wt_path lifecycle-prunes-remote)" && -e "$(wt_path "$PRUNE_REMOTE")" ]] && ! git -C "$AT" show-ref --quiet refs/heads/lifecycle-prunes-remote && grep -q "Run it again" <<<"$out" && grep -q -- "--self lifecycle-prunes-remote --no-gate" <<<"$out"'
out="$(start lifecycle-prunes-remote --no-gate)"; rc=$?
check "S4h3. the rerun starts the feature (got $rc)" '[[ $rc -eq 0 && -d "$(wt_path lifecycle-prunes-remote)" ]]'
check "S4i. the worktree merged only on the remote is removed" \
  '[[ ! -e "$(wt_path "$PRUNE_REMOTE")" ]]'
check "S4j. ... and its local branch is gone, though -d would have refused it" \
  '! git -C "$AT" show-ref --quiet "refs/heads/$PRUNE_REMOTE"'
check "S4k. ... and the printed line says the branch was deleted, not kept" \
  'grep -q "pruned .*$PRUNE_REMOTE and branch $PRUNE_REMOTE" <<<"$out" && ! grep -q "kept branch $PRUNE_REMOTE" <<<"$out"'
git -C "$AT" config --unset fetch.prune

# A primary that cannot simply be fast-forwarded is refused, touching nothing: one whose
# main has diverged from origin/main, and one that is behind while not on main at all.
git -C "$FORGE_CLONE" pull -q origin main 2>/dev/null
git -C "$FORGE_CLONE" commit -q --allow-empty -m "forge moves on"
git -C "$FORGE_CLONE" push -q origin main 2>/dev/null
main_before="$(git -C "$AT" rev-parse main)"
git -C "$AT" commit -q --allow-empty -m "local only"
diverged_head="$(git -C "$AT" rev-parse main)"
out="$(start lifecycle-diverged --no-gate)"; rc=$?
check "S4l. a diverged main is refused (got $rc), main and the start untouched" \
  '[[ $rc -eq 1 && "$(git -C "$AT" rev-parse main)" == "$diverged_head" && ! -e "$(wt_path lifecycle-diverged)" ]] && grep -q "diverged" <<<"$out"'
git -C "$AT" reset -q --hard "$main_before"
git -C "$AT" checkout -q -b off-main
out="$(start lifecycle-offmain --no-gate)"; rc=$?
check "S4m. behind while off main is refused (got $rc), nothing moved or started" \
  '[[ $rc -eq 1 && "$(git -C "$AT" rev-parse main)" == "$main_before" && ! -e "$(wt_path lifecycle-offmain)" ]] && grep -q "not main" <<<"$out"'
git -C "$AT" checkout -q main
git -C "$AT" branch -q -D off-main
# ... and one on main and behind whose fast-forward git itself refuses: an untracked file
# where origin/main adds one.
IN_THE_WAY="in-the-way.txt"
printf 'forge\n' > "$FORGE_CLONE/$IN_THE_WAY"
git -C "$FORGE_CLONE" add "$IN_THE_WAY"
git -C "$FORGE_CLONE" commit -q -m "forge adds a file"
git -C "$FORGE_CLONE" push -q origin main 2>/dev/null
printf 'local\n' > "$AT/$IN_THE_WAY"
out="$(start lifecycle-inway --no-gate)"; rc=$?
check "S4n. a fast-forward git refuses is refused (got $rc), nothing moved or started" \
  '[[ $rc -eq 1 && "$(git -C "$AT" rev-parse main)" == "$main_before" && ! -e "$(wt_path lifecycle-inway)" ]] && grep -q "could not fast-forward" <<<"$out"'
rm -f "$AT/$IN_THE_WAY"
# Level the primary with origin/main for the phases below, which push main from here.
git -C "$AT" merge -q --ff-only origin/main 2>/dev/null

# ── S5. --open runs the repo's hook with the worktree path ────────────────────
rm -f "$OPEN_ARG_OUT"
start lifecycle-noopen --no-gate >/dev/null 2>&1
check "S5a. a start without --open runs no session hook" '[[ ! -e "$OPEN_ARG_OUT" ]]'
start lifecycle-opens --open --no-gate >/dev/null 2>&1
check "S5b. --open runs open-session.sh with the worktree path as its only argument" \
  '[[ "$(cat "$OPEN_ARG_OUT" 2>/dev/null)" == "$(wt_path lifecycle-opens)" ]]'
check "S5c. the seeded hook never spells a chained cd as a command" \
  '! grep -E "^[[:space:]]*(cd|pushd)[[:space:]][^|;&]*(&&|;)" "$HERE/templates/plans/open-session.sh" "$HERE/self/open-session.sh"'
# The one `cd <path> && <command>` in the tree is text for Terminal.app, whose shell
# word-splits it. Unquoted, a checkout under `~/My Projects` opens the session in the
# wrong directory — and a session is billed to the branch of the directory it was
# launched in, so the mistake is silent and lands in the ledger.
#
# At template-version 3 the quoting is two named layers rather than one pair of literal
# single quotes, because a path holding `'`, `"` or `\` broke the one
# (self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §3). This is the text read; that
# the path survives BOTH layers is `self/tests/open-session.sh`, which runs the body.
SHELL_QUOTED_WORKTREE='shell_single_quote "$WORKTREE"'
APPLESCRIPT_ESCAPED_LINE='applescript_escape "$SESSION_LINE"'
BARE_QUOTED_WORKTREE="cd '\$WORKTREE'"
check "S5d. ... and both copies send the worktree path through the shell-quoting layer" \
  'grep -qF "$SHELL_QUOTED_WORKTREE" "$HERE/templates/plans/open-session.sh" && grep -qF "$SHELL_QUOTED_WORKTREE" "$HERE/self/open-session.sh"'
check "S5e. ... and through the AppleScript-escaping layer after it" \
  'grep -qF "$APPLESCRIPT_ESCAPED_LINE" "$HERE/templates/plans/open-session.sh" && grep -qF "$APPLESCRIPT_ESCAPED_LINE" "$HERE/self/open-session.sh"'
check "S5f. ... and neither still interpolates the raw path between bare single quotes" \
  '! grep -qF "$BARE_QUOTED_WORKTREE" "$HERE/templates/plans/open-session.sh" && ! grep -qF "$BARE_QUOTED_WORKTREE" "$HERE/self/open-session.sh"'

# ── S6. a --self start from a VENDORED agentTooling ───────────────────────────
# The layout every consuming repo has: agentTooling one directory inside the primary
# checkout with no .git of its own, so REPO_DIR is <primary>/agentTooling and REL_REPO is
# `agentTooling`. Every path the start commits has to carry that prefix. The feature
# directory gets it for free, by being stripped off an absolute path; the routing record
# rides inside that directory now (design 2026-09-18 §1), so the one `git add` covers it —
# where it used to be built from a label of its own, and without the prefix
# `git add self/routing/<id>.json` matched nothing, failed, and took the whole `S: start`
# commit down with it, in the one layout no scaffold exercised.
#
# Built beside the standalone scaffold rather than by rewriting it: $AT's first commit —
# the harness with its stubs, templates and analysis modules, before any start ran —
# unpacked one directory down inside a fresh consumer repo. No origin, so this start
# branches from the local main, fetches nothing and prunes nothing.
VENDOR="$TMP/consumer"
VENDOR_AT="$VENDOR/agentTooling"
VENDOR_SLUG="vendored-start"
VENDOR_WT="$VENDOR/$WORKTREES_DIR/$VENDOR_SLUG"
VENDOR_RECORD="$VENDOR_WT/agentTooling/self/features/$VENDOR_SLUG/routing.json"
mkdir -p "$VENDOR_AT"
git -C "$AT" archive "$(git -C "$AT" rev-list --max-parents=0 HEAD)" | tar -x -C "$VENDOR_AT"
printf 'a consuming repo, with agentTooling vendored one directory inside it\n' > "$VENDOR/README.md"
git -C "$VENDOR" init -q
git -C "$VENDOR" symbolic-ref HEAD refs/heads/main
git -C "$VENDOR" config user.email test@example.invalid
git -C "$VENDOR" config user.name "lifecycle test"
git -C "$VENDOR" add -A
git -C "$VENDOR" commit -q -m "init"
vendor_out="$(HOME="$FAKE_HOME" "$VENDOR_AT/feature-start.sh" --self "$VENDOR_SLUG" --no-gate 2>&1)"; rc=$?
check "S6a. a --self start from a vendored agentTooling exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "S6b. the worktree is under the CONSUMER's .worktrees/, not agentTooling's" \
  '[[ -d "$VENDOR_WT" && ! -e "$VENDOR_AT/$WORKTREES_DIR" ]]'
check "S6c. the feature directory is at agentTooling/self/features/<slug>/" \
  '[[ -f "$VENDOR_WT/agentTooling/self/features/$VENDOR_SLUG/README.md" ]]'
check "S6d. the routing record is inside the prefixed feature directory" '[[ -f "$VENDOR_RECORD" ]]'
check "S6e. ... and rides the S: start commit, which did not abort on its pathspec" \
  '[[ "$(git -C "$VENDOR_WT" log -1 --format=%s)" == "$VENDOR_SLUG: start" ]] && git -C "$VENDOR_WT" show --name-only --format= HEAD | grep -qx "agentTooling/self/features/$VENDOR_SLUG/routing.json"'
check "S6f. the start named the prefixed record in its output" \
  'grep -q "agentTooling/self/features/$VENDOR_SLUG/routing.json" <<<"$vendor_out"'
check "S6g. the worktree is clean and the consumer's primary untouched" \
  '[[ -z "$(git -C "$VENDOR_WT" status --porcelain)" && -z "$(git -C "$VENDOR" status --porcelain)" ]]'

# ── T1. a stub brief cannot run ───────────────────────────────────────────────
rm -f "$CLAUDE_CALLED_OUT"
review "$WT" "$SLUG" >/dev/null; rc=$?
check "T1a. run-review.sh over a @@TODO@@ brief exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "T1b. the brief is filed to failed/" '[[ -f "$FD/review/failed/01-review-opus.md" ]]'
check "T1c. its progress log names the marker" 'grep -q "@@TODO@@" "$FD/review/failed/01-review-opus.progress.md" 2>/dev/null'
check "T1d. claude was never called" '[[ ! -e "$CLAUDE_CALLED_OUT" ]]'
check "T1e. no PR hook ran" '! grep -q "pr create" "$GH_LOG"'
# A real brief replaces the stub, queued for T2, and the refused pass's own stamps are
# committed with it: the capture below commits cost records and nothing else, so it needs
# the build's work committed first, exactly as a real one-shot leaves it.
rm -f "$FD/review/failed/01-review-opus".*
printf '# 01 — review\n\nA real brief. Hold the diff to the manifest.\n' > "$FD/review/incomplete/01-review-opus.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m "$SLUG: review brief"

# ── C1. the capture runs on the branch, and pushes the branch ─────────────────
# The session launched in the worktree, on branch S — claimed by branch — and, in the
# primary on main, a coordinator with two delegates: one briefed for S and pinned by
# nobody, one briefed for S-two. And the router's own transcript: the session that ran
# S's start, which the capture's routing refresh re-derives the record from.
SESSION_W="wwwwwwww-0000-0000-0000-000000000002"
SESSION_M="mmmmmmmm-0000-0000-0000-000000000003"
AGENT_D="d1111111111111111"
AGENT_E="e1111111111111111"
WP="$(project_dir "$WT")"; MP="$(project_dir "$AT")"; EP="$(project_dir "/elsewhere/repo")"
mkdir -p "$WP" "$MP/$SESSION_M/subagents" "$EP"
T_C1="$(now_z)"
session_line "$SESSION_W" "$WT" "$SLUG" "msg-w" "$MODEL" "$T_C1" 100 5000 0 0 0 > "$WP/$SESSION_W.jsonl"
session_line "$SESSION_M" "$AT" "main" "msg-m" "$MODEL" "$T_C1" 100 1000 0 0 0 > "$MP/$SESSION_M.jsonl"
{
  subagent_prompt_line "$SESSION_M" "$AGENT_D" "$AT" "main" "$T_C1" "feature: agentTooling/$SLUG\\nbuild it"
  subagent_line "$SESSION_M" "$AGENT_D" "$AT" "main" "msg-d" "$MODEL" "$T_C1" 100 2000 0 0 0
} > "$MP/$SESSION_M/subagents/agent-$AGENT_D.jsonl"
{
  subagent_prompt_line "$SESSION_M" "$AGENT_E" "$AT" "main" "$T_C1" "feature: agentTooling/$SLUG-two\\nbuild the other one"
  subagent_line "$SESSION_M" "$AGENT_E" "$AT" "main" "msg-e" "$MODEL" "$T_C1" 100 2000 0 0 0
} > "$MP/$SESSION_M/subagents/agent-$AGENT_E.jsonl"
bash_tool_line "$PIN" "$AT" "main" "msg-router" "$MODEL" "$T_C1" "./feature-start.sh --self $SLUG" 100 200 \
  > "$MP/$PIN.jsonl"
echo "the build" > "$WT/work.txt"
git -C "$WT" add -A
git -C "$WT" commit -q -m "$SLUG: the build"
origin_main_before="$(git -C "$ORIGIN" rev-parse refs/heads/main)"
out="$(capture "$WT" "$SLUG")"; rc=$?
PJ="$FD/planning.json"
check "C1a. feature-capture.sh from the worktree exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C1b. it commits 'S: cost records' on the branch, over the build" \
  '[[ "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: cost records" && "$(git -C "$WT" log -1 --skip=1 --format=%s)" == "$SLUG: the build" ]]'
check "C1c. the branch is pushed: the remote's S is the worktree's HEAD" \
  '[[ "$(git -C "$ORIGIN" rev-parse "refs/heads/$SLUG" 2>/dev/null)" == "$(git -C "$WT" rev-parse HEAD)" ]]'
check "C1d. the remote's S carries planning.json, report.md, report.json and timing.jsonl" \
  'remote_has "$SLUG" planning.json report.md report.json timing.jsonl'
check "C1e. ... and the manifest with to stamped from evidence, one second past the session" \
  '[[ "$(remote_fence "$SLUG" "d[\"session_window\"][\"to\"]")" == "$(bound_after "$T_C1")" ]]'
check "C1f. the remote's main is unchanged" '[[ "$(git -C "$ORIGIN" rev-parse refs/heads/main)" == "$origin_main_before" ]]'
check "C1g. the worktree is clean and still present" '[[ -d "$WT" && -z "$(git -C "$WT" status --porcelain)" ]]'
check "C1h. the session launched in the worktree is claimed by branch, cwd recorded" \
  '[[ "$(pj "$PJ" "[(s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"]==\"$SESSION_W\"]")" == "[('"'"'branch'"'"', '"'"'$WT'"'"')]" ]]'
check "C1i. the unclaimed delegate briefed for S is a warning naming its id and the subagents pin" \
  'grep "$AGENT_D" <<<"$out" | grep -q "warn" && grep -q "\"subagents\"" <<<"$out"'
# The warning is this FEATURE's: only a delegate whose brief names S is a pin S's manifest
# is missing. The sibling briefed for S-two is somebody else's pin and is never warned
# about here — it is named once, in the corpus-wide residue below (C3c2), where it is one
# of the delegates nobody has claimed yet.
check "C1j. ... and the one briefed for S-two is never warned about" \
  '! grep "$AGENT_E" <<<"$out" | grep -q "warn"'
check "C1k. the router's routing record was refreshed from its transcript and rides the commit" \
  'git -C "$WT" show --name-only --format= HEAD | grep -qx "self/features/$SLUG/routing.json" && [[ "$(pj "$S1_RECORD" "d[\"cost_usd\"] is not None")" == "True" ]]'

# ── C3. the residue the retired sweep used to print ───────────────────────────
# The corpus-wide leftovers, printed by the capture after its own report and before its
# commit (design §3.5): the rate table's date, and every session and delegate no feature
# claims. Informational — an unclaimed session is a question for a human, never a reason
# to fail a capture that did its own job. Read from the residue section alone, since the
# commit below it names the router's record by path.
residue_of() { awk '/^=== residue ===/{f=1} /^=== commit ===/{f=0} f' <<<"$1"; }
residue="$(residue_of "$out")"
check "C3a. the capture prints a residue section with the rate table's date" \
  '[[ -n "$residue" ]] && grep -q "rates  *verified " <<<"$residue"'
check "C3b. ... an unclaimed listing naming the main session no feature claims" \
  'grep -q "$SESSION_M" <<<"$residue"'
check "C3c. ... and the delegates nobody claimed" 'grep -q "$AGENT_D" <<<"$residue"'
check "C3c2. ... including one briefed for another feature entirely — the residue is the corpus's, not this feature's" \
  'grep -q "$AGENT_E" <<<"$residue"'
check "C3d. ... while the router that started S is not listed as unclaimed — routing is its own category" \
  '! grep -q "$PIN" <<<"$residue"'
check "C3e. ... printed after what planning.json claims and before the commit" \
  '[[ "$(grep -n "=== what planning.json claims ===" <<<"$out" | head -1 | cut -d: -f1)" -lt "$(grep -n "=== residue ===" <<<"$out" | head -1 | cut -d: -f1)" ]] && [[ "$(grep -n "=== residue ===" <<<"$out" | head -1 | cut -d: -f1)" -lt "$(grep -n "=== commit ===" <<<"$out" | head -1 | cut -d: -f1)" ]]'
check "C3f. ... and an unclaimed session did not fail the capture" '[[ $rc -eq 0 ]]'

# ── C2. a second capture replaces the first ───────────────────────────────────
# More work on the branch: the session carries on an hour later. Before the merge the
# bound is provisional, so the second capture moves it LATER and rewrites the record —
# no frozen-record refusal, no "already captured" skip.
T_C2="$(shift_z "$T_C1" 3600)"
session_line "$SESSION_W" "$WT" "$SLUG" "msg-w2" "$MODEL" "$T_C2" 100 3000 0 0 0 >> "$WP/$SESSION_W.jsonl"
out="$(capture "$WT" "$SLUG")"; rc=$?
check "C2a. a second capture exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C2b. ... moving to later, onto the new last instant" \
  '[[ "$(fence "$FD/README.md" "d[\"session_window\"][\"to\"]")" == "$(bound_after "$T_C2")" ]]'
check "C2c. ... rewriting planning.json in a second cost commit" \
  '[[ "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: cost records" ]] && ! git -C "$WT" diff --quiet HEAD~1 HEAD -- "self/features/$SLUG/planning.json"'
check "C2d. ... with no refusal and no already-captured skip" '! grep -qi "already captured\|refus" <<<"$out"'
check "C2e. ... and the branch pushed again" \
  '[[ "$(git -C "$ORIGIN" rev-parse "refs/heads/$SLUG" 2>/dev/null)" == "$(git -C "$WT" rev-parse HEAD)" && -z "$(git -C "$WT" status --porcelain)" ]]'

# ── N1. no routing record, no routing talk ────────────────────────────────────
NWT="$(wt_path lifecycle-noenv)"
mkdir -p "$(project_dir "$NWT")"
session_line "nnnnnnnn-0000-0000-0000-000000000009" "$NWT" "lifecycle-noenv" "msg-n" "$MODEL" "$(now_z)" 100 500 0 0 0 \
  > "$(project_dir "$NWT")/nnnnnnnn-0000-0000-0000-000000000009.jsonl"
out="$(capture "$NWT" lifecycle-noenv)"; rc=$?
check "N1a. a feature no routing record names captures (got $rc)" '[[ $rc -eq 0 ]]'
check "N1b. ... and says nothing about routing" '! grep -qi "routing" <<<"$out"'

# ── V1. a clean review records its verdict and stops there ───────────────────
# The review pass is a runner again (design §3): it commits its own output as
# `S: review round N`, stamps the verdict and the head it judged onto plan_end, and opens
# no PR and runs no capture. The close is what does those, and the pass names it.
rm -f "$CLAUDE_CALLED_OUT"; : > "$GH_LOG"
echo "a review-pass fix" > "$WT/fixed-by-review.txt"
before="$(branches)"
V1_STEM="01-review-opus"
origin_before="$(git -C "$ORIGIN" rev-parse "refs/heads/$SLUG")"
out="$(review "$WT" "$SLUG")"; rc=$?
check "V1a. a real brief runs clean (got $rc)" '[[ $rc -eq 0 && -e "$CLAUDE_CALLED_OUT" ]]'
check "V1b. no branch was created — S is the head" '[[ "$(branches)" == "$before" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/review/$SLUG"'
check "V1c. the pass is committed as 'S: review round 1', carrying the pass's own fix" \
  '[[ "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: review round 1" ]] && git -C "$WT" show --name-only --format= HEAD | grep -qx "fixed-by-review.txt"'
check "V1d. plan_end carries verdict=clean and head=HEAD (got $(plan_end_field "$FD" "$V1_STEM" verdict) $(plan_end_field "$FD" "$V1_STEM" head))" \
  '[[ "$(plan_end_field "$FD" "$V1_STEM" verdict)" == "clean" && "$(plan_end_field "$FD" "$V1_STEM" head)" == "$(git -C "$WT" rev-parse HEAD)" ]]'
check "V1e. ... and round 1 (got $(plan_end_field "$FD" "$V1_STEM" round))" \
  '[[ "$(plan_end_field "$FD" "$V1_STEM" round)" == "1" ]]'
check "V1f. no PR was opened, nothing was pushed and no cost commit followed" \
  '! grep -q "pr create" "$GH_LOG" && [[ "$(git -C "$ORIGIN" rev-parse "refs/heads/$SLUG")" == "$origin_before" && "$(git -C "$WT" log -1 --format=%s)" == "$SLUG: review round 1" ]]'
check "V1g. the output names the close as the next step, and no PR" \
  'grep -q "feature-close.sh --self $SLUG" <<<"$out" && ! grep -q "opening PR" <<<"$out"'
check "V1h. the only path left dirty is the pass's own closing stamps (got: $(dirty_names "$WT" | tr "\n" " "))" \
  '[[ "$(dirty_names "$WT")" == "self/features/$SLUG/timing.jsonl" ]]'
TAIL="$(python3 -c "
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
last = max(i for i, e in enumerate(events) if e['event'] == 'pass_start')
tail = [e['event'] for e in events[last:]]
print(' '.join(tail[-2:]), tail.count('pass_end'), tail.count('plan_end'))
" "$FD/timing.jsonl" 2>/dev/null)"
check "V1i. the pass ends plan_end then exactly one pass_end, and one plan_end for the plan (got: $TAIL)" \
  '[[ "$TAIL" == "plan_end pass_end 1 1" ]]'

# ── T3. a mid-line marker runs, and the close's failing capture is advisory ───
# A brief that merely MENTIONS the marker — "replace `@@TODO@@` before the pass" — is not a
# stub: the refusal is anchored to a line that begins with it. This feature has no session
# to capture, so the capture the CLOSE runs refuses — reported, with the command to
# re-run, the PR left open, and the merge never requested, since the whole point of the
# ordering is that nothing asks the forge to merge before the records are pushed.
HWT="$(wt_path lifecycle-hand)"
HSTEM="$(fence "$HWT/self/features/lifecycle-hand/README.md" "d[\"plans\"][0]")"
printf '# review\n\nThe start script leaves a stub carrying `@@TODO@@`; hold the diff to the manifest.\n' \
  > "$HWT/self/features/lifecycle-hand/review/incomplete/$HSTEM.md"
git -C "$HWT" add -A
git -C "$HWT" commit -q -m "lifecycle-hand: review brief"
rm -f "$CLAUDE_CALLED_OUT"; : > "$GH_LOG"
out="$(review "$HWT" lifecycle-hand)"; rc=$?
check "T3a. a brief that mentions the marker mid-line is not a stub: it runs, and the pass exits 0 (got $rc)" '[[ $rc -eq 0 && -e "$CLAUDE_CALLED_OUT" ]]'
outh="$(PR_AUTO_MERGE=1 close "$HWT" lifecycle-hand)"; rch=$?
check "T3b. the close over a feature with nothing to capture exits non-zero (got $rch)" '[[ $rch -ne 0 ]]'
check "T3c. ... reporting the capture's failure with the exact re-run command" \
  'grep -q "feature-capture.sh --self lifecycle-hand" <<<"$outh"'
check "T3d. ... having opened the PR all the same, and never asked for the merge" \
  'grep -q "pr create" "$GH_LOG" && ! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
check "T3e. ... and the capture rolled its stamp back: to is still null" \
  '[[ "$(fence "$HWT/self/features/lifecycle-hand/README.md" "d[\"session_window\"][\"to\"]")" == "None" ]]'

# ── T4. where pr.sh opens nothing, the close still captures ───────────────────
# The review pass touches no forge at all now, and the close's pr.sh is the one thing that
# might not reach one: with the CLI present but not logged in — every repo without
# `gh auth login`, and the same for a detached HEAD or no pr.sh seeded — pr.sh takes its
# `skip` path, commits nothing and returns 0. The close carries on: the record is the
# feature's, not the PR's, and the capture must still find a tree holding nothing but cost
# records, which is why the runner commits its own pass and the close commits the stamps
# that followed it.
start_unrouted lifecycle-nogh --no-gate >/dev/null
GWT="$(wt_path lifecycle-nogh)"
GFD="$GWT/self/features/lifecycle-nogh"
GSTEM="$(fence "$GFD/README.md" "d[\"plans\"][0]")"
review_ready lifecycle-nogh "gggggggg-0000-0000-0000-000000000004"
echo "a review-pass fix nobody committed" > "$GWT/fixed-by-review.txt"
: > "$GH_LOG"; rm -f "$CLAUDE_CALLED_OUT"
out="$(review "$GWT" lifecycle-nogh)"; rc=$?
check "T4a. the review pass exits 0 and made no forge call of its own (got $rc)" \
  '[[ $rc -eq 0 && -e "$CLAUDE_CALLED_OUT" ]] && [[ ! -s "$GH_LOG" ]]'
check "T4b. the runner committed the pass itself, as round 1" \
  '[[ "$(git -C "$GWT" log -1 --format=%s)" == "lifecycle-nogh: review round 1" ]] && git -C "$GWT" show --name-only --format= HEAD | grep -qx "fixed-by-review.txt"'
outg="$(GH_AUTH_RC=1 close "$GWT" lifecycle-nogh)"; rcg=$?
check "T4c. the close over an unauthenticated forge exits 0 (got $rcg)" '[[ $rcg -eq 0 ]]'
check "T4d. pr.sh took its skip path and opened nothing" \
  'grep -q "not authenticated" <<<"$outg" && ! grep -q "pr create" "$GH_LOG"'
check "T4e. ... and the capture still committed the records over the pass" \
  '[[ "$(git -C "$GWT" log -1 --format=%s)" == "lifecycle-nogh: cost records" && -f "$GFD/planning.json" ]]'
check "T4f. ... leaving the worktree clean, with no capture refusal printed" \
  '[[ -z "$(git -C "$GWT" status --porcelain)" ]] && ! grep -q "capture exited" <<<"$outg"'

# ── P1. pr.sh on its own ──────────────────────────────────────────────────────
: > "$GH_LOG"
BWT="$(wt_path lifecycle-based)"
(
  cd "$BWT"
  echo x > dirty.txt
  FEATURE_BASE=other ./self/pr.sh lifecycle-based >/dev/null 2>&1
); rc=$?
check "P1a. FEATURE_BASE names the PR base (got $rc)" '[[ $rc -eq 0 ]] && grep -q -- "pr create --base other --head lifecycle-based" "$GH_LOG"'
check "P2a. PR_AUTO_MERGE unset: no gh pr merge call" '! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
: > "$GH_LOG"
head_before="$(git -C "$AT" rev-parse HEAD)"
(
  cd "$AT"
  echo y > dirty-main.txt
  ./self/pr.sh nothing >/dev/null 2>&1
); rc=$?
check "P1b. on the base branch pr.sh refuses (got $rc)" '[[ $rc -ne 0 ]]'
check "P1c. ... committing nothing and opening nothing" '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" ]] && ! grep -q "pr create" "$GH_LOG"'
rm -f "$AT/dirty-main.txt"
check "P1d. templates/plans/pr.sh and self/pr.sh carry the same logic" 'diff -q <(sed -n "/REPO-SPECIFIC/,\$p" "$HERE/templates/plans/pr.sh") <(sed -n "/REPO-SPECIFIC/,\$p" "$HERE/self/pr.sh") >/dev/null'
check "P1e. neither copy creates a branch" '! grep -q "checkout -b" "$HERE/templates/plans/pr.sh" && ! grep -q "checkout -b" "$HERE/self/pr.sh"'

# ── P2. PR_AUTO_MERGE lives behind --merge-request, and only there ────────────
# The merge is asked for by the CLOSE, after the capture has pushed — never by the step
# that opens the PR (design §5 step 4, template-version 4). So the open path makes no
# merge call whatever the environment says, and `--merge-request` is the second entry
# point that makes it.
: > "$GH_LOG"
(
  cd "$BWT"
  echo z >> dirty.txt
  FEATURE_BASE=other PR_AUTO_MERGE=1 "$PR_TEMPLATE" lifecycle-based >/dev/null 2>&1
); rc=$?
check "P2b. the OPEN path with PR_AUTO_MERGE=1 reaches the forge and asks for no merge (got rc $rc)" \
  '[[ $rc -eq 0 && -s "$GH_LOG" ]] && ! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
: > "$GH_LOG"
(
  cd "$BWT"
  FEATURE_BASE=other PR_AUTO_MERGE=1 "$PR_TEMPLATE" --merge-request lifecycle-based >/dev/null 2>&1
); rc=$?
check "P2b2. --merge-request with PR_AUTO_MERGE=1 makes exactly one gh pr merge --auto call (got rc $rc, $(grep -cE "$AUTO_MERGE_CALL_RE" "$GH_LOG") calls)" \
  '[[ $rc -eq 0 && "$(grep -cE "$AUTO_MERGE_CALL_RE" "$GH_LOG")" == "1" ]]'
# A merge commit, never a squash: feature-start.sh's prune and feature-capture.sh's
# post-merge path both decide "merged" by ancestry, which a squash merge never gives —
# so a squash here would strand every auto-merged feature's worktree and refuse its
# repair capture. The flag is one word in an array and nothing else asserts it.
check "P2b3. ... asking for a merge commit, never a squash" \
  'grep -qE "^pr merge .*--merge( |$)" "$GH_LOG" && ! grep -q -- "--squash" "$GH_LOG"'
check "P2b4. ... and it opened no PR of its own — the merge request is all it does" \
  '! grep -q "pr create" "$GH_LOG"'
: > "$GH_LOG"
outm="$(
  cd "$BWT"
  FEATURE_BASE=other "$PR_TEMPLATE" --merge-request lifecycle-based 2>&1
)"; rc=$?
check "P2c. --merge-request with PR_AUTO_MERGE unset exits 0, saying nothing was requested (got $rc)" \
  '[[ $rc -eq 0 ]] && grep -qi "no merge requested" <<<"$outm" && ! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
: > "$GH_LOG"
(
  cd "$BWT"
  FEATURE_BASE=other PR_AUTO_MERGE=1 ./self/pr.sh --merge-request lifecycle-based >/dev/null 2>&1
)
check "P2d. self/pr.sh never calls it, even with PR_AUTO_MERGE=1" '! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
check "P2e. both copies carry template-version 4 — the version the close's merge request needs" \
  '[[ "$(sed -n "s/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$HERE/templates/plans/pr.sh" | head -1)" == "4" ]] && [[ "$(sed -n "s/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$HERE/self/pr.sh" | head -1)" == "4" ]]'
rm -f "$BWT/dirty.txt"
git -C "$BWT" add -A
git -C "$BWT" commit -q -m "lifecycle-based: the pr.sh runs' leftovers" 2>/dev/null

# ── X1. the close refuses every tree no clean review judged ───────────────────
# The four refusals of design §5 step 1, each naming what to do. The shim is gone: this
# is the real script, and it is the only way out of a feature.
refs_before="$(origin_refs)"
: > "$GH_LOG"
outx="$(close "$AT" "$SLUG")"; rcx=$?
check "X1a. from the primary, not on the feature's branch, the close refuses (got $rcx)" \
  '[[ $rcx -ne 0 ]] && grep -q "$SLUG" <<<"$outx"'
check "X1b. ... changing nothing and opening nothing" \
  '[[ -z "$(git -C "$AT" status --porcelain)" && "$(origin_refs)" == "$refs_before" ]] && ! grep -q "pr create" "$GH_LOG"'
outx="$(close "$(wt_path lifecycle-nopin)" lifecycle-nopin)"; rcx=$?
check "X1c. a feature with no completed review is refused, naming run-review.sh (got $rcx)" \
  '[[ $rcx -ne 0 ]] && grep -q "run-review.sh" <<<"$outx"'
# The tree being closed must be the tree the review judged: a fix after the review is a
# new round, not a footnote on the old one.
echo "a fix that landed after the review" > "$WT/late-fix.txt"
git -C "$WT" add -A
git -C "$WT" commit -q -m "$SLUG: a fix nobody reviewed"
fixed_sha="$(git -C "$WT" rev-parse --short HEAD)"
: > "$GH_LOG"
outx="$(close "$WT" "$SLUG")"; rcx=$?
check "X1d. a commit with a non-harness subject after the judged head is refused, naming its sha (got $rcx)" \
  '[[ $rcx -ne 0 ]] && grep -q "$fixed_sha" <<<"$outx"'
check "X1e. ... before any PR is opened" '! grep -q "pr create" "$GH_LOG"'

# ── V2. an escalated review is a round that stops ─────────────────────────────
# Nothing after the review runs: the report becomes the rework brief in the same
# escalations/ directory the tier ladder writes into, and the next step is a new round.
start_unrouted lifecycle-escalated --no-gate >/dev/null
EWT="$(wt_path lifecycle-escalated)"
EFD="$EWT/self/features/lifecycle-escalated"
ESTEM="$(fence "$EFD/README.md" "d[\"plans\"][0]")"
review_ready lifecycle-escalated "eeeeeeee-0000-0000-0000-00000000000b"
: > "$GH_LOG"; rm -f "$CLAUDE_CALLED_OUT"
oute="$(review "$EWT" lifecycle-escalated "$VERDICT_LINE_ESCALATED")"; rce=$?
check "V2a. an escalated review pass exits 0 — a verdict is not a failure (got $rce)" \
  '[[ $rce -eq 0 && -e "$CLAUDE_CALLED_OUT" ]]'
check "V2b. plan_end carries verdict=escalated and round 1 (got $(plan_end_field "$EFD" "$ESTEM" verdict))" \
  '[[ "$(plan_end_field "$EFD" "$ESTEM" verdict)" == "escalated" && "$(plan_end_field "$EFD" "$ESTEM" round)" == "1" ]]'
check "V2c. the report is the rework brief at escalations/<stem>.md, byte for byte" \
  'cmp -s "$EWT/self/review-report.md" "$EFD/escalations/$ESTEM.md"'
check "V2d. ... and it rides the pass commit, 'lifecycle-escalated: review round 1'" \
  '[[ "$(git -C "$EWT" log -1 --format=%s)" == "lifecycle-escalated: review round 1" ]] && git -C "$EWT" show --name-only --format= HEAD | grep -qx "self/features/lifecycle-escalated/escalations/$ESTEM.md"'
check "V2e. no PR, no capture, nothing pushed" \
  '! grep -q "pr create" "$GH_LOG" && [[ ! -e "$EFD/planning.json" ]] && ! git -C "$ORIGIN" show-ref --quiet "refs/heads/lifecycle-escalated"'
check "V2f. the output names the brief's path and that a rework is a new round" \
  'grep -q "escalations/$ESTEM.md" <<<"$oute" && grep -qi "next round" <<<"$oute" && grep -q "set-plans" <<<"$oute"'
: > "$GH_LOG"
oute2="$(close "$EWT" lifecycle-escalated)"; rce2=$?
check "V2g. the close after an escalated round refuses, naming the brief (got $rce2)" \
  '[[ $rce2 -ne 0 ]] && grep -q "escalations/$ESTEM.md" <<<"$oute2" && ! grep -q "pr create" "$GH_LOG"'

# ── V3. a report with no verdict fails closed ─────────────────────────────────
# A missing or unrecognised first line is `unreadable` and is treated exactly like
# escalated, with a line saying the report carried no verdict.
start_unrouted lifecycle-noverdict --no-gate >/dev/null
NVWT="$(wt_path lifecycle-noverdict)"
NVFD="$NVWT/self/features/lifecycle-noverdict"
NVSTEM="$(fence "$NVFD/README.md" "d[\"plans\"][0]")"
review_ready lifecycle-noverdict "vvvvvvvv-0000-0000-0000-00000000000d"
: > "$GH_LOG"
outv="$(review "$NVWT" lifecycle-noverdict "")"; rcv=$?
check "V3a. a review whose report opens with no verdict line exits 0 (got $rcv)" '[[ $rcv -eq 0 ]]'
check "V3b. plan_end carries verdict=unreadable (got $(plan_end_field "$NVFD" "$NVSTEM" verdict))" \
  '[[ "$(plan_end_field "$NVFD" "$NVSTEM" verdict)" == "unreadable" ]]'
check "V3c. ... and it says the report carried no verdict" 'grep -qi "no .*verdict" <<<"$outv"'
check "V3d. treated exactly like escalated: the brief is written, no PR, no capture" \
  '[[ -f "$NVFD/escalations/$NVSTEM.md" ]] && ! grep -q "pr create" "$GH_LOG" && [[ ! -e "$NVFD/planning.json" ]]'
outv2="$(close "$NVWT" lifecycle-noverdict)"; rcv2=$?
check "V3e. and the close refuses it too (got $rcv2)" '[[ $rcv2 -ne 0 ]]'

# ── RD. a rework is a new round, and the close ends it ────────────────────────
# The measured defect, run forwards: an escalated round, a rework, a second review brief
# at a cheaper model, and a clean verdict — with every stamp of the second round carrying
# round 2, and the close the only way out.
start_unrouted lifecycle-rounds --no-gate >/dev/null
RWT="$(wt_path lifecycle-rounds)"
RFD="$RWT/self/features/lifecycle-rounds"
RSTEM1="$(fence "$RFD/README.md" "d[\"plans\"][0]")"
RSTEM2="$(printf '%02d' "$((10#${RSTEM1%%-*} + 1))")-review-sonnet"
review_ready lifecycle-rounds "rrrrrrrr-0000-0000-0000-00000000000c"
outr="$(review "$RWT" lifecycle-rounds "$VERDICT_LINE_ESCALATED")"
check "RDa. round 1 escalates, and its stamps say round 1" \
  '[[ "$(plan_end_field "$RFD" "$RSTEM1" verdict)" == "escalated" && "$(plan_end_field "$RFD" "$RSTEM1" round)" == "1" ]]'
# A by-hand stamp computes the round fresh, so a direct implementer's checkpoint stamps
# during the rework read round 2 with nobody passing anything.
HOME="$FAKE_HOME" "$RWT/stamp-timing.sh" --self lifecycle-rounds checkpoint status=implementing >/dev/null
check "RDb. a by-hand checkpoint stamp during the rework reads round 2 (got $(last_event_field "$RFD" checkpoint round))" \
  '[[ "$(last_event_field "$RFD" checkpoint round)" == "2" ]]'
echo "the rework, briefed from the escalations file" > "$RWT/rework.txt"
git -C "$RWT" add -A
git -C "$RWT" commit -q -m "lifecycle-rounds: the rework"
printf '# review\n\nRe-review, scoped to the escalations of round 1.\n' \
  > "$RFD/review/incomplete/$RSTEM2.md"
: > "$GH_LOG"
outr2="$(review "$RWT" lifecycle-rounds)"
check "RDc. the second round's plan_end carries verdict=clean and round 2 (got $(plan_end_field "$RFD" "$RSTEM2" verdict) $(plan_end_field "$RFD" "$RSTEM2" round))" \
  '[[ "$(plan_end_field "$RFD" "$RSTEM2" verdict)" == "clean" && "$(plan_end_field "$RFD" "$RSTEM2" round)" == "2" ]]'
check "RDd. ... and its pass commit is 'lifecycle-rounds: review round 2'" \
  '[[ "$(git -C "$RWT" log -1 --format=%s)" == "lifecycle-rounds: review round 2" ]]'
outr3="$(PR_AUTO_MERGE=1 close "$RWT" lifecycle-rounds)"; rcr3=$?
check "RDe. the close after a clean second round exits 0 (got $rcr3)" '[[ $rcr3 -eq 0 ]]'
check "RDf. ... opening the PR and committing the records on the branch" \
  'grep -q "pr create" "$GH_LOG" && [[ "$(git -C "$RWT" log -1 --format=%s)" == "lifecycle-rounds: cost records" && -f "$RFD/planning.json" ]]'
check "RDg. ... and under self/pr.sh no merge is ever requested, whatever PR_AUTO_MERGE says" \
  '! grep -qE "$AUTO_MERGE_CALL_RE" "$GH_LOG"'
check "RDh. the pr_opened stamp carries the round that closed (got $(last_event_field "$RFD" pr_opened round))" \
  '[[ "$(last_event_field "$RFD" pr_opened round)" == "2" ]]'

# ── X2. the close's order, and the race it closes ─────────────────────────────
# PR → pr_opened → cost records pushed → merge request, and nothing out of order: the
# origin head at the instant the forge is asked to merge already carries the cost commit,
# which is the whole of the PR_AUTO_MERGE race this feature closes by ordering.
start_unrouted lifecycle-closed --no-gate >/dev/null
XWT="$(wt_path lifecycle-closed)"
XFD="$XWT/self/features/lifecycle-closed"
XSTEM="$(fence "$XFD/README.md" "d[\"plans\"][0]")"
# The close runs the REPO-OWNED pr.sh, and auto-merge lives in the template's copy —
# self/pr.sh keeps AUTO_MERGE=0. Committed on this branch (review_ready's commit takes
# it), so the tree the close checks is clean.
cp "$PR_TEMPLATE" "$XWT/self/pr.sh"
chmod +x "$XWT/self/pr.sh"
review_ready lifecycle-closed "cccccccc-0000-0000-0000-00000000000e"
review "$XWT" lifecycle-closed >/dev/null
: > "$GH_LOG"; rm -f "$GH_MERGE_HEAD_OUT"
outx2="$(PR_AUTO_MERGE=1 close "$XWT" lifecycle-closed)"; rcx2=$?
check "X2a. the close after a clean round exits 0 (got $rcx2)" '[[ $rcx2 -eq 0 ]]'
check "X2b. pr create came before pr merge" \
  '[[ "$(grep -n "pr create" "$GH_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n "pr merge" "$GH_LOG" | head -1 | cut -d: -f1)" ]]'
check "X2c. the cost records are committed on the branch and pushed" \
  '[[ "$(git -C "$XWT" log -1 --format=%s)" == "lifecycle-closed: cost records" ]] && [[ "$(git -C "$ORIGIN" rev-parse refs/heads/lifecycle-closed)" == "$(git -C "$XWT" rev-parse HEAD)" ]]'
check "X2d. the pr_opened stamp carries the PR url and rides that commit" \
  '[[ "$(last_event_field "$XFD" pr_opened url)" == *example.invalid* ]] && git -C "$XWT" show "HEAD:self/features/lifecycle-closed/timing.jsonl" | grep -q "pr_opened"'
check "X2e. the origin head at the pr merge call already carried the cost commit" \
  '[[ -s "$GH_MERGE_HEAD_OUT" ]] && [[ "$(cat "$GH_MERGE_HEAD_OUT")" == "$(git -C "$XWT" rev-parse HEAD)" ]]'
check "X2f. exactly one merge request (got $(grep -cE "$AUTO_MERGE_CALL_RE" "$GH_LOG"))" \
  '[[ "$(grep -cE "$AUTO_MERGE_CALL_RE" "$GH_LOG")" == "1" ]]'
check "X2g. the close ends by naming the PR and saying nothing runs after the merge" \
  'grep -q "example.invalid" <<<"$outx2" && grep -qi "merge the PR" <<<"$outx2"'

# ── X3. a second close run ends at the same place ─────────────────────────────
outx3="$(PR_AUTO_MERGE=1 close "$XWT" lifecycle-closed)"; rcx3=$?
check "X3a. a second close exits 0 (got $rcx3)" '[[ $rcx3 -eq 0 ]]'
check "X3b. ... finding the PR already open, and opening no second one" \
  'grep -qi "already open" <<<"$outx3" && [[ "$(grep -c "pr create" "$GH_LOG")" == "1" ]]'
check "X3c. ... with one record, the cost commit still on top and the worktree clean" \
  '[[ "$(git -C "$XWT" log -1 --format=%s)" == "lifecycle-closed: cost records" && -f "$XFD/planning.json" && -z "$(git -C "$XWT" status --porcelain)" ]]'

# ── X4. the close refuses exactly what the capture would ─────────────────────
# One stray reader (self/features/lifecycle-records-and-numbering/README.md, slice A): the
# close's pre-PR check is `stray_paths` from plan-runner-roots.sh, admitting no sibling's
# annotation files. A half-written file INSIDE the feature directory is not a cost record,
# and it is refused HERE — before the PR — rather than by the capture after one is open.
: > "$GH_LOG"
STRAY_TMP="$XFD/NOTES.md.tmp"
: > "$STRAY_TMP"
outx4="$(close "$XWT" lifecycle-closed)"; rcx4=$?
check "X4a. an untracked non-record inside the feature directory refuses the close (got $rcx4)" \
  '[[ $rcx4 -ne 0 ]]'
check "X4b. ... naming that path" \
  'grep -q "self/features/lifecycle-closed/NOTES.md.tmp" <<<"$outx4"'
check "X4c. ... before any PR call — the forge stub logged nothing" '[[ ! -s "$GH_LOG" ]]'
check "X4d. ... and saying nothing was written and no PR was opened" \
  'grep -q "nothing was written, and no PR was opened" <<<"$outx4"'
rm -f "$STRAY_TMP"
outx4b="$(PR_AUTO_MERGE=1 close "$XWT" lifecycle-closed)"; rcx4b=$?
check "X4e. with it removed the same close exits 0 — the refusal was that path and nothing else (got $rcx4b)" \
  '[[ $rcx4b -eq 0 ]]'

# ── X5. a seeded pr.sh older than template-version 4 ─────────────────────────
# The consuming repo that has not hand-merged the version-4 edits (README.md → "Adopting
# rounds and the close"): its pr.sh has no --merge-request entry point, so the close says
# so once, naming both versions, and skips the request — the open path is never asked to
# merge, that being the race the ordering closes. The fixture is the real template with
# its version line rewritten, committed on the branch like any repo-owned hook.
start_unrouted lifecycle-pre4 --no-gate >/dev/null
P4WT="$(wt_path lifecycle-pre4)"
P4FD="$P4WT/self/features/lifecycle-pre4"
PRE4_VERSION=3
# The version whose --merge-request entry point the close needs (feature-close.sh's
# PR_MERGE_REQUEST_VERSION; P2e pins both real copies at it).
MERGE_REQUEST_VERSION=4
sed "s/^# template-version:.*/# template-version: $PRE4_VERSION/" "$PR_TEMPLATE" > "$P4WT/self/pr.sh"
chmod +x "$P4WT/self/pr.sh"
check "X5a. the fixture pr.sh reads template-version $PRE4_VERSION" \
  '[[ "$(sed -n "s/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$P4WT/self/pr.sh" | head -1)" == "$PRE4_VERSION" ]]'
review_ready lifecycle-pre4 "p4p4p4p4-0000-0000-0000-000000000011"
review "$P4WT" lifecycle-pre4 >/dev/null
: > "$GH_LOG"
outp4="$(PR_AUTO_MERGE=1 close "$P4WT" lifecycle-pre4)"; rcp4=$?
check "X5b. the close over a pre-4 pr.sh still exits 0 (got $rcp4)" '[[ $rcp4 -eq 0 ]]'
check "X5c. ... saying it skipped the merge request, naming version $PRE4_VERSION and the $MERGE_REQUEST_VERSION it needs" \
  'grep -q "template-version $PRE4_VERSION, older than $MERGE_REQUEST_VERSION" <<<"$outp4"'
check "X5d. ... calling the forge exactly once, to open the PR (got $(grep -c "pr create" "$GH_LOG") create calls)" \
  '[[ "$(grep -c "pr create" "$GH_LOG")" == "1" ]]'
check "X5e. ... and never asking for the merge" '! grep -q "pr merge" "$GH_LOG"'
check "X5f. ... with the cost records committed on the branch all the same" \
  '[[ "$(git -C "$P4WT" log -1 --format=%s)" == "lifecycle-pre4: cost records" && -f "$P4FD/planning.json" ]]'

# ── RC. the close's round comes from the stamp, not from the count ───────────
# A review whose budget cap fired AFTER it wrote its report is filed to review/failed/ with
# a complete verdict (run-review.sh → capped_after_report), so it counts toward no round:
# completed_review_count says 1 while the round that judged this tree is 2. The close reads
# `round` off the review's own plan_end, and only falls back to the count (RF).
start_unrouted lifecycle-capped --no-gate >/dev/null
CPWT="$(wt_path lifecycle-capped)"
CPFD="$CPWT/self/features/lifecycle-capped"
CPSTEM1="$(fence "$CPFD/README.md" "d[\"plans\"][0]")"
CPSTEM2="$(printf '%02d' "$((10#${CPSTEM1%%-*} + 1))")-review-sonnet"
review_ready lifecycle-capped "cpcpcpcp-0000-0000-0000-000000000012"
review "$CPWT" lifecycle-capped >/dev/null
printf '# review\n\nRound 2, re-reading the same tree.\n' > "$CPFD/review/incomplete/$CPSTEM2.md"
# The capped branch proves the report is THIS round's by comparing its content with the
# fingerprint taken before the pass (run-review.sh → report_fingerprint). The stub writes
# the same bytes every time, so round 1's report would read as unchanged; a real round 2
# never writes its predecessor's report, and removing it is how this fixture says so.
rm -f "$CPWT/self/review-report.md"
: > "$GH_LOG"
export CLAUDE_STUB_BUDGET_CAP=1
outc="$(review "$CPWT" lifecycle-capped)"; rcc=$?
unset CLAUDE_STUB_BUDGET_CAP
check "RCa. a review capped after its report exits non-zero (got $rcc)" '[[ $rcc -ne 0 ]]'
check "RCb. ... filed to review/failed/, with round 1's plan still the only one complete" \
  '[[ -f "$CPFD/review/failed/$CPSTEM2.md" && -f "$CPFD/review/complete/$CPSTEM1.md" ]] && [[ "$(ls "$CPFD/review/complete"/[0-9]*.md | grep -vc "progress")" == "1" ]]'
check "RCc. ... stamping verdict=clean, round=2 and the head it judged (got $(plan_end_field "$CPFD" "$CPSTEM2" verdict) round $(plan_end_field "$CPFD" "$CPSTEM2" round))" \
  '[[ "$(plan_end_field "$CPFD" "$CPSTEM2" verdict)" == "clean" && "$(plan_end_field "$CPFD" "$CPSTEM2" round)" == "2" && "$(plan_end_field "$CPFD" "$CPSTEM2" head)" == "$(git -C "$CPWT" rev-parse HEAD)" ]]'
outc2="$(close "$CPWT" lifecycle-capped)"; rcc2=$?
check "RCd. the close over that round exits 0 (got $rcc2)" '[[ $rcc2 -eq 0 ]]'
check "RCe. ... naming round 2 in its banner, not the completed count of 1" \
  'grep -q "round     2 of .lifecycle-capped." <<<"$outc2"'
check "RCf. ... and stamping pr_opened with round 2 (got $(last_event_field "$CPFD" pr_opened round))" \
  '[[ "$(last_event_field "$CPFD" pr_opened round)" == "2" ]]'

# ── RF. ... falling back to the count for a stamp written before rounds ──────
# A timing.jsonl from before every line carried its round: the close has nothing to read,
# and completed_review_count is the answer it had. Here that is 1 — the round-2 plan is in
# failed/ — so the fallback is visible as a different number from RC's.
python3 - "$CPFD/timing.jsonl" <<'PY'
import json, sys
path = sys.argv[1]
out = []
for line in open(path):
    line = line.strip()
    if not line:
        continue
    event = json.loads(line)
    if event.get("event") == "plan_end":
        event.pop("round", None)
    out.append(json.dumps(event))
open(path, "w").write("\n".join(out) + "\n")
PY
outc3="$(close "$CPWT" lifecycle-capped)"; rcc3=$?
check "RFa. a close whose plan_end carries no round still exits 0 (got $rcc3)" '[[ $rcc3 -eq 0 ]]'
check "RFb. ... falling back to the completed-review count, which is 1 here" \
  'grep -q "round     1 of .lifecycle-capped." <<<"$outc3"'
check "RFc. ... and stamping pr_opened with that round (got $(last_event_field "$CPFD" pr_opened round))" \
  '[[ "$(last_event_field "$CPFD" pr_opened round)" == "1" ]]'

# ── B1/B2. the batch ends a round the way the close does ──────────────────────
# Runners are runners: the batch reads the verdict exactly as the close does, and either
# calls the close or names the brief and stops. Its build and verify queues are empty
# here, which is a clean no-op, so what runs is the review pass and what follows it.
start_unrouted lifecycle-batch --no-gate >/dev/null
BBWT="$(wt_path lifecycle-batch)"
BBFD="$BBWT/self/features/lifecycle-batch"
review_ready lifecycle-batch "aaaaaaaa-0000-0000-0000-00000000000f"
: > "$GH_LOG"
outb="$(batch "$BBWT" lifecycle-batch)"; rcb=$?
check "B1a. a batch whose review is clean exits 0 (got $rcb)" '[[ $rcb -eq 0 ]]'
check "B1b. ... calling the close: the PR is opened" 'grep -q "pr create" "$GH_LOG"'
# The subject match is a string test and not `git log | grep -q`: this file runs under
# `set -o pipefail`, and a `grep -q` that exits on the first match leaves git dead of
# SIGPIPE, which pipefail then reports as a failed pipeline.
check "B1b2. ... and the cost record is written and committed on the branch (HEAD: $(git -C "$BBWT" log -1 --format=%s 2>&1))" \
  '[[ -f "$BBFD/planning.json" ]] && [[ "$(git -C "$BBWT" log --format=%s)" == *"lifecycle-batch: cost records"* ]]'
check "B1c. ... and saying so" 'grep -q "feature-close.sh" <<<"$outb"'
start_unrouted lifecycle-batch-red --no-gate >/dev/null
RBWT="$(wt_path lifecycle-batch-red)"
RBFD="$RBWT/self/features/lifecycle-batch-red"
RBSTEM="$(fence "$RBFD/README.md" "d[\"plans\"][0]")"
review_ready lifecycle-batch-red "fafafafa-0000-0000-0000-000000000010"
: > "$GH_LOG"
outb2="$(batch "$RBWT" lifecycle-batch-red "$VERDICT_LINE_ESCALATED")"; rcb2=$?
check "B2a. a batch whose review escalates exits 1 (got $rcb2)" '[[ $rcb2 -eq 1 ]]'
check "B2b. ... opening no PR and capturing nothing" \
  '! grep -q "pr create" "$GH_LOG" && [[ ! -e "$RBFD/planning.json" ]]'
check "B2c. ... and naming the rework brief" 'grep -q "escalations/$RBSTEM.md" <<<"$outb2"'

# ── M1. merge, then the next start prunes ─────────────────────────────────────
git -C "$AT" merge -q --no-ff -m "Merge $SLUG" "$SLUG"
git -C "$AT" push -q origin main 2>/dev/null
refs_before="$(origin_refs)"
out="$(start_unrouted lifecycle-after-merge --no-gate)"
check "M1a. the start after the merge removed S's worktree and local branch" \
  '[[ ! -e "$WT" ]] && ! git -C "$AT" show-ref --quiet "refs/heads/$SLUG"'
check "M1b. ... saying so" 'grep -q "pruned .*$SLUG" <<<"$out"'
check "M1c. ... and pushed nothing" '[[ "$(origin_refs)" == "$refs_before" ]]'

# ── MR. two features, one router, merged in turn ──────────────────────────────
# The defect the per-feature record closes (design 2026-09-18 §1). Under
# `<corpus>/routing/<session-id>.json`, two features one router starts before either
# merges each ADD that one path with different content, and the second merge is an add/add
# conflict a human resolves by hand — which is what happened to `policy-module` on
# 2026-09-18. The second start below happens BEFORE the first merges, and that is the
# whole fixture: started after, `main` already carries the file and every later branch
# merely modifies it.
MR_ROUTER="rrrrrrrr-0000-0000-0000-000000000010"
MR_A="routing-merge-one"
MR_B="routing-merge-two"
T_MR="$(now_z)"
report_all() { ( cd "$TMP" && HOME="$FAKE_HOME" python3 -B "$AT/analysis/report.py" --self --all 2>&1 ); }
bash_tool_line "$MR_ROUTER" "$AT" "main" "msg-mr1" "$MODEL" "$T_MR" \
  "./feature-start.sh --self $MR_A" 100 200 > "$MP/$MR_ROUTER.jsonl"
start_as "$MR_ROUTER" "$MR_A" --no-gate >/dev/null
# The router grows between the two starts — its first start has reached the transcript by
# the time it opens the second — so the two records differ in `features_started` and in
# `captured_at`. That difference is exactly what made the two sides conflict, and what
# `load_records` now resolves by keeping the later capture.
bash_tool_line "$MR_ROUTER" "$AT" "main" "msg-mr2" "$MODEL" "$(shift_z "$T_MR" 600)" \
  "./feature-start.sh --self $MR_B" 100 200 >> "$MP/$MR_ROUTER.jsonl"
start_as "$MR_ROUTER" "$MR_B" --no-gate >/dev/null
MR_A_REC="$(routing_record "$(wt_path "$MR_A")" "$MR_A")"
MR_B_REC="$(routing_record "$(wt_path "$MR_B")" "$MR_B")"
check "MRa. each feature carries its own copy of the one router's record" \
  '[[ -f "$MR_A_REC" && -f "$MR_B_REC" ]]'
check "MRb. ... and the two copies differ, as the two conflicting sides did" \
  '! cmp -s "$MR_A_REC" "$MR_B_REC"'
git -C "$AT" merge -q --no-ff -m "Merge $MR_A" "$MR_A" >/dev/null 2>&1; rc=$?
check "MRc. the first feature merges into main (got $rc)" '[[ $rc -eq 0 ]]'
mr_out="$(git -C "$AT" merge --no-ff -m "Merge $MR_B" "$MR_B" 2>&1)"; rc=$?
check "MRd. the SECOND merges too, with no conflict and no hand resolution (got $rc)" \
  '[[ $rc -eq 0 ]] && ! grep -qi "conflict" <<<"$mr_out" && [[ -z "$(git -C "$AT" ls-files --unmerged)" ]]'
check "MRe. main carries both records, one inside each feature directory" \
  'git -C "$AT" cat-file -e "HEAD:self/features/$MR_A/routing.json" 2>/dev/null && git -C "$AT" cat-file -e "HEAD:self/features/$MR_B/routing.json" 2>/dev/null'
mr_table="$(report_all | awk '/Routing overhead/{f=1} f')"
check "MRf. the Routing table holds exactly one row for that router (got $(grep -c "| $MR_ROUTER |" <<<"$mr_table"))" \
  '[[ "$(grep -c "| $MR_ROUTER |" <<<"$mr_table")" == "1" ]]'
check "MRg. ... naming both features it started — the later capture is the superset" \
  'grep "| $MR_ROUTER |" <<<"$mr_table" | grep -q "$MR_A" && grep "| $MR_ROUTER |" <<<"$mr_table" | grep -q "$MR_B"'

# ── T5. on the base branch itself the runner commits nothing ──────────────────
# The complement of T4. The runner's own commit is gated on being on a branch that is not
# this feature's base: on `main` there is no feature branch to commit to, and committing
# the primary's work in progress is the one thing the branch rule exists to prevent. The
# runner says so itself now — there is no pr.sh call in this pass to say it for it.
: > "$GH_LOG"
printf '# review\n\nA real brief run from the primary. Hold the diff to the manifest.\n' \
  > "$AT/self/features/$SLUG/review/incomplete/99-review-opus.md"
echo "work in progress in the primary" > "$AT/scratch.txt"
head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(review "$AT" "$SLUG")"
check "T5a. a review run from the primary on main commits nothing" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" ]]'
check "T5b. ... saying it is on the feature's base and left the output uncommitted" \
  'grep -q "this feature.s base" <<<"$out"'
check "T5c. ... leaving the work in progress uncommitted where it was" \
  '[[ -f "$AT/scratch.txt" ]] && git -C "$AT" status --porcelain | grep -q "scratch.txt"'
check "T5d. ... and touching no forge and no capture" \
  '! grep -q "pr create" "$GH_LOG" && ! grep -q "=== capture" <<<"$out"'
rm -f "$AT/scratch.txt"
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUG: the base-branch run's local records" 2>/dev/null

# ── R1. --recapture after the merge: tighten only, write locally, push nothing ─
MANIFEST_ONE="$AT/self/features/$SLUG/README.md"
T_R="$(shift_z "$T_C2" 3600)"
session_line "$SESSION_W" "$WT" "$SLUG" "msg-w3" "$MODEL" "$T_R" 100 1000 0 0 0 >> "$WP/$SESSION_W.jsonl"
to_before="$(fence "$MANIFEST_ONE" "d[\"session_window\"][\"to\"]")"
refs_before="$(origin_refs)"; head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(capture "$AT" "$SLUG" --recapture)"; rc=$?
check "R1a. --recapture from the primary after the merge exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R1b. ... refusing to widen: the manifest's to is unchanged ($to_before)" \
  '[[ -n "$to_before" && "$(fence "$MANIFEST_ONE" "d[\"session_window\"][\"to\"]")" == "$to_before" ]] && grep -q "never widened" <<<"$out"'
check "R1c. ... committing nothing and pushing nothing" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && "$(origin_refs)" == "$refs_before" ]]'
LATE_BOUND="2030-01-01T00:00:00Z"
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
set_bound "$MANIFEST_ONE" to "$LATE_BOUND"
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUG: a bound stamped too late, and the repair's local records"
refs_before="$(origin_refs)"; head_before="$(git -C "$AT" rev-parse HEAD)"
out="$(capture "$AT" "$SLUG" --recapture)"; rc=$?
check "R1d. an earlier bound tightens (got $rc): $LATE_BOUND -> the evidence" \
  '[[ $rc -eq 0 ]] && grep -q "$LATE_BOUND -> $(bound_after "$T_R")" <<<"$out" && [[ "$(fence "$MANIFEST_ONE" "d[\"session_window\"][\"to\"]")" == "$(bound_after "$T_R")" ]]'
check "R1e. ... written locally: nothing committed, the remote's refs byte-identical" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && "$(origin_refs)" == "$refs_before" && -n "$(git -C "$AT" status --porcelain)" ]]'
check "R1f. ... and it says the human opens the PR" 'grep -qi "open a PR" <<<"$out"'
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUG: the repair's records"

# ── L1. merged under the old flow, never closed: capture from the primary ─────
# A feature started before the lifecycle restructure, in the legacy sibling layout R-S,
# merged, and never captured — the shape consuming repos have in flight today.
SLUGL="lifecycle-legacy"; LWT="$AT-$SLUGL"
start_unrouted "$SLUGL" --no-gate >/dev/null
git -C "$AT" worktree move "$(wt_path "$SLUGL")" "$LWT"
git -C "$AT" merge -q --no-ff -m "Merge $SLUGL" "$SLUGL"
git -C "$AT" push -q origin main 2>/dev/null
SESSION_L="llllllll-0000-0000-0000-000000000008"
mkdir -p "$(project_dir "$LWT")"
session_line "$SESSION_L" "$LWT" "$SLUGL" "msg-l" "$MODEL" "$(now_z)" 100 5000 0 0 0 \
  > "$(project_dir "$LWT")/$SESSION_L.jsonl"
check "L0. the fixture's premise: branch S is checked out at the legacy R-S, merged, never captured" \
  '[[ -d "$LWT" && ! -e "$(wt_path "$SLUGL")" && ! -e "$AT/self/features/$SLUGL/planning.json" ]]'
refs_before="$(origin_refs)"; head_before="$(git -C "$AT" rev-parse HEAD)"
outl="$(capture "$AT" "$SLUGL")"; rcl=$?
PJL="$AT/self/features/$SLUGL/planning.json"
check "L1a. a merged, never-captured legacy feature captures from the primary (got $rcl)" '[[ $rcl -eq 0 ]]'
check "L1b. ... claiming the session launched in R-S by branch, cwd recorded" \
  '[[ "$(pj "$PJL" "[(s[\"selected_by\"], s[\"cwd\"]) for s in d[\"sessions\"] if s[\"session_id\"]==\"$SESSION_L\"]")" == "[('"'"'branch'"'"', '"'"'$LWT'"'"')]" ]]'
check "L1c. ... stamping to" '[[ "$(fence "$AT/self/features/$SLUGL/README.md" "d[\"session_window\"][\"to\"]")" != "None" ]]'
check "L1d. ... locally: nothing committed and nothing pushed" \
  '[[ "$(git -C "$AT" rev-parse HEAD)" == "$head_before" && "$(origin_refs)" == "$refs_before" ]] && grep -qi "nothing committed" <<<"$outl"'
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUGL: the legacy capture's records"

# ── C4. a stale rate table is news, not a refusal ─────────────────────────────
# The other half of the residue. Every dollar the capture just printed is tokens times
# that table, so its age belongs beside the numbers — and a table nobody has re-checked
# must not stop a feature being captured while its transcripts still exist. Run against
# the primary's copy, where the capture commits nothing, so the edit below cannot reach a
# cost commit.
cp "$AT/analysis/pricing.py" "$TMP/pricing.py.before"
python3 - "$AT/analysis/pricing.py" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(r'^RATES_VERIFIED = "[^"]*"', 'RATES_VERIFIED = "2000-01-01"', text, count=1, flags=re.M)
assert n == 1, "no RATES_VERIFIED assignment in %s" % path
open(path, "w").write(text)
PY
outs="$(capture "$AT" "$SLUGL")"; rcs=$?
check "C4a. a capture over a stale rate table still exits 0 (got $rcs)" '[[ $rcs -eq 0 ]]'
check "C4b. ... warning in the residue that the table needs re-checking" \
  'grep -q "rate table is stale" <<<"$(residue_of "$outs")"'
cp "$TMP/pricing.py.before" "$AT/analysis/pricing.py"
# That run rewrote the legacy feature's report locally, as every post-merge capture does.
# Commit it: the starts below refuse a primary with work in progress in it.
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUGL: the stale-table run's records" 2>/dev/null

# ── W. session_window.to is stamped from evidence, before the capture ─────────
# All three features are started before any of them merges: every start prunes the
# merged worktrees, and W1–W7 run inside theirs.
SLUGW="lifecycle-window"; WTW="$(wt_path "$SLUGW")"
SLUGN="lifecycle-nobranch"; WTN="$(wt_path "$SLUGN")"
PIN_N="nbnbnbnb-0000-0000-0000-000000000006"
SLUGK="lifecycle-nokey"; WTK="$(wt_path "$SLUGK")"
start_unrouted "$SLUGW" --no-gate >/dev/null
# --pin as well as --session: pinning is opt-in now (S1h), and W2's whole premise is a
# feature whose only claimed session is a pinned one off the branch.
start "$SLUGN" --no-gate --pin --session "$PIN_N" >/dev/null 2>&1
start_unrouted "$SLUGK" --no-gate >/dev/null
MW_WT="$WTW/self/features/$SLUGW/README.md"

# W1. The window's `from` moves back to a fixed instant, so a session hours in the past is
# inside it. The session opens at 12:00 and its last line is at 12:45; its DELEGATE runs
# on to 13:00 — the ordinary shape of a build, an implementer outliving its coordinator's
# last line. The two instants that decide the bound carry `.700`, so the bound is also
# evidence that the whole-second truncation happened. The middle line at 12:45 is what W6
# needs: the only line that can put a hand-written bound between a selected session's
# start and its end.
set_bound "$MW_WT" from "2026-06-01T00:00:00Z"
git -C "$WTW" commit -q -am "$SLUGW: an earlier window"
SESSION_WIN="wnwnwnwn-0000-0000-0000-000000000005"
AGENT_WIN="a1111111111111115"
mkdir -p "$(project_dir "$WTW")/$SESSION_WIN/subagents"
{
  session_line "$SESSION_WIN" "$WTW" "$SLUGW" "msg-w1" "$MODEL" "2026-06-01T12:00:00.700Z" 100 5000 0 0 0
  session_line "$SESSION_WIN" "$WTW" "$SLUGW" "msg-w1b" "$MODEL" "2026-06-01T12:45:00.000Z" 100 1000 0 0 0
} > "$(project_dir "$WTW")/$SESSION_WIN.jsonl"
subagent_line "$SESSION_WIN" "$AGENT_WIN" "$WTW" "$SLUGW" "msg-w1a" "$MODEL" "2026-06-01T13:00:00.700Z" 100 2000 0 0 0 \
  > "$(project_dir "$WTW")/$SESSION_WIN/subagents/agent-$AGENT_WIN.jsonl"
outw="$(capture "$WTW" "$SLUGW")"; rcw=$?
to_w="$(fence "$MW_WT" "d[\"session_window\"][\"to\"]")"
check "W1a. a capture whose branch session ended hours ago exits 0 (got $rcw)" '[[ $rcw -eq 0 ]]'
check "W1b. session_window.to is one second past the last instant of the session's DELEGATE, not of the session or of the capture's clock (got $to_w)" '[[ "$to_w" == "2026-06-01T13:00:01Z" ]]'
check "W1c. ... and the session and delegate it was derived from are both still captured — the bound is exclusive" '[[ "$(pj "$WTW/self/features/$SLUGW/planning.json" "[s[\"session_id\"] for s in d[\"sessions\"]]")" == "['"'"'$SESSION_WIN'"'"']" && "$(pj "$WTW/self/features/$SLUGW/planning.json" "[a[\"agent_id\"] for a in d[\"subagents\"]]")" == "['"'"'$AGENT_WIN'"'"']" ]]'
check "W1d. ... and the bound is at second resolution though the evidence carried milliseconds" '[[ "$to_w" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]'

# W7. Before the merge `to` is provisional, and it moves either way: C2 moved it later;
# here a bound written by hand LATER than the evidence is brought back onto it.
set_bound "$MW_WT" to "2026-06-02T00:00:00Z"
git -C "$WTW" commit -q -am "$SLUGW: a bound past the evidence"
out7="$(capture "$WTW" "$SLUGW")"; rc7=$?
check "W7a. before the merge a later hand-written to is moved EARLIER onto the evidence (got $rc7)" \
  '[[ $rc7 -eq 0 && "$(fence "$MW_WT" "d[\"session_window\"][\"to\"]")" == "2026-06-01T13:00:01Z" ]] && grep -q "2026-06-02T00:00:00Z -> 2026-06-01T13:00:01Z" <<<"$out7"'

# W2. No branch session at all: the pinned session is off the branch and in another
# checkout, so it is claimed by id and is not evidence of when work on the branch
# stopped. The capture falls back to its own clock and announces it.
session_line "$PIN_N" "/elsewhere/repo" "main" "msg-n" "$MODEL" "2026-02-02T00:00:00.000Z" 100 3000 0 0 0 \
  > "$EP/$PIN_N.jsonl"
before_z="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
outn="$(capture "$WTN" "$SLUGN")"; rcn=$?
to_n="$(fence "$WTN/self/features/$SLUGN/README.md" "d[\"session_window\"][\"to\"]")"
check "W2a. a feature whose only session is pinned off the branch captures 0 (got $rcn)" '[[ $rcn -eq 0 ]]'
check "W2b. ... announcing that to was stamped at capture time" 'grep -q "no branch session — to stamped at capture time" <<<"$outn"'
check "W2c. ... with to at this run's clock, not the pinned session's instant (got $to_n)" '[[ "$to_n" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && [[ ! "$to_n" < "$before_z" ]]'

# W5. A stamp that fails for any other reason stops the capture. `set-window-to` exits
# non-zero for several reasons, and only the refused widen (post-merge, W6) is the
# capture's business to continue past. A fence with no `to` key at all leaves the window
# OPEN on a feature about to be captured and pushed; the capture refuses, names what
# set-window-to printed rather than a cause that did not happen, and writes nothing.
python3 - "$WTK/self/features/$SLUGK/README.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
match = list(re.finditer(r"```json\n(.*?)\n```", text, re.S))[-1]
fence, n = re.subn(r',\s*"to":\s*(?:"[^"]*"|null)', "", match.group(1), count=1)
assert n == 1, "no `to` bound to drop from %s" % path
open(path, "w").write(text[: match.start(1)] + fence + text[match.end(1):])
PY
git -C "$WTK" commit -q -am "$SLUGK: a fence with no to bound"
# A real branch session, so the capture this run never reaches WOULD have succeeded:
# without it the capture would refuse for matching nothing and W5a would pass whatever the
# stamp did.
SESSION_K="kkkkkkkk-0000-0000-0000-000000000007"
mkdir -p "$(project_dir "$WTK")"
session_line "$SESSION_K" "$WTK" "$SLUGK" "msg-k" "$MODEL" "$(now_z)" 100 5000 0 0 0 \
  > "$(project_dir "$WTK")/$SESSION_K.jsonl"
k_head="$(git -C "$WTK" rev-parse HEAD)"
outk="$(capture "$WTK" "$SLUGK")"; rck=$?
check "W5a. a capture whose stamp fails for anything but a refused widen exits non-zero (got $rck)" '[[ $rck -ne 0 ]]'
check "W5b. ... naming what set-window-to printed, not the widen refusal that did not happen" 'grep -q "bound in the fence" <<<"$outk" && ! grep -q "never widened" <<<"$outk"'
check "W5c. ... writing no planning.json — the capture was never reached" '[[ ! -e "$WTK/self/features/$SLUGK/planning.json" ]]'
check "W5d. ... and committing nothing, leaving the worktree clean" '[[ -z "$(git -C "$WTK" status --porcelain)" && "$(git -C "$WTK" rev-parse HEAD)" == "$k_head" ]]'

# Merge the window feature: W3, W4 and W6 are the post-merge repair path, run from the
# primary's copy against the manifest main now carries.
git -C "$AT" merge -q --no-ff -m "Merge $SLUGW" "$SLUGW"
git -C "$AT" push -q origin main 2>/dev/null
MW="$AT/self/features/$SLUGW/README.md"

# W3. The repair path for a `to` stamped too late: --recapture re-derives the evidence and
# TIGHTENS the bound onto it.
set_bound "$MW" to "2026-06-02T00:00:00Z"
git -C "$AT" commit -q -am "$SLUGW: a bound stamped too late"
outt="$(capture "$AT" "$SLUGW" --recapture)"; rct=$?
check "W3a. --recapture over a to later than the evidence exits 0 (got $rct)" '[[ $rct -eq 0 ]]'
check "W3b. ... printing old -> new" 'grep -q "2026-06-02T00:00:00Z -> 2026-06-01T13:00:01Z" <<<"$outt"'
check "W3c. ... and the fence carries the tightened bound" '[[ "$(fence "$MW" "d[\"session_window\"][\"to\"]")" == "2026-06-01T13:00:01Z" ]]'
git -C "$AT" add -A
git -C "$AT" commit -q -m "$SLUGW: the repair's records"

# W4. A bound is never widened, by any path, and it is never written at or before its own
# `from` either. The refusal must name both instants: with --tighten unimplemented,
# argparse also exits non-zero, so exit code alone is vacuous — and the two refusals carry
# DIFFERENT codes, because feature-capture.sh continues past exactly one of them (W6).
cp "$MW" "$TMP/window-manifest.before"
outr="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2027-01-01T00:00:00Z 2>&1)"; rcr=$?
check "W4a. set-window-to --tighten refuses a later instant, with the widen refusal's own exit code (got $rcr, want 3)" '[[ $rcr -eq 3 ]]'
check "W4b. ... naming the bound it holds and the one it was offered" 'grep -q "2026-06-01T13:00:01Z" <<<"$outr" && grep -q "2027-01-01T00:00:00Z" <<<"$outr"'
check "W4c. ... and leaving the fence byte-identical" 'cmp -s "$TMP/window-manifest.before" "$MW"'
# The bound it already carries is a no-op, not a refusal: every repair run re-derives the
# same evidence (recover-at-close.sh C12).
oute="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-06-01T13:00:01Z 2>&1)"; rce=$?
check "W4d. ... while the bound it already carries is a no-op, exit 0 (got $rce)" '[[ $rce -eq 0 ]] && cmp -s "$TMP/window-manifest.before" "$MW"'
# The other end of the same fence. Tightening is inwards, and far enough inwards is an
# EMPTY window: `is_empty_window` drops such a claim from every other feature's split, so
# the feature would own nothing and only a WARN at the next capture would say so. It is a
# plain failure, not the widen refusal — the capture must stop on it — and it is
# unreachable from evidence, since a branch-selected session starts at or after `from`.
outf="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-05-31T23:00:00Z 2>&1)"; rcf=$?
check "W4e. ... and refuses a bound BEFORE the fence's from, as a plain failure not the widen code (got $rcf, want 1)" '[[ $rcf -eq 1 ]]'
check "W4f. ... naming the from it holds and the bound it was offered" 'grep -q "2026-06-01T00:00:00Z" <<<"$outf" && grep -q "2026-05-31T23:00:00Z" <<<"$outf"'
check "W4g. ... and leaving the fence byte-identical" 'cmp -s "$TMP/window-manifest.before" "$MW"'
outb="$(python3 -B "$AT/analysis/manifest.py" --self "$SLUGW" set-window-to --tighten 2026-06-01T00:00:00Z 2>&1)"; rcb=$?
check "W4h. ... and a bound exactly AT from is refused too — an empty window owns nothing (got $rcb)" '[[ $rcb -eq 1 ]] && cmp -s "$TMP/window-manifest.before" "$MW"'
check "W4i. ... and none of the four refusals dirtied the primary" '[[ -z "$(git -C "$AT" status --porcelain)" ]]'

# ── W6. ... and the one code the capture does continue past ───────────────────
# The complement of W5: the tolerated code is written down TWICE — WIDEN_REFUSED_EXIT in
# manifest.py, WIDEN_REFUSED_RC in feature-capture.sh, since bash cannot import it — so
# nothing but an assertion keeps the two in step, and a drift would turn every declined
# widen into a refused capture. Move the bound EARLIER than its evidence by hand, so
# --recapture's tighten would have to widen it: the capture must warn, capture anyway, and
# leave the published bound exactly where it found it.
set_bound "$MW" to "2026-06-01T12:30:00Z"
git -C "$AT" commit -q -am "$SLUGW: a bound tighter than the evidence"
outv="$(capture "$AT" "$SLUGW" --recapture)"; rcv=$?
check "W6a. --recapture whose evidence would WIDEN the bound still captures, exit 0 (got $rcv)" '[[ $rcv -eq 0 ]]'
check "W6b. ... warning that the bound was left as it is" 'grep -q "never widened" <<<"$outv"'
check "W6c. ... and leaving the published bound untouched" '[[ "$(fence "$MW" "d[\"session_window\"][\"to\"]")" == "2026-06-01T12:30:00Z" ]]'

# ── A1. the frozen-record annotation runs at capture ──────────────────────────
# What the retired sweep's `capture_planning.py --all` used to do (design §3.5): a
# feature frozen BEFORE another feature claimed the same session could never say so. The
# capture now refreshes `sessions[].also_claimed_by` on every frozen record in the corpus
# it can see — a ledger read, no transcript opened, no figure touched — and regenerates
# the report that renders it. Scoped to this checkout's corpus, which on a branch is the
# records merged into it: two features sharing one session, the second capturing after
# the first has merged.
SLUG_ONE="lifecycle-share-one"; SLUG_TWO="lifecycle-share-two"
SHARED="shshshsh-0000-0000-0000-00000000000a"
# set_pin <manifest> <session-id> — pin one session id into the fence's `sessions` array,
# which is how a session neither feature's branch selects is claimed by both.
set_pin() {
  python3 - "$1" "$2" <<'PY'
import json, re, sys
path, session = sys.argv[1], sys.argv[2]
text = open(path).read()
match = list(re.finditer(r"```json\n(.*?)\n```", text, re.S))[-1]
fence, n = re.subn(r'("sessions"\s*:\s*)\[[^]]*\]',
                   lambda m: m.group(1) + json.dumps([session]), match.group(1), count=1)
assert n == 1, "no `sessions` array in the fence of %s" % path
open(path, "w").write(text[: match.start(1)] + fence + text[match.end(1):])
PY
}
# record_but_annotation <planning.json> — the record with every `also_claimed_by` dropped:
# the part the annotation must leave exactly as it found it.
record_but_annotation() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for s in d.get('sessions') or []:
    s.pop('also_claimed_by', None)
print(json.dumps(d, sort_keys=True))" "$1" 2>/dev/null
}

# The shared session runs at a FIXED instant, and both features' `from` is moved back
# behind it: a window is what decides a shared session's split, and a fixture whose
# instant is "now" lands before the second feature's `from` — which a start stamps when it
# runs — so the second capture would claim nothing of it and the annotation under test
# would depend on how long this file takes to get here.
SHARED_AT="2026-06-01T12:00:00.700Z"
SHARED_WINDOW_FROM="2026-06-01T00:00:00Z"
session_line "$SHARED" "/elsewhere/repo" "main" "msg-share" "$MODEL" "$SHARED_AT" 100 6000 0 0 0 \
  > "$EP/$SHARED.jsonl"

start_unrouted "$SLUG_ONE" --no-gate >/dev/null
WT_ONE="$(wt_path "$SLUG_ONE")"
set_pin "$WT_ONE/self/features/$SLUG_ONE/README.md" "$SHARED"
set_bound "$WT_ONE/self/features/$SLUG_ONE/README.md" from "$SHARED_WINDOW_FROM"
git -C "$WT_ONE" commit -q -am "$SLUG_ONE: pin the shared session"
out="$(capture "$WT_ONE" "$SLUG_ONE")"; rc=$?
check "A1a. the first feature captures the shared session (got $rc)" \
  '[[ $rc -eq 0 && "$(pj "$WT_ONE/self/features/$SLUG_ONE/planning.json" "[s[\"session_id\"] for s in d[\"sessions\"]]")" == "['"'"'$SHARED'"'"']" ]]'
git -C "$AT" merge -q --no-ff -m "Merge $SLUG_ONE" "$SLUG_ONE"
git -C "$AT" push -q origin main 2>/dev/null
start_unrouted "$SLUG_TWO" --no-gate >/dev/null
WT_TWO="$(wt_path "$SLUG_TWO")"
ONE_PJ="$WT_TWO/self/features/$SLUG_ONE/planning.json"
ONE_REPORT="$WT_TWO/self/features/$SLUG_ONE/report.json"
check "A1b. the premise: the second feature's branch carries the first's frozen record" '[[ -f "$ONE_PJ" ]]'
before_record="$(record_but_annotation "$ONE_PJ")"
cp "$ONE_REPORT" "$TMP/one-report.before.json" 2>/dev/null
set_pin "$WT_TWO/self/features/$SLUG_TWO/README.md" "$SHARED"
set_bound "$WT_TWO/self/features/$SLUG_TWO/README.md" from "$SHARED_WINDOW_FROM"
git -C "$WT_TWO" commit -q -am "$SLUG_TWO: pin the shared session"
out="$(capture "$WT_TWO" "$SLUG_TWO")"; rc=$?
check "A1c. capturing the second feature exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "A1d. the first's frozen record now names the second as a co-claimant" \
  'grep -q "$SLUG_TWO" <<<"$(pj "$ONE_PJ" "d[\"sessions\"][0].get(\"also_claimed_by\")")"'
check "A1e. ... and every other byte of that record is as it was" \
  '[[ -n "$before_record" && "$(record_but_annotation "$ONE_PJ")" == "$before_record" ]]'
check "A1f. ... its report was regenerated to render it" \
  '[[ -f "$ONE_REPORT" ]] && ! cmp -s "$TMP/one-report.before.json" "$ONE_REPORT"'
check "A1g. ... and both ride the second feature's cost commit" \
  '[[ "$(git -C "$WT_TWO" log -1 --format=%s)" == "$SLUG_TWO: cost records" ]] && git -C "$WT_TWO" show --name-only --format= HEAD | grep -qx "self/features/$SLUG_ONE/planning.json" && git -C "$WT_TWO" show --name-only --format= HEAD | grep -qx "self/features/$SLUG_ONE/report.json"'
check "A1h. ... leaving the worktree clean" '[[ -z "$(git -C "$WT_TWO" status --porcelain)" ]]'
check "A1i. the capture said which record it annotated" 'grep -q "annotate .*$SLUG_ONE" <<<"$out"'

# ── A2. a sibling's cost record dirty BEFORE the run is a stranger's work ─────
# The other half of the one stray reader (slice A). A1 is the admitted case: the three
# ANNOTATION_FILES under a sibling's directory, dirtied by this run's own annotation step,
# ride the cost commit. Everything before that step is strict — `report.py <other>` run by
# hand in the worktree leaves a record this run did not write, and the capture used to
# neither refuse it nor commit it, pushing the branch with the tree still dirty.
SIBLING_REL="self/features/$SLUG_ONE/report.md"
echo "a report somebody re-rendered by hand before this run" >> "$WT_TWO/$SIBLING_REL"
outa2="$(capture "$WT_TWO" "$SLUG_TWO")"; rca2=$?
check "A2a. a capture with a sibling's report.md dirty before the run refuses (got $rca2)" \
  '[[ $rca2 -ne 0 ]]'
check "A2b. ... naming that path" 'grep -q "$SIBLING_REL" <<<"$outa2"'
check "A2c. ... and writing nothing: that one path is still the only dirt (got: $(dirty_names "$WT_TWO" | tr "\n" " "))" \
  '[[ "$(dirty_names "$WT_TWO")" == "$SIBLING_REL" ]]'
git -C "$WT_TWO" checkout -- "$SIBLING_REL"

echo
if (( fails > 0 )); then echo "feature-lifecycle: $fails assertion(s) FAILED"; exit 1; fi
echo "feature-lifecycle: all assertions passed"
