# Notes: release-original-year

Rulings the implementer made where the feature README's decisions left something open,
each with its reason. The decisions themselves are not repeated here.

## Rulings

- **The upper bound is read at validation time, not held in a constant.** "The current
  year" moves; a constant would go stale on the first of January. `EARLIEST_ORIGINAL_YEAR
  = 1877` is the named constant; the upper bound is `date.today().year` inside
  `Release._original_year_is_plausible`. Local date: a producer and a consumer in
  different zones can disagree only for a few hours around New Year, and the bound only
  ever widens, so nothing once valid becomes invalid. Recorded in `release.py`'s
  constant comment and `src/mediacore/README.md`.
- **Both checks live in one `Release` `model_validator`, not a field validator.** The
  ordering check needs `year`; keeping the bound beside it gives one place and one error
  vocabulary. Bounds are checked before ordering, so an out-of-range value is reported
  as out of range whatever `year` says. Both messages name `original_year`.
- **`original_year == year` is accepted.** The decision says "never later than `year`";
  equal is not later. A same-year reissue (a repress in the year of release) is real.
- **With `year` absent only the bounds apply.** IT'S SAXY itself has no `year`; a reissue
  of unknown pressing year may still know its original's.
- **Plain `int`, not `StrictInt`.** Matches `year` and every other int on the contract;
  tightening one field alone would be an inconsistency with no consumer asking for it.
- **`year` itself stays unvalidated.** Bounding it is a separate contract change (it
  would refuse bundles that read today); not in the decisions, not built, not
  backlogged — nobody has asked for it and no defect is known.
- **`EARLIEST_ORIGINAL_YEAR` is not re-exported from the package root.** Same standing as
  `MIN_ARTISTS`: consumers and the producer validate through `Release`, so the bound is
  enforced without anyone importing it, and the public surface `INTEGRATION.md` pins does
  not grow. The tests pin `1877` as a literal so a change to it is a deliberate edit.
- **A frozen schema-2 asset, `tests/assets/its-saxy-schema-2/release.json`.** A
  byte-for-byte copy of the fixture's `release.json` as `main` (0.3.0) wrote it, taken
  before regeneration — the schema-1 precedent (§13 2026-09-06): a backward read is only
  proven by an artefact the *old* writer produced. `test_release.py` validates it through
  `Release.model_validate` (decision 6); `test_bundle.py` also reads it through
  `read_bundle(verify=False)` and re-writes it to pin the stamp moving 2 → 3.
- **The package version is pinned as a literal too** (`CURRENT_PACKAGE_VERSION = "0.4.0"`
  in `test_release.py`), beside `CURRENT_SCHEMA_VERSION = 3`: schema and minor move
  together, so a bump of one without the other is caught.
- **The fixture generator names `ORIGINAL_YEAR = None` explicitly** rather than relying
  on the default, so the §11 fact ("not stated to be a reissue") is visible in the
  script's constants beside `YEAR`. The key reaches disk as `null` because the writer
  dumps the model whole — same as `Track.artist`.
- **`mediacore.store` is untouched.** `BundleEntry.schema_version` is read from the file,
  and every store test compares against `SCHEMA_VERSION` symbolically, so the bump
  carries through with no edit there.

## Deviations from the decisions

- None.

## Left unbuilt (backlogged)

- vinylCatalogue's adapter filling `original_year`, and the three consumer re-pins to
  `v0.4.0` — excluded by the feature README; `plans/BACKLOG.md` has an entry for each
  side.

## Open questions

- None.
