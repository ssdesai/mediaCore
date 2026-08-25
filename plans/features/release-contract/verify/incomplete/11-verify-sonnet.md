# Verify: the release contract end to end

Feature `release-contract` (plan 11 of 12). The batch delivers the whole `mediacore`
contract package — the `Release` schema, refs, the normalize fold, the bundle
reader/writer — plus the *IT'S SAXY* fixture bundle and its generator. WP0 of
`INTEGRATION.md` §12; three other repos are blocked on the tag cut from this branch.

Read `plans/gate-report.txt` first. It already ran install, `ruff check src tests`,
`fixture idempotent` (which regenerates `fixtures/its-saxy/` and diffs a second
generation against it), and `pytest -q`. **Do not re-run those.** If any section
failed, triage and fix it first, then re-run only that section to confirm.

Then read `tests/test_fixture.py`, `tests/test_bundle.py` and `tests/test_release.py`
before checking anything by hand — they cover a lot, and the point of this pass is what
they leave uncovered.

## What must be true when you are done

1. `fixtures/its-saxy/` exists on disk and is committed-able: `release.json` plus
   exactly sixteen files under `media/` (four PNGs, twelve WAVs). If the gate did not
   produce it, run `.venv/bin/python scripts/make_fixture_its_saxy.py` yourself.
2. The whole suite is green with zero skips.

## Checks worth a model's time

- **The fixture is portable, not just local.** The bundle's `sha256` filenames must be
  what any machine produces. Confirm the generator uses no clock, no randomness, no
  `zlib.compress`, no filesystem or network read, and no dict iteration whose order
  depends on anything but literal source order — read
  `scripts/make_fixture_its_saxy.py` for this; the gate's double-generation only proves
  determinism *on this machine*.
- **The packaged fixture path actually works.** `its_saxy_bundle()` prefers the repo
  checkout. Build a wheel into a temp directory (`.venv/bin/python -m pip wheel . -w
  <tmp> --no-deps`) and confirm `mediacore/_fixtures/its-saxy/release.json` is inside
  it — that is the only thing making the fixture reachable for a consumer who installs
  from a git URL, and no test can assert it from a source checkout.
- **A consumer's import line works.** In a scratch directory (not the repo root, so the
  `src/` layout cannot mask a packaging mistake), run a one-liner that does
  `from mediacore import Release, its_saxy_bundle, normalize_text, read_bundle` and
  `read_bundle(its_saxy_bundle())`, and prints the title. This is the exact call
  humanNetworkMap and musicMap will make.
- **`normalize_text` really matches vinylcat's.** Read
  `~/dev/vinylCatalogue/src/vinylcat/normalize.py` (read-only; do not modify anything
  in that repo) and diff its `normalize_text` / `normalize_catno` against
  `src/mediacore/normalize.py` line by line. Any difference at all is a defect here,
  not there. If `tests/test_normalize.py` has a sample the two would disagree on,
  say so.
- **Nothing vinyl-specific leaked into `src/`.** `INTEGRATION.md` §2.1 and
  `plans/PROJECT_FACTS.md`. `"vinyl"` may appear only as one value of the `Medium`
  literal. Grep `src/` for `vinyl`, `discogs`, `photo`, `sleeve`, `matrix` and judge
  each hit: a `discogs:*` ref-key constant is specified by §4 and is fine; a Discogs
  API shape or a photo-role vocabulary is not.
- **The README field lists match the code.** `src/mediacore/README.md` lists every
  field of every model (CONVENTIONS.md Rule 1). Compare it against
  `src/mediacore/release.py` field by field; a missing or renamed field there is a
  defect three repos will read as truth.
- **`INTEGRATION.md` §11 against the fixture**, for anything
  `tests/test_fixture.py` does not already assert.

## Latitude

Fix local defects directly — a wrong assertion, a drifted README line, a missing
constant, an import that ruff reorders. Anything needing a new function, a changed
signature, or a decision about the contract is a finding for the review pass or the
next batch; write it down rather than doing it here.

Do not create a `LICENSE`, tag a version, commit, or push — the review pass and
`plans/pr.sh` own that.
