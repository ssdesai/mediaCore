# 02 — review: runner-write-allows (round 2)

Re-review after the round-1 security audit escalated one blocking finding. Review the
**whole diff against the base**, not only the round-2 commit. Hold it to the round-1 brief,
`review/complete/01-review-opus.md` (what the feature was supposed to do, and its
contracts), and to the rework brief below. "No findings" is a legitimate verdict. Fix local
findings in the pass. Escalate structural ones.

## What the feature was supposed to do

Everything in the round-1 brief, plus the rework in
`escalations/01-audit-opus.md`:

- **B1 (blocking).** `pytest -W <action>::<module>.<name>` imports `<module>`, and
  importing it runs that module's code. `pytest -W 'ignore::antigravity.X'` ran a browser.
  `-W` is removed from the pytest allowlist, so every `-W` prompts, in both the `pytest`
  and the `python3 -m pytest` spellings.
- **The three non-blocking findings stay unfixed.** They are pre-existing accepted-limit
  cases, and each is filed as a follow-up in `self/BACKLOG.md`:
  - `--config`/`--config-file` accepts any in-root file;
  - both pinned `analysis/` directories are accepted in every repo;
  - `gate.sh` and `check-plans.sh` are still matched by basename.

  The docs (`hooks/README.md`, the `runner_config_file_ok` docstring) must not claim more
  than the code does about these.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The round-1 contracts all still hold.** No input that was ask or deny on base becomes
  allow. The plain read forms stay approved. Every F-case write form prompts.
- **Tests.** `self/tests/allow-repo-commands.sh` asserts that `pytest -W …` prompts in
  both spellings, and no row anywhere still expects a `-W` form to approve.
- **Docs.** The `hooks/README.md` runner-write audit table has a B1 row, and the
  documented pytest allowlist no longer lists `-W`.
- **Follow-ups.** `self/BACKLOG.md` carries the three non-blocking follow-ups.
- **Gate.** `./self/gate.sh` is green.

## Verdict
