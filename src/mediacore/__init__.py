"""mediaCore — the shared recorded-media `Release` contract. Everything a consumer
needs is re-exported here (`from mediacore import Release, read_bundle,
normalize_text, …`); submodule paths are an implementation detail, this surface is
what `INTEGRATION.md` §3–5 pins."""

from __future__ import annotations

__version__ = "0.1.0"

from mediacore.bundle import (
    BUNDLE_MEDIA_DIRNAME,
    BUNDLE_RELEASE_FILENAME,
    BundleError,
    bundle_entries,
    read_bundle,
    sha256_file,
    write_bundle,
)
from mediacore.fixtures import (
    ITS_SAXY_SLUG,
    its_saxy_bundle,
)
from mediacore.normalize import (
    normalize_catno,
    normalize_text,
)
from mediacore.refs import (
    DISCOGS_ARTIST,
    DISCOGS_LABEL,
    DISCOGS_MASTER,
    DISCOGS_RELEASE,
    KNOWN_REF_KEYS,
    MUSICBRAINZ_ARTIST,
    MUSICBRAINZ_LABEL,
    MUSICBRAINZ_RECORDING,
    MUSICBRAINZ_RELEASE,
    MUSICBRAINZ_RELEASE_GROUP,
    REF_KEY_PATTERN,
    REF_KEY_RE,
    Refs,
    parse_ref_uri,
    ref_uri,
    validate_ref_key,
    validate_ref_value,
    validate_refs,
)
from mediacore.release import (
    SCHEMA_VERSION,
    ArtistRef,
    AudioFile,
    ContractModel,
    Credit,
    LabelRef,
    Link,
    MediaFile,
    MediaKind,
    Medium,
    Provenance,
    Release,
    Track,
)

__all__ = [
    "BUNDLE_MEDIA_DIRNAME",
    "BUNDLE_RELEASE_FILENAME",
    "BundleError",
    "DISCOGS_ARTIST",
    "DISCOGS_LABEL",
    "DISCOGS_MASTER",
    "DISCOGS_RELEASE",
    "ITS_SAXY_SLUG",
    "KNOWN_REF_KEYS",
    "MUSICBRAINZ_ARTIST",
    "MUSICBRAINZ_LABEL",
    "MUSICBRAINZ_RECORDING",
    "MUSICBRAINZ_RELEASE",
    "MUSICBRAINZ_RELEASE_GROUP",
    "REF_KEY_PATTERN",
    "REF_KEY_RE",
    "SCHEMA_VERSION",
    "ArtistRef",
    "AudioFile",
    "ContractModel",
    "Credit",
    "LabelRef",
    "Link",
    "MediaFile",
    "MediaKind",
    "Medium",
    "Provenance",
    "Refs",
    "Release",
    "Track",
    "__version__",
    "bundle_entries",
    "its_saxy_bundle",
    "normalize_catno",
    "normalize_text",
    "parse_ref_uri",
    "read_bundle",
    "ref_uri",
    "sha256_file",
    "validate_ref_key",
    "validate_ref_value",
    "validate_refs",
    "write_bundle",
]
