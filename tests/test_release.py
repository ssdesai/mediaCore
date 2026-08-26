"""Pins the `Release` contract (INTEGRATION.md §3). Every field a consumer repo
reads is asserted here; a field that round-trips wrong here is a bug in three repos.
"""

from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from mediacore import (
    ArtistRef,
    AudioFile,
    Credit,
    LabelRef,
    Link,
    MediaFile,
    Provenance,
    Release,
    Track,
)

from conftest import (
    SAMPLE_ARTIST_REFS,
    SAMPLE_EXPORTED_AT,
    SAMPLE_RECORD_ID,
    SAMPLE_RELEASE_REFS,
    make_audio_file,
    make_media_file,
    make_release,
)


def full_release() -> Release:
    """A Release exercising every field."""
    return make_release(
        refs=dict(SAMPLE_RELEASE_REFS),
        provenance=[
            Provenance(
                kind="vinylcat",
                id=SAMPLE_RECORD_ID,
                label="Test 1",
                exported_at=SAMPLE_EXPORTED_AT,
            ),
            Provenance(
                kind="humanmap",
                id="id2",
                label="Test 2",
                exported_at=SAMPLE_EXPORTED_AT,
            ),
        ],
        title="IT'S SAXY",
        artists=[
            {"name": "The Duke's Combo", "refs": dict(SAMPLE_ARTIST_REFS)},
            {"name": "Feature Artist", "sort_name": "Artist, Feature", "refs": {}},
        ],
        labels=[
            {
                "name": "Atlantic Records",
                "catalogue_number": "SD-1234",
                "refs": {"discogs:label": "123456"},
            }
        ],
        year=1974,
        released="1974-06",
        country="US",
        medium="vinyl",
        format="LP",
        genres=["Jazz", "Soul"],
        styles=["Hard Bop", "Funk"],
        tracks=[
            Track(
                position="A1",
                title="First Track",
                duration="3:45",
                credits=[],
            ),
            Track(
                position="A2",
                title="Second Track",
                duration="4:20",
                credits=[
                    Credit(
                        role="saxophone",
                        name="Johnny Hodges",
                        refs={"discogs:artist": "654321"},
                    )
                ],
            ),
        ],
        credits=[
            Credit(
                role="producer",
                name="Duke Ellington",
                refs={},
            )
        ],
        notes="A classic recording",
        tags=["classic", "essential"],
        media=[
            make_media_file(b"cover image", kind="photo", role="cover"),
            make_media_file(b"back image", kind="external_photo", role="back"),
        ],
        audio=[
            make_audio_file(b"audio data", position="A1"),
        ],
        links=[
            Link(label="Discogs", url="https://www.discogs.com/release/123456", refs={}),
            Link(label="MusicBrainz", url="https://musicbrainz.org/release/456789", refs={}),
        ],
    )


def test_release_round_trips() -> None:
    full = full_release()
    dumped = full.model_dump(mode="json")

    # Verify dump is plain JSON (no datetime objects)
    json_str = json.dumps(dumped)
    assert isinstance(json_str, str)

    # Verify round-trip
    reloaded = Release.model_validate(dumped)
    assert reloaded == full


def test_schema_version_defaults_to_one() -> None:
    release = make_release()
    assert release.schema_version == 1

    dumped = release.model_dump(mode="json")
    reloaded = Release.model_validate(dumped)
    assert reloaded.schema_version == 1


def test_provenance_datetime_round_trips() -> None:
    full = full_release()
    dumped = full.model_dump(mode="json")

    # Verify datetime is serialized as string in JSON
    assert isinstance(dumped["provenance"][0]["exported_at"], str)

    reloaded = Release.model_validate(dumped)
    assert reloaded.provenance[0].exported_at == SAMPLE_EXPORTED_AT
    assert reloaded.provenance[0].exported_at.tzinfo is not None


def test_optional_fields_default() -> None:
    release = make_release()

    # Optional scalar fields default to None
    assert release.year is None
    assert release.released is None
    assert release.country is None
    assert release.format is None
    assert release.notes is None

    # List fields default to empty
    assert release.labels == []
    assert release.genres == []
    assert release.styles == []
    assert release.tracks == []
    assert release.credits == []
    assert release.tags == []
    assert release.media == []
    assert release.audio == []
    assert release.links == []

    # Refs default to empty dict on nested models
    artist = ArtistRef(name="Solo Artist")
    assert artist.refs == {}
    assert artist.sort_name is None


