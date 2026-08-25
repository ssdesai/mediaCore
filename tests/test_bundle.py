"""Pins the bundle format and its failure modes (INTEGRATION.md §5)."""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from mediacore import BundleError, Release, bundle, read_bundle, sha256_file, write_bundle

from conftest import (
    make_audio_file,
    make_media_file,
    make_release,
    sha256_bytes,
    write_source_files,
)

PHOTO_BYTES = b"fake-png-bytes"
AUDIO_BYTES = b"fake-wav-bytes"
PHOTO_EXT = "png"
AUDIO_EXT = "wav"
PHOTO_SOURCE_NAME = "photo.png"
AUDIO_SOURCE_NAME = "audio.wav"
RELEASE_FILENAME = "release.json"
MEDIA_DIRNAME = "media"
BUNDLE_DIRNAME = "bundle"


def built(tmp_path: Path) -> tuple[Release, dict[str, Path]]:
    """A release with one photo and one audio file, plus its {sha256: source path} mapping."""
    sources = write_source_files(
        tmp_path / "sources",
        {PHOTO_SOURCE_NAME: PHOTO_BYTES, AUDIO_SOURCE_NAME: AUDIO_BYTES},
    )
    media_file = make_media_file(PHOTO_BYTES, ext=PHOTO_EXT)
    audio_file = make_audio_file(AUDIO_BYTES, fmt=AUDIO_EXT)
    release = make_release(media=[media_file], audio=[audio_file])
    return release, sources


