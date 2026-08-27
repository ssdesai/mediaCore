# NOTES — `bundle-store-plans` (WP7a, `plans` arm)

Written by the architect as its last act. The standing replacement for its head; read
this before touching the batch.

Worktree `/Users/sahildesai/dev/mediaCore-bundleStorePlans`, branch `bundleStorePlans`,
off `main` @ `f47d670`. Brief: `INTEGRATION.md` §5.1 (with §5 for the bundle format it
generalises and §12's WP7a row for scope and the version bump). Nothing was read from
the `direct` arm's tree or from humanNetworkMap's experiment directory.

## Rulings — judgment, not spec

Every one of these is a gap §5.1 leaves; the review plan (12) lists the first six
explicitly so a human judges them on the merits.

1. **`record_id` / `exported_at` come from `provenance`, not `refs`.** §5.1 calls
   `record_id` "the `vinylcat:record` ULID", but no `release.json` carries that ref —
   §4 puts the ULID in `Provenance {kind: "vinylcat", id, exported_at}`, §6's adapter
   writes exactly that, §8 has the *consumers* file it under the `vinylcat:record` ref
   key, and the committed fixture's own `refs` bag holds only `discogs:release`. So the
   store reads the provenance entry whose `kind == "vinylcat"`. A release without one
   cannot be `put`.
2. **`slug` is derived from the release, not read from the directory name.** §5.1 says
   the entry's fields are read from its `release.json` and never parsed out of its key,
   and `put(release, files)` takes no slug argument — so `bundle_slug(release)` derives
   `<artist>--<title>--<catalogue number>`, each segment folded through `normalize_text`,
   lowercased, non-`[a-z0-9]` runs collapsed to `-`. That reproduces
   `the-duke-s-combo--it-s-saxy--saae-1012`, the slug §11 records for IT'S SAXY in
   vinylCatalogue, which is why the rule is pinned by a test on both sides. Safe because
   **nothing addresses an entry by slug** — `record_id` and `uri` do — so a divergence
   from vinylcat's own slugify is cosmetic.
3. **`open` accepts a `BundleEntry` or its `uri` string.** §5.1's consumer flow posts
   `{entry_uri}` to `preview-from-store`, so the caller holds an address, not an object.
   One argument type, not a fourth method; the "three methods and nothing else" rule
   survives.
4. **`StoreError` for the store, `BundleError` for the bundle.** Unusable URI, missing
   root, unaddressable entry, a `put` that would overwrite, a `release.json` that cannot
   become an entry → `StoreError`. Hash, size, and too-new `schema_version` →
   `BundleError`, raised by `read_bundle` and passed through, because §5.1 says `open`
   verifies *like* `read_bundle` and re-wrapping would make the two diverge.
5. **`put` creates its root; `list` on a missing root raises.** A store you write to may
   bootstrap itself; a configured store you read that is not there is a misconfiguration
   a consumer must see rather than an empty inbox.
6. **`list` parses raw JSON and never validates a `Release`.** Forced by §5.1's own
   carve-out: an entry whose `schema_version` is newer than this install must be
   *listed* with that version. `Release` is `extra="forbid"`, so validating would refuse
   precisely the entry the spec says to show. This is why the slug derivation has a
   raw-payload path as well as a `Release` path.
7. **A malformed entry in a listing is loud.** `list` skips anything that is not an
   entry at the layout's depth (stray files, empty record directories, a directory with
   no `release.json`), but a `release.json` at the right depth that will not parse, or
   that has no `vinylcat` provenance, raises `StoreError` naming its URI. §5.1 grants
   exactly one listing exception — the too-new `schema_version` — and an inbox that
   silently hides a broken export is worse than one that says so.
8. **On `s3://`, `release.json` is uploaded last.** The substitute for `write_bundle`'s
   atomic swap: `list` matches on `release.json`, so an interrupted `put` leaves orphan
   media objects that never appear as an entry, rather than a listable entry with
   missing media. `put` also stages through `write_bundle` into a temp directory so the
   `{sha256: Path}` validation and hashing have one implementation, and `open`
   downloads into a temp directory and calls `read_bundle` for the same reason.
9. **Two exports of one record in the same second collide.** `exported_at` is formatted
   to seconds (`%Y%m%dT%H%M%SZ`), so the second `put` hits the never-overwrite rule and
   raises. Correct-by-refusal rather than silently truncating to the same address; the
   review plan lists it as an invariant worth an assertion.

