#!/usr/bin/env bash
set -uo pipefail

# Self-test for killed-attempt cost recovery and the intro-rate window
# (self/features/killed-attempt-cost-recovery/README.md). Run by self/gate.sh, or by
# hand: bash self/tests/cost-recovery.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — copies of `analysis/pricing.py`,
# `analysis/roots.py`, `analysis/report.py` and (once plans 02-03 land) `analysis/transcript.py`
# and `analysis/recover_attempts.py` — plus a synthesized `self/features/` corpus of `usage.json`
# sidecars and, under a redirected $HOME, the `~/.claude/projects/*/<session_id>.jsonl`
# transcripts they point at. No model, no network; runs in a few seconds.
#
# Everything here is RED until plans 02 (pricing.py's two-sided intro window) and 03
# (analysis/transcript.py, analysis/recover_attempts.py) land — that is intended; a plan-01
# run against `python3: can't open file … recover_attempts.py` is expected to FAIL every
# recovery assertion below, not to crash the script.
#
# Asserts, in order:
#   1. a transcript dated before the intro window starts prices at the standard tier;
#   2. the identical tokens dated inside the window price at the intro tier, at exactly 2/3
#      the cost of assertion 1;
#   3. a date after the window's expiry prices standard again (closed on both sides);
#   4. recover_attempts.py fills a killed attempt's recovered_cost_usd (matching
#      pricing.compute_cost on the transcript's own tokens), recovered_tokens (five-key
#      shape, per model), recovered_from: "transcript", and recovered_at/rates_applied
#      (both present);
#   5. it does not modify total_cost_usd — measured and recovered stay distinguishable;
#   6. a usage.json's top-level recovered_cost_usd equals the sum over its recovered
#      attempts;
#   7. the 5m/1h cache-creation split is honoured: identical total cache-creation tokens,
#      one all-5m and one all-1h, recover different costs in the ratio
#      CACHE_WRITE_1H_MULTIPLIER / CACHE_WRITE_5M_MULTIPLIER;
#   8. an attempt that already has a real total_cost_usd is left byte-identical;
#   9. running recovery twice is idempotent — the second run changes nothing;
#  10. a killed attempt whose transcript is absent is left untouched, reported as
#      unrecoverable on stdout, and the run still exits 0;
#  11. per-message.id dedup: three lines sharing one message.id bill once; the same
#      fixture with distinct message ids (dedup defeated) bills three times — and the two
#      must differ, so the assertion cannot pass vacuously;
#  12. model: "<synthetic>" lines contribute nothing to recovered cost;
#  13. a killed attempt on a model absent from pricing.RATES is marked
#      recovered_is_partial with unpriced_models naming it, and report.py classes the
#      plan's total as partial rather than recovered-and-whole; a mixed transcript (one
#      priceable model, one not) still recovers the priceable model's dollars while
#      staying partial;
#  14. attempt-level recovery survives the top-level recovered_cost_usd key being absent
#      (write_usage_sidecar erases it on a resumed plan) — report.py sums attempts[]
#      instead and does not mark the total partial on that account; when the top-level
#      figure is present but disagrees with the attempts[] sum, report.py warns naming
#      both figures rather than silently preferring one.
#
# Assertions 13-14 exercise report.py's reading of recovered_is_partial / unpriced_models
# and the attempts[]-vs-top-level cross-check. They were authored RED against
# self/features/recovered-totals-stay-honest's plan 02, which has since landed; they are
# green now and guard that behavior from here on, same contract as above.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
# transcript.py / recover_attempts.py are plan 02/03's deliverables; a missing cp here is
# expected pre-landing and must not abort the script (no `set -e`, and we don't check rc).
for f in transcript.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
source "$HERE/self/tests/fixtures/usage/build-usage.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

ANALYSIS_DIR="$AT/analysis"
MODEL="claude-sonnet-5"
TOL="1e-6"

