# 05 — report.py counts recovered cost instead of dropping it

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Plan 5 of 6 build plans, first of level 2. `recover_attempts.py` now writes recovered
dollars into the sidecars; nothing reads them yet.

## What report.py does today

`compute_cost_rollup` (`analysis/report.py:260`) sums each plan's top-level
`total_cost_usd`. At `report.py:277-292` it separately notices attempts whose
`total_cost_usd` is null, appends the stem to `priced_without_cost`, and warns that "its
total is a lower bound". `total_is_partial` at `report.py:312-317` is then set from
`priced_without_cost` among other things. The reasoning in that comment is sound and stays
sound — it just now has a third case it does not know about: an attempt whose cost was never
measured but *has* been recovered.

## Changes

1. In the `unpriced` comprehension at `report.py:281-285`, an attempt now falls into one of
   three buckets rather than two: **measured** (`total_cost_usd` is not null),
   **recovered** (`total_cost_usd` null, `recovered_cost_usd` present), **unrecoverable**
   (both absent). Only the third makes the total partial.
2. Add the plan's recovered dollars into the queue bucket the measured cost goes into
   (`report.py:293-299`), so `cost.build` / `cost.verify` / `cost.review` are whole again.
3. Report recovered spend in its own right rather than silently folding it in. Add to the
   `cost` object: `recovered` (dollars) and `unrecoverable_attempts` (a list of
   `{plan, session_id}`). A reader must be able to see how much of a total is derived
   rather than measured — that is the whole reason plan 03 refused to overwrite
   `total_cost_usd`.
4. Keep a warning for recovered attempts, but change what it says: today's text claims the
   total "is a lower bound", which is false once the attempt is priced. Say instead that N
   attempts were priced from transcripts rather than reported by the CLI.
5. `report.md` is the human rendering of `report.json` and carries no independent numbers
   (`analysis/README.md`). Render the recovered figure there too, marked as derived.

## Compatibility

Every `report.json` and `usage.json` already on disk predates this. Read `recovered_cost_usd`
and `recovered` with a `0.0` default and `unrecoverable_attempts` with `[]` — never index
them. `analysis/README.md` already records the precedent and the reason:
`cost.review`/`cost.review_pct` are read with a `0.0` default because every report written
before the review queue existed lacks both keys, and `--all`'s job is ranking historical
features beside new ones. The same applies here; `--all` must not crash on a pre-batch
report, and a feature with nothing to recover must legitimately read `0.0`.

Do not recompute any dollar figure. `report.py`'s standing rule — stated in its own module
docstring at `report.py:9` — is that every cost comes from a `usage.json` or `planning.json`
already on disk, summed or divided, never repriced. A recovered figure was priced once, by
`recover_attempts.py`, at that session's own date; re-deriving it here would reintroduce
exactly the wall-clock-vs-session-date bug plan 02 just closed.

## Done when

`python3 -m py_compile analysis/*.py` is clean, `self/tests/cost-recovery.sh` still passes
in full, and `python3 analysis/report.py --all` runs against the existing committed corpus
without error — that corpus is entirely pre-batch, so it is the compatibility test.

Update `analysis/README.md`'s `report.json` field list with `cost.recovered` and
`cost.unrecoverable_attempts[]`, and its `report.py` entry with the three-bucket rule.
