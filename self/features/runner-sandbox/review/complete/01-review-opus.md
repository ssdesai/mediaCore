# 01 — review: runner-sandbox

## What the feature was supposed to do

Close the `self/BACKLOG.md` entry "The verify and review passes run an unattended shell as
the user's account with no OS boundary." The generated `.claude/settings.json` (both
layouts, written by `hooks/wire-settings.py` from named constants) now carries Claude
Code's sandbox: `enabled`, a narrow write deny on `.git/hooks`, `.git/config` and
`.claude` (never a blanket deny that breaks `git commit`, `.venv/__pycache__` or
`node_modules/.vite`), a secrets-only read deny (`~/.ssh`, `~/.aws`, `~/.config/gh`, not
`~/`), and a network allowlist built from what one real batch needed. `sync-plans.sh`
carries it to consumers with stated merge semantics. Validated with one real batch or
review run under the sandbox, with the evidence in NOTES.md.

## The diff

The branch was cut from `self-settings-untracked`, which has since merged, and `main` has
been merged in; judge `git diff main...HEAD --stat`, then the full diff. Read `self/features/runner-sandbox/NOTES.md` for the implementer's
rulings, but judge against this brief, not against the notes.

## Contracts to hold it to

- Every sandbox value is a named constant in `wire-settings.py`; the block appears in
  both `--self` and consumer output and `hook-wiring.sh` asserts it.
- The write deny is exactly the narrow set; the read deny never covers `~/` or
  `~/.claude`; the allowlist contains at least `registry.npmjs.org`, `pypi.org`,
  `files.pythonhosted.org`, `api.anthropic.com`, `github.com`, `api.github.com`.
- The merge into a consumer's settings keeps consumer additions to the allowlists and
  lets the generator own the rest, and the test shows both.
- The validation run really happened under the generated sandbox: NOTES.md names the
  feature or review it ran, the exact failures it hit and what was added for each.
  A validation that was skipped or that ran without `sandbox.enabled` is an escalation.
- The negative assertion (`python3 -c` writing `.git/hooks/pre-commit` fails with
  `Operation not permitted`) is either tested live with the excerpt in NOTES.md, or the
  test asserts the generated deny and NOTES.md says why live was not possible.
- The key names match the installed Claude Code version, which NOTES.md records.
- `hooks/README.md`, `RUNNER.md` → "The executor's environment", and the root README rows
  are current; the gate is green; READMEs of every touched folder are current.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