# ── Python verification helper ────────────────────────────────────────────────
# JSON parsing and float comparisons belong in Python, not bash. Every dollar figure
# this prints is derived from pricing.compute_cost, never a hardcoded literal, and every
# "actual" figure is read straight out of the usage.json a real recovery run produced.
cat > "$TMP/verify.py" <<'PYEOF'
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def find_attempt(usage_path, session_id):
    data = load(usage_path)
    for attempt in data.get("attempts") or []:
        if attempt.get("session_id") == session_id:
            return attempt
    return None


def cmd_tier(args):
    analysis_dir, model, as_of = args
    sys.path.insert(0, analysis_dir)
    import pricing
    rates = pricing.get_rates(model, as_of)
    print(rates["tier"] if rates else "NONE")


def cmd_cost_ratio_check(args):
    analysis_dir, model, as_of_a, as_of_b, tokens_json, expected_ratio, tol = args
    sys.path.insert(0, analysis_dir)
    import pricing
    tokens = json.loads(tokens_json)
    cost_a, _ = pricing.compute_cost(model, tokens, as_of_a)
    cost_b, _ = pricing.compute_cost(model, tokens, as_of_b)
    if cost_a is None or cost_b is None:
        print(False)
        return
    expected = cost_a * float(expected_ratio)
    print(abs(cost_b - expected) <= float(tol) * max(1.0, abs(expected)))


def cmd_recovered_cost_matches(args):
    usage_path, session_id, analysis_dir, model, as_of, tokens_json, tol = args
    sys.path.insert(0, analysis_dir)
    import pricing
    tokens = json.loads(tokens_json)
    expected, _ = pricing.compute_cost(model, tokens, as_of)
    attempt = find_attempt(usage_path, session_id)
    actual = (attempt or {}).get("recovered_cost_usd")
    if actual is None or expected is None:
        print(False)
        return
    print(abs(actual - expected) <= float(tol) * max(1.0, abs(expected)))


def cmd_field_equals(args):
    usage_path, session_id, field, expected_json = args
    attempt = find_attempt(usage_path, session_id)
    expected = json.loads(expected_json)
    actual = attempt.get(field) if attempt is not None else None
    print(actual == expected)


def cmd_has_nonnull(args):
    usage_path, session_id = args[0], args[1]
    fields = args[2:]
    attempt = find_attempt(usage_path, session_id)
    if attempt is None:
        print(False)
        return
    print(all(attempt.get(f) is not None for f in fields))


def cmd_tokens_equal(args):
    usage_path, session_id, model, expected_tokens_json = args
    attempt = find_attempt(usage_path, session_id)
    expected = {model: json.loads(expected_tokens_json)}
    actual = (attempt or {}).get("recovered_tokens")
    print(actual == expected)


def cmd_top_equals_sum(args):
    (usage_path,) = args
    data = load(usage_path)
    attempts = data.get("attempts") or []
    recovered = [a["recovered_cost_usd"] for a in attempts if a.get("recovered_cost_usd") is not None]
    if not recovered:
        print(False)
        return
    attempts_sum = sum(recovered)
    top = data.get("recovered_cost_usd")
    if top is None:
        print(False)
        return
    print(abs(top - attempts_sum) <= 1e-9 * max(1.0, abs(top)))


def cmd_ratio_between(args):
    analysis_dir, usage_path_a, session_a, usage_path_b, session_b, tol = args
    sys.path.insert(0, analysis_dir)
    import pricing
    expected_ratio = pricing.CACHE_WRITE_1H_MULTIPLIER / pricing.CACHE_WRITE_5M_MULTIPLIER
    a = find_attempt(usage_path_a, session_a)
    b = find_attempt(usage_path_b, session_b)
    cost_a = (a or {}).get("recovered_cost_usd")
    cost_b = (b or {}).get("recovered_cost_usd")
    if not cost_a or cost_b is None:
        print(False)
        return
    ratio = cost_b / cost_a
    print(abs(ratio - expected_ratio) <= float(tol))


def cmd_not_equal(args):
    usage_path_a, session_a, usage_path_b, session_b = args
    a = find_attempt(usage_path_a, session_a)
    b = find_attempt(usage_path_b, session_b)
    ca = (a or {}).get("recovered_cost_usd")
    cb = (b or {}).get("recovered_cost_usd")
    print(ca is not None and cb is not None and ca != cb)


