"""URI-addressed bundle store (INTEGRATION.md §5.1).

A *store* is where bundles sit between the source and its consumers, addressed by a URI
so moving from a laptop directory to a hosted bucket is configuration rather than code:

    file:///Users/…/bundles      a directory of bundle directories
    s3://<bucket>/<prefix>       the same layout under a key prefix

`open_store(uri)` picks the backend from the scheme; a `BundleStore` has three methods —
`list`, `open`, `put` — and consumers touch neither paths nor boto3 through it.

Two invariants from §5.1 shape everything here:

* **A re-export is a new version beside the old one, never an overwrite.** The key is
  `<root>/<record ULID>/<exported_at, ISO basic>/<slug>`, so a second export of the same
  record lands beside the first. `put` refuses a key that already exists, nothing here
  deletes, and there is deliberately no delete method.
* **`open` refuses a `schema_version` newer than this install; `list` does not.** A
  consumer must be able to *see* an entry it cannot read yet, so that a page can offer
  "upgrade to import this" instead of hiding it. `list` therefore reads the four
  `BundleEntry` fields straight out of the entry's `release.json` mapping without model
  validation — a newer bundle may legitimately carry fields this `Release` forbids —
  while `open` goes through `read_bundle`, which validates and refuses.

`BundleEntry` is always read from the entry's own `release.json`, never parsed out of
its key: the key is an address, the bundle is the truth. A store whose directories were
renamed by hand still reports what the bundles say.
"""

from __future__ import annotations

import json
import re
import shutil
import tempfile
from abc import ABC, abstractmethod
from collections.abc import Iterable, Iterator, Mapping, Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit
from urllib.request import url2pathname

from mediacore.bundle import (
    BUNDLE_RELEASE_FILENAME,
    read_bundle,
    write_bundle,
)
from mediacore.normalize import normalize_text
from mediacore.release import ContractModel, Release

# URI schemes `open_store` dispatches on. Anything else is a StoreError.
FILE_URI_SCHEME = "file"
S3_URI_SCHEME = "s3"
S3_SERVICE_NAME = "s3"
# `file://<host>/…` names another machine's filesystem; only these two mean "this one".
LOCAL_FILE_URI_HOSTS = ("", "localhost")
URI_SEPARATOR = "/"

# Key layout: <root>/<record ULID>/<exported_at>/<slug>/{release.json,media/…}.
ENTRY_KEY_DEPTH = 3
# ISO 8601 basic in UTC: no separators (safe in a path and in an S3 key) and it sorts
# lexicographically in export order. Whole seconds — two exports of one record inside
# the same second are the same version, and the second one is refused, not merged.
EXPORTED_AT_KEY_FORMAT = "%Y%m%dT%H%M%SZ"

# `release.json` fields read out of the raw JSON mapping by `list`, which must not model
# validate (see the module docstring). Named because the strings are the contract.
SCHEMA_VERSION_FIELD = "schema_version"
PROVENANCE_FIELD = "provenance"
PROVENANCE_ID_FIELD = "id"
PROVENANCE_EXPORTED_AT_FIELD = "exported_at"
TITLE_FIELD = "title"
ARTISTS_FIELD = "artists"
LABELS_FIELD = "labels"
NAME_FIELD = "name"
CATALOGUE_NUMBER_FIELD = "catalogue_number"
# The store keys on the *first* provenance entry — the export that produced this bundle.
# Matching on `kind` instead would put a value like "vinylcat" into the contract package
# (INTEGRATION.md §4: `kind` is evidence, and `cd-rip`/`digital` are coming).
PROVENANCE_INDEX = 0
FIRST_ARTIST_INDEX = 0

# A record id becomes one segment of the entry key — a directory name under `file://`.
# The other two segments are safe by construction (the timestamp is `strftime` output,
# the slug is folded to `[a-z0-9-]`); the id is the only part of the key that reaches
# here straight out of `release.json`, and `Provenance.id` is an unconstrained `str`.
# `Path.joinpath` silently leaves the store root on an absolute or `..` segment, so a
# bundle taken from an upload could otherwise be `put` outside the store it addresses.
RECORD_ID_SEPARATORS = ("/", "\\")
RECORD_ID_RELATIVE_SEGMENTS = (".", "..")

