#!/usr/bin/env bash
set -uo pipefail

# Self-test for the hard-killed-session usage-limit signal
# (self/features/tooling-backlog-2026-09-06/README.md, item 1). Run by self/gate.sh, or
# by hand: bash self/tests/usage-limit-kill.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — the real runner scripts, a
# stub `claude` that cats a canned `.stream.jsonl` and exits with a set code, a stub
# `self/gate.sh` — and drives the real `run-plans.sh --self` at it. No model, no network.
#
# The defect: `stream_shows_usage_limit` (plan-runner-lib.sh) inspected only the final
# `result` event. That is the right guard against a message that merely says "rate
# limit", but a session the platform cuts off at a usage limit is killed mid-turn and
# never emits one — so `finalize_plan` saw an ordinary non-zero rc, filed the plan and
# all four sidecars to `failed/`, and the `rc == 2` branch that leaves the plan in
# `inprogress/` for the next run to resume was dead for the case it exists for. That is
# what happened to vinylCatalogue's `group-commit-all-adjudication` review plan on
# 2026-09-04 (self/BACKLOG.md, raised by `stale-failed-sidecars`).
#
# The second signal is scoped as tightly as the manifest scopes it: the stream must have
# NO `result` event, its LAST parsed JSON event must be `type: "error"`, and that event
# must name HTTP 429 or a rate/usage limit in the same terms the final-result matcher
# already accepts. Everything outside that box keeps routing exactly as before, which is
# what phases 3 to 7 exist to pin.
#
# Asserts, in order:
#   1. no result event, last event an `error` naming HTTP 429 → usage limit: the plan
#      stays in auto/inprogress/, the runner exits 1, and the reason names the limit;
#   2. the same with a limit named in words instead of a status code;
#   3. no result event and no error event (killed mid-turn on an assistant event) still
#      routes to auto/failed/ — the ordinary-failure path is untouched;
#   4. an `error` event that names no limit at all still routes to auto/failed/;
#   5. an `error` naming 429 that is NOT the last event still routes to auto/failed/ —
#      the signal is the stream's ending, not a scan of its body;
#   6. a non-JSON line after the error event (claude's stderr is merged into the stream)
#      does not hide it: still a usage limit, since both readers parse with
#      STREAM_EVENTS_JQ;
#   7. a stream that DID reach a result event is judged by that event alone: a success
#      result after an `error` naming 429 is filed to auto/complete/, and a result whose
#      assistant text merely mentions "rate limit" is not a limit either;
#   8. the original signal is unchanged: a final `result` event that is an error naming
#      the limit still leaves the plan in inprogress/.
#
# RED until the second signal lands: phases 1, 2 and 6 file to auto/failed/ instead.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/usage-limit-kill.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/self/features" "$TMP/bin"
for f in run-plans.sh run-verify.sh run-review.sh run-batch.sh run-escalation-plan.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f"
done

# Stub claude: the canned stream named by CLAUDE_STUB_STREAM, then the exit code a
# killed session leaves. The stream file IS the fixture — every phase below writes one
# and nothing else about the run changes.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
cat "$CLAUDE_STUB_STREAM"
exit "${CLAUDE_STUB_RC:-1}"
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

cat > "$AT/self/gate.sh" <<'STUB'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
{ echo "# Gate report"; echo ""; echo "# VERDICT"; echo "all checks passed"; } > "$HERE/self/gate-report.txt"
exit 0
STUB
chmod +x "$AT/self/gate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$AT/self/pr.sh"; chmod +x "$AT/self/pr.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "usage-limit-kill"

SLUG=ulk
F="$AT/self/features/$SLUG"
PLAN=01-x-haiku
CANNED="$TMP/canned.stream.jsonl"

reset_feature() {
  rm -rf "$F" "$AT"/self/gate-report*.txt
  mkdir -p "$F/auto/incomplete" "$F/verify/incomplete" "$F/review/incomplete"
  echo '{"slug":"ulk","plans":["01-x-haiku"],"branches":[]}' > "$F/README.md"
  echo "plan" > "$F/auto/incomplete/$PLAN.md"
}

