Verdict: clean

# Review: readme-index-check

## What the batch was supposed to do

Add a shared, read-only README-index checker that a consumer's gate can opt into. For
every tracked folder with a `README.md`, it reports each tracked file and direct subfolder
the README never names. The batch also had to wire the checker blocking into
`self/gate.sh`, with agentTooling's own READMEs made to pass, and document adoption for
consumers. That documentation covers the opt-in gate line, a note in `CONVENTIONS.md`,
and a docs-only description of the per-repo Rule 1 conformance test, which is not built
here.

## Does it do it

Yes. I checked the diff against `origin/main` (`check-readme-index.py`, `self/gate.sh`,
`self/readme-index-ignore`, `self/tests/readme-index.sh`, the README, `CONVENTIONS.md`
and `PROJECT_FACTS.md` edits) against each contract in the brief:

- **Read-only.** The checker runs only `git rev-parse` and `git ls-files -z`, opens files
  for reading only, and is invoked with `python3 -B`. Test I12 asserts `git status`,
  `.git/index` and `__pycache__` are all untouched.
- **A pull doesn't turn a consumer's gate red.** `templates/` is not touched. The seeded
  `plans/gate.sh` is repo-owned and never calls the checker. Adoption is a hand-added
  `--report-only` line, made blocking later. So a consumer with an unlisted file sees no
  change after `subtree pull` and `sync-plans.sh`. Leaving the template alone instead of
  adding a commented example is a reasonable call, and `README.md` gives the reason (it
  avoids a `template-version` bump and drift reports for a no-op).
- **Exit codes.** 0 when clean or under `--report-only`, 1 when entries are missing, 2 on
  an error: an unreadable ignore file, a bad pattern, a folder that isn't a checkout, or
  a missing `git`. A folder with no tracked `README.md` is skipped. Tests I1, I2, I7, I9
  and I10 cover these.
- **Tracked files and direct children only.** The file list comes from `git ls-files`,
  minus files deleted on disk. A subfolder is an entry by its bare name. Tests I3, I4,
  I5 and I13 cover this.
- **Recognition rule.** It is stated once, in the docstring, and matches the regex
  guards: case-sensitive, with name-character boundaries on both sides. A trailing
  `.` counts as a boundary only when no name character follows it. So `gate` does not
  match inside `integrate` or `gate.sh`, `self/gate.sh` does name `gate.sh`, and
  `tool.py.bak` does not name `tool.py`. Test I6 covers this.
- **Generated READMEs.** A README is treated as generated when a `_Generated from` line
  appears in its first 12 lines. It is then checked together with the file its header
  names as repo-owned, resolved against the README's own folder. Each of the three
  template stubs names that file in a form that resolves to `plans/PROJECT_FACTS.md`. A
  missing entry is reported against the owned file, so nobody is asked to edit a stub.
  Test I11 covers this.
- **Scope.** Nothing under `harness/`, `analysis/`, `.claude/` or `templates/` is
  changed. No model name appears in the new code or docs. The Rule 1 conformance test is
  described in docs only, citing musicMap's `types.conformance.ts`.
- **Gate.** The gate ends `all checks passed`. `readme-index: 20 READMEs checked, none
  missing`. The ignore list has three entries, each with a stated reason:
  - feature records, `self/features/*/`
  - orchestration records, `self/orchestrations/*/`
  - `templates/plans/TEMPLATE_VERSIONS`. Its folder's README is the stub that ships to
    every consumer, and `templates/README.md` documents the file instead.

  None of the three hides a real folder index. The batch added the README lines that
  were missing, such as `DESIGN-2026-09-17-close-and-review-rounds.md` in
  `self/README.md`, rather than ignoring them.
- **READMEs current.** The root `README.md`, `self/README.md`, `self/tests/README.md`,
  `CONVENTIONS.md` and `self/PROJECT_FACTS.md` (Layout and the gate's command list) all
  describe the new files and checks. The new test is added to `shell_scripts` and
  `record`ed in `self/gate.sh`, and the checker is added to the `py_compile` checks.

## Fixed in this pass

- `check-readme-index.py` docstring, "Exit codes": it said usage errors are printed as
  `readme-index: error: <detail>`. They are not: argparse prints its own `usage:` and
  `check-readme-index.py: error:` lines. The exit code, 2, was already right. I changed
  the docstring to describe what the code does. Test I9 asserts only the exit code for
  an unknown flag, so this mismatch could never have turned the gate red.

## Escalated to the next round

None.
