# Notes: stream-capture-file-first

Rulings made during the build, with a one-line rationale each; deviations from the
manifest and why; the RED lines the tests produced before the fix; open questions.
The manifest (`README.md`) holds the spec — this file holds what building it decided.

## The capture design: (a) file first

Ruling 1 offered file-first first and a SIGPIPE-immune pipeline as the fallback.
**File-first was taken**, and made deterministic. `claude -p` runs as a background job
with its stdout (and, as before, its stderr) redirected straight to `$stream_file`; a
`follow_stream` subshell tails that file, forwarding every byte to the progress FIFO on
fd 4 and, best-effort, to `display_stream` on its stdout.

Nothing downstream of `$stream_file` can now touch it: it is `claude`'s own stdout, held
open by `claude` alone. The follower is a reader. Killing the follower, the logger, the
display or the whole terminal cannot cost a byte of the record — which is the property
ruling 1 asks for, and is strictly stronger than what the fallback design would have
given (there, `tee` still writes the file through a pipe and is merely told not to die).

The fallback was not needed, but was measured before being set aside: BSD `tee` warns on
*every* write error rather than once, so a dead display would have produced one stderr
line per read chunk for the rest of the run, and `display_stream` would have needed a
wrapper of its own to be given the same immunity. File-first has neither problem.

## How the drain is made deterministic

The requirement is that every byte `claude` wrote reaches `log_stream_events` before
`run_plan` moves on, without depending on a sleep being long enough, and without writing
a sentinel into `$stream_file` (`write_usage_sidecar` and `stream_shows_usage_limit`
parse it).

The order in `run_plan` is what makes it exact:

1. `claude … > "$stream_file" 2>&1 &` — a background job, so `$!` is `claude`'s own pid.
2. `( follow_stream … 4> "$log_fifo" | display_stream ) &` — the follower starts polling.
3. `wait "$CAPTURE_CLAUDE_PID"` in the foreground. Its status *is* `run_plan`'s exit
   code — the exact replacement for the old `${PIPESTATUS[0]}`.
4. Only then is the exited-marker created. It cannot exist before `claude` has exited, so
   it is proof that the file is final.
5. `wait` on the follower, then on the logger.

`follow_stream` samples the marker **before** it measures the file, not after:

    was_done=$producer_done
    size=<bytes in the file>
    if (( size > off )); then forward; continue; fi
    (( was_done )) && break
    if [[ -e "$marker" ]]; then producer_done=1; continue; fi
    sleep "$FOLLOW_POLL_SECONDS"

so the loop can only exit through a size measurement taken *after* the marker was
already seen. A measurement that finds nothing new, taken after `claude` has exited, is
end-of-file for good. The poll interval sets latency, never correctness: a
`FOLLOW_POLL_SECONDS` of ten minutes would make the display sluggish and lose nothing.

**The follower forwards bytes, not lines.** It keeps a byte offset, measures the file
with `wc -c`, and forwards exactly `size - off` bytes with
`tail -c "+$((off+1))" | head -c "$n"` — both BSD-supported. Two reasons:

- `jq` on the far end parses a JSON *stream*; a chunk boundary mid-value is invisible to
  it, so there is nothing to gain from splitting on newlines.
- A bash `read` loop over a growing file is not reliable. Measured on this machine while
  prototyping: a `while IFS= read -r line <&3` follower whose *other* write in the same
  iteration failed with EPIPE (the display consumer having gone away) re-read one line
  and delivered it twice — reproducibly, at the same line, on every run. `read` buffers
  and `lseek`s back on a seekable fd, and that bookkeeping does not survive the
  combination. `tail -c`/`head -c` have no such state.

