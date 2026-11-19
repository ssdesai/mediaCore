# 01 — review: harness-review-model

Review the diff of this branch against the spec below, written before the build and not
from the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

The experiment harness builds and reviews on one model, `HARNESS_MODEL`. The owner wants to
build with a cheaper model and keep the harness review on Opus, so a weaker model never
grades its own work. The feature adds one knob and records it:

- `HARNESS_REVIEW_MODEL` names the model of the harness review stage. Unset or empty means
  `HARNESS_MODEL`, so every existing experiment behaves exactly as before. The review is
  the only stage that judges and makes a model call; accept is mechanical. Rework builds
  and stays on `HARNESS_MODEL`; so do the method, the program orchestrator and the program
  implementers. A program cell's review goes through the same `do_review`, so it inherits
  the knob.
- Both ledger row shapes (ordinary and program) gain `review_model`; `model` keeps its
  meaning (the build model). Added, nothing renamed. `review_model` is the resolved model,
  never empty.
- `--dry-run` prints the model of every stage: the method line, the review line, the rework
  line, and the program cell's lines.
- `harness/README.md` documents the variable, that rework stays on `HARNESS_MODEL`, and two
  facts: `HARNESS_EFFORT` reaches only sessions launched through `harness_claude` (sessions
  the arm's own `run-batch.sh` / `plan-runner-lib.sh` start run at the CLI default), and a
  method's `run.sh` runs from the driver's checkout (`HARNESS_METHODS_DIR`), so a method fix
  must be in the driver.
- Offline tests with a stub `claude`, registered in `self/gate.sh`: unset = old behaviour;
  set = the review call carries the review model and no build call does; the row records
  both; the dry run prints both.

Excluded: effort plumbing into the arm's batch runners; any consumer repo; any change to
the rework or accept model.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- With `HARNESS_REVIEW_MODEL` unset, every `claude` argv is identical to before, and rows
  differ only by the added `review_model` (equal to `model`). Dry-run lines are unchanged
  except the program cell's per-feature review and rework lines, which now name `--model`.
- Both review call sites in `run.sh` (first call and usage-limit retry) use the review
  model; no other call site does. The dry-run review line shows it.
- `model` in rows is still `HARNESS_MODEL`; `review_model` is in the ordinary row, the
  program row, and the field lists in `harness/README.md` (Rule 1 of CONVENTIONS.md).
- The new test is registered in `self/gate.sh` (syntax-check list and a `record` line),
  named in `harness/tests/README.md`, and the gate's count line there is correct.
- Docs: `harness/README.md` has the variable, the rework statement, and both facts above;
  `harness/SPEC.md` line about "Every implementer runs at HARNESS_MODEL" stays true or is
  updated; no stale statement that review runs at `HARNESS_MODEL` remains.
- The diff touches only `harness/`, its tests and docs, `self/gate.sh`, and
  `self/features/harness-review-model/`. Nothing under `.claude/`; no model name in any
  file or commit message.
- Shell style: named constants for defaults, no magic literals.

## Verdict

Write the round's verdict in the form `run-review.sh` expects: `Verdict: clean` or
`Verdict: escalated`, with each finding's file and line.
