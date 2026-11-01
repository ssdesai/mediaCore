# Checkpoint: stream-capture-file-first

status: committed           planned | tests-written | implementing | gating | committed
updated: 2026-09-06T16:23:44Z
gate: all checks passed — 53 ok, 0 FAIL, 0 SKIP (shellcheck not installed)

## Slices
- [x] brief — `review/incomplete/86-review-opus.md`, manifest prose, `check-plans --self` clean
- [x] acceptance test — `self/tests/stream-capture.sh` (4 phases), registered in `self/gate.sh`; 14 of 31 RED
- [x] 1. file-first capture in `run_plan` — `claude > $stream_file 2>&1 &`, `follow_stream`
      feeding the FIFO (fd 4) and `display_stream`, drain on an exited-marker
- [x] 2. `trap 'exec >/dev/null; printf "\n"' PIPE` in `run_all` (the flush is not optional —
      NOTES.md); `on_interrupt` kills `claude` and releases the follower
- [x] 3. ruling 3 — `stream_has_result` + the `rc == 0`/no-result warning in `finalize_plan`
- [x] 4. docs — `RUNNER.md`, the comment block above the capture, `self/PROJECT_FACTS.md`
- [x] 5. READMEs — `self/tests/README.md` row, `self/features/README.md` entry
- [x] gate green, NOTES.md, stamp-timing, commit
- [x] rework — the review's four escalations, closed (NOTES.md → "Rework — 2026-09-06");
      self/tests/stream-capture.sh phases 6-9, 56 assertions

## Learned
- `self/gate.sh` does not glob: a new test needs BOTH a `shell_scripts` entry and a
  `record` line.
- `check-plans.sh --self <slug>` is 14 checks; check 13 wants the slug named in every
  queued plan file.
- A bash script that survives SIGPIPE must ALSO flush its stdio buffer, or every later
  `$(…)` and `<(…)` is poisoned with the text of the failed write. See NOTES.md.
- `set -o pipefail` makes `tail | head -c N` look failed whenever the file is still
  growing; branch on `${PIPESTATUS[1]}`, not on the pipeline.
- The full gate is ~50s; `bash self/tests/stream-capture.sh` alone is ~5s.

## Resume
- `cd /Users/sahildesai/dev/agentTooling-stream-capture-file-first`
- `bash self/tests/stream-capture.sh` — the acceptance test, standalone
- `./self/gate.sh` — the whole gate (~2 min)