def test_extra_fields_forbidden_on_release() -> None:
    with pytest.raises(ValidationError):
        make_release(surprise="x")


@pytest.mark.parametrize(
    "constructor,kwargs",
    [
        (Track, {"position": "A1", "title": "t", "surprise": "x"}),
        (Credit, {"role": "r", "name": "n", "surprise": "x"}),
        (ArtistRef, {"name": "n", "surprise": "x"}),
        (LabelRef, {"name": "n", "surprise": "x"}),
        (Link, {"label": "l", "url": "u", "surprise": "x"}),
        (Provenance, {"kind": "k", "id": "i", "exported_at": SAMPLE_EXPORTED_AT, "surprise": "x"}),
    ],
)
def test_extra_fields_forbidden_on_nested_models(constructor, kwargs) -> None:
    with pytest.raises(ValidationError):
        constructor(**kwargs)


def test_at_least_one_artist_required() -> None:
    with pytest.raises(ValidationError):
        make_release(artists=[])


@pytest.mark.parametrize("medium", ["vinyl", "cd", "cassette", "digital", "other"])
def test_medium_vocabulary_is_closed_valid(medium: str) -> None:
    release = make_release(medium=medium)
    assert release.medium == medium


@pytest.mark.parametrize("medium", ["8-track", "Vinyl"])
def test_medium_vocabulary_is_closed_invalid(medium: str) -> None:
    with pytest.raises(ValidationError):
        make_release(medium=medium)


@pytest.mark.parametrize("kind", ["photo", "external_photo"])
def test_media_kind_vocabulary_is_closed_valid(kind: str) -> None:
    media = make_media_file(b"data", kind=kind)
    assert media.kind == kind


def test_media_kind_vocabulary_is_closed_invalid() -> None:
    with pytest.raises(ValidationError):
        make_media_file(b"data", kind="scan")


@pytest.mark.parametrize(
    "model_class,kwargs",
    [
        (ArtistRef, {"name": "n", "refs": {"Discogs:artist": "1"}}),
        (LabelRef, {"name": "n", "refs": {"Discogs:artist": "1"}}),
        (Credit, {"role": "r", "name": "n", "refs": {"Discogs:artist": "1"}}),
        (MediaFile, {
            "kind": "photo",
            "sha256": "abc123",
            "file": "f",
            "mime": "image/png",
            "refs": {"Discogs:artist": "1"},
        }),
        (Link, {"label": "l", "url": "u", "refs": {"Discogs:artist": "1"}}),
    ],
)
def test_nested_refs_invalid_key(model_class, kwargs) -> None:
    with pytest.raises(ValidationError):
        model_class(**kwargs)


@pytest.mark.parametrize(
    "model_class,kwargs",
    [
        (Credit, {"role": "r", "name": "n", "refs": {"discogs:artist": ""}}),
    ],
)
def test_nested_refs_empty_value(model_class, kwargs) -> None:
    with pytest.raises(ValidationError):
        model_class(**kwargs)


def test_release_refs_invalid_key() -> None:
    with pytest.raises(ValidationError):
        make_release(refs={"Discogs:release": "1"})


def test_track_credits_are_nested_models() -> None:
    full = full_release()
    track_with_credit = full.tracks[1]

    assert len(track_with_credit.credits) == 1
    credit = track_with_credit.credits[0]
    assert isinstance(credit, Credit)
    assert credit.role == "saxophone"
    assert credit.name == "Johnny Hodges"
    assert credit.refs == {"discogs:artist": "654321"}

    # Verify refs survive round-trip
    dumped = full.model_dump(mode="json")
    reloaded = Release.model_validate(dumped)
    reloaded_credit = reloaded.tracks[1].credits[0]
    assert reloaded_credit.refs == {"discogs:artist": "654321"}


@pytest.mark.parametrize(
    "model_class,kwargs",
    [
        (AudioFile, {"track_position": "A1", "sha256": "abc", "file": "f.wav", "size_bytes": 100}),
        (MediaFile, {"kind": "photo", "sha256": "abc", "file": "f.png"}),
        (Track, {"position": "A1"}),
        (Link, {"label": "x"}),
    ],
)
def test_required_fields_are_required(model_class, kwargs) -> None:
    with pytest.raises(ValidationError):
        model_class(**kwargs)