# Slug: `<artist>--<title>--<catalogue number>`, each segment folded to [a-z0-9-] over
# `normalize_text`, so accents fold to their base letters instead of vanishing.
SLUG_SEGMENT_SEPARATOR = "--"
SLUG_WORD_SEPARATOR = "-"
SLUG_SEPARATOR_RE = re.compile(r"[^a-z0-9]+")
SLUG_FALLBACK = "release"

# boto3 response and request vocabulary.
S3_LIST_PAGINATOR = "list_objects_v2"
S3_CONTENTS_FIELD = "Contents"
S3_OBJECT_KEY_FIELD = "Key"
S3_BODY_FIELD = "Body"
# One key is enough to know an entry prefix is taken.
S3_EXISTS_PROBE_MAX_KEYS = 1

JSON_ENCODING = "utf-8"


class StoreError(Exception):
    """A store URI is unusable, an entry is malformed, or a write would overwrite one.

    Failures *inside* a bundle keep raising `BundleError` — `open` verifies through
    `read_bundle`, and a hash mismatch is the same fault whether the bundle came from a
    store or from a folder the user picked.
    """


class BundleEntry(ContractModel):
    """One bundle in a store, described by its own `release.json` (§5.1).

    `record_id` and `exported_at` come from the first `Provenance` entry, `slug` is
    derived from the release, `schema_version` is the bundle's own — which may be newer
    than this install understands, which is exactly why `list` reports it. `uri` is the
    entry's own address: what a consumer posts back to pick it.
    """

    record_id: str
    exported_at: datetime
    slug: str
    uri: str
    schema_version: int


def open_store(uri: str, *, s3_client: Any | None = None) -> BundleStore:
    """The store at `uri`, backend chosen by scheme (`file`, `s3`).

    `s3_client` injects a boto3-compatible S3 client instead of building one from the
    ambient credential chain; it exists so the s3 backend can be exercised offline and
    is ignored by the `file` backend.
    """
    if not isinstance(uri, str) or not uri.strip():
        raise StoreError("a bundle store URI is required, e.g. file:///path or s3://bucket/prefix")

    scheme = urlsplit(uri).scheme.lower()
    if scheme == FILE_URI_SCHEME:
        return FileBundleStore(uri)
    if scheme == S3_URI_SCHEME:
        return S3BundleStore(uri, client=s3_client)
    raise StoreError(
        f"unsupported bundle store URI {uri!r}: expected a "
        f"{FILE_URI_SCHEME}:// or {S3_URI_SCHEME}:// URI"
    )


def release_slug(release: Release) -> str:
    """`<artist>--<title>--<catalogue number>`, the human-readable half of an entry key.

    Derived from the release rather than carried on it, so two exports of one record
    always agree, and so the key never becomes the source of truth for the entry.
    """
    return _slug(
        artist=release.artists[FIRST_ARTIST_INDEX].name if release.artists else None,
        title=release.title,
        catalogue_number=next(
            (label.catalogue_number for label in release.labels if label.catalogue_number),
            None,
        ),
    )


class BundleStore(ABC):
    """The three-method interface of §5.1. `uri` is the store root's own address.

    `list` is shared: every backend enumerates entries, and picking the latest version
    per record happens once, here.
    """

    def __init__(self, uri: str) -> None:
        self.uri = uri

    def list(self, *, all_versions: bool = False) -> list[BundleEntry]:
        """Entries in this store, newest export first.

        The latest version per record by default; every version when `all_versions`.
        An entry whose `schema_version` is newer than this install is listed like any
        other — refusing it is `open`'s job, not this one's.
        """
        entries = [*self._read_entries()]
        if not all_versions:
            entries = _latest_per_record(entries)
        return sorted(entries, key=_entry_sort_key)

    @abstractmethod
    def open(
        self,
        entry: BundleEntry,
        *,
        verify: bool = True,
        dest: Path | str | None = None,
    ) -> Release:
        """The entry's `Release`, verified like `read_bundle` (hashes, audio sizes) and
        refused outright when its `schema_version` is newer than this install's.

        With `dest`, the whole bundle — `release.json` and every media file — is
        materialised into that directory, which must be absent or empty; that is how a
        consumer gets the bytes out of a remote store without a second download API.
        """

    @abstractmethod
    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry:
        """Write a new entry and return it. `files` is the `{sha256: source path}`
        mapping `write_bundle` takes.

        A version that already exists is refused: a re-export is a new version beside
        the old one, and nothing here overwrites or deletes.
        """

    @abstractmethod
    def _read_entries(self) -> Iterator[BundleEntry]:
        """Every version of every record, in any order."""


