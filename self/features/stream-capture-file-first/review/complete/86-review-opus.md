# 86 — review: stream-capture-file-first

Independent review of one direct-built feature's diff. Written before the build, from
the spec that produced it; nothing here comes from the builder's report.
`run-review.sh` refuses a brief still carrying the stub marker, so this file being
written is itself the gate on the build having started from a spec.

## What the feature was supposed to do

`self/features/stream-capture-file-first/README.md` — the summary paragraph, "The
defect", "The rulings" and "Deliberately excluded". Read all four before the diff and
hold the diff to them ruling by ruling. The rulings are not reopened: a diff that picked
a different design for one of them is a finding, however good that design.

In one sentence: `plan-runner-lib.sh::run_plan` captured `claude -p`'s event stream with
a `tee` in the *middle* of a pipeline, so a consumer that closed the runner's stdout
early killed the capture — leaving a 689-byte `.stream.jsonl`, a 0-byte `.progress.md`
and a `total_cost_usd: null` sidecar on nine plans that had in fact run to completion —
and the capture must now be immune to whatever happens downstream of it.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`plan-runner-lib.sh` (the capture in `run_plan` and the comment block above it, a
follower helper, `finalize_plan`'s new warning, the interrupt path), `RUNNER.md`
(wherever it describes the capture pipeline and the stream/progress files),
`self/PROJECT_FACTS.md` if it states anything about how the stream is captured, a new
`self/tests/stream-capture.sh` (or a name in the repo's style), `self/gate.sh` (two
registrations), `self/tests/README.md` (the new test's row), possibly `self/BACKLOG.md`,
and this feature's own directory — `README.md`, `NOTES.md`, `CHECKPOINT.md`,
`timing.jsonl`, this brief — which is the record, not the feature.

**Use the three dots.** This branch is stacked off `cb892e2` and `main` has moved since:
the sibling feature `recover-cost-at-close` merged as PR #31 while this was being built.
`git diff main..HEAD` (two dots) therefore renders that whole feature as deletions and is
not this feature's diff. `git diff main...HEAD` — against the merge base — is, and it
should come to thirteen files.

`write_usage_sidecar`, `feature-close.sh`, `analysis/recover_attempts.py` and
`analysis/report.py` should not appear in that diff at all: they belong to the sibling,
as does its new sidecar field `result_event`. Any hunk touching them, or any assertion in
the new test that depends on that field, is a finding on its own.

## Contracts to hold it to

- **The stream file is complete no matter what happens downstream of it.** Read the
  capture in `run_plan` and answer one question: can any process that consumes the
  runner's stdout stop `$stream_file` from growing? If `claude`'s stdout is redirected
  to the file directly, the answer is structural and the check is that nothing was left
  writing the file through a pipe. If instead the pipeline was kept with SIGPIPE ignored
  (the fallback design), the answer depends on `tee` continuing after a write error, and
  `NOTES.md` must say why the file-first design could not be made deterministic on bash
  3.2 + macOS. Either way: no sentinel or marker line is ever written into
  `$stream_file` — `write_usage_sidecar` and `stream_shows_usage_limit` parse it, and a
  stray line is a parse error or a wrong figure.
- **The drain is deterministic, not timed.** Every line `claude` wrote must reach the
  progress-log FIFO before `run_plan` returns. Find the mechanism that says "the
  producer has finished" and check it cannot race: a follower that stops when a *sleep*
  expires, or that samples "is the process still alive" and then breaks without a final
  read to end-of-file, is a finding. macOS `tail` polls and has no `--pid`; a
  `tail -f` killed after a fixed wait is exactly the design ruling 1 forbids. Check the
  order of operations at the end: whatever signals "done" must be raised only *after*
  `claude` has exited, and the follower must do at least one more full read afterwards.
- **The progress log is complete too.** `log_stream_events` receives every event, closed
  consumer or not. `.progress.md` for a run that edited files can never again be 0 bytes.
  Check the display and the FIFO are not in series in a way that lets the display's death
  stop the FIFO.
- **The exit code is still `claude`'s.** `run_plan` returns `claude`'s status, not a
  follower's, not a `tee`'s, not `display_stream`'s. If `PIPESTATUS[0]` is gone, whatever
  replaced it must be exact — a `wait` on the right pid, and the status captured on the
  very next line. Check the usage-limit (`rc == 2`) and budget (`rc == 3`) branches still
  see the same stream and return the same codes.
- **A closed consumer does not fail the plan.** With the runner's stdout piped to a
  consumer that exits after two lines, the plan must still be filed by its exit code —
  which means the runner's *own* writes to stdout must not kill it either. Check how that
  was done and that it is scoped and commented, not an accident.
- **The FIFO/`wait "$log_pid"` race the existing comment guards stays closed.** The
  reason the log is fed through a named FIFO with a tracked PID rather than `tee >(...)`
  is that bash does not wait for a process substitution and `finalize_plan` exits
  immediately on the failure path. Check no process substitution appeared anywhere in the
  new capture, that the logger is still waited on, and that the wait happens after the
  last writer to the FIFO has closed it.
- **A silent capture failure is loud.** In `finalize_plan`, `rc == 0` with no
  `type == "result"` event in the stream — the one combination that is never normal —
  prints a warning naming the plan and the stream file, and the stream file stays on
  disk. Check the message names both, that it fires only for that combination (a
  non-zero rc already has its own reason line; a stream with a result event is silent),
  and that nothing was added that deletes the stream.
- **The tests were RED first, and are red without the fix.** A new script in
  `self/tests/`, in the style of its neighbours: throwaway `mktemp -d` checkout, stub
  `claude`, no model, no network, driving a real runner invocation rather than calling
  `run_plan` directly. Its stub `claude` must **ignore SIGPIPE** and emit thousands of
  events — a stub that exits on its own after a handful cannot distinguish the fix from
  the defect. Assert it covers all four cases: (a) stdout piped to a consumer that closes
  after two lines — the stream ends with the `result` event and has the full line count,
  the sidecar's `total_cost_usd` is non-null, `.progress.md` holds one line per mutating
  `tool_use`, the plan is in `complete/`; (b) stdout to a file — identical results;
  (c) a stub emitting no `result` event and exiting 0 — filed by exit code, ruling 3's
  warning printed naming the plan, stream file still there; (d) the existing usage-limit
  routing still works. Check (a) would really go red on `main` and that `NOTES.md`
  records the pre-fix failure lines verbatim.
- **The existing runner tests still pass unchanged.** `self/tests/level-sentinel.sh`,
  `tiered-gates.sh` and `feature-lifecycle.sh` drive the pipeline this feature rewrites.
  A change to their assertions or to their stub `claude` to accommodate the new capture
  is a finding unless `NOTES.md` justifies it: they are the regression surface.
- **`./self/gate.sh` is green and the new test is registered twice** — in
  `shell_scripts` (for `bash -n`) and as its own `record` line. The gate does not glob; a
  test added to only one list runs half. `self/tests/README.md` gains a row in the shape
  of its neighbours, naming what the script depends on that its imports do not show.
- **bash 3.2 and the repo's shell rules** (`self/PROJECT_FACTS.md`): no associative
  arrays, no `${var^^}`, `${a[@]+"${a[@]}"}` for a possibly-empty array under `set -u`;
  `set -uo pipefail` with no `set -e`, so any status the script branches on is checked
  with `if`, never left to `-e`. macOS `tail`/`head`/`sleep`, not GNU: check every flag
  used exists in the BSD versions, and that a fractional `sleep` is the only GNU-ish
  thing relied on (it is in BSD `sleep`).
- **Named constants** (`CONVENTIONS.md` → "Named constants"): a poll interval, a marker
  path, a warning threshold — each a named constant at the top of its file, not an inline
  literal.
- **No new artifact appears in a consuming repo's working tree.** Every file here ships
  to every consuming repo on its next `subtree pull`. If the capture writes a control
  file beside the plan, `templates/plans/.gitignore` and this repo's `.gitignore` must
  both cover it, or `git subtree` breaks on a dirty tree the next time anyone pushes. A
  control file in `$TMPDIR` needs neither, but must be cleaned up on the interrupt path
  as well as the normal one — check `on_interrupt`.
- **`self/BACKLOG.md` and the sibling's entry.** This feature fixes the defect, so it
  adds no backlog entry for it. `NOTES.md` must record that the sibling branch
  `recover-cost-at-close` carries an entry beginning "A `claude -p` run can exit 0,
  finish its work and open its PR while its captured … stream carries no `result` event"
  which this feature closes, so whoever merges last deletes it. Anything found and *not*
  fixed goes into `self/BACKLOG.md` in that file's shape.
- **Every touched folder's README is current** (`CONVENTIONS.md` → "Keeping READMEs up to
  date"): `self/tests/README.md` carries the new row, `self/features/README.md` carries
  this feature's entry, and `RUNNER.md`'s description of the capture and of the four
  sidecar files matches the code.

## Verdict

"No findings" is a legitimate verdict. Findings are phrased as assertions — what must
hold, and what in the diff does not — with the file and line. Local findings (a stale
README row, a missing `shell_scripts` entry, a test that passes vacuously, a comment
still describing the old pipeline) are fixed here and listed as fixed. Anything
structural — a drain that can race, a capture still reachable from the consumer, an exit
code that is no longer `claude`'s, an edit to one of the sibling feature's files — is a
finding for the human, not a rework done here.
