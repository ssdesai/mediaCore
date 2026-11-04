# 01 — review: fable-plan-model

feature: agentTooling/fable-plan-model

## What the feature was supposed to do

Make `fable` a fourth model a plan, verify or review file may name in its
`NN-description-MODEL.md` suffix, beside `haiku`, `sonnet` and `opus`, so any of the
three runners can run a plan on Claude Fable 5.1 — reviews in particular. Every place
that enumerates the accepted suffixes accepts `fable`; an unknown suffix is still refused
(check-plans, manifest.py) or still falls back to `sonnet` with a warning
(`extract_model`). The suffix reaches `claude --model` unchanged: the installed CLI's
`--help` lists `fable` as an alias, so no suffix-to-id mapping is introduced. No template
or runner changes which model it defaults to. Guidance in `AGENT_PLANS.md` places
`fable` above `opus` — most capable, reserved for reviews and the rare heaviest build,
never a default. The review budget (`REVIEW_BUDGET_USD`, $7.00, opus-calibrated) is
deliberately left alone; `RUNNER.md` says to raise it on the command line for a fable
review. This very review runs on fable.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. `self/features/` other than this feature's own directory is history
and must not have changed.

## Contracts to hold it to

- **One list, three spellings.** `check-plans.sh` `MODEL_RE`, `plan-runner-lib.sh`
  `extract_model`, `analysis/manifest.py` `PLAN_STEM_RE` must accept exactly the same four
  names. Is there any other enumeration of the suffixes on the tree (a runner, a template,
  `hooks/`, `analysis/`, a regex such as `report.py`'s `ESCALATION_STEM`, a doc or README
  row listing the three) that was missed, or one that now disagrees?
- **Nothing else moves.** No default model changed anywhere (`feature-start.sh`'s
  `NN-review-opus` stub, templates, run-escalation's `NN-escalation-opus`, budgets). The
  `extract_model` fallback and its WARN are unchanged for unknown suffixes.
- **Cost.** `analysis/rates_history.json` already prices `claude-fable-5-1`; a fable
  transcript is priced from the history with no live lookup and no unpriced warning, and
  `report.py`'s haiku/sonnet turn-count advisories do not misfire on a fable plan.
- **Tests.** `self/tests/check-plans.sh` 8d/8e and the new `self/tests/model-suffix.sh`
  (M1–M5) pin the contract and would have failed on `main`; the new test is wired into
  `self/gate.sh` (both the syntax list and a `record` line) and documented in
  `self/tests/README.md`.
- **Docs agree with the code.** `AGENT_PLANS.md` (filename convention, model guidance,
  review-plan model), `RUNNER.md` (review plans), `ORCHESTRATION.md`,
  `self/PROJECT_FACTS.md` — accurate, no duplicated or contradicting bullets, and no claim
  the code does not back (e.g. the rate ratio quoted against `rates_history.json`).

## Verdict

"No findings" is a legitimate verdict — say it outright rather than manufacturing concerns.
