# 01 — review: `Track.artist`

Independent review of one direct one-shot's diff. Written before the build, from the
manifest; nothing here comes from the implementer's report, and the implementer did not
write it.

## What the feature was supposed to do

`plans/features/track-artist-field/README.md` → "The decision": five points. Read them
first and hold the diff to them. Point 2 (schema 2, package 0.3.0) is the one a builder
is most tempted to soften to "additive, 0.2.1" — it is settled, for the reason given
there; a diff that did not bump `SCHEMA_VERSION` is a finding.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`src/mediacore/release.py`, `pyproject.toml`, `INTEGRATION.md`, `README.md`,
`plans/PROJECT_FACTS.md`, the `src/mediacore/` README, `fixtures/its-saxy/release.json`,
a frozen schema-1 asset under `tests/`, `tests/test_release.py`, `tests/test_bundle.py`,
`tests/README.md`. Also `plans/features/track-artist-field/` itself — `CHECKPOINT.md`,
`NOTES.md` — which is the implementer's record, not the feature.

## Contracts to hold it to

- **The tests came first** (`git log --oneline main..HEAD` shows the acceptance-tests
  commit before the implementation) and are black-box: through `write_bundle` /
  `read_bundle` or the public model API, never through private helpers.
- **`SCHEMA_VERSION == 2`, `version = "0.3.0"`**, the regenerated fixture carries
  `schema_version: 2`, and the gate's fixture step is clean (it fails on a diff — so the
  committed fixture must be exactly what the script writes).
- **Backward read, forward refusal**: a schema-1 bundle reads (the frozen asset proves
  it, not a hand-built dict); a schema-3 bundle is still refused.
- **Nothing vinyl-specific entered `src/`** (`plans/PROJECT_FACTS.md` → Conventions).
  `artist` is a neutral field; if its docstring or the INTEGRATION text talks about
  vinylCatalogue's `tracklist[].artist` leaf as anything other than the *source* in the
  mapping paragraph, flag it.
- **`Credit` is untouched**; no ref was added to `Track`.
- **Docs say what the code does**: every place `INTEGRATION.md` spells the `Track` shape;
  the §12 line; the §13 entry with its date; the README field lists.
- **Ruff clean, `s3` tests still run for real under `moto`** — no skip introduced.

## Judgment calls to check

1. Null versus omitted for a track with no artist — whichever `write_bundle` already
   does for other optional fields, applied consistently, and NOTES says which.
2. That the frozen schema-1 asset is byte-for-byte the previous checked-in fixture, not
   a hand-edited copy.
3. Whether the `Track` docstring makes the "absence is absence" semantics unambiguous
   to a consumer that has not read this manifest.

## Verdict

Write it to the path the runner names, for the person approving the PR: what the diff
was supposed to do, whether it does it, then two lists — fixed in this pass, escalated.
Fix local defects here (a missing README line, a stale shape string, an assertion that
does not bite); escalate structural ones, and record each escalation in a
`plans/BACKLOG.md` (create it, in the shape vinylCatalogue's has, if this repo has none)
— an escalation that lives only in this verdict is not recorded. Close with the one line
the person merging needs: the tag to create afterwards. "No findings" is a legitimate
verdict; say it outright rather than manufacturing concerns.
