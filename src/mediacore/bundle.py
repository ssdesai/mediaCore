"""Bundle reader and writer (INTEGRATION.md §5). A bundle is a directory —
`release.json` plus `media/<sha256>.<ext>`, one file per `MediaFile` and `AudioFile`.
It is written wholesale and never edited: exporting again replaces the directory.

`write_bundle` stages into a sibling temporary directory and swaps it into place, so an
interrupted export leaves either the previous bundle intact or nothing at all — never a
half-written directory that the "is this a bundle?" guard would then refuse to
overwrite."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
from collections.abc import Iterator, Mapping
from pathlib import Path

from pydantic import ValidationError

from mediacore.release import BUNDLE_MEDIA_DIRNAME, Release

BUNDLE_RELEASE_FILENAME = "release.json"
# release.json is committed in the fixture and read by humans; indent it and end with
# a newline so a diff of a regenerated bundle is readable.
BUNDLE_JSON_INDENT = 2
# Hash in chunks so a large audio file is never held in memory whole.
HASH_CHUNK_BYTES = 1 << 20
# Names for the two directories the atomic swap needs beside `dest`. Both are derived
# from one mkdtemp token, so neither can collide with a concurrent export.
STAGING_PREFIX_TEMPLATE = ".{name}.tmp-"
REPLACED_SUFFIX = ".replaced"


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


def _entry_path(root: Path, relative: str) -> Path:
    """Resolve `relative` under `<root>/media/`, refusing anything that escapes it.

    `MediaFile`/`AudioFile` already validate that `file` is `media/<sha256>.<ext>`, so
    this cannot trigger through the models. It is defence in depth for the one thing
    the contract cannot promise: both consumers take bundles from a browser upload and
    join this value onto a directory, and a `..` or absolute path silently escapes a
    `pathlib` join. Resolving also collapses a symlinked media file pointing outward.
    """
    media_root = (root / BUNDLE_MEDIA_DIRNAME).resolve()
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(media_root)
    except ValueError as exc:
        raise BundleError(
            f"bundle file escapes {BUNDLE_MEDIA_DIRNAME}/: {relative!r}"
        ) from exc
    return candidate


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
            entry_path = _entry_path(root, relative)
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

    sources: list[tuple[Path, str, str]] = []
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
        sources.append((Path(source), relative, sha256))

    _check_destination_replaceable(root)

    root.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            dir=root.parent, prefix=STAGING_PREFIX_TEMPLATE.format(name=root.name)
        )
    )
    # Derived from staging's unique token, so it cannot collide and never pre-exists —
    # os.replace onto a directory requires the target to be absent or empty.
    replaced = staging.with_name(staging.name + REPLACED_SUFFIX)

    try:
        _populate(staging, release, sources)
        _swap_into_place(staging, root, replaced)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        shutil.rmtree(replaced, ignore_errors=True)
        raise

    shutil.rmtree(replaced, ignore_errors=True)
    return root


def _populate(
    staging: Path, release: Release, sources: list[tuple[Path, str, str]]
) -> None:
    """Fill a staging directory with a complete, hash-verified bundle."""
    (staging / BUNDLE_MEDIA_DIRNAME).mkdir(parents=True, exist_ok=True)
    for source, relative, sha256 in sources:
        target = _entry_path(staging, relative)
        shutil.copyfile(source, target)
        found = sha256_file(target)
        if found != sha256:
            raise BundleError(
                f"copy of {relative} does not match its hash: expected {sha256}, "
                f"found {found}"
            )

    release_json = (
        json.dumps(
            release.model_dump(mode="json"), indent=BUNDLE_JSON_INDENT, ensure_ascii=False
        )
        + "\n"
    )
    (staging / BUNDLE_RELEASE_FILENAME).write_text(release_json, encoding="utf-8")


def _swap_into_place(staging: Path, root: Path, replaced: Path) -> None:
    """Move `staging` onto `root`, keeping any existing bundle until the last moment.

    Either the new bundle is in place or the old one still is: the only window is
    between the two renames, and a failure there puts the old one back."""
    had_previous = root.exists()
    if had_previous:
        os.replace(root, replaced)
    try:
        os.replace(staging, root)
    except OSError:
        if had_previous and not root.exists():
            os.replace(replaced, root)
        raise


def _check_destination_replaceable(root: Path) -> None:
    """Raise unless `root` is absent, empty, or an existing bundle. Never mutates:
    a mistyped destination must survive the call that refused it."""
    if not root.exists():
        return

    if not root.is_dir():
        raise BundleError(f"destination exists and is not a directory: {root}")

    if not any(root.iterdir()):
        return

    if not (root / BUNDLE_RELEASE_FILENAME).is_file():
        raise BundleError(
            f"refusing to overwrite a directory that is not a bundle: {root}"
        )
