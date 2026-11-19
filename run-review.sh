#!/usr/bin/env bash
set -uo pipefail

# REVIEW runner: executes the post-verify review plans in plans/features/<slug>/review/
# after the verify pass finishes (see AGENT_PLANS.md "Review plans"). The feature slug
# may be given as the first argument, and is otherwise inferred from whichever feature
# has plans queued.
#
# Why a third pass rather than a second verify plan. Verify generates observations by
# RUNNING the work — it finds what only execution reveals (a 500 that needs an
# unreadable directory to reach, a job run across a config switch). Review generates
# observations by READING the diff — it finds what stays green: an invariant with no
# test, a cross-layer contract broken on one side, a README whose field list no longer
# matches the shape it documents. Neither subsumes the other, and the split is the whole
# point: AGENT_PLANS.md "The mechanical gate" rules out handing a high model a
# transcript to summarize, because the defects worth finding are not in the output.
# Reading a diff is not reading a transcript.
#
# Same tool scope and the same fix policy as verify: Bash is ENABLED, edits are
# auto-approved, and the executor fixes what is LOCAL and reports what is structural.
# A review that could not fix a drifted README line would be buying a whole extra batch
# to correct a one-line defect it already found.
#
# This pass ends a ROUND and nothing more (self/DESIGN-2026-09-17-close-and-review-rounds.md
# §2–§3). It reads the verdict from the report's first line, commits its own output as
# `<slug>: review round N`, stamps that round's plan_end with the verdict and the head it
# judged, commits those stamps as `<slug>: review stamps`, and names what comes next: feature-close.sh on a clean round, or the rework
# brief it has just written to <features>/<slug>/escalations/<review-stem>.md. It opens no
# PR and runs no capture — those belong to the close, which refuses any tree a clean review
# has not judged, so a rework cannot happen behind a PR body describing the tree before it.
#
# A feature with an OWNER_BRIEF.md (feature-start.sh --owner-brief; LIFECYCLE.md → "The
# owner's brief and the conformance check") is reviewed against the owner's words: they go
# into the prompt verbatim, the report must carry `## Acceptance` and `## Deviations from
# the brief`, and a third kind of plan, `NN-conformance-<model>`, runs before the review — a
# `claude -p` with no tools whose prompt is only the brief and the diff, its answer written
# by this runner to conformance-report.md (queue_conformance_check, build_conformance_prompt,
# write_conformance_report). Without an owner brief: one note line, a report that asks only
# for `## Deviations from the brief` (no acceptance table: there is no request to list), and
# a queued conformance plan refused as one the feature does not owe
# (refuse_unowed_conformance_plans).
#
# This script lives in the shared agentTooling checkout, vendored at agentTooling/ in the
# consuming repo root. By default REPO_DIR is therefore that root, and the plan queue it
# operates on lives in that repo's own plans/ directory. Passing --self as the first
# argument instead points the run at agentTooling's own self/features/ queue — see
# plan-runner-roots.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
# The profile adapter, for the round's checkpoint push only (push_round, below): sourced when
# it sits beside this script, which every real install has; a copy without it is a local one.
PROFILE_ADAPTER="$SCRIPT_DIR/env-profile.sh"
if [[ -f "$PROFILE_ADAPTER" ]]; then source "$PROFILE_ADAPTER"; fi
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi
refuse_orchestrator_session "${CLAUDE_CODE_SESSION_ID:-}"   # an orchestrator builds nothing
QUEUE="review"
PLAN_KIND="review plan"
SUMMARY_TITLE="Review run summary"
# The step that follows a CLEAN round, and the only way out of a feature: it opens the PR,
# stamps it, captures the cost on the branch and asks for the merge, in that order
# (LIFECYCLE.md → step 6). This runner names it and never runs it — a runner is a runner
# (self/DESIGN-2026-09-17-close-and-review-rounds.md §2).
CLOSE_SCRIPT_NAME="feature-close.sh"
CLOSE_SCRIPT="$SCRIPT_DIR/$CLOSE_SCRIPT_NAME"
# The subject this runner commits the pass's own output under. The round is what makes one
# round's commit distinguishable from the next's; pr.sh's own fallback commit keeps its
# older subject and, now that this runner always commits first, is only ever a no-op.
PASS_COMMIT_ROUND_PREFIX=": review round "
# The subject the round's stamps are committed under, one commit after the pass's: the
# stamp names the pass commit's sha, so it cannot ride that commit. feature-close.sh accepts
# it after the stamped head like its own subjects, so a clean round leaves a clean tree and
# a coordinator may pause before the close with nothing dirty
# (self/features/rates-haiku-live-warning/NOTES.md, round 2).
STAMPS_COMMIT_SUFFIX=": review stamps"
# The base a feature whose manifest names none was cut from (pr.sh's FALLBACK_BASE). Only
# the commit decision below uses it: on the base branch itself there is nothing to commit
# to, and pr.sh's own refusal says so.
FALLBACK_BASE="main"
# The remote whose copy of the base the review diffs against
# (self/features/review-base-and-cloud-hook/, Part B). Three dots take the merge-base, so
# a local <base> NEWER than the branch point is harmless, and an OLDER one — a feature
# that merged a newer origin/<base> mid-way while local <base> stayed put, a fresh
# container, a consumer that never pulled — puts already-merged commits in the review and
# in the PR body written from it. `origin/<base>`, fetched just before, is where the
# feature really branched from; the local <base> is only the fallback with no remote.
REVIEW_REMOTE="origin"
REMOTE_TRACKING_PREFIX="refs/remotes/"
# The fetch is unattended: a remote that wants credentials fails it rather than waiting
# on a prompt nobody will answer (git's own GIT_TERMINAL_PROMPT switch)
FETCH_TERMINAL_PROMPT="0"
# The feature's committed copy of its latest verdict, relative to the feature directory
# (self/features/review-report-never-tracked/). The same basename as the live report on
# purpose: the generated plans/.gitignore anchors `/review-report.md` to plans/ so that it
# ignores the live one and never this one.
ARCHIVED_REPORT_NAME="review-report.md"

# Bash is on for the same reason it is on for verify, plus one specific to this pass:
# establishing what the batch changed is read-only git (status/diff/log/show), and there
# is no other way to get it.
CLAUDE_TOOL_ARGS=(--allowedTools Bash)

# A circuit breaker, not a budget — same role as VERIFY_BUDGET_USD, calibrated
# separately because this pass defaults to a more expensive model. Verify's $3.00 was
# derived from sonnet runs (see run-verify.sh); an opus pass at comparable turn counts
# does not fit inside it, and a cap that fires on every honest run teaches nothing.
#
# $5.00 was the starting estimate; the first two measured opus runs cost $4.53 and
# $5.11 (the second capped after it had written its report), so $7.00 is the median
# doubled, rounded down to what those runs say an honest pass needs with headroom.
# Re-derive again after a few more.
#
# Enforced after each API call, so a run overshoots by at most one turn's spend.
REVIEW_BUDGET_USD="${REVIEW_BUDGET_USD:-7.00}"
CLAUDE_BUDGET_ARGS=(--max-budget-usd "$REVIEW_BUDGET_USD")

