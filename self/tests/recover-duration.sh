#!/usr/bin/env bash
set -uo pipefail

# Self-test for the recovered duration lower bound
# (self/features/recovered-duration-lower-bound/README.md, item 1's first two points).
# Run by self/gate.sh, or by hand: bash self/tests/recover-duration.sh
#
# Same scaffolding as recover-at-close.sh's phase B — copies of `analysis/pricing.py`,
# `roots.py`, `transcript.py` and `recover_attempts.py` into a throwaway agentTooling
# checkout under mktemp -d, a synthesized `self/features/` corpus of `usage.json`
# sidecars, and `~/.claude/projects/*/<session_id>.jsonl` transcripts under a redirected
# $HOME. No model, no network; a second or two.
#
# $HOME is redirected rather than a path being passed in: `Path.home()` is what resolves
# both the transcript glob and the claims ledger, so redirecting it moves the whole of
# `~/.claude` at once and no test can reach the real one (self/tests/README.md).
#
# The defect (self/BACKLOG.md, raised by `tooling-backlog-2026-09-06`): an attempt whose
# `result` event never arrived has a null `duration_ms` as well as a null
# `total_cost_usd`. `recover_attempts.py` priced the tokens and stopped there, so the
# plan's bucket read `0.0` minutes with a `†` naming it, while the transcript on disk
# bounded the run all along — its first and last instants are the lower bound nobody
# derived.
#
# Asserts, in order:
#   1. an unpriced attempt whose transcript survives gains `recovered_duration_s`, the
#      span between the transcript's first and last instants in seconds — including a
#      trailing line that is not an assistant response, since what bounds the run is the
#      transcript, not the billing — beside the `recovered_cost_usd` it already gained,
#      and `total_cost_usd`/`duration_ms` are both still null (a measured figure is never
#      overwritten, and a recovered one must stay distinguishable);
#   2. the sidecar's top-level `recovered_duration_s` is the sum over its recovered
#      attempts, the way the top-level `recovered_cost_usd` beside it already was;
#   3. a transcript with fewer than two timestamped lines writes NO duration at all —
#      not `0.0`, which would read as "the run took no time" — while still recovering the
#      cost, and the sidecar gains no top-level duration key either;
#   4. an attempt whose transcript is gone is untouched and reported as unrecoverable,
#      exactly as today;
#   5. an attempt that already carries `recovered_cost_usd` and no duration — every
#      attempt recovered before this feature existed — is skipped by the idempotent run
#      and backfilled by `--force`, which is the documented repair path;
#   6. an attempt with a measured `duration_ms` is never visited: no
#      `recovered_duration_s` is written beside a figure the CLI reported.
#
# RED until item 1 lands: 1, 2, 3 and 5 find no `recovered_duration_s` anywhere. 4 and 6
# guard what already works and must keep working. A missing script fails its own
# assertions loudly rather than aborting the run — the cost-recovery.sh convention (no
# `set -e`, and every cp below tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recover-duration.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# pwd -P for the reason capture-guard.sh gives: roots.py resolves AGENT_TOOLING_DIR with
# Path.resolve(), and on macOS an unresolved /var/... fixture path matches nothing.
TMP="$(cd "$TMP" && pwd -P)"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
source "$HERE/self/tests/fixtures/usage/build-usage.sh"

AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"
for f in pricing.py roots.py transcript.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
# One field of a JSON file, or the empty string if the file, the path or the interpreter
# is not there — an absent deliverable must fail an assertion, never abort the script.
jf() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

echo "recover duration"

FAKE_HOME="$TMP/home"
PROJ="$FAKE_HOME/.claude/projects/recover-duration-fixtures"
mkdir -p "$PROJ"
export HOME="$FAKE_HOME"

