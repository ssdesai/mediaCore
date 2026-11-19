# 01 — review: runner-write-allows

Review the diff below against the spec in this brief, which was written before the build.
"No findings" is a legitimate verdict. Fix local findings in the pass. Escalate
structural ones.

## What the feature was supposed to do

Close the silent allows of writes in `hooks/allow-repo-commands.sh` that an audit of #147
found. Each must now **prompt** (ask) or be a rewrite deny, never an approval.

- **F1.** `ruff check --config 'fix = true' f.py`, `--config fix=true`, and
  `ruff --config 'fix = true' check …`. A `--config` value that is not an existing
  in-root regular file prompts.
- **F2.** `ruff check --add-noqa f.py`.
- **F3.** `mypy --python-executable <file>`, in both the space and the `=` forms.
- **F4.** These write output files:
  - ruff: `--output-file=X`, `--output-file X`, `-o X`, including with `--show-settings`;
  - mypy: `--junit-xml X` and every `--*-report DIR`.
- **F5.** mypy abbreviations of forbidden options (`--install-type`, `--install-typ`,
  `--inst`), and any `@file` argument, prompt.
- **F6.** These write files or upload results:
  - pytest's `--basetemp`, `--junitxml`/`--junit-xml`, `--log-file`, `--debug`,
    `--resultlog`, `--pastebin`, in both `=` and space forms, and their abbreviations;
  - `-o`/`--override-ini` (for example `cache_dir`, `log_file`, `junit_*`).
- **F7.** `python3 analysis/report.py <slug>` without `--self`, in the standalone
  checkout, writes outside the root. It prompts.
- **F9.** Only the real `analysis/report.py` and `agentTooling/analysis/report.py`
  paths approve. A planted or symlinked `x/report.py` prompts.
- **F10.** Correct the hooks/README.md text that said `-B` suppresses `py_compile`'s
  `.pyc`. It does not.

The same rules apply to the `python3 -m ruff|mypy|pytest` spellings.

The implementation the coordinator ruled on is in `../NOTES.md`:
- exact-word flag allowlists for each runner;
- pinned paths for the Python entry points;
- symlink refusal;
- `--self` required for `<root>/analysis/report.py`.

**These read forms must still approve silently:**
- `ruff check f.py`, `ruff format --check f.py`, `python -m ruff check src`;
- `mypy f.py`, `python3 -m mypy f.py`;
- `pytest -q tests/x.py`, `python -m pytest -q tests/x.py`;
- `python3 analysis/report.py --self <slug>`, plus the existing approved
  `capture_planning.py`/`manifest.py` shapes;
- `self/gate.sh` and `./check-plans.sh --self <slug>`.

**Excluded:**
- tool caches at their default places, which are a documented accepted limit;
- writes a repo's own config asks for;
- F12, which is recorded only;
- a full emulation of each tool's option grammar.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **No regression.** No input that was ask or deny on base becomes allow. Check every
  form the base approved that the diff now refuses, and confirm that each is one of the
  listed write forms or an unknown flag. Check every form the diff approves, and confirm
  the base approved it too.
- **Ground truth.** Each F-case was checked against the real tool in a throwaway copy,
  and each result is recorded in `NOTES.md` → Build log. Spot-check at least F1, F3, F6
  (`--basetemp`) and F7 yourself in a `mktemp -d` copy.
- **Tests.** `self/tests/allow-repo-commands.sh` has rows for every F-case (F1–F7, F9),
  showing that the write prompts. It also has rows showing that the plain read forms
  above still approve. The rows exist in both profiles where the file already tests both.
- **Docs.**
  - `hooks/README.md` documents the allowlists, the pinned entry paths and the new
    "Tool caches" accepted limit.
  - It adds an audit table for this feature (F1–F10, with the guard beside each), and
    fixes the F10 text.
  - The "Held to" table no longer says `report.py` takes "any arguments".
- **CONVENTIONS.md.** The "approved silently" paragraph is still true.
- **Constants.** Constants are named (the repo's Named-constants rule), and there are no
  new inline magic strings in logic.
- **Generated settings.** If `policy.py` changed, `.claude/settings.json` is regenerated
  (the gate checks byte for byte).
- **Gate.** `./self/gate.sh` is green.

## Verdict
