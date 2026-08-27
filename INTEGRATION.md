# Integration design: vinylCatalogue → mediaCore → humanNetworkMap / musicMap

The cross-repo design for moving recorded-media data between four repos. This file is
the brief every implementing agent works from; the decisions log at the bottom records
what was settled with the owner and when. Repo-local facts (commands, paths, field lists)
live in each repo's own `README.md`/`plans/PROJECT_FACTS.md`, not here.

## 1. Repos and roles

| Repo | Role | Stack |
|---|---|---|
| `vinylCatalogue` (`~/dev/vinylCatalogue`) | **Source.** Photographs of physical records → reviewed `record.json`. Exports a *release bundle* once a record is signed off. Knows nothing about consumers. | Python `vinylcat` package, files on disk (no DB), FastAPI GUI |
| `mediaCore` (`~/dev/mediaCore`, this repo) | **Contract.** The neutral `Release` schema, refs/authorities, `normalize_text`, bundle reader/writer, and the shared test fixture. No app code. | Python package `mediacore`, public GitHub repo, consumed by git tag |
| `humanNetworkMap` (`~/dev/humanNetworkMap`) | **Consumer.** A release becomes an *information source*; the people/bands/labels on it become nodes; credits become edges; every fact cites the source. Human-supervised import page. | FastAPI + SQLAlchemy async/asyncpg + Alembic, React/TS (types generated from OpenAPI) |
| `musicMap` (`~/dev/musicMap`) | **Consumer.** A release becomes album + artist + one song per audio file, then embeddings. Human-supervised import page. | FastAPI + SQLAlchemy sync/psycopg + pgvector + Alembic, React/TS (hand-mirrored types), Docker |

Data flows one way: vinylCatalogue → bundle store (§5.1: a folder locally, a bucket when
hosted) → consumer import page. No repo depends on another repo's *runtime*; consumers
depend only on the `mediacore` package.
Future sources (CD rips, digital purchases, cassettes) plug in by writing the same bundle.

## 2. Principles (settled)

1. **Nothing vinyl-specific crosses the boundary.** The contract is a `Release`. The
   vinyl-shaped things (photo roles, pressing/matrix data, review gates) stay in
   vinylCatalogue; its adapter is the only code that knows both shapes.
2. **Identity never hinges on any one source.** An artist, label, release, or person
   *is* the consumer's own entity (its row). Discogs IDs, MusicBrainz IDs, vinylcat
   record IDs, file hashes, and names are all **supporting evidence** attached to that
   entity — any of them may be absent (a record with only Discogs data, one with only
   local photographs, a band that exists in no database). No ref is required, no ref is
   a key, and no source is privileged: the human confirms every match.
3. **Imports are human-supervised, always.** Every consumer has an import page that
   parses a bundle, proposes matches against existing entities, and commits only what
   the human confirmed. There is no unattended sync. Re-import is the same page again —
   the human decides what to link, create, or skip.
4. **Consumers never see unreviewed data.** Only signed-off records are exportable, so
   the contract carries plain values — no confidence, no field envelopes, no conflicts.
5. **Each consumer owns its own mapping.** `Release → nodes/edges/sources` lives in
   humanNetworkMap; `Release → artist/album/songs` lives in musicMap. mediaCore never
   imports either.
6. **Shared database: no. Monorepo: no.** Four repos, one contract package, git-tag
   pinning.

## 3. The `Release` contract (`mediacore.release`)

Pydantic v2, `extra="forbid"`, JSON-serialisable, `schema_version` on the wire. Field
naming follows Discogs vocabulary where an equivalent exists (Discogs is
format-agnostic; MusicBrainz maps onto it cleanly).

```
Release
  schema_version: int = 1
  refs: Refs                      # authority-keyed identity of THIS release (§4)
  provenance: list[Provenance]    # where this copy came from (§4)
  title: str
  artists: list[ArtistRef]        # ≥ 1
  labels: list[LabelRef]
  year: int | None
  released: str | None            # ISO date or partial ("1974", "1974-06")
  country: str | None
  medium: Medium                  # "vinyl" | "cd" | "cassette" | "digital" | "other"
  format: str | None              # free text as the authority states it, e.g. "Vinyl, LP, Album"
  genres: list[str]
  styles: list[str]
  tracks: list[Track]
  credits: list[Credit]           # release-level credits
  notes: str | None
  tags: list[str]
  media: list[MediaFile]          # images
  audio: list[AudioFile]
  links: list[Link]               # navigable URLs, each tagged with the refs it is about

ArtistRef   { name: str, sort_name: str | None, refs: Refs }
LabelRef    { name: str, catalogue_number: str | None, refs: Refs }
Track       { position: str, title: str, duration: str | None, credits: list[Credit] }
Credit      { role: str, name: str, refs: Refs }
MediaFile   { kind: "photo" | "external_photo", role: str | None, sha256: str,
              file: str, mime: str, source_url: str | None, refs: Refs }
AudioFile   { track_position: str, sha256: str, file: str, format: str, size_bytes: int }
Link        { label: str, url: str, refs: Refs }
Provenance  { kind: str, id: str, label: str | None, exported_at: datetime }
Refs = dict[str, str]             # see §4 for key format
```

- `file` on `MediaFile`/`AudioFile` is a path relative to the bundle root, always
  `media/<sha256>.<ext>` (§5). `sha256` is the hex digest of that file's bytes.
- `medium` is the one closed vocabulary; consumers may use it (e.g. as a default
  `source_type`). `format` is the authority's free-text string and is never parsed.
