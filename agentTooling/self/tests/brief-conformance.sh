#!/usr/bin/env bash
set -uo pipefail

# Self-test for the brief-conformance checks (self/features/brief-conformance-checks/;
# LIFECYCLE.md → "The owner's brief and the conformance check"). Run by self/gate.sh, or by
# hand: bash self/tests/brief-conformance.sh
#
# A throwaway agentTooling checkout (the real scripts, analysis/ and hooks/ copied in) with a
# bare origin whose forge identity is a GitHub URL, a stub `claude` on PATH and a stub `gh`
# that remembers a PR per branch and records the title and body it was sent. The real
# feature-start.sh, run-review.sh, feature-close.sh, pr.sh and forge.sh run; nothing is
# re-implemented here. The stub claude answers the two kinds of launch differently: a launch
# with `--tools ""` is the conformance check (prompt on stdin, answer from $CONF_SRC), any
# other is a review (prompt as the last argument, report from $REVIEW_SRC). No model, no
# network.
#
# Asserts:
#   S1. `feature-start.sh --owner-brief <file>` commits OWNER_BRIEF.md byte for byte in the
#       `<slug>: start` commit; a missing, empty (whitespace) or non-regular path is refused
#       with nothing written (no branch, no worktree);
#   P1. the review prompt the runner builds holds the owner brief verbatim, its item list and
#       the report sections it asks for; without an owner brief it holds none of that, the
#       runner prints the one-line notice, and no conformance plan is queued;
#   C1. with an owner brief run-review.sh queues `01-conformance-opus` (in plans[]) and runs it
#       BEFORE `01-review-opus`, launched with `--tools ""`, the prompt on stdin and none of it
#       in argv; that prompt holds the owner brief, the item list and the diff, and none of
#       NOTES.md, the review brief or the feature directory; every other launch keeps its
#       arguments; the runner writes conformance-report.md from the stub's result; the round
#       counts once and the review's plan_end carries the verdict;
#   K1. close: a "partial" acceptance row is refused naming the row; all done with a
#       conformance "not done" for an item is refused naming the disagreement; a missing
#       acceptance table, a conformance report no review round committed and an owner brief
#       that differs from the start commit's copy are refused; nothing was written by any
#       refusal;
#   K2. all agreeing: the close proceeds, and the PR body the forge receives begins with
#       `## Acceptance`;
#   D1. a conformance out-of-scope file appears in the PR body's deviations section and one
#       deviation titles the PR `[deviations] <slug>`; "None" in both retitles it `<slug>`
#       on the re-close (pr-edit);
#   N1. no owner brief: the close proceeds as before, with its note, and the PR title is the
#       bare slug;
#   N2. no owner brief: a report with no deviations section leaves the PR title the bare
#       slug, one with a deviation marks it (R17);
#   B1. a conformance plan the feature does not owe (no owner brief, with a review queued or
#       alone after a clean round; or an owner brief and a stem that is not the review's NN
#       and model) is refused before anything runs;
#   L1. an owner brief written as a numbered list: both prompts list every item; a second
#       queueing of the same conformance stem leaves plans[] with it once;
#   U1. conformance.py alone: items (headings, a numbered list, headings winning), the table
#       parser (an unknown result value fails closed), deviations None / missing (with and
#       without --owner-brief-present), check-close and pr-body.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brief-conformance.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
export RATES_CHECK_SOURCE="$HERE/self/tests/fixtures/pricing/litellm-sample.json"
export AGENTTOOLING_PROFILE=local
unset CLAUDE_CODE_REMOTE CLAUDE_CODE_SESSION_ID GATE_RESUME PR_AUTO_MERGE

# The fixture
SLUG="conf"
NO_OWNER_SLUG="plain"
FORGE_URL="https://github.com/conf-owner/agentTooling.git"
FEATURE_REL="self/features/$SLUG"
OWNER_BRIEF_FILE="OWNER_BRIEF.md"
CONFORMANCE_REPORT_FILE="conformance-report.md"
REVIEW_STEM="01-review-opus"
CONFORMANCE_STEM="01-conformance-opus"
# Text that must reach the conformance executor, and text that must not
NOTES_SECRET="NOTES-RULING-SECRET-4711"
BRIEF_SECRET="REVIEW-BRIEF-CONTRACT-SECRET-4711"
DIFF_MARKER="FROBNICATE-THE-WIDGET"
STRAY_FILE="stray-extra.txt"
NOTICE_RE="note +no OWNER_BRIEF.md"
ACCEPTANCE_HEAD="## Acceptance"
DEVIATIONS_HEAD="## Deviations from the brief"
MARKED_TITLE="[deviations] $SLUG"

fails=0
# The last command's output a check was judging, shown under a FAIL so a red run explains itself
LAST_OUT=""
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); if [[ -n "$LAST_OUT" ]]; then printf '%s\n' "$LAST_OUT" | tail -n 25 | sed 's/^/        | /'; fi; }
check() { LAST_OUT="${out:-}"; if eval "$2"; then ok "$1"; else fail "$1"; fi; }
out=""
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

AT="$TMP/agentTooling"
ORIGIN="$TMP/origin.git"
FAKE_HOME="$TMP/home"
mkdir -p "$AT/analysis" "$AT/hooks" "$AT/templates/plans/features" "$AT/self/features" "$TMP/bin" "$FAKE_HOME/.claude/projects"

for f in feature-start.sh feature-capture.sh feature-close.sh plan-runner-roots.sh plan-runner-lib.sh \
         run-plans.sh run-verify.sh run-review.sh run-batch.sh stamp-timing.sh forge.sh env-profile.sh \
         conformance.py; do
  cp "$HERE/$f" "$AT/$f"
done
for f in pricing.py litellm_prices.py rates_history.json refresh_rates.py roots.py transcript.py \
         capture_planning.py report.py manifest.py routing.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
for f in shared_rules.py brief_header.py policy.py env_profile.py wire-settings.py allow-repo-commands.sh; do
  cp "$HERE/hooks/$f" "$AT/hooks/$f" 2>/dev/null || true