# review_diff_base <base> — fetch <base> from REVIEW_REMOTE, best-effort, and print the ref
# the review diffs from: `origin/<base>` when that ref exists after the fetch, else the
# local <base>. A failed fetch (no network, a remote that is gone) warns on stderr and
# carries on with whatever `origin/<base>` already holds; it never refuses the pass and
# never changes an exit code. The explicit refspec updates the remote-tracking ref however
# the remote's fetch refspecs are configured. Called from build_prompt, so it runs before
# each review plan's executor starts; its output is the prompt's, so the fetch is quiet
# and the warning goes to stderr, which reaches the terminal.
review_diff_base() {
  local base="$1" tracking="$REVIEW_REMOTE/$base"
  if git -C "$REPO_DIR" remote get-url "$REVIEW_REMOTE" >/dev/null 2>&1; then
    if ! GIT_TERMINAL_PROMPT="$FETCH_TERMINAL_PROMPT" git -C "$REPO_DIR" fetch -q "$REVIEW_REMOTE" \
        "+refs/heads/$base:$REMOTE_TRACKING_PREFIX$tracking" >/dev/null 2>&1; then
      echo "WARN: git fetch $REVIEW_REMOTE $base failed — the review diffs against what $tracking already holds, or the local $base if nothing" >&2
    fi
    if git -C "$REPO_DIR" rev-parse --verify -q "$REMOTE_TRACKING_PREFIX$tracking^{commit}" >/dev/null 2>&1; then
      echo "$tracking"
      return 0
    fi
  fi
  echo "$base"
}

# ── The owner's brief and the conformance check (self/features/brief-conformance-checks/;
# LIFECYCLE.md → "The owner's brief and the conformance check") ─────────────────
# The helper that parses the owner brief and the report tables; executed, never sourced.
CONFORMANCE_SCRIPT="$SCRIPT_DIR/conformance.py"
# The marker the conformance prompt opens with — what tells it apart from a review prompt
CONFORMANCE_PROMPT_MARKER="You are running a CONFORMANCE CHECK"
# The most diff bytes the conformance prompt carries. Past it the diff is cut and the prompt
# says so; the --stat above it always lists every changed file, so nothing is hidden, only
# unread. A circuit breaker for the context window, not a tuning knob.
CONFORMANCE_DIFF_MAX_BYTES=400000
# The flags for the conformance executor (executor_args_for_plan): no tool of any kind, so
# nothing but the prompt reaches it
CONFORMANCE_TOOL_ARGS=(--tools "")

# executor_args_for_plan <plan> — the per-plan launch hook of plan-runner-lib.sh. The
# conformance plan runs with no tools and its prompt on stdin; every other plan keeps the
# runner's own arguments (the hook sets nothing for it).
executor_args_for_plan() {
  if is_conformance_stem "$(basename "$1" .md)"; then
    PLAN_TOOL_ARGS=("${CONFORMANCE_TOOL_ARGS[@]}")
    PLAN_PROMPT_ON_STDIN=1
  fi
}

# owner_brief_path — the current feature's OWNER_BRIEF.md (it may not exist)
owner_brief_path() { echo "$FEATURES_DIR/$FEATURE_SLUG/$OWNER_BRIEF_NAME"; }

# owner_item_lines <owner-brief> — the item list the helper reads from the brief, as
# `- <id> — <title>` lines: the ids both tables key their rows by
owner_item_lines() {
  python3 -B "$CONFORMANCE_SCRIPT" items "$1" | awk -F '\t' '{ printf "- %s — %s\n", $1, $2 }'
}

# report_sections_text <has-owner-brief: 1 or empty> — what the review is asked to write
# besides its verdict. The deviations section is asked of every report (item 4 applies
# everywhere); the acceptance table only with an owner brief, since it is a row per item of
# that request (R17). feature-close.sh parses both and pr.sh puts them at the top of the body.
report_sections_text() {
  if [[ -z "${1:-}" ]]; then
    cat <<'SECTIONS'
The report also carries one FIXED section, spelled exactly — the harness parses it:
   - `## Deviations from the brief` — every place the work reads the brief it was given differently, leaves part of it out, or edits outside it, one per line; exactly `None` when there is nothing to list.
SECTIONS
    return
  fi
  cat <<'SECTIONS'
The report also carries two FIXED sections, spelled exactly — the harness parses them:
   - `## Acceptance` — a markdown table whose header row is `| Item | Evidence | Result |`: one row for each item of the owner's request listed above (the Item cell starts with its id) and one for each acceptance line of the plan, with the test name or file:line that proves it as Evidence and exactly `done`, `partial` or `not done` as Result. A row that is not `done` keeps the feature from closing as clean, so it belongs in your escalated list too.
   - `## Deviations from the brief` — every place the work reads the request differently, leaves part of it out, or edits outside it, one per line; exactly `None` when there is nothing to list.
SECTIONS
}

# owner_brief_block <owner-brief> — the review prompt's owner section: the brief word for
# word, the item list, and the rule that the work is judged against it
owner_brief_block() {
  local brief="$1"
  cat <<BLOCK
THE OWNER'S REQUEST. $FEATURES_LABEL/$FEATURE_SLUG/$OWNER_BRIEF_NAME holds what the repository owner asked for, and it is the yardstick for this review: judge the diff against it, never against the implementer's restatement of it (NOTES.md, the plan, a commit message). The review brief below may add contracts to hold the work to; it may not narrow this. The owner's request, verbatim:

----- BEGIN OWNER BRIEF -----
$(cat "$brief")
----- END OWNER BRIEF -----

Its items, by the ids your acceptance table uses:
$(owner_item_lines "$brief")
BLOCK
}

