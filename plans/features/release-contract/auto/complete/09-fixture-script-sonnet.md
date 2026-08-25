# The IT'S SAXY fixture generator

Feature `release-contract` (plan 8 of 12, level 2). The batch delivers the whole
`mediacore` contract package — the `Release` schema, refs, the normalize fold, the
bundle reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Create `scripts/make_fixture_its_saxy.py`: a deterministic, stdlib-only generator that
writes the §11 fixture bundle through `mediacore.write_bundle`.

Depends on: `07-package-bundle-sonnet.md` (the whole package is on disk and green).

**You cannot run this script — build executors have no bash.** `fixtures/its-saxy/` is
written when the level-2 gate and the batch's verify plan run it. Do not create any
file under `fixtures/its-saxy/`, and do not hand-write `release.json`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

## Pinned facts

- Import the public surface from the package root:
  `from mediacore import AudioFile, ArtistRef, Credit, LabelRef, Link, MediaFile,
  Provenance, Release, Track, write_bundle, BUNDLE_MEDIA_DIRNAME, DISCOGS_ARTIST,
  DISCOGS_LABEL, DISCOGS_RELEASE`. `mediacore` is installed editable into `.venv`.
- `write_bundle(release, dest, files: Mapping[str, Path]) -> Path` — `files` maps
  **sha256 → source path**; it validates every mapping entry, then replaces `dest`
  wholesale and writes `release.json` + `media/<sha256>.<ext>`.
- Model shapes (INTEGRATION.md §3): `Release { schema_version, refs, provenance, title,
  artists, labels, year, released, country, medium, format, genres, styles, tracks,
  credits, notes, tags, media, audio, links }`; `ArtistRef { name, sort_name, refs }`;
  `LabelRef { name, catalogue_number, refs }`; `Track { position, title, duration,
  credits }`; `Credit { role, name, refs }`; `MediaFile { kind, role, sha256, file,
  mime, source_url, refs }`; `AudioFile { track_position, sha256, file, format,
  size_bytes }`; `Link { label, url, refs }`; `Provenance { kind, id, label,
  exported_at }`. All are `extra="forbid"`.
- Ruff runs with `select = ["E", "F", "I", "B", "UP"]`, line length 100, target py311.
  **`B905`: every `zip()` needs an explicit `strict=True`.** Ruff is configured to
  check `src tests` only, but write this file to the same standard.
- CONVENTIONS.md: every magic value is a named constant at the top of the file, grouped
  under a short label comment. That applies to every byte-level constant here.

## Files

- Create `scripts/make_fixture_its_saxy.py`
- Create `scripts/README.md`
- Modify `README.md` (repo root)

## `scripts/make_fixture_its_saxy.py`

Module docstring:

> Regenerate the IT'S SAXY contract fixture (INTEGRATION.md §11).
>
> Usage: `python scripts/make_fixture_its_saxy.py [dest]` — `dest` defaults to
> `fixtures/its-saxy` at the repo root.
>
> The metadata below is one real, Discogs-matched record's, transcribed from
> `INTEGRATION.md` §11. The media are **placeholders**: 1×1 PNGs and short silent WAVs
> synthesized from the constants in this file. Nothing here reads the clock, the
> filesystem or the network, and no value is random — running this twice must produce
> byte-identical trees, because every filename in the bundle is the sha256 of the bytes
> it holds. `plans/gate.sh` asserts exactly that. `EXPORTED_AT` is a fixed constant for
> the same reason.

Imports: `hashlib`, `struct`, `sys`, `tempfile`, `zlib`, `datetime`, `pathlib.Path`,
and the `mediacore` names above.

### Placeholder-media helpers

Paste verbatim — these are byte-level formats where the exact output is the point:

```python
# Deflate/zlib framing. zlib.compress() would be shorter, but its exact output can
# differ between zlib builds, and these bytes decide the fixture's filenames — so the
# payload goes into one uncompressed ("stored") block, which is specified byte-for-byte.
ZLIB_HEADER = b"\x78\x01"           # CM=8, CINFO=7, no preset dict, check bits valid
DEFLATE_FINAL_STORED_BLOCK = b"\x01"  # BFINAL=1, BTYPE=00, padded to a byte boundary
STORED_BLOCK_LENGTH_MASK = 0xFFFF
CHECKSUM_MASK = 0xFFFFFFFF

# PNG: a 1x1 opaque truecolour image, one per placeholder photo.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_IHDR = b"IHDR"
PNG_IDAT = b"IDAT"
PNG_IEND = b"IEND"
PNG_WIDTH = 1
PNG_HEIGHT = 1
PNG_BIT_DEPTH = 8
PNG_COLOUR_TYPE_RGB = 2
PNG_COMPRESSION_DEFLATE = 0
PNG_FILTER_METHOD_ADAPTIVE = 0
PNG_INTERLACE_NONE = 0
PNG_FILTER_NONE = 0
PNG_EXTENSION = "png"
PNG_MIME = "image/png"

# WAV: mono 8-bit PCM silence. 8-bit samples are unsigned, so silence is 0x80.
WAV_PCM_FORMAT = 1
WAV_CHANNELS = 1
WAV_SAMPLE_RATE = 8000
WAV_BITS_PER_SAMPLE = 8
WAV_SILENT_SAMPLE = 0x80
BITS_PER_BYTE = 8
WAV_EXTENSION = "wav"
WAV_FORMAT = "wav"
# Each track gets a different length, so no two placeholder files share a sha256 and
# collapse into one entry in a content-addressed bundle. Kept even so the RIFF data
# chunk never needs a pad byte.
AUDIO_BASE_FRAMES = 800
AUDIO_FRAME_STEP = 8


def _deflate_stored(payload: bytes) -> bytes:
    """A zlib stream carrying `payload` in a single uncompressed deflate block."""
    return (
        ZLIB_HEADER
        + DEFLATE_FINAL_STORED_BLOCK
        + struct.pack("<HH", len(payload), len(payload) ^ STORED_BLOCK_LENGTH_MASK)
        + payload
        + struct.pack(">I", zlib.adler32(payload) & CHECKSUM_MASK)
    )


def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & CHECKSUM_MASK)
    )


def png_bytes(rgb: tuple[int, int, int]) -> bytes:
    """A 1x1 opaque PNG of one colour."""
    scanline = bytes((PNG_FILTER_NONE, *rgb))
    header = struct.pack(
        ">IIBBBBB",
        PNG_WIDTH,
        PNG_HEIGHT,
        PNG_BIT_DEPTH,
        PNG_COLOUR_TYPE_RGB,
        PNG_COMPRESSION_DEFLATE,
        PNG_FILTER_METHOD_ADAPTIVE,
        PNG_INTERLACE_NONE,
    )
    return (
        PNG_SIGNATURE
        + _png_chunk(PNG_IHDR, header)
        + _png_chunk(PNG_IDAT, _deflate_stored(scanline))
        + _png_chunk(PNG_IEND, b"")
    )


def wav_bytes(frames: int) -> bytes:
    """A mono 8-bit PCM WAV holding `frames` samples of silence."""
    data = bytes([WAV_SILENT_SAMPLE]) * frames
    block_align = WAV_CHANNELS * WAV_BITS_PER_SAMPLE // BITS_PER_BYTE
    byte_rate = WAV_SAMPLE_RATE * block_align
    fmt_chunk = struct.pack(
        "<HHIIHH",
        WAV_PCM_FORMAT,
        WAV_CHANNELS,
        WAV_SAMPLE_RATE,
        byte_rate,
        block_align,
        WAV_BITS_PER_SAMPLE,
    )
    body = (
        b"WAVE"
        + b"fmt "
        + struct.pack("<I", len(fmt_chunk))
        + fmt_chunk
        + b"data"
        + struct.pack("<I", len(data))
        + data
    )
    return b"RIFF" + struct.pack("<I", len(body)) + body
```

### The §11 metadata

Paste verbatim — this is pure data, transcribed from `INTEGRATION.md` §11, and every
value is asserted by `tests/test_fixture.py`:

```python
# Where the fixture is written when no destination is given.
FIXTURE_SLUG = "its-saxy"
FIXTURES_DIRNAME = "fixtures"

# Identity (INTEGRATION.md §11). No discogs:master — the release has none.
DISCOGS_RELEASE_ID = "16853262"
DISCOGS_ARTIST_ID = "5682050"
DISCOGS_LABEL_ID = "1504762"
DISCOGS_RELEASE_URL = "https://www.discogs.com/release/16853262-The-Dukes-Combo-Its-Saxy"
DISCOGS_ARTIST_URL_PREFIX = "https://www.discogs.com/artist/"
DISCOGS_LABEL_URL_PREFIX = "https://www.discogs.com/label/"
DISCOGS_LINK_LABEL_PREFIX = "Discogs: "

# Provenance: the vinylcat record this was exported from, and a fixed instant so the
# generator is deterministic.
PROVENANCE_KIND = "vinylcat"
VINYLCAT_RECORD_ID = "01M08WYYQGY1S66KY425FYCBS7"
COLLECTION_LABEL = "Test"
EXPORTED_AT = datetime(2026, 8, 25, 0, 0, 0, tzinfo=timezone.utc)

TITLE = "IT'S SAXY"
ARTIST_NAME = "The Duke's Combo"
ARTIST_SORT_NAME = "Duke's Combo, The"
LABEL_NAME = "A. A. E."
CATALOGUE_NUMBER = "SAAE 1012"
COUNTRY = "South Africa"
MEDIUM = "vinyl"
RELEASE_FORMAT = "Vinyl, LP, Album"
YEAR = None          # Discogs says 0; §11 records the year as unknown
RELEASED = None
GENRES = [
    "Jazz",
    "Rock",
    "Funk / Soul",
    "Blues",
    "Folk, World, & Country",
    "Stage & Screen",
]

TRACKS = [
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
# position -> (role, credited name, discogs artist id)
TRACK_CREDITS = {
    "B5": ("Written-By", "peter tetteroo", "282874"),
    "B6": ("Written-By", "Terry Dempsey", "1033325"),
}

# Placeholder photos. The roles are vinylCatalogue's; the colours only exist to give
# each file its own sha256.
PHOTO_ROLES = ("label_a", "label_b")
PHOTO_COLOURS = ((0x2E, 0x3B, 0x4E), (0x4E, 0x3B, 0x2E))
# The live record carries two images from the Discogs release. The fixture's copies are
# placeholders, and so are these URLs: they are the Discogs image-CDN shape for this
# release, not addresses that were fetched.
EXTERNAL_PHOTO_URLS = (
    "https://i.discogs.com/R-16853262-0001.jpeg",
    "https://i.discogs.com/R-16853262-0002.jpeg",
)
EXTERNAL_PHOTO_COLOURS = ((0x7A, 0x6C, 0x52), (0x52, 0x6C, 0x7A))
```

### Building and writing

Write these, in prose terms — the shapes above settle the rest:

- `build_release() -> tuple[Release, dict[str, bytes]]`. Keep a `payloads`
  `{sha256: bytes}` dict and a small closure that hashes a payload, records it, and
  returns the digest, so a file's name and its `sha256` field can never disagree.
  - `media`: the two `PHOTO_ROLES`/`PHOTO_COLOURS` pairs as `kind="photo"` with
    `mime=PNG_MIME`, `role`, no `source_url`, no `refs`; then the two
    `EXTERNAL_PHOTO_URLS`/`EXTERNAL_PHOTO_COLOURS` pairs as `kind="external_photo"`
    with `source_url` and `refs={DISCOGS_RELEASE: DISCOGS_RELEASE_ID}` and no `role`.
    Every `file` is `f"{BUNDLE_MEDIA_DIRNAME}/{digest}.{PNG_EXTENSION}"`.
  - `audio`: one `AudioFile` per entry of `TRACKS`, in order, from
    `wav_bytes(AUDIO_BASE_FRAMES + index * AUDIO_FRAME_STEP)`, with
    `track_position`, `format=WAV_FORMAT`, `size_bytes=len(data)`, and
    `file=f"{BUNDLE_MEDIA_DIRNAME}/{digest}.{WAV_EXTENSION}"`.
  - `tracks`: one `Track` per `TRACKS` entry, `duration=None`, `credits=[]` except for
    the two positions in `TRACK_CREDITS`, which get one `Credit` with the role, the
    name, and `refs={DISCOGS_ARTIST: <id>}`.
  - `links`, in this exact order: the release (`DISCOGS_LINK_LABEL_PREFIX + TITLE`,
    `DISCOGS_RELEASE_URL`, `{DISCOGS_RELEASE: DISCOGS_RELEASE_ID}`); the artist
    (`… + ARTIST_NAME`, `DISCOGS_ARTIST_URL_PREFIX + DISCOGS_ARTIST_ID`,
    `{DISCOGS_ARTIST: DISCOGS_ARTIST_ID}`); the label (`… + LABEL_NAME`,
    `DISCOGS_LABEL_URL_PREFIX + DISCOGS_LABEL_ID`,
    `{DISCOGS_LABEL: DISCOGS_LABEL_ID}`); then one per credited artist in `TRACKS`
    order — B5's `peter tetteroo`, then B6's `Terry Dempsey` — each
    `(DISCOGS_LINK_LABEL_PREFIX + name, DISCOGS_ARTIST_URL_PREFIX + id,
    {DISCOGS_ARTIST: id})`.
  - The `Release` itself: `refs={DISCOGS_RELEASE: DISCOGS_RELEASE_ID}`, one
    `Provenance`, `title`, one `ArtistRef` (name, sort name, `{DISCOGS_ARTIST: …}`),
    one `LabelRef` (name, `catalogue_number`, `{DISCOGS_LABEL: …}`), `year=YEAR`,
    `released=RELEASED`, `country`, `medium=MEDIUM`, `format=RELEASE_FORMAT`,
    `genres=GENRES`, and *nothing else set* — `styles`, `credits`, `tags` stay empty
    and `notes` stays `None`, per §11.
- `default_destination() -> Path` — `<repo root>/fixtures/its-saxy`, where the repo
  root is this file's `parents[1]` (`scripts/` sits directly under it).
- `main(argv: list[str]) -> int` — destination from `argv[1]` when given, else
  `default_destination()`. Build the release, stage every payload into a
  `tempfile.TemporaryDirectory()` (one file per digest, named by the digest), then call
  `write_bundle(release, destination, files)`. Print the destination and the file count.
  Return `0`.
- `if __name__ == "__main__": raise SystemExit(main(sys.argv))`.

## `scripts/README.md`

```markdown
# scripts

Standalone maintenance scripts. Each one is run by hand or by `plans/gate.sh`, never
imported. They require `mediacore` to be installed (`.venv/bin/python -m pip install -e
".[dev]"`).

- `make_fixture_its_saxy.py` — regenerates the IT'S SAXY contract fixture
  (`INTEGRATION.md` §11) into `fixtures/its-saxy/`, or into a destination given as the
  first argument. Deterministic by construction: the metadata is a set of module
  constants, the placeholder PNGs and WAVs are synthesized from constants with stdlib
  `struct`/`zlib` only, and `EXPORTED_AT` is fixed — no clock, no randomness, no
  network. That matters because every filename in the bundle is the sha256 of its own
  bytes, so a non-deterministic generator would rewrite the whole fixture on every run.
  `plans/gate.sh`'s "fixture idempotent" section runs it twice and requires both trees
  to be byte-identical and `git status --porcelain fixtures/` to be clean. It writes
  through `mediacore.write_bundle`, so the fixture is also a live test of the writer.
```

## `README.md` (repo root)

In the `## Contents` table, delete the trailing *(created by the first feature batch)*
note from the four rows that carry it (`src/mediacore/`, `tests/`,
`fixtures/its-saxy/`, `scripts/`) — those folders now exist. Change nothing else in the
row text, and nothing else in the file.