class FileBundleStore(BundleStore):
    """`file://` — a directory of `<record ULID>/<exported_at>/<slug>/` bundles."""

    def __init__(self, uri: str) -> None:
        self._root = _file_uri_to_path(uri)
        super().__init__(_path_to_file_uri(self._root))

    def _read_entries(self) -> Iterator[BundleEntry]:
        if not self._root.exists():
            # A store that has not been seeded yet is empty, not broken.
            return
        if not self._root.is_dir():
            raise StoreError(f"bundle store root is not a directory: {self.uri}")

        for record_dir in _subdirectories(self._root):
            for version_dir in _subdirectories(record_dir):
                for bundle_dir in _subdirectories(version_dir):
                    release_path = bundle_dir / BUNDLE_RELEASE_FILENAME
                    if not release_path.is_file():
                        # Not an entry: a half-written upload or a foreign directory.
                        continue
                    uri = _path_to_file_uri(bundle_dir)
                    yield _entry_from_payload(_load_json(release_path.read_bytes(), uri), uri)

    def open(
        self,
        entry: BundleEntry,
        *,
        verify: bool = True,
        dest: Path | str | None = None,
    ) -> Release:
        path = self._entry_path(entry)
        if dest is None:
            return read_bundle(path, verify=verify)
        target = _prepare_dest(dest)
        shutil.copytree(path, target, dirs_exist_ok=True)
        return read_bundle(target, verify=verify)

    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry:
        record_id, exported_at, slug, _ = _entry_fields(_release_payload(release), self.uri)
        dest = self._root.joinpath(*_entry_key_parts(record_id, exported_at, slug))
        uri = _path_to_file_uri(dest)
        if dest.exists():
            raise StoreError(_overwrite_message(uri))
        write_bundle(release, dest, files)
        return _entry_from_payload(_release_payload(release), uri)

    def _entry_path(self, entry: BundleEntry) -> Path:
        """The entry's directory, refusing a URI that is not an entry of *this* store.

        `entry.uri` reaches a consumer's server from a browser (§5.1's
        `preview-from-store` posts it back), so it is untrusted input: it is resolved
        and required to sit exactly `ENTRY_KEY_DEPTH` segments under this root.
        """
        candidate = _file_uri_to_path(entry.uri).resolve()
        root = self._root.resolve()
        try:
            relative = candidate.relative_to(root)
        except ValueError as exc:
            raise StoreError(f"entry {entry.uri} is not in the store at {self.uri}") from exc
        if len(relative.parts) != ENTRY_KEY_DEPTH:
            raise StoreError(f"entry {entry.uri} is not a store entry key in {self.uri}")
        if not (candidate / BUNDLE_RELEASE_FILENAME).is_file():
            raise StoreError(f"no such entry in the store at {self.uri}: {entry.uri}")
        return candidate


