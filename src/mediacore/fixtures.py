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

from mediacore.bundle import BUNDLE_RELEASE_FILENAME

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
