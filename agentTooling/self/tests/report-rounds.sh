#!/usr/bin/env bash
set -uo pipefail

# Self-test for the Rounds table in the cost report
# (self/DESIGN-2026-09-17-close-and-review-rounds.md §4, and §9's RD and the
# no-`round` fallback). Run by self/gate.sh, or by hand:
# bash self/tests/report-rounds.sh
#
# Same scaffolding as report-footnotes.sh — copies of `analysis/pricing.py`,
# `roots.py`, `transcript.py`, `routing.py` and `report.py` into a throwaway
# agentTooling checkout under mktemp -d, plus a synthesized `self/features/` corpus of
# hand-written manifests, `planning.json` files, plan `.md` files, `usage.json` sidecars
# and — the input this file is about — a hand-written `timing.jsonl`. No transcripts, no
# model, no network: every dollar and every minute is a literal in a sidecar, which is
# what report.py's no-recompute contract says it reads.
#
# The defect (design §1): a feature is a sequence of rounds — build → gate → verify →
# review, ending in the review's verdict — and nothing in the record could tell one
# round from the next. The rework after an escalated review was money in the same
# buckets as the work it was reworking, with no verdict beside either, so "how many
# reviews did this feature need, and what did each round cost" was a question the
# committed record could not answer.
#
# The contract this file asserts, which `plan-runner-roots.sh`'s `stamp_timing` and
# `run-review.sh` write (slice A of this feature):
#   - every event a runner pass stamps carries `round`, e.g. `"round":"2"` — a STRING,
#     like every other detail value in timing.jsonl;
#   - a line with NO `round` key is round 1: every timing.jsonl written before this
#     feature existed;
#   - the review plan's `plan_end` carries `verdict` (`clean`/`escalated`/`unreadable`)
#     and `head`;
#   - an escalated review's brief is `<features>/<slug>/escalations/<review-stem>.md`,
#     which the report LINKS and never parses.
#
# Asserts, in order:
#   1. two rounds, escalated then clean: `rounds[]` carries one row per round, ascending,
#      with each round's build/verify/review dollars and minutes partitioned by the round
#      its plans' stamps carry, the review plan's stem, its verdict, and
#      `escalations_file` set on the escalated round only — and the rows' dollars sum to
#      the Cost table's own build+verify+review, so the two tables cannot drift;
#   2. report.md renders the same rows as a **Rounds** table;
#   3. a legacy timing.jsonl with no `round` key anywhere renders as exactly one round,
#      round 1, with no mark;
#   4. `--rounds-md` prints ONLY the Rounds table, exit 0, and rewrites neither
#      report.json nor report.md — it is what `feature-close.sh` calls to compose the PR
#      body, before the capture that writes the report has run;
#   5. ...including for a feature with no `planning.json` at all, which is every feature
#      at the moment its first PR is opened: exit 0, the table prints, and the build
#      figure nobody has frozen yet is marked rather than printed as a bare zero;
#   6. a review plan whose `plan_end` carries no `verdict` key at all has a null verdict
#      and a null `escalations_file`, and still names its plan.
#   7. `report.py <slug>` (no `--rounds-md`) on a feature with no `planning.json` at all
#      (`lifecycle-records-and-numbering`, slice B1) exits non-zero, names `planning.json`
#      and `feature-close.sh` on stderr, prints no traceback, and writes no report.json —
#      the plain single-feature mode refuses exactly the input phase 5's `--rounds-md`
#      is required to tolerate.
#
# RED until `rounds[]`, the Rounds table and `--rounds-md` land: phase 1 finds no
# `rounds` key, phase 2 no `## Rounds` heading, phase 4 an argparse usage error. Phase 7
# is RED until `run_single_feature` checks for `planning.json` before reading it: a bare
# `FileNotFoundError` traceback fails 7a (a non-zero exit for the wrong reason still
# passes it, so 7d — no `Traceback` on stderr — is the assertion that actually catches
# it) and 7b/7c together, since Python's own traceback never says `feature-close.sh`. A
# missing analysis script is tolerated rather than fatal, the cost-recovery.sh
# convention.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/report-rounds.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py rates_history.json roots.py transcript.py report.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "report-rounds"