MODEL="claude-opus-5"
# The three instants the span is measured between. `LAST` is deliberately later than the
# last billable line, and carried by a `user` line, so assertion 1 fails if the span is
# taken over `iter_billable_messages`'s yields instead of over the transcript.
FIRST="2026-09-04T20:00:00.000Z"
MID="2026-09-04T20:05:00.000Z"
LAST="2026-09-04T20:07:30.000Z"
SPAN_S="450.0"          # FIRST -> LAST, the figure the sidecar must carry
# A second transcript, so the top-level sum in assertion 2 is not just a copy of the one
# attempt's figure: 20:00:00 -> 20:01:00.
SPAN2_S="60.0"
SUM_S="510.0"

# A `user` line: timestamped, carries no usage, and is not what iter_billable_messages
# yields. The last instant of a real transcript is one of these far more often than not.
user_line() {                          # user_line TIMESTAMP
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"ok"}}\n' "$1"
}

recover() { python3 "$AT/analysis/recover_attempts.py" --self "$@" 2>&1; }

# ── 1 + 2: the span, and the top-level sum ───────────────────────────────────
S_SPAN="sess-span"; S_SHORT="sess-second"
F_ONE="$AT/self/features/spanfeature/review/complete"
mkdir -p "$F_ONE"
U_ONE="$F_ONE/01-review-opus.usage.json"
write_usage_json "$U_ONE" "$S_SPAN:complete:null" "$S_SHORT:complete:null"
# write_usage_json gives every attempt a duration_ms of 1000; these two are unpriced and
# unmeasured, which is the shape under test.
python3 - "$U_ONE" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for attempt in data["attempts"]:
    attempt["duration_ms"] = None
json.dump(data, open(path, "w"), indent=2)
PY
{
  transcript_line m-1 "$MODEL" "$FIRST" 1000 500 2000 0 0
  transcript_line m-2 "$MODEL" "$MID"   1000 500 2000 0 0
  user_line "$LAST"
} > "$PROJ/$S_SPAN.jsonl"
{
  transcript_line m-3 "$MODEL" "$FIRST" 1000 500 2000 0 0
  transcript_line m-4 "$MODEL" "2026-09-04T20:01:00.000Z" 1000 500 2000 0 0
} > "$PROJ/$S_SHORT.jsonl"

out1="$(recover --for spanfeature)"; rc1=$?
d1="$(jf "$U_ONE" 'd["attempts"][0].get("recovered_duration_s")')"
c1="$(jf "$U_ONE" 'd["attempts"][0].get("recovered_cost_usd")')"
check "1a. an unpriced attempt gains recovered_duration_s from its transcript's first and last instants (rc $rc1, got ${d1:-<absent>})" '[[ $rc1 -eq 0 && "$d1" == "$SPAN_S" ]]'
check "1b. ... beside the recovered_cost_usd it already gained (got ${c1:-<absent>})" '[[ -n "$c1" && "$c1" != "None" ]]'
m1="$(jf "$U_ONE" '(d["attempts"][0].get("total_cost_usd"), d["attempts"][0].get("duration_ms"))')"
check "1c. ... while the measured figures stay null — a recovered duration never becomes a measured one (got ${m1:-<absent>})" '[[ "$m1" == "(None, None)" ]]'
d2="$(jf "$U_ONE" 'd["attempts"][1].get("recovered_duration_s")')"
check "1d. the second attempt carries its own, shorter span (got ${d2:-<absent>})" '[[ "$d2" == "$SPAN2_S" ]]'
top1="$(jf "$U_ONE" 'd.get("recovered_duration_s")')"
check "2. the sidecar's top level carries the sum over its recovered attempts, as it does for dollars (got ${top1:-<absent>})" '[[ "$top1" == "$SUM_S" ]]'

# ── 3: one timestamped line is not a span ────────────────────────────────────
S_LONE="sess-lone"
F_LONE="$AT/self/features/lonefeature/review/complete"
mkdir -p "$F_LONE"
U_LONE="$F_LONE/01-review-opus.usage.json"
write_unpriced_usage_json "$U_LONE" "$S_LONE" opus
transcript_line m-lone "$MODEL" "$FIRST" 1000 500 2000 0 0 > "$PROJ/$S_LONE.jsonl"
recover --for lonefeature >/dev/null
lone_d="$(jf "$U_LONE" '"recovered_duration_s" in d["attempts"][0]')"
lone_c="$(jf "$U_LONE" 'd["attempts"][0].get("recovered_cost_usd")')"
check "3a. a one-line transcript writes no duration at all — not 0.0 (got key present: ${lone_d:-<absent>})" '[[ "$lone_d" == "False" ]]'
check "3b. ... while its cost is still recovered (got ${lone_c:-<absent>})" '[[ -n "$lone_c" && "$lone_c" != "None" ]]'
lone_top="$(jf "$U_LONE" '"recovered_duration_s" in d')"
check "3c. ... and the sidecar gains no top-level duration key either" '[[ "$lone_top" == "False" ]]'

