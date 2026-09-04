# null

The harness's own test double, and the reason `harness/tests/smoke.sh` can run the whole
pipeline with no network and no money. It calls no model.

- `run.sh` — writes `plans/null-method-marker.md` (the brief, verbatim, inside a fence),
  commits it, and calls the repo's own `plans/pr.sh` — the same hook `run-review.sh`
  uses, so the PR step is exercised rather than mocked away. Exits 0, or 1 if the brief
  is missing, nothing was committed, or the hook fails.
- `template.md` — filled like any other method's, and copied into the marker. Nothing
  reads it as a brief; it exists so the smoke test proves the brief stage fills every
  placeholder, which is where a real method's run would otherwise fail first.

It ships with the harness rather than living under `tests/` on purpose: a double that
sits outside `methods/` stops satisfying the method contract the moment that contract
changes, and then the smoke test passes while the real methods do not.

Its marker path (`plans/null-method-marker.md`) is the fixture-side agreement: the smoke
fixture's `accept/accept.py` checks for exactly that file.