### The three the coordinator asked for, in one line each

- **`s3://` with no network and no credentials:** `moto[s3]>=5.0` (`mock_aws`), added to
  the `dev` extra alongside `boto3>=1.34`, with fake credentials set in the environment
  by the `s3_store_uri` fixture — it intercepts botocore below the HTTP layer, so the
  real client code, pagination and key semantics are exercised rather than a hand-rolled
  fake of my own that would only test my model of S3. `mediacore[s3]` stays `boto3` alone.
- **Seeding the fixture with no bash:** `seed_its_saxy_store(store_uri)` is a library
  function (idempotent, so a dev stack can restart) exercised by
  `tests/test_store_fixture.py` against `tmp_path` when the gate runs the suite, plus
  `scripts/seed_bundle_store.py` for a human — no committed bytes, no new gate section,
  and nothing written inside the checkout. Unlike the last batch's generated fixture, a
  store is runtime state, so routing it through the gate would have been wrong even if
  an executor could run one.
- **The level split:** 1 = the seam + `file://` (red only for the acceptance test and
  the not-yet-existing s3 tests), 2 = `s3://` (red only for the acceptance test), 3 =
  seeding (nothing red). Three levels because each has a distinct dependency — s3 reuses
  level 1's helpers, seeding needs a working `put` — and because level 3's gate is then
  the batch's real acceptance gate. Nothing is deferred at any level: this batch adds no
  gate section, and `fixture idempotent` is load-bearing from level 1 as the check that
  catches a store written into `fixtures/`.

## Deviations from the design doc

None from §5.1's stated behaviour. Two additions it does not mention, both minimal and
both flagged to review: the `entry | uri` argument to `open` (ruling 3) and
`bundle_slug` as a public function (ruling 2, needed because `put` has no slug
argument).

## Open questions for the human

Relayed in the final report; recorded here so they survive it.

1. **Is `slug` meant to be derived, or is it vinylCatalogue's slug travelling in the
   bundle?** If the latter, `release.json` has nowhere to carry it today and §3 would
   need a field — which would be a `schema_version` change, and §12 says WP7a does not
   make one. Ruling 2 is the only reading that fits the version constraint, but a
   `Provenance.label`-style carrier is the alternative if the owner prefers it.
2. **Should `mediacore` refuse a release with no `vinylcat` provenance, or grow a
   generic "record identity" notion?** Today the store is keyed on a vinylcat-shaped
   fact. §2's "nothing vinyl-specific in `src/`" tolerates it — `"vinylcat"` is a
   provenance *kind* §4 names, as `"vinyl"` is a value of `Medium` — but a second source
   repo would need this generalised.
3. **`exported_at` precision.** Seconds, so two exports of one record in the same second
   collide (ruling 9). Fine for a human-driven export gate; say so if it is not.

## Cold-start commands

```bash
cd /Users/sahildesai/dev/mediaCore-bundleStorePlans

# what is queued / where the batch got to
ls plans/features/bundle-store-plans/{auto,verify,review}/*/

# run it (coordinator only — the architect never does)
./agentTooling/run-batch.sh bundle-store-plans

# per-level gate results, written by each sentinel
cat plans/gate-report.05.txt plans/gate-report.08.txt plans/gate-report.10.txt
cat plans/gate-report.txt          # the final one

# a red level's own log
cat plans/features/bundle-store-plans/auto/*/NN-*.progress.md
```

The gate was rehearsed green in this worktree before authoring: install, lint, fixture
idempotent, wheel contains fixture, tests — 5/5. Its section labels, which the
sentinels' `defer:` lines would have to match exactly, are `install`, `lint`,
`fixture idempotent`, `wheel contains fixture`, `tests`. Expected-red globs are
repo-relative (`tests/test_store_s3.py`), which is the form `--ignore-glob` matches.

## Manifest hygiene

`session_window.to` is still `null`. Set it as soon as this feature stops being planned
— `bundleStorePlans` is a fresh branch, so nothing else competes for its sessions today,
but an open window is what double-counted two features in a sibling repo. The architect
was spawned from a coordinator on another repo's `main`, so its transcript carries that
branch and must be pinned by agent id in `subagents` (`capture_planning.py
--list-subagents --unclaimed`) — `branches` alone will not find it.
