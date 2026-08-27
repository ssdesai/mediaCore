# Seeding IT'S SAXY into a store, and the docs

Feature `bundle-store-plans` (plan 9 of 12). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store of §5.1 — `open_store(uri)` returning a `BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding.

Add `seed_its_saxy_store` to `src/mediacore/fixtures.py`, give it a command-line
front door, and bring the repo's documentation up to date with the new module.

Depends on: levels 1 and 2 (`04-store-core-file-sonnet.md`,
`07-store-s3-sonnet.md`). **The contract is on disk: read `src/mediacore/store.py`,
`src/mediacore/fixtures.py` and `tests/test_store_fixture.py` before writing.** This
plan is what turns `tests/test_store_fixture.py` green; it closes level 3 and the
batch.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- `INTEGRATION.md` §5.1 → "Fixture": "Each dev stack seeds *IT'S SAXY* into a local
  `file://` store, so the store path is exercised by tests and not only by upload."
- Already on disk: `mediacore.fixtures.its_saxy_bundle() -> Path` (the committed
  `fixtures/its-saxy/` bundle), `mediacore.bundle.read_bundle(path, *, verify=True)`,
  and `mediacore.store`'s `open_store`, `BundleEntry` and `StoreError`.
- `put(release, files)` takes `files` as a `{sha256: Path}` mapping; the pair for the
  committed fixture is `read_bundle(its_saxy_bundle())` plus
  `{entry.sha256: bundle / entry.file for entry in (*release.media, *release.audio)}`.
  `tests/conftest.py`'s `its_saxy_source()` already does exactly this — read it and
  keep the two consistent.
- **You cannot run anything.** This plan writes a seeding function and a script; the
  script is run by a human setting up a dev stack, and the function is exercised by
  `tests/test_store_fixture.py` when the gate runs the suite. Do not create any file
  under `fixtures/its-saxy/` or write a store tree into the repo — a store is a runtime
  directory outside the checkout, and `plans/gate.sh`'s `fixture idempotent` section
  fails on any change under `fixtures/`.
- CONVENTIONS.md: named constants at the top of each file; every folder's `README.md`
  stays accurate after the change.

## Files

- Modify `src/mediacore/fixtures.py`
- Modify `src/mediacore/__init__.py`
- Create `scripts/seed_bundle_store.py`
- Modify `scripts/README.md`
- Modify `fixtures/README.md`
- Modify `src/mediacore/README.md`
- Modify `README.md` (repo root)
- Modify `plans/PROJECT_FACTS.md`

## `src/mediacore/fixtures.py`

Add `seed_its_saxy_store(store_uri: str) -> BundleEntry`: read the committed bundle
with `its_saxy_bundle()` and `read_bundle`, build the `{sha256: Path}` mapping from
`release.media` and `release.audio`, and `put` it into `open_store(store_uri)`.

**It is idempotent.** A dev stack restarts, and re-seeding must not fail: before
putting, take `list(all_versions=True)` and return the existing entry when one already
has this record's `record_id` and `exported_at`. Everything else — a `StoreError` from
an unusable URI, a `BundleError` from a damaged checkout — propagates.

It lives here rather than in `store.py` because it is a fixture affordance;
`store.py`'s public surface stays the three methods §5.1 names.

## `src/mediacore/__init__.py`

Re-export `seed_its_saxy_store` beside `its_saxy_bundle`, and add it to `__all__` in
the order that file already uses.

## `scripts/seed_bundle_store.py`

A small stdlib-only CLI in the style of `scripts/make_fixture_its_saxy.py` — read that
file for its argument handling and `main()` shape. It takes one argument, the store
URI, calls `seed_its_saxy_store`, and prints the resulting entry's `uri` so the operator
can paste it. No default URI: a store address is a deployment decision, and a script
that guesses one writes a bundle somewhere nobody asked for. Missing argument → usage
message and a non-zero exit; `StoreError` → the message and a non-zero exit, not a
traceback.

## The READMEs

- `scripts/README.md` — a bullet for `seed_bundle_store.py`: what it does, that it
  takes the store URI as its only argument and refuses to guess one, and that it is run
  by hand when setting up a dev stack for WP7b/7c/7d, never by `plans/gate.sh`.
- `fixtures/README.md` — say that `its-saxy/` is also the bundle
  `mediacore.seed_its_saxy_store()` puts into a `file://` (or `s3://`) store, and that
  seeding writes **outside** the checkout: nothing under `fixtures/` is ever written by
  the store.
- `src/mediacore/README.md` — extend the `fixtures.py` entry with
  `seed_its_saxy_store(store_uri) -> BundleEntry`, its idempotence, and that it is the
  §5.1 "Fixture" bullet's implementation.
- Root `README.md` — the `Contents` table's `src/mediacore/` row still stands; add the
  bundle store to the opening paragraph's list of what the package is (schema, refs,
  fold, bundle reader/writer, **bundle store**, fixture), and note under `Consuming`
  that `s3://` support needs `mediacore[s3]`.
- `plans/PROJECT_FACTS.md` — add a short **Bundle store** block under `Types`, for the
  next plan author in this repo: `mediacore.store` implements §5.1; `BundleEntry`'s
  five fields; that `record_id` and `exported_at` are read from the `provenance` entry
  whose `kind` is `"vinylcat"` and never parsed out of a path; the
  `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/` layout; that nothing
  overwrites or deletes; the `StoreError` / `BundleError` split; that `boto3` is the
  optional `mediacore[s3]` extra and `moto[s3]` is the dev-only test double, so the
  suite needs no network or credentials; and that `seed_its_saxy_store` writes only
  outside the checkout. Also update the `Tests` list with the three new test files.
