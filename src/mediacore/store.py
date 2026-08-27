"""URI-addressed bundle store (INTEGRATION.md §5.1). Where bundles sit between the
source and the consumers, addressed by a URI so the local→hosted move is configuration
and not code. `file://` is §5's bundle folder generalised to a directory of bundle
directories; `s3://` is the same layout under a key prefix. Entries are versioned by
`exported_at` and are never overwritten or deleted.
"""

from __future__ import annotations

import json
import re
import tempfile
from abc import ABC, abstractmethod
from collections.abc import Mapping
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

from pydantic import ConfigDict, ValidationError

from mediacore.bundle import (
    BUNDLE_MEDIA_DIRNAME,
    BUNDLE_RELEASE_FILENAME,
    read_bundle,
    write_bundle,
)
from mediacore.normalize import normalize_text
from mediacore.release import ContractModel, Release

# Store URI schemes
STORE_SCHEME_FILE = "file"
STORE_SCHEME_S3 = "s3"
FILE_SCHEME_LOCAL_HOSTS = ("", "localhost")

# Entry layout: <root>/<record ULID>/<exported_at, ISO basic>/<slug>/
ENTRY_TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"
ENTRY_DEPTH = 3
# The record id becomes one path segment, and it is a string off an untrusted
# release.json rather than a validated ULID, so it is checked before it is joined.
PATH_SEGMENT_SEPARATORS = ("/", "\\")
UNSAFE_PATH_SEGMENTS = ("", ".", "..")

# Provenance carrying the record identity (INTEGRATION.md §4)
VINYLCAT_PROVENANCE_KIND = "vinylcat"

# Slug: <artist>--<title>--<catalogue number>
SLUG_SEPARATOR = "--"
SLUG_WORD_SEPARATOR = "-"
SLUG_INVALID_PATTERN = r"[^a-z0-9]+"

# s3:// backend
S3_CLIENT_SERVICE_NAME = "s3"
S3_LIST_PAGE_SIZE = 1000
S3_KEY_SEPARATOR = "/"
S3_LIST_OBJECTS_PAGINATOR = "list_objects_v2"


class StoreError(Exception):
    """A problem with the store itself, as distinct from `BundleError`, which is a
    problem with a bundle."""


class BundleEntry(ContractModel):
    """One bundle in a store (INTEGRATION.md §5.1). Every field but `uri` is read from
    the entry's own release.json; `uri` is the address a consumer posts back."""

    model_config = ConfigDict(frozen=True)

    record_id: str
    exported_at: datetime
    slug: str
    uri: str
    schema_version: int


def _slug_segment(value: str) -> str:
    folded = normalize_text(value).lower()
    return re.sub(SLUG_INVALID_PATTERN, SLUG_WORD_SEPARATOR, folded).strip(SLUG_WORD_SEPARATOR)


def _slug(artist: str, title: str, catalogue_number: str | None) -> str:
    parts = [artist, title, *([catalogue_number] if catalogue_number else [])]
    segments = [segment for segment in (_slug_segment(part) for part in parts) if segment]
    return SLUG_SEPARATOR.join(segments)


def bundle_slug(release: Release) -> str:
    """The directory (or key segment) name for a release's bundle."""
    catalogue_number = next(
        (label.catalogue_number for label in release.labels if label.catalogue_number), None
    )
    return _slug(release.artists[0].name, release.title, catalogue_number)


def _entry_from_payload(payload: dict[str, Any], uri: str) -> BundleEntry:
    """Build an entry from a raw `release.json` payload without validating it as a
    `Release` — §5.1 requires `list` to surface an entry whose `schema_version` is
    newer than this install's, which `Release.model_validate` would refuse."""
    try:
        provenance = payload["provenance"]
        vinylcat = next(
            (entry for entry in provenance if entry.get("kind") == VINYLCAT_PROVENANCE_KIND),
            None,
        )
        if vinylcat is None:
            raise StoreError(f"{uri}: no {VINYLCAT_PROVENANCE_KIND!r} provenance entry")
        labels = payload.get("labels", [])
        catalogue_number = next(
            (label.get("catalogue_number") for label in labels if label.get("catalogue_number")),
            None,
        )
        return BundleEntry(
            record_id=vinylcat["id"],
            exported_at=vinylcat["exported_at"],
            slug=_slug(payload["artists"][0]["name"], payload["title"], catalogue_number),
            uri=uri,
            schema_version=payload["schema_version"],
        )
    except (KeyError, IndexError, TypeError, AttributeError, ValidationError) as exc:
        raise StoreError(f"{uri}: malformed release.json ({exc})") from exc


