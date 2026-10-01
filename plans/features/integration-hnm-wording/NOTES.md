# Notes: integration-hnm-wording

Built by hand. Sources read: humanNetworkMap `plans/BACKLOG.md` (the four entries and their
assertions) and the `NOTES.md` of `import-default-link`, `import-audio-credit-items` and
`import-into-existing-source`; musicMap `backend/app/services/README.md` for its default
rule.

- **`hnm:edge-key` is described as "not unique across releases on its own"**, which is
  why the stamp also carries the release refs and `vinylcat:record` (hNM
  `import-into-existing-source` NOTES, "Tier 1 needs the release's `vinylcat:record`").
  The key is grammar-valid under §4, so no §4 change is needed.
- **"`vinylcat:record` when the bundle has one"**: a bundle without vinylcat provenance
  stamps edges with authority refs + `hnm:edge-key` only.
- **The credit-sentence rule is stated as "edge only; node only when the edge is not
  created"** (hNM rule B), including a credit that collapsed into the release artist.
  The "a present edge counts as carrying it on re-import" detail is left in hNM; §8 does
  not need it to be true.
- **§9 is unchanged.** The backlog entry names "§8/§9", but §9 never mentions hNM or
  audio for hNM; the stale text was §8's media bullet covering `MediaFile` only.
- **§8's links bullet was already correct** for first imports (amended 2026-08-27);
  it gains the re-import move and the "refs overlap an entity's" wording from the
  backlog assertion.