# ── 4: a transcript that is gone ─────────────────────────────────────────────
S_GONE="sess-gone"
F_GONE="$AT/self/features/gonefeature/review/complete"
mkdir -p "$F_GONE"
U_GONE="$F_GONE/01-review-opus.usage.json"
write_unpriced_usage_json "$U_GONE" "$S_GONE" opus
cp "$U_GONE" "$TMP/gone.pristine"
gone_out="$(recover --for gonefeature)"; gone_rc=$?
check "4a. an attempt whose transcript is gone is left byte-identical (rc $gone_rc)" '[[ $gone_rc -eq 0 ]] && cmp -s "$TMP/gone.pristine" "$U_GONE"'
check "4b. ... and is reported as unrecoverable, exactly as today" 'grep -q "unrecoverable:" <<<"$gone_out" && grep -q "$S_GONE" <<<"$gone_out"'

# ── 5: the pre-feature shape, and --force ────────────────────────────────────
# An attempt recovered before this feature existed: a recovered cost, no duration. The
# idempotence check skips it, which is right — and --force is what backfills it, the same
# repair path a drifted top-level figure already documents.
S_OLD="sess-old"
F_OLD="$AT/self/features/oldfeature/review/complete"
mkdir -p "$F_OLD"
U_OLD="$F_OLD/01-review-opus.usage.json"
write_unpriced_usage_json "$U_OLD" "$S_OLD" opus
python3 - "$U_OLD" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["attempts"][0].update({
    "recovered_cost_usd": 0.5,
    "recovered_from": "transcript",
    "recovered_at": "2026-09-01T00:00:00+00:00",
})
data["recovered_cost_usd"] = 0.5
json.dump(data, open(path, "w"), indent=2)
PY
{
  transcript_line m-old "$MODEL" "$FIRST" 1000 500 2000 0 0
  user_line "$LAST"
} > "$PROJ/$S_OLD.jsonl"
cp "$U_OLD" "$TMP/old.pristine"
recover --for oldfeature >/dev/null
check "5a. an already-recovered attempt with no duration is skipped by an ordinary run" 'cmp -s "$TMP/old.pristine" "$U_OLD"'
recover --for oldfeature --force >/dev/null
old_d="$(jf "$U_OLD" 'd["attempts"][0].get("recovered_duration_s")')"
check "5b. --force re-derives it, backfilling the span (got ${old_d:-<absent>})" '[[ "$old_d" == "$SPAN_S" ]]'

# ── 6: a measured duration is never shadowed ─────────────────────────────────
S_MEASURED="sess-measured"
F_MEASURED="$AT/self/features/measuredfeature/auto/complete"
mkdir -p "$F_MEASURED"
U_MEASURED="$F_MEASURED/01-build-sonnet.usage.json"
write_usage_json "$U_MEASURED" "$S_MEASURED:complete:1.25"
{
  transcript_line m-meas "$MODEL" "$FIRST" 1000 500 2000 0 0
  user_line "$LAST"
} > "$PROJ/$S_MEASURED.jsonl"
cp "$U_MEASURED" "$TMP/measured.pristine"
recover --for measuredfeature >/dev/null
check "6. a priced, measured attempt is never visited — no recovered figure beside a reported one" 'cmp -s "$TMP/measured.pristine" "$U_MEASURED"'

echo
if (( fails > 0 )); then echo "recover-duration: $fails assertion(s) FAILED"; exit 1; fi
echo "recover-duration: all assertions passed"
