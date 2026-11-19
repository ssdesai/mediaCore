Verdict: clean

# Review round 2: harness-scorecard-time

## What the batch was supposed to do

Make `harness/scorecard.py` show time as plainly as it shows cost. The Runs table gains
"Wall to green" (`t_method_start` → `t_green`) and "Total" (`t_setup_start` → `t_green`)
next to "Wall to PR". The Per cell table gains mean wall to PR and mean total, which leave
out `method_failed` rows, with a footnote saying so. The docs name the new columns and say
the times are wall-clock, and an offline test is registered in `self/gate.sh`. The feature
adds no row fields, makes no `run.sh` change and touches no consumer repo.

Round 1 judged it clean. The only work after that is commit `497243b`, which fills
`self/features/harness-scorecard-time/README.md` (`feature-close.sh` refuses the template),
plus the queue commit that added this round's plan row.

## Does it do it

Yes.

- **Scope:** `git diff origin/main...HEAD --stat` touches only `harness/` (scorecard,
  SPEC, README, tests), the one `self/gate.sh` registration, and
  `self/features/harness-scorecard-time/`.
- **Code:** the code diff is the one round 1 read, and the round-1 contracts still hold on
  the final tree:
  - The Runs header and the separator both have 13 columns.
  - The Per cell header and the separator both have 9 columns.
  - `mean_minutes` drops rows with `method_failed` and rows missing an instant, and
    prints `—` when no row is left.
  - The SPEC paragraph matches the code.
- **Feature README:** it states the columns, the exclusions (no new fields, no `run.sh`
  change, no time in the Programs section, no consumer repo), and that the feature was
  built directly. The Plans table and the manifest's `plans` both list `01-review-opus`
  and `02-review-opus`, one row per plan.

## Fixed in this pass

- `self/features/harness-scorecard-time/README.md`, "Deliberately excluded": the README
  said "the five existing instants suffice", but a ledger row has six
  (`harness/SPEC.md:283`: `t_setup_start`, `t_method_start`, `t_pr_open`, `t_review_end`,
  `t_rework_end`, `t_green`). It now says the row's existing instants suffice and names the
  four the columns read.

## Escalated to the next round

None.
