# 01 — review: session-start-precision

Independent review, written before the build from GitHub issue #82 and the coordinator's
rulings below — never from the implementer's report. Read the code. "No findings" is a
legitimate verdict. Fix local drift in this pass; anything structural is an escalation.
Begin your report with the `Verdict:` line the prompt asks for.

## What the feature was supposed to do

**1. Issue #82.** `analysis/manifest.py [--self] <slug> session-start <id>` printed a
session's first transcript instant floored to the whole second
(`self/features/execution-profiles/NOTES.md` ruling 18), while `set-window-from <instant>
--session <id>` refuses an instant earlier than that session's first line. Transcript
instants carry milliseconds, so `set-window-from "$(manifest.py <slug> session-start <id>)"
--session <id>` was refused for nearly every session — and that is the remedy the start's
own `warn` line names.

**The coordinator's ruling:** `session-start` keeps sub-second precision — it prints the
first instant **truncated (never rounded) to the millisecond**, UTC, with a `Z`, the
precision transcripts carry — so its output is never later than the session's first line
and `set-window-from` accepts it exactly. `set-window-from`'s refusal is NOT loosened: no
tolerance window. The ruling is recorded in this feature's `NOTES.md` and supersedes
execution-profiles ruling 18's "floored to the second".

**2. A base defect the start hit.** On `main`, `self/tests/self-settings.sh` B2–B6 and
E1–E4 fail whenever `GATE_RESUME=1` is in the environment — which `feature-start.sh` and
the runners set — because the nested `self/gate.sh` those assertions run reuses a recorded
pass of "permission policy wired into .claude/settings.json", whose input (the ignored,
generated `.claude/settings.json`) the gate's tree sha leaves out. So under resume a
deleted or drifted settings file passed. The fix: `self/gate.sh` gains `record_fresh`, a
blocking check that is never reused and never recorded, and the settings check uses it.
Only `self/gate.sh`; the template gate has no such check and is unchanged.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`analysis/manifest.py`, `feature-start.sh` (comments at most), `self/gate.sh`,
`self/tests/cloud-start.sh`, `self/tests/self-settings.sh` (or `gate-resume.sh`),
READMEs that describe `session-start` or the gate's resume (`analysis/README.md`,
`self/README.md`, `self/tests/README.md`, `LIFECYCLE.md` if it says "floored"), and this
feature's directory. Nothing in other features' directories.

## Contracts to hold it to

- **`session-start` never prints an instant later than the session's first line**, and
  for a millisecond transcript prints it exactly. A first instant with no fraction still
  prints something `to_instant` parses and that compares equal.
- **`set-window-from` given `session-start`'s output succeeds** for a session whose first
  line has a fractional second, and **the capture still selects that session by branch**
  (`self/tests/cloud-start.sh` — the new assertion; A2 now expects the exact instant, not
  the floor). Check the assertion would have failed on `main`.
- **The start's direct write of `from` still works**: `feature-start.sh` stamps the
  coordinator's `from` from `session-start`; every reader of a fence `from`
  (`capture_planning.py`'s window test and empty-window check, `manifest.py
  set-window-to`'s `from` comparison, `check-plans.sh` check 7, `report.py`) handles a
  fractional bound — compared as instants, never as strings.
- **`set-window-from`'s three refusals are unchanged**, and no tolerance was added.
- **`record_fresh`**: a blocking failure still fails the verdict; it writes no
  `gate-state` file and is never reused; a test shows a missing/drifted settings file
  fails the self gate under `GATE_RESUME=1`. No other check moved to it without reason.
- Named constants for any new literal (`CONVENTIONS.md`); READMEs updated for every
  folder touched; `self/tests/README.md` rows for changed tests.
- **No existing assertion weakened** — A2's change is the ruling, and must say so.
- Report the touched tests run individually; the coordinator runs the full gate.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what you fixed, what you escalated, and the files this pass touched.
