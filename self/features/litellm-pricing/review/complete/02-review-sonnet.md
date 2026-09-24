# 02 — review: litellm-pricing (round 2, the merge from main)

feature: agentTooling/litellm-pricing

Round 1 (`01-review-opus`) reviewed the whole feature and returned `Verdict: clean`. After
that review, `origin/main` gained `carry-stream-sections` (PR #61), and it was merged into
this branch. The merge commit is the only thing round 1 did not read. Review only the
merge. Do not re-review the feature.

## What the feature was supposed to do

See `self/features/litellm-pricing/README.md` → "Spec". The rates come from a dated,
append-only `analysis/rates_history.json`, which `analysis/refresh_rates.py` appends to
from LiteLLM.

## The diff

The merge commit is the latest `Merge remote-tracking branch 'origin/main'` on this
branch; find it with `git log --merges -1`. Read `git show --cc <merge>`, which shows only
the hunks that combine both sides. Then read the files both sides touched, as they are at
`HEAD`: `analysis/README.md`, `analysis/report.py`, `self/BACKLOG.md`,
`self/tests/README.md` and `self/tests/report-footnotes.sh`.

## Contracts to hold it to

1. **Both sides survive.** `report.py` keeps litellm-pricing's rates footer and imports
   (the history's `checked` date, with no `RATES` table). It also keeps
   carry-stream-sections' carried-forward stream sections and `STREAMS_UNAVAILABLE`.
   Neither side's hunk may be dropped or duplicated.
2. **`self/tests/report-footnotes.sh`.** Its sandbox copies `analysis/rates_history.json`
   next to `pricing.py`, which is this feature's line. Its new phase from
   carry-stream-sections is present, and the whole script passes.
3. **READMEs and BACKLOG.** Each side's entries are present once, in a readable order,
   with no text interleaved. The `rates_applied` field lists in `analysis/README.md` still
   list `from` and `source`.
4. **Gate.** Run `./self/gate.sh` yourself. It must be green.

## Verdict

Open the report with exactly one line: `Verdict: clean` or `Verdict: escalated`. "No
findings" is a legitimate verdict. Fix local defects yourself and commit the fixes.
Escalate only what is structural.