done
cp "$HERE/self/pr.sh" "$AT/self/pr.sh"
cp "$HERE/.gitignore" "$AT/.gitignore"
# A manifest template with real prose: the close refuses a README still matching its template
{
  printf '# A fixture feature\n\nThe goal of a fixture feature, written out.\n\n## Plans\n\n| Plan | What it does |\n|---|---|\n| `review/incomplete/01-review-opus.md` | the review |\n\n'
  sed -n '/^## Machine-readable/,$p' "$HERE/templates/plans/features/TEMPLATE.md"
} > "$AT/templates/plans/features/TEMPLATE.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/worktree-setup.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/open-session.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/gate.sh"
chmod +x "$AT"/*.sh "$AT/self/"*.sh

# Stub claude. `--tools ""` is the conformance check: it logs its argv (never a prompt),
# keeps the stdin it was given, and answers with the report in $CONF_SRC. Any other launch is
# a review: it keeps its last argv word as the prompt and writes $REVIEW_SRC to the report path.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
mode=review
for arg in "$@"; do if [[ "$arg" == "--tools" ]]; then mode=conformance; fi; done
echo "$mode" >> "${ORDER_LOG:?}"
if [[ "$mode" == conformance ]]; then
  { echo "launch"; printf '[%s]\n' "$@"; } >> "${CONF_ARGV_LOG:?}"
  cat > "${CONF_STDIN_OUT:?}"
  answer="$(cat "${CONF_SRC:?}")"
else
  printf '%s' "${@: -1}" > "${REVIEW_PROMPT_OUT:?}"
  { echo "launch"; printf '[%s]\n' "${@:1:$#-1}"; } >> "${REVIEW_ARGV_LOG:?}"
  cat "${REVIEW_SRC:?}" > "${CLAUDE_REPORT_OUT:?}"
  answer="done"
fi
printf '{"type":"system","subtype":"init","session_id":"stub"}\n'
jq -cn --arg r "$answer" '{type: "result", subtype: "success", is_error: false, result: $r, total_cost_usd: 0.5, num_turns: 1, session_id: "stub", usage: {}}'
STUB
# Stub gh: one PR per head branch; records the title and body of the POST that opens it and
# of the PATCH that refreshes it
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_ARGV_LOG:?}"
[[ "${1:-}" == "api" ]] || exit 0
shift
method=GET; path=""; head=""; title=""; body=""; have_title=0
while (( $# )); do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -f|-F)
      key="${2%%=*}"; value="${2#*=}"
      if [[ "$1" == "-F" && "$value" == @* ]]; then value="$(cat "${value#@}")"; fi
      case "$key" in head) head="$value" ;; title) title="$value"; have_title=1 ;; body) body="$value" ;; esac
      shift 2 ;;
    --jq) shift 2 ;;
    -*) shift ;;
    *) path="$1"; shift ;;
  esac
done
url="https://example.invalid/pr/1"
marker() { echo "${GH_PR_DIR:?}/$(printf '%s' "$1" | tr '/' '%')"; }
case "$method $path" in
  "GET repos/"*"/pulls") if [[ -f "$(marker "${head#*:}")" ]]; then cat "$(marker "${head#*:}")"; fi ;;
  "POST repos/"*"/pulls")
    echo "$url" > "$(marker "$head")"
    echo "POST $title" >> "${GH_TITLE_LOG:?}"
    printf '%s' "$body" > "${GH_BODY_OUT:?}"
    echo "$url" ;;
  "PATCH repos/"*"/pulls/"*)
    if (( have_title )); then echo "PATCH $title" >> "${GH_TITLE_LOG:?}"; else echo "PATCH" >> "${GH_TITLE_LOG:?}"; fi
    printf '%s' "$body" > "${GH_BODY_OUT:?}"
    echo "$url" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/claude" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export ORDER_LOG="$TMP/order.log" CONF_ARGV_LOG="$TMP/conf-argv.log" CONF_STDIN_OUT="$TMP/conf-stdin.out"
export REVIEW_PROMPT_OUT="$TMP/review-prompt.out" REVIEW_ARGV_LOG="$TMP/review-argv.log"
export GH_ARGV_LOG="$TMP/gh-argv.log" GH_TITLE_LOG="$TMP/gh-title.log" GH_BODY_OUT="$TMP/gh-body.out"
export GH_PR_DIR="$TMP/gh-prs"; mkdir -p "$GH_PR_DIR"
: > "$ORDER_LOG"; : > "$CONF_ARGV_LOG"; : > "$REVIEW_ARGV_LOG"; : > "$GH_ARGV_LOG"; : > "$GH_TITLE_LOG"
export REVIEW_SRC="$TMP/review-src.md" CONF_SRC="$TMP/conf-src.md"

git -C "$AT" init -q
gitq "$AT" symbolic-ref HEAD refs/heads/main
gitq "$AT" config user.email test@example.invalid
gitq "$AT" config user.name "brief conformance test"
gitq "$AT" add -A
gitq "$AT" commit -q -m init
git init -q --bare "$ORIGIN"
gitq "$ORIGIN" symbolic-ref HEAD refs/heads/main
# A GitHub identity for forge.sh, with git's own transport sent to the bare repo beside it
gitq "$AT" remote add origin "$FORGE_URL"
gitq "$AT" config "url.$ORIGIN.insteadOf" "$FORGE_URL"
gitq "$AT" push -q -u origin main

start() { ( cd "$TMP" && HOME="$FAKE_HOME" env -u CLAUDE_CODE_SESSION_ID "$AT/feature-start.sh" --self "$1" --no-gate "${@:2}" 2>&1 ); }
WT="$AT/.worktrees/$SLUG"
review() { ( cd "$1" && HOME="$FAKE_HOME" CLAUDE_REPORT_OUT="$1/self/review-report.md" ./run-review.sh --self "$2" 2>&1 ); }
close_it() { ( cd "$TMP" && HOME="$FAKE_HOME" "$1/feature-close.sh" --self "$2" 2>&1 ); }

echo "brief-conformance"

# ── S1: the start ──────────────────────────────────────────────────────────────
OWNER="$TMP/owner-brief.md"
cat > "$OWNER" <<'BRIEF'
# The owner's request, word for word

Make the widget frobnicate. Quotes " and ', a $(touch should-not-exist), `ticks` and a trailing space

### 1. Add the frobnicate command

It prints FROBNICATE-THE-WIDGET and exits 0.

### 2. Document it

A README line names the command.
BRIEF
for bad in "$TMP/no-such-owner.md" "$TMP"; do
  out="$(start "$SLUG" --owner-brief "$bad")"; rc=$?
  check "S1a. --owner-brief '${bad#"$TMP"/}' (missing or not a regular file) is refused, nothing written (got $rc)" \
    '[[ $rc -eq 1 ]] && grep -q "owner-brief" <<<"$out" && [[ ! -e "$AT/.worktrees" ]] && ! git -C "$AT" rev-parse -q --verify "refs/heads/$SLUG" >/dev/null'
done
printf '  \n\t\n' > "$TMP/blank.md"
out="$(start "$SLUG" --owner-brief "$TMP/blank.md")"; rc=$?
check "S1b. a whitespace-only owner brief is refused, nothing written (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "is empty" <<<"$out" && [[ ! -e "$AT/.worktrees" ]] && ! git -C "$AT" rev-parse -q --verify "refs/heads/$SLUG" >/dev/null'
out="$(start "$SLUG" --owner-brief "$OWNER")"; rc=$?
check "S1c. the start with --owner-brief succeeds (got $rc)" '[[ $rc -eq 0 ]] && [[ -d "$WT" ]]'
START_SHA="$(git -C "$WT" log --format='%H %s' | awk -v s="$SLUG: start" 'substr($0, index($0, " ") + 1) == s { print $1 }')"
check "S1d. OWNER_BRIEF.md is in the '$SLUG: start' commit, byte for byte" \
  '[[ -n "$START_SHA" ]] && git -C "$WT" show "$START_SHA:$FEATURE_REL/$OWNER_BRIEF_FILE" | cmp -s - "$OWNER" && cmp -s "$WT/$FEATURE_REL/$OWNER_BRIEF_FILE" "$OWNER"'
check "S1e. no copy of the owner brief was written under the primary checkout" '[[ ! -e "$AT/$FEATURE_REL" ]]'

# The feature's own work, its notes and a real review brief (the start's stub is refused)
printf '%s\n' "$DIFF_MARKER" > "$WT/frob.txt"
printf '# Notes\n\n%s\n' "$NOTES_SECRET" > "$WT/$FEATURE_REL/NOTES.md"
printf '# 01 — review: %s\n\nJudge it. %s\n' "$SLUG" "$BRIEF_SECRET" > "$WT/$FEATURE_REL/review/incomplete/$REVIEW_STEM.md"
gitq "$WT" add -A
gitq "$WT" commit -q -m "$SLUG: the work"

review_report() {  # review_report <acceptance rows> <deviations text> — the stub review's report
  printf 'Verdict: clean\n\nNo findings.\n\n%s\n\n| Item | Evidence | Result |\n|---|---|---|\n%s\n\n%s\n\n%s\n' \
    "$ACCEPTANCE_HEAD" "$1" "$DEVIATIONS_HEAD" "$2" > "$REVIEW_SRC"
}
conformance_report() {  # conformance_report <rows> <out-of-scope text> — the stub conformance answer
  printf '## Conformance\n\n| Item | Evidence | Result |\n|---|---|---|\n%s\n\n## Out of scope\n\n%s\n' "$1" "$2" > "$CONF_SRC"
}
ROWS_PARTIAL=$'| 1 | frob.txt:1 | done |\n| 2 | README line | partial |'
ROWS_DONE=$'| 1 | frob.txt:1 | done |\n| 2 | README line | done |'
ROWS_CONF_NOT_DONE=$'| 1 | frob.txt:1 | done |\n| 2 | nothing found | not done |'
review_report "$ROWS_PARTIAL" "None"
conformance_report "$ROWS_DONE" "None"

# ── C1 / P1: round 1, with an owner brief ──────────────────────────────────────
out="$(review "$WT" "$SLUG")"; rc=$?
FEATURE_WT="$WT/$FEATURE_REL"
check "C1a. the pass exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "C1b. the conformance plan was queued with the review's NN and model, and is in plans[]" \
  '[[ -f "$FEATURE_WT/review/complete/$CONFORMANCE_STEM.md" ]] && [[ "$(python3 -B "$WT/analysis/manifest.py" --self "$SLUG" get plans 2>/dev/null)" == *"$CONFORMANCE_STEM"* ]]'
check "C1c. it ran before the review, once each" '[[ "$(tr "\n" " " < "$ORDER_LOG")" == "conformance review " ]]'
check "C1d. launched with --tools \"\" and nothing of its prompt in argv" \
  '[[ "$(grep -A1 -x "\[--tools\]" "$CONF_ARGV_LOG" | tail -1)" == "[]" ]] && ! grep -qF "BEGIN OWNER BRIEF" "$CONF_ARGV_LOG" && ! grep -qF "$DIFF_MARKER" "$CONF_ARGV_LOG"'
check "C1e. its stdin prompt holds the owner brief verbatim, the item ids and the diff" \
  '[[ "$(cat "$CONF_STDIN_OUT")" == *"$(cat "$OWNER")"* ]] && grep -q "^- 1 — Add the frobnicate command$" "$CONF_STDIN_OUT" && grep -q "^- 2 — Document it$" "$CONF_STDIN_OUT" && grep -qF "+$DIFF_MARKER" "$CONF_STDIN_OUT"'
check "C1f. ... and none of NOTES.md, the review brief, or the feature directory's files" \
  '! grep -qF "$NOTES_SECRET" "$CONF_STDIN_OUT" && ! grep -qF "$BRIEF_SECRET" "$CONF_STDIN_OUT" && ! grep -qF "$FEATURE_REL/NOTES.md" "$CONF_STDIN_OUT" && ! grep -qF "$FEATURE_REL/review" "$CONF_STDIN_OUT"'
check "C1g. the review kept its own arguments: --allowedTools Bash, the prompt as the last word" \
  'grep -qx "\[--allowedTools\]" "$REVIEW_ARGV_LOG" && grep -qx "\[Bash\]" "$REVIEW_ARGV_LOG" && ! grep -qx "\[--tools\]" "$REVIEW_ARGV_LOG" && grep -qF "$BRIEF_SECRET" "$REVIEW_PROMPT_OUT"'
check "C1h. the runner wrote conformance-report.md from the stub's result, committed by the round" \
  'diff -q <(printf "%s\n" "$(cat "$CONF_SRC")") "$FEATURE_WT/$CONFORMANCE_REPORT_FILE" >/dev/null && [[ "$(git -C "$WT" log -1 --format=%s -- "$FEATURE_REL/$CONFORMANCE_REPORT_FILE")" == "$SLUG: review round 1" ]] && [[ -z "$(git -C "$WT" status --porcelain)" ]]'
check "C1i. the pass printed the one-line summary" 'grep -q "conformance: 2 item(s) - 2 done, 0 partial, 0 not done; 0 file(s) out of scope" <<<"$out"'
check "C1j. one round: the conformance plan is no round, and the review's plan_end carries the verdict" \
  '[[ "$(jq -r "select(.event == \"plan_end\" and .plan == \"$REVIEW_STEM\") | .verdict" "$FEATURE_WT/timing.jsonl" | tail -1)" == clean ]] && [[ "$(jq -r "select(.event == \"plan_end\" and .plan == \"$CONFORMANCE_STEM\") | .verdict // \"none\"" "$FEATURE_WT/timing.jsonl" | tail -1)" == none ]] && [[ "$(jq -r "select(.event == \"plan_end\") | .round" "$FEATURE_WT/timing.jsonl" | sort -u | tr "\n" " ")" == "1 " ]]'
check "C1k. the review prompt holds the owner brief verbatim, the item ids and the two report sections it asks for" \
  '[[ "$(cat "$REVIEW_PROMPT_OUT")" == *"$(cat "$OWNER")"* ]] && grep -q "^- 1 — Add the frobnicate command$" "$REVIEW_PROMPT_OUT" && grep -qF "## Acceptance" "$REVIEW_PROMPT_OUT" && grep -qF "## Deviations from the brief" "$REVIEW_PROMPT_OUT" && ! grep -q "no OWNER_BRIEF.md" "$REVIEW_PROMPT_OUT"'
check "C1l. no stale-report leftovers: a conformance report exists for this round only" '[[ -f "$FEATURE_WT/$CONFORMANCE_REPORT_FILE" ]]'

# ── K1: the close refuses ──────────────────────────────────────────────────────
before="$(git -C "$WT" rev-parse HEAD)"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1a. a partial acceptance row is refused, naming the row (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "acceptance row .2. is .partial., not done" <<<"$out" && ! grep -q "^  pr  " <<<"$out"'
check "K1b. ... and nothing was written: no PR call, the same head, a clean tree" \
  '[[ ! -s "$GH_ARGV_LOG" ]] && [[ "$(git -C "$WT" rev-parse HEAD)" == "$before" ]] && [[ -z "$(git -C "$WT" status --porcelain)" ]]'

# Round N+1: queue the next review beside the same feature, as the runner's next-round line says
next_round() {  # next_round <n> — queue <n>-review-opus and run the pass
  local n="$1" stem plans
  stem="0$n-review-opus"
  printf '# 0%s — review: %s\n\nJudge it again. %s\n' "$n" "$SLUG" "$BRIEF_SECRET" > "$FEATURE_WT/review/incomplete/$stem.md"
  plans="$(python3 -B "$WT/analysis/manifest.py" --self "$SLUG" get plans 2>/dev/null | jq -r '.[]' | tr '\n' ' ')"
  python3 -B "$WT/analysis/manifest.py" --self "$SLUG" set-plans $plans "$stem" >/dev/null
  review "$WT" "$SLUG"
}

review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_CONF_NOT_DONE" "None"
out="$(next_round 2)"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1c. all done in the review but not done in the conformance check: refused, naming the disagreement (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "owner item 2 (Document it): review says done, conformance says not done" <<<"$out" && [[ ! -s "$GH_ARGV_LOG" ]]'

review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_DONE" "None"
sed -i.bak '/^## Acceptance$/,/^| 2 /d' "$REVIEW_SRC"; rm -f "$REVIEW_SRC.bak"
out="$(next_round 3)"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1d. a review report with no acceptance table is refused (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "has no .## Acceptance. table" <<<"$out" && [[ ! -s "$GH_ARGV_LOG" ]]'

# A conformance report no review round committed is no evidence: rewrite it under another subject
review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_DONE" "None"
out="$(next_round 4)"
echo "# edited after the round" >> "$FEATURE_WT/$CONFORMANCE_REPORT_FILE"
gitq "$WT" add -A
gitq "$WT" commit -q -m "$SLUG: cost records"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1e. a conformance report not last written by the round's own commit is refused (got $rc)" \
  '[[ $rc -ne 0 ]] && grep -qE "landed after the review judged|was last written by" <<<"$out" && [[ ! -s "$GH_ARGV_LOG" ]]'

# An owner brief edited after the start is refused: the yardstick cannot move under the review
printf '\n### 3. A narrower request\n' >> "$FEATURE_WT/$OWNER_BRIEF_FILE"
gitq "$WT" add -A
gitq "$WT" commit -q -m "$SLUG: soften the brief"
review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_DONE" "None"
out="$(next_round 5)"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1f. an OWNER_BRIEF.md that differs from the start commit's copy is refused (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "differs from the copy the .$SLUG: start. commit carried" <<<"$out" && [[ ! -s "$GH_ARGV_LOG" ]]'
gitq "$WT" checkout "$START_SHA" -- "$FEATURE_REL/$OWNER_BRIEF_FILE"
gitq "$WT" commit -q -m "$SLUG: restore the brief"

# An owner brief the start carried and the judged tree no longer holds is refused: deleting it
# must not turn the close into the rollout's no-brief note
gitq "$WT" rm -q "$FEATURE_REL/$OWNER_BRIEF_FILE"
gitq "$WT" commit -q -m "$SLUG: drop the brief"
review_report "$ROWS_DONE" "None"
out="$(next_round 6)"
out="$(close_it "$WT" "$SLUG")"; rc=$?
check "K1g. an OWNER_BRIEF.md the start carried and the judged head lacks is refused (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "carried self/features/$SLUG/$OWNER_BRIEF_FILE and the head the review judged does not" <<<"$out" && ! grep -q "note  *no OWNER_BRIEF.md" <<<"$out" && [[ ! -s "$GH_ARGV_LOG" ]]'
gitq "$WT" checkout "$START_SHA" -- "$FEATURE_REL/$OWNER_BRIEF_FILE"
gitq "$WT" commit -q -m "$SLUG: restore the brief again"

# ── K2 / D1: all agreeing, with one deviation and one out-of-scope file ───────
review_report "$ROWS_DONE" "- reads item 2 as a README line, not a man page"
conformance_report "$ROWS_DONE" "- $STRAY_FILE — ties to no item"
out="$(next_round 7)"
out="$(close_it "$WT" "$SLUG")"
check "K2a. every row done and the conformance check agreeing: the close goes on to open the PR" \
  'grep -q "every owner item is done in the review.s acceptance table" <<<"$out" && grep -q "^  pr  " <<<"$out" && grep -q "^POST " "$GH_TITLE_LOG"'
check "K2b. the PR body the forge received begins with ## Acceptance" '[[ "$(head -n 1 "$GH_BODY_OUT")" == "$ACCEPTANCE_HEAD" ]]'
check "K2c. ... then the deviations section, before the verdict line and the rest of the report" \
  '[[ "$(grep -n "^## " "$GH_BODY_OUT" | head -n 2 | cut -d: -f2 | tr "\n" "|")" == "$ACCEPTANCE_HEAD|$DEVIATIONS_HEAD|" ]] && [[ "$(grep -n "^Verdict: clean" "$GH_BODY_OUT" | head -n 1 | cut -d: -f1)" -gt "$(grep -n "^$DEVIATIONS_HEAD" "$GH_BODY_OUT" | cut -d: -f1)" ]]'
check "K2d. the out-of-scope file is in the deviations section, beside the review's own deviation" \
  '[[ "$(sed -n "/^$DEVIATIONS_HEAD/,/^## /p" "$GH_BODY_OUT")" == *"$STRAY_FILE"* ]] && [[ "$(sed -n "/^$DEVIATIONS_HEAD/,/^## /p" "$GH_BODY_OUT")" == *"not a man page"* ]]'
check "K2e. one deviation titles the PR '$MARKED_TITLE'" '[[ "$(tail -n 1 "$GH_TITLE_LOG")" == "POST $MARKED_TITLE" ]]'

# The re-close of a clean round with "None" everywhere: the PR already open is retitled, unmarked
review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_DONE" "None"
out="$(next_round 8)"
out="$(close_it "$WT" "$SLUG")"
check "D1a. 'None' in both: the PR an earlier round opened is edited and its title is the bare slug" \
  '[[ "$(tail -n 1 "$GH_TITLE_LOG")" == "PATCH $SLUG" ]] && [[ "$(head -n 1 "$GH_BODY_OUT")" == "$ACCEPTANCE_HEAD" ]] && [[ "$(sed -n "/^$DEVIATIONS_HEAD/,/^## /p" "$GH_BODY_OUT" | sed -n 3p)" == "None" ]]'

# ── N1 / P1: a feature with no owner brief ─────────────────────────────────────
out="$(start "$NO_OWNER_SLUG")"; rc=$?
PWT="$AT/.worktrees/$NO_OWNER_SLUG"
PFEATURE="$PWT/self/features/$NO_OWNER_SLUG"
check "N1a. a start without --owner-brief writes no OWNER_BRIEF.md (got $rc)" '[[ $rc -eq 0 && ! -e "$PFEATURE/$OWNER_BRIEF_FILE" ]]'
printf 'plain work\n' > "$PWT/plain.txt"
printf '# 01 — review: %s\n\nJudge it.\n' "$NO_OWNER_SLUG" > "$PFEATURE/review/incomplete/$REVIEW_STEM.md"
gitq "$PWT" add -A
gitq "$PWT" commit -q -m "$NO_OWNER_SLUG: the work"
printf 'Verdict: clean\n\nNo findings.\n\n%s\n\nNone\n' "$DEVIATIONS_HEAD" > "$REVIEW_SRC"
: > "$ORDER_LOG"; : > "$GH_TITLE_LOG"
out="$(review "$PWT" "$NO_OWNER_SLUG")"; rc=$?
check "N1b. the runner prints the notice once, queues no conformance plan and runs only the review (got $rc)" \
  '[[ $rc -eq 0 ]] && [[ "$(grep -cE "$NOTICE_RE" <<<"$out")" == 1 ]] && [[ "$(tr "\n" " " < "$ORDER_LOG")" == "review " ]] && [[ -z "$(ls "$PFEATURE/review/complete" | grep conformance)" ]]'
check "N1c. ... and the review prompt carries no owner section and asks for no acceptance table, only the deviations section (R17)" \
  '! grep -qF "THE OWNER" "$REVIEW_PROMPT_OUT" && ! grep -qF "BEGIN OWNER BRIEF" "$REVIEW_PROMPT_OUT" && ! grep -qF "## Acceptance" "$REVIEW_PROMPT_OUT" && ! grep -qF "owner'"'"'s request listed above" "$REVIEW_PROMPT_OUT" && grep -qF "$DEVIATIONS_HEAD" "$REVIEW_PROMPT_OUT"'
out="$(close_it "$PWT" "$NO_OWNER_SLUG")"
check "N1d. the close proceeds as before, with its note and no acceptance requirement" \
  'grep -qE "note +no OWNER_BRIEF.md in self/features/$NO_OWNER_SLUG at the judged head" <<<"$out" && grep -q "^  pr  " <<<"$out" && ! grep -q "do not clear this round" <<<"$out" && ! grep -qE "^  refused  (the judged tree|this feature carries)" <<<"$out"'
check "N1e. the PR is titled the bare slug, its body the report" \
  '[[ "$(tail -n 1 "$GH_TITLE_LOG")" == "POST $NO_OWNER_SLUG" ]] && grep -q "^Verdict: clean" "$GH_BODY_OUT"'

# ── R17: the title mark of a feature with no owner brief ──────────────────────
no_brief_close() {  # no_brief_close <slug> <review report text> — a whole round and the close, no owner brief
  local slug="$1" wt="$AT/.worktrees/$1"
  start "$slug" >/dev/null
  printf 'work of %s\n' "$slug" > "$wt/$slug.txt"
  printf '# 01 — review: %s\n\nJudge it.\n' "$slug" > "$wt/self/features/$slug/review/incomplete/$REVIEW_STEM.md"
  gitq "$wt" add -A
  gitq "$wt" commit -q -m "$slug: the work"
  printf '%s' "$2" > "$REVIEW_SRC"
  : > "$GH_TITLE_LOG"
  review "$wt" "$slug" >/dev/null
  close_it "$wt" "$slug"
}
BARE_SLUG="bare"
out="$(no_brief_close "$BARE_SLUG" $'Verdict: clean\n\nNo findings.\n')"
check "N2a. no owner brief and no deviations section in the report: the close proceeds and the PR title is the bare slug" \
  'grep -q "^  pr  " <<<"$out" && [[ "$(tail -n 1 "$GH_TITLE_LOG")" == "POST $BARE_SLUG" ]] && ! grep -q "^  mark  " <<<"$out"'
DEVS_SLUG="devs"
out="$(no_brief_close "$DEVS_SLUG" $'Verdict: clean\n\nNo findings.\n\n## Deviations from the brief\n\n- one thing the work did differently\n')"
check "N2b. no owner brief, a deviations section with one deviation: the PR is marked" \
  'grep -q "^  pr  " <<<"$out" && [[ "$(tail -n 1 "$GH_TITLE_LOG")" == "POST [deviations] $DEVS_SLUG" ]]'

# ── R17 / B1: a conformance plan the feature does not owe is refused, nothing run ─
# With a review queued beside it and no owner brief
STRAY_SLUG="stray"
start "$STRAY_SLUG" >/dev/null
SWT="$AT/.worktrees/$STRAY_SLUG"
SFEATURE="$SWT/self/features/$STRAY_SLUG"
printf '# 01 — review: %s\n\nJudge it.\n' "$STRAY_SLUG" > "$SFEATURE/review/incomplete/$REVIEW_STEM.md"
printf '# 02 — conformance\n' > "$SFEATURE/review/incomplete/02-conformance-opus.md"
gitq "$SWT" add -A
gitq "$SWT" commit -q -m "$STRAY_SLUG: the work"
: > "$ORDER_LOG"
out="$(review "$SWT" "$STRAY_SLUG")"; rc=$?
check "B1a. a stray conformance plan beside a review, no owner brief: refused with 'delete it', nothing run (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "02-conformance-opus.md is queued, but this feature has no OWNER_BRIEF.md.*delete it" <<<"$out" && [[ ! -s "$ORDER_LOG" ]] && [[ -z "$(ls "$SFEATURE/review/complete" 2>/dev/null)" ]]'
# Alone, after a clean round (the plain feature's round 1 is done)
printf '# 02 — conformance\n' > "$PFEATURE/review/incomplete/02-conformance-opus.md"
: > "$ORDER_LOG"
out="$(review "$PWT" "$NO_OWNER_SLUG")"; rc=$?
check "B1b. a stray conformance plan alone after a clean round: refused, nothing run (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "02-conformance-opus.md is queued, but this feature has no OWNER_BRIEF.md.*delete it" <<<"$out" && [[ ! -s "$ORDER_LOG" ]]'
rm -f "$PFEATURE/review/incomplete/02-conformance-opus.md"

# ── L1: an owner brief written as a numbered list ──────────────────────────────
LIST_BRIEF="$TMP/list-brief.md"
cat > "$LIST_BRIEF" <<'BRIEF'
# What the feature was supposed to do

1. **The owner's request is the review's yardstick.** A feature with a brief
   is judged against it, word for word:
   1. a nested numbered line is no item
   - a nested bullet
2. **The review report carries an acceptance table.** One row per item.
3. **An independent check runs.** With no tools.
4. **A deviations section exists.** And pr.sh marks the PR.
5. **Rollout.** Falls back to today's behaviour.
BRIEF
LISTY_SLUG="listy"
out="$(start "$LISTY_SLUG" --owner-brief "$LIST_BRIEF")"; rc=$?
LWT="$AT/.worktrees/$LISTY_SLUG"
LFEATURE="$LWT/self/features/$LISTY_SLUG"
printf 'listy work\n' > "$LWT/listy.txt"
printf '# 01 — review: %s\n\nJudge it.\n' "$LISTY_SLUG" > "$LFEATURE/review/incomplete/$REVIEW_STEM.md"
gitq "$LWT" add -A
gitq "$LWT" commit -q -m "$LISTY_SLUG: the work"
review_report "$ROWS_DONE" "None"
conformance_report "$ROWS_DONE" "None"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "L1a. a list-shaped owner brief: the conformance prompt lists all five items, by their bold titles (got $rc)" \
  '[[ $rc -eq 0 ]] && [[ "$(grep -c -e "^- [1-5] — " "$CONF_STDIN_OUT")" == 5 ]] && grep -qxF -e "- 1 — The owner'"'"'s request is the review'"'"'s yardstick." "$CONF_STDIN_OUT" && grep -qxF -e "- 5 — Rollout." "$CONF_STDIN_OUT"'
check "L1b. ... and so does the review prompt" \
  '[[ "$(grep -c -e "^- [1-5] — " "$REVIEW_PROMPT_OUT")" == 5 ]] && grep -qxF -e "- 3 — An independent check runs." "$REVIEW_PROMPT_OUT"'
listy_plans() { python3 -B "$LWT/analysis/manifest.py" --self "$LISTY_SLUG" get plans 2>/dev/null | jq -r '.[]' | grep -cx "$CONFORMANCE_STEM"; }
check "L1c. the conformance stem is in plans[] once" '[[ "$(listy_plans)" == 1 ]]'
# The review moved back to incomplete/ after its check finished (the refusal's own advice): the
# same stem is queued again and must not be appended a second time
mv "$LFEATURE/review/complete/$REVIEW_STEM.md" "$LFEATURE/review/incomplete/$REVIEW_STEM.md"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "L1d. a second queueing for the same NN leaves the stem in plans[] once (got $rc)" '[[ $rc -eq 0 ]] && [[ "$(listy_plans)" == 1 ]]'
# An owner brief, a review queued, and a conformance stem that is not that review's
printf '# 03 — review\n\nJudge it.\n' > "$LFEATURE/review/incomplete/03-review-opus.md"
printf '# 09 — conformance\n' > "$LFEATURE/review/incomplete/09-conformance-opus.md"
: > "$ORDER_LOG"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "B1c. an owner brief, a conformance plan whose NN is not the review's: refused, nothing run (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "09-conformance-opus.md is queued, but this review.s conformance check is 03-conformance-opus.*delete it" <<<"$out" && [[ ! -s "$ORDER_LOG" ]] && [[ ! -e "$LFEATURE/review/incomplete/03-conformance-opus.md" ]]'
rm -f "$LFEATURE/review/incomplete/09-conformance-opus.md"
printf '# 03 — conformance\n' > "$LFEATURE/review/incomplete/03-conformance-sonnet.md"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "B1d. ... and one whose model is not the review's: refused, nothing run (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "03-conformance-sonnet.md is queued, but this review.s conformance check is 03-conformance-opus.*delete it" <<<"$out" && [[ ! -s "$ORDER_LOG" ]]'
rm -f "$LFEATURE/review/incomplete/03-conformance-sonnet.md" "$LFEATURE/review/incomplete/03-review-opus.md"
# The owed plan, already queued by an earlier pass that was interrupted, is never refused: the
# refusal and queue_conformance_check compute the same stem (round 2 review, escalation 1).
# Interrupted during the check: the check in inprogress/, the review still in incomplete/
printf '# 03 — review\n\nJudge it.\n' > "$LFEATURE/review/incomplete/03-review-opus.md"
printf '# 03 — conformance\n' > "$LFEATURE/review/inprogress/03-conformance-opus.md"
: > "$ORDER_LOG"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "L1e. the owed check left in inprogress/ beside its review is resumed, not refused: check, then review (got $rc)" \
  '[[ $rc -eq 0 ]] && ! grep -q "refused" <<<"$out" && [[ "$(tr "\n" " " < "$ORDER_LOG")" == "conformance review " ]]'
# Interrupted with both in inprogress/: the review resumed with its owed check beside it
printf '# 04 — review\n\nJudge it.\n' > "$LFEATURE/review/inprogress/04-review-opus.md"
printf '# 04 — conformance\n' > "$LFEATURE/review/inprogress/04-conformance-opus.md"
: > "$ORDER_LOG"
out="$(review "$LWT" "$LISTY_SLUG")"; rc=$?
check "L1f. a review resumed from inprogress/ with its owed check beside it is not refused: check, then review (got $rc)" \
  '[[ $rc -eq 0 ]] && ! grep -q "refused" <<<"$out" && [[ "$(tr "\n" " " < "$ORDER_LOG")" == "conformance review " ]]'

# ── U1: conformance.py alone ───────────────────────────────────────────────────
CP="$HERE/conformance.py"
U="$TMP/unit"; mkdir -p "$U"
printf 'Just a paragraph, no numbered headings.\n\n## Not an item\n' > "$U/plain-brief.md"
printf '## 1) First\n\n```\n### 9. inside a fence\n```\n\n### 2. Second one ###\n\n#### 10. Tenth\n### 3 No dot\n' > "$U/numbered-brief.md"
FALLBACK_ITEM=$'1\tthe owner\'s request'
check "U1a. items: a brief with no numbered heading is one item, id 1" \
  '[[ "$(python3 -B "$CP" items "$U/plain-brief.md")" == "$FALLBACK_ITEM" ]]'
check "U1b. items: numbered headings only, fences skipped, ids in order, trailing #s trimmed" \
  '[[ "$(python3 -B "$CP" items "$U/numbered-brief.md" | tr "\t\n" "~|")" == "1~First|2~Second one|10~Tenth|" ]]'
python3 -B "$CP" items "$U/no-such-file.md" >/dev/null 2>&1; rc=$?
check "U1c. items: an unreadable file exits 2 (got $rc)" '[[ $rc -eq 2 ]]'
cat > "$U/report.md" <<'REPORT'
Verdict: clean

## Acceptance

| Item | Evidence | Result |
|---|---|---|
| 1 | `a | b` test | Done |
| 2. — x | file:1 | `partial` |
| 3: y | file:2 | looks fine |
| the review's own line | t | not   done |
| 4 | none | |

## Deviations from the brief

None.
REPORT
table="$(python3 -B "$CP" table "$U/report.md" Acceptance | cut -f1,2 | tr "\t\n" "~|")"
check "U1d. table: ids read from 1 / 2. / 3:, results normalised, an unknown value kept as unknown:<raw>, a blank result unknown" \
  '[[ "$table" == "1~done|2~partial|3~unknown:looks fine|the review'"'"'s own line~not done|4~unknown:|" ]]'
check "U1e. table: a pipe inside evidence does not move the result" '[[ "$(python3 -B "$CP" table "$U/report.md" Acceptance | sed -n 1p | cut -f2,3)" == $'"'"'done\t`a | b` test'"'"' ]]'
python3 -B "$CP" table "$U/report.md" "No such section" >/dev/null 2>&1; rc=$?
check "U1f. table: a missing section exits 3 (got $rc)" '[[ $rc -eq 3 ]]'
check "U1g. deviations: None. is none; free text is non-empty" \
  '[[ "$(python3 -B "$CP" deviations "$U/report.md")" == none ]] && printf "## Deviations from the brief\n\n- x\n" > "$U/d.md" && [[ "$(python3 -B "$CP" deviations "$U/d.md")" == non-empty ]]'
printf 'Verdict: clean\n\nNo findings.\n' > "$U/nodev.md"
check "U1h. deviations: a missing section reads as non-empty when told there is an owner brief, with the reason on stderr; as none otherwise (R17)" \
  '[[ "$(python3 -B "$CP" deviations "$U/nodev.md" --owner-brief-present 2>/dev/null)" == non-empty ]] && python3 -B "$CP" deviations "$U/nodev.md" --owner-brief-present 2>&1 >/dev/null | grep -q "no .## Deviations from the brief. section" && [[ "$(python3 -B "$CP" deviations "$U/nodev.md" 2>/dev/null)" == none ]]'
EXPECTED_LIST_ITEMS="1~The owner's request is the review's yardstick.|2~The review report carries an acceptance table.|3~An independent check runs.|4~A deviations section exists.|5~Rollout.|"
check "U1n. items: a brief that is a top-level numbered list gives ids 1-5 with the bold titles; nested lines are no items (R17)" \
  '[[ "$(python3 -B "$CP" items "$LIST_BRIEF" | tr "\t\n" "~|")" == "$EXPECTED_LIST_ITEMS" ]]'
printf '# Request\n\n1. **A list item** that loses.\n2. **Another** one.\n\n### 1. A heading item\n\n### 2. Another heading item\n' > "$U/both-brief.md"
check "U1o. items: with numbered headings and a numbered list, the headings win" \
  '[[ "$(python3 -B "$CP" items "$U/both-brief.md" | tr "\t\n" "~|")" == "1~A heading item|2~Another heading item|" ]]'
printf '1) Plain item with **bold** inside\n2. __Under__ and more\n\n```\n3. inside a fence\n```\n  4. indented, no item\n' > "$U/plain-list.md"
check "U1p. items: markers are stripped from a title with no opening bold span, a bold span is cut at its end, fences and indented lines are skipped" \
  '[[ "$(python3 -B "$CP" items "$U/plain-list.md" | tr "\t\n" "~|")" == "1~Plain item with bold inside|2~Under|" ]]'
printf '## 1. A\n\n## 2. B\n' > "$U/brief2.md"
printf '## Conformance\n\n| Item | Evidence | Result |\n|---|---|---|\n| 1 | x | done |\n| 2 | y | maybe |\n\n## Out of scope\n\nNone\n' > "$U/conf.md"
printf 'Verdict: clean\n\n## Acceptance\n\n| Item | Evidence | Result |\n|---|---|---|\n| 1 | x | done |\n| 2 | y | done |\n\n## Deviations from the brief\n\nNone\n' > "$U/rev.md"
probs="$(python3 -B "$CP" check-close --owner-brief "$U/brief2.md" --review "$U/rev.md" --conformance "$U/conf.md")"; rc=$?
check "U1i. check-close: an unknown conformance value fails closed, named as a disagreement (got $rc)" \
  '[[ $rc -eq 1 && "$probs" == "owner item 2 (B): review says done, conformance says unknown:maybe" ]]'
printf 'Verdict: clean\n\n## Acceptance\n\n| Item | Evidence | Result |\n|---|---|---|\n| 1 | x | done |\n| extra line | y | partial |\n' > "$U/rev-bad.md"
probs="$(python3 -B "$CP" check-close --owner-brief "$U/brief2.md" --review "$U/rev-bad.md" --conformance "$U/conf.md")"
check "U1j. check-close: the review's own acceptance line is held to the rule, an owner item with no row and a missing deviations section are named" \
  '[[ "$probs" == *"acceptance row '"'"'extra line'"'"' is '"'"'partial'"'"'"* && "$probs" == *"owner item 2 (B) has no row"* && "$probs" == *"no '"'"'## Deviations from the brief'"'"' section"* ]]'
printf '## Conformance\n\n| Item | Evidence | Result |\n|---|---|---|\n| 1 | x | done |\n| 2 | y | done |\n\n## Out of scope\n\n- a.txt — why\n- b.txt — why\n' > "$U/conf-ok.md"
body="$(python3 -B "$CP" pr-body "$U/rev.md" --conformance "$U/conf-ok.md")"
check "U1k. pr-body: Acceptance first, deviations second with the out-of-scope files, the verdict after; deviations then says non-empty" \
  '[[ "$(head -n 1 <<<"$body")" == "## Acceptance" ]] && [[ "$body" == *"## Deviations from the brief"*"a.txt"*"b.txt"*"Verdict: clean"* ]] && printf "%s\n" "$body" > "$U/body.md" && [[ "$(python3 -B "$CP" deviations "$U/body.md")" == non-empty ]]'
check "U1l. pr-body: a report with no acceptance section is passed through unchanged" \
  'python3 -B "$CP" pr-body "$U/nodev.md" | cmp -s - "$U/nodev.md"'
check "U1m. summary: counts the owner items by the conformance report's verdicts" \
  '[[ "$(python3 -B "$CP" summary --owner-brief "$U/brief2.md" --conformance "$U/conf.md")" == "conformance: 2 item(s) - 1 done, 0 partial, 1 not done; 0 file(s) out of scope" ]]'

echo ""
if (( fails )); then
  echo "brief-conformance: $fails check(s) FAILED"
  exit 1
fi
echo "brief-conformance: all checks passed"
