#!/usr/bin/env bash
set -uo pipefail

# Self-test for the runner's stream capture (RUNNER.md → "Capturing the stream"). Run by
# self/gate.sh as `record "stream capture self-test" …`, or by hand:
#   bash self/tests/stream-capture.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — the real runner scripts, a
# stub `claude` that ignores SIGPIPE and emits a few thousand events, a stub self/gate.sh
# — and drives it with --self through a real `run-plans.sh` invocation. Nothing here
# touches this checkout's own queue, gate report or PATH beyond the subshell. No model,
# no network; runs in a few seconds.
#
# What it exists to catch: `run_plan` used to capture the stream with a `tee` in the
# MIDDLE of a pipeline whose last stage (display_stream) wrote to the caller's stdout.
# A consumer that stopped reading killed the last stage with SIGPIPE, then each `tee` on
# its next write, and the capture stopped — while `claude`, whose own stdout was the pipe
# into the first `tee`, ran to completion and exited 0. Nine merged reviews were filed as
# successes with a 689-byte .stream.jsonl, a 0-byte .progress.md and a
# `total_cost_usd: null` sidecar. The stub `claude` here therefore has to ignore SIGPIPE
# too: one that dies with the pipeline cannot tell the fix from the defect.
#
# Asserts, in order:
#   1. the healthy case — stdout to a file: the stream ends with the `result` event and
#      has every line, the sidecar is priced, .progress.md has one line per mutating
#      tool_use, the plan is filed to complete/, and the display really rendered;
#   2. stdout piped to a consumer that exits after two lines — i.e. before `claude` is
#      even started: identical results, and the runner still exits 0;
#   3. the same with a consumer that exits mid-stream, after the display has begun;
#   4. a stub that emits no `result` event and exits 0: the plan is still filed by its
#      exit code, the rc==0-without-a-result warning names the plan and the stream, and
#      the stream file survives;
#   5. the usage-limit routing is unchanged: a `result` event stream_shows_usage_limit
#      recognises leaves the plan in inprogress/ and stops the run.
#
# Depends on plan-runner-lib.sh's run_plan capturing the stream where nothing downstream
# can truncate it, on finalize_plan warning on rc==0 with no result event, and on the
# runner surviving a closed stdout — none of which is visible from an import line.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/self/features" "$TMP/bin"
for f in run-plans.sh run-verify.sh run-review.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f"
done

# ── Fixture sizes ────────────────────────────────────────────────────────────
# One `assistant` text event and one mutating `tool_use` event per step, wrapped in an
# init event and a result event. Big enough that the pre-fix pipeline is demonstrably
# truncated (a pipe buffer is 64 KiB; this is ~330 KiB) and small enough to stay under a
# second.
STUB_STEPS=1500
STUB_COST=1.25
STREAM_LINES=$(( STUB_STEPS * 2 + 2 ))   # init + 2 per step + result
PROGRESS_LINES=$STUB_STEPS               # one line per mutating tool_use
NO_RESULT_STREAM_LINES=$(( STUB_STEPS * 2 + 1 ))
# The consumer in phases 2 and 5 closes after this many lines: fewer than the runner's own
# preamble, so its stdout is dead before `claude` is started at all.
CLOSED_CONSUMER_LINES=2
# The consumer in phase 3 closes after this many lines: past the runner's own preamble
# and well into the displayed stream, so the capture is cut mid-flight rather than
# before `claude` starts.
MIDSTREAM_CONSUMER_LINES=40
# `slow` mode pauses every this-many steps for this long, so a run lasts a couple of
# seconds and the signal phases can kill it while `claude` is still writing.
STUB_SLOW_EVERY=25
STUB_SLOW_PAUSE=0.05
# Watchdog for the phases where the failure under test would be a HANG rather than a
# wrong answer (an unchecked mktemp, a follower with no way out). Generous — the whole
# script runs in a few seconds — but finite, so the gate reports a failure instead of
# never returning.
RUNNER_TIMEOUT_TICKS=200
WATCHDOG_TICK=0.1
# Polls of this length, up to this many, waiting for the stream to start growing or for
# the runner's processes to go away after a signal.
POLL_SECONDS=0.05
POLL_TRIES=200
# A much shorter budget for "nothing is still running after the signal". It has to be
# well under the time the `slow` stub still had left to run, or an orphaned `claude`
# finishing on its own would satisfy the assertion and the check would pass whether or
# not stop_capture killed anything.
ORPHAN_POLL_TRIES=40

