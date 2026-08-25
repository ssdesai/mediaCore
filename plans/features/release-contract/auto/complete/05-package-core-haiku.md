# Package scaffold: `pyproject.toml`, `normalize.py`, `refs.py`

Feature `release-contract` (plan 5 of 12). The batch delivers the whole `mediacore`
contract package — the `Release` schema, refs, the normalize fold, the bundle
reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Create the packaging metadata and the two leaf modules everything else imports.

Depends on: nothing. Plans 06 and 07 add the remaining modules and
`src/mediacore/README.md`; do not create that README here.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- src layout: the package is `src/mediacore/`, built with **hatchling**, Python ≥ 3.11.
  The only runtime dependency is `pydantic>=2.7`; dev extras are `pytest` and `ruff`.
- `fixtures/` at the repo root is force-included into the wheel as `mediacore/_fixtures`
  so a consumer that pip-installs from git can still reach the test fixture. Hatchling
  fails the build if that source directory does not exist, which is why
  `fixtures/README.md` is created **here** rather than in the fixture plan (plan 09) —
  the level-1 gate runs `pip install -e ".[dev]"` before plan 09 has run.
- `src/mediacore/__init__.py` is written by plan 07 and re-exports everything. Do not
  create it here — creating an `__init__.py` without the re-exports would make plan 07's
  job ambiguous.
- Ref-key grammar (INTEGRATION.md §4): `^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$`, values are
  non-empty strings.
- `normalize.py` must be the same algorithm as `vinylcat.normalize` in the
  vinylCatalogue repo. It is reproduced verbatim below; do not "improve" it.

## Files

- Create `pyproject.toml`
- Create `src/mediacore/normalize.py`
- Create `src/mediacore/refs.py`
- Create `fixtures/README.md`

## `pyproject.toml`

```toml
[build-system]
requires = ["hatchling>=1.24"]
build-backend = "hatchling.build"

[project]
name = "mediacore"
version = "0.1.0"
description = "The shared recorded-media Release contract: schema, identity refs, name normalisation, bundle I/O, and one real-world test fixture."
readme = "README.md"
requires-python = ">=3.11"
authors = [{ name = "Sahil Desai" }]
dependencies = ["pydantic>=2.7"]

[project.optional-dependencies]
dev = ["pytest>=8.0", "ruff>=0.6"]

[project.urls]
Homepage = "https://github.com/ssdesai/mediaCore"

[tool.hatch.build.targets.wheel]
packages = ["src/mediacore"]

# The fixture bundle lives at the repo root, not inside the package, but a consumer
# that installs from a git URL still has to reach it through `its_saxy_bundle()`.
[tool.hatch.build.targets.wheel.force-include]
"fixtures" = "mediacore/_fixtures"

[tool.hatch.build.targets.sdist]
include = ["src/mediacore", "fixtures", "scripts", "tests", "README.md", "INTEGRATION.md"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP"]

[tool.ruff.lint.isort]
known-first-party = ["mediacore"]
known-local-folder = ["conftest"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra"
```

## `src/mediacore/normalize.py`

Verbatim — this is `vinylcat.normalize`'s algorithm, and the two must not drift:

```python
"""The shared name-matching fold (INTEGRATION.md §4).

Byte-for-byte the same algorithm as `vinylcat.normalize` in the vinylCatalogue repo.
Every consumer falls back to `normalize_text` equality when a release carries no
authority refs, so a divergence here silently stops matching entities that the source
repo considers identical. `tests/test_normalize.py` pins the samples both sides agree
on.
"""

from __future__ import annotations

import re
import unicodedata

_WHITESPACE_RE = re.compile(r"\s+")
_NON_ALNUM_RE = re.compile(r"[^A-Z0-9]")


def normalize_text(value: str | None) -> str:
    """Uppercase, NFKD accent-strip, whitespace collapse."""
    if not value:
        return ""
    stripped = "".join(
        c for c in unicodedata.normalize("NFKD", value) if not unicodedata.combining(c)
    )
    return _WHITESPACE_RE.sub(" ", stripped.upper()).strip()


def normalize_catno(value: str | None) -> str:
    """`normalize_text` plus stripping every non-alphanumeric character, so
    `"PB 41447"` and `"PB-41447"` compare equal.
    """
    return _NON_ALNUM_RE.sub("", normalize_text(value))
```

## `src/mediacore/refs.py`