class S3BundleStore(BundleStore):
    """`s3://` — the same layout under a key prefix.

    The client comes from the ambient boto3 credential chain (environment, shared
    config, instance role): `mediacore` takes no keys, stores none, and the browser
    never talks to the bucket. `boto3` itself is the optional extra `mediacore[s3]`.
    """

    def __init__(self, uri: str, *, client: Any | None = None) -> None:
        split = urlsplit(uri)
        bucket = split.netloc
        if not bucket or "@" in bucket or ":" in bucket:
            raise StoreError(
                f"invalid {S3_URI_SCHEME}:// bundle store URI {uri!r}: expected "
                f"{S3_URI_SCHEME}://<bucket>/<prefix> and no credentials in the URI"
            )
        self._bucket = bucket
        self._prefix = split.path.strip(URI_SEPARATOR)
        self._client = _s3_client() if client is None else client
        super().__init__(_s3_uri(self._bucket, self._prefix))

    def _read_entries(self) -> Iterator[BundleEntry]:
        root = _s3_prefix_with_separator(self._prefix)
        for key in self._iter_keys(root):
            parts = key[len(root) :].split(URI_SEPARATOR)
            if len(parts) != ENTRY_KEY_DEPTH + 1 or parts[-1] != BUNDLE_RELEASE_FILENAME:
                # Media files sit one level deeper; anything else is not an entry.
                continue
            uri = _s3_uri(self._bucket, root + URI_SEPARATOR.join(parts[:-1]))
            yield _entry_from_payload(_load_json(self._read_key(key), uri), uri)

    def open(
        self,
        entry: BundleEntry,
        *,
        verify: bool = True,
        dest: Path | str | None = None,
    ) -> Release:
        prefix = self._entry_prefix(entry)
        keys = [*self._iter_keys(prefix)]
        release_key = prefix + BUNDLE_RELEASE_FILENAME
        if release_key not in keys:
            raise StoreError(f"no such entry in the store at {self.uri}: {entry.uri}")

        if dest is not None:
            target = _prepare_dest(dest)
            self._download(keys, prefix, target)
            return read_bundle(target, verify=verify)

        # Without a destination the bundle still has to exist on disk to be read, so it
        # goes to a temporary directory that is removed again. `verify=False` needs
        # nothing but release.json, so it does not pay for the media.
        wanted = keys if verify else [release_key]
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            self._download(wanted, prefix, target)
            return read_bundle(target, verify=verify)

    def put(self, release: Release, files: Mapping[str, Path]) -> BundleEntry:
        record_id, exported_at, slug, _ = _entry_fields(_release_payload(release), self.uri)
        key_parts = _entry_key_parts(record_id, exported_at, slug)
        prefix = _s3_prefix_with_separator(self._prefix) + URI_SEPARATOR.join(key_parts)
        uri = _s3_uri(self._bucket, prefix)
        if self._prefix_in_use(prefix + URI_SEPARATOR):
            raise StoreError(_overwrite_message(uri))

        # Staged locally first: `write_bundle` validates the whole `files` mapping and
        # re-hashes every copy, so nothing reaches the bucket unless the bundle is
        # complete and correct.
        with tempfile.TemporaryDirectory() as tmp:
            staged = write_bundle(release, Path(tmp) / slug, files)
            for path in _bundle_upload_order(staged):
                relative = path.relative_to(staged).as_posix()
                self._client.upload_file(
                    str(path), self._bucket, prefix + URI_SEPARATOR + relative
                )
        return _entry_from_payload(_release_payload(release), uri)

    def _entry_prefix(self, entry: BundleEntry) -> str:
        """The entry's key prefix (trailing separator), refusing a URI from elsewhere.

        Same boundary as the file backend's `_entry_path`: `entry.uri` is untrusted.
        """
        split = urlsplit(entry.uri)
        if split.scheme.lower() != S3_URI_SCHEME or split.netloc != self._bucket:
            raise StoreError(f"entry {entry.uri} is not in the store at {self.uri}")
        root = _s3_prefix_with_separator(self._prefix)
        key = split.path.strip(URI_SEPARATOR)
        relative = key[len(root) :]
        if not key.startswith(root) or len(relative.split(URI_SEPARATOR)) != ENTRY_KEY_DEPTH:
            raise StoreError(f"entry {entry.uri} is not a store entry key in {self.uri}")
        return key + URI_SEPARATOR

    def _iter_keys(self, prefix: str) -> Iterator[str]:
        paginator = self._client.get_paginator(S3_LIST_PAGINATOR)
        for page in paginator.paginate(Bucket=self._bucket, Prefix=prefix):
            for obj in page.get(S3_CONTENTS_FIELD, []):
                yield obj[S3_OBJECT_KEY_FIELD]

    def _prefix_in_use(self, prefix: str) -> bool:
        response = self._client.list_objects_v2(
            Bucket=self._bucket, Prefix=prefix, MaxKeys=S3_EXISTS_PROBE_MAX_KEYS
        )
        return bool(response.get(S3_CONTENTS_FIELD))

    def _read_key(self, key: str) -> bytes:
        response = self._client.get_object(Bucket=self._bucket, Key=key)
        return response[S3_BODY_FIELD].read()

    def _download(self, keys: Iterable[str], prefix: str, target: Path) -> None:
        for key in keys:
            path = _contained_path(target, key[len(prefix) :])
            path.parent.mkdir(parents=True, exist_ok=True)
            self._client.download_file(self._bucket, key, str(path))


def _load_boto3() -> Any:
    try:
        import boto3
    except ImportError as exc:
        raise StoreError(
            f"{S3_URI_SCHEME}:// bundle stores need boto3: install mediacore[s3]"
        ) from exc
    return boto3


def _s3_client() -> Any:
    """A client from the ambient credential chain — no keys are read or held here."""
    return _load_boto3().client(S3_SERVICE_NAME)