# Stub claude. Ignores SIGPIPE the way the real CLI does — that is the whole point of the
# fixture. CLAUDE_STUB_MODE picks the ending: a priced result event (default), none at
# all, or one the usage-limit matcher recognises.
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
trap '' PIPE
sid="\${CLAUDE_STUB_SESSION_ID:-stub-session}"
printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "\$sid"
i=0
while (( i < $STUB_STEPS )); do
  printf '{"type":"assistant","session_id":"%s","message":{"content":[{"type":"text","text":"step %d"}]}}\n' "\$sid" "\$i"
  printf '{"type":"assistant","session_id":"%s","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/work/file%d.txt"}}]}}\n' "\$sid" "\$i"
  i=\$((i + 1))
  if [[ "\${CLAUDE_STUB_MODE:-normal}" == slow ]] && (( i % $STUB_SLOW_EVERY == 0 )); then
    sleep $STUB_SLOW_PAUSE
  fi
done
case "\${CLAUDE_STUB_MODE:-normal}" in
  no-result)
    exit 0 ;;
  malformed)
    # One line of merged stderr in the middle of the stream, then a perfectly good
    # result event. Nothing may treat this stream as truncated.
    printf 'warning: a non-JSON line on stderr, merged into the stream by 2>&1\n'
    printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":$STUB_COST,"num_turns":7,"duration_ms":4321,"session_id":"%s","usage":{"input_tokens":10,"output_tokens":20}}\n' "\$sid"
    exit 0 ;;
  usage-limit)
    printf '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Claude usage limit reached - your limit will reset at 3pm","session_id":"%s","total_cost_usd":0.5,"num_turns":2,"usage":{}}\n' "\$sid"
    exit 1 ;;
  *)
    printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":$STUB_COST,"num_turns":7,"duration_ms":4321,"session_id":"%s","usage":{"input_tokens":10,"output_tokens":20}}\n' "\$sid"
    exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

# Stub gate: never reached (no sentinels here), present so a stray level gate cannot run
# this checkout's real one.
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

SLUG=cap
F="$AT/self/features/$SLUG"
PLAN=01-capture-haiku
reset_feature() {
  rm -rf "$F"
  mkdir -p "$F/auto/incomplete" "$F/verify/incomplete" "$F/review/incomplete"
  echo '{"slug":"cap","plans":[],"branches":[]}' > "$F/README.md"
  echo "do the work for cap" > "$F/auto/incomplete/$PLAN.md"
}

# Line count of a file, or -1 when it is not there, so a missing file reads as a failed
# assertion with a number in it rather than as an empty string comparison.
lines_of() { if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo -1; fi; }
# The last event's `type`, or "" — the one field that says the capture reached the end.
last_type() { jq -r '.type // empty' < <(tail -1 "$1" 2>/dev/null) 2>/dev/null; }

