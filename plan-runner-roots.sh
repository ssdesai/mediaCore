#!/usr/bin/env bash
# Root resolution shared by run-plans.sh, run-verify.sh, run-review.sh and
# run-batch.sh. Sourced (never executed) before plan-runner-lib.sh, which needs
# REPO_DIR and FEATURES_DIR already set.
#
# Two modes, differing only in which repo's queue a run drains:
#
#   normal   REPO_DIR = the consuming repo root (this checkout's parent)
#            queue    = plans/features/<slug>/
#   --self   REPO_DIR = this agentTooling checkout
#            queue    = self/features/<slug>/
#
# Self-mode is how agentTooling builds its own features with its own harness. It lives
# here rather than in each wrapper for the same reason plan-runner-lib.sh exists: three
# copies of a two-branch path rule is three chances for the modes to drift apart, and a
# run that resolves the wrong root files its cost records under the wrong repo.

# resolve_roots <first-arg>
#
# Inspects only whether the first argument is --self; the caller does the shift, so
# nothing here mutates the caller's positional parameters.
#
# Sets, for the caller:
#   SELF_MODE          1 when --self was passed, else 0
#   REPO_DIR           the root the runner cd's to, so claude runs from there
#   FEATURES_DIR       absolute path to the per-feature tree
#   FEATURES_LABEL     that same path as a human would type it FROM REPO_DIR — used in
#                      messages, which are all printed after run_all's cd
#   SELF_ARG           "--self " or "", so a message can echo back a command line that
#                      actually reproduces this run
#   GATE_SCRIPT        the mechanical gate run-batch.sh runs after the build pass
#   GATE_SCRIPT_LABEL  that same path relative to REPO_DIR, for executor prompts
#   GATE_REPORT_LABEL  where that gate leaves its report, relative to REPO_DIR
#   PR_SCRIPT          the repo-owned PR hook run-review.sh runs after a clean pass
#   REVIEW_REPORT      absolute path the review executor writes its findings to, and
#                      the PR hook reads as the PR body
#   REVIEW_REPORT_LABEL that same path relative to REPO_DIR, for the executor prompt
# Exit code run-plans.sh uses for "paused at a level boundary — a level-verify plan is
# queued" (RUNNER.md → "Level sentinels"). Reserved: finalize_plan and run_level_gate clamp
# a child process that happens to exit with this code, so a failed plan or gate can never
# be mistaken for a pause by run-batch.sh. 64 is EX_USAGE in sysexits.h, which neither
# claude nor a gate script returns in practice; 1-3 and 127/130 are already spoken for.
LEVEL_PAUSE_RC=64

# ── The verdict ───────────────────────────────────────────────────────────────
# The review report's FIRST LINE, and the three values it can mean
# (self/DESIGN-2026-09-17-close-and-review-rounds.md §3). They live here, beside the one
# reader, rather than in run-review.sh: the runner writes the prompt that asks for the
# line, and run-review.sh, run-batch.sh and feature-close.sh all read it back — three
# copies of the spelling would be three chances for a clean review to read as escalated.
VERDICT_PREFIX="Verdict:"
VERDICT_CLEAN="clean"
VERDICT_ESCALATED="escalated"
# A missing or unrecognised line. Treated exactly like escalated everywhere — fail
# closed: a report nobody can read is not a report saying the batch is fine.
VERDICT_UNREADABLE="unreadable"

# report_verdict <report-path> — clean | escalated | unreadable, on stdout, always 0.
# The report's first line only: the executor writes the verdict as its opening line and
# everything below it is prose a `grep` would find the word in.
report_verdict() {
  local report="${1:-}" first prefix value
  if [[ ! -f "$report" ]]; then echo "$VERDICT_UNREADABLE"; return 0; fi
  # The line is folded BEFORE the prefix is matched, not after: a report opening
  # `  VERDICT:  CLEAN ` — a CRLF file, an executor writing the label the way the prompt
  # shouts it — is the clean verdict it plainly is, and only a first line that says
  # something else is unreadable. The case is folded and the space trimmed by hand:
  # bash 3.2 has no ${v,,}, and ${v#${v%%[![:space:]]*}} is its leading-space trim.
  first="$(sed -n '1p' "$report" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
  first="${first#"${first%%[![:space:]]*}"}"
  prefix="$(printf '%s' "$VERDICT_PREFIX" | tr '[:upper:]' '[:lower:]')"
  case "$first" in
    "$prefix"*)
      value="${first#"$prefix"}"
      value="$(printf '%s' "$value" | tr -d '[:space:]')"
      ;;
    *) value="" ;;
  esac
  case "$value" in
    "$VERDICT_CLEAN")     echo "$VERDICT_CLEAN" ;;
    "$VERDICT_ESCALATED") echo "$VERDICT_ESCALATED" ;;
    *)                    echo "$VERDICT_UNREADABLE" ;;
  esac
}

