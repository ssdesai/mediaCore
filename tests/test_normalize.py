"""Pins `normalize_text` / `normalize_catno` (INTEGRATION.md §4). The fold
must stay byte-for-byte equivalent to `vinylcat.normalize` in the vinylCatalogue repo;
these samples are what both sides agree on."""

import pytest

from mediacore import normalize_catno, normalize_text


@pytest.mark.parametrize(
    "value,expected",
    [
        (None, ""),
        ("", ""),
        ("   ", ""),
        ("Café", "CAFE"),
        ("Björk", "BJORK"),
        ("Motörhead", "MOTORHEAD"),
        ("naïve café", "NAIVE CAFE"),
        ("Jy Is My Liefling", "JY IS MY LIEFLING"),
        ("  The   Duke's\tCombo\n", "THE DUKE'S COMBO"),
        ("A. A. E.", "A. A. E."),
        ("ﬁnal", "FINAL"),
        ("IT'S SAXY", "IT'S SAXY"),
    ],
)
def test_normalize_text(value, expected):
    assert normalize_text(value) == expected


@pytest.mark.parametrize(
    "value,expected",
    [
        (None, ""),
        ("", ""),
        ("SAAE 1012", "SAAE1012"),
        ("PB 41447", "PB41447"),
        ("PB-41447", "PB41447"),
        ("saae/1012", "SAAE1012"),
        ("Ünïcode-9", "UNICODE9"),
    ],
)
def test_normalize_catno(value, expected):
    assert normalize_catno(value) == expected


def test_normalize_text_is_idempotent():
    test_values = [
        None,
        "",
        "   ",
        "Café",
        "Björk",
        "Motörhead",
        "naïve café",
        "Jy Is My Liefling",
        "  The   Duke's\tCombo\n",
        "A. A. E.",
        "ﬁnal",
        "IT'S SAXY",
    ]
    for value in test_values:
        assert normalize_text(normalize_text(value)) == normalize_text(value)


def test_normalize_catno_matches_across_separator_styles():
    assert normalize_catno("PB 41447") == normalize_catno("PB-41447") == normalize_catno("pb41447")
