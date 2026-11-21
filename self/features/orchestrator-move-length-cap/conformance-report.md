## Conformance

| Item | Evidence | Result |
|---|---|---|
| 1 | No evidence in the diff; the start would be recorded only in the excluded feature directory | not done |
| 2 | hooks/allow-repo-commands.sh:5686-5687 (`if len(command) > ORCHESTRATOR_MAX_LINE_CHARS: return False` at the top of `orchestrator_moves_own_record`; the check in `orchestrator_command_allowed` is untouched) | done |
| 3 | self/tests/hook-orchestrator-role.sh H29 (move and `mkdir -p` remedy at exactly the cap, then cap+1); second defect: orchestration-start.sh:233-234, 256-257, analysis/roots.py:480,487, self/tests/orchestration-records-in-repo.sh R14, self/tests/consumer-record-guard.sh C7 (empty, exit-0 and other-output stubs); run-review.sh duplicate-stem entry at self/BACKLOG.md:895 | done |
| 4 | self/BACKLOG.md:874 (edited `analysis/roots.py` defeats the classifier), self/BACKLOG.md:887 (only the last fence counted) | done |
| 5 | No gate, review or close evidence in the diff | not done |
| 6 | self/BACKLOG.md:903-920 has a "Why it happens" diagnosis: a fresh model run, inputs limited to brief, items and diff, no owner rulings or earlier verdicts, unreasoned downgrades. NOTES, where the item asked for it, is in the excluded feature directory, so it is not visible | partial |
| 7 | No mechanism in the diff; self/BACKLOG.md:922-934 only proposes one (`check-close --tracked/--round` carry-forward) | not done |
| 8 | No fixture or test for the conformance carry-forward in the diff; only proposed assertions at self/BACKLOG.md:936-941 | not done |
| 9 | self/BACKLOG.md:922 ("Proposal … split out by the owner") is a split proposal, and the diff contains no build of it | done |

## Out of scope

None