- `Link.refs` says which entity the link is *about* — a Discogs artist URL carries
  `{"discogs:artist": "5682050"}` so a consumer can attach it to the matching node.
  The release's own link carries the release refs.
- `MediaFile.role` is free text; vinylCatalogue emits its photo-role vocabulary
  (`sleeve_front`, `sleeve_back`, `label_a`, `label_b`), a CD source would emit its own.
  Consumers treat it as a caption hint, nothing more.

## 4. Refs as evidence, authorities, provenance (`mediacore.refs`)

**A ref is a piece of evidence, not an identity.** `refs` on a release, artist, label,
credit, or link records what some external source calls this thing. It is always
optional and may be empty. A consumer uses refs to *propose* a match and to *retain
evidence* on the entity it links or creates; it never treats a ref as the entity's key,
never requires one, and never lets one source's absence block an import. Two rows may
legitimately share a ref (Discogs has duplicates) and one real-world entity may carry
refs from several sources or none — the human decides which rows are the same thing.

**Ref keys** are `"<authority>:<entity>"` — lowercase, validated by
`^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$`. Values are non-empty strings (Discogs numeric IDs are
stored as strings). Known keys are constants; unknown keys are allowed (that is the
extension point) but a consumer only *matches* on keys it knows.

| Key | Meaning |
|---|---|
| `discogs:release` | release (edition) |
| `discogs:master` | master (same album across editions) |
| `discogs:artist` | artist or group |
| `discogs:label` | label |
| `musicbrainz:release`, `musicbrainz:release-group`, `musicbrainz:artist`, `musicbrainz:label`, `musicbrainz:recording` | reserved for a future digital source |
| `isrc:recording` | ISRC of a recording (reserved) |
| `barcode:release` | UPC/EAN printed on a release (reserved) |

**Ref URI** (for query strings and cross-app links, phase 2): `f"{key}:{value}"`, e.g.
`discogs:artist:5682050`. `ref_uri(key, value)` / `parse_ref_uri(s)` live in
`mediacore.refs`.

**Two levels of "same":** `discogs:master` / `musicbrainz:release-group` = same album
(a vinyl and a CD of it collapse — same band, same label, same credits);
`discogs:release` = same edition. humanNetworkMap cares about the former, musicMap may
keep both.

