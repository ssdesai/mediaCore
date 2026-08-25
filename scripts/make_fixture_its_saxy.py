"""Regenerate the IT'S SAXY contract fixture (INTEGRATION.md §11).

Usage: `python scripts/make_fixture_its_saxy.py [dest]` — `dest` defaults to
`fixtures/its-saxy` at the repo root.

The metadata below is one real, Discogs-matched record's, transcribed from
`INTEGRATION.md` §11. The media are **placeholders**: 1×1 PNGs and short silent WAVs
synthesized from the constants in this file. Nothing here reads the clock, the
filesystem or the network, and no value is random — running this twice must produce
byte-identical trees, because every filename in the bundle is the sha256 of the bytes
it holds. `plans/gate.sh` asserts exactly that. `EXPORTED_AT` is a fixed constant for
the same reason.
"""

import hashlib
import struct
import sys
import tempfile
import zlib
from datetime import datetime, timezone
from pathlib import Path

from mediacore import (
    BUNDLE_MEDIA_DIRNAME,
    DISCOGS_ARTIST,
    DISCOGS_LABEL,
    DISCOGS_RELEASE,
    ArtistRef,
    AudioFile,
    Credit,
    LabelRef,
    Link,
    MediaFile,
    Provenance,
    Release,
    Track,
    write_bundle,
)

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


def build_release() -> tuple[Release, dict[str, bytes]]:
    """Build the IT'S SAXY release and its content-addressed media payloads."""
    payloads: dict[str, bytes] = {}

    def _record(data: bytes) -> str:
        digest = hashlib.sha256(data).hexdigest()
        payloads[digest] = data
        return digest

    media = []
    for role, rgb in zip(PHOTO_ROLES, PHOTO_COLOURS, strict=True):
        digest = _record(png_bytes(rgb))
        media.append(
            MediaFile(
                kind="photo",
                role=role,
                sha256=digest,
                file=f"{BUNDLE_MEDIA_DIRNAME}/{digest}.{PNG_EXTENSION}",
                mime=PNG_MIME,
            )
        )
    for url, rgb in zip(EXTERNAL_PHOTO_URLS, EXTERNAL_PHOTO_COLOURS, strict=True):
        digest = _record(png_bytes(rgb))
        media.append(
            MediaFile(
                kind="external_photo",
                sha256=digest,
                file=f"{BUNDLE_MEDIA_DIRNAME}/{digest}.{PNG_EXTENSION}",
                mime=PNG_MIME,
                source_url=url,
                refs={DISCOGS_RELEASE: DISCOGS_RELEASE_ID},
            )
        )

    audio = []
    for index, (position, _title) in enumerate(TRACKS):
        data = wav_bytes(AUDIO_BASE_FRAMES + index * AUDIO_FRAME_STEP)
        digest = _record(data)
        audio.append(
            AudioFile(
                track_position=position,
                sha256=digest,
                file=f"{BUNDLE_MEDIA_DIRNAME}/{digest}.{WAV_EXTENSION}",
                format=WAV_FORMAT,
                size_bytes=len(data),
            )
        )

    tracks = []
    for position, title in TRACKS:
        credits = []
        if position in TRACK_CREDITS:
            role, name, artist_id = TRACK_CREDITS[position]
            credits.append(Credit(role=role, name=name, refs={DISCOGS_ARTIST: artist_id}))
        tracks.append(Track(position=position, title=title, duration=None, credits=credits))

    links = [
        Link(
            label=DISCOGS_LINK_LABEL_PREFIX + TITLE,
            url=DISCOGS_RELEASE_URL,
            refs={DISCOGS_RELEASE: DISCOGS_RELEASE_ID},
        ),
        Link(
            label=DISCOGS_LINK_LABEL_PREFIX + ARTIST_NAME,
            url=DISCOGS_ARTIST_URL_PREFIX + DISCOGS_ARTIST_ID,
            refs={DISCOGS_ARTIST: DISCOGS_ARTIST_ID},
        ),
        Link(
            label=DISCOGS_LINK_LABEL_PREFIX + LABEL_NAME,
            url=DISCOGS_LABEL_URL_PREFIX + DISCOGS_LABEL_ID,
            refs={DISCOGS_LABEL: DISCOGS_LABEL_ID},
        ),
    ]
    for position, _title in TRACKS:
        if position in TRACK_CREDITS:
            _role, name, artist_id = TRACK_CREDITS[position]
            links.append(
                Link(
                    label=DISCOGS_LINK_LABEL_PREFIX + name,
                    url=DISCOGS_ARTIST_URL_PREFIX + artist_id,
                    refs={DISCOGS_ARTIST: artist_id},
                )
            )

    release = Release(
        refs={DISCOGS_RELEASE: DISCOGS_RELEASE_ID},
        provenance=[
            Provenance(
                kind=PROVENANCE_KIND,
                id=VINYLCAT_RECORD_ID,
                label=COLLECTION_LABEL,
                exported_at=EXPORTED_AT,
            )
        ],
        title=TITLE,
        artists=[
            ArtistRef(
                name=ARTIST_NAME,
                sort_name=ARTIST_SORT_NAME,
                refs={DISCOGS_ARTIST: DISCOGS_ARTIST_ID},
            )
        ],
        labels=[
            LabelRef(
                name=LABEL_NAME,
                catalogue_number=CATALOGUE_NUMBER,
                refs={DISCOGS_LABEL: DISCOGS_LABEL_ID},
            )
        ],
        year=YEAR,
        released=RELEASED,
        country=COUNTRY,
        medium=MEDIUM,
        format=RELEASE_FORMAT,
        genres=GENRES,
        styles=[],
        tracks=tracks,
        credits=[],
        notes=None,
        tags=[],
        media=media,
        audio=audio,
        links=links,
    )
    return release, payloads


def default_destination() -> Path:
    """`fixtures/its-saxy` at the repo root."""
    return Path(__file__).resolve().parents[1] / FIXTURES_DIRNAME / FIXTURE_SLUG


def main(argv: list[str]) -> int:
    destination = Path(argv[1]) if len(argv) > 1 else default_destination()
    release, payloads = build_release()
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        files = {}
        for digest, data in payloads.items():
            staged = tmp_path / digest
            staged.write_bytes(data)
            files[digest] = staged
        write_bundle(release, destination, files)
    print(f"{destination} ({len(payloads)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
