"""Locating the packaged contract fixtures (INTEGRATION.md §11) and seeding them into a
bundle store (§5.1).

Consumer test suites load the IT'S SAXY bundle through `its_saxy_bundle()` rather than
by path, because where it lives depends on how mediacore was installed: a source
checkout (or an editable install) keeps it at the repo root under `fixtures/`, while a
wheel built from this project carries it as package data under `mediacore/_fixtures/`
(the force-include in `pyproject.toml`). The checkout is preferred, so a developer who
regenerates the fixture sees the new bytes and not a copy installed earlier.

`seed_its_saxy_store()` is the other half: every dev stack seeds the same bundle into a
local `file://` store, so the store path is exercised by tests and not only by upload.
It ships in the package because the stacks that call it (vinylCatalogue, humanNetworkMap,
musicMap) install `mediacore` as a wheel and have no access to this repo's `scripts/`.
"""

from __future__ import annotations

from pathlib import Path

from mediacore.bundle import BUNDLE_RELEASE_FILENAME, bundle_entries, read_bundle
from mediacore.store import BundleEntry, open_store

ITS_SAXY_SLUG = "its-saxy"
# The repo-root fixtures directory, and its name inside an installed wheel.
FIXTURES_DIRNAME = "fixtures"
PACKAGED_FIXTURES_DIRNAME = "_fixtures"
# src/mediacore/fixtures.py -> parents[0] src/mediacore, [1] src, [2] the repo root.
REPO_ROOT_PARENT_INDEX = 2
# The export that produced the fixture bundle: the store keys on the first provenance
# entry (`mediacore.store`), so seeding compares against the same one.
FIXTURE_PROVENANCE_INDEX = 0


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
    """Put the committed IT'S SAXY bundle into the store at `store_uri` and return its
    entry (INTEGRATION.md §5.1, "Fixture").

    Idempotent: a stack that re-runs its seed gets the entry that is already there.
    Re-putting it would be refused anyway — the version key is the fixture's fixed
    `exported_at`, and nothing in `mediacore` overwrites an entry — so the check is what
    makes seeding safe to repeat, not a way around that rule.
    """
    bundle = its_saxy_bundle()
    release = read_bundle(bundle)
    store = open_store(store_uri)

    record_id = release.provenance[FIXTURE_PROVENANCE_INDEX].id
    exported_at = release.provenance[FIXTURE_PROVENANCE_INDEX].exported_at
    for entry in store.list(all_versions=True):
        if entry.record_id == record_id and entry.exported_at == exported_at:
            return entry

    files = {sha256: bundle / relative for sha256, relative in bundle_entries(release)}
    return store.put(release, files)
