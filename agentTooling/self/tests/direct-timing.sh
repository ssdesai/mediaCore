#!/usr/bin/env bash
set -uo pipefail

# Self-test for a direct feature's build milestones (AGENT_DIRECT.md → "Checkpoint and
# resume"; self/features/tooling-backlog-2026-09/README.md item 5). Run by self/gate.sh,
# or by hand: bash self/tests/direct-timing.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — the real stamp-timing.sh and
# plan-runner-roots.sh, plus copies of analysis/{pricing,roots,transcript,report}.py — and
# a synthesized self/features/ corpus of hand-written manifests, planning.json files and
# timing.jsonl streams. No model, no network; runs in a couple of seconds.
#
# Asserts, in order:
#   1. stamp-timing.sh --self <slug> checkpoint status=<s> appends one timing.jsonl line
#      carrying that event and that key, and repeated calls append rather than replace;
#   2. it refuses what it cannot stamp — a missing slug or event, a feature that does not
#      exist, and a detail argument that is not key=value — non-zero and writing nothing,
#      because a silently dropped milestone is a hole in the only record a direct build
#      leaves between its commits;
#   3. report.py derives tests_s (planned → tests-written), direct_build_s (tests-written
#      → gating) and gate_s (gating → committed) for a `method: direct` feature that has
#      checkpoint events, and renders them as sub-rows under "build: implementer" whose
#      minutes sum to the implementer row;
#   4. a direct feature with NO checkpoint events gains neither the keys nor the rows;
#   5. a `method: plans` feature gains neither either, even with checkpoint events on
#      disk — the sub-rows split an implementer's span, and a planned feature has none;
#   6. `method: hand` — a feature the coordinator built itself, no delegate — is treated
#      as direct is: the transcripts are the build, the row reads "build: by hand", the
#      checkpoint sub-rows apply, and no unknown-method warning fires.
#
# Depends on stamp_timing (plan-runner-roots.sh) writing through jq, and on report.py's
# compute_time_rollup/render_time_section reading `event: "checkpoint"` with a `status`.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

cp "$HERE/plan-runner-roots.sh" "$AT/plan-runner-roots.sh"
# stamp-timing.sh is this feature's deliverable; a missing cp must fail every assertion
# below loudly rather than abort the script (no `set -e`, and the rc is not checked).
cp "$HERE/stamp-timing.sh" "$AT/stamp-timing.sh" 2>/dev/null || true
for f in pricing.py roots.py transcript.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── Python verification helper ────────────────────────────────────────────────
# JSON parsing and float comparisons belong in Python, not bash. Every expected figure
# is derived from the fixture's own instants, never from a hardcoded literal repeated
# from the code under test.
cat > "$TMP/verify.py" <<'PYEOF'
import json
import sys


def load(path):
    with open(path) as handle:
        return json.load(handle)


def dig(data, dotted):
    for part in dotted.split("."):
        if not isinstance(data, dict) or part not in data:
            return "<absent>"
        data = data[part]
    return data


def field_equals(report, dotted, expected):
    print(json.dumps(dig(load(report), dotted)) == expected)


def has_key(report, dotted):
    print(dig(load(report), dotted) != "<absent>")


def seconds_equal(report, dotted, expected):
    value = dig(load(report), dotted)
    print(isinstance(value, (int, float)) and abs(value - float(expected)) < 1e-6)


def subrows_sum_to_implementer(report):
    time = load(report)["time"]
    parts = [time.get(k) for k in ("tests_s", "direct_build_s", "gate_s")]
    if any(p is None for p in parts):
        print(False)
        return
    print(abs(sum(parts) - time["implementer_s"]) < 1e-6)


globals()[sys.argv[1]](*sys.argv[2:])
PYEOF
V() { python3 "$TMP/verify.py" "$@"; }

