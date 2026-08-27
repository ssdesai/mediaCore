# fixtures

Contract fixtures every repo in the integration tests against. Read-only inputs — never
edited by hand, never edited by a test.

- `its-saxy/` — the *IT'S SAXY* release bundle (`INTEGRATION.md` §11): one real,
  Discogs-matched record (The Duke's Combo, A. A. E. `SAAE 1012`) with **placeholder
  media** — deterministic 1×1 PNGs for the four images and short silent WAVs for the
  twelve audio files. Layout is the §5 bundle format: `release.json` plus
  `media/<sha256>.<ext>`. Its media hashes therefore differ from the live record's, by
  design: the live bundle is for the human end-to-end run, this one is for tests.
  Regenerate with `.venv/bin/python scripts/make_fixture_its_saxy.py`; the generator is
  deterministic, so a regeneration that changes a byte is a bug in the generator.
  Reach it from code with `mediacore.its_saxy_bundle()`, never by hard-coded path.
  It is also the bundle `mediacore.seed_its_saxy_store()` puts into a `file://` (or
  `s3://`) store (`INTEGRATION.md` §5.1 "Fixture"). Seeding writes **outside** the
  checkout, into whatever store root or bucket the caller names — nothing under
  `fixtures/` is ever written by the store.

  **One field in this bundle is invented rather than transcribed.** Every other value
  in `release.json` comes from `INTEGRATION.md` §11, which was read from the live
  record — but §11 does not record the two `external_photo` `source_url`s, so the
  generator synthesizes them (`https://i.discogs.com/R-16853262-000N.jpeg`). They have
  the shape of a Discogs image-CDN address and are **not** addresses that were fetched
  or that resolve. A consumer test may assert that `source_url` is present and is a
  URL; it must not fetch one, and it must not treat these two strings as real Discogs
  data. Nothing else in the bundle is invented: the placeholder PNG/WAV *bytes* are
  declared as such by §11 itself.

`pyproject.toml` force-includes this directory into the wheel as `mediacore/_fixtures`,
so a consumer that installs `mediacore` from a git URL can still load the fixture.
