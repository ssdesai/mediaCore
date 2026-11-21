Verdict: clean

# Review round 3: orchestrator-move-length-cap

## What this round was supposed to do

The owner ruled on 2026-11-21 (`NOTES.md` → "Owner's ruling: split") to narrow this round to
defects 1 and 2 and the backlog entries. Defect 3, the conformance flip, was split out into
`self/BACKLOG.md`.

1. **Record-move line cap.** `orchestrator_moves_own_record` now refuses a line past
   `ORCHESTRATOR_MAX_LINE_CHARS` before reading it. `main()` asks this check before
   `orchestrator_command_allowed`, so the cap now applies first.
2. **`roots.py` go-ahead token.** `roots.py start-refusal` and `roots.py self-write` now print
   `shared_rules.ROOTS_CLI_GO_AHEAD` (`ok`) when the start may go ahead.
   `orchestration-start.sh` goes ahead only on exit 0 with exactly that output. Anything else
   refuses.

## Does it do it

Yes. I checked each contract against `git diff origin/main...HEAD`:

- **The cap.**
  - The check is at `hooks/allow-repo-commands.sh:5686`, the first statement of
    `orchestrator_moves_own_record`.
  - The check in `orchestrator_command_allowed` is kept (`:5810`).
  - Both use the same `>` comparison on the same constant. No new literal is added.
- **The token.**
  - It is defined once, in `hooks/shared_rules.py`.
  - `roots.py` binds it as `CLI_GO_AHEAD`. `self/tests/shared-rules.sh` S2 checks this by
    identity, and S1 checks the value.
  - `orchestration-start.sh` reads it through `SHARED_RULES_NAMES`, so no file restates `ok`.
  - Both call sites check the exit code first, then require the output to equal the token
    exactly (`orchestration-start.sh:233-234` and `:256-257`). `$(…)` strips the trailing
    newline and stderr goes to `/dev/null`, so a warning on stderr cannot break the match.
- **Tests.** The gate report at `self/gate-report.txt` shows these rows passing:
  - H29, all 8 rows: the move and the `mkdir -p` remedy, at the cap and at cap+1, under both
    profiles. The cap+1 rows are the allowlist denial.
  - R14 and C7: the real classifier's go-ahead, plus an empty stub, a `sys.exit(0)` stub and a
    stub printing another line. Each stub refuses with exit 1 and writes nothing.
  - The gate ran after the split commit. The only later commit (`66665e7`) changes the
    feature's own records only.
- **Nothing of defect 3 remains.** The diff makes no change to `conformance.py`,
  `feature-close.sh`, `self/tests/brief-conformance.sh`, `LIFECYCLE.md` or `README.md`.
- **Docs.** These entries describe the change:
  - `hooks/README.md`: the `shared_rules.py` entry;
  - `analysis/README.md`: the `roots.py` CLI lines;
  - `self/tests/README.md`: H29, R14, C7 and S1.
- **Backlog.** `self/BACKLOG.md` has all four entries:
  - an edited `roots.py` defeats the classifier;
  - only a record's last fence is counted;
  - `run-review.sh` adds the audit stem to `plans` twice;
  - the split-out conformance flip, with its diagnosis and design.

## Fixed in this pass

- `self/features/orchestrator-move-length-cap/NOTES.md`, "Ruling: owner items the conformance
  check cannot see":
  - **Problem:** it still said item 6 is met in `LIFECYCLE.md` step 5. The split restored
    `LIFECYCLE.md` to the branch base, so that was false.
  - **Fix:** it now says the diagnosis is met there only through the backlog entry.
- `NOTES.md`, "Ruling: no split (owner item 9)":
  - **Problem:** the section still stood as a live ruling, contradicting the owner's split
    ruling above it.
  - **Fix:** it is now marked superseded, with a pointer to that ruling.

## Escalated to the next round

None.

## Acceptance

| Item | Evidence | Result |
|---|---|---|
| 1 — Start the feature | Not reviewable as code; judged by hand at the close (owner's split ruling). Start commit `aceb350` is on the branch | done |
| 2 — Cap checked at the top of `orchestrator_moves_own_record`; `orchestrator_command_allowed`'s check kept; no new literal | `hooks/allow-repo-commands.sh:5686`, `:5810` | done |
| 3 — Tests at the cap and at cap+1, for the move and the `mkdir -p` lead; second defect fixed, with tests | `self/tests/hook-orchestrator-role.sh` H29; `orchestration-start.sh:233-234`, `:256-257`; `self/tests/orchestration-records-in-repo.sh` R14; `self/tests/consumer-record-guard.sh` C7; `self/tests/shared-rules.sh` S1/S2 | done |
| 4 — The audit's two non-blocking findings in `self/BACKLOG.md` (plus the `run-review.sh` duplicate stem from the brief) | `self/BACKLOG.md`, the last four entries | done |
| 5 — Gate, review and security audit, then close | Not reviewable as code; judged by hand at the close (owner's split ruling). The gate is green (`self/gate-report.txt`) | done |
| 6 — Diagnose the conformance flip in NOTES | `NOTES.md` → "Diagnosis: the conformance flip (owner item 6)"; `self/BACKLOG.md`, the conformance entry | done |
| 7 — Make the conformance verdict stable | Split out by the owner's ruling of 2026-11-21 (item 9 invoked). The design is filed in `self/BACKLOG.md` | done |
| 8 — Carry-forward fixtures | Split out together with item 7; the assertions are filed in the same backlog entry | done |
| 9 — Report a split proposal if the fix is too large | `NOTES.md` → "Owner's ruling: split"; the code is removed from the diff | done |
| Plan: cap contract | `hooks/allow-repo-commands.sh:5686` | done |
| Plan: H29, both profiles | `self/tests/hook-orchestrator-role.sh` H29; gate rows pass | done |
| Plan: token defined once, bound by identity, read via `SHARED_RULES_NAMES` | `hooks/shared_rules.py`; `analysis/roots.py` `CLI_GO_AHEAD`; `self/tests/shared-rules.sh` S2; `orchestration-start.sh` `SHARED_RULES_NAMES` | done |
| Plan: fail-closed tests R14 and C7 | Gate rows R14 ×4 and C7 ×4 pass | done |
| Plan: nothing of defect 3 remains | `git diff origin/main...HEAD --stat` touches none of the five files | done |
| Plan: docs | `hooks/README.md`, `analysis/README.md`, `self/tests/README.md` | done |

## Deviations from the brief

- Owner items 7 and 8 (the stable conformance verdict and its fixtures) are not built in this
  feature. The owner ruled on 2026-11-21 to split them out under item 9. The diagnosis and
  design are in `self/BACKLOG.md`.
- Owner items 1 and 5 are process steps the conformance check cannot see. The owner ruled that
  they are judged by hand at the close.
