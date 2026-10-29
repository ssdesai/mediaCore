Verdict: clean

# Review: fable-plan-model (round 1, on fable)

## What the batch was supposed to do

Make `fable` a fourth model suffix a plan, verify or review file may carry
(`NN-description-fable.md`) beside `haiku`, `sonnet` and `opus`, so any runner can run a
plan — a review in particular — on Claude Fable 5.1. Every enumeration of the accepted
suffixes accepts it; an unknown suffix is still refused by `check-plans.sh` and
`manifest.py` and still falls back to `sonnet` with a WARN in `extract_model`; the suffix
reaches `claude --model` unchanged as the CLI's own alias; no default model or budget moves;
the guidance places `fable` above `opus`, never as a default.

## Does it?

Yes. Diff reviewed against `origin/main` (14 files, two commits; `self/features/` untouched
outside this feature's own directory).

- **One list, three spellings.** `check-plans.sh` `MODEL_RE`, `plan-runner-lib.sh`
  `extract_model` and `analysis/manifest.py` `PLAN_STEM_RE` all read
  `haiku|sonnet|opus|fable`. A sweep of the tree for any other enumeration of the three
  (runners, templates, `hooks/`, `analysis/`, `harness/`, docs) found none that was missed:
  `backfill_usage.py`'s `derive_model` takes any trailing segment, `report.py`'s
  `ESCALATION_STEM` takes any `[a-z]+`, and `ORCHESTRATION.md`'s one list of the
  suffix names was updated. The remaining `opus`/`sonnet` mentions in `LIFECYCLE.md`,
  `ORCHESTRATION.md` and `AGENT_DIRECT.md` are tiering guidance, not suffix lists, and
  are correct as they stand.
- **Nothing else moves.** `feature-start.sh`'s `01-review-opus` stub, the template's
  `NN-review-opus`, `write_escalation_plan`'s `NN-escalation-opus`, and all four budget
  constants are absent from the diff. The `extract_model` fallback and WARN text are
  unchanged. The runner still passes the suffix as `claude -p --model "$model"`, and the
  installed CLI's `--help` lists `fable` as an alias beside `opus` and `sonnet`.
- **Cost.** `analysis/rates_history.json` already carries `claude-fable-5-1`; M5 prices
  it from the history with no live lookup. `report.py`'s turn advisories match `haiku` and
  `sonnet` by substring only, so a fable plan takes neither.
- **Tests.** `check-plans.sh` 8d/8e and `model-suffix.sh` M1–M5 pass in the gate report
  and would fail on `main` (8d, M1-fable and M3 each depend on the new alternation). The
  new test is in `self/gate.sh`'s syntax list and has its `record` line, and
  `self/tests/README.md` describes it accurately, down to the file list it copies.
- **Docs.** `AGENT_PLANS.md`, `RUNNER.md`, `ORCHESTRATION.md`, `self/PROJECT_FACTS.md`,
  `self/features/README.md` and the feature README agree with the code and with each
  other. One claim was only partly backed; fixed below.

## Fixed in this pass

- **Rate ratio overstated.** `AGENT_PLANS.md` (lines 127 and 501) and `RUNNER.md`
  (line 108) said a fable review "pays two and a half times" Opus 5.5's token rates.
  Against `rates_history.json` that holds for input, output and cache writes
  ($10/$50/$12.50 vs $4/$20/$5) but cache reads are $0.25 vs $0.20, a quarter more — and
  cache reads are most of what a review pass replays. Reworded both files to name the
  rates the ratio applies to and to say a review's bill lands between the two ratios;
  the `REVIEW_BUDGET_USD=15.00` advice is unchanged, since it is a cap, not an estimate.

## Escalated to the next round

None.