def _release_payload(release: Release) -> dict[str, Any]:
    """The release as `list` would read it back off disk, so one derivation serves both
    `put` and `list` and the two can never disagree about an entry."""
    return release.model_dump(mode="json")


def _entry_from_payload(payload: Any, uri: str) -> BundleEntry:
    record_id, exported_at, slug, schema_version = _entry_fields(payload, uri)
    return BundleEntry(
        record_id=record_id,
        exported_at=exported_at,
        slug=slug,
        uri=uri,
        schema_version=schema_version,
    )


def _entry_fields(payload: Any, source: str) -> tuple[str, datetime, str, int]:
    """`(record_id, exported_at, slug, schema_version)` out of a raw `release.json`.

    Deliberately not `Release.model_validate`: a bundle written by a newer `mediacore`
    carries fields this install forbids, and §5.1 requires such an entry to be *listed*
    with its `schema_version`, not hidden. `source` only names the entry in errors.
    """
    if not isinstance(payload, Mapping):
        raise StoreError(f"{source}: {BUNDLE_RELEASE_FILENAME} is not a JSON object")

    schema_version = payload.get(SCHEMA_VERSION_FIELD)
    if not isinstance(schema_version, int) or isinstance(schema_version, bool):
        raise StoreError(
            f"{source}: {BUNDLE_RELEASE_FILENAME} has no integer {SCHEMA_VERSION_FIELD}"
        )

    provenance = payload.get(PROVENANCE_FIELD)
    if (
        not isinstance(provenance, Sequence)
        or isinstance(provenance, str)
        or len(provenance) <= PROVENANCE_INDEX
        or not isinstance(provenance[PROVENANCE_INDEX], Mapping)
    ):
        raise StoreError(
            f"{source}: {BUNDLE_RELEASE_FILENAME} has no {PROVENANCE_FIELD} entry, so the "
            f"store cannot say which record it is a version of"
        )

    origin = provenance[PROVENANCE_INDEX]
    record_id = origin.get(PROVENANCE_ID_FIELD)
    if not isinstance(record_id, str) or not record_id:
        raise StoreError(
            f"{source}: {PROVENANCE_FIELD}[{PROVENANCE_INDEX}].{PROVENANCE_ID_FIELD} is "
            f"missing or empty"
        )

    exported_at = _parse_exported_at(origin.get(PROVENANCE_EXPORTED_AT_FIELD), source)
    return record_id, exported_at, _slug_from_payload(payload), schema_version


def _parse_exported_at(value: Any, source: str) -> datetime:
    if not isinstance(value, str):
        raise StoreError(
            f"{source}: {PROVENANCE_FIELD}[{PROVENANCE_INDEX}]."
            f"{PROVENANCE_EXPORTED_AT_FIELD} is missing"
        )
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise StoreError(
            f"{source}: {PROVENANCE_EXPORTED_AT_FIELD} {value!r} is not an ISO 8601 timestamp"
        ) from exc
    # A naive timestamp is read as UTC: the key is UTC, so anything else would put the
    # same export under two different versions depending on where it was read.
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=UTC)


def _slug_from_payload(payload: Mapping[str, Any]) -> str:
    artists = payload.get(ARTISTS_FIELD)
    artist = None
    if isinstance(artists, Sequence) and not isinstance(artists, str) and artists:
        first = artists[FIRST_ARTIST_INDEX]
        if isinstance(first, Mapping):
            artist = first.get(NAME_FIELD)

    catalogue_number = None
    labels = payload.get(LABELS_FIELD)
    if isinstance(labels, Sequence) and not isinstance(labels, str):
        for label in labels:
            if isinstance(label, Mapping) and label.get(CATALOGUE_NUMBER_FIELD):
                catalogue_number = label[CATALOGUE_NUMBER_FIELD]
                break

    return _slug(
        artist=artist, title=payload.get(TITLE_FIELD), catalogue_number=catalogue_number
    )


def _slug(*, artist: Any, title: Any, catalogue_number: Any) -> str:
    segments = [_slug_segment(value) for value in (artist, title, catalogue_number)]
    return SLUG_SEGMENT_SEPARATOR.join(filter(None, segments)) or SLUG_FALLBACK


