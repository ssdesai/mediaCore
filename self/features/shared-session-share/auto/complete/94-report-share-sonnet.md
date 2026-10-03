# 94 — report the share, and retire the no-apportionment doctrine

feature: agentTooling/shared-session-share — plan 6 of 6. Level 1 splits a multiply-claimed
session between its claimants; this plan renders that in `report.py` and rewrites the four
places in the doctrine that currently assert the money is never split.

Depends on: `91-share-pricing-sonnet.md` for the `planning.json` fields, and
`93-report-tests-sonnet.md` for the assertions.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- `report.py` never reprices. It reads `planning.json`'s frozen dollars and sums them; the
  share is already applied to `priced[].cost_usd` by level 1, so no total in this file
  changes and none of its arithmetic is edited.
- `compute_shared_sessions(planning_data)` is at `analysis/report.py:805`; its output
  lands as `cost.shared_sessions` at `analysis/report.py:1053` and is rendered by the
  block at `analysis/report.py:1883`.
- A `planning.json` written before this feature has neither `share_basis` nor
  `session_cost_usd` on any session entry. Read every new field with `.get(...)`, and
  treat its absence as the old meaning — counted in full — rather than as zero.

## Files

- Modify `analysis/report.py`
- Modify `analysis/README.md`
- Modify `AGENT_PLANS.md`
- Modify `templates/plans/features/TEMPLATE.md`

## `analysis/report.py`

`compute_shared_sessions` gains `session_cost_usd` in each entry, read from the session
entry's own field and omitted when the record does not carry one. `cost_usd` keeps its
current derivation — the sum of that session's own `priced[]` rows, delegates excluded —
which is now the share, because level 1 divided it there.

Rewrite the docstring. What it says today is the position this feature reverses: "There is
no apportionment and there will not be one: the transcript cannot say which feature a
message served, and a split by message count would be a number nobody measured." Replace
it with the rule and the reason the objection no longer applies — the split is not by
message count but by the claims themselves, each feature's own `session_window`, which are
facts the manifests already state; the claims partition the transcript, so the shares plus
the unclaimed remainder equal the session's cost exactly; and where claims overlap the
even division is an estimator, which is why `share_basis` records what it used. Keep the
"read with `.get(…) or []`" note and extend it to the new field.

Rewrite the footnote at `analysis/report.py:1883`. It currently ends "Each is priced here
in full and in full there: a transcript cannot say which feature a message served, so
nothing is apportioned, and summing these features' totals counts it once per feature."
The new line names, per session, this feature's share, the session's own cost and the
other claimants, and says the shares of all claimants sum to the session — so summing
these features' totals now counts it once, not once per feature. **A session entry with no
`session_cost_usd` keeps the old sentence**, because that record was frozen before the
split and is counted in full; render the two cases distinctly rather than with one string.
The phrase "in full" must not appear beside a divided figure — `self/tests/claims-ledger.sh`
B11 asserts its absence.

## `analysis/README.md`

The `report.py` entry's description of `cost.shared_sessions` (search for
`compute_shared_sessions`, near `analysis/README.md:545`, and the report-shape line near
`analysis/README.md:889`): add `session_cost_usd` to the field list and replace the
"priced in full by each" sentence with the share. Do not restate the rule at length — it
belongs in the `capture_planning.py` entry plan 91 rewrites; point at it.

Also update the weekly-cadence paragraph near `analysis/README.md:70` that describes what
`--all` refreshes on a frozen record: `also_claimed_by` is still the only thing it writes,
but the run now also *warns* that such a record's figure predates the share rule and names
`--recapture` as the repair, while transcripts survive.

## `AGENT_PLANS.md`

The `sessions` bullet in "The feature manifest" says "A pinned session that branch and
window would also select is priced once, and each `planning.json` entry records
`selected_by`". Add to it: a session that more than one manifest claims is now **split**
between them by the windows they claim it with, so a `session_window` on a pinned session
has become load-bearing where it used to be inert — a wrong bound moves money between
features rather than merely widening a net. Also amend the `session_window` bullet's "Set
`to` as soon as the feature is done" paragraph: an open `to` on a shared session now takes
a share of everything to the end of the transcript.

Do not restate the algorithm here; one sentence and a pointer to `analysis/README.md`.

## `templates/plans/features/TEMPLATE.md`

The `sessions` bullet in the manifest template ships to every consuming repo and says the
same thing. Give it the same one-sentence amendment: a session claimed by more than one
feature is split between them by their windows, so the bounds on a pinned session decide
dollars. Nothing else in the template changes, and its `template-version` is not bumped —
this is prose in a generated stub, not one of the five repo-owned files.
