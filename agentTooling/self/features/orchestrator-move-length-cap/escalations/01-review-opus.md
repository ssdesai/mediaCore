Verdict: escalated

# Review — orchestrator-move-length-cap (round 1)

## What the batch was supposed to do

Close three fail-open gaps from `OWNER_BRIEF.md`:

1. Check the hook's length cap on the orchestrator's record move.
2. Make `orchestration-start.sh` require an explicit go-ahead token from `roots.py`.
3. Stop the conformance check flipping a `done` item to `partial` when nothing about that item changed.

It also had to file three backlog entries.

## Does it do it

**Parts 1 and 2: yes, cleanly.**

- **The cap.** `orchestrator_moves_own_record` now checks `ORCHESTRATOR_MAX_LINE_CHARS` before it reads the line (`hooks/allow-repo-commands.sh:5686`). The check in `orchestrator_command_allowed` stays (`:5810`), and no new literal was added. H29 covers both profiles, both forms, at the cap and one character past it.
- **The go-ahead token.** It is defined once, as `shared_rules.ROOTS_CLI_GO_AHEAD`. `roots.py` binds it by identity (S2), and the start reads it through `SHARED_RULES_NAMES`. Both checks in the start now require exit 0 **and** exactly that output. R14 and C7 test three stubs each (empty, `sys.exit(0)`, another printed line), and the real classifier's go-ahead is also tested.
- **Backlog.** All three entries are filed.

**Part 3: the diagnosis is good; the stability fix only lasts one round.** The NOTES diagnosis (owner item 6) is accurate and specific. The carry-forward does what the plan's contract describes, and V1/V2 test it. But that contract does not fully meet owner item 7, as explained below.

## Fixed in this pass

None.

## Escalated to the next round

1. **A carried `done` holds for only one round; a repeat flip in the next round is refused again.** (owner item 7)
   - **Where:** `conformance.py` `carry_forward` reads `previous_result` from the previous round's table only. `feature-close.sh` passes only the `review round N-1` report.
   - **How it fails:** an item is carried at round N's close because round N-1 said `done` and round N said `partial`. Round N's committed table still says `partial`. If round N's close is refused for another item, round N+1 runs a fresh conformance pass. If that pass says `partial` again (the same sampling noise NOTES diagnoses), the previous verdict is now `partial`. Nothing is carried, and the close is refused. Nothing touching the item changed.
   - **Why it matters:** this is exactly #385's pattern: several rounds in a row, each with its own reason to refuse. The owner's rule ("must not regress … unless the diff touching that item … changed") is met for one round only.
   - **What it should do:** the anchor should be the **latest round whose table marked the item `done`**. Either walk back through the `review round K` commits, or have the close record each item's effective (carried) verdict and evidence somewhere committed. The changed-paths check should then run from that round's tree.
   - **Missing test:** a V2 variant. Round 7 is `done` on `frob.txt`. Round 8 says `partial` and is refused on another item. Round 9 says `partial` again with `frob.txt` unchanged. Item 1 must still be carried at round 9's close.

2. **A dotted identifier in the evidence is taken as a file, which lets an item be carried after its real file changed.**
   - **Where:** `conformance.py` `EVIDENCE_PATH_RE` matches `shared_rules.ROOTS_CLI_GO_AHEAD` as the "file" `shared_rules.ROOTS`, and `roots.CLI_GO_AHEAD` as `roots.CLI`. These tokens satisfy the "evidence names at least one file" anchor. But `path_touched` can never match them against a changed path such as `hooks/shared_rules.py`.
   - **How it fails:** previous evidence that names code only by its attribute, which is common in this repo, carries the item even after that module changed. It should fail closed instead.
   - **What it should do:** keep as anchors only the tokens that are paths in the judged tree. For example, `feature-close.sh` could pass `git ls-files` at the judged head, or `check-close` could resolve each anchor against the changed and tracked paths. Any token that resolves to no tracked file should count as no anchor.
   - **Missing test:** a V1 row. The previous evidence is `` `shared_rules.ROOTS_CLI_GO_AHEAD` `` and `hooks/shared_rules.py` is among the changed paths. The downgrade must stand.

## Acceptance

| Item | Evidence | Result |
|---|---|---|
| 1 — Start the feature | the feature's `start` commit and manifest; session-start reports the feature started on `claude/orchestrator-move-length-cap` | done |
| 2 — Cap at the top of `orchestrator_moves_own_record`, keep the other check, no new literal | `hooks/allow-repo-commands.sh:5686` and `:5810` | done |
| 3 — Tests at the cap and cap+1 for both forms; second defect fixed with tests | `self/tests/hook-orchestrator-role.sh` H29; `orchestration-start.sh:233,256`; `self/tests/orchestration-records-in-repo.sh` R14; `self/tests/consumer-record-guard.sh` C7 | done |
| 4 — Backlog: edited `roots.py`, last fence only (plus the duplicate audit stem) | `self/BACKLOG.md` (three new entries at the end) | done |
| 5 — Gate, review, security audit, close | `self/gate-report.txt` is green; this review is escalated; the audit and close are still to come | partial |
| 6 — Diagnose the flip in NOTES | `self/features/orchestrator-move-length-cap/NOTES.md` → "Diagnosis: the conformance flip" | done |
| 7 — A `done` must not regress on unchanged evidence; stay fail-closed for new gaps | `conformance.py` `carry_forward`; `feature-close.sh` carry block. The carry holds for one round only (escalation 1), and attribute names count as file anchors (escalation 2) | partial |
| 8 — Fixtures: an unchanged item stays done; a changed item can be downgraded | `self/tests/brief-conformance.sh` V1a–h, V2a/V2b | done |
| 9 — Split proposal if the fix is too large | NOTES → "Ruling: no split" | done |
| Plan: the hook cap | H29, both profiles, both forms | done |
| Plan: the go-ahead token | `shared_rules.py` `ROOTS_CLI_GO_AHEAD`; `shared-rules.sh` S1/S2; R14; C7 | done |
| Plan: the conformance carry-forward as contracted | V1 (unit), V2 (the real close, rounds 7–10); K1/K2/D1 renumbered and green | done |
| Plan: docs | `LIFECYCLE.md` step 5 item 3 and the refusal list; `README.md` `conformance.py` row; `hooks/README.md` `shared_rules.py` entry; `analysis/README.md` `roots.py` CLI lines; `self/tests/README.md` | done |

## Deviations from the brief

- Owner item 7 asks that a downgrade stand when "the diff touching that item" changed. The batch checks only the files named in either round's evidence. A change to a file the evidence does not name, but which implements the item, does not stop the carry. The review's own acceptance table is the remaining guard (NOTES → "What it does not catch").
- Owner item 7 also names "the brief/rulings for it" as a reason a downgrade may stand. The changed-paths diff leaves out the feature directory, which holds `OWNER_BRIEF.md` and the `NOTES.md` rulings. The close already refuses any `OWNER_BRIEF.md` changed after the start, so only a ruling change is affected. The conformance pass never sees NOTES, so this cannot cause a wrongful carry.
- The owner's addition is renumbered 6–9 inside the committed `OWNER_BRIEF.md`, so each item keeps a unique id (NOTES ruling 3). That is the only change to the relayed text.
