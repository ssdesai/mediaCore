"""The neutral `Release` contract (INTEGRATION.md §3).

This is the on-disk `release.json` shape and the only thing that crosses the boundary
between the source repo (vinylCatalogue) and its consumers (humanNetworkMap, musicMap).
Field naming follows Discogs vocabulary wherever an equivalent exists. Every model
forbids extra fields, so a producer that invents one fails loudly instead of having it
silently dropped somewhere downstream.

Nothing here is specific to any medium: `medium` is the one closed vocabulary and
`"vinyl"` is merely one of its values — the code that chooses a value lives in the
producing repo's adapter, never here.

Every `refs` field below is *evidence recorded by an external source* about that
entity, never the entity's identity (INTEGRATION.md §4). All of them are optional and
default to `{}`; nothing in the contract requires one, privileges one source over
another, or enforces uniqueness.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from mediacore.refs import Refs

# Bumped only when the on-disk release.json shape changes (INTEGRATION.md §12).
SCHEMA_VERSION = 1

# The contract's only closed vocabularies. `format` sits beside `medium` and is the
# authority's own free text — never parsed, never validated against a list.
Medium = Literal["vinyl", "cd", "cassette", "digital", "other"]
MediaKind = Literal["photo", "external_photo"]

# A release without an artist cannot be matched by any consumer.
MIN_ARTISTS = 1


class ContractModel(BaseModel):
    """Base for every model on the wire: extras forbidden, so a field one side invented
    is a validation error rather than silent data loss."""

    model_config = ConfigDict(extra="forbid")


class Provenance(ContractModel):
    """Where this copy came from: evidence of a different kind, carrying no more
    authority than any other ref (INTEGRATION.md §4)."""

    kind: str
    id: str
    label: str | None = None
    exported_at: datetime


class ArtistRef(ContractModel):
    name: str
    sort_name: str | None = None
    refs: Refs = Field(default_factory=dict)


class LabelRef(ContractModel):
    name: str
    catalogue_number: str | None = None
    refs: Refs = Field(default_factory=dict)


class Credit(ContractModel):
    role: str
    name: str
    refs: Refs = Field(default_factory=dict)


class Track(ContractModel):
    position: str
    title: str
    duration: str | None = None
    credits: list[Credit] = Field(default_factory=list)


class MediaFile(ContractModel):
    """An image. `file` is always `media/<sha256>.<ext>`, relative to the bundle root
    (INTEGRATION.md §5); `role` is free text a consumer treats as a caption hint."""

    kind: MediaKind
    role: str | None = None
    sha256: str
    file: str
    mime: str
    source_url: str | None = None
    refs: Refs = Field(default_factory=dict)


class AudioFile(ContractModel):
    """One audio file, joined to its `Track` by `track_position`."""

    track_position: str
    sha256: str
    file: str
    format: str
    size_bytes: int


class Link(ContractModel):
    """A navigable URL. `refs` says which entity the link is *about*, so a consumer can
    attach it to the matching artist/label/release rather than guessing."""

    label: str
    url: str
    refs: Refs = Field(default_factory=dict)


class Release(ContractModel):
    schema_version: int = SCHEMA_VERSION
    refs: Refs = Field(default_factory=dict)
    provenance: list[Provenance] = Field(default_factory=list)
    title: str
    artists: list[ArtistRef] = Field(min_length=MIN_ARTISTS)
    labels: list[LabelRef] = Field(default_factory=list)
    year: int | None = None
    released: str | None = None
    country: str | None = None
    medium: Medium
    format: str | None = None
    genres: list[str] = Field(default_factory=list)
    styles: list[str] = Field(default_factory=list)
    tracks: list[Track] = Field(default_factory=list)
    credits: list[Credit] = Field(default_factory=list)
    notes: str | None = None
    tags: list[str] = Field(default_factory=list)
    media: list[MediaFile] = Field(default_factory=list)
    audio: list[AudioFile] = Field(default_factory=list)
    links: list[Link] = Field(default_factory=list)
