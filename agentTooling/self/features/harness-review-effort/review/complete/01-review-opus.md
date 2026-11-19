# 01 — review: harness-review-effort

You are reviewing a finished change against its spec, with fresh eyes. Report what is
wrong; "no findings" is a legitimate verdict, and a finding must name the file, the line
and the failing scenario.

## What the feature was supposed to do

Add `HARNESS_REVIEW_EFFORT`, the effort (`claude --effort <level>`) of the harness review
stage and its usage-limit retry — exactly the calls `HARNESS_REVIEW_MODEL` covers (PR 127,
merge `c7c11abd`), found the same way (`do_review` in `harness/run.sh`).

- Unset or empty = `HARNESS_EFFORT`; both unset = no `--effort` flag, the CLI default, as
  before. Every existing experiment behaves identically.
- Validated like `HARNESS_EFFORT`: low, medium, high, xhigh, max; anything else is refused.
- Rework is building and stays on `HARNESS_EFFORT`; so do the methods and the program
  orchestrator. Only the review call and its retry carry the review effort.
- Recorded: result rows gain `review_effort` beside `effort` (added, `effort` unchanged),
  in both row shapes (cell rows in `run.sh`, program rows in `program-stages.sh`);
  null when the resolved value is empty, like `effort`.
- `--dry-run` prints the effort for every stage (cell and program dry runs).
- Docs: `harness/README.md` and `harness/SPEC.md` row fields; the note that the variable
  does not reach sessions the arm's own batch runners start applies to the new variable.
- Excluded: plumbing into the arm's batch runners, consumer repos, scorecard columns.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Exactly one call carries the review effort in a full run (two only on a usage-limit
  retry); no build, method or rework call does. No call ever carries two `--effort` flags.
- Unset behaviour is byte-identical to before: same argv, same dry-run text.
- `review_effort` is in cell rows and program rows; `effort` keeps its meaning.
- Invalid `HARNESS_REVIEW_EFFORT` is refused at source time with `harness_die`.
- The new tests (`harness/tests/review-effort.sh`, plus smoke assertions) run in
  `./self/gate.sh` and stub `claude`; no model spend. READMEs under `harness/` and
  `harness/tests/` describe the change.
- The diff stays under `harness/`, its tests and docs, `self/gate.sh`, and
  `self/features/harness-review-effort/`.

## Verdict

State `Verdict: clean` or list the findings.