# Where the runner's capture directories land. mktemp is given an explicit template
# under $TMPDIR, so pointing $TMPDIR here makes every capture directory visible to the
# assertions — and pointing it at $TMP/no-such-dir makes mktemp fail on demand, which is
# how the unwritable-temp phase is driven without touching permissions.
CAPTURE_TMP="$TMP/captmp"
NO_SUCH_TMP="$TMP/no-such-dir"
mkdir -p "$CAPTURE_TMP"
capture_dirs_left() { find "$CAPTURE_TMP" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

# Poll until <predicate> holds, up to POLL_TRIES × POLL_SECONDS. Returns non-zero if it
# never did, so an assertion reads as a failure rather than as a hang.
poll_until() {          # poll_until <shell condition> [tries]
  local i=0 tries="${2:-$POLL_TRIES}"
  while (( i < tries )); do
    if eval "$1"; then return 0; fi
    sleep "$POLL_SECONDS"
    i=$((i + 1))
  done
  return 1
}

# Start a runner in the background under a watchdog, setting $runner_pid. Two phases
# below signal it themselves, one waits for it to fail on its own — in every case the
# watchdog is what turns "it hung" into a reported failure rather than a gate that never
# returns. The watchdog polls instead of sleeping the whole timeout so it can retire
# quietly the moment the runner is reaped: a watchdog killed by a signal makes bash print
# a job-status line into the middle of the assertions.
start_runner() {        # start_runner <tmpdir> <stub mode> <out> <err>
  TMPDIR="$1" CLAUDE_STUB_MODE="$2" "$AT/run-plans.sh" --self "$SLUG" > "$3" 2> "$4" &
  runner_pid=$!
  ( wd=0
    while (( wd < RUNNER_TIMEOUT_TICKS )); do
      kill -0 "$runner_pid" 2>/dev/null || exit 0
      sleep "$WATCHDOG_TICK"
      wd=$((wd + 1))
    done
    kill -9 "$runner_pid" 2>/dev/null ) &
  watchdog_pid=$!
}

# Reap the runner into $runner_rc and let the watchdog retire. NOT a command
# substitution: `wait` only works on this shell's own children, and a $(…) subshell
# cannot reap the runner at all — it reports failure and leaves the process behind.
# $runner_rc of 137 means the watchdog fired, i.e. the runner never came back on its own.
reap_runner() {
  wait "$runner_pid"; runner_rc=$?
  wait "$watchdog_pid" 2>/dev/null
}

# Every process still alive inside the throwaway checkout: the runner, its follower
# subshell (a fork, so it keeps the runner's argv), the `tail` reading the stream, the
# stub `claude` (the sandbox paths are in its prompt) and the jq logger. Nothing may be
# left after a signal.
sandbox_procs_gone() { ! pgrep -f "$AT" >/dev/null 2>&1; }

# ── 1: the healthy consumer — stdout to a file ───────────────────────────────
# The baseline the fix must not disturb: with nobody closing the pipe early, everything
# about this run is what it always was.
reset_feature
DISPLAY_OUT="$TMP/display-1.out"
( cd "$AT" && ./run-plans.sh --self "$SLUG" > "$DISPLAY_OUT" 2>"$TMP/err-1.txt" ); rc=$?
C="$F/auto/complete/$PLAN"
check "1a. healthy run exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "1b. plan filed to auto/complete/" '[[ -f "$C.md" ]]'
check "1c. stream has every line (want $STREAM_LINES, got $(lines_of "$C.stream.jsonl"))" \
  '[[ "$(lines_of "$C.stream.jsonl")" == "'"$STREAM_LINES"'" ]]'
check "1d. stream ends with the result event (got \"$(last_type "$C.stream.jsonl")\")" \
  '[[ "$(last_type "$C.stream.jsonl")" == "result" ]]'
check "1e. sidecar total_cost_usd is $STUB_COST" \
  '[[ "$(jq -r ".total_cost_usd" "$C.usage.json" 2>/dev/null)" == "'"$STUB_COST"'" ]]'
check "1f. progress log has one line per mutating tool_use (want $PROGRESS_LINES, got $(lines_of "$C.progress.md"))" \
  '[[ "$(lines_of "$C.progress.md")" == "'"$PROGRESS_LINES"'" ]]'
check "1g. progress log lines name the edited files" \
  'grep -q "^edit: /work/file0.txt$" "$C.progress.md" && grep -q "^edit: /work/file$((STUB_STEPS - 1)).txt$" "$C.progress.md"'
# The display is a follower of the same file, so it can lag — but it must not stop. Its
# first, last and closing lines are asserted together: the follower reads the growing file
# in chunks, and a status misread there (`tail` killed by `head` under `pipefail` looks
# like a dead display) cut the terminal output off a few hundred events in while the
# capture itself ran on to the end.
check "1h. the display rendered the whole stream, first event to last" \
  'grep -q "step 0" "$DISPLAY_OUT" && grep -q "step $((STUB_STEPS - 1))" "$DISPLAY_OUT" && grep -q "\[result: success\]" "$DISPLAY_OUT"'

# ── 2: a consumer that closes after two lines ────────────────────────────────
# The defect's shape. `head -2` takes the runner's first two lines and exits, so the
# runner's stdout is dead before `claude` is even started: nothing downstream of the
# capture exists any more. Every assertion in phase 1 must still hold.
reset_feature
( cd "$AT" && ./run-plans.sh --self "$SLUG" 2>"$TMP/err-2.txt" ) | head -"$CLOSED_CONSUMER_LINES" > /dev/null
rc=${PIPESTATUS[0]}
C="$F/auto/complete/$PLAN"
check "2a. a closed consumer does not fail the plan (exit 0, got $rc)" '[[ $rc -eq 0 ]]'
check "2b. plan still filed to auto/complete/" '[[ -f "$C.md" ]]'
check "2c. stream still has every line (want $STREAM_LINES, got $(lines_of "$C.stream.jsonl"))" \
  '[[ "$(lines_of "$C.stream.jsonl")" == "'"$STREAM_LINES"'" ]]'
check "2d. stream still ends with the result event (got \"$(last_type "$C.stream.jsonl")\")" \
  '[[ "$(last_type "$C.stream.jsonl")" == "result" ]]'
check "2e. sidecar total_cost_usd is still non-null (got $(jq -r ".total_cost_usd" "$C.usage.json" 2>/dev/null))" \
  '[[ "$(jq -r ".total_cost_usd // \"null\"" "$C.usage.json" 2>/dev/null)" == "'"$STUB_COST"'" ]]'
check "2f. progress log is not 0 bytes and has every line (want $PROGRESS_LINES, got $(lines_of "$C.progress.md"))" \
  '[[ -s "$C.progress.md" ]] && [[ "$(lines_of "$C.progress.md")" == "'"$PROGRESS_LINES"'" ]]'
check "2g. no capture warning for a run that did produce a result event" \
  '! grep -q "no result event" "$TMP/err-2.txt"'

# ── 3: a consumer that closes mid-stream ─────────────────────────────────────
# Phase 2 kills the consumer before the capture starts; this one kills it while the
# capture is running, which is the case the middle-`tee` pipeline truncated in place.
reset_feature
( cd "$AT" && ./run-plans.sh --self "$SLUG" 2>"$TMP/err-3.txt" ) | head -"$MIDSTREAM_CONSUMER_LINES" > /dev/null
rc=${PIPESTATUS[0]}
C="$F/auto/complete/$PLAN"
check "3a. a mid-stream close does not fail the plan (exit 0, got $rc)" '[[ $rc -eq 0 ]]'
check "3b. stream has every line (want $STREAM_LINES, got $(lines_of "$C.stream.jsonl"))" \
  '[[ "$(lines_of "$C.stream.jsonl")" == "'"$STREAM_LINES"'" ]]'
check "3c. stream ends with the result event (got \"$(last_type "$C.stream.jsonl")\")" \
  '[[ "$(last_type "$C.stream.jsonl")" == "result" ]]'
check "3d. progress log has every line (want $PROGRESS_LINES, got $(lines_of "$C.progress.md"))" \
  '[[ "$(lines_of "$C.progress.md")" == "'"$PROGRESS_LINES"'" ]]'
check "3e. sidecar total_cost_usd is still $STUB_COST" \
  '[[ "$(jq -r ".total_cost_usd // \"null\"" "$C.usage.json" 2>/dev/null)" == "'"$STUB_COST"'" ]]'

# ── 4: exit 0 with no result event is loud ───────────────────────────────────
# The one combination that is never normal. It is still filed by its exit code — a plan
# that finished its work must not be re-run on the strength of a missing event — but it
# says so, names the stream, and the stream stays on disk.
reset_feature
( cd "$AT" && CLAUDE_STUB_MODE=no-result ./run-plans.sh --self "$SLUG" \
    > "$TMP/out-4.txt" 2>"$TMP/err-4.txt" ); rc=$?
C="$F/auto/complete/$PLAN"
BOTH_4="$TMP/both-4.txt"; cat "$TMP/out-4.txt" "$TMP/err-4.txt" > "$BOTH_4"
check "4a. a stub with no result event still exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "4b. plan filed by its exit code, to auto/complete/" '[[ -f "$C.md" ]]'
check "4c. the warning names the plan" 'grep -q "$PLAN" "$BOTH_4" && grep -q "no result event" "$BOTH_4"'
check "4d. the warning names the stream file" 'grep -q "$PLAN.stream.jsonl" "$BOTH_4"'
check "4e. the stream file survives, with everything claude wrote (want $NO_RESULT_STREAM_LINES, got $(lines_of "$C.stream.jsonl"))" \
  '[[ "$(lines_of "$C.stream.jsonl")" == "'"$NO_RESULT_STREAM_LINES"'" ]]'
check "4f. the sidecar records the missing cost as null, not as zero" \
  '[[ "$(jq -r ".total_cost_usd" "$C.usage.json" 2>/dev/null)" == "null" ]]'

# ── 5: the usage-limit routing is unchanged ──────────────────────────────────
# stream_shows_usage_limit reads the final result event out of the captured file. It has
# to keep working through the new capture, and it has to keep working when the consumer
# is gone — that combination is how the nine lost reviews were launched.
reset_feature
( cd "$AT" && CLAUDE_STUB_MODE=usage-limit ./run-plans.sh --self "$SLUG" \
    > "$TMP/out-5.txt" 2>"$TMP/err-5.txt" ); rc=$?
BOTH_5="$TMP/both-5.txt"; cat "$TMP/out-5.txt" "$TMP/err-5.txt" > "$BOTH_5"
check "5a. a usage-limit stop exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "5b. the plan is left in inprogress/ for the next run" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'
check "5c. the stop reason names the usage limit" 'grep -q "usage limit reached" "$BOTH_5"'

reset_feature
( cd "$AT" && CLAUDE_STUB_MODE=usage-limit ./run-plans.sh --self "$SLUG" 2>"$TMP/err-5b.txt" ) \
  | head -"$CLOSED_CONSUMER_LINES" > /dev/null
rc=${PIPESTATUS[0]}
check "5d. it is still routed as a usage limit with the consumer gone (exit 1, got $rc)" '[[ $rc -eq 1 ]]'
check "5e. and the plan is still left in inprogress/" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'

# ── 6: a non-JSON line in the stream is not a truncated capture ──────────────
# claude's stderr is merged into the stream (2>&1), so one runtime warning or crash
# trace puts a line in it that is not JSON. The sidecar has always skipped such lines;
# stream_has_result used to fail over them, which made finalize_plan announce a lost
# capture on a stream that was complete and priced — a false alarm on the exact signal
# this feature exists to make trustworthy. Both now read the file the same way.
reset_feature
( CLAUDE_STUB_MODE=malformed "$AT/run-plans.sh" --self "$SLUG" \
    > "$TMP/out-6.txt" 2>"$TMP/err-6.txt" ); rc=$?
C="$F/auto/complete/$PLAN"
BOTH_6="$TMP/both-6.txt"; cat "$TMP/out-6.txt" "$TMP/err-6.txt" > "$BOTH_6"
check "6a. a stream with a malformed line still exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "6b. the malformed line really is in the captured stream" \
  'grep -q "^warning: a non-JSON line" "$C.stream.jsonl"'
check "6c. no truncation warning for a stream that has its result event" \
  '! grep -q "no result event" "$BOTH_6"'
check "6d. the sidecar is priced (got $(jq -r ".total_cost_usd" "$C.usage.json" 2>/dev/null))" \
  '[[ "$(jq -r ".total_cost_usd" "$C.usage.json" 2>/dev/null)" == "'"$STUB_COST"'" ]]'
check "6e. the sidecar and the warning agree: result_event is seen" \
  '[[ "$(jq -r ".result_event" "$C.usage.json" 2>/dev/null)" == "seen" ]]'

# ── 7: a capture directory that cannot be created fails the plan ─────────────
# The marker follow_stream waits for lives in a mktemp -d. Unchecked, an unwritable
# $TMPDIR put it at /claude-exited, where `: >` fails silently and the follower waited
# for a file that would never appear — with no timeout anywhere in the path, so the
# runner sat there forever with the plan never finalized. The watchdog is the assertion:
# 137 here means it hung and was killed, not that it failed.
reset_feature
rm -rf "$NO_SUCH_TMP"
start_runner "$NO_SUCH_TMP" normal "$TMP/out-7.txt" "$TMP/err-7.txt"
reap_runner; rc="$runner_rc"
BOTH_7="$TMP/both-7.txt"; cat "$TMP/out-7.txt" "$TMP/err-7.txt" > "$BOTH_7"
check "7a. an uncreatable capture directory returns instead of hanging (got $rc)" \
  '[[ "$rc" != "137" ]]'
check "7b. and fails the plan, non-zero (got $rc)" '[[ "$rc" != "0" ]]'
check "7c. the plan is routed to auto/failed/" '[[ -f "$F/auto/failed/$PLAN.md" ]]'
check "7d. the message names the directory it could not create one under" \
  'grep -q "capture directory" "$BOTH_7" && grep -q "$NO_SUCH_TMP" "$BOTH_7"'
check "7e. the progress log carries the reason too" \
  '[[ -f "$F/auto/failed/$PLAN.progress.md" ]] && grep -q "capture directory" "$F/auto/failed/$PLAN.progress.md"'
check "7f. claude was never started, so no stream was captured" \
  '[[ ! -s "$F/auto/failed/$PLAN.stream.jsonl" ]]'

# ── 8: a signal to the runner alone ──────────────────────────────────────────
# `claude` is a background job now, and a background job in a non-interactive shell has
# SIGINT set to ignore — it no longer dies with the process group, so stop_capture has to
# kill it by pid. If that ever regresses, a Ctrl-C leaves claude running as an orphan,
# spending budget and writing into a stream file the runner has already moved, while
# every other check in this repo stays green. Nothing else in self/tests/ sends a signal.
reset_feature
rm -rf "${CAPTURE_TMP:?}"/*
start_runner "$CAPTURE_TMP" slow "$TMP/out-8.txt" "$TMP/err-8.txt"
check "8a. the capture reached the stream file before the signal" \
  'poll_until '"'"'[[ -s "$F/auto/inprogress/$PLAN.stream.jsonl" ]]'"'"''
# Non-vacuity for 8f/9f below: the capture directory really is under $TMPDIR while the
# run is in flight, so counting zero afterwards means it was removed rather than that it
# was never there to see.
check "8b. the capture directory is under \$TMPDIR while the run is in flight (got $(capture_dirs_left))" \
  '[[ "$(capture_dirs_left)" == "1" ]]'
kill -TERM "$runner_pid" 2>/dev/null
reap_runner; rc="$runner_rc"
check "8c. the runner exits through its interrupt handler (130, got $rc)" '[[ "$rc" == "130" ]]'
check "8d. the plan is left in inprogress/ for the next run" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'
check "8e. the stream file holds what was captured up to the kill" \
  '[[ -s "$F/auto/inprogress/$PLAN.stream.jsonl" ]]'
check "8f. no orphan claude, follower or tail is left behind" 'poll_until sandbox_procs_gone $ORPHAN_POLL_TRIES'
check "8g. the capture directory is gone (got $(capture_dirs_left))" \
  'poll_until '"'"'[[ "$(capture_dirs_left)" == "0" ]]'"'"''

# ── 9: a signal to the whole process group ───────────────────────────────────
# What a supervisor tearing down a batch sends. The follower does NOT survive this one —
# it dies alongside the runner — so its own `rm -rf` never runs and the capture directory
# is on_interrupt's to remove. Phase 8 cannot catch that: there the follower outlives the
# runner and tidies up on its way out. `set -m` is what gives the runner a process group
# of its own to signal; without it the kill would take this script with it.
reset_feature
rm -rf "${CAPTURE_TMP:?}"/*
set -m
start_runner "$CAPTURE_TMP" slow "$TMP/out-9.txt" "$TMP/err-9.txt"
set +m
check "9a. the capture reached the stream file before the signal" \
  'poll_until '"'"'[[ -s "$F/auto/inprogress/$PLAN.stream.jsonl" ]]'"'"''
check "9b. the capture directory is under \$TMPDIR while the run is in flight (got $(capture_dirs_left))" \
  '[[ "$(capture_dirs_left)" == "1" ]]'
kill -TERM -"$runner_pid" 2>/dev/null
reap_runner; rc="$runner_rc"
check "9c. the runner still exits through its interrupt handler (130, got $rc)" '[[ "$rc" == "130" ]]'
check "9d. the plan is left in inprogress/" '[[ -f "$F/auto/inprogress/$PLAN.md" ]]'
check "9e. the stream file holds what was captured up to the kill" \
  '[[ -s "$F/auto/inprogress/$PLAN.stream.jsonl" ]]'
check "9f. nothing from the sandbox is still running" 'poll_until sandbox_procs_gone $ORPHAN_POLL_TRIES'
check "9g. the capture directory is gone, removed by the interrupt handler (got $(capture_dirs_left))" \
  '[[ "$(capture_dirs_left)" == "0" ]]'

if (( fails > 0 )); then echo "stream-capture: $fails assertion(s) FAILED"; exit 1; fi
echo "stream-capture: all assertions passed"
