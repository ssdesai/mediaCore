# 01 — review: integration-hnm-wording

feature: mediaCore/integration-hnm-wording

## What the feature was supposed to do

A by-hand, documentation-only change to `INTEGRATION.md` §7, §8 and §13, closing the
wording half of four humanNetworkMap backlog entries. Each entry's assertion is the spec:

1. (`import-default-link`) §7's candidate paragraph says a candidate (by ref or by equal
   normalized name) is proposed as the default link, which the human confirms or changes
   before the commit, and no longer that only a shared authority ref proposes one.
2. (`import-audio-credit-items`) §8 lists audio among what the release becomes in hNM,
   and its information-items bullet says a credit sentence sits on the edge, not also on
   the node.
3. (`import-into-existing-source`) §7 "Re-import" names linking an existing source and
   the `hnm:edge-key` edge stamp.
4. (`import-links-on-entities`) §8's links bullet says a link whose refs overlap an
   entity's is attached to that entity's node, only entity-less links to the source, and
   that a re-import moves a source-only link onto its nodes.

Read the entries themselves with
`gh api repos/ssdesai/humanNetworkMap/contents/plans/BACKLOG.md --jq .content`
(base64-decode the output) — search for `INTEGRATION.md`.

## The diff

Base is `main`. `git diff main...HEAD --stat` must show only `INTEGRATION.md` and files
under `plans/features/integration-hnm-wording/`. Then the full diff of `INTEGRATION.md`.

## Contracts to hold it to

1. **Each of the four assertions above holds** against the new text.
2. **musicMap is not misdescribed.** §7 is "both consumers"; musicMap still defaults a
   name-only match to *create* and a ref match to *link* (musicMap
   `backend/app/services/README.md`, `_default_link_or_create`; fetch with
   `gh api repos/ssdesai/musicMap/contents/backend/app/services/README.md --jq .content`).
   The text must not attribute hNM's rule to musicMap.
3. **No contract change is implied.** Nothing in §3–§5 changes, no version or
   `schema_version` is mentioned as bumped, and `hnm:edge-key` satisfies §4's ref-key
   grammar.
4. **The §13 entry is accurate** and matches the feature manifest's Decisions.
5. **Nothing else changed**: no code, no other README. `gate.sh` is green.

"No findings" is a legitimate verdict. Fix local defects in place; escalate only what needs a
design decision.

## Verdict

Write `plans/review-report.md` with first line `Verdict: clean` or `Verdict: escalated`, then
the findings.
