"""Shared builders for the mediacore test suite.

Owned by plan 01 of the release-contract batch: tests/test_release.py and
tests/test_bundle.py use these by name rather than defining their own.
"""

from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from mediacore import AudioFile, MediaFile, Provenance, Release

# A fixed instant, so nothing in the suite depends on the clock.
SAMPLE_EXPORTED_AT = datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC)
SAMPLE_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
SAMPLE_RELEASE_REFS = {"discogs:release": "16853262"}
SAMPLE_ARTIST_REFS = {"discogs:artist": "5682050"}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_release(**overrides: Any) -> Release:
    """A minimal valid Release — one artist, no files — with any field overridden."""
    fields: dict[str, Any] = {
        "refs": dict(SAMPLE_RELEASE_REFS),
        "provenance": [
            Provenance(
                kind="vinylcat",
                id=SAMPLE_RECORD_ID,
                label="Test",
                exported_at=SAMPLE_EXPORTED_AT,
            )
        ],
        "title": "IT'S SAXY",
        "artists": [{"name": "The Duke's Combo", "refs": dict(SAMPLE_ARTIST_REFS)}],
        "medium": "vinyl",
    }
    fields.update(overrides)
    return Release(**fields)


def make_media_file(data: bytes, *, ext: str = "png", **overrides: Any) -> MediaFile:
    digest = sha256_bytes(data)
    fields: dict[str, Any] = {
        "kind": "photo",
        "role": "label_a",
        "sha256": digest,
        "file": f"media/{digest}.{ext}",
        "mime": "image/png",
    }
    fields.update(overrides)
    return MediaFile(**fields)


def make_audio_file(
    data: bytes, *, position: str = "A1", fmt: str = "wav", **overrides: Any
) -> AudioFile:
    digest = sha256_bytes(data)
    fields: dict[str, Any] = {
        "track_position": position,
        "sha256": digest,
        "file": f"media/{digest}.{fmt}",
        "format": fmt,
        "size_bytes": len(data),
    }
    fields.update(overrides)
    return AudioFile(**fields)


def write_source_files(directory: Path, payloads: dict[str, bytes]) -> dict[str, Path]:
    """Write each payload under `directory`; return the {sha256: path} mapping
    `write_bundle` takes as its `files` argument."""
    directory.mkdir(parents=True, exist_ok=True)
    mapping: dict[str, Path] = {}
    for name, data in payloads.items():
        path = directory / name
        path.write_bytes(data)
        mapping[sha256_bytes(data)] = path
    return mapping