**Provenance** is evidence of a different kind: where *this copy* came from —
`{kind, id, label, exported_at}`. Kinds so far: `vinylcat` (id = the record ULID, label
= collection root's basename). Future: `cd-rip`, `digital`. Consumers store it on the
rows an import touches (under `kind:record`-style keys, §7) so a re-import can show what
an earlier import created. It carries no more authority than any other ref.

**Releases with no authority data at all** (`not_on_discogs`, demo tapes, a label that
exists only on a sleeve) are first-class, not a fallback case. Their evidence is names,
photographs, and provenance; candidates come from `normalize_text` equality on names,
and the human confirms. No central registry mints canonical IDs; if that is ever
needed it goes behind the same `refs` interface.

**`normalize_text`** (`mediacore.normalize`) is the shared fold used for name
matching in every consumer. It must be *byte-for-byte the same algorithm* as
`vinylcat.normalize.normalize_text` (uppercase, accent-strip, whitespace-collapse) —
read that file when implementing and pin its behaviour with sample-based tests.

## 5. Bundle format (`mediacore.bundle`)

A *bundle* is a directory:

```
<slug>/
  release.json              # one Release, schema_version 1
  media/<sha256>.<ext>      # every MediaFile and AudioFile, named by content hash
```

- Written wholesale, never edited: exporting again replaces the directory.
- `read_bundle(path, *, verify=True) -> Release` parses and, when `verify`, checks every
  referenced file exists, hashes to its `sha256`, and — for each `AudioFile` — that its
  byte size on disk matches `size_bytes`. Missing, mismatched, or wrong-size files raise
  `BundleError` naming the file. Independently of `verify`, it rejects a `release.json`
  whose `schema_version` is newer than the running `mediacore`'s `SCHEMA_VERSION`,
  telling the caller to upgrade.
- `write_bundle(release, dest, files: Mapping[str, Path]) -> Path` writes `release.json`
  and copies each file keyed by sha256 to `media/`, verifying the hash on the way.
- Browser transport: the import pages accept the folder through a file picker
  (`<input type="file" webkitdirectory>`); the client posts `release.json` plus the
  files as multipart; the server re-verifies hashes. Nothing needs another app running.
- musicMap alternative for large corpora: drop the bundle under `data/incoming/` and pick
  it from the import page — same server code path, files read instead of uploaded.
  Optional; browser upload is the baseline. Generalised by §5.1: `data/incoming/` is a
  `file://` bundle store.

### 5.1 Bundle store (`mediacore.store`) — designed 2026-08-27, WP7

The problem §5's transport leaves open: one signed-off record is imported into *two*
consumers, each by hand-picking the same folder. And "folder" stops working the day
musicMap and hNM are hosted while vinylCatalogue stays on a laptop. A *bundle store* is
where bundles sit between source and consumers, addressed by a URI so the local→hosted
move is configuration, not code:

```
file:///Users/…/bundles              local: a directory of bundle directories
s3://<bucket>/<prefix>               hosted: the same layout under a key prefix
```

- **Interface.** `open_store(uri) -> BundleStore` picks the backend from the scheme
  (`file`, `s3`; anything else raises `StoreError`). A `BundleStore` has three methods
  and nothing else: `list(*, all_versions=False) -> list[BundleEntry]`,
  `open(entry, *, verify=True) -> Release`, `put(release, files) -> BundleEntry`.
  Consumers and the source call these; none of them touches paths or boto directly.
- **`BundleEntry { record_id, exported_at, slug, uri, schema_version }`** — `record_id`
  is the `vinylcat:record` ULID, `exported_at` the export timestamp, `uri` the entry's
  own address (what a consumer posts back to pick it). All read from the entry's
  `release.json`, never parsed out of its key. Concretely (WP7a): `record_id` and
  `exported_at` are the **first `provenance` entry's** `id` and `exported_at` — for a
  vinylCatalogue export that is the record ULID, without the value `vinylcat` entering
  the package — and `slug` is *derived* by `release_slug(release)` as
  `<artist>--<title>--<catalogue number>` folded over `normalize_text`, because
  `release.json` carries no slug field to read.
- **Layout and versions.** `<root>/<record ULID>/<exported_at, ISO basic>/<bundle>`. A
  re-export is a new version beside the old one; `list()` returns the latest per record
  (`all_versions=True` for every version, latest included). Nothing in `mediacore`
  overwrites or deletes an entry — `put` *refuses* a version key that already exists
  (whole-second granularity), so the rule is enforced, not merely intended. Consumers
  never delete either.
- **`open` verifies like `read_bundle`** — hashes, audio sizes, and a `schema_version`
  newer than the running `mediacore` is refused with the upgrade message. `list` does
  not refuse: such an entry is listed with its `schema_version` so a page can say
  "upgrade to import this" instead of hiding it. `open(entry, dest=…)` also materialises
  the whole bundle — `release.json` and every media file — into an empty `dest`, which is
  how a consumer gets the bytes out of a remote store for the import path below without
  a fourth method.
- **`s3://`** uses the ambient boto3 credential chain; `mediacore` takes no keys and the
  browser never sees the store. `boto3` is the optional extra `mediacore[s3]`.
- **Consumer inbox rule.** The inbox is the store's entries whose `record_id` appears in
  no `refs` bag (`vinylcat:record`) in this database. Already-imported entries are still
  listed, with the date they were imported — the §7 re-import rule reads the same
  evidence — not hidden. Endpoints: hNM `GET /api/projects/{pid}/imports/release/inbox`,
  musicMap `GET /api/v1/imports/release/inbox`, both returning
  `InboxEntryOut { record_id, exported_at, slug, uri, schema_version, title, imported_at }`
  (`imported_at` null when not in this DB).
- **One import path.** Picking an entry calls
  `POST …/imports/release/preview-from-store { entry_uri }`, which returns the same
  preview payload as the multipart preview and stashes the bytes it reads from the store
  under an import id; commit is unchanged. Media is read from the store, never
  re-uploaded through the browser, and lands with the same `sha256` as an upload would.
- **Unset means absent.** Each consumer reads `BUNDLE_STORE_URI` server-side; unset
  hides the inbox section and the endpoints answer 404, exactly the `VITE_PEER_*`
  convention of §10. Browser upload stays as the baseline and is unchanged.
- **Source side.** `vinylcat export-release <id>` writes to the store named by
  `bundle_store_uri` in its config (`--store <uri>` overrides); with neither it writes
  the folder as before. The §6 sign-off gate applies identically.
- **Fixture.** Each dev stack seeds *IT'S SAXY* into a local `file://` store, so the
  store path is exercised by tests and not only by upload.
- **Optional, later:** vinylCatalogue's record page asks each peer's resolve endpoint
  (§10) for `vinylcat:record:<ulid>` and shows *imported where*; "unknown" when a peer is
  unreachable.

Principle 6 stands: a shared bucket is shared *transport* — the bundle on disk with the
disk generalised — not a shared database. Logged in §13.

## 6. vinylCatalogue: the export gate and the adapter

- **Gate:** a record is exportable only when it has passed the fourth review gate
  (record sign-off, spec §7.8b). The exact predicate is whatever the code uses for
  "signed off" (`resolved_at` on the record summary is the visible symptom); the
  vinylCatalogue agent confirms it in the spec/code and pins it in `PROJECT_FACTS.md`.
  No `--force`. An unsigned record gets a clear refusal naming the gate.
- **Surface:** `vinylcat export-release <id-or-slug>` (CLI), `POST
  /api/records/{ref}/export` (writes the bundle, returns its path), and an *Export
  bundle* action in the Browse view. Bundles go to `<collection>/exports/releases/<slug>/`.
  Spec §7.10 is amended: `record.json`'s *bundle* is an outbound contract; the CSV
  exports remain "never an input to anything".
- **Adapter** `Record → Release` (the only vinyl-aware code), rules:
  - `refs`: `discogs:release` from `external.discogs.release_id` when status is
    `matched`; `discogs:master` when `master_id` is set. Nothing when `not_on_discogs`.
  - `provenance`: `[{kind: "vinylcat", id: record.id, label: <collection basename>,
    exported_at: now}]`.
  - `artists`: when matched, from `external.discogs.data["artists"]` — `name`, and
    `refs["discogs:artist"] = str(id)`; `sort_name` from `data["artists_sort"]`. When
    unmatched, one `ArtistRef` from `identity.artist.value`, no refs.
  - `labels`: when matched, from `data["labels"]` (`name`, `catno` →
    `catalogue_number`, `refs["discogs:label"]`); else from `identity.label` /
    `identity.catalogue_number`.
  - `year`: `identity.year.value`, else `data["year"]` when > 0, else null. `country`,
    `released`, `format` from identity values. `medium = "vinyl"` — hard-coded in this
    adapter, which is the right place for the only vinyl fact.
  - `tracks`: from `record.tracklist` (values only, where the envelope state is
    present). Track credits: `role` and `name` from the record; `refs["discogs:artist"]`
    resolved by matching `data["tracklist"][same position]["extraartists"]` on
    `(normalize_text(role), normalize_text(name))` — the role is normalized too, since
    it is hand-transcribed on one side and Discogs free text on the other (WP1 review,
    2026-08-26). Release-level `credits` the same way against
    `data["extraartists"]`.
  - `genres`, `styles`, `notes`, `tags` straight across.
  - `media`: `photos[]` → `kind="photo"`, `role`, `sha256`, `mime` from extension,
    `file = media/<sha256>.<ext>`; `external_photos[]` → `kind="external_photo"`,
    `source_url`, `refs = {"discogs:release": ...}`.
  - `audio`: `audio[]` → `track_position`, `sha256`, `format`, `size_bytes`,
    `file = media/<sha256>.<format>`.
  - `links`: the Discogs release (`data["uri"]`, refs = release refs); one per artist
    with an id (`https://www.discogs.com/artist/<id>`, refs `discogs:artist`); one per
    label with an id (`https://www.discogs.com/label/<id>`); one per credited artist
    with an id. Labels: `"Discogs: <name>"`.
  - Envelopes are unwrapped; nothing about confidence, sources, or verification crosses.

## 7. Consumer rules (both consumers)

- **Columns.** Add `refs JSONB NOT NULL DEFAULT '{}'` (+ GIN index) to every table that
  can represent a release-derived entity (§8/§9 list them). It is an *evidence bag*:
  per entity, the authority refs from the bundle *plus* provenance under
  `vinylcat:record` (the ULID) and, for files, `sha256`. Rows created by hand have an
  empty bag and are matched by name like anything else. Never store another app's UUIDs.
- **Candidates, not matches.** For each incoming entity the preview lists existing rows
  with the evidence that connects them, strongest first: (1) a shared known authority
  ref — strong signal, default action *link*, but still shown for confirmation; (2)
  equal `normalize_text(name)` — default action *create* with the candidate offered;
  (3) nothing — *create*. The human can always override to link/create/skip, including
  linking to a row that shares no evidence at all (that is how a hand-made node and its
  Discogs entry become one thing).
- **Linking accumulates evidence.** When the human links an incoming entity to an
  existing row, the row's `refs` is merged additively with the incoming refs: existing
  keys are kept, missing keys are added, and on a per-key conflict the existing value
  wins — the import never replaces what a human already curated. Conflicts are shown
  in the preview so the human sees them, but the correction surface is the consumer's
  ordinary edit endpoints (PATCH on the row), not the import; a per-key picker in the
  preview is deferred until real imports show conflicts are common (decision 2026-08-26,
  §13). This is the one edit an import makes to a pre-existing row, and it is what lets
  an entity known first from local photographs later gain a Discogs ref, or vice versa.
- **Re-import.** If a row already carries this release's `discogs:release` or
  `vinylcat:record`, the preview says so up front (what it is, when it was imported) and
  lets the human continue or cancel. Continuing runs the same matching; previously
  created rows appear as exact candidates. Nothing is ever overwritten silently —
  importers *add*; edits to existing rows happen only where the page explicitly offers
  them.
- **Commit is atomic.** Preview and commit are two endpoints; commit takes the human's
  decisions and creates everything in one transaction. Preview stashes uploaded files
  under an import id so commit does not re-upload.
- **Inbox.** When `BUNDLE_STORE_URI` is set, the import page also lists the bundle
  store (§5.1) and the human picks from it; the pick runs the same preview/commit as an
  upload. The consumer reads the store and never writes to or deletes from it.
- **Type mirrors.** hNM regenerates TS from OpenAPI; musicMap hand-mirrors `*Out` schemas
  in `frontend/src/api/types.ts` with its conformance test. Both follow their repo's
  existing rule — mediaCore ships no TypeScript.

## 8. humanNetworkMap mapping

**Model additions:** `refs` on `nodes`, `information_sources`, `media` (media's `refs`
carries `sha256`). Alembic migration. `NodeOut`/`InformationSourceOut`/`MediaOut` gain
`refs`; README field lists updated per Rule 1.

**The release becomes:**
- One `information_source` — `source_name = "<artists> — <title> (<label> <catno>)"`,
  `refs` = release refs + `vinylcat:record`. Editable in the page.
- One `information_source_instance` on it — `source_type` default `"physical media"`
  (editable; the owner plans public/private filtering by source type later),
  `date` = `released` or `year` if known.
- Nodes: one per `ArtistRef` (default `asset_type = "artist"`), one per `LabelRef`
  (`"label"`), one per distinct credited person across track/release credits
  (`"person"`). Each with `refs`. All defaults editable per row.
- Edges (defaults, each a row the human can retype or uncheck):
  - artist → label: type `released on`, `year_started` = year.
  - credited person → artist: type = the credit role as the authority spells it
    (`Written-By`), description `"<position> '<track title>' on <title>"`.
- Information items citing the instance: on every created/linked node and edge, one
  item — e.g. artist: `Released IT'S SAXY (A. A. E. SAAE 1012), South Africa`; label:
  `Released IT'S SAXY by The Duke's Combo (SAAE 1012)`; credit: `Written-By on B5 'Ma
  Belle Amie' — IT'S SAXY`; edge: the same sentence as its endpoint's credit.
- Media: every `MediaFile` uploaded to the store and attached to the source
  (`source_ids`), with `refs.sha256`; a re-import skips files whose sha256 already
  exists in the project.
- Links: a link that resolved to nodes lives on those nodes only; the source carries
  just the entity-less links — the release's own, or one whose entities were all skipped
  (so the evidence is retained somewhere). Duplicate URLs within a project are not
  re-added. (Amended 2026-08-27 — see decisions log; originally every link also landed
  on the source.)

**Endpoints:** `POST /api/projects/{pid}/imports/release/preview` (multipart) →
`ReleaseImportPreviewOut`; `POST /api/projects/{pid}/imports/release/commit` →
`ReleaseImportResultOut` (ids of everything created/linked). Path parameter follows the
`{pid}` convention.

**Page:** a new top-level *Import* view beside the existing views (the app has no
router; follow the existing view-switch pattern). Steps: pick bundle folder → preview
(source card, entity table with candidate pickers and link/create/skip, edge checklist
with editable types, media/link summary, re-import banner if applicable) → commit →
result summary. No step advances without a click.

## 9. musicMap mapping

**Model additions:** `refs` on `artists`, `albums`, `songs` (+ GIN). Alembic migration.
`source_type` stays `personal_collection`; provenance goes in `refs`.

**The release becomes:**
- One `artist` per `ArtistRef` (matched per §7). Multi-artist releases: the first artist
  is the album/song artist; the rest are offered as rows the human may create or skip
  (the schema has one `artist_id`; do not widen it in this batch).
- One `album` — `name = title`, `year`, `label = labels[0].name`, `artwork_uri` from the
  first `media` image if any; `refs` = release refs + `vinylcat:record`.
- One `song` per `AudioFile`, joined to its `Track` by `position`: `name` = track title,
  `year`, `country_of_production = country`, `tags` = lowercased genres, `refs` =
  `{"sha256": <audio sha>, "release:position": <position>, "discogs:release": ...,
  "vinylcat:record": ...}`. Audio uploaded to the blob store; embed jobs enqueued for the
  models the human ticks (reuse the existing ingest/embed path); attached to the chosen
  dataset (existing or new), as the current ingest dialog does.
- **Already-present songs are skipped by default.** A track whose `sha256` or
  `(discogs:release, release:position)` matches an existing song is shown greyed with
  "already imported <date>" and an explicit *re-import anyway* toggle.

**Endpoints:** `POST /api/imports/release/preview`, `POST /api/imports/release/commit`,
same two-step shape as §8.

**Page:** *Import release…* beside *Ingest audio…*; steps: pick bundle → artist match →
album match → track table (skip/import per row, model selection, dataset) → commit →
embedding progress (reuse the existing progress UI).

## 10. Phase 2: resolvers and deep links (designed 2026-08-27; WP5/WP6)

The cross-app currency is the **ref URI** (§4): `discogs:artist:5682050`. Nothing else
crosses the boundary — no ids, no URLs to specific pages, no shared database. A ref URI
resolves to a *disambiguation, never an assumption*: possibly several matches, possibly
none.

### 10.1 Resolve endpoints (the cross-repo API contract)

Both consumers expose a resolver over their own data. Match rule: an entity matches when
its `refs` bag contains exactly `{key: value}` from the parsed URI. Only grammar-valid
keys (§4) are resolvable — musicMap's bare `sha256` song key, for example, is not
expressible as a ref URI and stays internal.

- **humanNetworkMap** — `GET /api/resolve?ref=<uri>` (project-independent; the point is
  cross-project disambiguation):
  `ResolveOut { ref: str, nodes: list[ResolvedNodeOut], sources: list[ResolvedSourceOut] }`
  where `ResolvedNodeOut { id, project_id, name, asset_type }` and
  `ResolvedSourceOut { id, project_id, name: str | None }` — a source's name is nullable
  (`source_name` is an optional column); peers must not assume it. 400 on a malformed URI
  (`mediacore.refs.parse_ref_uri` is the arbiter). Sources are included because
  `vinylcat:record` / `discogs:release` live on information sources in hNM (§8) — a
  record deep-link lands on the source, not on a node.
- **musicMap** — `GET /api/v1/resolve?ref=<uri>`:
  `ResolveOut { ref: str, artists: list[ArtistOut], albums: list[AlbumOut], songs: list[SongOut] }`.
  Same 400 rule.

### 10.2 Deep-link landing (`?ref=`)

Both frontends accept `?ref=<ref-uri>` on their root URL, resolve it at boot via their
own `/resolve`, and then: exactly one match → navigate straight to it (navigation is not
an import; §2's human-supervision rule does not apply); several → show the
disambiguation; none → a "nothing here carries that reference" notice. The `?ref=` param
is consumed — replaced by the app's own state URL once handled. The value is written
percent-encoded as an ordinary query value and read back with `URLSearchParams` (which
decodes) — pinned here because a mismatch would break links silently and neither repo's
checks would catch it. In-app landing UX beyond this rule is each repo's own design,
with one floor: a landing must offer a next step into the entity's actual data (e.g. an
artist match lists that artist's songs), never a dead-end label.

### 10.3 humanNetworkMap URL-addressable state

hNM has no router and gains none. `NetworkPage` reads `?project=&node=&source=` at boot
(project switch → node selection or source drill-in) and mirrors selection changes back
with `history.replaceState`. Invalid or stale ids degrade silently to the default view.
This is what a resolved `?ref=` navigates into, and what a person copies out of the
address bar.

### 10.4 Peer URLs and "Open in …" links

§10's `PEER_*` env vars are realised as build-time Vite vars, matching how both clients
already read config: **hNM client** reads `VITE_PEER_MUSICMAP_URL`, **musicMap
frontend** reads `VITE_PEER_HNM_URL`. Each names the *peer frontend's origin*; unset →
the buttons don't render (the apps stay fully usable standalone). Dev note: both repos'
dev stacks default to :5173, so running the pair concurrently means hNM via
`scripts/sandbox.sh` (:5175) beside musicMap compose (:5173) — the suggested dev values
are `VITE_PEER_MUSICMAP_URL=http://localhost:5173` and
`VITE_PEER_HNM_URL=http://localhost:5175`.

A button is built as `<peer-origin>/?ref=<uri>` from the entity's own refs, first key to
match a pinned priority list:

- hNM → musicMap: node detail (`discogs:artist`, `discogs:master`, `discogs:release`),
  source detail (`vinylcat:record`, `discogs:release`).
- musicMap → hNM: artist (`discogs:artist`), album and song (`vinylcat:record`,
  `discogs:release`) — album/song links land on the hNM *source* for that record.

### 10.5 Deferred

The optional musicMap side panel fetching the band's hNM neighbourhood stays deferred —
it needs a server-to-server call or CORS story that nothing else in phase 2 needs, and
the "Open in hNM" button covers the workflow. Recorded in the decisions log.

## 11. The fixture: *IT'S SAXY*

One real, Discogs-matched record from the owner's Test collection is the contract
fixture every repo tests against: `fixtures/its-saxy/` in mediaCore, a complete bundle
with the real metadata and **placeholder media** (tiny PNGs for photos, short silent
WAVs for audio, generated by a committed script so hashes are reproducible). Its
`sha256`s therefore differ from the live record's — by design; the live bundle is for
the human end-to-end run, the fixture is for tests.

Metadata (read from the live `record.json` on 2026-08-25; read-only):

- vinylcat record id `01M08WYYQGY1S66KY425FYCBS7`, slug
  `the-duke-s-combo--it-s-saxy--saae-1012`, collection label `Test`
- Discogs release `16853262`, no master, uri
  `https://www.discogs.com/release/16853262-The-Dukes-Combo-Its-Saxy`
- title `IT'S SAXY`; artist **The Duke's Combo** (`discogs:artist` `5682050`,
  sort name `Duke's Combo, The`); label **A. A. E.** (`discogs:label` `1504762`),
  catalogue number `SAAE 1012`; country `South Africa`; year unknown (Discogs says 0);
  format `Vinyl, LP, Album`; medium `vinyl`
- genres `Jazz, Rock, Funk / Soul, Blues, Folk, World, & Country, Stage & Screen`; no styles
- tracks (position, title, duration — the record's verified values, v0.1.1):
  A1 LOVE GROWS 1:57 · A2 ALL I HAVE TO DO IS DREAM 2:37 · A3 JY IS MY LIEFLING 2:10 ·
  A4 I'LL NEVER FALL IN LOVE AGAIN 1:50 · A5 DOMINIQUE 2:07 · A6 THERESA 2:31 ·
  B1 SUGAR SUGAR 2:17 · B2 Love Theme From Romeo And Juliet 2:05 · B3 SEEMAN 2:07 ·
  B4 MAKE ME AN ISLAND 2:03 ·
  B5 MA BELLE AMIE 2:58 (Written-By: peter tetteroo, `discogs:artist` `282874`) ·
  B6 LOVE IS A BEAUTIFUL SONG 2:32 (Written-By: Terry Dempsey, `discogs:artist` `1033325`
  — B6's photo reads 2.35; the verified value is Discogs's 2:32)
- no release-level credits; no notes; no tags
- photos: `label_a`, `label_b` (two); external photos: two from the Discogs release
- audio: one file per track, A1–B6, twelve in all (live files are mp3; fixture uses wav)
- links: the release; artist 5682050; label 1504762; credits 282874 and 1033325

The fixture bundle is what the adapter's output for the live record must equal
*modulo media hashes and `exported_at`* — the vinylCatalogue batch asserts that with a
copy of the record's `record.json` (metadata only, no photos) in its own tests.

## 12. Work packages, order, versioning

| WP | Repo | Delivers | Depends on |
|---|---|---|---|
| 0 | mediaCore | `mediacore` package (§3–5), `normalize_text`, fixture + generator, README/PROJECT_FACTS/gate, tag `v0.1.0` | — |
| 1 | vinylCatalogue | adapter, export gate, CLI + API + Browse action, spec §7.10 amendment, tests against the SAXY `record.json` copy | WP0 |
| 2 | humanNetworkMap | §8: migration, refs on schemas, preview/commit endpoints, Import view, tests per `TEST_SPEC.md` | WP0 |
| 3 | musicMap | §9: migration, refs, preview/commit, Import release dialog, tests | WP0 |
| 4 | human, interactive | sign off SAXY → export → import into an hNM **sandbox** (never the `humannetworkmap` DB) and the musicMap dev stack | WP1–3 |
| 5 | humanNetworkMap | §10: `GET /api/resolve`, URL state `?project=&node=&source=`, `?ref=` landing, "Open in musicMap" links, `VITE_PEER_MUSICMAP_URL` | WP2 |
| 6 | musicMap | §10: `GET /api/v1/resolve`, `?ref=` landing, "Open in hNM" links, `VITE_PEER_HNM_URL` | WP3 |
| 7a | mediaCore | §5.1: `mediacore.store` — `open_store`, `BundleStore` over `file://` and `s3://`, `BundleEntry`, fixture seeding, tag `v0.2.0` | WP0 |
| 7b | vinylCatalogue | §5.1 source side: `bundle_store_uri` config, `--store`, export writes an entry | 7a |
| 7c | humanNetworkMap | §5.1 inbox: `BUNDLE_STORE_URI`, inbox + preview-from-store endpoints, inbox section on the Import view | 7a, WP2 |
| 7d | musicMap | §5.1 inbox: same, replacing the `data/incoming/` pickup | 7a, WP3 |
| 7e | vinylCatalogue, optional | *imported where* on the record page via the peers' resolve endpoints | 7b, WP5, WP6 |

WP1–3 run in parallel once `v0.1.0` is tagged. Consumers pin
`mediacore @ git+https://github.com/ssdesai/mediaCore.git@v0.1.0`. Before 1.0 a
breaking change to §3 bumps the minor version and every consumer re-pins deliberately;
`schema_version` changes only when the on-disk `release.json` shape changes. WP7a adds a
module, not a field: `mediacore` **0.2.0**, `schema_version` unchanged.

WP7 is also an experiment on the delegation tier itself — each of 7a–7d is built twice,
once through the plan workflow and once by a single Opus delegate, from this section as
the shared brief. The checklist and scorecard live in humanNetworkMap
`plans/experiments/wp7-bundle-store/`.

Each WP is executed in its own repo with that repo's plan workflow
(`agentTooling/AGENT_PLANS.md`, `plans/PROJECT_FACTS.md`), on a bare camelCase branch,
by an agent briefed with this file.

## 13. Decisions log

- **2026-08-27 (WP7a) — `mediacore.store` implementation calls.** Taken while building
  §5.1; each one is either something §5.1 left open or a place the code is more specific
  than the design. `mediacore` **0.2.0** (§12: a module, not a field).
  - **The entry keys on the first `provenance` entry**, not on a `vinylcat`-kinded one
    and not on `refs["vinylcat:record"]` (which a bundle does not carry — the ULID is
    provenance, §4). `record_id`/`exported_at` are that entry's `id`/`exported_at`, so
    nothing vinyl-specific enters `src/` and `cd-rip`/`digital` exports key identically.
  - **`slug` is derived, not carried:** `release_slug` = `<artist>--<title>--<catalogue
    number>`, each segment folded over `normalize_text` and reduced to `[a-z0-9-]`,
    which reproduces §11's recorded slug from the release alone. Nothing survives the
    fold → `release`.
  - **`open(entry, dest=…)`** materialises the bundle into an empty directory. §5.1
    fixes the interface at three methods but the import path (§5.1 "One import path")
    needs the media bytes; a keyword on `open` serves that without a fourth method.
  - **`put` refuses an existing version** with `StoreError` rather than overwriting, and
    versions are keyed to whole seconds. **`all_versions=True` returns every version**,
    latest included.
  - **A malformed entry is reported, not skipped:** `list` raises `StoreError` naming the
    entry when its `release.json` is unreadable or has no provenance. A directory with no
    `release.json` at all is simply not an entry — which is also why the `s3` backend
    uploads `release.json` last, so an interrupted `put` is invisible rather than half
    there.
  - **`entry.uri` is untrusted input** (a browser posts it back): `open` refuses a URI
    that is not exactly one entry key under this store's own root.
  - **Faults inside a bundle stay `BundleError`** (hash, size, schema upgrade);
    `StoreError` is for store-level faults. A consumer catches the same exception whether
    the bundle arrived by upload or from a store.
  - **The `s3` backend is tested, not stubbed:** `moto` is a dev extra and the suite runs
    both backends through the same tests offline; `open_store(uri, s3_client=…)` injects
    a client, and with none it builds one from the ambient chain. `mediacore[s3]` is
    boto3 alone.
  - **Fixture seeding ships in the package** as `seed_its_saxy_store(uri)` (dev stacks
    install the wheel and cannot reach this repo's `scripts/`), and is idempotent: a
    second run returns the entry already there instead of colliding with the no-overwrite
    rule.

- **2026-08-27 — Transport generalised to a URI-addressed bundle store (§5.1).**
  Supersedes "bundle folder on disk" (2026-08-25) as the *shared* transport; the folder
  is now the `file://` backend and browser upload stays as the baseline. A record is
  exported once and both consumers pick it from the same store; hosting moves the store
  to `s3://` by configuration. Entries are versioned by `exported_at` and never
  overwritten or deleted; a consumer's inbox is derived from its own `refs`, so no
  consumer state lives in the store. Principle 6 (no shared DB) stands — a bucket of
  bundles is transport, not a database. Also the first plans-vs-direct A/B (§12).

- **2026-08-26 — conflict resolution on link/re-import is existing-wins, PATCH is the
  correction surface.** Both consumers merge refs additively with existing values
  winning; the preview displays conflicts but offers no per-key picker (deferred).
  Consequence: node/source update schemas MUST keep `refs` editable — with re-import
  never replacing, PATCH is the only way to fix a wrong ref. An explicit `refs: null`
  on PATCH is rejected (422), never "clear the bag". Media rows stay importer-owned
  (no `refs` on media update). Ratified by the owner on hNM PR #60 finding 4 and the
  musicMap WP3 open question.

- 2026-08-24 — Polyrepo + shared contract package, not a monorepo or shared DB.
- 2026-08-25 — Contract is a neutral `Release`, not vinylcat's `Record`; identity by
  authority refs; vinylcat IDs are provenance only.
- 2026-08-25 — Imports are human-supervised via an import page in each consumer; that
  page *is* the re-sync and merge policy. No unattended sync.
- 2026-08-25 — No confidence/envelopes in the contract; only signed-off records export.
- 2026-08-25 — `discogs:master` carried in refs; navigable Discogs links imported into
  hNM (source + nodes).
- 2026-08-25 — musicMap skips already-present songs by default; artist/album matching is
  human, like hNM.
- 2026-08-25 — Fixture is *IT'S SAXY* (SAAE 1012) from the Test collection; no other
  live data is touched.
- 2026-08-25 — Package/repo named **mediaCore**; public GitHub repo; consumed by pip git
  URL pinned to a tag; this repo is the management home.
- 2026-08-25 — Export gate = fourth-gate sign-off; the owner signs SAXY off before the
  end-to-end run.
- 2026-08-25 — Transport = bundle folder on disk, uploaded through the import page.
- 2026-08-25 — **Identity never hinges on Discogs or any single source.** Refs are
  supporting evidence on a consumer-owned entity; any may be absent; linking merges
  evidence additively; the human confirms every match. Supersedes the earlier
  "identity = authority refs" wording.

## 14. Open questions and follow-ups

Raised by an implementing agent → recorded here with the answer.

- 2026-08-27 (WP7a) — **`BundleEntry` reports `record_id` without the provenance
  `kind`.** The inbox rule (§5.1) tells a consumer to look for `vinylcat:record` in its
  own `refs` bags, but the entry does not say the id *is* a `vinylcat` one — the store
  deliberately keys on the first provenance entry whatever its kind. Today every export
  is `vinylcat`, so 7c/7d hard-code that key. If a second kind ever writes to a store,
  either `BundleEntry` gains `kind` (a §5.1 change and a consumer re-pin) or consumers
  match on any `<kind>:record`. Not resolved now: adding a sixth field for a producer
  that does not exist yet is speculative.
- 2026-08-27 (WP7a) — **`list()` reads every entry's `release.json`.** On `s3://` that
  is one `GET` per version, so a store holding thousands of versions makes an inbox page
  slow. Deliberate for now — it is what "never parsed out of its key" costs, and the
  real store holds one record per signed-off release. If it bites, the fix is an index
  object written beside the root by `put` and refreshed from a full listing, not parsing
  the keys.

- 2026-08-26 (WP1) — **Fixture lacks track durations.** The live IT'S SAXY record has
  `duration` on every track (`A1 1:57`, `A2 2:37`, …); §11 above omitted them, so
  `fixtures/its-saxy/release.json` has `null` for all twelve. Ruling: adapter emits
  durations; WP1's equality test excludes `tracks[].duration` until mediaCore **0.1.1**
  adds the twelve real values to §11 and the fixture generator. **Done in v0.1.1**
  (2026-08-26): §11 carries the twelve verified durations, the fixture generator emits
  them, and vinylCatalogue drops the exclusion when it bumps its pin.
- 2026-08-26 (WP1) — vinylCatalogue's spec says the fourth gate does not block
  `export`; that sentence is about the collection-wide CSV exports (§7.10). The
  per-record *bundle* export is gated on sign-off (this document §6); the CSV sentences
  are left as they are.
- 2026-08-26 (WP1) — hatchling refuses a git-URL dependency unless
  `[tool.hatch.metadata] allow-direct-references = true` is set. Consumers using
  hatchling need that line; pip-based consumers do not.
- 2026-08-27 (WP4) — **A link lives where its subject lives.** First real hNM import
  surfaced §8's original rule ("each artist/label link on its node *and* on the source")
  putting all five Discogs links on the IT'S SAXY source page. Owner ruled: an artist's
  Discogs page is about the artist, not about this record as a source — entity-matched
  links attach to their nodes only, and the source carries just the entity-less links
  (the release's own, plus any whose entities were all skipped, as a fallback so the
  evidence is retained). §8 amended; hNM commit path changed the same day.
- 2026-08-27 (Phase 2) — **Phase 2 designed as WP5/WP6** (§10 rewritten from four
  bullets to the full contract). Settled: resolve endpoints are project-independent and
  return disambiguation lists; hNM's resolver includes information sources (that is
  where `vinylcat:record` lives); `?ref=` on either frontend's root URL is the deep-link
  convention, consumed after handling; a single match may auto-navigate (navigation is
  not an import); `PEER_*` env vars realised as `VITE_PEER_MUSICMAP_URL` /
  `VITE_PEER_HNM_URL`, unset hides the buttons. The optional hNM-neighbourhood overlay
  in musicMap is deferred — needs a cross-origin story nothing else needs, and the
  "Open in hNM" button covers the workflow. WP5 and WP6 are independent and run in
  parallel; no mediaCore change needed (`ref_uri` / `parse_ref_uri` shipped in v0.1.0).
- 2026-08-27 — **`mediacore.__version__` said `0.1.0` in the v0.1.1 package** (the WP5
  plan author caught the mismatch against consumers' `@v0.1.1` pins). Fixed on `main`;
  not re-tagged — nothing reads the attribute programmatically, so the fix rides the
  next tag instead of forcing three re-pins.
- 2026-08-27 (WP6 review) — **No `truncated` flag on resolve responses.** Both
  consumers cap matches (musicMap at 100, documented and tested); a flag would be a
  wire-shape change on both sides for a disambiguation UI nobody scrolls. Deferred
  until a real catalogue makes a 100-match disambiguation plausible; the caps stay
  documented in each repo.
