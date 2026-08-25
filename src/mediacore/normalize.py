"""The shared name-matching fold (INTEGRATION.md §4).

Byte-for-byte the same algorithm as `vinylcat.normalize` in the vinylCatalogue repo.
Every consumer falls back to `normalize_text` equality when a release carries no
authority refs, so a divergence here silently stops matching entities that the source
repo considers identical. `tests/test_normalize.py` pins the samples both sides agree
on.
"""

from __future__ import annotations

import re
import unicodedata

_WHITESPACE_RE = re.compile(r"\s+")
_NON_ALNUM_RE = re.compile(r"[^A-Z0-9]")


def normalize_text(value: str | None) -> str:
    """Uppercase, NFKD accent-strip, whitespace collapse."""
    if not value:
        return ""
    stripped = "".join(
        c for c in unicodedata.normalize("NFKD", value) if not unicodedata.combining(c)
    )
    return _WHITESPACE_RE.sub(" ", stripped.upper()).strip()


def normalize_catno(value: str | None) -> str:
    """`normalize_text` plus stripping every non-alphanumeric character, so
    `"PB 41447"` and `"PB-41447"` compare equal.
    """
    return _NON_ALNUM_RE.sub("", normalize_text(value))
