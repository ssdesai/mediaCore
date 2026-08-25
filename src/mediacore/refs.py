"""Refs: evidence recorded by an external source about an entity (INTEGRATION.md §4).

A ref key is `"<authority>:<entity>"` and a ref value is what that source calls this
thing. **A ref is evidence, never identity.** Every `refs` field in the contract is
optional and may be empty: a release, artist, label or credit may carry refs from
Discogs, from MusicBrainz, from a local pipeline, from several at once, or from none —
a band that exists only on a sleeve is as valid as one with a Discogs id. Nothing here
requires a ref, privileges a source, or treats a ref as a key: refs uniqueness is not
enforced and two entities may legitimately carry the same one. A consumer uses refs
only to *propose* candidates and to *retain evidence* on the entity it links or
creates; the human confirms every match.

Known keys are constants below; an unknown but well-formed key is accepted on purpose —
that is the contract's extension point — though a consumer only proposes candidates
from keys it knows.

`isrc:recording` and `barcode:release` are reserved but not yet produced by anything.
They carry entity segments because the key grammar requires one — an earlier draft of
§4 listed them as bare `isrc` / `barcode`, which the grammar cannot express; the
grammar was kept and the keys were given segments rather than the other way round.
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
ISRC_RECORDING = "isrc:recording"
BARCODE_RELEASE = "barcode:release"

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
        ISRC_RECORDING,
        BARCODE_RELEASE,
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