# Where a review's escalated report is copied to, relative to the feature directory: the
# same directory the tier ladder writes NN.md into (RUNNER.md → "Red gates").
ESCALATIONS_DIR_NAME="escalations"

# ── Rounds ────────────────────────────────────────────────────────────────────
# A feature is a sequence of rounds — build → gate → verify → review — and the round is
# the number of review plans already FILED COMPLETE plus one (design §4). Held in
# TIMING_ROUND for the length of a runner pass, so every stamp of one pass carries the
# same number even though the review plan moves into complete/ halfway through it; left
# unset by stamp-timing.sh, which computes it fresh at each by-hand stamp; and taken by
# feature-close.sh from the closing review's own `plan_end` stamp, whose round is the one
# that judged the tree — the count is that script's fallback and not its answer, since a
# review capped after writing its report is filed to failed/ and counts toward no round.

# completed_review_count <slug> — review plans in review/complete/, progress logs and
# sidecars excluded.
completed_review_count() {
  local slug="${1:-}" dir f count=0
  dir="$FEATURES_DIR/$slug/review/complete"
  [[ -n "$slug" && -d "$dir" ]] || { echo 0; return 0; }
  for f in "$dir"/[0-9]*.md; do
    [[ -e "$f" && "$f" != *.progress.md ]] || continue
    count=$((count + 1))
  done
  echo "$count"
}

# next_round <slug> — the round the work happening now belongs to.
next_round() { echo "$(( $(completed_review_count "${1:-}") + 1 ))"; }

