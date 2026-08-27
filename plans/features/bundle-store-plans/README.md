# Bundle store (`mediacore.store`) — WP7a, `plans` arm

WP7a of the cross-repo integration (`INTEGRATION.md` §12): the URI-addressed bundle
store designed in §5.1 — `open_store(uri) -> BundleStore` with `list` / `open` / `put`
over `file://` and `s3://`, the `BundleEntry` shape, the versioned layout, and fixture
seeding so the store path is exercised by tests rather than only by upload. `mediacore`
goes to **0.2.0**; `schema_version` is unchanged, because this adds a module and not a
field.

This is one arm of an A/B on the delegation tier itself, not just a feature. The
question, the acceptance checklist and the scorecard live in humanNetworkMap
`plans/experiments/wp7-bundle-store/`; the `direct` arm builds the same brief with a
single Opus delegate on `bundleStoreDirect`. Both arms are off the same prep commit
(mediaCore `main` @ `f47d670`) and run the same agentTooling
(`git-subtree-split: daba8d6`) — the doctrine under test is *who builds*, not which
version of the harness. **Neither arm's tree is read while authoring or building the
other.**

> **Sections below the header are the architect's to fill in** — Plans, Levels,
> Contracts across levels, Deliberately excluded. The `Machine-readable` block is
> already correct and is the coordinator's: `branches` was copied verbatim from
> `git branch --show-current` in this worktree, and the only edit it needs is the
> `plans` array, which must list every plan stem in the table below, without `.md`, in
> batch order.

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/01-acceptance-tests-sonnet.md` | Black-box acceptance: `tests/test_store_fixture.py` seeds the committed IT'S SAXY bundle into a store and drives §5.1's whole story — put, list, open, re-export, seeding — parametrized over **both** backends, because §5.1's claim is that the local→hosted move is configuration and not code. Also owns the batch's shared `tests/conftest.py` builders (`file_store_uri`, `s3_store_uri`, `store_uri`, `its_saxy_source`). RED until level 3. |
| `auto/incomplete/02-tests-store-core-haiku.md` | `tests/test_store.py` — the backend-independent half: `open_store` scheme dispatch and its refusals, the `BundleEntry` shape and its JSON form, `bundle_slug`, the rule that entry fields come from `release.json` and never from the path, `list` ordering, `__version__` against the installed metadata. |
| `auto/incomplete/03-tests-store-file-sonnet.md` | `tests/test_store_file.py` — the `file://` backend: the layout `put` writes, versioning, latest-per-record, `open` verifying, and every failure §5.1 implies. |
| `auto/incomplete/04-store-core-file-sonnet.md` | `src/mediacore/store.py` (the seam plus `FileBundleStore`), `src/mediacore/__init__.py`, `pyproject.toml` (0.2.0, the `s3` extra, `boto3` + `moto[s3]` in `dev`), `src/mediacore/README.md`. |
| `auto/incomplete/05-gate.md` | Level 1 sentinel. |
| `auto/incomplete/06-tests-store-s3-sonnet.md` | `tests/test_store_s3.py` — the same behaviour over `s3://` against `moto`, plus the key layout under a prefix, listing across pages, a half-uploaded entry staying unlisted, and the missing-`boto3` message. |
| `auto/incomplete/07-store-s3-sonnet.md` | `S3BundleStore` and the `s3` branch of `open_store` in `src/mediacore/store.py`; `src/mediacore/README.md`. |
| `auto/incomplete/08-gate.md` | Level 2 sentinel. |
| `auto/incomplete/09-fixture-seeding-sonnet.md` | `seed_its_saxy_store` in `src/mediacore/fixtures.py`, `scripts/seed_bundle_store.py`, and the documentation: `scripts/`, `fixtures/`, `src/mediacore/` and root `README.md`, plus `plans/PROJECT_FACTS.md`. |
| `auto/incomplete/10-gate.md` | Level 3 sentinel. |
| `verify/incomplete/05-level-store-core-sonnet.md` | Level 1 level-verify (skipped when level 1's gate is green). |
| `verify/incomplete/08-level-store-s3-sonnet.md` | Level 2 level-verify (skipped when level 2's gate is green). |
| `verify/incomplete/10-level-fixture-store-sonnet.md` | Level 3 level-verify (skipped when level 3's gate is green). |
| `verify/incomplete/11-verify-sonnet.md` | Final verify: that `boto3` is genuinely optional in a clean install, that `mediacore` takes no keys, that nothing deletes, and that the two backends do not diverge. |
| `review/incomplete/12-review-opus.md` | Reads the diff against `main` and judges it against §5.1 and the six rulings §5.1 does not settle. |

Tests split three ways rather than one file per module (`AGENT_PLANS.md` → "Splitting
tests plans"): `mediacore.store` is one module but ~30 cases, so it splits by behaviour
group — backend-independent, `file://`, `s3://` — and the `s3://` group falls on a level
boundary anyway. The shared `conftest.py` fixtures belong to plan 01, the
lowest-numbered tests plan; 02, 03 and 06 use them by name and add none.

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| 1 — the seam and `file://` | 02–04 | `05-gate.md` | `05-level-store-core-sonnet.md` | install, lint, fixture idempotent, wheel contains fixture, tests — except `tests/test_store_fixture.py` and `tests/test_store_s3.py` (expected-red) |
| 2 — `s3://` | 06–07 | `08-gate.md` | `08-level-store-s3-sonnet.md` | all of the above **including** `tests/test_store_s3.py`; only `tests/test_store_fixture.py` is expected-red |
| 3 — fixture seeding | 09 | `10-gate.md` | `10-level-fixture-store-sonnet.md` | everything, including `tests/test_store_fixture.py` |

Plan 01 sits above all three: it is the batch's acceptance test and is red until level
3 puts `seed_its_saxy_store` on disk.

Nothing is `defer:`red at any level. This batch adds a module and no new gate section,
so all five sections run from level 1 — and `fixture idempotent` / `wheel contains
fixture` are load-bearing at every sentinel rather than irrelevant to the early ones:
they are what catches a store written into the checkout.

**Build executors have no bash, so no build plan can seed a store.** The seed is a
library function (`seed_its_saxy_store`) exercised by `tests/test_store_fixture.py`
against `tmp_path` when the gate runs the suite, plus `scripts/seed_bundle_store.py` for
a human setting up a dev stack. No committed bytes and no new gate section: the last
batch in this repo hit the same constraint and routed the fixture's bytes through the
gate's `fixture idempotent` section, which worked only because a *generated fixture* is
supposed to end up committed. A store is runtime state outside the checkout, so
committing one would be wrong even if an executor could produce it. Plans 01 and 09
both say so, and level 3's sentinel names `fixture idempotent` as the check that catches
it.

## Contracts across levels

| Value / identifier | Produced by (plan, file) | Consumed by (plan, file) | Fixture | Asserted by |
|---|---|---|---|---|
| `BundleEntry { record_id, exported_at, slug, uri, schema_version }`, frozen, `extra="forbid"` | 04, `src/mediacore/store.py` | 07, `store.py` (`S3BundleStore`); 09, `src/mediacore/fixtures.py`; WP7c/7d's `InboxEntryOut` | — in-process between the levels; its JSON form is what crosses to the consumers | `test_store.py::test_bundle_entry_fields`, `::test_bundle_entry_serializes_for_a_consumer` / `test_store_fixture.py::test_put_lists_and_opens_the_fixture` |
| Layout `<root>/<record ULID>/<exported_at as `%Y%m%dT%H%M%SZ`>/<slug>/`, via the shared `_layout_parts` | 04, `store.py` | 07, `store.py` (the same segments as key parts); 09 | `fixtures/its-saxy/release.json`, which is what lands at the leaf | `test_store_file.py::test_put_writes_the_documented_layout` / `test_store_s3.py::test_put_writes_the_documented_keys` |
| `record_id` and `exported_at` = the `provenance` entry whose `kind == "vinylcat"` (§4) | 04, `store.py` | 07; 09; produced by vinylCatalogue's adapter (§6); filed by WP7c/7d under the `vinylcat:record` ref key (§8) | `fixtures/its-saxy/release.json` → `provenance[0]` | `test_store.py::test_entry_fields_come_from_release_json_not_the_path`, `test_store_file.py::test_put_requires_vinylcat_provenance` / `test_store_fixture.py::test_put_lists_and_opens_the_fixture` |
| `bundle_slug(release)` = `the-duke-s-combo--it-s-saxy--saae-1012` for IT'S SAXY — the slug §11 records for it in vinylCatalogue | 04, `store.py` | 07 (key segment); 09; WP7b writes entries with it | `fixtures/its-saxy/release.json` | `test_store.py::test_bundle_slug_matches_the_vinylcat_slug` / `test_store_fixture.py::test_slug_matches_the_vinylcat_slug` |
| Shared backend helpers: the raw-payload entry parse, the latest-per-record selection, `S3_LIST_PAGE_SIZE`, `_import_boto3` | 04, `store.py` | 07, `store.py` | — in-process | `test_store.py::test_list_returns_newest_first` / `test_store_s3.py::test_list_spans_pages`, `::test_missing_boto3_names_the_extra` |
| `open(entry \| uri, *, verify=True)` — accepts an entry's own `uri` string | 04, `store.py` | 07; WP7c/7d's `POST …/imports/release/preview-from-store { entry_uri }` | the `uri` on each `BundleEntry` | `test_store_file.py::test_open_accepts_an_entry_or_its_uri` / `test_store_s3.py::test_open_accepts_an_entry_or_its_uri` |
| `list` builds entries from the **raw** `release.json` payload, never a validated `Release`, so a too-new `schema_version` is listed and not refused (§5.1) | 04, `store.py` | 07, `store.py` | a stored `release.json` with `schema_version = SCHEMA_VERSION + 1` | `test_store_file.py::test_list_does_not_refuse_a_newer_schema_version`, `::test_open_refuses_a_newer_schema_version` / `test_store_s3.py::test_schema_version_newer_than_this_install` |
| `mediacore[s3]` = `boto3`; `dev` = `+ boto3, moto[s3]` | 04, `pyproject.toml` | 01 and 06, `tests/conftest.py` / `tests/test_store_s3.py` (moto); 07, `store.py` (boto3); `plans/gate.sh` → `install` | — | `plans/gate.sh` section "install" / `test_store_s3.py::test_missing_boto3_names_the_extra`, plus the clean-install check in `11-verify-sonnet.md` |
| `mediacore` 0.2.0 in `pyproject.toml` **and** in `__init__.__version__`; `SCHEMA_VERSION` still 1 | 04, `pyproject.toml`, `src/mediacore/__init__.py` | the tag WP7b/7c/7d pin (§12) | — | `test_store.py::test_package_version_matches_distribution_metadata` |
| `seed_its_saxy_store(store_uri) -> BundleEntry`, idempotent | 09, `src/mediacore/fixtures.py` | 01, `tests/test_store_fixture.py`; `scripts/seed_bundle_store.py`; every WP7 dev stack | `fixtures/its-saxy/` | `test_store_fixture.py::test_seed_its_saxy_store_is_idempotent` — consumer side only; the producer is a `put` of a bundle asserted everywhere else |

## Deliberately excluded

- **Nothing outside `mediacore`.** The source side (`vinylcat export-release --store`)
  is WP7b and the consumer inboxes are WP7c/7d — separate features, separate arms,
  blocked on this one. F1 is the seam every other WP7 feature builds against.
- **No consumer-side inbox predicate.** §5.1's "entries whose `record_id` appears in no
  `refs` bag" is a *consumer* rule; `mediacore` has no database and never learns what
  was imported.
- **Nothing deletes.** Neither `mediacore` nor any consumer removes or overwrites an
  entry (§5.1, checklist D7).
- **No fourth method, and no store configuration.** §5.1 fixes the interface at `list`
  / `open` / `put`; there is no `delete`, no `exists`, no `stat`, no cache. Reading
  `BUNDLE_STORE_URI` is the consumers' job (§5.1 → "Unset means absent") and
  `bundle_store_uri` is vinylCatalogue's — `mediacore` is handed a URI and nothing else.
- **No credentials, endpoints or regions of `mediacore`'s own.** §5.1: the ambient
  boto3 credential chain, "`mediacore` takes no keys and the browser never sees the
  store." No signed URLs, no bucket creation, no server-side-encryption or storage-class
  options, no multipart tuning. A store that needs any of those is configured outside
  this package.
- **`open` re-downloads.** On `s3://` it materialises the entry into a temporary
  directory each call rather than caching. §5.1 asks for correctness at this seam, and a
  cache is state — the thing a shared bucket is explicitly not.
- **No `schema_version` migration.** An entry too new for this install is listed with
  its version and refused on open, which is what §5.1 asks for. Reading it is an upgrade,
  not a conversion.
- **Nothing writes into the checkout.** Seeding puts the fixture into a store the caller
  names; `fixtures/its-saxy/` stays the read-only input it already is.
- **No tag, no CHANGELOG.** The version moves to 0.2.0 in this batch; `v0.2.0` is cut by
  the owner after the PR merges (§12).
- **Not 7e.** "Imported where" on vinylCatalogue's record page is optional and depends
  on WP5/WP6.

Every assertion in plan 01 is satisfiable without doing any of the above.

## Machine-readable

```json
{
  "slug": "bundle-store-plans",
  "plans": ["01-acceptance-tests-sonnet", "02-tests-store-core-haiku", "03-tests-store-file-sonnet", "04-store-core-file-sonnet", "05-level-store-core-sonnet", "06-tests-store-s3-sonnet", "07-store-s3-sonnet", "08-level-store-s3-sonnet", "09-fixture-seeding-sonnet", "10-level-fixture-store-sonnet", "11-verify-sonnet", "12-review-opus"],
  "branches": ["bundleStorePlans"],
  "session_window": {"from": "2026-08-27T21:44:00Z", "to": "2026-08-27T23:00:00Z"},
  "exclude_sessions": [],
  "subagents": ["a6c2bbe4b2c558baa"]
}
```
