Verdict: escalated

# Review: brief-conformance-checks, round 1

## What the batch was supposed to do

Add four checks so that a review can no longer come back clean while the PR does something other than what the owner asked:

1. The owner's request (`OWNER_BRIEF.md`) is the yardstick for the review.
2. The review report carries an acceptance table, and the close enforces it.
3. An independent conformance check runs with no tools and is shown only the brief and the diff.
4. A fixed "Deviations from the brief" section exists, and `pr.sh` marks the PR when the section is not empty.
5. A rollout that falls back to today's behaviour when a feature has no owner brief.

## Does it do it

Mostly yes, and the mechanics are solid:

- **`feature-start.sh --owner-brief`:** refuses bad input before writing anything.
- **Conformance plan isolation:**
  - The launch hook leaves every other plan's argv unchanged.
  - The conformance prompt is built from git, never from the plan body.
  - The executor runs with `--tools ""`, and its prompt arrives on stdin.
- **Round mechanics:** the conformance plan skips `completed_review_count`, `latest_review_plan` and `queue_security_audit`. The review stays last and keeps the held `plan_end`.
- **The close:** reads all of its evidence from git at the judged head and refuses before writing anything. It also refuses in these cases:
  - the owner brief was edited or removed after the start;
  - the conformance report was not written by the round's own commit.
- **`pr.sh` 8:** older callers still get the old contract.
- **`forge.sh pr-edit`:** without a title, it behaves as before.
- **Bookkeeping:** `AUDIT_TOOLING_PATHS`, `TEMPLATE_VERSIONS` and the READMEs are all updated.
- **Tests:** `self/tests/brief-conformance.sh` runs the real scripts with a stubbed `claude` and a stubbed forge. The gate is green.

Two gaps stay green under every check, and both are escalated below:

- **The owner's item format collapses to one item.** `conformance.py items` treats only numbered *headings* (`### 1. …`) as items. The owner writes items as a top-level numbered list (`1. **…**`), which is how this feature's own ruling is written. `ORCHESTRATION.md` requires that text to be copied verbatim. A real owner brief would therefore parse as a single item, "1 — the owner's request", and two things weaken:
  - The independent check gives one verdict for the whole request.
  - The close's "agrees with the review's table" test compares one row instead of one per item.
  
  Nothing tells the orchestrator or the owner to use headings: only `LIFECYCLE.md:434` mentions it, and `ORCHESTRATION.md` and `ORCHESTRATOR_BRIEF.md` say nothing.
- **Item 2 still applies when there is no owner brief.** Without an owner brief:
  - The review prompt still asks for the `## Acceptance` table, worded as "one row for each item of the owner's request listed above", even though no request is listed. Test N1c asserts this.
  - `pr.sh` 8 still moves that table to the top of the PR body.
  - `pr.sh` 8 also rewrites the PR title on every re-close.
  
  Item 5 says items 1–3 fall back to today's behaviour. The review brief's contract says a feature with no owner brief reviews and opens its PR "exactly as on main, plus one notice line each".

## Fixed in this pass

Nothing. Both findings are design changes. Also, `run-review.sh` is the script running this pass: editing it while it runs would corrupt the parent shell, which reads the file as it goes.

## Escalated to the next round

1. **Numbered-list owner items** (`conformance.py:47`, `ITEM_HEADING_RE`, and `parse_items`).
   - **Change:** treat top-level numbered list items (`^\d+[.)]\s+`, column 0, outside fences) as items too, removing `**` from the titles. Decide what wins when a brief has both numbered headings and numbered lists, for example headings first and lists only when there are no headings, and write that down in `LIFECYCLE.md`, `ORCHESTRATION.md` and `templates/plans/ORCHESTRATOR_BRIEF.md`.
   - **Assertion (U1):** `conformance.py items` on a brief shaped like this feature's ruling (`1. **The owner's request is the review's yardstick.** …` through `5. **Rollout.** …`, with nested indented lists) prints ids 1–5 with their bold titles.
   - **Assertion (C1):** with such a brief, the conformance prompt lists five items.
