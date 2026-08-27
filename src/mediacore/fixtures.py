"""Locating the packaged contract fixtures (INTEGRATION.md §11).

Consumer test suites load the IT'S SAXY bundle through `its_saxy_bundle()` rather than
by path, because where it lives depends on how mediacore was installed: a source
checkout (or an editable install) keeps it at the repo root under `fixtures/`, while a
wheel built from this project carries it as package data under `mediacore/_fixtures/`
(the force-include in `pyproject.toml`). The checkout is preferred, so a developer who
regenerates the fixture sees the new bytes and not a copy installed earlier.
"""

from __future__ import annotations

from pathlib import Path

from mediacore.bundle import BUNDLE_RELEASE_FILENAME, read_bundle
from mediacore.store import VINYLCAT_PROVENANCE_KIND, BundleEntry, open_store

ITS_SAXY_SLUG = "its-saxy"
# The repo-root fixtures directory, and its name inside an installed wheel.
FIXTURES_DIRNAME = "fixtures"
PACKAGED_FIXTURES_DIRNAME = "_fixtures"
# src/mediacore/fixtures.py -> parents[0] src/mediacore, [1] src, [2] the repo root.
REPO_ROOT_PARENT_INDEX = 2


def its_saxy_bundle() -> Path:
    """The `its-saxy` bundle directory. Raises `FileNotFoundError` when it has not been
    generated (`scripts/make_fixture_its_saxy.py`)."""
    module_path = Path(__file__).resolve()
    checkout = (
        module_path.parents[REPO_ROOT_PARENT_INDEX] / FIXTURES_DIRNAME / ITS_SAXY_SLUG
    )
    packaged = module_path.parent / PACKAGED_FIXTURES_DIRNAME / ITS_SAXY_SLUG
    for candidate in (checkout, packaged):
        if (candidate / BUNDLE_RELEASE_FILENAME).is_file():
            return candidate
    raise FileNotFoundError(
        f"the {ITS_SAXY_SLUG} fixture bundle is not present; looked in {checkout} and "
        f"{packaged}. In a source checkout, generate it with "
        f"`python scripts/make_fixture_its_saxy.py`."
    )


def seed_its_saxy_store(store_uri: str) -> BundleEntry:
    """Seed the committed IT'S SAXY bundle into the store at `store_uri`
    (`INTEGRATION.md` §5.1 "Fixture"). Idempotent: a dev stack restarts and must be
    able to re-seed without failing, so an existing entry for this record's
    `record_id` and `exported_at` is returned as-is rather than put again. A
    `StoreError` from an unusable `store_uri` or a `BundleError` from a damaged
    checkout both propagate."""
    bundle = its_saxy_bundle()
    release = read_bundle(bundle)
    files = {entry.sha256: bundle / entry.file for entry in (*release.media, *release.audio)}
    vinylcat = next(
        entry for entry in release.provenance if entry.kind == VINYLCAT_PROVENANCE_KIND
    )
    store = open_store(store_uri)
    for entry in store.list(all_versions=True):
        if entry.record_id == vinylcat.id and entry.exported_at == vinylcat.exported_at:
            return entry
    return store.put(release, files)