# The event lines, one helper each so a phase reads as the stream it is.
init_line()      { printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$1"; }
assistant_line() { printf '{"type":"assistant","session_id":"%s","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2"; }
# The kill: the platform's own error event, the last thing a cut-off session emits.
error_line()     { printf '{"type":"error","session_id":"%s","error":{"message":"%s"}}\n' "$1" "$2"; }
result_line()    { printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.5,"num_turns":2,"duration_ms":1000,"session_id":"%s","usage":{},"modelUsage":{}}\n' "$1"; }
limit_result_line() { printf '{"type":"result","subtype":"error","is_error":true,"result":"Claude usage limit reached","session_id":"%s","usage":{},"modelUsage":{}}\n' "$1"; }

# run_phase <claude exit code> — drives the real runner over the canned stream and
# returns its exit code, with the runner's output in $out.
run_phase() {
  out="$( cd "$AT" && CLAUDE_STUB_STREAM="$CANNED" CLAUDE_STUB_RC="$1" ./run-plans.sh --self "$SLUG" 2>&1 )"
  return $?
}

# ── 1: no result event, last event an error naming HTTP 429 ──────────────────
# The status code alone, with no limit words anywhere in the payload, so this phase
# pins the 429 half of the rule rather than riding on "exceeded" or "rate limit".
reset_feature
{ init_line sess-429
  assistant_line sess-429 "working"
  printf '{"type":"error","session_id":"sess-429","error":{"status":429,"message":"API Error: 429"}}\n'
} > "$CANNED"
run_phase 1; rc=$?
check "1a. a 429 error event with no result event exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "1b. ...the plan is LEFT in auto/inprogress/ for the next run" '[[ -f "$F/auto/inprogress/$PLAN.md" && ! -f "$F/auto/failed/$PLAN.md" ]]'
check "1c. ...and the reason names the usage limit" 'grep -q "usage limit reached" <<<"$out"'

# ── 2: the same limit named in words ──────────────────────────────────────────
reset_feature
{ init_line sess-words
  assistant_line sess-words "working"
  error_line sess-words "Claude usage limit reached; try again after 3pm"
} > "$CANNED"
run_phase 1; rc=$?
check "2a. an error event naming a usage limit in words exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "2b. ...and leaves the plan in auto/inprogress/" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'

# ── 3: killed mid-turn with no error event — still an ordinary failure ────────
reset_feature
{ init_line sess-mid
  assistant_line sess-mid "working"
} > "$CANNED"
run_phase 1; rc=$?
check "3a. no result and no error event exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "3b. ...and the plan is filed to auto/failed/, not left queued" '[[ -f "$F/auto/failed/$PLAN.md" && ! -f "$F/auto/inprogress/$PLAN.md" ]]'

# ── 4: an error event that names no limit ─────────────────────────────────────
reset_feature
{ init_line sess-err
  assistant_line sess-err "working"
  error_line sess-err "connection reset by peer"
} > "$CANNED"
run_phase 1; rc=$?
check "4a. an unrelated error event exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "4b. ...and files the plan to auto/failed/" '[[ -f "$F/auto/failed/$PLAN.md" ]]'

# ── 5: a 429 error event that is not the last one ─────────────────────────────
# The signal is how the stream ENDED. A limit reported mid-stream and recovered from is
# not a kill, and treating it as one would re-open the false-positive hole from the
# other side.
reset_feature
{ init_line sess-recovered
  printf '{"type":"error","session_id":"sess-recovered","error":{"status":429,"message":"API Error: 429"}}\n'
  assistant_line sess-recovered "retrying"
} > "$CANNED"
run_phase 1; rc=$?
check "5a. a 429 error followed by more events exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "5b. ...and files the plan to auto/failed/" '[[ -f "$F/auto/failed/$PLAN.md" ]]'

# ── 6: claude's merged stderr does not hide the error event ───────────────────
# `2>&1` puts stderr in the same file, so a runtime warning can be the physically last
# LINE while the error event is the last parsed EVENT. Both readers skip unparseable
# lines (STREAM_EVENTS_JQ); this is the assertion that says so.
reset_feature
{ init_line sess-stderr
  assistant_line sess-stderr "working"
  printf '{"type":"error","session_id":"sess-stderr","error":{"status":429,"message":"API Error: 429"}}\n'
  echo "(node:8123) Warning: something on stderr"
} > "$CANNED"
run_phase 1; rc=$?
check "6a. a trailing non-JSON line does not hide the 429 (exit $rc)" '[[ $rc -eq 1 ]]'
check "6b. ...the plan is still left in auto/inprogress/" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'

# ── 7: a stream that reached a result event is judged by that event ───────────
reset_feature
{ init_line sess-ok
  printf '{"type":"error","session_id":"sess-ok","error":{"status":429,"message":"API Error: 429"}}\n'
  result_line sess-ok
} > "$CANNED"
run_phase 0; rc=$?
check "7a. a success result after a 429 error is not a limit (exit $rc)" '[[ $rc -eq 0 ]]'
check "7b. ...and the plan is filed to auto/complete/" '[[ -f "$F/auto/complete/$PLAN.md" ]]'

reset_feature
{ init_line sess-text
  assistant_line sess-text "we hit a rate limit earlier and waited"
  result_line sess-text
} > "$CANNED"
run_phase 0; rc=$?
check "7c. assistant text mentioning a rate limit is still not a limit (exit $rc)" '[[ $rc -eq 0 ]]'
check "7d. ...and the plan is filed to auto/complete/" '[[ -f "$F/auto/complete/$PLAN.md" ]]'

# ── 8: the original signal, unchanged ─────────────────────────────────────────
reset_feature
{ init_line sess-limit
  limit_result_line sess-limit
} > "$CANNED"
run_phase 1; rc=$?
check "8a. a final result event naming the limit still exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "8b. ...and still leaves the plan in auto/inprogress/" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'
check "8c. ...naming the usage limit" 'grep -q "usage limit reached" <<<"$out"'

echo
if (( fails > 0 )); then echo "usage-limit-kill: $fails assertion(s) FAILED"; exit 1; fi
echo "usage-limit-kill: all assertions passed"