# One dollar figure and one duration per plan, each a distinct power of two, so no
# assertion below can pass by reading the wrong fixture and no sum can be reached two
# ways. The milliseconds are whole minutes, so the minutes columns are exact.
BUILD_COST="1.0";   BUILD_MS="60000"     # 1 minute
VERIFY_COST="2.0";  VERIFY_MS="120000"   # 2 minutes
REVIEW_COST="4.0";  REVIEW_MS="240000"   # 4 minutes
REWORK_COST="8.0";  REWORK_MS="480000"   # 8 minutes
REREVIEW_COST="16.0"; REREVIEW_MS="960000"  # 16 minutes

# The Rounds table's own text, asserted by value so a change to either is a visible
# change to this test — the close composes its PR body out of exactly these lines.
ROUNDS_HEADING="## Rounds"
ROUNDS_HEADER="| round | build usd | build min | verify usd | verify min | review usd | review min | review plan | verdict | escalation brief |"
# The mark a bucket with no partitionable figure carries. The Cost and Time tables'
# `†` — one marking, reused, not a second one invented here.
MARK="†"
# What an absent text value renders as, distinct from `n/a` (a figure nobody recorded).
ABSENT="—"

# ── Fixture helpers ───────────────────────────────────────────────────────────

# feature_dir <slug> <plans-json> [method] — the throwaway feature, with the manifest
# and planning.json report.py needs before it reads anything else. planning.json's total
# and durations are 0 so every dollar and every minute below comes from a usage.json.
feature_dir() {
  local slug="$1" plans="$2" method="${3:-plans}" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MDEOF
# $slug

Test fixture only, for self/tests/report-rounds.sh.

\`\`\`json
{"slug": "$slug", "method": "$method", "plans": $plans, "branches": ["$slug"]}
\`\`\`
MDEOF
  cat > "$dir/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false},
 "duration_s": {"sessions": 0.0, "subagents": 0.0}}
JSONEOF
  echo "$dir"
}

# plan_sidecar <feature dir> <queue> <stem> <cost> <duration_ms> — the four files the
# runner files for a completed plan, of which the report reads the `.md` and the
# `usage.json`.
plan_sidecar() {
  local dir="$1" queue="$2" stem="$3" cost="$4" ms="$5"
  mkdir -p "$dir/$queue/complete"
  cat > "$dir/$queue/complete/$stem.md" <<MDEOF
# $stem

Test fixture plan for report-rounds.sh. Not a real plan.
MDEOF
  echo "$queue pass complete" > "$dir/$queue/complete/$stem.progress.md"
  cat > "$dir/$queue/complete/$stem.usage.json" <<JSONEOF
{
  "plan": "$stem",
  "model": "sonnet",
  "outcome": "complete",
  "session_id": "sess-$stem",
  "result_event": "seen",
  "subtype": null,
  "is_error": null,
  "num_turns": 4,
  "duration_ms": $ms,
  "total_cost_usd": $cost,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [
    {"session_id": "sess-$stem", "outcome": "complete", "total_cost_usd": $cost, "num_turns": 4, "duration_ms": $ms}
  ]
}
JSONEOF
}

# escalation_brief <feature dir> <review stem> — what run-review.sh copies the report to
# when the verdict is escalated. Its contents are the model's; the report links it.
escalation_brief() {
  mkdir -p "$1/escalations"
  cat > "$1/escalations/$2.md" <<'MDEOF'
Verdict: escalated

## Escalated

- A structural finding the executor may not fix.
MDEOF
}

# ── Python verification helper ────────────────────────────────────────────────
# JSON parsing belongs in Python, not bash.
cat > "$TMP/verify.py" <<'PYEOF'
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def get_path(data, dotted):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def cmd_field_equals(args):
    report_path, dotted, expected_json = args
    print(get_path(load(report_path), dotted) == json.loads(expected_json))


def cmd_rounds_sum_matches_cost(args):
    """The Rounds rows' dollars against the Cost table's own executor buckets. The two
    are computed from the same sidecars, so a difference is a drift between them."""
    data = load(args[0])
    rounds = data.get("rounds") or []
    cost = data.get("cost") or {}
    rows = sum(
        (r.get("build_usd") or 0.0) + (r.get("verify_usd") or 0.0) + (r.get("review_usd") or 0.0)
        for r in rounds
    )
    buckets = (cost.get("build") or 0.0) + (cost.get("verify") or 0.0) + (cost.get("review") or 0.0)
    print(abs(rows - buckets) < 0.0001)


COMMANDS = {
    "field_equals": cmd_field_equals,
    "rounds_sum_matches_cost": cmd_rounds_sum_matches_cost,
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
PYEOF

V() { python3 "$TMP/verify.py" "$@" 2>/dev/null; }
report_for() { python3 "$AT/analysis/report.py" --self "$1" >/dev/null 2>&1; }
rounds_md_for() { python3 "$AT/analysis/report.py" --self "$1" --rounds-md 2>/dev/null; }
# stderr alone, for the refusal phase below: 2>&1 first (send stderr where stdout — the
# command substitution's pipe — currently goes), then >/dev/null (move stdout itself
# aside), so only what the process wrote to stderr is captured.
report_stderr_for() { python3 "$AT/analysis/report.py" --self "$1" 2>&1 >/dev/null; }

# ── 1 + 2: two rounds, escalated then clean ───────────────────────────────────
# Design §9 RD, the report half: the second review's stamps carry `round=2`, and
# `report.json` has two `rounds[]` rows with verdicts `escalated` then `clean` and the
# first row's `escalations_file` set.
D1="$(feature_dir rr-two-rounds '["01-build-sonnet", "02-verify-sonnet", "03-review-opus", "04-rework-sonnet", "05-review-sonnet"]')"
plan_sidecar "$D1" auto   01-build-sonnet   "$BUILD_COST"    "$BUILD_MS"
plan_sidecar "$D1" verify 02-verify-sonnet  "$VERIFY_COST"   "$VERIFY_MS"
plan_sidecar "$D1" review 03-review-opus    "$REVIEW_COST"   "$REVIEW_MS"
plan_sidecar "$D1" auto   04-rework-sonnet  "$REWORK_COST"   "$REWORK_MS"
plan_sidecar "$D1" review 05-review-sonnet  "$REREVIEW_COST" "$REREVIEW_MS"
escalation_brief "$D1" 03-review-opus
cat > "$D1/timing.jsonl" <<'JSONLEOF'
{"at":"2026-09-17T16:00:00Z","event":"batch_start"}
{"at":"2026-09-17T16:00:10Z","event":"pass_start","queue":"auto","round":"1"}
{"at":"2026-09-17T16:00:11Z","event":"plan_start","plan":"01-build-sonnet","queue":"auto","round":"1"}
{"at":"2026-09-17T16:01:11Z","event":"plan_end","plan":"01-build-sonnet","queue":"auto","rc":"0","round":"1"}
{"at":"2026-09-17T16:01:12Z","event":"pass_end","queue":"auto","reason":"drained","round":"1"}
{"at":"2026-09-17T16:01:20Z","event":"pass_start","queue":"verify","round":"1"}
{"at":"2026-09-17T16:01:21Z","event":"plan_start","plan":"02-verify-sonnet","queue":"verify","round":"1"}
{"at":"2026-09-17T16:03:21Z","event":"plan_end","plan":"02-verify-sonnet","queue":"verify","rc":"0","round":"1"}
{"at":"2026-09-17T16:03:22Z","event":"pass_end","queue":"verify","reason":"drained","round":"1"}
{"at":"2026-09-17T16:03:30Z","event":"pass_start","queue":"review","round":"1"}
{"at":"2026-09-17T16:03:31Z","event":"plan_start","plan":"03-review-opus","queue":"review","round":"1"}
{"at":"2026-09-17T16:07:31Z","event":"plan_end","plan":"03-review-opus","queue":"review","rc":"0","verdict":"escalated","head":"abc1234","round":"1"}
{"at":"2026-09-17T16:07:32Z","event":"pass_end","queue":"review","reason":"drained","round":"1"}
{"at":"2026-09-17T17:00:00Z","event":"pass_start","queue":"auto","round":"2"}
{"at":"2026-09-17T17:00:01Z","event":"plan_start","plan":"04-rework-sonnet","queue":"auto","round":"2"}
{"at":"2026-09-17T17:08:01Z","event":"plan_end","plan":"04-rework-sonnet","queue":"auto","rc":"0","round":"2"}
{"at":"2026-09-17T17:08:02Z","event":"pass_end","queue":"auto","reason":"drained","round":"2"}
{"at":"2026-09-17T17:10:00Z","event":"pass_start","queue":"review","round":"2"}
{"at":"2026-09-17T17:10:01Z","event":"plan_start","plan":"05-review-sonnet","queue":"review","round":"2"}
{"at":"2026-09-17T17:26:01Z","event":"plan_end","plan":"05-review-sonnet","queue":"review","rc":"0","verdict":"clean","head":"def5678","round":"2"}
{"at":"2026-09-17T17:26:02Z","event":"pass_end","queue":"review","reason":"drained","round":"2"}
JSONLEOF
report_for rr-two-rounds
rc1=$?
R1="$D1/report.json"
M1="$D1/report.md"
check "1a. a two-round feature reports cleanly (report.py exit $rc1)" '(( rc1 == 0 ))'
EXPECTED_ROUNDS='[
  {"round": 1,
   "build_usd": 1.0, "build_min": 1.0,
   "verify_usd": 2.0, "verify_min": 2.0,
   "review_usd": 4.0, "review_min": 4.0,
   "review_plan": "03-review-opus", "verdict": "escalated",
   "escalations_file": "escalations/03-review-opus.md"},
  {"round": 2,
   "build_usd": 8.0, "build_min": 8.0,
   "verify_usd": 0.0, "verify_min": 0.0,
   "review_usd": 16.0, "review_min": 16.0,
   "review_plan": "05-review-sonnet", "verdict": "clean",
   "escalations_file": null}
]'
r1b="$(V field_equals "$R1" rounds "$EXPECTED_ROUNDS")"
check "1b. rounds[] carries both rows, partitioned by the stamps' round (got $r1b)" '[[ "$r1b" == "True" ]]'
r1c="$(V rounds_sum_matches_cost "$R1")"
check "1c. the rows' dollars sum to the Cost table's own buckets (got $r1c)" '[[ "$r1c" == "True" ]]'
r1d="$(V field_equals "$R1" rounds_unpartitioned 'null')"
check "1d. nothing is unpartitioned — every figure has a round (got $r1d)" '[[ "$r1d" == "True" ]]'

check "2a. report.md carries the Rounds heading" 'grep -qF "$ROUNDS_HEADING" "$M1"'
check "2b. ...and the table header" 'grep -qF "$ROUNDS_HEADER" "$M1"'
check "2c. ...round 1's row, with its verdict and its brief" \
  'grep -qF "| 1 | \$1.0000 | 1.0 | \$2.0000 | 2.0 | \$4.0000 | 4.0 | 03-review-opus | escalated | escalations/03-review-opus.md |" "$M1"'
check "2d. ...and round 2's, clean, with no brief" \
  'grep -qF "| 2 | \$8.0000 | 8.0 | \$0.0000 | 0.0 | \$16.0000 | 16.0 | 05-review-sonnet | clean | $ABSENT |" "$M1"'
check "2e. ...and no mark, since every figure was partitionable" '! grep -qF "$MARK build" "$M1"'

# ── 3: a legacy timing.jsonl is one round ─────────────────────────────────────
# Every timing.jsonl committed before this feature existed carries no `round` key at
# all. Such a line is round 1 — not "unknown", not a row of its own — so a feature that
# ran once renders as exactly one round and nothing about its record needs rewriting.
D3="$(feature_dir rr-legacy '["01-build-sonnet", "02-review-opus"]')"
plan_sidecar "$D3" auto   01-build-sonnet "$BUILD_COST"  "$BUILD_MS"
plan_sidecar "$D3" review 02-review-opus  "$REVIEW_COST" "$REVIEW_MS"
cat > "$D3/timing.jsonl" <<'JSONLEOF'
{"at":"2026-09-16T10:00:00Z","event":"batch_start"}
{"at":"2026-09-16T10:00:10Z","event":"pass_start","queue":"auto"}
{"at":"2026-09-16T10:00:11Z","event":"plan_start","plan":"01-build-sonnet","queue":"auto"}
{"at":"2026-09-16T10:01:11Z","event":"plan_end","plan":"01-build-sonnet","queue":"auto","rc":"0"}
{"at":"2026-09-16T10:01:12Z","event":"pass_end","queue":"auto","reason":"drained"}
{"at":"2026-09-16T10:02:00Z","event":"pass_start","queue":"review"}
{"at":"2026-09-16T10:02:01Z","event":"plan_start","plan":"02-review-opus","queue":"review"}
{"at":"2026-09-16T10:06:01Z","event":"plan_end","plan":"02-review-opus","queue":"review","rc":"0"}
{"at":"2026-09-16T10:06:02Z","event":"pass_end","queue":"review","reason":"drained"}
{"at":"2026-09-16T10:07:00Z","event":"pr_opened","rc":"0","url":"https://example.invalid/pr/1"}
JSONLEOF
report_for rr-legacy
rc3=$?
R3="$D3/report.json"
M3="$D3/report.md"
check "3a. a legacy feature reports cleanly (report.py exit $rc3)" '(( rc3 == 0 ))'
r3b="$(V field_equals "$R3" rounds '[
  {"round": 1,
   "build_usd": 1.0, "build_min": 1.0,
   "verify_usd": 0.0, "verify_min": 0.0,
   "review_usd": 4.0, "review_min": 4.0,
   "review_plan": "02-review-opus", "verdict": null,
   "escalations_file": null}
]')"
check "3b. a timing.jsonl with no round key anywhere is exactly one round (got $r3b)" '[[ "$r3b" == "True" ]]'
check "3c. ...rendered as round 1, unmarked" \
  'grep -qF "| 1 | \$1.0000 | 1.0 | \$0.0000 | 0.0 | \$4.0000 | 4.0 | 02-review-opus | $ABSENT | $ABSENT |" "$M3"'

# ── 4: --rounds-md prints the table alone and writes nothing ───────────────────
# What feature-close.sh calls to compose the PR body (design §5.2): one renderer, so the
# PR body and report.md cannot disagree about what a round cost.
cp "$R1" "$TMP/rounds-before.json"
cp "$M1" "$TMP/rounds-before.md"
out4="$(rounds_md_for rr-two-rounds)"
rc4=$?
check "4a. --rounds-md exits 0 (got $rc4)" '(( rc4 == 0 ))'
check "4b. it prints the Rounds heading and header" \
  '[[ "$out4" == *"$ROUNDS_HEADING"* && "$out4" == *"$ROUNDS_HEADER"* ]]'
check "4c. ...both rows, as report.md renders them" \
  '[[ "$out4" == *"| 1 | \$1.0000 | 1.0 |"* && "$out4" == *"| 2 | \$8.0000 | 8.0 |"* ]]'
check "4d. ...the escalated round's brief and the clean round's verdict" \
  '[[ "$out4" == *"escalations/03-review-opus.md"* && "$out4" == *"clean"* ]]'
check "4e. ...and ONLY the Rounds table — no Cost, Time or Churn section" \
  '[[ "$out4" != *"## Cost"* && "$out4" != *"## Time"* && "$out4" != *"## Churn"* ]]'
check "4f. report.json is untouched" 'cmp -s "$TMP/rounds-before.json" "$R1"'
check "4g. report.md is untouched" 'cmp -s "$TMP/rounds-before.md" "$M1"'

# ── 5: --rounds-md before the first capture ───────────────────────────────────
# The close opens the PR and THEN captures, so at the moment the body is composed there
# is no planning.json and no report.json. The table must still print, and the build
# figure nobody has frozen yet must be marked rather than printed as a bare zero.
D5="$(feature_dir rr-uncaptured '["01-build-sonnet", "02-review-opus"]' direct)"
rm -f "$D5/planning.json"
plan_sidecar "$D5" review 02-review-opus "$REVIEW_COST" "$REVIEW_MS"
cat > "$D5/timing.jsonl" <<'JSONLEOF'
{"at":"2026-09-17T09:00:00Z","event":"pass_start","queue":"review","round":"1"}
{"at":"2026-09-17T09:00:01Z","event":"plan_start","plan":"02-review-opus","queue":"review","round":"1"}
{"at":"2026-09-17T09:04:01Z","event":"plan_end","plan":"02-review-opus","queue":"review","rc":"0","verdict":"clean","head":"0badcaf","round":"1"}
{"at":"2026-09-17T09:04:02Z","event":"pass_end","queue":"review","reason":"drained","round":"1"}
JSONLEOF
out5="$(rounds_md_for rr-uncaptured)"
rc5=$?
check "5a. --rounds-md on a feature with no planning.json exits 0 (got $rc5)" '(( rc5 == 0 ))'
check "5b. ...prints the header and round 1" \
  '[[ "$out5" == *"$ROUNDS_HEADER"* && "$out5" == *"| 1 |"* ]]'
check "5c. ...with the review verdict it was called for" '[[ "$out5" == *"clean"* ]]'
check "5d. ...and the unfrozen build figure marked, with a footnote" \
  '[[ "$out5" == *"$MARK"* ]]'
check "5e. ...having written no report.json" '[[ ! -f "$D5/report.json" ]]'

# ── 6: a review plan with no verdict ──────────────────────────────────────────
# A runner that stamped rounds but not verdicts, and a review killed before it wrote
# one: the round is real, the verdict is unknown, and `null` is the only honest value —
# never "clean", which is what the close reads to decide whether a feature may ship.
D6="$(feature_dir rr-no-verdict '["01-review-opus"]')"
plan_sidecar "$D6" review 01-review-opus "$REVIEW_COST" "$REVIEW_MS"
cat > "$D6/timing.jsonl" <<'JSONLEOF'
{"at":"2026-09-17T11:00:00Z","event":"pass_start","queue":"review","round":"1"}
{"at":"2026-09-17T11:00:01Z","event":"plan_start","plan":"01-review-opus","queue":"review","round":"1"}
{"at":"2026-09-17T11:04:01Z","event":"plan_end","plan":"01-review-opus","queue":"review","rc":"0","round":"1"}
{"at":"2026-09-17T11:04:02Z","event":"pass_end","queue":"review","reason":"drained","round":"1"}
JSONLEOF
report_for rr-no-verdict
rc6=$?
R6="$D6/report.json"
check "6a. a verdictless review reports cleanly (report.py exit $rc6)" '(( rc6 == 0 ))'
r6b="$(V field_equals "$R6" rounds '[
  {"round": 1,
   "build_usd": 0.0, "build_min": 0.0,
   "verify_usd": 0.0, "verify_min": 0.0,
   "review_usd": 4.0, "review_min": 4.0,
   "review_plan": "01-review-opus", "verdict": null,
   "escalations_file": null}
]')"
check "6b. a plan_end with no verdict key leaves verdict null and names the plan (got $r6b)" \
  '[[ "$r6b" == "True" ]]'
check "6c. ...and the row still renders" \
  'grep -qF "| 1 | \$0.0000 | 0.0 | \$0.0000 | 0.0 | \$4.0000 | 4.0 | 01-review-opus | $ABSENT | $ABSENT |" "$D6/report.md"'

# ── 7: the plain per-feature mode, before any capture (B1) ────────────────────
# --rounds-md (phase 5) is the one caller meant to run before the capture, and stays
# quiet about the missing planning.json — that is what the close's PR body needs. Every
# other way of running report.py on the same feature — `report.py <slug>`, with no
# `--rounds-md` — used to hit planning.json's bare `read_text()` and print a full
# traceback. It refuses instead: one line to stderr naming the missing path and the fix
# (`feature-close.sh` before the merge, `feature-capture.sh` after it), a non-zero exit,
# and no report.json written.
D7="$(feature_dir rr-uncaptured-plain '["01-review-opus"]' direct)"
rm -f "$D7/planning.json"
plan_sidecar "$D7" review 01-review-opus "$REVIEW_COST" "$REVIEW_MS"
err7="$(report_stderr_for rr-uncaptured-plain)"
rc7=$?
check "7a. report.py <slug> on an uncaptured feature exits non-zero (got $rc7)" '(( rc7 != 0 ))'
check "7b. ...naming planning.json in its stderr" '[[ "$err7" == *"planning.json"* ]]'
check "7c. ...and feature-close.sh, the fix" '[[ "$err7" == *"feature-close.sh"* ]]'
check "7d. ...with no traceback" '[[ "$err7" != *"Traceback"* ]]'
check "7e. ...and writes no report.json" '[[ ! -f "$D7/report.json" ]]'

echo
if (( fails > 0 )); then echo "report-rounds: $fails assertion(s) FAILED"; exit 1; fi
echo "report-rounds: all assertions passed"
