# Review pass and cost attribution

The third queue and the accounting fixes it exposed. `run-review.sh` drains
`review/incomplete/` after verify, hands an opus executor the batch's own diff, and opens
the PR with the executor's verdict as the body — so the last thing that reads the work is
a model that did not write it. `run-batch.sh` chains build → gate → verify → review.

Adding a third queue changed what the cost report has to account for, and each of the
three accounting fixes here was found by the same route: a number that was wrong with no
visible symptom.

- A fourth cost bucket. `analysis/report.py` split `verify` into `verify` and `review`;
  before, a review plan's cost either landed in the verify bucket or nowhere.
- `find_orphan_usage`. The runners are directory-driven — they drain
  `<queue>/incomplete/` and never read the manifest — so a plan left out of `plans[]`
  runs, bills, and writes its usage.json while every table walking the manifest behaves
  as though it never existed. A third queue widened the chance of that omission enough
  that a documentation rule stopped being sufficient.
- `check_branch_overlap`'s condition. It warned only when *neither* manifest declared a
  `session_window`, so declaring one on both silenced the only check there was. Two
  open-ended windows on a shared branch — the natural thing to write mid-feature — then
  double-counted every shared session in silence. It now tests whether the windows
  *intersect*.

## This feature is unbuilt work made visible, not delegated work

Everything here was written interactively rather than by executors, so there are no
plans, no usage.json sidecars, and no build/verify/review cost. This manifest exists so
the planning cost has somewhere to live and so `analysis/report.py` can say what it does
not know, rather than the work being invisible to the corpus that measures the harness.

## Attribution honesty

**This manifest claims exactly one session, and every session it would otherwise have
claimed is listed in `exclude_sessions`.**

The five interactive sessions that produced this work also produced the
`discogs-field-reconciliation` batch in the consuming repo, and that feature's window
already claims all five. A session is matched atomically — the whole session or none of
it, on its start timestamp — so there is no way to split one after the fact. Claiming
them here as well would reintroduce exactly the double-count `check_branch_overlap` was
just fixed to catch, so they are excluded by id instead.

The consequence is stated rather than hidden: those five dollars are booked to
`discogs-field-reconciliation`, which therefore reports a total that includes work that is
not its own. That is a known misattribution with a named cause, which is the honest
version; a plausible number is not.

The one session this manifest does claim is `925334ee`, captured at **$0.8538** — the
subtree update that landed this work, on this feature's own branch and claimed by no other
feature. It is not feature planning in the usual sense, and an earlier revision of this
section asserted a flat zero on the strength of that. Excluding it was the wrong
instrument: `exclude_sessions` prevents a session being counted **twice**, and nothing else
counts this one, so excluding it would delete real spend from the corpus rather than move
it. A dollar that belongs to no feature and appears in no total is the precise failure
`killed-attempt-cost-recovery` and `recovered-totals-stay-honest` were built to remove, and
it would be perverse to reintroduce it here to keep a rounder number.

This is also why `branches` names this feature's own branch rather than the shared one.
Naming the shared branch would make `check_branch_overlap` warn forever about a
double-count that `exclude_sessions` has already prevented — the check reads windows, not
exclusions — and a permanent false warning is how a real one gets ignored.

The lesson is the one the fixed warning now prints on its own: one session per feature,
and one branch per feature, so `branches` does the attribution and `session_window` stays
an escape hatch rather than the load-bearing part.

## Deliberately excluded

- **No `plans[]` entries.** There were no delegated plans. An empty array is the true
  value, and `analysis/report.py` renders it as a feature with planning cost and no
  execution cost rather than treating it as a broken manifest.

## Machine-readable

```json
{
  "slug": "review-pass-and-cost-attribution",
  "plans": [],
  "branches": ["agenttooling-cost-attribution-fixes"],
  "session_window": {"from": "2026-08-18T00:00:00Z", "to": "2026-08-18T23:59:59Z"},
  "exclude_sessions": [
    "3954fa69-4a02-4cd9-9a52-2bf904b6f443",
    "77d5feef-d21d-4b27-9bd7-7c91c812690b",
    "835f5918-62d9-42d6-b0dd-ae6f697cfdb9",
    "a448990d-87d6-4e6a-899c-10b6f193ca49",
    "ec71f411-f0a2-41fb-a5dc-38bbe0eb0396"
  ]
}
```
