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

- **humanNetworkMap still pins `mediacore` `v0.3.0`, so it refuses schema-3 bundles.**
  Its dependency pin (`pyproject.toml` / requirements) names `v0.3.0`; a bundle written by
  0.4.0 is refused by `read_bundle` with the "upgrade mediacore" message, which is the
  designed behaviour (§12) until it re-pins. Excluded by the `release-original-year` README:
  re-pins are separate features after `v0.4.0` is tagged. musicMap (its PR #43) and
  vinylCatalogue (its PR #158) re-pinned on 2026-09-25; vinylCatalogue's export now fills
  `Release.original_year`. Closed when humanNetworkMap's suite reads the 0.4.0
  `its_saxy_bundle()` (`schema_version` 3) without error and it decides what, if anything,
  to do with `original_year`.
  Raised by: release-original-year (2026-09-24); narrowed 2026-09-25.