```python
"""Authority-keyed identity refs (INTEGRATION.md §4).

A ref key is `"<authority>:<entity>"` and a ref value is that authority's own id as a
string. Known keys are constants below; an unknown but well-formed key is accepted on
purpose — that is the contract's extension point — though a consumer only *matches* on
keys it knows.

§4's table also lists `isrc` and `barcode` as reserved. Neither is expressible under
the key grammar that same section states (both lack an `<entity>` segment), so neither
is defined here; the grammar is implemented as written rather than widened to fit two
keys nothing uses yet.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Annotated

from pydantic import AfterValidator

# Ref-key grammar (INTEGRATION.md §4): lowercase authority, then a lowercase entity
# which may carry digits and hyphens ("musicbrainz:release-group").
REF_KEY_PATTERN = r"^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$"
REF_KEY_RE = re.compile(REF_KEY_PATTERN)

# A ref URI is "<authority>:<entity>:<value>" — three segments. The value may itself
# contain the separator, so parsing splits at most twice and keeps the rest.
REF_URI_SEPARATOR = ":"
REF_URI_MAX_SPLITS = 2

DISCOGS_RELEASE = "discogs:release"
DISCOGS_MASTER = "discogs:master"
DISCOGS_ARTIST = "discogs:artist"
DISCOGS_LABEL = "discogs:label"
MUSICBRAINZ_RELEASE = "musicbrainz:release"
MUSICBRAINZ_RELEASE_GROUP = "musicbrainz:release-group"
MUSICBRAINZ_ARTIST = "musicbrainz:artist"
MUSICBRAINZ_LABEL = "musicbrainz:label"
MUSICBRAINZ_RECORDING = "musicbrainz:recording"

KNOWN_REF_KEYS = frozenset(
    {
        DISCOGS_RELEASE,
        DISCOGS_MASTER,
        DISCOGS_ARTIST,
        DISCOGS_LABEL,
        MUSICBRAINZ_RELEASE,
        MUSICBRAINZ_RELEASE_GROUP,
        MUSICBRAINZ_ARTIST,
        MUSICBRAINZ_LABEL,
        MUSICBRAINZ_RECORDING,
    }
)


def validate_ref_key(key: object) -> str:
    if not isinstance(key, str) or REF_KEY_RE.match(key) is None:
        raise ValueError(
            f"invalid ref key {key!r}: expected '<authority>:<entity>' "
            f"matching {REF_KEY_PATTERN}"
        )
    return key


def validate_ref_value(key: object, value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(
            f"invalid ref value for {key!r}: expected a non-empty string, got {value!r}"
        )
    return value


def validate_refs(refs: Mapping[str, str]) -> dict[str, str]:
    """Validate every key and value; return a new dict."""
    validated: dict[str, str] = {}
    for key, value in refs.items():
        validated[validate_ref_key(key)] = validate_ref_value(key, value)
    return validated


Refs = Annotated[dict[str, str], AfterValidator(validate_refs)]


def ref_uri(key: str, value: str) -> str:
    """`ref_uri("discogs:artist", "5682050") -> "discogs:artist:5682050"` — the
    cross-app link form (INTEGRATION.md §4)."""
    return f"{validate_ref_key(key)}{REF_URI_SEPARATOR}{validate_ref_value(key, value)}"


def parse_ref_uri(uri: str) -> tuple[str, str]:
    """Inverse of `ref_uri`, returning `(key, value)`. Raises `ValueError` on anything
    malformed."""
    if not isinstance(uri, str):
        raise ValueError(f"invalid ref URI {uri!r}: expected a string")
    parts = uri.split(REF_URI_SEPARATOR, REF_URI_MAX_SPLITS)
    if len(parts) != REF_URI_MAX_SPLITS + 1:
        raise ValueError(
            f"invalid ref URI {uri!r}: expected '<authority>:<entity>:<value>'"
        )
    authority, entity, value = parts
    key = f"{authority}{REF_URI_SEPARATOR}{entity}"
    return validate_ref_key(key), validate_ref_value(key, value)
```

## `fixtures/README.md`

New folder — create its README. `fixtures/its-saxy/` itself is **generated**, not
written by hand: do not create any file under it.

```markdown
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

`pyproject.toml` force-includes this directory into the wheel as `mediacore/_fixtures`,
so a consumer that installs `mediacore` from a git URL can still load the fixture.
```