def test_release_without_title_required() -> None:
    with pytest.raises(ValidationError):
        Release(
            refs={},
            provenance=[],
            artists=[{"name": "n"}],
            medium="vinyl",
        )


# --- `file` is validated against `sha256` (INTEGRATION.md §5) -------------------
#
# Both consumers accept bundles as untrusted browser uploads and then join `file` onto
# a directory path, so a traversal here is a filesystem write outside the bundle.

VALID_DIGEST = "a" * 64
OTHER_DIGEST = "b" * 64
VALID_MEDIA_PATH = f"media/{VALID_DIGEST}.png"
VALID_AUDIO_PATH = f"media/{VALID_DIGEST}.wav"


def media_file(**overrides):
    fields = {
        "kind": "photo",
        "sha256": VALID_DIGEST,
        "file": VALID_MEDIA_PATH,
        "mime": "image/png",
    }
    fields.update(overrides)
    return MediaFile(**fields)


def audio_file(**overrides):
    fields = {
        "track_position": "A1",
        "sha256": VALID_DIGEST,
        "file": VALID_AUDIO_PATH,
        "format": "wav",
        "size_bytes": 1,
    }
    fields.update(overrides)
    return AudioFile(**fields)


def test_bundle_file_path_accepted_when_it_names_its_own_digest():
    assert media_file().file == VALID_MEDIA_PATH
    assert audio_file().file == VALID_AUDIO_PATH
    # A multi-character alphanumeric extension is fine; so is a digit-only one.
    assert media_file(file=f"media/{VALID_DIGEST}.jpeg").file.endswith(".jpeg")
    assert audio_file(file=f"media/{VALID_DIGEST}.mp3").file.endswith(".mp3")


@pytest.mark.parametrize(
    ("bad_file", "why"),
    [
        (f"media/{OTHER_DIGEST}.png", "digest belongs to another entry"),
        (f"{VALID_DIGEST}.png", "no media/ prefix"),
        (f"/media/{VALID_DIGEST}.png", "absolute path"),
        (f"media/../{VALID_DIGEST}.png", "parent traversal inside the prefix"),
        (f"../media/{VALID_DIGEST}.png", "parent traversal before the prefix"),
        (f"media/sub/{VALID_DIGEST}.png", "extra path segment"),
        (f"media/{VALID_DIGEST}.png/x", "trailing segment"),
        (f"media/{VALID_DIGEST}", "no extension"),
        (f"media/{VALID_DIGEST}.", "empty extension"),
        (f"media/{VALID_DIGEST}.PNG", "uppercase extension"),
        (f"media/{VALID_DIGEST}.extensionlong", "extension over eight characters"),
        (f"media/{VALID_DIGEST}.p-g", "non-alphanumeric extension"),
        (f"Media/{VALID_DIGEST}.png", "wrong-case directory"),
        ("", "empty"),
    ],
)
def test_bundle_file_path_rejected(bad_file, why):
    with pytest.raises(ValidationError):
        media_file(file=bad_file)
    with pytest.raises(ValidationError):
        audio_file(file=bad_file)


@pytest.mark.parametrize(
    "bad_digest",
    [
        "a" * 63,
        "a" * 65,
        "A" * 64,
        "g" * 64,
        "../../etc/passwd",
        "",
    ],
)
def test_sha256_must_be_a_lowercase_hex_digest(bad_digest):
    with pytest.raises(ValidationError):
        media_file(sha256=bad_digest, file=f"media/{bad_digest}.png")
    with pytest.raises(ValidationError):
        audio_file(sha256=bad_digest, file=f"media/{bad_digest}.wav")


def test_bundle_file_validation_survives_a_round_trip():
    entry = media_file()
    assert MediaFile.model_validate(entry.model_dump(mode="json")) == entry

    payload = entry.model_dump(mode="json")
    payload["file"] = f"media/{OTHER_DIGEST}.png"
    with pytest.raises(ValidationError):
        MediaFile.model_validate(payload)


def test_audio_file_size_bytes_must_be_non_negative():
    with pytest.raises(ValidationError):
        audio_file(size_bytes=-1)


def test_audio_file_size_bytes_zero_is_allowed():
    assert audio_file(size_bytes=0).size_bytes == 0