def _entry_from_release(release: Release, uri: str) -> BundleEntry:
    vinylcat = next(
        (entry for entry in release.provenance if entry.kind == VINYLCAT_PROVENANCE_KIND), None
    )
    if vinylcat is None:
        raise StoreError(
            f"release has no {VINYLCAT_PROVENANCE_KIND!r} provenance entry to address it by"
        )
    return BundleEntry(
        record_id=vinylcat.id,
        exported_at=vinylcat.exported_at,
        slug=bundle_slug(release),
        uri=uri,
        schema_version=release.schema_version,
    )


def _layout_parts(entry: BundleEntry) -> tuple[str, str, str]:
    record_id = entry.record_id
    if record_id in UNSAFE_PATH_SEGMENTS or any(
        separator in record_id for separator in PATH_SEGMENT_SEPARATORS
    ):
        raise StoreError(f"record id is not a single path segment: {record_id!r}")
    exported_at = entry.exported_at
    if exported_at.tzinfo is None:
        exported_at = exported_at.replace(tzinfo=UTC)
    exported_at = exported_at.astimezone(UTC)
    return record_id, exported_at.strftime(ENTRY_TIMESTAMP_FORMAT), entry.slug


def _selected(entries: list[BundleEntry], *, all_versions: bool) -> list[BundleEntry]:
    ordered = sorted(entries, key=lambda entry: entry.record_id)
    ordered.sort(key=lambda entry: entry.exported_at, reverse=True)
    if all_versions:
        return ordered
    seen: set[str] = set()
    selected: list[BundleEntry] = []
    for entry in ordered:
        if entry.record_id in seen:
            continue
        seen.add(entry.record_id)
        selected.append(entry)
    return selected


def _import_boto3() -> Any:
    """Import and return the `boto3` module. Its own function so `mediacore` imports
    cleanly without the `s3` extra, and so a test can monkeypatch it."""
    try:
        import boto3
    except ImportError as exc:
        raise StoreError("s3:// stores require boto3; install mediacore[s3]") from exc
    return boto3


class BundleStore(ABC):
    """A store of bundles, addressed by URI (INTEGRATION.md §5.1). Three methods and
    nothing else."""

    @abstractmethod
    def list(self, *, all_versions: bool = False) -> list[BundleEntry]: ...

    @abstractmethod
    def open(self, entry: BundleEntry | str, *, verify: bool = True) -> Release: ...

    @abstractmethod
    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry: ...


