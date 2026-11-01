# 96 — review: shared-session share

feature: agentTooling/shared-session-share.

## What the feature was supposed to do

`feature-start.sh` pins the session that ran it, so a session that starts N features is
pinned into N manifests as a matter of course, and `select_parent` then priced each of
those N features for the whole transcript — the window was only ever used to *include* a
session, never to slice it. Measured: session `3571cc77` cost $47.18 and is booked at
$188.71 by four features, each also reporting its full 22.8-hour span as its own duration;
session `ed088063` cost $70.50 and is booked at $563.97 by eight features across two
repos.

This batch splits a multiply-claimed session between its claimants. Each billable response
goes to every feature whose `session_window` covers its timestamp, divided equally; the
stretch before the earliest claim goes to the earliest claimant; the stretch past every
`to` goes to nobody and is reported. Time is partitioned by the same rule. A session with
exactly **one** claimant is priced and timed exactly as before.

`window-slicing-brief.md` in this feature's directory is the original bug report. Two of
its recommendations were deliberately not taken; the manifest's "Deliberately excluded"
section says which and why. Read both before judging the diff — a finding that re-proposes
either is answered there.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- **The invariant.** A session's claimants' shares, plus its unclaimed remainder, equal
  the session's own undivided cost — and the same for seconds against its own span. Every
  other property of this feature is downstream of that one. Check it holds in the code and
  not merely in the fixtures the tests happen to use: what does an empty claim list do,
  what does a claim whose `from` equals another's `to` do, what does a `None` timestamp do.
- **The unshared path did not move.** A feature whose session nobody else claims must
  produce a byte-identical `planning.json` to the one it produced before this batch, and
  every consuming repo's future capture depends on that. `share`, `full_cost_usd`,
  `shared_with`, `share_basis`, `session_cost_usd`, `session_duration_s` and
  `unclaimed_usd` are all absent on such a record.
- **Frozen records are not re-derived.** `--all` without `--recapture` still opens no
  transcript and changes no figure; the only thing this batch adds to that path is a
  warning.
- **`report.py` reprices nothing.** It reads frozen dollars and sums them. If any total in
  that file is now computed differently, that is a defect regardless of whether it happens
  to agree.
- **Legacy records read as what they are.** A `planning.json` with no `session_cost_usd`
  predates the split and is counted in full; a ledger claim with no `window` predates
  recorded windows and is read as unbounded. Both are the common case in every consuming
  repo. Neither may be rendered as a share it is not.
- **The doctrine matches the code.** `analysis/README.md`, `AGENT_PLANS.md`,
  `templates/plans/features/TEMPLATE.md` and `analysis/report.py`'s own docstrings all
  asserted, in those words, that nothing is apportioned. Every one of those statements is
  now false; a surviving copy of it is a defect of the same kind as a wrong field list.
- **README Rule 1.** `analysis/README.md`'s `planning.json` shape entry must list every
  new field, and `self/tests/README.md` must describe the two new scripts at the depth of
  their neighbours.

## Verdict

"No findings" is a legitimate verdict; say so plainly if that is what reading the diff
supports, rather than producing a speculative finding the next batch has to disprove.

The highest-value finding here is a missing assertion — an invariant this batch introduced
that nothing tests, phrased as the assertion to add. Two separate lists: what you fixed in
this pass, and what you escalated to the next batch.

The verdict is the body of the pull request, so write it for the human approving it: what
the batch was supposed to do, whether it does it, and those two lists.
