Verdict: clean

# Review: runner-write-allows (round 2)

## What the batch was supposed to do

Close the silent write approvals in `hooks/allow-repo-commands.sh` that the #147 audit found
(F1–F7, F9, F10). The fix replaces the runner denylist with exact-word allowlists for ruff,
mypy and pytest, and pins the harness's Python entry points to `<root>/analysis/` and
`<root>/agentTooling/analysis/` with no symlinks allowed. `<root>/analysis/report.py` now
requires `--self`. Round 2 then had to close the round-1 audit's blocking finding, B1:
`pytest -W ignore::<module>.X` imports that module. It also had to file the three
non-blocking findings as backlog follow-ups.

## Does it do it

Yes.

- **B1.** `-W` and `--pythonwarnings` are in none of pytest's lists (`RUNNER_BARE_FLAGS`,
  `RUNNER_VALUE_FLAGS`, `RUNNER_CONFIG_FLAGS`). The short-flag patterns
  (`-[qvxsl]+`, `-r[fEsxXpPaAwN]+`) can't match a `-W`. The `python -m pytest` form goes
  through the same `runner_form_allowed`, and a `python3 -W … -m pytest` form matches no
  runner prefix. An env prefix such as `PYTHONWARNINGS=… pytest` is refused at command
  position (`subcommand_allowed`).
- **Tests.** `RUNNER_WRITE_PROMPT` checks that `-W` prompts in both the bare and
  `python3 -m` spellings, and that `--pythonwarnings` prompts. No row anywhere expects a
  `-W` form to be approved.
- **Docs.** `hooks/README.md` has a B1 row in the runner-write audit table. Its "Never
  listed" list names `-W`/`--pythonwarnings`, and the pytest allowlist no longer includes
  them. The `--config` paragraph, the `runner_config_file_ok` docstring and the
  entry-points section ("Two cases stay approved…") describe the three accepted limits
  accurately. None of them claims more than the code does.
- **Follow-ups.** `self/BACKLOG.md` has all three items, each with its assertion.
- **Round-1 contracts.**
  - Every form the diff approves was already approved on base, so nothing that prompted
    before is now approved.
  - The plain read forms are still approved (`RUNNER_READ_ALLOW`).
  - CONVENTIONS.md's "approved silently" paragraph is still true.
  - The new values are named constants.
- **Gate.** `self/gate-report.txt` ends "all checks passed" and lists no skipped checks.

## Fixed in this pass

- `self/BACKLOG.md`, the `--config`/`--config-file` item: added that a planted mypy config
  with `plugins = <module>` imports that module. That is the same import-time execution as
  B1, not just a write, which matters when the item is prioritised. The limit itself is
  unchanged: it is still the accepted "a planted file needs a prior write" case.

## Escalated to the next round

None.
