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
