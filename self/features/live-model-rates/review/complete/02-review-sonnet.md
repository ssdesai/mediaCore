# 02 — re-review: live-model-rates, round 2

Scoped re-review. Round 1 (`review/complete/01-review-opus.md`, escalations in
`escalations/01-review-opus.md`) found the feature correct and escalated two items. Judge
only whether round 2 closes them, and whether the round-2 commits broke anything.

## The diff

`git log --oneline` to find the round-1 review commit (`live-model-rates: review round 1`);
read `git diff <that commit>..HEAD` in full. Earlier commits are out of scope.

## Contracts

1. **Visibility tests.** A self-test recovers an attempt on a model only the fixture
   LiteLLM source carries (lookup on, `RATES_CHECK_SOURCE` at a local fixture, no
   network) and asserts: the attempt's `rates_applied[<model>].source == "litellm-live"`;
   `recover_attempts.py` stdout has a `live:` line naming the model; `report.py` over
   that feature has a `WARN:` line naming the model with no live row in `planning.json`.
   Each assertion must fail if its path broke (check the assertion would catch a dropped
   `is_live` check).
2. **Warning wording.** `pricing.live_price_warning` now tells the reader to refresh the
   history in a self feature *and then* `capture_planning.py --recapture` the feature;
   `analysis/README.md` quotes the same sentence; existing assertions still pass.
3. `./self/gate.sh` is green. Run it.
4. Nothing else changed in behaviour.

## Verdict

"No findings" is a legitimate verdict. Report findings with file:line; fix nothing.