The marker lives in a `mktemp -d` directory, not beside the plan. A new artifact beside
the plan would need a pattern in this repo's `.gitignore` **and** in
`templates/plans/.gitignore` for every consuming repo, or `git subtree` would refuse the
next push over a dirty tree — and every file in this directory ships. `$TMPDIR` needs
neither. The follower's own subshell removes the directory on its way out; `stop_capture`
removes it too, because on a group SIGTERM the follower dies with the runner and never
gets there (see "Rework — 2026-09-06", ruling 4 — the first version of this paragraph
claimed the interrupt path leaked nothing, and the review was right that it did).

## SIGPIPE: a handler that redirects *and* flushes

Ruling 1 requires that "a closed consumer does not fail the plan". That is not only about
the capture: once the consumer is gone, the runner's own `echo`s to stdout take SIGPIPE
too, and the runner used to die on the third line of `run_plan` — `echo "    model: …"`,
before `claude` was even started. Phase 2 of the test pins it.

`run_all` installs

    trap 'exec >/dev/null; printf "\n"' PIPE

and every token of it is load-bearing.

**A handler, deliberately not `trap '' PIPE`.** Bash resets a *handled* signal to its
default in exec'd children while propagating an *ignored* one through `exec`, so ignoring
here would have silently changed the SIGPIPE disposition of `claude`, `jq`, `git`, `gh`
and — worst, because it ships — a consuming repo's own `plans/gate.sh` and `plans/pr.sh`,
where a `foo | head -1` would stop dying quietly and start printing write errors. Both
forms keep this shell alive; only one has a blast radius. Verified both ways.

**`exec >/dev/null`, so the runner stops writing to a pipe that is gone.** Without it
every subsequent line costs another SIGPIPE and another `write error` on stderr.

**`printf "\n"`, and this one cost an afternoon.** A bare handler is *not enough*, and
the way it fails is vicious. The bytes of the write that took EPIPE are still in bash's
stdio buffer, and bash never retries them; every fork from that point inherits the dirty
buffer and flushes it into *its own* stdout. For a command substitution that is the
substitution's pipe. With `trap ':' PIPE` and nothing else, the very first run of the new
capture produced:

- `size="$(wc -c < "$stream_file" …)"` → `"       0\n    model: haiku"`, so
  `$(( size ))` died with `haiku: unbound variable`;
- `"$(build_prompt …)"` → the prompt with `    model: haiku` appended twice, which is
  what `claude` was actually handed;
- `< <(list_plans "$INCOMPLETE_DIR")` → `=== Finished: 01-capture-haiku.md ===` as the
  next plan to run, then `=== Finished: === Finished: … === ===`, and so on — an infinite
  loop writing sidecars named after its own terminal output.