# ── Fixtures ──────────────────────────────────────────────────────────────────
# One planning.json shape for every feature here: a direct feature's planning.json IS
# its implementer's transcript span, which is what the sub-rows subdivide.
IMPLEMENTER_S=3600
write_feature() {                     # write_feature <slug> <method> <duration_s>
  local slug="$1" method="$2" duration="$3" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MDEOF
# $slug

Test fixture only, for direct-timing.sh.

\`\`\`json
{"slug": "$slug", "method": "$method", "plans": [], "branches": []}
\`\`\`
MDEOF
  cat > "$dir/planning.json" <<JSONEOF
{"cost_usd": {"total": 12.0, "subagents": 0.0, "total_is_partial": false},
 "duration_s": {"sessions": $duration, "subagents": 0, "entries_without_duration": []}}
JSONEOF
}

# The four checkpoint milestones AGENT_DIRECT.md names, 10 / 35 / 15 minutes apart, so
# each derived span is distinct and a transposed pair would be visible.
TESTS_S=600
BUILD_S=2100
GATE_S=900
write_checkpoints() {                 # write_checkpoints <slug>
  local path="$AT/self/features/$1/timing.jsonl"
  {
    echo '{"at":"2026-09-02T12:00:00Z","event":"checkpoint","status":"planned"}'
    echo '{"at":"2026-09-02T12:10:00Z","event":"checkpoint","status":"tests-written"}'
    echo '{"at":"2026-09-02T12:20:00Z","event":"checkpoint","status":"implementing"}'
    echo '{"at":"2026-09-02T12:45:00Z","event":"checkpoint","status":"gating"}'
    echo '{"at":"2026-09-02T13:00:00Z","event":"checkpoint","status":"committed"}'
  } > "$path"
}

# ── 1: stamp-timing.sh appends a checkpoint line ─────────────────────────────
write_feature stamped direct "$IMPLEMENTER_S"
STAMPED="$AT/self/features/stamped/timing.jsonl"
( cd "$TMP" && "$AT/stamp-timing.sh" --self stamped checkpoint status=planned >/dev/null 2>&1 ); rc=$?
check "1a. stamping a checkpoint exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "1b. the line carries the event and the status" '[[ -f "$STAMPED" ]] && grep -q "\"event\":\"checkpoint\"" "$STAMPED" && grep -q "\"status\":\"planned\"" "$STAMPED"'
check '1c. the line carries a UTC at-instant to the second' 'grep -qE "\"at\":\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\"" "$STAMPED"'
( cd "$TMP" && "$AT/stamp-timing.sh" --self stamped checkpoint status=tests-written >/dev/null 2>&1 )
check "1d. a second milestone appends rather than replaces" '[[ "$(wc -l < "$STAMPED")" -eq 2 ]] && grep -q "tests-written" "$STAMPED"'
check "1e. --self is accepted first, like every other script" '[[ "$(head -1 "$STAMPED" | grep -c planned)" -eq 1 ]]'

# ── 2: it refuses what it cannot stamp ───────────────────────────────────────
( cd "$TMP" && "$AT/stamp-timing.sh" --self >/dev/null 2>&1 ); rc=$?
check "2a. no slug and no event exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
( cd "$TMP" && "$AT/stamp-timing.sh" --self stamped >/dev/null 2>&1 ); rc=$?
check "2b. a slug with no event exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
out="$(cd "$TMP" && "$AT/stamp-timing.sh" --self no-such-feature checkpoint status=planned 2>&1)"; rc=$?
check "2c. an unknown feature exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "2d. it names the feature it could not find" 'grep -q "no-such-feature" <<<"$out"'
check "2e. it wrote no timing.jsonl for a feature that does not exist" '[[ ! -e "$AT/self/features/no-such-feature" ]]'
before="$(wc -l < "$STAMPED")"
out="$(cd "$TMP" && "$AT/stamp-timing.sh" --self stamped checkpoint notakeyvalue 2>&1)"; rc=$?
check "2f. a detail argument that is not key=value exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "2g. and stamps nothing" '[[ "$(wc -l < "$STAMPED")" -eq "$before" ]]'

# ── 3: report.py derives and renders the three spans ─────────────────────────
write_feature direct-with direct "$IMPLEMENTER_S"
write_checkpoints direct-with
python3 "$AT/analysis/report.py" direct-with --self >/dev/null 2>&1
R="$AT/self/features/direct-with/report.json"
MD="$AT/self/features/direct-with/report.md"
r3a="$(V seconds_equal "$R" time.tests_s "$TESTS_S")"
check "3a. tests_s is planned → tests-written (got $r3a)" '[[ "$r3a" == "True" ]]'
r3b="$(V seconds_equal "$R" time.direct_build_s "$BUILD_S")"
check "3b. direct_build_s is tests-written → gating (got $r3b)" '[[ "$r3b" == "True" ]]'
r3c="$(V seconds_equal "$R" time.gate_s "$GATE_S")"
check "3c. gate_s is gating → committed (got $r3c)" '[[ "$r3c" == "True" ]]'
r3d="$(V subrows_sum_to_implementer "$R")"
check "3d. the three spans sum to the implementer row (got $r3d)" '[[ "$r3d" == "True" ]]'
check "3e. report.md renders a sub-row under build: implementer" 'grep -q "^| build: implementer |" "$MD" && [[ "$(grep -c "^| ↳ " "$MD")" -eq 3 ]]'
check "3f. the first sub-row sits immediately under the implementer row" '[[ "$(grep -A1 "^| build: implementer |" "$MD" | tail -1)" == "| ↳ acceptance tests"* ]]'
check "3g. the sub-rows carry minutes and no second dollar figure" 'grep -qE "^\| ↳ [^|]+\| [0-9]+\.[0-9] \|  *\|  *\|$" "$MD"'

# ── 4: a direct feature with no checkpoint events is unchanged ───────────────
write_feature direct-without direct "$IMPLEMENTER_S"
printf '{"at":"2026-09-02T12:00:00Z","event":"batch_start"}\n' > "$AT/self/features/direct-without/timing.jsonl"
python3 "$AT/analysis/report.py" direct-without --self >/dev/null 2>&1
R4="$AT/self/features/direct-without/report.json"
r4a="$(V has_key "$R4" time.tests_s)"
check "4a. no checkpoint events → no tests_s key (got $r4a)" '[[ "$r4a" == "False" ]]'
r4b="$(V has_key "$R4" time.direct_build_s)"
check "4b. ... nor direct_build_s (got $r4b)" '[[ "$r4b" == "False" ]]'
r4c="$(V has_key "$R4" time.gate_s)"
check "4c. ... nor gate_s (got $r4c)" '[[ "$r4c" == "False" ]]'
check "4d. ... and no sub-rows in report.md" '! grep -q "^| ↳ " "$AT/self/features/direct-without/report.md"'

# ── 5: a planned feature is untouched even with checkpoint events on disk ────
write_feature planned plans "$IMPLEMENTER_S"
write_checkpoints planned
python3 "$AT/analysis/report.py" planned --self >/dev/null 2>&1
R5="$AT/self/features/planned/report.json"
r5a="$(V has_key "$R5" time.tests_s)"
check "5a. method: plans → no tests_s key (got $r5a)" '[[ "$r5a" == "False" ]]'
check "5b. ... and no sub-rows in report.md" '! grep -q "^| ↳ " "$AT/self/features/planned/report.md"'
r5c="$(V field_equals "$R5" time.method '"plans"')"
check "5c. ... and the method is still recorded as plans (got $r5c)" '[[ "$r5c" == "True" ]]'

# ── 6: method hand is a build with no delegate ───────────────────────────────
write_feature handy hand "$IMPLEMENTER_S"
write_checkpoints handy
python3 "$AT/analysis/report.py" handy --self >/dev/null 2>&1
R6="$AT/self/features/handy/report.json"
MD6="$AT/self/features/handy/report.md"
r6a="$(V field_equals "$R6" time.method '"hand"')"
check "6a. method hand is recorded as hand (got $r6a)" '[[ "$r6a" == "True" ]]'
r6b="$(V subrows_sum_to_implementer "$R6")"
check "6b. the checkpoint spans apply and sum to the build row (got $r6b)" '[[ "$r6b" == "True" ]]'
check "6c. report.md reads build: by hand, with the sub-rows under it" 'grep -q "^| build: by hand |" "$MD6" && [[ "$(grep -c "^| ↳ " "$MD6")" -eq 3 ]]'
r6d="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(any('not one of' in w for w in d.get('warnings', [])))" "$R6" 2>/dev/null)"
check "6d. no unknown-method warning (got $r6d)" '[[ "$r6d" == "False" ]]'
r6e="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['cost']['implementer'] == d['cost']['total'] and d['cost']['planning'] == 0)" "$R6" 2>/dev/null)"
check "6e. every dollar is build, none is planning (got $r6e)" '[[ "$r6e" == "True" ]]'

if (( fails > 0 )); then echo "direct-timing: $fails assertion(s) FAILED"; exit 1; fi
echo "direct-timing: all assertions passed"