def get_path(data, dotted):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def cmd_report_field_equals(args):
    report_path, dotted, expected_json = args
    data = load(report_path)
    expected = json.loads(expected_json)
    actual = get_path(data, dotted)
    print(actual == expected)


def cmd_report_warning_contains(args):
    report_path = args[0]
    substrings = args[1:]
    data = load(report_path)
    warnings = data.get("warnings") or []
    print(any(all(s in w for s in substrings) for w in warnings))


COMMANDS = {
    "tier": cmd_tier,
    "cost_ratio_check": cmd_cost_ratio_check,
    "recovered_cost_matches": cmd_recovered_cost_matches,
    "field_equals": cmd_field_equals,
    "has_nonnull": cmd_has_nonnull,
    "tokens_equal": cmd_tokens_equal,
    "top_equals_sum": cmd_top_equals_sum,
    "ratio_between": cmd_ratio_between,
    "not_equal": cmd_not_equal,
    "report_field_equals": cmd_report_field_equals,
    "report_warning_contains": cmd_report_warning_contains,
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
PYEOF

V() { python3 "$TMP/verify.py" "$@" 2>/dev/null; }

# ── 1-3: the intro-rate window (pricing.py only) ──────────────────────────────
t1="$(V tier "$ANALYSIS_DIR" "$MODEL" 2026-08-01)"
check "1. a date before the intro window starts prices standard (got $t1)" '[[ "$t1" == "standard" ]]'

TOKENS_23='{"input":1000,"output":1000,"cache_read":0,"cache_creation_5m":0,"cache_creation_1h":0}'
t2="$(V tier "$ANALYSIS_DIR" "$MODEL" 2026-08-22)"
check "2a. a date inside the intro window prices intro (got $t2)" '[[ "$t2" == "intro" ]]'
r2="$(V cost_ratio_check "$ANALYSIS_DIR" "$MODEL" 2026-08-01 2026-08-22 "$TOKENS_23" 0.6666666666666666 "$TOL")"
check "2b. intro-tier cost is exactly 2/3 of standard for identical tokens (got $r2)" '[[ "$r2" == "True" ]]'

t3="$(V tier "$ANALYSIS_DIR" "$MODEL" 2026-09-01)"
check "3. a date after the window's expiry prices standard again (got $t3)" '[[ "$t3" == "standard" ]]'

# ── Fixture corpus for assertions 4-12 ────────────────────────────────────────
FEAT="$AT/self/features/fixcost/auto/complete"
mkdir -p "$FEAT"
HOME_DIR="$TMP/home"
PROJ_DIR="$HOME_DIR/.claude/projects/proj1"
mkdir -p "$PROJ_DIR"
export HOME="$HOME_DIR"

TS="2026-08-01T10:00:00.000Z"
AS_OF="2026-08-01"

# assertion 4/5: one killed attempt, one transcript line.
S4="sess-assert4"
transcript_line m4 "$MODEL" "$TS" 1000 500 2000 0 0 > "$PROJ_DIR/$S4.jsonl"
U4="$FEAT/assert4-basic-sonnet.usage.json"
write_usage_json "$U4" "$S4:killed:null"
TOKENS4='{"input":1000,"output":500,"cache_read":2000,"cache_creation_5m":0,"cache_creation_1h":0}'

# assertion 6: two killed attempts in one sidecar, each with its own transcript.
S6A="sess-assert6a"; S6B="sess-assert6b"
transcript_line m6a "$MODEL" "$TS" 200 100 0 0 0 > "$PROJ_DIR/$S6A.jsonl"
transcript_line m6b "$MODEL" "$TS" 300 150 0 0 0 > "$PROJ_DIR/$S6B.jsonl"
U6="$FEAT/assert6-sum-sonnet.usage.json"
write_usage_json "$U6" "$S6A:killed:null" "$S6B:killed:null"

# assertion 7: identical total cache-creation tokens, one all-5m, one all-1h.
S7_5M="sess-assert7-5m"; S7_1H="sess-assert7-1h"
transcript_line m7a "$MODEL" "$TS" 0 0 0 10000 0 > "$PROJ_DIR/$S7_5M.jsonl"
transcript_line m7b "$MODEL" "$TS" 0 0 0 0 10000 > "$PROJ_DIR/$S7_1H.jsonl"
U7_5M="$FEAT/assert7-5m-sonnet.usage.json"
U7_1H="$FEAT/assert7-1h-sonnet.usage.json"
write_usage_json "$U7_5M" "$S7_5M:killed:null"
write_usage_json "$U7_1H" "$S7_1H:killed:null"

# assertion 8: already-measured attempt, transcript present but must be ignored.
S8="sess-assert8"
transcript_line m8 "$MODEL" "$TS" 999 999 0 0 0 > "$PROJ_DIR/$S8.jsonl"
U8="$FEAT/assert8-measured-sonnet.usage.json"
write_usage_json "$U8" "$S8:success:3.14"
cp "$U8" "$TMP/assert8.pristine"

# assertion 10: killed attempt, no transcript anywhere.
S10="sess-assert10-missing"
U10="$FEAT/assert10-missing-sonnet.usage.json"
write_usage_json "$U10" "$S10:killed:null"

# assertion 11: dedup by message.id, and the same fixture with dedup defeated.
S11_DUP="sess-assert11-dup"; S11_NODUP="sess-assert11-nodup"
{
  transcript_line dup-msg "$MODEL" "$TS" 100 50 0 0 0
  transcript_line dup-msg "$MODEL" "$TS" 100 50 0 0 0
  transcript_line dup-msg "$MODEL" "$TS" 100 50 0 0 0
} > "$PROJ_DIR/$S11_DUP.jsonl"
{
  transcript_line trip-1 "$MODEL" "$TS" 100 50 0 0 0
  transcript_line trip-2 "$MODEL" "$TS" 100 50 0 0 0
  transcript_line trip-3 "$MODEL" "$TS" 100 50 0 0 0
} > "$PROJ_DIR/$S11_NODUP.jsonl"
U11_DUP="$FEAT/assert11-dup-sonnet.usage.json"
U11_NODUP="$FEAT/assert11-nodup-sonnet.usage.json"
write_usage_json "$U11_DUP" "$S11_DUP:killed:null"
write_usage_json "$U11_NODUP" "$S11_NODUP:killed:null"
TOKENS11_1X='{"input":100,"output":50,"cache_read":0,"cache_creation_5m":0,"cache_creation_1h":0}'
TOKENS11_3X='{"input":300,"output":150,"cache_read":0,"cache_creation_5m":0,"cache_creation_1h":0}'

# assertion 12: a real line plus a synthetic notice with deliberately non-zero usage.
S12="sess-assert12"
{
  transcript_line m12 "$MODEL" "$TS" 100 50 0 0 0
  synthetic_line "$TS" 99999 99999
} > "$PROJ_DIR/$S12.jsonl"
U12="$FEAT/assert12-synthetic-sonnet.usage.json"
write_usage_json "$U12" "$S12:killed:null"
TOKENS12='{"input":100,"output":50,"cache_read":0,"cache_creation_5m":0,"cache_creation_1h":0}'

# assertion 13: a model absent from pricing.RATES, plus a mixed transcript (one
# priceable model, one not). Lives in its own feature dir, not fixcost, because the
# report.py half needs a clean manifest + planning.json with no unrelated
# partial/orphan plans muddying total_is_partial.
UNPRICED_MODEL="claude-not-a-real-model-9"
REPFEAT13="$AT/self/features/rpt13-unpriced"
RFEAT13="$REPFEAT13/auto/complete"
mkdir -p "$RFEAT13"

S13U="sess-assert13-unpriced"
transcript_line m13u "$UNPRICED_MODEL" "$TS" 1000 500 0 0 0 > "$PROJ_DIR/$S13U.jsonl"
U13U="$RFEAT13/p13u.usage.json"
write_usage_json "$U13U" "$S13U:killed:null"
cat > "$RFEAT13/p13u.md" <<'MDEOF'
# p13u

Test fixture plan for cost-recovery.sh assertion 13. Not a real plan.
MDEOF

S13M="sess-assert13-mixed"
{
  transcript_line m13m-priced "$MODEL" "$TS" 200 100 0 0 0
  transcript_line m13m-unpriced "$UNPRICED_MODEL" "$TS" 300 150 0 0 0
} > "$PROJ_DIR/$S13M.jsonl"
U13M="$RFEAT13/p13m.usage.json"
write_usage_json "$U13M" "$S13M:killed:null"
cat > "$RFEAT13/p13m.md" <<'MDEOF'
# p13m

Test fixture plan for cost-recovery.sh assertion 13. Not a real plan.
MDEOF
TOKENS13M_PRICED='{"input":200,"output":100,"cache_read":0,"cache_creation_5m":0,"cache_creation_1h":0}'

cat > "$REPFEAT13/README.md" <<'MDEOF'
# rpt13-unpriced

Test fixture only, for cost-recovery.sh assertion 13.

```json
{"plans": ["p13u", "p13m"]}
```
MDEOF
cat > "$REPFEAT13/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false}}
JSONEOF

# ── Run 1 ──────────────────────────────────────────────────────────────────────
run1_out="$(python3 "$AT/analysis/recover_attempts.py" --self 2>&1)"; run1_rc=$?

# assertion 4
r4a="$(V recovered_cost_matches "$U4" "$S4" "$ANALYSIS_DIR" "$MODEL" "$AS_OF" "$TOKENS4" "$TOL")"
check "4a. recovered_cost_usd matches pricing.compute_cost on the transcript's tokens (got $r4a)" '[[ "$r4a" == "True" ]]'
r4b="$(V tokens_equal "$U4" "$S4" "$MODEL" "$TOKENS4")"
check "4b. recovered_tokens carries the five-key shape, per model (got $r4b)" '[[ "$r4b" == "True" ]]'
r4c="$(V field_equals "$U4" "$S4" recovered_from '"transcript"')"
check "4c. recovered_from is \"transcript\" (got $r4c)" '[[ "$r4c" == "True" ]]'
r4d="$(V has_nonnull "$U4" "$S4" recovered_at rates_applied)"
check "4d. recovered_at and rates_applied are both present (got $r4d)" '[[ "$r4d" == "True" ]]'

# assertion 5
r5="$(V field_equals "$U4" "$S4" total_cost_usd null)"
check "5. total_cost_usd is left null — measured and recovered stay distinguishable (got $r5)" '[[ "$r5" == "True" ]]'

# assertion 6
r6="$(V top_equals_sum "$U6")"
check "6. top-level recovered_cost_usd equals the sum over recovered attempts (got $r6)" '[[ "$r6" == "True" ]]'

# assertion 7
r7="$(V ratio_between "$ANALYSIS_DIR" "$U7_5M" "$S7_5M" "$U7_1H" "$S7_1H" "$TOL")"
check "7. the 5m/1h cache-creation split prices in the CACHE_WRITE_1H_MULTIPLIER/CACHE_WRITE_5M_MULTIPLIER ratio (got $r7)" '[[ "$r7" == "True" ]]'

# assertion 8 — checked against the file as it existed before ANY recovery run.
check "8. an attempt with a real total_cost_usd is left byte-identical" 'diff -q "$U8" "$TMP/assert8.pristine" >/dev/null 2>&1'

# assertion 10
r10a="$(V field_equals "$U10" "$S10" recovered_cost_usd null)"
check "10a. a killed attempt with no transcript is left untouched (got $r10a)" '[[ "$r10a" == "True" ]]'
check "10b. the missing transcript is reported as unrecoverable on stdout" 'grep -q "unrecoverable" <<<"$run1_out" && grep -q "$S10" <<<"$run1_out"'
check "10c. recovery still exits 0 (got $run1_rc)" '[[ $run1_rc -eq 0 ]]'

# assertion 11
r11a="$(V recovered_cost_matches "$U11_DUP" "$S11_DUP" "$ANALYSIS_DIR" "$MODEL" "$AS_OF" "$TOKENS11_1X" "$TOL")"
check "11a. three lines sharing one message.id bill once (got $r11a)" '[[ "$r11a" == "True" ]]'
r11b="$(V recovered_cost_matches "$U11_NODUP" "$S11_NODUP" "$ANALYSIS_DIR" "$MODEL" "$AS_OF" "$TOKENS11_3X" "$TOL")"
check "11b. the same fixture with dedup defeated bills three times (got $r11b)" '[[ "$r11b" == "True" ]]'
r11c="$(V not_equal "$U11_DUP" "$S11_DUP" "$U11_NODUP" "$S11_NODUP")"
check "11c. the dedup and defeated-dedup fixtures recover different costs (got $r11c)" '[[ "$r11c" == "True" ]]'

# assertion 12
r12="$(V recovered_cost_matches "$U12" "$S12" "$ANALYSIS_DIR" "$MODEL" "$AS_OF" "$TOKENS12" "$TOL")"
check "12. a model: \"<synthetic>\" line contributes nothing (got $r12)" '[[ "$r12" == "True" ]]'

# assertion 13 — attempt-level fields (defect 1: recover_attempts.py must not swallow an
# unpriced model into a silent 0).
r13a="$(V field_equals "$U13U" "$S13U" recovered_is_partial true)"
check "13a. an attempt on an unpriced model is marked recovered_is_partial (got $r13a)" '[[ "$r13a" == "True" ]]'
r13b="$(V field_equals "$U13U" "$S13U" unpriced_models "[\"$UNPRICED_MODEL\"]")"
check "13b. unpriced_models names the model (got $r13b)" '[[ "$r13b" == "True" ]]'

r13c="$(V recovered_cost_matches "$U13M" "$S13M" "$ANALYSIS_DIR" "$MODEL" "$AS_OF" "$TOKENS13M_PRICED" "$TOL")"
check "13c. a mixed transcript still recovers the priceable model's dollars (got $r13c)" '[[ "$r13c" == "True" ]]'
r13d="$(V field_equals "$U13M" "$S13M" recovered_is_partial true)"
check "13d. the mixed-model attempt is still marked partial (got $r13d)" '[[ "$r13d" == "True" ]]'

# assertion 13 — report.py's classification (defect 1's other half: a report must not
# call an unpriced-model plan's total "recovered and whole").
python3 "$AT/analysis/report.py" rpt13-unpriced --self >/dev/null 2>&1
R13="$REPFEAT13/report.json"
r13e="$(V report_field_equals "$R13" cost.total_is_partial true)"
check "13e. report.py classes an unpriced-model plan's total as partial (got $r13e)" '[[ "$r13e" == "True" ]]'

# assertion 14 — attempt-level recovery must survive write_usage_sidecar erasing the
# top-level recovered_cost_usd key. Constructed directly, not via recover_attempts.py:
# the contract under test is report.py's reading of a sidecar shape, not recovery itself.
REPFEAT14A="$AT/self/features/rpt14-durable"
RFEAT14A="$REPFEAT14A/auto/complete"
mkdir -p "$RFEAT14A"
cat > "$REPFEAT14A/README.md" <<'MDEOF'
# rpt14-durable

Test fixture only, for cost-recovery.sh assertion 14.

```json
{"plans": ["p14a"]}
```
MDEOF
cat > "$REPFEAT14A/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false}}
JSONEOF
cat > "$RFEAT14A/p14a.md" <<'MDEOF'
# p14a

Test fixture plan for cost-recovery.sh assertion 14. Not a real plan.
MDEOF
# Top level deliberately carries NO recovered_cost_usd key at all — simulating
# write_usage_sidecar's fixed-key rebuild on a resumed plan (plan-runner-lib.sh:554-581).
cat > "$RFEAT14A/p14a.usage.json" <<'JSONEOF'
{
  "plan": "p14a",
  "model": "sonnet",
  "outcome": "killed",
  "session_id": null,
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": null,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": [
    {
      "session_id": "sess-p14a",
      "outcome": "killed",
      "total_cost_usd": null,
      "num_turns": 1,
      "duration_ms": 1000,
      "recovered_cost_usd": 2.5,
      "recovered_tokens": {"claude-sonnet-5": {"input": 1000, "output": 500, "cache_read": 0, "cache_creation_5m": 0, "cache_creation_1h": 0}},
      "recovered_from": "transcript",
      "recovered_at": "2026-08-01T10:00:00.000Z",
      "rates_applied": {"claude-sonnet-5": {"model": "claude-sonnet-5", "input": 3, "output": 15, "cache_read": 0.3, "cache_creation_5m": 3.75, "cache_creation_1h": 6.0, "tier": "standard"}}
    }
  ]
}
JSONEOF
python3 "$AT/analysis/report.py" rpt14-durable --self >/dev/null 2>&1
R14A="$REPFEAT14A/report.json"
r14a="$(V report_field_equals "$R14A" cost.recovered 2.5)"
check "14a. attempt-level dollars land in cost.recovered despite the erased top-level key (got $r14a)" '[[ "$r14a" == "True" ]]'
r14b="$(V report_field_equals "$R14A" cost.build 2.5)"
check "14b. ...and in the queue bucket cost.build (got $r14b)" '[[ "$r14b" == "True" ]]'
r14c="$(V report_field_equals "$R14A" cost.total_is_partial false)"
check "14c. the total is not marked partial on that account — nothing is actually missing (got $r14c)" '[[ "$r14c" == "True" ]]'

# assertion 14 — the cross-check half: a top-level recovered_cost_usd that disagrees
# with the sum of attempts[] must warn naming both figures, not silently prefer one.
REPFEAT14B="$AT/self/features/rpt14-mismatch"
RFEAT14B="$REPFEAT14B/auto/complete"
mkdir -p "$RFEAT14B"
cat > "$REPFEAT14B/README.md" <<'MDEOF'
# rpt14-mismatch

Test fixture only, for cost-recovery.sh assertion 14.

```json
{"plans": ["p14b"]}
```
MDEOF
cat > "$REPFEAT14B/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false}}
JSONEOF
cat > "$RFEAT14B/p14b.md" <<'MDEOF'
# p14b

Test fixture plan for cost-recovery.sh assertion 14. Not a real plan.
MDEOF
# attempts[] sum to 4.25; the top-level figure says 9.75 — a disagreement that must not
# be silently reconciled in either direction.
cat > "$RFEAT14B/p14b.usage.json" <<'JSONEOF'
{
  "plan": "p14b",
  "model": "sonnet",
  "outcome": "killed",
  "session_id": null,
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": null,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "recovered_cost_usd": 9.75,
  "attempts": [
    {
      "session_id": "sess-p14b-1",
      "outcome": "killed",
      "total_cost_usd": null,
      "num_turns": 1,
      "duration_ms": 1000,
      "recovered_cost_usd": 1.25,
      "recovered_from": "transcript",
      "recovered_at": "2026-08-01T10:00:00.000Z"
    },
    {
      "session_id": "sess-p14b-2",
      "outcome": "killed",
      "total_cost_usd": null,
      "num_turns": 1,
      "duration_ms": 1000,
      "recovered_cost_usd": 3.0,
      "recovered_from": "transcript",
      "recovered_at": "2026-08-01T10:00:00.000Z"
    }
  ]
}
JSONEOF
python3 "$AT/analysis/report.py" rpt14-mismatch --self >/dev/null 2>&1
R14B="$REPFEAT14B/report.json"
r14d="$(V report_warning_contains "$R14B" "4.25" "9.75")"
check "14d. a disagreeing top-level recovered_cost_usd warns naming both figures (got $r14d)" '[[ "$r14d" == "True" ]]'

# ── 9: run again, unchanged ────────────────────────────────────────────────────
SNAPSHOT="$TMP/features-after-run1"
cp -r "$AT/self/features" "$SNAPSHOT"
python3 "$AT/analysis/recover_attempts.py" --self >/dev/null 2>&1
check "9. running recovery twice is idempotent" 'diff -rq "$AT/self/features" "$SNAPSHOT" >/dev/null 2>&1'

if (( fails > 0 )); then echo "cost-recovery: $fails assertion(s) FAILED"; exit 1; fi
echo "cost-recovery: all assertions passed"
