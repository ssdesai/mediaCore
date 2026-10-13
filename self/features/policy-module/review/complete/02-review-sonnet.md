# 02 — review: policy-module, round 2

Round 1 (`review/complete/01-review-opus.md`, report at `escalations/01-review-opus.md`)
judged every manifest slice done, fixed two local drifts, and escalated one finding. This
round judges the rework of that finding and confirms round 1's own fixes still hold. Begin
your report with the `Verdict:` line the prompt asks for. "No findings" is a legitimate
verdict; fix local drift here; anything structural is round 3's brief. You may edit
under `hooks/` through the Edit tool; if refused, say so and escalate instead of shelling
a write around it.

## What the rework was supposed to do

`scratch_argument_allowed` (`hooks/allow-repo-commands.sh`) judged a scratch script's
argument with `token_confined`, whose rule "a relative value that names nothing on disk
is not a path" is right for a reader (`cat ../x` fails harmlessly) and wrong for a
script's argument, which may be an output path. So `bash <scratch>/x.sh ../x` was
approved while `../x` did not exist and prompted once it did; the absolute spelling
prompted either way. The contract chosen: **existence never decides.** A relative
non-flag value — including the value after `=` in `--out=../x` — must be lexically inside
the project root (`normpath(join(cwd, value))` under the root) or lexically inside the
scratch root, whether or not it exists, and must still pass `token_confined` when it does
exist (a symlink out of either root is not confined). A flag with no value carries no
path and stays approved. Asserted in `self/tests/hook-escalation.sh`: `bash
<scratch>/x.sh ../x` with `../x` absent prompts; `bash <scratch>/x.sh --out=../x`
prompts; `bash <scratch>/x.sh new-output.txt` (relative, absent, inside the root) is
approved. `hooks/README.md` § the scratch entry point says existence does not decide.
`NOTES.md` carries the ruling under "Round 2".

## The diff

Two diffs. The rework: `git diff <round-1 head>..HEAD` where the round-1 head is the
`head` on the `plan_end` stamp for `01-review-opus` in
`self/features/policy-module/timing.jsonl` (or the commit `policy-module: review round
1`). Expect `hooks/allow-repo-commands.sh`, `self/tests/hook-escalation.sh`,
`hooks/README.md`, `NOTES.md`, `CHECKPOINT.md`, `timing.jsonl`, and this brief plus the
manifest's `plans` and `subagents`. Then the whole feature, `git diff
lifecycle-records-and-numbering...HEAD --stat`, to confirm nothing outside those files
moved since round 1.

## Contracts to hold it to

- **Existence never decides.** Read `scratch_argument_allowed`: the lexical check runs
  on every relative non-flag value before any `os.path.exists`; the same value spelled
  `--out=<value>` is split and judged the same way. Create `../x` in the fixture and the
  outcome is unchanged (prompt).
- **The unit was red without the fix; end to end it was masked.** The rework found
  that `command_allowed`'s older `UNANALYSABLE` guard refuses any command containing
  `..` before the scratch logic runs, so the two `../x` commands prompted before the
  fix too, and only a direct call of `scratch_argument_allowed` showed the defect
  (`True` for `../x` and `--out=../x` before, `False` after). Hold it to that: the
  function's contract is the fix, and `NOTES.md` ruling 17 says exactly what was and
  was not seen red. Then judge whether a unit assertion belongs in a test file — the
  module-loading technique `self/tests/policy-table.sh` uses reaches the function
  directly — and add one if the end-to-end cases cannot demonstrate the rule; that is
  local drift, yours to fix. Confirm `SCRATCH_PROMPT` carries both new cases and
  `SCRATCH_ALLOW` the inside-the-root one regardless.
- **Nothing else loosened.** Every earlier `SCRATCH_ALLOW` and `SCRATCH_PROMPT` case is
  still there with the same expectation; `bash -x <scratch>/x.sh` still prompts; a
  symlink out of the scratch root still prompts.
- **Round 1's fixes hold.** `./gate.sh` and `./gate.sh 08` are in `ENTRY_ALLOW`; the
  `self/PROJECT_FACTS.md` ruling is in `NOTES.md`.
- **Style and docs.** Python stdlib; named constants; `hooks/README.md`'s scratch
  paragraph states the rule; the ruling is in `NOTES.md` under "Round 2".
- **Gate.** `self/gate-report.txt` ends `all checks passed`.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the rework was supposed to do, whether it does it, what you fixed, what you
escalated with the assertion that would catch it, and the files this pass touched.
