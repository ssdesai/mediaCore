# humanNetworkMap claim fixes before the owner's audit — child briefs

The owner's brief of 2026-11-18 ("claim-run fixes before the owner's own audit"), features 1
and 2, as sent to the children on 2026-11-19. Feature 3 (`claim-verify-parallel`) is held
for a free slot; its brief is the owner's section 3 in the same shape.

Shared allocation: humanNetworkMap main 3c14b9d4, migration 0070, no migration expected.

| Feature | Session | Test-spec ids |
|---|---|---|
| claim-duplicate-subset-drop | see README fence | S2.105–108, S3.155–159, C3.158–161 |
| claim-owner-options-restore | see README fence | S2.109–112, S3.160–164, C3.162–165 |
| claim-verify-parallel (held) | — | S2.113–116, S3.165–169, C3.166–169 |

Orchestrator rulings carried in the briefs:
- Span cap: when the union of spans would exceed `CLAIM_SPANS_MAX`, the kept candidate's own
  spans come first; the removed row keeps its own spans and `duplicate_of`, so nothing is lost.
- `claim-owner-uncertain-noise` (#370) NOTES ruling 7 stands (owner, 2026-11-18).
- Conformance by hand until `brief-conformance-checks` lands: the owner's section is saved
  verbatim as `OWNER_BRIEF.md` in the feature directory, quoted in the review brief as the
  yardstick, and the review report and PR body carry an acceptance table and a "Deviations
  from the brief" section.