One *successful* write clears the buffer. A zero-byte one (`printf ''`) does not; nor
does an external command, nor a large write through a pipeline (that flushes the child's
copy, not the parent's). `exec >/dev/null` first, then one byte. Minimal repro kept in
`self/tests/stream-capture.sh` phase 2, which is red without it in a way that is
impossible to misread.

What is still visible is bash's own `write error: Broken pipe`, once, for the write that
first failed. That is left on purpose: it is the evidence that was missing for nine
features. No note is added beside it, because a note written to stderr would itself take
SIGPIPE when stderr is the same closed pipe, and re-enter the handler.

## `pipefail` made the display look dead

Found by the test, not by reading. `follow_stream` forwards a chunk with
`tail -c "+N" "$f" | head -c "$n"`, and `claude` keeps writing while that runs — so `tail`
usually has more to give than the `$n` bytes measured a moment earlier and is killed by
`head` closing the pipe. Under `set -o pipefail` that is a non-zero *pipeline* status on
a completely healthy display, and reading it as "the consumer is gone" latched
`display=0` a few hundred events in: terminal output stopped, silently, while the capture
ran on to the end. The fix is to branch on `${PIPESTATUS[1]}` — `head`'s own status,
which is non-zero only when *its* write failed. Assertion 1h now checks the display
rendered the first event, the last event and the closing line, so the same mistake cannot
pass again.

## Ruling 3: the warning

`stream_has_result` is a `jq -e` over the stream, matching `finalize_plan`'s existing
style. The warning fires on `rc == 0` **and** no `type == "result"` event, names the plan
and the stream's final path, and goes to stderr. It is computed before the plan is routed
and printed after, so it can name where the file actually ended up. A non-zero rc already
writes its own reason into the progress log and is left alone.

The stream file is kept exactly as before — `finalize_plan` already moves it to
`complete/` on success and `failed/` otherwise. Nothing deletes it; it is gitignored
(`self/**/*.stream.jsonl` here, `**/*.stream.jsonl` in a consuming repo's
`plans/.gitignore`), and the warning says so.

## Interrupts

`claude` used to be a foreground member of the runner's process group, so a Ctrl-C at the
terminal reached it directly. As a background job in a non-interactive shell it ignores
SIGINT (POSIX), so `on_interrupt` now kills it by pid before exiting. This is a small
behaviour change in the other direction too: a SIGTERM to the runner now also stops
`claude`, where before it left it running. That is the intent of the trap — "leave any
in-progress plan where it is; next run resumes it" — rather than a regression.

## RED before the fix

`bash self/tests/stream-capture.sh` against `main`'s `plan-runner-lib.sh`: **14 of 31
assertions failed.** The load-bearing lines, verbatim:

    FAIL  2a. a closed consumer does not fail the plan (exit 0, got 141)
    FAIL  2b. plan still filed to auto/complete/
    FAIL  2c. stream still has every line (want 3002, got -1)
    FAIL  2d. stream still ends with the result event (got "")
    FAIL  2e. sidecar total_cost_usd is still non-null (got )
    FAIL  2f. progress log is not 0 bytes and has every line (want 1500, got -1)
    FAIL  3a. a mid-stream close does not fail the plan (exit 0, got 141)
    FAIL  3b. stream has every line (want 3002, got 94)
    FAIL  3c. stream ends with the result event (got "assistant")
    FAIL  3d. progress log has every line (want 1500, got 39)
    FAIL  3e. sidecar total_cost_usd is still 1.25
    FAIL  4c. the warning names the plan
    FAIL  4d. the warning names the stream file
    FAIL  5d. it is still routed as a usage limit with the consumer gone (exit 1, got 141)

Phase 3 is the defect itself, reproduced in the harness: **94 of 3002 stream lines and 39
of 1500 progress lines, the capture stopping on an `assistant` event**, from a `claude`
that exited 0 having written all 3002. Phase 2 is its harsher form — the consumer closes
before `claude` starts, the runner dies of SIGPIPE at exit 141, and there is no stream at
all. Phase 1 (the healthy consumer) and phases 4a/4b/4e/4f and 5a/5b/5c/5e were green
before the fix and had to stay green after it.

## Gate

`./self/gate.sh` from the worktree, after the fix:

    === gate: done — all checks passed ===
    === gate: report at self/gate-report.txt ===

51 `ok`, 0 `FAIL`, 0 `SKIP`; one `skip  shellcheck (not installed)`, which is the gate's
own "not a dependency" line and never counted toward the verdict. That is 33 `bash -n`
parses, 14 behavioural self-tests (`stream capture self-test` among them),
`py_compile analysis`, and the two informational checks. **The twelve pre-existing
self-tests are unchanged and green** — `level-sentinel.sh`, `tiered-gates.sh` and
`feature-lifecycle.sh` all drive `run_plan` through the pipeline this feature rewrote,
and they were the regression surface: not one assertion or stub in them was touched.

`./check-plans.sh --self stream-capture-file-first`: 14 checks, 0 failed.

## The sibling's backlog entry — delete it on the merge

`recover-cost-at-close` carries a `self/BACKLOG.md` entry beginning "A `claude -p` run
can exit 0, finish its work and open its PR while its captured … stream carries no
`result` event". **This feature closes it**: ruling 1 removes the cause and ruling 3
makes the residue loud.

The brief said that entry was not on `main` yet. It is now — `main` moved during this
build (`d41a4a5`, PR #31, plus two `cost records` commits), so the sibling merged first
and **this branch is the one that merges second**. It is still branched off `cb892e2`,
deliberately: it depends on nothing the sibling added, and `git diff main...HEAD` is
exactly the thirteen files the review brief predicts. What that means for whoever merges:

- **Delete `self/BACKLOG.md`'s "A `claude -p` run can exit 0 …" entry** as part of the
  merge. It is closed, and this diff cannot delete a line it never had.
- Expect textual conflicts in the three append-only files both features touch —
  `self/gate.sh` (the sibling registers `self/tests/recover-at-close.sh`, this one
  registers `self/tests/stream-capture.sh`; both lists want both lines),
  `self/tests/README.md` and `self/features/README.md`. All three are "keep both".
- Nothing else in `self/BACKLOG.md` is touched here. Its first entry
  (`stream_shows_usage_limit`'s blindness to a hard-killed session, raised by
  `stale-failed-sidecars`) is a different defect — a `result` event never *emitted*, not
  one emitted and thrown away — and stays.
- The sidecar's `result_event: "seen"|"missing"` field is on `main` now. Nothing here
  reads or writes it; ruling 3's warning is derived from the stream file alone, so the
  two are independent.

## Found and left

One entry added to `self/BACKLOG.md`, in that file's shape:

1. **`run-batch.sh` still dies of SIGPIPE on a closed stdout.** It is a separate process
   that sources only `plan-runner-roots.sh`, so `run_all`'s trap does not reach it. The
   blast radius is now small — its child runner survives, finishes its plan and files it —
   but the rest of the batch (gate, verify, review, PR) is lost with no summary. The fix
   is the same three tokens; it is out of scope by ruling 1, which is about `run_plan`'s
   capture, and by the tests, which drive the runners directly.

A second entry was written and then removed by the review pass (`86-review-opus`): "a lost
capture is warned about on stderr and nowhere on disk". It was drafted before `main` moved
under this branch, and the merge closed it — `write_usage_sidecar` records
`result_event: "missing"` in the `.usage.json` for exactly this case, and
`analysis/report.py::unpriced_reason` already prints `no result event` for it as against
`killed` for a session cut off mid-turn, which is the distinction the entry asked for.

## Open questions

None that block, and no gap found in the rulings. Two things worth naming for the review:

- **The exit code is `wait`'s, and `wait` can be cut short by a trapped signal.** It is
  not reachable today: the only trapped-and-not-exiting signal is SIGPIPE, which this
  shell can only receive from its own write, and it does not write while waiting.
  INT/TERM both exit. Worth knowing before a third trap is added.
- **Terminal output after a closed consumer is gone for the rest of the run**, including
  for later plans in the same pass, because `exec >/dev/null` is not undone. That is the
  intent — there is no consumer to write to — but it means a run whose consumer died and
  was replaced (a `tee` restarted, say) stays silent.


## Rework — 2026-09-06

The review (PR #32, `self/review-report.md` → "Escalated to the next batch") escalated
four items. All four are closed here. Every fix is pinned by an assertion in
`self/tests/stream-capture.sh`, and every assertion was checked by mutation — reverting
the fix makes the named check fail.

**1. `mktemp -d` is checked, and the follower can no longer wait forever.**
`CAPTURE_TMPDIR="$(mktemp -d)"` was unchecked: an unwritable `$TMPDIR` or a full disk
made it empty, the marker became `/claude-exited`, `: >` failed, and the follower polled
for a file that would never appear while `wait "$follow_pid"` never returned. `claude`
finished, the stream landed on disk, and the plan was never finalized — silent, with no
timeout anywhere in the path. Two changes, because either alone leaves a hole:

- `run_plan` creates the directory *before* it starts anything, with an explicit
  template (`mktemp -d "$tmp_root/plan-capture.XXXXXX"`), and fails the plan on failure:
  `CAPTURE_SETUP_RC=70`, a message naming the directory it tried, the same reason
  appended to the progress log, and `finalize_plan` files it to `failed/`. The template
  is not cosmetic — a bare `mktemp -d` on macOS asks the OS for the per-user temp and
  **ignores `$TMPDIR`**, which makes the failure both untestable and unconfigurable.
- `follow_stream` takes `claude`'s pid and stops when either the marker exists *or* that
  pid is gone. A process that no longer exists has finished writing, so the
  snapshot-then-measure order still guarantees one final read; a missing marker now costs
  one poll interval instead of the run. Tests `7a`–`7f` (7a is the watchdog: a hang is
  reported as a failure rather than stalling the gate) and, for the pid condition, `8f`
  and `9f` — removing it leaves orphans in both signal phases.

**2. One definition of "has a result event".** `stream_has_result` ran
`jq -e 'select(.type == "result")'`, which exits non-zero on a *parse* error exactly as
it does on an absent event, while `write_usage_sidecar` derived the same fact from
`split("\n") | map(fromjson?)`, which drops unparseable lines. `claude`'s stderr is
merged into the stream, so one runtime warning split them: the sidecar recorded
`result_event: "seen"` and a real cost while `finalize_plan` announced a truncated
capture — a false alarm on the signal this feature exists to make trustworthy. The
derivation is now two constants at the top of `plan-runner-lib.sh`, `STREAM_EVENTS_JQ`
and `STREAM_LAST_RESULT_JQ`, spliced into both readers, so `$r` in the sidecar's program
and the predicate in `stream_has_result` are the same text. Tests `6a`–`6e`: a stream
with a non-JSON line before a valid result is priced, reports `result_event: "seen"`, and
draws no warning. `stream_shows_usage_limit` and `stream_shows_budget_exhausted` keep the
intolerant form deliberately — for them a parse error fails safe and silent, and widening
them is a routing change, not this rework.

**3. The interrupt path is tested.** Nothing in `self/tests/` sent a signal to a runner
before. Two phases now do. `8` sends SIGTERM to the runner alone — the case
`stop_capture` exists for, since a background job in a non-interactive shell ignores
SIGINT and no longer dies with the process group. `9` sends it to the whole group
(`set -m` gives the runner one of its own), which is what a supervisor tearing down a
batch does. Both assert: exit 130, plan left in `inprogress/`, the stream file holding
what was captured, no orphan `claude`/follower/`tail`, and no capture directory left.
The orphan budget (`ORPHAN_POLL_TRIES`, 2s) is deliberately far shorter than the `slow`
stub's remaining runtime — with a 10s budget an unkilled `claude` finished on its own and
the check passed whatever `stop_capture` did. With it tightened, removing the `kill` from
`stop_capture` fails `8f`, which is the assertion the review asked for.

**4. No capture-directory leak on a group SIGTERM.** `stop_capture` now removes the
directory itself after touching the marker. Safe under the follower because of ruling 1's
second stop condition: the follower does not need the marker to exist to notice `claude`
is gone. `9g` is the assertion, and `8b`/`9b` keep it honest by pinning that the
directory is really there under `$TMPDIR` while the run is in flight — without them a
`capture_dirs_left` of zero would pass vacuously.

Docs touched with the code: `RUNNER.md` → "Capturing the stream" (the pid stop condition,
the checked `mktemp`, the shared definition), and `self/tests/README.md`'s row for the
four new phases and the `$TMPDIR` dependency they rest on.

Gate after the rework: **all checks passed — 53 ok, 0 FAIL, 0 SKIP** (one `skip
shellcheck (not installed)`, the gate's own not-a-dependency line). 53 rather than the
51 recorded above because `main` merged in between and brought
`self/tests/recover-at-close.sh` with it. `self/tests/stream-capture.sh` is 56/56 — the build's 31 plus the
review's 25 — and takes ~4s.

Nothing from the review is left open, and no new backlog entry: the two entries added by
the build still stand as written.
