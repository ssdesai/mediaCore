# Tests: the normalize fold and the refs grammar

Feature `release-contract` (plan 2 of 12). The batch delivers the whole
`mediacore` contract package — the `Release` schema, refs, the normalize fold, the
bundle reader/writer — plus the *IT'S SAXY* fixture bundle and its generator.

Write `tests/test_normalize.py` and `tests/test_refs.py`, the level-1 unit tests for
`src/mediacore/normalize.py` and `src/mediacore/refs.py` (written by plan 05).

Depends on: `01-acceptance-tests-sonnet.md` for `tests/conftest.py` — but neither file
here uses it. Do not add anything to `conftest.py`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none —
`tests/README.md` is written by plan 01 and already describes both files).

## Pinned facts

- Package `mediacore`, src layout. Import from the package root:
  `from mediacore import normalize_text, normalize_catno` and
  `from mediacore import DISCOGS_ARTIST, KNOWN_REF_KEYS, REF_KEY_RE, parse_ref_uri,
  ref_uri, validate_refs`. Never import from a submodule.
- These modules do not exist yet — plan 05 writes them. Write the tests against the
  signatures below; do not create the source files.
- `normalize_text(value: str | None) -> str` — NFKD, drop combining marks, uppercase,
  collapse whitespace runs to one space, strip. `None` and `""` both give `""`.
- `normalize_catno(value: str | None) -> str` — `normalize_text` then remove every
  character outside `[A-Z0-9]`.
- `validate_refs(refs) -> dict[str, str]` raises `ValueError` on a key that does not
  match `REF_KEY_PATTERN = r"^[a-z][a-z0-9]*:[a-z][a-z0-9-]*$"` or on a value that is
  not a non-empty `str`. It returns a **new** dict.
- `ref_uri(key, value) -> str` is `f"{key}:{value}"`; `parse_ref_uri(s) -> tuple[str, str]`
  splits it back and raises `ValueError` on anything malformed.
- `KNOWN_REF_KEYS` is a `frozenset[str]` of the keys `INTEGRATION.md` §4 tabulates that
  the grammar can express: the four `discogs:*` keys and the five `musicbrainz:*` keys.
  §4 also lists `isrc` and `barcode`, which the grammar cannot express (no `<entity>`
  segment); they are deliberately **not** constants and must not appear in any test as
  valid.
- Pydantic is not needed by either file.

## Files

- Create `tests/test_normalize.py`
- Create `tests/test_refs.py`

## `tests/test_normalize.py`

One `@pytest.mark.parametrize` case list per function, plus two behaviour tests. Module
docstring: *"Pins `normalize_text` / `normalize_catno` (INTEGRATION.md §4). The fold
must stay byte-for-byte equivalent to `vinylcat.normalize` in the vinylCatalogue repo;
these samples are what both sides agree on."*

`normalize_text` cases — `(value, expected)`, exactly these:

```python
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
```

`normalize_catno` cases — `(value, expected)`, exactly these:

```python
(None, ""),
("", ""),
("SAAE 1012", "SAAE1012"),
("PB 41447", "PB41447"),
("PB-41447", "PB41447"),
("saae/1012", "SAAE1012"),
("Ünïcode-9", "UNICODE9"),
```

Plus:

- `test_normalize_text_is_idempotent` — for every sample value,
  `normalize_text(normalize_text(v)) == normalize_text(v)`.
- `test_normalize_catno_matches_across_separator_styles` — `normalize_catno("PB 41447")
  == normalize_catno("PB-41447") == normalize_catno("pb41447")`, the property §4 relies
  on for unmatched-release fallback matching.

## `tests/test_refs.py`

Module docstring: *"Pins the ref-key grammar and ref URIs (INTEGRATION.md §4)."*

- `test_valid_ref_keys_accepted` — parametrized over
  `["discogs:release", "discogs:master", "discogs:artist", "discogs:label",
  "musicbrainz:release", "musicbrainz:release-group", "musicbrainz:artist",
  "musicbrainz:label", "musicbrainz:recording"]`: `validate_refs({key: "1"}) == {key: "1"}`.
- `test_unknown_but_well_formed_key_is_allowed` — `validate_refs({"newauthority:thing":
  "abc"})` succeeds and the key is *not* in `KNOWN_REF_KEYS`. This is §4's extension
  point.
- `test_invalid_ref_keys_rejected` — parametrized, each raising `ValueError`:
  `"discogs"`, `"isrc"`, `"barcode"`, `"discogs:"`, `":release"`, `"Discogs:release"`,
  `"discogs:Release"`, `"discogs:release:extra"`, `"1discogs:release"`,
  `"discogs:-release"`, `"discogs::release"`, `"discogs release"`, `""`.
- `test_ref_values_must_be_non_empty_strings` — `validate_refs({"discogs:artist": ""})`
  and `validate_refs({"discogs:artist": 5682050})` each raise `ValueError`.
- `test_validate_refs_returns_a_new_dict` — the returned dict equals the input but is
  not the same object.
- `test_empty_refs_are_valid` — `validate_refs({}) == {}`.
- `test_known_ref_keys_all_match_the_grammar` — every member of `KNOWN_REF_KEYS`
  matches `REF_KEY_RE`, and `len(KNOWN_REF_KEYS) == 9`.
- `test_known_ref_key_constants` — the imported constants hold exactly
  `"discogs:release"`, `"discogs:master"`, `"discogs:artist"`, `"discogs:label"`,
  `"musicbrainz:release"`, `"musicbrainz:release-group"`, `"musicbrainz:artist"`,
  `"musicbrainz:label"`, `"musicbrainz:recording"`, and each is in `KNOWN_REF_KEYS`.
  Import them by their names: `DISCOGS_RELEASE`, `DISCOGS_MASTER`, `DISCOGS_ARTIST`,
  `DISCOGS_LABEL`, `MUSICBRAINZ_RELEASE`, `MUSICBRAINZ_RELEASE_GROUP`,
  `MUSICBRAINZ_ARTIST`, `MUSICBRAINZ_LABEL`, `MUSICBRAINZ_RECORDING`.
- `test_ref_uri_round_trips` — `ref_uri(DISCOGS_ARTIST, "5682050") ==
  "discogs:artist:5682050"` and `parse_ref_uri("discogs:artist:5682050") ==
  ("discogs:artist", "5682050")`; also round-trip
  `("musicbrainz:release-group", "abc-123")`.
- `test_ref_uri_rejects_an_invalid_key_or_value` — `ref_uri("Discogs:artist", "1")` and
  `ref_uri("discogs:artist", "")` each raise `ValueError`.
- `test_parse_ref_uri_rejects_malformed` — parametrized, each raising `ValueError`:
  `"discogs:artist"`, `"discogs:artist:"`, `"Discogs:artist:1"`, `"nonsense"`, `""`.
- `test_parse_ref_uri_keeps_colons_in_the_value` —
  `parse_ref_uri("discogs:artist:a:b") == ("discogs:artist", "a:b")`, since the key is
  exactly two segments.