# build_conformance_prompt <plan> <log> <diff-base> — the prompt for an `NN-conformance-<model>`
# plan, composed by the runner from exactly four things: fixed instructions, the item list,
# the owner brief verbatim, and the feature's diff with the feature's own directory left out
# (that is where NOTES.md, the checkpoints, the review briefs and the reports live). The plan
# body is NEVER read into it — a hand-edited plan changes nothing — and the executor is
# launched with no tools (executor_args_for_plan), so the isolation is the launch's and not
# something asked of the model (R8).
build_conformance_prompt() {
  local brief diff_bytes truncated="" exclude
  brief="$(owner_brief_path)"
  exclude=":(exclude)$FEATURES_LABEL/$FEATURE_SLUG/"
  diff_bytes="$(git -C "$REPO_DIR" diff "$3...HEAD" -- . "$exclude" | wc -c | tr -d '[:space:]')"
  if (( diff_bytes > CONFORMANCE_DIFF_MAX_BYTES )); then
    truncated="THE DIFF BELOW WAS CUT AT $CONFORMANCE_DIFF_MAX_BYTES BYTES (it is $diff_bytes bytes whole). The --stat above lists every changed file: an item you cannot verify from the part you were given is \`partial\`, never \`done\`."
  fi
  cat <<PROMPT
$CONFORMANCE_PROMPT_MARKER: an independent check of whether a diff does what a repository owner asked. You have no tools and need none. You are given the owner's request and the diff, and nothing else: no notes, no plan, no review, no transcript. Judge the diff against the request alone.

For each item listed below, decide whether the diff delivers it:
- \`done\` — the diff delivers the whole item, and you can point at where (a test name, or file:line from the diff).
- \`partial\` — part of it is delivered, or it is delivered without the test the owner asked for.
- \`not done\` — the diff does not deliver it, or you cannot find it.
Then list every changed file you cannot tie to any item. A file that is only a test, a README line or a template an item needs counts as tied to that item; say which.

Answer with exactly this and nothing else — your whole final message is the report, parsed by a program:

## Conformance

| Item | Evidence | Result |
|---|---|---|
| <item id> | <test name, or file:line> | <done, partial or not done> |

(one row per item id below, in order)

## Out of scope

- <path> — <why it ties to no item>

(one line per such file, or the single word None)

Items:
$(owner_item_lines "$brief")

----- BEGIN OWNER BRIEF -----
$(cat "$brief")
----- END OWNER BRIEF -----

The diff against \`$3\` (this feature's own directory, which holds its notes and reports, is left out):

$(git -C "$REPO_DIR" diff --stat "$3...HEAD" -- . "$exclude")

$truncated
$(git -C "$REPO_DIR" diff "$3...HEAD" -- . "$exclude" | head -c "$CONFORMANCE_DIFF_MAX_BYTES")
PROMPT
}

build_prompt() {
  local plan_path="$1"
  local log_path="$2"
  local base diff_base base_note owner_brief owner_block="" sections_text has_brief=""
  base="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" base)"
  base="${base:-$FALLBACK_BASE}"
  diff_base="$(review_diff_base "$base")"
  if is_audit_stem "$(basename "$plan_path" .md)"; then
    build_audit_prompt "$plan_path" "$log_path" "$diff_base"
    return
  fi
  if is_conformance_stem "$(basename "$plan_path" .md)"; then
    build_conformance_prompt "$plan_path" "$log_path" "$diff_base"
    return
  fi
  owner_brief="$(owner_brief_path)"
  if [[ -f "$owner_brief" ]]; then
    owner_block=$'\n\n'"$(owner_brief_block "$owner_brief")"
    has_brief=1
  fi
  sections_text="$(report_sections_text "$has_brief")"
  if [[ "$diff_base" == "$REVIEW_REMOTE/$base" ]]; then
    base_note="That is the remote's \`$base\`, fetched just now — never the local \`$base\` branch, which can be older than where this feature branched and would put already-merged commits in the diff. Use it even where the plan names a bare \`$base\`."
  else
    base_note="There is no $REVIEW_REMOTE/$base here (no \`$REVIEW_REMOTE\` remote, or nothing could be fetched from it), so this falls back to the local \`$base\`; if the diff carries commits that are plainly not this feature's, say so in your verdict."
  fi
  cat <<PROMPT
You are running a REVIEW plan: a post-verify pass that reads the DIFF a batch produced and judges the code itself. The build pass wrote it, the mechanical gate ran the deterministic checks, and the verify pass already ran the work and fixed what running revealed. You are the last pass, and you are looking for what all three of those miss: defects that are still there while every check is green. A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)$owner_block

Process:
1. Read the progress log first. Each line was appended by the harness as '<tool>: <absolute file path>', recording a mutating tool call from a previous run. Treat it as a hint about which files you may already have changed.
2. Read the plan. It is a BRIEF, not a diff: it states what the batch was supposed to do and which contracts to hold it to. Use your judgment.
3. ESTABLISH THE DIFF FIRST, before reading any file in full. Read-only git is available and is the right tool: \`git status\`, \`git diff\`, \`git log --oneline\`, \`git diff $diff_base...HEAD\`, \`git show\`. The base to compare against is \`$diff_base\`: \`git diff $diff_base...HEAD --stat\`, then the full diff. $base_note Read the diff before opening whole files — a diff shows you what changed, and a file shows you everything, most of which this batch did not touch.
4. If $GATE_REPORT_LABEL exists, read it. Install, format, lint, tests, typecheck and build ALREADY RAN. Do not re-run them, and do not re-derive their verdict. A green gate is your starting condition, not your finding. If it lists a check as SKIPPED, treat that as absent information, not as a pass: either run that check yourself or state in your verdict exactly what is consequently unverified.
5. DO NOT REDO THE VERIFY PASS. It already ran the work, exercised the behaviour, and triaged what failed. Re-running tests, starting a server, driving an endpoint, or constructing fixtures is either its job or a test's job, and it is not yours. If the only way to settle a question is to run something, that is a signal you are answering the wrong question in this pass — record it as a missing test instead.
6. LOOK FOR WHAT STAYS GREEN. That is the entire value of this pass, and it is where the batch's real defects live. In particular:
   - An invariant the code depends on that no test asserts — the highest-value finding this pass produces, because naming the missing assertion lets the next batch write it at a cheaper model's rate and the gate then runs it forever.
   - A contract broken on one side only: a response shape and its client type, a serialized field and its reader, a constant mirrored by hand across two layers.
   - Documentation that has drifted out of agreement with the code it documents — a field list missing a field, a stated guarantee the implementation no longer makes.
   - An edge case the change introduces and does not handle: empty, absent, malformed, or already-present input on a path the batch just added.
   - A stated project invariant the change quietly amends. If the batch needed to amend one, say so plainly — an amended invariant is a decision, and it should be visible as one rather than discovered later.
7. FIX ONLY WHAT IS LOCAL — a drifted README line, an off-by-one in a bound, a missing null guard, a wrong constant (edits are auto-accepted). Anything needing a new function, a changed signature, or a DESIGN DECISION is NOT yours to implement: report it, precisely enough to act on — the file, the line, what is wrong, and what it should be — as work for the next batch's build plan. Expect to escalate more often than a verify pass does: a defect found by reading is more often structural than one found by running, and rewriting a design at peak context on this model is the most expensive way this workflow can correct anything.
8. NEVER mutate repo-wide VCS state: no \`git stash\`, \`git checkout\`, \`git reset\`, \`git clean\`, or branch switch. Two reasons, both load-bearing. (a) The plan queue you are running from is UNTRACKED working-tree state, so \`git stash -u\` sweeps this plan, its progress log and its usage record out from under the runner — and \`git stash pop\` restores the files but not the queue directories it emptied, which strands this plan in inprogress/ where the next run resumes it. (b) This run can stop at ANY turn (budget cap, usage limit), and a stop between stash and pop leaves the whole batch's uncommitted output in a stash nobody knows to look for. To compare against a baseline, use \`git worktree add <scratch-path> HEAD\`, which never touches this working tree. Read-only git is not just fine here, it is the point — see step 3.
9. Do not check whether a model obeys an instruction. Such checks are flaky by construction and cannot fail informatively.
10. WRITE YOUR VERDICT TO $REVIEW_REPORT_LABEL, overwriting whatever is there. Its FIRST LINE must be exactly \`$VERDICT_PREFIX $VERDICT_CLEAN\` or \`$VERDICT_PREFIX $VERDICT_ESCALATED\` — \`$VERDICT_CLEAN\` means the escalated list below is EMPTY, and nothing else does. The harness reads that line, and only that line: \`$VERDICT_CLEAN\` lets the feature be closed, \`$VERDICT_ESCALATED\` makes the rework a new round, and a first line it cannot read is treated as \`$VERDICT_ESCALATED\`. Then write the report for the human who approves the PR, since this file becomes its body: what the batch was supposed to do, whether it does it, then two separate lists — what you fixed in this pass, and what you are escalating to the next round. Markdown. "No findings" is a legitimate and useful verdict; say it outright rather than manufacturing something to justify the pass, because a list of speculative concerns is worse than an empty list — the next round has to spend turns disproving each one. $sections_text
   If you write nothing here, your review is invisible to the person approving it and the harness reads the missing verdict as an escalation.
11. Do NOT Read or Write the progress log yourself. The harness appends to it live as you use Edit/Write.

Plan contents:

$(cat "$plan_path")
PROMPT
}

# ── The security audit (LIFECYCLE.md → "The security audit") ───────────────────
# Where an audit plan writes its verdict: the feature's own directory, committed with the
# pass, so the live review report is never shared between the two plans of one pass.
AUDIT_REPORT_LABEL_FOR() { echo "$FEATURES_LABEL/$1/$AUDIT_REPORT_NAME"; }
# The marker the audit prompt opens with — what tells it apart from a review prompt
AUDIT_PROMPT_MARKER="You are running a SECURITY AUDIT plan"

# build_audit_prompt <plan> <log> <diff-base> — the prompt for an `NN-audit-<model>` plan:
# the same harness rules as a review, a different job (the plan body says it) and its own
# report path, so its verdict cannot overwrite the review's.
build_audit_prompt() {
  local plan_path="$1" log_path="$2" diff_base="$3" report_label
  report_label="$(AUDIT_REPORT_LABEL_FOR "$FEATURE_SLUG")"
  cat <<PROMPT
$AUDIT_PROMPT_MARKER: a pass separate from the review, run before it in the same pass, that tries concrete inputs against every hook rule this feature's diff adds or changes and reports which ones get past. A progress log is maintained automatically by the harness so this work can be resumed if interrupted.

Relevant files (absolute paths):
- Plan:         $plan_path
- Progress log: $log_path (auto-populated — do not write to it yourself)

Process:
1. Read the plan: it names the hook files the diff changed and how to attack them. The base is \`$diff_base\`: \`git diff $diff_base...HEAD -- <file>\` for each.
2. Attack a throwaway copy (\`git archive HEAD\` into your scratch space), never this checkout. Do NOT edit any file in the repository; the review that runs after you judges this same tree.
3. NEVER mutate repo-wide VCS state: no \`git stash\`, \`git checkout\`, \`git reset\`, \`git clean\`, or branch switch.
4. WRITE YOUR VERDICT TO $report_label, overwriting whatever is there. Its FIRST LINE must be exactly \`$VERDICT_PREFIX $VERDICT_CLEAN\` or \`$VERDICT_PREFIX $VERDICT_ESCALATED\`, as the plan's classification decides: every finding is classed \`blocking\` or \`non-blocking\` by the plan's rule, one you cannot class with the base's result as evidence is \`blocking\`, \`$VERDICT_CLEAN\` means no blocking finding, and \`$VERDICT_ESCALATED\` means at least one. Then write the sections the plan names, in its order — non-blocking findings are listed, never dropped. A first line the harness cannot read is treated as \`$VERDICT_ESCALATED\`, and \`feature-close.sh\` refuses to close a hook change until this verdict is \`$VERDICT_CLEAN\`.
5. Do NOT Read or Write the progress log yourself.

Plan contents:

$(cat "$plan_path")
PROMPT
}

# queue_security_audit [slug] — before the pass: when the feature's diff changes the hook
# (audit_paths_touched) and a review is queued, render AUDIT_TEMPLATE_REL as
# review/incomplete/<NN>-audit-<AUDIT_DEFAULT_MODEL>.md — NN the queued review's, so it
# sorts and runs first — and add its stem to plans[]; an audit already queued must be
# exactly that file, or the pass is refused. Refuses (exit
# 1) a queue it cannot run as one pass: an audit queued with no review after it, which
# would leave the audit's plan_end the one the pass stamps with the review's verdict.
queue_security_audit() {
  local requested="${1:-}" queue_dir state f stem review="" review_state="" audit="" audit_state=""
  local last="" base diff_base touched nn target files plans_json template text plans self_flag links
  shopt -s nullglob
  resolve_feature "$requested" >/dev/null 2>&1 || return 0
  [[ -n "${FEATURE_SLUG:-}" ]] || return 0
  queue_dir="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE"
  # inprogress/ first, as run_all resumes it first: a review or an audit there counts as
  # queued, and the checks below hold an audit there exactly as one in incomplete/
  # (security audit round 2, N9)
  for state in inprogress incomplete; do
    for f in $(list_plans "$queue_dir/$state"); do
      stem="$(basename "${f%.md}")"
      is_conformance_stem "$stem" && continue   # the conformance plan is neither (queue_conformance_check)
      last="$stem"
      if is_audit_stem "$stem"; then audit="$stem"; audit_state="$state"
      else review="$stem"; review_state="$state"; fi
    done
  done
  if [[ -n "$audit" ]] && { [[ -z "$review" ]] || is_audit_stem "$last"; }; then
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/$audit_state/$audit.md is queued with no review plan after it — an audit runs in the same pass as a review and sorts before it (same NN): queue the review as $QUEUE/incomplete/NN-review-<model>.md with the audit's NN" >&2
    exit 1
  fi
  [[ -n "$review" ]] || return 0
  # A symlink at an audit path makes what runs differ from what the diff shows (round 2, N10)
  links="$(audit_symlinks "$REPO_DIR")"
  if [[ -n "$links" ]]; then
    echo "  refused  $(tr '\n' ' ' <<<"$links")is a symlink at an audit path — the hook and the files that enforce it are reviewed and audited as files, never through a link: replace it with the file itself" >&2
    exit 1
  fi
  base="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" base)"
  diff_base="$(review_diff_base "${base:-$FALLBACK_BASE}")"
  # A diff that cannot be read queues nothing here — the pass still runs — and the close,
  # which is the enforcement, refuses on the same unreadable diff (fail closed there).
  if ! touched="$(audit_paths_touched "$REPO_DIR" "$diff_base")"; then
    echo "WARN: cannot diff $diff_base...HEAD to tell whether the hook changed — no security audit was queued, and feature-close.sh will refuse until it can tell" >&2
    return 0
  fi
  [[ -n "$touched" ]] || return 0
  template="$SCRIPT_DIR/$AUDIT_TEMPLATE_REL"
  if [[ ! -f "$template" ]]; then
    echo "  refused  the diff changes the hook and there is no $AUDIT_TEMPLATE_REL beside this script to queue its security audit from" >&2
    exit 1
  fi
  # A review resumed from inprogress/ runs before anything in incomplete/, so an audit cannot
  # be queued beside it there; and a hook change's review never runs without its audit
  # (round 2, N8): refused, naming the way back.
  if [[ "$review_state" == inprogress && -z "$audit" ]]; then
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/inprogress/$review.md would resume with no security audit beside it, and the diff changes the hook ($(tr '\n' ' ' <<<"$touched")) — move it back to $QUEUE/incomplete/ and run this again: the audit is queued to run before it" >&2
    exit 1
  fi
  nn="${review%%-*}"
  stem="$nn$AUDIT_STEM_INFIX$AUDIT_DEFAULT_MODEL"
  target="$queue_dir/${audit_state:-incomplete}/$stem.md"
  files="$(sed 's/^/- `/; s/$/`/' <<<"$touched")"
  # Literal replacements: the quoted pattern and the quoted replacement keep a `&` or a
  # glob character in a path from meaning anything to bash.
  text="$(cat "$template")"
  text="${text//"{{NN}}"/"$nn"}"
  text="${text//"{{SLUG}}"/"$FEATURE_SLUG"}"
  text="${text//"{{DIFF_BASE}}"/"$diff_base"}"
  text="${text//"{{FILES}}"/"$files"}"
  # The audit a hook change gets is THIS one: the template's body, the pinned model. A queued
  # audit that is anything else — another model, a body rewritten to ask for less — is
  # refused rather than run in its place (security audit round 1, F5).
  if [[ -n "$audit" ]]; then
    if [[ "$audit" != "$stem" ]]; then
      echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/$audit_state/$audit.md is queued, but a hook change's audit is $stem — the model is pinned to $AUDIT_DEFAULT_MODEL and the NN is the review's: delete it, and this runner queues $stem from $AUDIT_TEMPLATE_REL" >&2
      exit 1
    fi
    if [[ "$(cat "$target" 2>/dev/null)" != "$text" ]]; then
      echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/$audit_state/$audit.md differs from $AUDIT_TEMPLATE_REL rendered for this diff — an audit's brief is the template's, never a hand-written one: delete it, and this runner queues it again" >&2
      exit 1
    fi
    return 0
  fi
  printf '%s\n' "$text" > "$target"
  plans_json="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" plans)"
  plans=()
  while IFS= read -r f; do [[ -n "$f" ]] && plans+=("$f"); done < <(jq -r '.[]?' <<<"${plans_json:-[]}" 2>/dev/null)
  plans+=("$stem")
  self_flag=()
  if (( SELF_MODE )); then self_flag=(--self); fi
  python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${self_flag[@]+"${self_flag[@]}"} "$FEATURE_SLUG" set-plans "${plans[@]}" >/dev/null \
    || echo "  warn      could not add $stem to plans[] — add it: python3 $SCRIPT_DIR/analysis/manifest.py $SELF_ARG$FEATURE_SLUG set-plans … $stem" >&2
  echo "=== the diff changes the hook ($(tr '\n' ' ' <<<"$touched")) — queued the security audit $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/incomplete/$stem.md to run before $review (LIFECYCLE.md → \"The security audit\") ==="
}

CONFORMANCE_PLAN_BODY_LEAD="# NN — conformance check"
# queue_conformance_check [slug] — before the pass (after queue_security_audit): when the
# feature carries OWNER_BRIEF.md and a review is queued, write review/incomplete/
# <NN>-conformance-<model>.md — NN and model the review's, so it sorts after the audit and
# before the review, which stays last and keeps the plan_end the pass stamps — and add its
# stem to plans[] so the cost report prices it like any plan (R7). The file is a stub: the
# runner composes the executor's prompt from git and the owner brief and never reads it
# (build_conformance_prompt), so there is nothing in it to edit or to refuse. A conformance
# plan queued under any other stem is refused, the way a stray audit is. Without an owner
# brief: one note line and nothing queued — the rollout (R15).
queue_conformance_check() {
  local requested="${1:-}" queue_dir state f stem review="" conf="" conf_state="" review_state=""
  local nn model target plans_json plans self_flag text already_listed
  shopt -s nullglob
  resolve_feature "$requested" >/dev/null 2>&1 || return 0
  [[ -n "${FEATURE_SLUG:-}" ]] || return 0
  queue_dir="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE"
  for state in inprogress incomplete; do
    for f in $(list_plans "$queue_dir/$state"); do
      stem="$(basename "${f%.md}")"
      if is_conformance_stem "$stem"; then conf="$stem"; conf_state="$state"
      elif ! is_audit_stem "$stem"; then review="$stem"; review_state="$state"; fi
    done
  done
  [[ -n "$review" ]] || return 0
  if [[ ! -f "$(owner_brief_path)" ]]; then
    echo "  note      no $OWNER_BRIEF_NAME in $FEATURES_LABEL/$FEATURE_SLUG — the review is judged against its own brief only, and no conformance check runs (LIFECYCLE.md → \"The owner's brief and the conformance check\")"
    return 0
  fi
  if [[ ! -f "$CONFORMANCE_SCRIPT" ]]; then
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$OWNER_BRIEF_NAME exists and there is no conformance.py beside this script to read it with" >&2
    exit 1
  fi
  nn="${review%%-*}"
  model="${review##*-}"
  stem="$nn$CONFORMANCE_STEM_INFIX$model"
  if [[ -n "$conf" && "$conf" != "$stem" ]]; then
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/$conf_state/$conf.md is queued, but this review's conformance check is $stem — the NN and model are the review's: delete it, and this runner queues $stem" >&2
    exit 1
  fi
  # A review resumed from inprogress/ runs before anything in incomplete/, so the check cannot
  # be queued beside it there
  if [[ "$review_state" == inprogress && -z "$conf" ]]; then
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/inprogress/$review.md would resume with no conformance check beside it, and the feature carries an $OWNER_BRIEF_NAME — move it back to $QUEUE/incomplete/ and run this again: the check is queued to run before it" >&2
    exit 1
  fi
  target="$queue_dir/${conf_state:-incomplete}/$stem.md"
  text="$CONFORMANCE_PLAN_BODY_LEAD $nn: $FEATURE_SLUG"$'\n\n'"Written by run-review.sh. The conformance executor is given only the owner's brief and the feature's diff, composed from git by the runner; this file is never put in its prompt, so editing it changes nothing."
  printf '%s\n' "$text" > "$target"
  [[ -z "$conf" ]] || return 0
  plans_json="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" plans)"
  plans=()
  while IFS= read -r f; do [[ -n "$f" ]] && plans+=("$f"); done < <(jq -r '.[]?' <<<"${plans_json:-[]}" 2>/dev/null)
  # Only when absent: a review moved back to incomplete/ after its check finished queues the
  # same stem again, and set-plans does not remove duplicates
  already_listed=0
  for f in ${plans[@]+"${plans[@]}"}; do [[ "$f" == "$stem" ]] && already_listed=1; done
  (( already_listed )) || plans+=("$stem")
  self_flag=()
  if (( SELF_MODE )); then self_flag=(--self); fi
  python3 -B "$SCRIPT_DIR/analysis/manifest.py" ${self_flag[@]+"${self_flag[@]}"} "$FEATURE_SLUG" set-plans "${plans[@]}" >/dev/null \
    || echo "  warn      could not add $stem to plans[] — add it: python3 $SCRIPT_DIR/analysis/manifest.py $SELF_ARG$FEATURE_SLUG set-plans … $stem" >&2
  echo "=== the feature carries an $OWNER_BRIEF_NAME — queued the conformance check $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/incomplete/$stem.md to run before $review (LIFECYCLE.md → \"The owner's brief and the conformance check\") ==="
}

# refuse_unowed_conformance_plans [slug] — before the pass, and BEFORE queue_security_audit
# pairs an audit with its review: a queued `NN-conformance-<model>` plan the feature does not
# owe is refused (exit 1, nothing run), the way a stray audit is. It is owed only with an
# OWNER_BRIEF.md, a review queued beside it, and exactly the stem <review NN>-conformance-
# <review model> (R7). A stray one would run last with no tools, hold the pass's deferred
# plan_end and take the round's verdict stamp off the review (security audit round 1, B1).
refuse_unowed_conformance_plans() {
  local requested="${1:-}" queue_dir state f stem review="" owed="" i why
  local confs=() conf_states=()
  shopt -s nullglob
  resolve_feature "$requested" >/dev/null 2>&1 || return 0
  [[ -n "${FEATURE_SLUG:-}" ]] || return 0
  queue_dir="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE"
  for state in inprogress incomplete; do
    for f in $(list_plans "$queue_dir/$state"); do
      stem="$(basename "${f%.md}")"
      if is_conformance_stem "$stem"; then confs+=("$stem"); conf_states+=("$state")
      elif ! is_audit_stem "$stem"; then review="$stem"; fi
    done
  done
  (( ${#confs[@]} )) || return 0
  if [[ -f "$(owner_brief_path)" && -n "$review" ]]; then
    owed="${review%%-*}$CONFORMANCE_STEM_INFIX${review##*-}"
  fi
  for i in "${!confs[@]}"; do
    [[ "${confs[$i]}" == "$owed" ]] && continue
    if [[ ! -f "$(owner_brief_path)" ]]; then
      why="this feature has no $OWNER_BRIEF_NAME, so it owes no conformance check"
    elif [[ -z "$review" ]]; then
      why="no review is queued beside it, and a conformance check runs only before one"
    else
      why="this review's conformance check is $owed — the NN and model are the review's"
    fi
    echo "  refused  $FEATURES_LABEL/$FEATURE_SLUG/$QUEUE/${conf_states[$i]}/${confs[$i]}.md is queued, but $why: delete it${owed:+, and this runner queues $owed}" >&2
    exit 1
  done
}

# Lets run_all return after a budget cap instead of exiting, so the PR block below gets
# to look at whether the report was written first (finalize_plan, plan-runner-lib.sh).
after_budget_exceeded() { BUDGET_CAPPED=1; }
BUDGET_CAPPED=0

source "$SCRIPT_DIR/plan-runner-lib.sh"
# This runner finishes its own plan_end stamp: the verdict and the sha of the commit it
# makes below are both details that do not exist when finalize_plan has the exit code
# (plan-runner-lib.sh → "plan_end, and the one wrapper that finishes the stamp itself").
PLAN_END_DEFERRED=1
# Fingerprint taken before the pass so "the report was written by THIS run" is a
# content comparison rather than a guess (mtime granularity is a second, which a stub
# or a fast pass can fit inside); see the budget-capped branch below.
report_fingerprint() { if [[ -f "$REVIEW_REPORT" ]]; then cksum < "$REVIEW_REPORT"; else echo absent; fi; }
REVIEW_BEFORE="$(report_fingerprint)"
refuse_unowed_conformance_plans "${1:-}"
queue_security_audit "${1:-}"
queue_conformance_check "${1:-}"
# The audit plan this pass will run, if any (queued just now or by hand), and its report's
# fingerprint, for the same "written by THIS run" comparison the review's report gets. The
# conformance plan likewise, and its report: any earlier copy is deleted before the pass, so
# a conformance-report.md can only be this pass's (R6).
AUDIT_PLAN_QUEUED=""
AUDIT_REPORT=""
CONFORMANCE_PLAN_QUEUED=""
CONFORMANCE_REPORT=""
if [[ -n "${FEATURE_SLUG:-}" ]]; then
  for f in $(list_plans "$FEATURES_DIR/$FEATURE_SLUG/$QUEUE/inprogress") $(list_plans "$FEATURES_DIR/$FEATURE_SLUG/$QUEUE/incomplete"); do
    if is_audit_stem "$(basename "${f%.md}")"; then AUDIT_PLAN_QUEUED="$(basename "${f%.md}")"; fi
    if is_conformance_stem "$(basename "${f%.md}")"; then CONFORMANCE_PLAN_QUEUED="$(basename "${f%.md}")"; fi
  done
  AUDIT_REPORT="$FEATURES_DIR/$FEATURE_SLUG/$AUDIT_REPORT_NAME"
  CONFORMANCE_REPORT="$FEATURES_DIR/$FEATURE_SLUG/$CONFORMANCE_REPORT_NAME"
  if [[ -n "$CONFORMANCE_PLAN_QUEUED" ]]; then rm -f "$CONFORMANCE_REPORT"; fi
fi
audit_fingerprint() { if [[ -n "$AUDIT_REPORT" && -f "$AUDIT_REPORT" ]]; then cksum < "$AUDIT_REPORT"; else echo absent; fi; }
AUDIT_BEFORE="$(audit_fingerprint)"
# The hook the audit judged (security audit round 1, F3): the audit runs before the review in
# one pass, and the review may fix things — so the audit paths' working-tree fingerprint is
# taken the moment the audit plan finishes, and compared with the committed tree at the
# stamp. Any difference means the hook the round closes on is not the hook the audit
# attacked, and the audit is stamped `stale`, never clean. Chosen over running the audit
# after the review because the review's plan_end must stay the one the pass holds and
# stamps (plan-runner-lib.sh), and a fingerprint also catches a change made by anything
# else between the two, uncommitted included (self/features/hook-role-hardening/NOTES.md).
AUDIT_TREE_AT_AUDIT=""
AUDIT_VERDICT_STALE="stale"
on_plan_finished() {
  if [[ -n "$AUDIT_PLAN_QUEUED" && "$1" == "$AUDIT_PLAN_QUEUED" ]]; then
    AUDIT_TREE_AT_AUDIT="$(audit_tree_fingerprint "$REPO_DIR" | cksum)"
  fi
}
run_all "$@"
run_rc=$?
(( BUDGET_CAPPED )) && run_rc=1

# --- Read the verdict, commit the pass, and stop. ---
#
# In the script, not the executor prompt: committing is deterministic work with a real
# exit code, and AGENT_PLANS.md "The mechanical gate" already settles that such work
# leaves the model. The model's contribution is the review itself — which reaches the PR
# as its body when feature-close.sh opens one, via $REVIEW_REPORT.
#
# A runner is a runner (design §2). This pass records what the round decided and names
# the next step; it opens no PR and runs no capture, so a rework after an escalated round
# cannot happen behind a PR body and a frozen record that describe the tree before it.
#
# Gated on a clean pass, with one exception. A review that failed or was interrupted has
# not finished judging the batch, and a verdict recorded on its behalf would be a
# half-written one. The exception is a BUDGET cap that fired after the report was written:
# the verdict is complete — the executor writes the report as its last act (prompt step
# 10) — and the cap cut off only the turns after it. Measured: the first pilot's review
# wrote its full report, then hit the cap, was filed to failed/, and the PR was opened by
# hand with the identical body. The report is used as-is with a banner saying the pass was
# capped, so the approver knows the review's own fix loop may have been cut short.
capped_after_report() {
  [[ -n "$(list_plans "$FAILED_DIR")" ]] || return 1
  [[ -z "$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]] || return 1
  [[ -f "$REVIEW_REPORT" && "$(report_fingerprint)" != "$REVIEW_BEFORE" ]] || return 1
  grep -qs "reached the run budget" "$FAILED_DIR"/*.progress.md
}
record_verdict=0
if [[ -n "${FEATURE_SLUG:-}" ]]; then
  if (( run_rc == 0 )) && [[ -z "$(list_plans "$FAILED_DIR")$(list_plans "$INPROGRESS_DIR")$(list_plans "$INCOMPLETE_DIR")" ]]; then
    record_verdict=1
  elif (( BUDGET_CAPPED )) && capped_after_report; then
    echo ""
    echo "=== review pass hit its budget AFTER writing its report — the verdict in it stands ==="
    printf '\n---\n_Review pass reached its budget cap (%s USD) after writing this verdict; any fixes it was still applying may be incomplete. The review itself is as written above._\n' "$REVIEW_BUDGET_USD" >> "$REVIEW_REPORT"
    record_verdict=1
  fi
fi
# untrack_review_report — the one-time repair of a repo that committed $REVIEW_REPORT
# before its ignore line reached it (self/features/review-report-never-tracked/). The
# .gitignore that covers it never untracks a file already in the index, and the `git add
# -A` below re-commits a tracked one every round — so two features reviewed at once
# conflict on it at merge, the live report being the one path every round rewrites. Only
# the INDEX entry goes: the file stays on disk, where feature-close.sh reads it for the PR
# body, and the commit below carries the untrack. Only when the ignore now covers it, too:
# an untrack the next `git add -A` would undo is no repair, so a repo whose plans/.gitignore
# predates the line is told to run sync-plans.sh instead (which does the same untrack).
# Advisory like the rest of the commit step: a git failure is reported and the pass goes on.
untrack_review_report() {
  git -C "$REPO_DIR" ls-files --error-unmatch -- "$REVIEW_REPORT" >/dev/null 2>&1 || return 0
  if ! git -C "$REPO_DIR" check-ignore -q --no-index -- "$REVIEW_REPORT" 2>/dev/null; then
    echo "=== $REVIEW_REPORT_LABEL is tracked and nothing ignores it — run sync-plans.sh, whose .gitignore does, and it untracks it ==="
    return 0
  fi
  if git -C "$REPO_DIR" rm --cached -q -- "$REVIEW_REPORT" >/dev/null 2>&1; then
    echo "=== untracked $REVIEW_REPORT_LABEL — it is ignored and rewritten every round, and this commit stops git carrying it ==="
  else
    echo "=== could not untrack $REVIEW_REPORT_LABEL — it stays tracked, and concurrent features will conflict on it ==="
  fi
}

# commit_pass_output <branch> <base> <subject> — commit everything this pass produced.
#
# The commit is the RUNNER'S, and pr.sh's older one is now only a fallback that finds a
# clean tree. pr.sh returns 0 without committing on four ordinary paths — no forge CLI
# installed, not authenticated, detached HEAD, no pr.sh seeded at all — and until the
# runner committed, each of them left the pass's own files dirty when feature-capture.sh
# ran next, which refuses anything that is not a cost record as a stranger's work: every
# clean review in such a repo ended with "capture exited 1" (the capture-on-branch
# review's escalation; self/DESIGN-2026-09-16-lifecycle-restructure.md §3.8).
#
# On the base branch there is nothing to commit to — committing the primary's work in
# progress is what LIFECYCLE.md rule 2 exists to prevent. Advisory throughout, exactly
# like the gate: a review that succeeded is never unwound by a git failure after it, and
# the verdict is stamped either way.
commit_pass_output() {
  local branch="$1" base="$2" subject="$3"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    echo "=== detached HEAD — the pass's output is left uncommitted ==="
    return 0
  fi
  if [[ "$branch" == "$base" ]]; then
    echo "=== on '$branch', this feature's base — the pass's output is left uncommitted ==="
    return 0
  fi
  untrack_review_report
  if [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo "=== nothing to commit — the working tree is already clean ==="
    return 0
  fi
  if ! git -C "$REPO_DIR" add -A; then
    echo "=== git add failed — the pass's output is left uncommitted ==="
    return 0
  fi
  if ! git -C "$REPO_DIR" commit -q -m "$subject"; then
    echo "=== git commit failed — the pass's output is left uncommitted ==="
    return 0
  fi
  echo "=== committed the pass as '$subject' on $branch ==="
}

# commit_stamps <branch> <base> <subject> — commit the feature's timing.jsonl alone, after
# the stamps are written. Same guards and the same advisory stance as commit_pass_output;
# only the one file is staged, so nothing the pass did not write is swept in with it.
commit_stamps() {
  local branch="$1" base="$2" subject="$3"
  local timing="$FEATURES_DIR/$FEATURE_SLUG/timing.jsonl"
  if [[ -z "$branch" || "$branch" == "HEAD" || "$branch" == "$base" ]]; then
    return 0
  fi
  if [[ -z "$(git -C "$REPO_DIR" status --porcelain -- "$timing")" ]]; then
    return 0
  fi
  if git -C "$REPO_DIR" add -- "$timing" && git -C "$REPO_DIR" commit -q -m "$subject" -- "$timing"; then
    echo "=== committed the round's stamps as '$subject' ==="
  else
    echo "=== could not commit the round's stamps — timing.jsonl is left uncommitted, and the close commits it ==="
  fi
}

# push_round <branch> <base> — the round's checkpoint (self/features/cloud-checkpoint-push/):
# under the cloud profile, push the feature's branch once the round's commits are made, so a
# container reclaimed after the review loses neither the round commit nor its stamps. Only
# when this checkout is on the manifest's branches[0] and that is neither the base nor a
# detached HEAD — the cases where the commits above were made at all. Advisory, through the
# shared push (plan-runner-roots.sh): a failure is one warning line and changes no exit
# status. Local, and a copy with no profile adapter beside it: nothing, not even a line.
push_round() {
  local branch="$1" base="$2" feature_branch
  declare -F profile_is_cloud >/dev/null && profile_is_cloud || return 0
  if [[ -z "$branch" || "$branch" == "HEAD" || "$branch" == "$base" ]]; then
    return 0
  fi
  feature_branch="$(manifest_branch "$FEATURES_DIR/$FEATURE_SLUG/README.md" "$FEATURE_SLUG")"
  [[ "$branch" == "$feature_branch" ]] || return 0
  checkpoint_push "$REPO_DIR" "$branch"
}

# write_conformance_report — the conformance executor's final `result` text, from its stream
# in review/complete/, into the feature's conformance-report.md, and a one-line summary of
# it. The stream is the executor's whole record and it is gitignored; this is the one
# committed copy of its answer.
write_conformance_report() {
  local stream="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE/complete/$CONFORMANCE_PLAN_QUEUED.stream.jsonl" answer
  if [[ ! -f "$stream" ]]; then
    echo "=== the conformance check $CONFORMANCE_PLAN_QUEUED left no stream in $QUEUE/complete/ — no conformance report was written, and $CLOSE_SCRIPT_NAME refuses a round without one ==="
    return 0
  fi
  answer="$(jq -R -s -r 'split("\n") | map(fromjson? | select(.type == "result")) | last | .result // empty' "$stream" 2>/dev/null)"
  if [[ -z "${answer//[[:space:]]/}" ]]; then
    echo "=== the conformance check $CONFORMANCE_PLAN_QUEUED ended with no answer — no conformance report was written, and $CLOSE_SCRIPT_NAME refuses a round without one ==="
    return 0
  fi
  printf '%s\n' "$answer" > "$CONFORMANCE_REPORT"
  echo "=== $(python3 -B "$CONFORMANCE_SCRIPT" summary --owner-brief "$(owner_brief_path)" --conformance "$CONFORMANCE_REPORT") — recorded at $FEATURES_LABEL/$FEATURE_SLUG/$CONFORMANCE_REPORT_NAME ==="
}

if (( record_verdict )); then
  # The round this pass belongs to, fixed by run_all at pass_start, and the plan whose
  # plan_end is still held (plan-runner-lib.sh): the one that wrote the report.
  round="${TIMING_ROUND:-$(next_round "$FEATURE_SLUG")}"
  review_plan="${PLAN_END_HELD_PLAN:-$(latest_review_plan "$FEATURE_SLUG")}"
  verdict="$(report_verdict "$REVIEW_REPORT")"
  pass_subject="$FEATURE_SLUG$PASS_COMMIT_ROUND_PREFIX$round"
  escalations_dir="$FEATURES_DIR/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME"
  escalations_file="$escalations_dir/$review_plan.md"
  escalations_label="$FEATURES_LABEL/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME/$review_plan.md"
  archived_report="$FEATURES_DIR/$FEATURE_SLUG/$ARCHIVED_REPORT_NAME"
  archived_label="$FEATURES_LABEL/$FEATURE_SLUG/$ARCHIVED_REPORT_NAME"

  echo ""
  case "$verdict" in
    "$VERDICT_CLEAN")
      echo "=== round $round verdict: $VERDICT_CLEAN ==="
      ;;
    "$VERDICT_UNREADABLE")
      echo "=== round $round verdict: $VERDICT_UNREADABLE — the report's first line carried no '$VERDICT_PREFIX' the harness could read, so it is treated as $VERDICT_ESCALATED (fail closed) ==="
      ;;
    *)
      echo "=== round $round verdict: $VERDICT_ESCALATED ==="
      ;;
  esac

  # The rework brief, written by the RUNNER and not by the executor: the report already
  # carries the two lists the prompt asks for, and one file with one writer is what keeps
  # the brief and the verdict from disagreeing. Same directory the tier ladder writes
  # NN.md into (RUNNER.md → "Red gates").
  if [[ "$verdict" != "$VERDICT_CLEAN" ]]; then
    if mkdir -p "$escalations_dir" && cp "$REVIEW_REPORT" "$escalations_file" 2>/dev/null; then
      echo "=== the rework brief is $escalations_label ==="
    else
      echo "=== could not write $escalations_label — the report is at $REVIEW_REPORT_LABEL ==="
    fi
  fi

  # The security audit that ran beside this review, if one did: its verdict is its report's
  # first line, read only when THIS pass wrote the report (unreadable otherwise, which
  # fails closed), and an audit that is not clean leaves its report as a rework brief in
  # the same directory the review's does. Stamped after the commit, below, with the head.
  audit_verdict=""
  if [[ -n "$AUDIT_PLAN_QUEUED" && -e "$FEATURES_DIR/$FEATURE_SLUG/$QUEUE/complete/$AUDIT_PLAN_QUEUED.md" ]]; then
    if [[ "$(audit_fingerprint)" == "$AUDIT_BEFORE" ]]; then
      audit_verdict="$VERDICT_UNREADABLE"
    else
      audit_verdict="$(report_verdict "$AUDIT_REPORT")"
    fi
    echo "=== security audit $AUDIT_PLAN_QUEUED verdict: $audit_verdict ==="
    if [[ "$audit_verdict" != "$VERDICT_CLEAN" ]]; then
      audit_brief="$escalations_dir/$AUDIT_PLAN_QUEUED.md"
      if mkdir -p "$escalations_dir" && { [[ -f "$AUDIT_REPORT" ]] && cp "$AUDIT_REPORT" "$audit_brief" 2>/dev/null; }; then
        echo "=== the audit's rework brief is $FEATURES_LABEL/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME/$AUDIT_PLAN_QUEUED.md ==="
      else
        echo "=== the audit wrote no report this pass — $(AUDIT_REPORT_LABEL_FOR "$FEATURE_SLUG") holds no verdict of this tree ==="
      fi
    fi
  fi

  # The committed record of this round's verdict, clean or not: the live report is ignored
  # and rewritten every round, so without this a clean verdict survived only as a PR body.
  # One file per feature, overwritten each round and carried by that round's commit below,
  # so the feature's history holds every round's verdict and no two features share a path.
  if cp "$REVIEW_REPORT" "$archived_report" 2>/dev/null; then
    echo "=== this round's verdict is recorded at $archived_label ==="
  else
    echo "=== could not write $archived_label — the round's verdict is only at $REVIEW_REPORT_LABEL ==="
  fi

  # The conformance check that ran beside this review, if one did: its answer is the `result`
  # of its stream — the executor has no tools, so it wrote no file — and the RUNNER writes it
  # to conformance-report.md, committed with the round below (R6). A plan that left no
  # answer leaves no report, and the close refuses a round without one.
  if [[ -n "$CONFORMANCE_PLAN_QUEUED" ]]; then
    write_conformance_report
  fi

  # The branch this feature was cut from, recorded by feature-start.sh: on it there is
  # nothing for this pass to commit to. Read here, once, so nothing else parses markdown.
  feature_base="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" base)"
  current_branch="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)"
  echo ""
  echo "=== committing the pass's output ==="
  commit_pass_output "$current_branch" "${feature_base:-$FALLBACK_BASE}" "$pass_subject"

  # The stamps, after the commit: `head` is the sha of the tree this verdict judged, which
  # is what feature-close.sh refuses to close anything but. pass_end is written here
  # rather than left to the EXIT trap so the two land together, one line after the other.
  # Then they are committed on their own, so the round ends on a clean tree.
  stamp_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)"
  flush_plan_end verdict="$verdict" head="$stamp_head"
  if [[ -n "$audit_verdict" ]] && [[ -z "$AUDIT_TREE_AT_AUDIT" || "$(audit_tree_fingerprint "$REPO_DIR" | cksum)" != "$AUDIT_TREE_AT_AUDIT" ]]; then
    echo "=== the hook changed after the security audit finished (the review, or something else, edited an audit path) — the audit is stamped '$AUDIT_VERDICT_STALE', and the close refuses it: the next round audits the tree as it now stands ==="
    audit_verdict="$AUDIT_VERDICT_STALE"
  fi
  if [[ -n "$audit_verdict" ]]; then
    stamp_timing "$AUDIT_END_EVENT" plan="$AUDIT_PLAN_QUEUED" verdict="$audit_verdict" head="$stamp_head"
  fi
  stamp_pass_end
  commit_stamps "$current_branch" "${feature_base:-$FALLBACK_BASE}" "$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX"
  push_round "$current_branch" "${feature_base:-$FALLBACK_BASE}"

  echo ""
  if [[ "$verdict" == "$VERDICT_CLEAN" && -n "$audit_verdict" && "$audit_verdict" != "$VERDICT_CLEAN" ]]; then
    echo "=== the review is $VERDICT_CLEAN but the security audit is $audit_verdict, and $CLOSE_SCRIPT_NAME refuses a hook change without a clean one: the rework is round $((round + 1)) ==="
    echo "=== next round: brief the rework from $FEATURES_LABEL/$FEATURE_SLUG/$ESCALATIONS_DIR_NAME/$AUDIT_PLAN_QUEUED.md, queue the re-review as $FEATURES_LABEL/$FEATURE_SLUG/review/incomplete/NN-review-<model>.md, add its stem with 'python3 analysis/manifest.py $SELF_ARG$FEATURE_SLUG set-plans <stem>...', then run: $SCRIPT_DIR/run-review.sh $SELF_ARG$FEATURE_SLUG — it queues the audit again ==="
  elif [[ "$verdict" == "$VERDICT_CLEAN" ]]; then
    echo "=== next: $CLOSE_SCRIPT $SELF_ARG$FEATURE_SLUG ==="
    echo "=== the close opens the PR with this verdict as its body, captures the cost on the branch, and asks for the merge — in that order, and nothing runs after the merge ==="
  else
    echo "=== nothing after this review runs: the rework is round $((round + 1)) ==="
    echo "=== next round: brief the rework from $escalations_label (route it like a build — direct, plans or by hand, at a cheaper model where the findings are precise), queue the re-review as $FEATURES_LABEL/$FEATURE_SLUG/review/incomplete/NN-review-<model>.md, add its stem with 'python3 analysis/manifest.py $SELF_ARG$FEATURE_SLUG set-plans <stem>...', then run: $SCRIPT_DIR/run-review.sh $SELF_ARG$FEATURE_SLUG ==="
  fi
elif [[ -n "${FEATURE_SLUG:-}" ]]; then
  echo ""
  echo "=== review pass did not finish cleanly — no verdict was recorded, and nothing after the review runs ==="
fi

exit "$run_rc"