# latest_review_plan <slug> — the stem of the highest-numbered review plan this feature
# has FINISHED with, or nothing when none has. That plan's `plan_end` stamp is where the
# latest round's verdict is recorded.
#
# complete/ and failed/ both, because a review whose budget cap fired AFTER it wrote its
# report is filed to failed/ and its verdict is complete all the same (design §3) — while
# a review that failed for any other reason stamped no verdict, so the close refuses on
# the verdict and not on the state directory. Only complete/ counts toward the ROUND: a
# round advances when a review finishes judging, not when one is re-scoped.
#
# Highest by the stem's leading NUMBER, not by the string. A feature numbers its own plans
# from 01, and AGENT_PLANS.md → "If one feature's own numbering ever passes 99" tells the
# author who crosses it to re-pad that feature's filenames — so between the round that
# crosses that boundary and the re-padding, one feature holds stems of two widths, where
# "98-review-opus" sorts above
# "101-review-sonnet" lexically and would hand the close the earlier round's verdict. The
# numeric compare is what keeps such a feature ordered right until the widths agree again.
# `10#` because bash reads a leading zero as octal, and `08` would otherwise abort the
# caller. Equal numbers fall back to the string, which is the only case the two orders
# agree on anyway. Asserted directly in self/tests/verdict-readers.sh.
latest_review_plan() {
  local slug="${1:-}" dir f stem number latest="" latest_number=0
  [[ -n "$slug" ]] || return 0
  for dir in "$FEATURES_DIR/$slug/review/complete" "$FEATURES_DIR/$slug/review/failed"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/[0-9]*.md; do
      [[ -e "$f" && "$f" != *.progress.md ]] || continue
      stem="$(basename "${f%.md}")"
      number="${stem%%[!0-9]*}"
      number=$((10#${number:-0}))
      if (( number > latest_number )) ||
         { (( number == latest_number )) && [[ -z "$latest" || "$stem" > "$latest" ]]; }; then
        latest="$stem"
        latest_number="$number"
      fi
    done
  done
  echo "$latest"
}

# review_plan_end <slug> <plan-stem> <key> — one detail of the LAST `plan_end` stamp for
# that plan in timing.jsonl: `verdict`, `head` or `round`. Nothing when there is no such
# stamp or the key is absent, so a caller can test with [[ -n … ]]. One reader for
# run-review.sh's own stamp, run-batch.sh's branch and the close's refusals.
review_plan_end() {
  local slug="${1:-}" plan="${2:-}" key="${3:-}" path
  path="$FEATURES_DIR/$slug/timing.jsonl"
  [[ -f "$path" ]] || return 0
  jq -r --arg plan "$plan" --arg key "$key" \
    'select(.event == "plan_end" and .plan == $plan) | .[$key] // empty' "$path" 2>/dev/null \
    | tail -1
}

resolve_roots() {
  local first_arg="${1:-}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "$first_arg" == "--self" ]]; then
    SELF_MODE=1
    REPO_DIR="$script_dir"
    FEATURES_DIR="$script_dir/self/features"
    FEATURES_LABEL="self/features"
    SELF_ARG="--self "
    GATE_SCRIPT="$script_dir/self/gate.sh"
    GATE_SCRIPT_LABEL="self/gate.sh"
    GATE_REPORT_LABEL="self/gate-report.txt"
    PR_SCRIPT="$script_dir/self/pr.sh"
    REVIEW_REPORT="$script_dir/self/review-report.md"
    REVIEW_REPORT_LABEL="self/review-report.md"
  else
    SELF_MODE=0
    REPO_DIR="$(cd "$script_dir/.." && pwd)"
    FEATURES_DIR="$REPO_DIR/plans/features"
    FEATURES_LABEL="plans/features"
    SELF_ARG=""
    GATE_SCRIPT="$REPO_DIR/plans/gate.sh"
    GATE_SCRIPT_LABEL="plans/gate.sh"
    GATE_REPORT_LABEL="plans/gate-report.txt"
    PR_SCRIPT="$REPO_DIR/plans/pr.sh"
    REVIEW_REPORT="$REPO_DIR/plans/review-report.md"
    REVIEW_REPORT_LABEL="plans/review-report.md"
  fi
}

# ── The harness's own records ─────────────────────────────────────────────────
# Which dirty paths in a feature's checkout are records the harness wrote, and which are
# somebody's work in progress. ONE reader, here rather than in either script that calls it:
# feature-capture.sh refuses its cost commit on this and feature-close.sh refuses the PR on
# it, and a close looser than the capture is a half-written file passing the check that runs
# BEFORE the PR only to be refused by the one that runs after it — the one moment the
# refusal exists to come before.

# The harness's own records, relative to the feature directory: everything the capture, the
# report, the window stamp, the runners' timing and the start's routing record write there,
# and what the cost commit may carry. Anything else dirty is somebody's work in progress.
# `routing.json` joined them when the routing record moved inside the feature it links
# (self/DESIGN-2026-09-18-ledger-and-routing.md §1): it is a cost record of this feature
# like the rest, written by feature-start.sh and rewritten by the capture's refresh.
COST_FILES="README.md planning.json report.md report.json routing.json timing.jsonl"
# The per-plan cost sidecars, which are not flat names: <queue>/<state>/<stem>.usage.json
# under the feature directory, one level deeper again for an archived batch. These are the
# runner's own two sets — QUEUE is exactly one of the three (run-plans.sh, run-verify.sh,
# run-review.sh) and the four states are what finalize_plan routes a plan between — and
# analysis/report.py holds the same two as QUEUE_DIRS and STATE_DIRS. Matching the names
# rather than any *.usage.json is what makes the stray refusal mean something: a
# .usage.json anywhere else under the feature directory was never the harness's.
COST_USAGE_QUEUES="auto verify review"
COST_USAGE_STATES="incomplete inprogress complete failed"
USAGE_SIDECAR_SUFFIX=".usage.json"
# What feature-capture.sh's annotation step may rewrite under ANOTHER feature's directory
# in this corpus: the frozen record whose `sessions[].also_claimed_by` the claims ledger
# changed, and the two reports rendered from it. Those three files and no others — and only
# for the slugs the annotation actually returned, which is stray_paths' second argument.
ANNOTATION_FILES="planning.json report.md report.json"
# The admitted-siblings argument for every caller that has annotated nothing: the capture
# before its annotation step, and the close, which never annotates at all. Named so the two
# call sites read as the same decision rather than as two empty strings.
NO_SIBLINGS=""

# stray_labels <slug> <checkout> — the three path labels stray_paths reads, as globals.
#
# Globals rather than three more arguments, and one function rather than a copy in each
# caller: they are `git status` prefixes, all derived from the same three facts — this
# copy's REPO_DIR, the checkout it lives in, and the slug — and two callers deriving them
# apart is the drift this shared reader exists to end. Both callers call this once, before
# any stray_paths call. The names are the ones feature-capture.sh already used:
#
#   FEATURE_REL   <repo>/<features>/<slug>    this feature's own directory
#   FEATURES_REL  <repo>/<features>           the corpus above it
#   STRAY_SLUG    the slug, which tells this feature's directory from a sibling's
#
# There was a fourth, ROUTING_REL, for `<repo>/<...>/routing` — gone with the directory it
# named, now that a routing record is a `COST_FILES` entry inside the feature it links
# (self/DESIGN-2026-09-18-ledger-and-routing.md §1).
#
# <repo> is "" in a standalone checkout and `agentTooling/` where this directory is
# vendored, which is what a status line carries in front of every path.
stray_labels() {
  local slug="$1" checkout="$2" rel
  rel="${REPO_DIR#"$checkout"}"; rel="${rel#/}"
  STRAY_SLUG="$slug"
  FEATURE_REL="${rel:+$rel/}$FEATURES_LABEL/$slug"
  FEATURES_REL="${rel:+$rel/}$FEATURES_LABEL"
}

# is_cost_usage_path <feature-relative path> — one of the per-plan sidecars above:
# <queue>/<state>/… ending in .usage.json. What follows the state directory is left
# unconstrained, so an archived batch's extra level still matches.
is_cost_usage_path() {
  local name="$1" queue rest state
  case "$name" in *"$USAGE_SIDECAR_SUFFIX") ;; *) return 1 ;; esac
  case "$name" in */*/*) ;; *) return 1 ;; esac      # needs a queue AND a state above it
  queue="${name%%/*}"
  rest="${name#*/}"
  state="${rest%%/*}"
  case " $COST_USAGE_QUEUES " in *" $queue "*) ;; *) return 1 ;; esac
  case " $COST_USAGE_STATES " in *" $state "*) ;; *) return 1 ;; esac
  return 0
}

