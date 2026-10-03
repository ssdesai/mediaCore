# 57 — Verify: the analysis tooling actually runs

Feature: plan-analytics (plan 9 of 9) — tooling to price a feature end-to-end (planning
plus execution) and surface where delegated fanout wasted effort. This is the batch's
verify pass.

Depends on: 52–56.

Read `plans/gate-report.txt` first. Do not re-run install, lint, tests, typecheck, or
build — those already ran. If the report shows failures, triage and fix those first,
then re-run only the specific check that failed.

## Why this pass exists here

Batch 52–56 wrote a bash change and four Python scripts that **nothing has executed**.
`plans/gate.sh` runs this repo's checks — pytest over `tests/`, ruff over `src tests`,
the frontend build — and none of those cover `agentTooling/`. So the entire deliverable
is unexercised code, and that gap is the whole job here.

Everything below runs against data already on disk. Do not construct a collection,
generate fixtures, start a server, or fabricate a plan batch to test against — the five
completed features under `plans/features/*/auto/complete/` and `.../verify/complete/`
are real input and are sufficient.

## Checks

**1. The scripts run at all.** Each of `agentTooling/analysis/{pricing,backfill_usage,capture_planning,report}.py`
under `python3`. Confirm stdlib-only — no import of anything requiring an install. A
`ModuleNotFoundError` or `SyntaxError` here is the most likely defect in the batch.

**2. Backfill against real streams.** Run `backfill_usage.py`. It should write
`<plan>.usage.json` beside every `.stream.jsonl` under `plans/features/**`, across all
six feature directories (`core-library-and-gui`, `collection-selection`,
`extractor-backends`, `manual-readings-and-browse`, `image-versions-and-copies`,
`plan-analytics`) and both the `auto/` and `verify/` queues within each. Spot-check one
against its stream: for
`40-ingest-real-copies-haiku`, `total_cost_usd` should be ≈0.1647, `num_turns` 14, and
`files_edited` three **repo-relative** paths (a leading `/Users/...` means the prefix
strip is broken). Confirm re-running is idempotent and doesn't rewrite existing files
without `--force`.

**3. The runner writes the same shape.** Don't run a plan to find out. `bash -n` the
modified `agentTooling/plan-runner-lib.sh`, then extract its jq expression and run it by
hand against an archived `.stream.jsonl`. The output must match what `backfill_usage.py`
produces for that same plan — same keys, same values. These two writers diverging is the
defect that would quietly corrupt every future report, and it is invisible without this
comparison.

**4. Runner sessions are excluded from planning cost.** Run `capture_planning.py` for
the `plan-analytics` feature. Then confirm no `session_id` appearing in any
`usage.json` also appears in `plans/features/plan-analytics/planning.json`. Double-
counting execution as planning would inflate exactly the number this feature exists to
report.

**5. Cost is frozen, not recomputed.** `planning.json` must carry `rates_applied` and a
`rates_source` alongside the token counts. Confirm `report.py` reads the stored dollars
rather than recalculating from tokens — re-running the report must not change a
previously-written number.

**6. Unknown models yield null, not zero.** Ask the pricing module for a model that
isn't in the table. It must return `None`/null with token counts intact. A silent `0.0`
reports "planning was cheap" when it means "unmeasured", and would be indistinguishable
in a report.

**7. Report generation end to end.** Run `report.py` for `plan-analytics` and read the
output as a person would. Does the roll-up arithmetic add up (planning + build + verify
= total)? Do the tripwires stay silent rather than firing on noise? Confirm the
stream-dependent metrics (re-hunting, cross-plan edit overlap) say "not computed" when
streams are absent rather than reporting zero — delete or move a `.stream.jsonl` to a
temp location to check this, then restore it.

## Latitude

Fix local defects directly — a wrong dict key, an off-by-one in a path strip, a metric
dividing by zero on an empty plan. Anything needing a new function or a signature change
is a build plan for the next batch; report it rather than building it here.

Where you find an invariant worth guarding permanently — the two writers agreeing in
check 3 is the obvious candidate — **report the assertion rather than writing a test
harness**. `agentTooling/` has no test setup, and standing one up is its own decision,
not a verify-pass side effect.
