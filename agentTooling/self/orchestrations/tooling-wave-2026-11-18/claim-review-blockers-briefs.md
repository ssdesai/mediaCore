# humanNetworkMap: claim review blockers and claim topics — child briefs

From the owner's first full review of a claim run by hand (2026-11-19), in two briefs:
"two review blockers" (an addendum to `claim-run-fourth-pass-brief.md`, which is in neither
repository) and "claim topics". Three features, dispatched 2026-11-19. Each feature commits the
owner's section verbatim as `plans/features/<slug>/OWNER_BRIEF.md`, the yardstick for its
review. That file is the record of the owner's words here.

Shared allocation: humanNetworkMap main 43cf959f, latest migration 0070.

| Feature | Test-spec ids | Migration |
|---|---|---|
| claim-new-entity-once | S1.48–51, S2.117–124, S3.170–177, C3.158–165, C4.107–110 | 0071 if needed |
| claim-review-pair-decision | S1.52–53, S2.125–128, S3.178–181, C3.166–171, C4.111–114 | none expected; 0073 if needed |
| claim-topics | S1.54–59, S2.129–138, S3.182–193, C3.172–181, C4.115–120 | 0072 |

Merge order: `claim-new-entity-once` (the owner's most urgent), then
`claim-review-pair-decision`, then `claim-topics`. Each later one merges `origin/main`
normally, renumbers its migration onto the chain it finds, and re-gates. All three touch the
ClaimReview screen; conflicts there are expected and resolved keeping both features.

Update 2026-11-19 16:30 UTC (owner): `claim-new-entity-once` is on hold, stopped at a clean
point, not merged. Merge order is `claim-review-pair-decision` then `claim-topics`; the
migration table above is superseded: pair-decision takes 0071 if it needs one, claim-topics
renumbers after it. claim-topics keeps its extraction-output field one small separable block.

Update 2026-11-19 16:42 UTC (owner's design brief "match names to nodes after extraction, not
in the prompt", committed verbatim as the feature's `OWNER_BRIEF.md`): it replaces both held
features. Feature 1, `claim-extract-names-only` (a run option, off by default, plus the design
record `plans/claim-entity-linking/DESIGN.md` with D2–D11 accepted or argued in writing),
dispatched; ids S1.60–63, S2.139–144, S3.194–199, C3.182–185, C4.121–123; migration after the
siblings'. It merges after `claim-topics`. Features 2–6 (`claim-run-entities`,
`claim-entity-search`, `claim-entity-decide`, `claim-review-entities`, `claim-entity-metrics`)
wait for the owner's measurement.

Orchestrator rulings carried in the briefs:
- `claim-new-entity-once`: the owner's open question (what a commit does with an accepted new
  edge whose end is still a bare name) is answered in NOTES and the PR from the code at base, and
  after this feature the case is either impossible or refused with a reason, never silent.
- `claim-review-pair-decision`: groups are whatever `claim-duplicate-subset-drop` (#377, merged)
  leaves as `duplicate_pair`; merge cites the union of passages within `CLAIM_SPANS_MAX`.
- `claim-topics`: the open question (whether an accepted claim's information item keeps its
  topic) is raised in the report, not decided; "re-sort" is built only if small, else filed in
  `plans/BACKLOG.md` and named as a deviation.
- Conformance by hand (humanNetworkMap has not yet pulled #167): `OWNER_BRIEF.md`, an
  acceptance table and a "Deviations from the brief" section. Every humanNetworkMap merge waits
  for the owner until the propagation pull lands.