def test_write_then_read_round_trips(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME

    write_bundle(release, dest, sources)

    assert read_bundle(dest) == release


def test_write_bundle_returns_the_destination(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME

    result = write_bundle(release, dest, sources)

    assert isinstance(result, Path)
    assert result == dest


def test_write_bundle_creates_the_documented_layout(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME

    write_bundle(release, dest, sources)

    release_json_path = dest / RELEASE_FILENAME
    assert release_json_path.exists()
    assert json.loads(release_json_path.read_text()) == release.model_dump(mode="json")

    media_dir = dest / MEDIA_DIRNAME
    media_files = sorted(media_dir.iterdir())
    photo_sha = sha256_bytes(PHOTO_BYTES)
    audio_sha = sha256_bytes(AUDIO_BYTES)
    expected_names = {f"{photo_sha}.{PHOTO_EXT}", f"{audio_sha}.{AUDIO_EXT}"}
    assert {p.name for p in media_files} == expected_names

    assert (media_dir / f"{photo_sha}.{PHOTO_EXT}").read_bytes() == PHOTO_BYTES
    assert (media_dir / f"{audio_sha}.{AUDIO_EXT}").read_bytes() == AUDIO_BYTES


def test_read_bundle_missing_release_json_raises(tmp_path):
    dest = tmp_path / BUNDLE_DIRNAME
    dest.mkdir()

    with pytest.raises(BundleError, match=re.escape(RELEASE_FILENAME)):
        read_bundle(dest)


def test_read_bundle_on_a_missing_directory_raises(tmp_path):
    with pytest.raises(BundleError):
        read_bundle(tmp_path / "does-not-exist")


def test_read_bundle_on_a_file_raises(tmp_path):
    path = tmp_path / "not-a-directory"
    path.write_text("nope")

    with pytest.raises(BundleError):
        read_bundle(path)


def test_read_bundle_missing_media_file_raises_naming_it(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    photo_sha = sha256_bytes(PHOTO_BYTES)
    missing_name = f"{photo_sha}.{PHOTO_EXT}"
    (dest / MEDIA_DIRNAME / missing_name).unlink()

    with pytest.raises(BundleError, match=re.escape(missing_name)):
        read_bundle(dest)


def test_read_bundle_hash_mismatch_raises_naming_it(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    photo_sha = sha256_bytes(PHOTO_BYTES)
    target_name = f"{photo_sha}.{PHOTO_EXT}"
    (dest / MEDIA_DIRNAME / target_name).write_bytes(b"different-bytes")

    with pytest.raises(BundleError, match=re.escape(target_name)):
        read_bundle(dest)


def test_read_bundle_verify_false_skips_file_checks(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    photo_sha = sha256_bytes(PHOTO_BYTES)
    (dest / MEDIA_DIRNAME / f"{photo_sha}.{PHOTO_EXT}").unlink()

    result = read_bundle(dest, verify=False)

    assert result == release


@pytest.mark.parametrize(
    "content",
    [json.dumps({"nonsense": True}), "not json at all {{{"],
    ids=["invalid-schema", "not-json"],
)
def test_read_bundle_rejects_invalid_release_json(tmp_path, content):
    dest = tmp_path / BUNDLE_DIRNAME
    dest.mkdir()
    (dest / RELEASE_FILENAME).write_text(content)

    with pytest.raises(BundleError):
        read_bundle(dest)


def test_write_bundle_requires_every_sha256_in_files(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    audio_sha = sha256_bytes(AUDIO_BYTES)
    del sources[audio_sha]

    with pytest.raises(BundleError, match=re.escape(audio_sha)):
        write_bundle(release, dest, sources)


def test_write_bundle_rejects_a_source_whose_bytes_do_not_hash_to_its_key(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    photo_sha = sha256_bytes(PHOTO_BYTES)
    tampered = tmp_path / "sources" / "tampered.png"
    tampered.write_bytes(b"not-the-right-bytes")
    sources[photo_sha] = tampered

    with pytest.raises(BundleError):
        write_bundle(release, dest, sources)


def test_write_bundle_replaces_an_existing_bundle(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    photo_sha = sha256_bytes(PHOTO_BYTES)
    second_release = make_release(media=[make_media_file(PHOTO_BYTES, ext=PHOTO_EXT)])
    second_sources = {photo_sha: sources[photo_sha]}

    write_bundle(second_release, dest, second_sources)

    media_files = list((dest / MEDIA_DIRNAME).iterdir())
    assert len(media_files) == 1
    assert media_files[0].name == f"{photo_sha}.{PHOTO_EXT}"
    assert read_bundle(dest) == second_release


def test_write_bundle_refuses_a_non_bundle_destination(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    dest.mkdir()
    unrelated = dest / "unrelated.txt"
    unrelated.write_text("do not delete me")

    with pytest.raises(BundleError):
        write_bundle(release, dest, sources)

    assert unrelated.exists()
    assert unrelated.read_text() == "do not delete me"


def test_write_bundle_accepts_an_empty_existing_destination(tmp_path):
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    dest.mkdir()

    write_bundle(release, dest, sources)

    assert read_bundle(dest) == release


def test_sha256_file_matches_hashlib(tmp_path):
    path = tmp_path / "sample.bin"
    path.write_bytes(PHOTO_BYTES)

    assert sha256_file(path) == sha256_bytes(PHOTO_BYTES)


def test_release_with_no_files_round_trips(tmp_path):
    release = make_release()
    dest = tmp_path / BUNDLE_DIRNAME

    write_bundle(release, dest, {})

    assert read_bundle(dest) == release
    media_dir = dest / MEDIA_DIRNAME
    assert media_dir.exists()
    assert list(media_dir.iterdir()) == []


# --- Atomicity: a failed write never damages what is already there (review finding) ---


def test_write_bundle_leaves_an_existing_bundle_intact_when_a_hash_is_wrong(tmp_path):
    """A bad hash on the *second* entry must not cost the caller the bundle already
    at `dest`. The pre-flight loop catches it before anything is staged."""
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    decoy = tmp_path / "decoy.wav"
    decoy.write_bytes(b"different-bytes-entirely")
    broken = dict(sources)
    broken[sha256_bytes(AUDIO_BYTES)] = decoy

    with pytest.raises(BundleError):
        write_bundle(release, dest, broken)

    assert read_bundle(dest) == release


def test_write_bundle_leaves_an_existing_bundle_intact_when_a_copy_fails(
    tmp_path, monkeypatch
):
    """The mid-write case the staging directory exists for: the pre-flight loop has
    passed and files are being written when the filesystem gives out."""
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    real_copyfile = bundle.shutil.copyfile
    calls = {"n": 0}

    def failing_copyfile(source, target, **kwargs):
        calls["n"] += 1
        if calls["n"] == 2:
            raise OSError("no space left on device")
        return real_copyfile(source, target, **kwargs)

    monkeypatch.setattr(bundle.shutil, "copyfile", failing_copyfile)

    with pytest.raises(OSError, match="no space left on device"):
        write_bundle(release, dest, sources)

    monkeypatch.undo()
    assert read_bundle(dest) == release
    assert len(list((dest / MEDIA_DIRNAME).iterdir())) == 2


def test_write_bundle_leaves_no_staging_directory_behind(tmp_path):
    """Staging and backup directories are siblings of `dest`; neither may survive a
    successful write or a refused one."""
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME

    write_bundle(release, dest, sources)
    write_bundle(release, dest, sources)

    assert [entry.name for entry in sorted(tmp_path.iterdir())] == [
        BUNDLE_DIRNAME,
        "sources",
    ]


def test_write_bundle_creates_nothing_when_the_destination_is_refused(tmp_path):
    """A refused destination is untouched, and no staging sibling is left over."""
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    dest.mkdir()
    stranger = dest / "not-a-bundle.txt"
    stranger.write_text("keep me")

    with pytest.raises(BundleError, match="not a bundle"):
        write_bundle(release, dest, sources)

    assert stranger.read_text() == "keep me"
    assert [entry.name for entry in sorted(dest.iterdir())] == ["not-a-bundle.txt"]
    assert [entry.name for entry in sorted(tmp_path.iterdir())] == [
        BUNDLE_DIRNAME,
        "sources",
    ]


def test_read_bundle_refuses_a_file_outside_the_media_directory(tmp_path):
    """Defence in depth: the models forbid such a `file`, so this is reached only by
    editing release.json on disk — exactly what an untrusted upload can do."""
    release, sources = built(tmp_path)
    dest = tmp_path / BUNDLE_DIRNAME
    write_bundle(release, dest, sources)

    outsider = tmp_path / "outside.png"
    outsider.write_bytes(PHOTO_BYTES)

    payload = json.loads((dest / RELEASE_FILENAME).read_text())
    payload["media"][0]["file"] = f"{MEDIA_DIRNAME}/../../outside.png"
    (dest / RELEASE_FILENAME).write_text(json.dumps(payload))

    with pytest.raises(BundleError):
        read_bundle(dest)