class FileBundleStore(BundleStore):
    """A directory of bundle directories under `root` (INTEGRATION.md §5.1): §5's
    bundle folder, generalised."""

    def __init__(self, root: Path, uri: str) -> None:
        self._root = root
        self._uri = uri

    def list(self, *, all_versions: bool = False) -> list[BundleEntry]:
        if not self._root.is_dir():
            raise StoreError(f"store root is not a directory: {self._root}")
        pattern = "/".join(["*"] * ENTRY_DEPTH) + f"/{BUNDLE_RELEASE_FILENAME}"
        entries: list[BundleEntry] = []
        for release_path in sorted(self._root.glob(pattern)):
            bundle_dir = release_path.parent
            uri = bundle_dir.as_uri()
            try:
                payload = json.loads(release_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                raise StoreError(
                    f"{uri}: invalid JSON in {BUNDLE_RELEASE_FILENAME} ({exc})"
                ) from exc
            entries.append(_entry_from_payload(payload, uri))
        return _selected(entries, all_versions=all_versions)

    def open(self, entry: BundleEntry | str, *, verify: bool = True) -> Release:
        uri = entry.uri if isinstance(entry, BundleEntry) else entry
        parts = urlsplit(uri)
        if parts.scheme != STORE_SCHEME_FILE or parts.netloc not in FILE_SCHEME_LOCAL_HOSTS:
            raise StoreError(f"not a file:// URI for this store: {uri}")
        # Resolved before the containment check, not after: a lexical `relative_to`
        # accepts `<root>/../../elsewhere`, and §5.1's consumer flow posts this URI back
        # from a browser (`preview-from-store {entry_uri}`), so the root is a boundary
        # an untrusted caller must not be able to step over. Resolving also collapses a
        # symlinked entry pointing outward, as `bundle._entry_path` does for media.
        path = Path(unquote(parts.path)).resolve()
        try:
            path.relative_to(self._root.resolve())
        except ValueError as exc:
            raise StoreError(f"not under this store's root {self._root}: {uri}") from exc
        if not (path / BUNDLE_RELEASE_FILENAME).is_file():
            raise StoreError(f"no bundle at {uri}")
        return read_bundle(path, verify=verify)

    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry:
        entry = _entry_from_release(release, uri="")
        record_id, timestamp, slug = _layout_parts(entry)
        dest = self._root / record_id / timestamp / slug
        if dest.exists():
            raise StoreError(f"entry already exists at {dest.as_uri()}: {slug}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        write_bundle(release, dest, files)
        return entry.model_copy(update={"uri": dest.as_uri()})


class S3BundleStore(BundleStore):
    """A bucket of bundle keys under `prefix` (INTEGRATION.md §5.1): the same layout as
    `FileBundleStore`, over a client built once from the ambient boto3 credential
    chain — `mediacore` takes no keys, region or endpoint of its own."""

    def __init__(self, bucket: str, prefix: str, uri: str) -> None:
        try:
            boto3 = _import_boto3()
        except ImportError as exc:
            raise StoreError("s3:// stores require boto3; install mediacore[s3]") from exc
        self._bucket = bucket
        self._prefix = prefix
        self._uri = uri
        self._client = boto3.client(S3_CLIENT_SERVICE_NAME)

    def _key(self, *parts: str) -> str:
        segments = [self._prefix, *parts] if self._prefix else list(parts)
        return S3_KEY_SEPARATOR.join(segments)

    def _entry_uri(self, record_id: str, timestamp: str, slug: str) -> str:
        return f"{STORE_SCHEME_S3}://{self._bucket}/{self._key(record_id, timestamp, slug)}"

    @property
    def _root_prefix(self) -> str:
        return f"{self._prefix}{S3_KEY_SEPARATOR}" if self._prefix else ""

    def list(self, *, all_versions: bool = False) -> list[BundleEntry]:
        root_prefix = self._root_prefix
        paginator = self._client.get_paginator(S3_LIST_OBJECTS_PAGINATOR)
        entries: list[BundleEntry] = []
        for page in paginator.paginate(
            Bucket=self._bucket,
            Prefix=root_prefix,
            PaginationConfig={"PageSize": S3_LIST_PAGE_SIZE},
        ):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if not key.endswith(f"{S3_KEY_SEPARATOR}{BUNDLE_RELEASE_FILENAME}"):
                    continue
                relative = key[len(root_prefix) :]
                parts = relative.split(S3_KEY_SEPARATOR)
                if len(parts) != ENTRY_DEPTH + 1:
                    continue
                record_id, timestamp, slug, _ = parts
                uri = self._entry_uri(record_id, timestamp, slug)
                body = self._client.get_object(Bucket=self._bucket, Key=key)["Body"].read()
                try:
                    payload = json.loads(body)
                except json.JSONDecodeError as exc:
                    raise StoreError(
                        f"{uri}: invalid JSON in {BUNDLE_RELEASE_FILENAME} ({exc})"
                    ) from exc
                entries.append(_entry_from_payload(payload, uri))
        return _selected(entries, all_versions=all_versions)

    def open(self, entry: BundleEntry | str, *, verify: bool = True) -> Release:
        uri = entry.uri if isinstance(entry, BundleEntry) else entry
        parts = urlsplit(uri)
        if parts.scheme != STORE_SCHEME_S3 or parts.netloc != self._bucket:
            raise StoreError(f"not an s3:// URI for this store: {uri}")
        key_prefix = unquote(parts.path).strip(S3_KEY_SEPARATOR)
        if self._prefix and key_prefix != self._prefix and not key_prefix.startswith(
            f"{self._prefix}{S3_KEY_SEPARATOR}"
        ):
            raise StoreError(f"not under this store's prefix {self._prefix!r}: {uri}")

        list_prefix = f"{key_prefix}{S3_KEY_SEPARATOR}"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            paginator = self._client.get_paginator(S3_LIST_OBJECTS_PAGINATOR)
            for page in paginator.paginate(
                Bucket=self._bucket,
                Prefix=list_prefix,
                PaginationConfig={"PageSize": S3_LIST_PAGE_SIZE},
            ):
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    relative = key[len(list_prefix) :]
                    if not relative or relative.endswith(S3_KEY_SEPARATOR):
                        continue  # a zero-length "directory marker", not a bundle file
                    # A key is arbitrary text, and the store is an untrusted path like
                    # an uploaded bundle: a `..` segment or a leading separator would
                    # otherwise put this write outside the temp directory.
                    target = tmp_path / relative
                    try:
                        target.resolve().relative_to(tmp_path.resolve())
                    except ValueError as exc:
                        raise StoreError(f"{uri}: key escapes the entry: {key}") from exc
                    target.parent.mkdir(parents=True, exist_ok=True)
                    body = self._client.get_object(Bucket=self._bucket, Key=key)["Body"].read()
                    target.write_bytes(body)
            # Keyed on `release.json`, not on "any object downloaded", so that a prefix
            # holding objects but no bundle raises the same `StoreError` the `file://`
            # backend raises rather than a `BundleError` from `read_bundle`.
            if not (tmp_path / BUNDLE_RELEASE_FILENAME).is_file():
                raise StoreError(f"no bundle at {uri}")
            return read_bundle(tmp_path, verify=verify)

    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry:
        entry = _entry_from_release(release, uri="")
        record_id, timestamp, slug = _layout_parts(entry)
        key_prefix = self._key(record_id, timestamp, slug)
        release_key = f"{key_prefix}{S3_KEY_SEPARATOR}{BUNDLE_RELEASE_FILENAME}"

        exists = True
        try:
            self._client.head_object(Bucket=self._bucket, Key=release_key)
        except self._client.exceptions.ClientError as exc:
            code = exc.response.get("Error", {}).get("Code")
            if code in ("404", "NoSuchKey", "NotFound"):
                exists = False
            else:
                raise
        if exists:
            uri = self._entry_uri(record_id, timestamp, slug)
            raise StoreError(f"entry already exists at {uri}: {slug}")

        with tempfile.TemporaryDirectory() as tmp:
            staging = Path(tmp)
            write_bundle(release, staging, files)
            media_dir = staging / BUNDLE_MEDIA_DIRNAME
            if media_dir.is_dir():
                for media_path in sorted(media_dir.iterdir()):
                    key = (
                        f"{key_prefix}{S3_KEY_SEPARATOR}{BUNDLE_MEDIA_DIRNAME}"
                        f"{S3_KEY_SEPARATOR}{media_path.name}"
                    )
                    self._client.put_object(
                        Bucket=self._bucket, Key=key, Body=media_path.read_bytes()
                    )
            release_bytes = (staging / BUNDLE_RELEASE_FILENAME).read_bytes()
            self._client.put_object(Bucket=self._bucket, Key=release_key, Body=release_bytes)

        return entry.model_copy(update={"uri": self._entry_uri(record_id, timestamp, slug)})


def open_store(uri: str) -> BundleStore:
    parts = urlsplit(uri)
    if parts.scheme == STORE_SCHEME_FILE:
        if parts.netloc not in FILE_SCHEME_LOCAL_HOSTS:
            raise StoreError(
                f"file:// store must be on this host, got host {parts.netloc!r}: {uri}"
            )
        root = Path(unquote(parts.path))
        # `file://` on its own parses to an empty path, which `Path` reads as the
        # process's working directory — a consumer configured that way would list its
        # own checkout instead of a store.
        if not root.is_absolute():
            raise StoreError(f"file:// store must name an absolute path: {uri}")
        return FileBundleStore(root, uri)
    if parts.scheme == STORE_SCHEME_S3:
        bucket = parts.netloc
        if not bucket:
            raise StoreError(f"s3:// store must name a bucket: {uri}")
        prefix = unquote(parts.path).strip(S3_KEY_SEPARATOR)
        return S3BundleStore(bucket, prefix, uri)
    if parts.scheme == "":
        raise StoreError(f"no scheme in store URI {uri!r}; write a file:// URI")
    raise StoreError(f"unsupported store URI scheme {parts.scheme!r}: {uri}")
