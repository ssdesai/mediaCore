# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased
as the assertion that would catch it, with the feature that raised it. An entry is
removed by the feature that closes it, not when it is merely noticed again.

Anything a feature deliberately leaves unbuilt belongs here: an exclusion that is real
work, a review escalation not taken, a defect found and not fixed. A line in a feature's
`NOTES.md` is not a record — it is filed under one feature and nobody reads it once that
feature has closed.

Write each entry as one bulleted item: a bold sentence saying what is wrong or missing,
in the present tense; a short paragraph naming the file and the function, what happens
today, and why it was left; the assertion that fails today and would pass once it is
closed; and the feature that raised it, on its own last line.

Seeded once by `../agentTooling/sync-plans.sh` and never overwritten afterwards, the
same treatment `PROJECT_FACTS.md` gets. Empty until a feature leaves something behind,
which is the correct state for a repo that has closed everything it found.

## Entries

- **vinylCatalogue's export does not fill `Release.original_year`.** The adapter
  (`INTEGRATION.md` §6; vinylCatalogue `src/vinylcat/`, its `Record → Release` export
  path) still pins `mediacore` 0.3.0 and has no field to write, so a record whose
  `issue.kind` is `"reissue"` leaves the system without its `issue.original_year`.
  Excluded here because the adapter is vinylCatalogue's code and needs the `v0.4.0` tag
  this feature does not cut. Closed when exporting a signed-off record with
  `issue = {kind: "reissue", original_year: 1969}` yields a `release.json` with
  `"original_year": 1969` and `"schema_version": 3`, and one with `kind: "original"` or
  no `issue` yields `"original_year": null`.
  Raised by: release-original-year (2026-09-24).
- **humanNetworkMap, musicMap and vinylCatalogue still pin `mediacore` `v0.3.0`, so
  they refuse schema-3 bundles.** Each consumer's dependency pin (`pyproject.toml` /
  requirements) names `v0.3.0`; a bundle written by 0.4.0 is refused by `read_bundle`
  with the "upgrade mediacore" message, which is the designed behaviour (§12) until they
  re-pin. Excluded by the feature README: re-pins are separate features after `v0.4.0`
  is tagged. Closed in each repo when its suite reads the 0.4.0 `its_saxy_bundle()`
  (`schema_version` 3) without error, and — where the consumer shows release metadata —
  when it decides what, if anything, to do with `original_year`.
  Raised by: release-original-year (2026-09-24).
