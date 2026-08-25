"""Bundle reader and writer (INTEGRATION.md §5). A bundle is a directory —
`release.json` plus `media/<sha256>.<ext>`, one file per `MediaFile` and `AudioFile`.
It is written wholesale and never edited: exporting again replaces the directory."""

from __future__ import annotations

import hashlib
import json
import shutil
from collections.abc import Iterator, Mapping
from pathlib import Path

from pydantic import ValidationError

from mediacore.release import Release

BUNDLE_RELEASE_FILENAME = "release.json"
BUNDLE_MEDIA_DIRNAME = "media"
# release.json is committed in the fixture and read by humans; indent it and end with
# a newline so a diff of a regenerated bundle is readable.
BUNDLE_JSON_INDENT = 2
# Hash in chunks so a large audio file is never held in memory whole.
HASH_CHUNK_BYTES = 1 << 20


class BundleError(Exception):
    """A bundle is missing, malformed, or does not match its own hashes."""


def sha256_file(path: Path | str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(HASH_CHUNK_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_entries(release: Release) -> Iterator[tuple[str, str]]:
    for media_file in release.media:
        yield media_file.sha256, media_file.file
    for audio_file in release.audio:
        yield audio_file.sha256, audio_file.file


def read_bundle(path: Path | str, *, verify: bool = True) -> Release:
    root = Path(path)
    if not root.is_dir():
        raise BundleError(f"not a bundle directory: {root}")

    release_path = root / BUNDLE_RELEASE_FILENAME
    if not release_path.is_file():
        raise BundleError(f"missing {BUNDLE_RELEASE_FILENAME}: {release_path}")

    try:
        payload = json.loads(release_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise BundleError(f"invalid JSON in {release_path}") from exc

    try:
        release = Release.model_validate(payload)
    except ValidationError as exc:
        raise BundleError(f"invalid release payload in {release_path}") from exc

    if verify:
        for sha256, relative in bundle_entries(release):
            entry_path = root / relative
            if not entry_path.is_file():
                raise BundleError(f"missing bundle file: {relative}")
            found = sha256_file(entry_path)
            if found != sha256:
                raise BundleError(
                    f"hash mismatch for {relative}: expected {sha256}, found {found}"
                )

    return release


def write_bundle(release: Release, dest: Path | str, files: Mapping[str, Path]) -> Path:
    root = Path(dest)

    copies: list[tuple[Path, Path]] = []
    for sha256, relative in bundle_entries(release):
        source = files.get(sha256)
        if source is None:
            raise BundleError(f"no source file provided for {relative} ({sha256})")
        if not Path(source).is_file():
            raise BundleError(f"source path is not a file: {source}")
        found = sha256_file(source)
        if found != sha256:
            raise BundleError(
                f"source hash mismatch for {relative}: expected {sha256}, found {found}"
            )
        copies.append((Path(source), root / relative))

    _clear_destination(root)

    (root / BUNDLE_MEDIA_DIRNAME).mkdir(parents=True, exist_ok=True)
    for source, target in copies:
        shutil.copyfile(source, target)

    release_json = (
        json.dumps(release.model_dump(mode="json"), indent=BUNDLE_JSON_INDENT, ensure_ascii=False)
        + "\n"
    )
    (root / BUNDLE_RELEASE_FILENAME).write_text(release_json, encoding="utf-8")

    return root


def _clear_destination(root: Path) -> None:
    if not root.exists():
        root.mkdir(parents=True)
        return

    if not root.is_dir():
        raise BundleError(f"destination exists and is not a directory: {root}")

    entries = list(root.iterdir())
    if not entries:
        return

    if not (root / BUNDLE_RELEASE_FILENAME).is_file():
        raise BundleError(
            f"refusing to overwrite a directory that is not a bundle: {root}"
        )

    for entry in entries:
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()