def _slug_segment(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    folded = normalize_text(value).lower()
    return SLUG_SEPARATOR_RE.sub(SLUG_WORD_SEPARATOR, folded).strip(SLUG_WORD_SEPARATOR)


def _entry_key_parts(record_id: str, exported_at: datetime, slug: str) -> tuple[str, str, str]:
    """The three key segments of an entry. Refuses a `record_id` that is not one segment.

    Only `put` builds a key; `list` reads an entry's address off its own location, so an
    id like this is a fault in the bundle being written, not in one already stored.
    """
    if (
        any(separator in record_id for separator in RECORD_ID_SEPARATORS)
        or record_id in RECORD_ID_RELATIVE_SEGMENTS
    ):
        raise StoreError(
            f"{PROVENANCE_FIELD}[{PROVENANCE_INDEX}].{PROVENANCE_ID_FIELD} {record_id!r} is "
            f"not a single key segment, so it cannot address an entry in a bundle store"
        )
    return (
        record_id,
        exported_at.astimezone(UTC).strftime(EXPORTED_AT_KEY_FORMAT),
        slug,
    )


def _overwrite_message(uri: str) -> str:
    return (
        f"refusing to overwrite the existing store entry {uri}: a re-export is a new "
        f"version beside the old one, and nothing in mediacore replaces or deletes an entry"
    )


def _latest_per_record(entries: Iterable[BundleEntry]) -> list[BundleEntry]:
    latest: dict[str, BundleEntry] = {}
    for entry in entries:
        current = latest.get(entry.record_id)
        if current is None or (entry.exported_at, entry.uri) > (current.exported_at, current.uri):
            latest[entry.record_id] = entry
    return [*latest.values()]


def _entry_sort_key(entry: BundleEntry) -> tuple[float, str, str]:
    """Newest export first, then record id, then slug — a stable order for a page."""
    return (-entry.exported_at.timestamp(), entry.record_id, entry.slug)


def _load_json(data: bytes, source: str) -> Any:
    try:
        return json.loads(data.decode(JSON_ENCODING))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise StoreError(f"{source}: {BUNDLE_RELEASE_FILENAME} is not valid JSON") from exc


def _subdirectories(path: Path) -> list[Path]:
    return sorted(child for child in path.iterdir() if child.is_dir())


def _bundle_upload_order(staged: Path) -> list[Path]:
    """Every file in a staged bundle, `release.json` last.

    `list` keys on `release.json`, so uploading it last means an interrupted `put`
    leaves an entry that is invisible rather than one that is half there.
    """
    files = sorted(path for path in staged.rglob("*") if path.is_file())
    release_json = staged / BUNDLE_RELEASE_FILENAME
    return [path for path in files if path != release_json] + [release_json]


def _prepare_dest(dest: Path | str) -> Path:
    """`dest` for `open(..., dest=…)`: it must be absent or empty, and is never
    emptied here — a mistyped destination has to survive the call that refused it."""
    target = Path(dest)
    if target.exists():
        if not target.is_dir():
            raise StoreError(f"destination exists and is not a directory: {target}")
        if any(target.iterdir()):
            raise StoreError(f"refusing to write a bundle into a non-empty directory: {target}")
    target.mkdir(parents=True, exist_ok=True)
    return target


def _contained_path(root: Path, relative: str) -> Path:
    """Join `relative` under `root`, refusing anything that escapes it. Object keys come
    from the bucket, which a consumer does not control end to end."""
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError as exc:
        raise StoreError(f"bundle key escapes its destination: {relative!r}") from exc
    return candidate


def _file_uri_to_path(uri: str) -> Path:
    split = urlsplit(uri)
    if split.scheme.lower() != FILE_URI_SCHEME:
        raise StoreError(f"not a {FILE_URI_SCHEME}:// URI: {uri!r}")
    if split.netloc.lower() not in LOCAL_FILE_URI_HOSTS:
        raise StoreError(
            f"{uri!r} names another host; a {FILE_URI_SCHEME}:// bundle store is local"
        )
    path = Path(url2pathname(split.path))
    if not path.is_absolute():
        raise StoreError(f"{FILE_URI_SCHEME}:// bundle store URI must be absolute: {uri!r}")
    return path


def _path_to_file_uri(path: Path) -> str:
    return path.absolute().as_uri()


def _s3_uri(bucket: str, key: str) -> str:
    return f"{S3_URI_SCHEME}://{bucket}{URI_SEPARATOR}{key}" if key else f"{S3_URI_SCHEME}://{bucket}"


def _s3_prefix_with_separator(prefix: str) -> str:
    return prefix + URI_SEPARATOR if prefix else ""
