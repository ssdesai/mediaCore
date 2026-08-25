"""Black-box acceptance test for the release-contract batch.

Loads `fixtures/its-saxy/` through the package's public API and asserts every
fact `INTEGRATION.md` §11 states about that bundle. This file is expected to be
RED until `scripts/make_fixture_its_saxy.py` has been run to generate the fixture
bundle — that script cannot be run by build executors (no bash); the level-2 gate
and the batch's verify plan run it.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from datetime import UTC, datetime
from pathlib import Path

import pytest

from mediacore import BundleError, Release, its_saxy_bundle, read_bundle

DISCOGS_RELEASE_ID = "16853262"
DISCOGS_ARTIST_ID = "5682050"
DISCOGS_LABEL_ID = "1504762"
VINYLCAT_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
FIXTURE_EXPORTED_AT = datetime(2026, 8, 25, 0, 0, 0, tzinfo=UTC)
RELEASE_FILENAME = "release.json"
MEDIA_DIRNAME = "media"
EXPECTED_TITLE = "IT'S SAXY"
EXPECTED_ARTIST_NAME = "The Duke's Combo"
EXPECTED_ARTIST_SORT_NAME = "Duke's Combo, The"
EXPECTED_LABEL_NAME = "A. A. E."
EXPECTED_CATALOGUE_NUMBER = "SAAE 1012"
EXPECTED_COUNTRY = "South Africa"
EXPECTED_MEDIUM = "vinyl"
EXPECTED_FORMAT = "Vinyl, LP, Album"
EXPECTED_GENRES = [
    "Jazz",
    "Rock",
    "Funk / Soul",
    "Blues",
    "Folk, World, & Country",
    "Stage & Screen",
]
EXPECTED_TRACKS = [
    ("A1", "LOVE GROWS"),
    ("A2", "ALL I HAVE TO DO IS DREAM"),
    ("A3", "JY IS MY LIEFLING"),
    ("A4", "I'LL NEVER FALL IN LOVE AGAIN"),
    ("A5", "DOMINIQUE"),
    ("A6", "THERESA"),
    ("B1", "SUGAR SUGAR"),
    ("B2", "Love Theme From Romeo And Juliet"),
    ("B3", "SEEMAN"),
    ("B4", "MAKE ME AN ISLAND"),
    ("B5", "MA BELLE AMIE"),
    ("B6", "LOVE IS A BEAUTIFUL SONG"),
]
EXPECTED_TRACK_CREDITS = {
    "B5": ("Written-By", "peter tetteroo", "282874"),
    "B6": ("Written-By", "Terry Dempsey", "1033325"),
}
EXPECTED_PHOTO_ROLES = ["label_a", "label_b"]
EXPECTED_EXTERNAL_PHOTO_COUNT = 2
EXPECTED_PHOTO_MIME = "image/png"
# §11: two photos plus two external photos; one audio file per track, twelve in all.
EXPECTED_MEDIA_COUNT = len(EXPECTED_PHOTO_ROLES) + EXPECTED_EXTERNAL_PHOTO_COUNT
EXPECTED_AUDIO_COUNT = len(EXPECTED_TRACKS)
EXPECTED_AUDIO_FORMAT = "wav"
EXPECTED_SCHEMA_VERSION = 1
EXPECTED_PROVENANCE_KIND = "vinylcat"
EXPECTED_COLLECTION_LABEL = "Test"
EXPECTED_LINKS = [
    (
        "Discogs: IT'S SAXY",
        "https://www.discogs.com/release/16853262-The-Dukes-Combo-Its-Saxy",
        {"discogs:release": "16853262"},
    ),
    (
        "Discogs: The Duke's Combo",
        "https://www.discogs.com/artist/5682050",
        {"discogs:artist": "5682050"},
    ),
    (
        "Discogs: A. A. E.",
        "https://www.discogs.com/label/1504762",
        {"discogs:label": "1504762"},
    ),
    (
        "Discogs: peter tetteroo",
        "https://www.discogs.com/artist/282874",
        {"discogs:artist": "282874"},
    ),
    (
        "Discogs: Terry Dempsey",
        "https://www.discogs.com/artist/1033325",
        {"discogs:artist": "1033325"},
    ),
]


@pytest.fixture(scope="module")
def bundle_dir() -> Path:
    return its_saxy_bundle()


@pytest.fixture(scope="module")
def release(bundle_dir: Path) -> Release:
    return read_bundle(bundle_dir)


def test_bundle_path_exists(bundle_dir: Path) -> None:
    assert bundle_dir.is_dir()
    assert (bundle_dir / RELEASE_FILENAME).is_file()
    assert (bundle_dir / MEDIA_DIRNAME).is_dir()


def test_bundle_reads_and_verifies(release: Release) -> None:
    assert release.schema_version == EXPECTED_SCHEMA_VERSION


def test_every_bundle_file_hashes_to_its_name(bundle_dir: Path, release: Release) -> None:
    for entry in [*release.media, *release.audio]:
        ext = entry.file.rsplit(".", 1)[-1]
        assert entry.file == f"{MEDIA_DIRNAME}/{entry.sha256}.{ext}"
        path = bundle_dir / entry.file
        assert path.is_file()
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry.sha256


def test_media_directory_has_no_orphans(bundle_dir: Path, release: Release) -> None:
    on_disk = {p.name for p in (bundle_dir / MEDIA_DIRNAME).iterdir()}
    referenced = {Path(entry.file).name for entry in [*release.media, *release.audio]}
    assert on_disk == referenced


def test_release_json_round_trips(bundle_dir: Path, release: Release) -> None:
    on_disk = json.loads((bundle_dir / RELEASE_FILENAME).read_text())
    assert on_disk == release.model_dump(mode="json")


def test_identity_matches_integration_md(release: Release) -> None:
    assert release.refs == {"discogs:release": DISCOGS_RELEASE_ID}
    assert "discogs:master" not in release.refs

    assert len(release.provenance) == 1
    provenance = release.provenance[0]
    assert provenance.kind == EXPECTED_PROVENANCE_KIND
    assert provenance.id == VINYLCAT_RECORD_ID
    assert provenance.label == EXPECTED_COLLECTION_LABEL
    assert provenance.exported_at == FIXTURE_EXPORTED_AT

    assert release.title == EXPECTED_TITLE
    assert release.country == EXPECTED_COUNTRY
    assert release.medium == EXPECTED_MEDIUM
    assert release.format == EXPECTED_FORMAT
    assert release.year is None
    assert release.released is None

    assert len(release.artists) == 1
    artist = release.artists[0]
    assert artist.name == EXPECTED_ARTIST_NAME
    assert artist.sort_name == EXPECTED_ARTIST_SORT_NAME
    assert artist.refs == {"discogs:artist": DISCOGS_ARTIST_ID}

    assert len(release.labels) == 1
    label = release.labels[0]
    assert label.name == EXPECTED_LABEL_NAME
    assert label.catalogue_number == EXPECTED_CATALOGUE_NUMBER
    assert label.refs == {"discogs:label": DISCOGS_LABEL_ID}


def test_genres_and_styles(release: Release) -> None:
    assert release.genres == EXPECTED_GENRES
    assert release.styles == []


def test_tracks_match_integration_md(release: Release) -> None:
    assert [(t.position, t.title) for t in release.tracks] == EXPECTED_TRACKS
    for track in release.tracks:
        assert track.duration is None

    credited = {t.position: t for t in release.tracks if t.credits}
    assert set(credited) == set(EXPECTED_TRACK_CREDITS)
    for position, (role, name, artist_id) in EXPECTED_TRACK_CREDITS.items():
        credits = credited[position].credits
        assert len(credits) == 1
        credit = credits[0]
        assert credit.role == role
        assert credit.name == name
        assert credit.refs["discogs:artist"] == artist_id


def test_media_matches_integration_md(release: Release) -> None:
    assert len(release.media) == EXPECTED_MEDIA_COUNT

    photos = [m for m in release.media if m.kind == "photo"]
    assert [m.role for m in photos] == EXPECTED_PHOTO_ROLES
    for photo in photos:
        assert photo.mime == EXPECTED_PHOTO_MIME
        assert photo.source_url is None
        assert photo.refs == {}

    externals = [m for m in release.media if m.kind == "external_photo"]
    assert len(externals) == EXPECTED_EXTERNAL_PHOTO_COUNT
    for external in externals:
        assert external.source_url
        assert external.refs == {"discogs:release": DISCOGS_RELEASE_ID}


def test_audio_matches_integration_md(bundle_dir: Path, release: Release) -> None:
    assert len(release.audio) == EXPECTED_AUDIO_COUNT
    assert [a.track_position for a in release.audio] == [t[0] for t in EXPECTED_TRACKS]
    for audio in release.audio:
        assert audio.format == EXPECTED_AUDIO_FORMAT
        assert audio.size_bytes == (bundle_dir / audio.file).stat().st_size

    shas = [a.sha256 for a in release.audio]
    assert len(shas) == len(set(shas))


def test_links_match_integration_md(release: Release) -> None:
    assert [(link.label, link.url, link.refs) for link in release.links] == EXPECTED_LINKS


def test_release_level_credits_notes_and_tags_are_empty(release: Release) -> None:
    assert release.credits == []
    assert release.notes is None
    assert release.tags == []


def test_verify_rejects_a_corrupted_bundle(bundle_dir: Path, tmp_path: Path) -> None:
    copy = tmp_path / "its-saxy-corrupted"
    shutil.copytree(bundle_dir, copy)

    media_dir = copy / MEDIA_DIRNAME
    target = next(media_dir.iterdir())
    target.write_bytes(b"these are definitely not the original bytes")

    with pytest.raises(BundleError) as exc_info:
        read_bundle(copy)
    assert target.name in str(exc_info.value)

    unverified = read_bundle(copy, verify=False)
    assert isinstance(unverified, Release)