# Returned by stray_paths (below) when it could not judge the tree at all — one of the
# labels stray_labels sets was empty, so the loop never ran. A programming error,
# never a dirty tree: the caller either never called stray_labels for this checkout, or
# called it for a different slug or checkout and read the reader before calling it again.
STRAY_UNJUDGED_RC=2

# stray_paths <`git status --porcelain --untracked-files=all` output> <admitted slugs>
#
# stdout is the list of dirty paths that are NOT records the caller may commit, one per
# line; empty means every dirty path is one the harness writes: a COST_FILES name (the
# routing record among them) or a sidecar under THIS feature's directory, or one of the
# three ANNOTATION_FILES under the directory of a sibling named in <admitted slugs>
# (space-separated; empty admits none).
#
# The RETURN CODE says whether that stdout may be trusted, and every caller must check
# it: 0 means the loop below ran and stdout is the complete list; STRAY_UNJUDGED_RC means
# it did not run — FEATURE_REL, FEATURES_REL or STRAY_SLUG was not set, so
# stray_labels was never called (or was called and something after it unset one of its
# globals). A caller that reads stdout without checking the code has the fail-open bug
# back: under `set -uo pipefail`, an unset label used to let `set -u` kill only the
# command substitution's subshell that wraps this call, so `STRAY="$(stray_paths …)"`
# came back empty and read as "nothing is stray" — the close opened a PR over a dirty
# tree and the capture pushed it. Every caller here is
# `if ! STRAY="$(stray_paths …)"; then refuse …; fi`, which refuses on this explicit
# check AND on any other way the subshell can die, not only on these names going
# missing.
#
# That last arm is feature-capture.sh's annotation step, and it is the whole reason the
# admitted list is an argument rather than a rule. A record another feature froze is a cost
# record under that feature's directory, so refusing it outright would refuse every capture
# that found a shared session — while admitting it unconditionally admits a sibling's record
# somebody re-rendered by hand an hour earlier, which this run neither wrote nor commits and
# would push the branch still dirty. So: nothing before the annotation, exactly the slugs
# `capture_planning.py --annotate-frozen` returned after it, and nothing for the close,
# which annotates nothing.
stray_paths() {
  local admitted=" ${2:-} " line path rel name other
  local missing=""
  [[ -n "${FEATURE_REL:-}" ]]  || missing="FEATURE_REL"
  [[ -n "${FEATURES_REL:-}" ]] || missing="${missing:+$missing, }FEATURES_REL"
  [[ -n "${STRAY_SLUG:-}" ]]   || missing="${missing:+$missing, }STRAY_SLUG"
  if [[ -n "$missing" ]]; then
    echo "stray_paths: $missing not set — call stray_labels <slug> <checkout> first" >&2
    return "$STRAY_UNJUDGED_RC"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"                       # `XY <path>`; nothing here is ever a rename
    case "$path" in
      "$FEATURE_REL"/*)
        name="${path#"$FEATURE_REL"/}"
        case " $COST_FILES " in *" $name "*) continue ;; esac
        if is_cost_usage_path "$name"; then continue; fi
        ;;
      "$FEATURES_REL"/*/*)
        rel="${path#"$FEATURES_REL"/}"     # <other-slug>/<rest>
        other="${rel%%/*}"
        name="${rel#*/}"
        if [[ "$other" != "$STRAY_SLUG" ]] && [[ "$admitted" == *" $other "* ]]; then
          case " $ANNOTATION_FILES " in *" $name "*) continue ;; esac
        fi
        ;;
    esac
    echo "$path"
  done <<<"$1"
}

