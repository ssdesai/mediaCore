# Review: the bundle store

Feature `bundle-store-direct` (the review pass; this arm authored no plans — one delegate implemented §5.1 directly). WP7a of `INTEGRATION.md` §12: the
URI-addressed bundle store designed in §5.1 — `open_store(uri) -> BundleStore` with
`list` / `open` / `put` over `file://` and `s3://`, the `BundleEntry` shape, the
versioned layout, and fixture seeding. `mediacore` 0.2.0, `schema_version` unchanged.
Nothing else: no source side, no consumer inbox, no endpoint.

Branch `bundleStoreDirect`, base `main` @ `f47d670`. The work is committed: the feature is the single commit `7946154` off `main` (the two
later commits labelled EXPERIMENT BOOKKEEPING are cost manifests, not the feature — leave
them alone). Assemble the diff from `git diff main...7946154`, and read the current files
directly. Do not commit anything yourself.

The delegate ran the gate green itself. Do not re-run tests, build wheels or seed a
store. Read the code.

If `plans/features/bundle-store-direct/escalations/` holds anything, read it first: it
records a contract the batch changed after authoring.

## Hold it to

- **§5.1, bullet by bullet.** The interface (three methods and nothing else), the
  `BundleEntry` fields, the layout and versioning, "nothing overwrites or deletes",
  `open` verifying like `read_bundle` while `list` does not refuse a too-new
  `schema_version`, `s3://` over the ambient credential chain with the extra
  `mediacore[s3]`, and the fixture bullet.
- **The rulings this delegate had to make, because §5.1 does not settle them.** Judge each
  one on the merits — they are logged in `INTEGRATION.md` §13 (decisions) and §14 (open
  questions) and summarised in the PR body, and a consumer repo will inherit whichever way
  they went: where `record_id` and `exported_at` are read from; how `slug` is obtained;
  what `open` accepts and whether it does more than return a `Release`; `StoreError` vs
  `BundleError` and which side a malformed `release.json` in a listing falls on; what
  `put` does when the version already exists; what `list` does on a missing root; and how
  the `s3://` upload substitutes for `write_bundle`'s atomic swap.
- **The security boundary is unchanged.** Bundles reach both consumers as untrusted
  uploads, and a store adds a second untrusted path: a `release.json` in a store may
  have been hand-edited. Nothing in this batch may weaken `MediaFile`/`AudioFile`'s
  `file == media/<sha256>.<ext>` validation or `read_bundle`'s containment check —
  confirm `open` still goes through `read_bundle` on both backends rather than
  re-implementing any part of it, and that the raw-payload parse `list` uses cannot be
  induced to read or write outside the entry.
- **CONVENTIONS.md.** README Rule 1's field list for `BundleEntry`; Rule 2 for the
  contracts no import reveals (the `vinylcat` provenance entry, the ambient credential
  chain, the `mediacore[s3]` extra); named constants instead of inline literals.
- **Nothing vinyl-specific leaked into `src/`** beyond what §4 already blesses:
  `"vinylcat"` is a provenance *kind* the contract names, the way `"vinyl"` is a value
  of `Medium`. Judge whether the way it enters `store.py` keeps that line.

## The invariants most likely to have no test

This is the highest-value output: name the assertion, and where it belongs. Candidates
worth checking, not a checklist to confirm:

- that two `put`s a second apart for one record produce two entries rather than
  colliding, and that sub-second precision in `exported_at` cannot make two exports
  collide silently;
- that a `list` over a store containing an entry from a *newer* `mediacore` still
  returns every older entry alongside it;
- that `open` on one backend and `open` on the other raise the same exception type for
  the same fault;
- that nothing in `mediacore` can be made to write outside the entry it is putting.

## Verdict

Write `plans/review-report.md`. It becomes the PR body verbatim, so write it for the
human approving the PR: what the batch was supposed to do, whether it does it, then two
lists — *fixed in this pass* and *escalated to the next batch* — and a one-line note on
anything WP7b, 7c or 7d must know before pinning `v0.2.0`.

**"No findings" is a legitimate verdict.** Do not manufacture findings to fill the
lists; a speculative one costs the next batch turns to disprove.