# --- Content addressing: one sha256 must name one file across a Release (§5) --------
#
# `MediaFile`/`AudioFile` each validate `file` against their own `sha256` above; this
# is the cross-entry counterpart, which needs the whole `media`/`audio` lists to check
# and so can only live on `Release`, the same way the orphan-audio check below does.


def test_release_accepts_two_entries_that_share_a_sha256_and_the_same_file():
    digest = "c" * 64
    file = f"media/{digest}.wav"
    release = make_release(
        tracks=[Track(position="A1", title="t1"), Track(position="A2", title="t2")],
        audio=[
            AudioFile(
                track_position="A1", sha256=digest, file=file, format="wav", size_bytes=1
            ),
            AudioFile(
                track_position="A2", sha256=digest, file=file, format="wav", size_bytes=1
            ),
        ],
    )
    assert len(release.audio) == 2


def test_release_rejects_two_media_entries_sharing_a_sha256_with_different_file():
    digest = "d" * 64
    with pytest.raises(ValidationError):
        make_release(
            media=[
                MediaFile(
                    kind="photo", sha256=digest, file=f"media/{digest}.png", mime="image/png"
                ),
                MediaFile(
                    kind="photo", sha256=digest, file=f"media/{digest}.jpg", mime="image/jpeg"
                ),
            ]
        )


def test_release_rejects_two_audio_entries_sharing_a_sha256_with_different_file():
    digest = "d" * 64
    with pytest.raises(ValidationError):
        make_release(
            tracks=[Track(position="A1", title="t1"), Track(position="A2", title="t2")],
            audio=[
                AudioFile(
                    track_position="A1",
                    sha256=digest,
                    file=f"media/{digest}.wav",
                    format="wav",
                    size_bytes=1,
                ),
                AudioFile(
                    track_position="A2",
                    sha256=digest,
                    file=f"media/{digest}.mp3",
                    format="mp3",
                    size_bytes=1,
                ),
            ],
        )


def test_release_rejects_a_media_and_an_audio_entry_sharing_a_sha256_with_different_file():
    digest = "d" * 64
    with pytest.raises(ValidationError):
        make_release(
            tracks=[Track(position="A1", title="t1")],
            media=[
                MediaFile(
                    kind="photo", sha256=digest, file=f"media/{digest}.png", mime="image/png"
                )
            ],
            audio=[
                AudioFile(
                    track_position="A1",
                    sha256=digest,
                    file=f"media/{digest}.wav",
                    format="wav",
                    size_bytes=1,
                )
            ],
        )


def test_release_duplicate_sha256_different_file_rejected_via_model_validate():
    """The review's escalation: two entries sharing a sha256 with different `file`
    values used to round-trip cleanly through `model_validate`. That is exactly the
    path a hand-edited `release.json` takes as an untrusted upload, so the rejection
    must hold there too, not only when both entries are built through `Release(...)`
    in the same call."""
    digest = "e" * 64
    release = make_release(
        tracks=[Track(position="A1", title="t1")],
        audio=[
            AudioFile(
                track_position="A1",
                sha256=digest,
                file=f"media/{digest}.wav",
                format="wav",
                size_bytes=1,
            )
        ],
    )
    payload = release.model_dump(mode="json")
    payload["media"] = [
        {
            "kind": "photo",
            "sha256": digest,
            "file": f"media/{digest}.png",
            "mime": "image/png",
            "refs": {},
        }
    ]
    with pytest.raises(ValidationError):
        Release.model_validate(payload)


# --- Every AudioFile.track_position must match a Track.position (§3) ----------------
#
# An audio file joined to no track is an orphan; the review found nothing rejected it.


def test_release_accepts_audio_whose_track_position_matches_a_track():
    release = make_release(
        tracks=[Track(position="A1", title="t1")],
        audio=[make_audio_file(b"a1 audio", position="A1")],
    )
    assert release.audio[0].track_position == "A1"


def test_release_rejects_audio_whose_track_position_matches_no_track():
    with pytest.raises(ValidationError, match="A1"):
        make_release(
            tracks=[Track(position="A2", title="t2")],
            audio=[make_audio_file(b"orphan audio", position="A1")],
        )


def test_release_rejects_audio_when_there_are_no_tracks_at_all():
    with pytest.raises(ValidationError):
        make_release(audio=[make_audio_file(b"orphan audio", position="A1")])