# level_expectations <sentinel-path>
#
# A sentinel (NN-gate.md) may say what its level does NOT own, so the gate's verdict is
# about this level and not about tests that are red by design until a level above builds
# them (the first tiered pilot spent a tier-1 and a tier-2 pass on a level that was green
# everywhere it owned). Two directives, each on its own line, each optional:
#
#   expected-red: <glob> [<glob>...]   test paths the gate's test run ignores at this level
#   defer: <label>, <label>, ...       gate sections recorded as deferred, not run
#
# Exported for the repo's gate.sh as GATE_EXPECTED_RED (space-separated) and GATE_DEFERRED
# (comma-separated); both empty for the final gate, which owns everything. A gate.sh that
# predates these ignores them and behaves as before.
level_expectations() {
  local sentinel="${1:-}"
  GATE_EXPECTED_RED=""
  GATE_DEFERRED=""
  [[ -f "$sentinel" ]] || { export GATE_EXPECTED_RED GATE_DEFERRED; return 0; }
  GATE_EXPECTED_RED="$(sed -n 's/^expected-red:[[:space:]]*//p' "$sentinel" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  GATE_DEFERRED="$(sed -n 's/^defer:[[:space:]]*//p' "$sentinel" | tr '\n' ',' | sed 's/,[[:space:]]*$//')"
  export GATE_EXPECTED_RED GATE_DEFERRED
}

# manifest_field <readme> <key> — one field from the LAST ```json fence of a feature
# manifest, the fence analysis/capture_planning.py reads. A string prints bare, anything
# else as JSON; absent or null prints nothing, so a caller can test with [[ -n ... ]].
# Through jq so a manifest's markdown is parsed in exactly one place on the shell side.
#   base="$(manifest_field "$FEATURES_DIR/$FEATURE_SLUG/README.md" base)"
manifest_field() {
  local readme="$1" key="$2"
  [[ -f "$readme" ]] || return 0
  awk '/^```json[[:space:]]*$/{buf=""; f=1; next} /^```[[:space:]]*$/{if(f){last=buf}; f=0; next} f{buf=buf $0 "\n"} END{printf "%s", last}' "$readme" \
    | jq -r --arg k "$key" '.[$k] // empty | if type == "string" then . else tojson end' 2>/dev/null
}

# Append one wall-clock event to the feature's timing.jsonl. A plan's own duration is in
# its usage.json, but everything between plans is invisible from inside an executor:
# the gates, the parallelism a batch got, the stretch from first plan to PR. This is
# the record of that — one JSON line per event, UTC to the second, built by jq so a
# value with a quote in it cannot break the file. analysis/report.py reads it into the
# report's "Time" section; a feature without one simply has no wall-clock figures.
# Small and committed, like the usage sidecars. Silent when no feature is resolved yet.
#
# Every line also carries its `round` (above): TIMING_ROUND when a caller has fixed one
# for the pass, else computed fresh from review/complete/. A line written before this
# existed carries none and is read as round 1. Like every other detail it is a STRING,
# which is what analysis/report.py's readers expect of a timing detail.
#   stamp_timing <event> [key=value ...]     e.g. stamp_timing gate_end level=05 rc=0
stamp_timing() {
  local event="$1"; shift
  [[ -n "${FEATURE_SLUG:-}" && -d "$FEATURES_DIR/$FEATURE_SLUG" ]] || return 0
  local path="$FEATURES_DIR/$FEATURE_SLUG/timing.jsonl"
  local round="${TIMING_ROUND:-}"
  if [[ -z "$round" ]]; then round="$(next_round "$FEATURE_SLUG")"; fi
  local args=(--arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg event "$event")
  local expr='{at: $at, event: $event}'
  local kv key
  for kv in "$@"; do
    key="${kv%%=*}"
    args+=(--arg "$key" "${kv#*=}")
    expr+=" + {$key: \$$key}"
  done
  # LAST, after the caller's details: the key order of a line is what several tests read
  # it back by (`"event":"pass_start","queue":"auto"`), and a round inserted between the
  # event and its details would break every one of them for no gain. It is also why this
  # one wins over a `round=` a caller passed as a detail — jq takes the later key — so the
  # way to fix a round is TIMING_ROUND, which is what the close and the runners use.
  args+=(--arg round "$round")
  expr+=' + {round: $round}'
  jq -cn "${args[@]}" "$expr" >> "$path" 2>/dev/null || true
}
