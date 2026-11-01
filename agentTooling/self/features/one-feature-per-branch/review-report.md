Verdict: clean

# one-feature-per-branch — review, round 3

## What this round was supposed to do

Round 2 escalated one finding, and it was test-only: no test covered looking for a
session's subagents beside every copy of its transcript. A session that exists in two
project directories might have its subagents only beside the copy that was not walked. This
round adds cases 19j and 19k to `self/tests/capture-guard.sh` and extends the phase-19
entry in `self/tests/README.md`. No production code was meant to change.

## Does it do it

Yes. `git show 0c96cfe` changes only the test, its README line, the feature README and the
queued review plan. Nothing under `analysis/` changed.

- **The fixture.** The short copy of `SESSION_C` is in the walked directory and the long
  copy is in `$OTHER_PROJECT`, which is not walked. The new subagent `AGENT_C`, ending at
  10:45, is filed under `$OTHER_PROJECT/$SESSION_C/subagents/` only. `write_manifest`
  resets the fence, so nothing pins the subagent and `to` is null.
- **19j would catch a regression.** `last_branch_instant` looks for subagents in
  `copy_dirs` (every copy's directory plus `transcript_dir`, `capture_planning.py:2607`). If
  it went back to `transcript_dir` alone, it would not find the subagent and would print
  `10:30:01Z` instead of `10:45:01Z`.
- **19k would catch a regression.** If the capture's walk (`capture_planning.py:3434`/`3519`)
  regressed the same way, `subagents[]` would be empty and the total would equal
  `long_total`. Either half of the check fails. Nothing pins `AGENT_C`, so the
  pinned-subagent fallback cannot find it and hide the regression.
- **The gate is green.** It runs 19j (`got 2026-07-01T10:45:01Z`) and 19k, and lists no
  failed or SKIPPED checks.
- **The README.** The phase-19 entry in `self/tests/README.md` now describes 19j–k
  accurately.

## Fixed in this pass

- `self/tests/capture-guard.sh`, header comment for phase 19: re-wrapped a line that ran
  well past the file's comment width. The wording is unchanged.

## Escalated to the next round

None.
