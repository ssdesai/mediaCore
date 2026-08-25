"""Pins the ref-key grammar and ref URIs (INTEGRATION.md §4)."""

import pytest

from mediacore import (
    DISCOGS_ARTIST,
    DISCOGS_LABEL,
    DISCOGS_MASTER,
    DISCOGS_RELEASE,
    KNOWN_REF_KEYS,
    MUSICBRAINZ_ARTIST,
    MUSICBRAINZ_LABEL,
    MUSICBRAINZ_RECORDING,
    MUSICBRAINZ_RELEASE,
    MUSICBRAINZ_RELEASE_GROUP,
    REF_KEY_RE,
    parse_ref_uri,
    ref_uri,
    validate_refs,
)


@pytest.mark.parametrize(
    "key",
    [
        "discogs:release",
        "discogs:master",
        "discogs:artist",
        "discogs:label",
        "musicbrainz:release",
        "musicbrainz:release-group",
        "musicbrainz:artist",
        "musicbrainz:label",
        "musicbrainz:recording",
    ],
)
def test_valid_ref_keys_accepted(key):
    assert validate_refs({key: "1"}) == {key: "1"}


def test_unknown_but_well_formed_key_is_allowed():
    result = validate_refs({"newauthority:thing": "abc"})
    assert result == {"newauthority:thing": "abc"}
    assert "newauthority:thing" not in KNOWN_REF_KEYS


@pytest.mark.parametrize(
    "key",
    [
        "discogs",
        "isrc",
        "barcode",
        "discogs:",
        ":release",
        "Discogs:release",
        "discogs:Release",
        "discogs:release:extra",
        "1discogs:release",
        "discogs:-release",
        "discogs::release",
        "discogs release",
        "",
    ],
)
def test_invalid_ref_keys_rejected(key):
    with pytest.raises(ValueError):
        validate_refs({key: "1"})


def test_ref_values_must_be_non_empty_strings():
    with pytest.raises(ValueError):
        validate_refs({"discogs:artist": ""})
    with pytest.raises(ValueError):
        validate_refs({"discogs:artist": 5682050})


def test_validate_refs_returns_a_new_dict():
    input_dict = {"discogs:artist": "1"}
    result = validate_refs(input_dict)
    assert result == input_dict
    assert result is not input_dict


def test_empty_refs_are_valid():
    assert validate_refs({}) == {}


def test_known_ref_keys_all_match_the_grammar():
    assert len(KNOWN_REF_KEYS) == 9
    for key in KNOWN_REF_KEYS:
        assert REF_KEY_RE.match(key)


def test_known_ref_key_constants():
    expected_keys = {
        "discogs:release",
        "discogs:master",
        "discogs:artist",
        "discogs:label",
        "musicbrainz:release",
        "musicbrainz:release-group",
        "musicbrainz:artist",
        "musicbrainz:label",
        "musicbrainz:recording",
    }
    actual_keys = {
        DISCOGS_RELEASE,
        DISCOGS_MASTER,
        DISCOGS_ARTIST,
        DISCOGS_LABEL,
        MUSICBRAINZ_RELEASE,
        MUSICBRAINZ_RELEASE_GROUP,
        MUSICBRAINZ_ARTIST,
        MUSICBRAINZ_LABEL,
        MUSICBRAINZ_RECORDING,
    }
    assert actual_keys == expected_keys
    assert actual_keys.issubset(KNOWN_REF_KEYS)


def test_ref_uri_round_trips():
    assert ref_uri(DISCOGS_ARTIST, "5682050") == "discogs:artist:5682050"
    assert parse_ref_uri("discogs:artist:5682050") == ("discogs:artist", "5682050")
    assert ref_uri(MUSICBRAINZ_RELEASE_GROUP, "abc-123") == "musicbrainz:release-group:abc-123"
    assert parse_ref_uri("musicbrainz:release-group:abc-123") == (
        "musicbrainz:release-group",
        "abc-123",
    )


def test_ref_uri_rejects_an_invalid_key_or_value():
    with pytest.raises(ValueError):
        ref_uri("Discogs:artist", "1")
    with pytest.raises(ValueError):
        ref_uri("discogs:artist", "")


@pytest.mark.parametrize(
    "uri",
    [
        "discogs:artist",
        "discogs:artist:",
        "Discogs:artist:1",
        "nonsense",
        "",
    ],
)
def test_parse_ref_uri_rejects_malformed(uri):
    with pytest.raises(ValueError):
        parse_ref_uri(uri)


def test_parse_ref_uri_keeps_colons_in_the_value():
    assert parse_ref_uri("discogs:artist:a:b") == ("discogs:artist", "a:b")
