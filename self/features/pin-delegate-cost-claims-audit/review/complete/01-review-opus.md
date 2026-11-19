# 01 — review: pin-delegate-cost-claims-audit

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/pin-delegate-cost-claims-audit/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`self/features/pin-delegate-cost-claims-audit/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own contracts — a records-only repair, so they replace the test and gate
lines above, which have nothing to bite on (no code or test changes; the start ran
`--no-gate`, and there is no `NOTES.md`):

- The diff touches only `self/features/delegate-cost-claims/{README.md,planning.json,report.json,report.md}`,
  this feature's own directory `self/features/pin-delegate-cost-claims-audit/`, and one
  added entry for it in `self/features/README.md`.
- In `delegate-cost-claims/README.md`, the only change is the JSON fence's `subagents`
  going from `["a36edc1deff7517d8"]` to
  `["a36edc1deff7517d8", "ad64af30ea0b2fdf0", "aff571c3480ebde40"]` — `session_window`,
  `branches` and every other key are byte for byte as on `origin/main`.
- `delegate-cost-claims/planning.json` holds exactly those three subagents, each selected
  `pinned`, and keeps `excluded_session_ids` (`5d25b685-…`) as on `origin/main`; its
  `cost_usd.total` is the sum of their three `priced` costs (≈ $43.47).
- `report.json` / `report.md` agree with that `planning.json`: build ≈ $43.47, review
  $1.4927 unchanged, total ≈ $44.96.

## Verdict