2. **No owner brief should mean no acceptance section** (`run-review.sh`, `report_sections_text` and `build_prompt`).
   - **Change:** with no `OWNER_BRIEF.md`, ask only for `## Deviations from the brief` (item 4 applies to every report, per NOTES R15). Ask for `## Acceptance`, and the "owner's request listed above" wording, only when the brief exists.
   - **Assertion:** N1c is flipped to `! grep -qF "## Acceptance" "$REVIEW_PROMPT_OUT"`.
   - **Owner's call:** whether `pr.sh` 8 should leave a PR from a no-brief feature completely unchanged, as the review brief's "exactly as on main" contract says, or whether item 4's mark applies there too, as R15 reads it. This includes the title being rewritten on re-close and a report with no deviations section getting `[deviations]`.
3. **Duplicate `plans[]` entry on a resumed review** (`run-review.sh`, in `queue_conformance_check`, `plans+=("$stem")`).
   - **The problem:** the append does not check whether the stem is already there. Here is how it happens:
     1. The conformance plan finishes and moves to `complete/`.
     2. The review is interrupted.
     3. The operator follows the refusal's advice and moves the review back to `incomplete/`.
     4. The next pass queues the same stem again and appends it to `plans[]` a second time, because `manifest.py set-plans` does not remove duplicates.
   - **Change:** append the stem only when it is missing.
   - **Assertion:** after a second `queue_conformance_check` for the same NN, `plans[]` holds the stem once.

## Acceptance

| Item | Evidence | Result |
|---|---|---|
| 1 — owner's request is the review's yardstick | `self/tests/brief-conformance.sh` S1a–S1e, C1k; `run-review.sh` `owner_brief_block`; ORCHESTRATION.md "Rules", ORCHESTRATOR_BRIEF.md "Owner's request (verbatim)" | done |
| 2 — acceptance table | K1a, K1d, K2a–K2c; `conformance.py` `cmd_check_close`; but a numbered-list owner brief gives one item instead of one row per item (`conformance.py:47`) | partial |
| 3 — independent conformance check | C1b–C1j, K1c, K1e, D1/K2d; isolation per `executor_args_for_plan`; per-item agreement weakened by the same item parsing (`conformance.py:47`) | partial |
| 4 — deviations section and PR mark | K2d, K2e, D1a; ORCHESTRATION.md "never merges … without the owner's word" | done |
| 5 — rollout | N1a–N1e, LIFECYCLE.md "Rollout", self/BACKLOG.md entry; but item 2 still applies without a brief (N1c asserts the acceptance section is asked for) | partial |
| Contract: no owner brief, no change | N1b–N1e; review prompt and PR title and body still differ from main without a brief (`run-review.sh` `report_sections_text`, `self/pr.sh` title_args) | partial |
| Contract: isolation of item 3 is mechanical | C1d–C1g; `plan-runner-lib.sh` run_plan hook, `--tools ""`, stdin prompt | done |
| Contract: round mechanics intact | C1c, C1j; `plan-runner-roots.sh:153,161`; `run-review.sh` queue_security_audit skip | done |
| Contract: close reads evidence from git at the judged head | K1a–K1g (nothing written on refusal, report not by round commit refused) | done |
| Contract: templates | `templates/plans/TEMPLATE_VERSIONS` pr.sh 8; sync-check.sh, feature-lifecycle.sh P2e; `forge.sh` pr-edit optional title | done |
| Contract: audit paths | `plan-runner-roots.sh:172`; LIFECYCLE.md audit-path list | done |
| Contract: READMEs, test listed and gated | gate "readme index", "brief conformance self-test"; self/tests/README.md | done |
| Contract: each item has its assertion on real scripts | `self/tests/brief-conformance.sh` S1/P1/C1/K1/K2/D1/N1/U1 with stub claude and stub gh | done |

## Deviations from the brief

- Item 2 still applies without an owner brief: the review prompt asks for `## Acceptance`, and `pr.sh` 8 moves it to the top of the body. Item 5 says items 1–3 fall back to today's behaviour.
- Item 4 (the `[deviations]` title mark, and the title rewritten on re-close) applies to features without an owner brief too (NOTES R15). This fits item 4, which is not one of the items that fall back, but it conflicts with the review brief's "exactly as on main" contract. The owner should confirm it.
- The owner's items are recognized only as numbered headings, not as the numbered list the owner actually writes in. This narrows items 2 and 3.
- The conformance executor still loads the repo's `CLAUDE.md` and runs its SessionStart hook, because it runs in the repo with project settings. This is a documented residue (NOTES R8, LIFECYCLE.md item 3). It is not the implementer's notes, but it is more than "only the owner's brief and the diff".
