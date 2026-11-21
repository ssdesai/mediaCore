# 03 — review: orchestrator-move-length-cap

## What the feature was supposed to do

Round 3 is the owner's last authorised round. The owner's ruling of 2026-11-21 (`NOTES.md` →
"Owner's ruling: split") cut the feature to **defects 1 and 2 only**, plus the backlog
entries. Defect 3, the conformance carry-forward, is split out. Its code is gone from the
diff: `conformance.py`, `feature-close.sh`, `self/tests/brief-conformance.sh`, `LIFECYCLE.md`
and the root `README.md` match `main` again. Its diagnosis and design are filed as the last
entry of `self/BACKLOG.md`.

1. **The record move's line cap.** `main()` in `hooks/allow-repo-commands.sh` asks
   `orchestrator_moves_own_record` before `orchestrator_command_allowed`. The cap
   `ORCHESTRATOR_MAX_LINE_CHARS` is now checked at the top of `orchestrator_moves_own_record`.
   The check in `orchestrator_command_allowed` is kept, and no new literal is named.
2. **The `roots.py` go-ahead token.** `roots.py start-refusal` and `roots.py self-write` print
   `shared_rules.ROOTS_CLI_GO_AHEAD` (`ok`) on the go-ahead. `orchestration-start.sh` proceeds
   only on exit 0 with exactly that output, and anything else refuses.

The backlog gets four entries:

- an edited `roots.py` defeats the classifier;
- only a record's last fence is counted;
- `run-review.sh` duplicates the audit stem;
- the split-out conformance flip.

Owner items 1, 5, 6, 7 and 8 are not reviewable as code:

- items 1 and 5 are judged by hand at the close;
- items 7 and 8 are split out;
- item 6 is the diagnosis in `NOTES.md` and `BACKLOG.md`.

Mark them in the acceptance table with that reason.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The cap.** `orchestrator_moves_own_record` returns False when `len(command) >
  ORCHESTRATOR_MAX_LINE_CHARS`, before reading the line. `orchestrator_command_allowed`
  keeps its own check.
- **H29** in `self/tests/hook-orchestrator-role.sh` covers:
  - the move and the `mkdir -p` remedy padded to exactly the cap: ALLOW;
  - the same padded to cap+1: DENY with the orchestrator allowlist reason;
  - both profiles.
- **The token** is defined once, as `hooks/shared_rules.py` `ROOTS_CLI_GO_AHEAD`:
  - `analysis/roots.py` binds it as `CLI_GO_AHEAD` (identity: `shared-rules.sh` S2);
  - `orchestration-start.sh` reads it through `SHARED_RULES_NAMES`, so no file restates the
    literal (S3).
- **Fail-closed tests.**
  - `orchestration-records-in-repo.sh` R14 and `consumer-record-guard.sh` C7: an empty stub,
    a `sys.exit(0)` stub and a stub printing another line each refuse with nothing written.
  - The real classifier's go-ahead still proceeds.
- **Nothing of defect 3 remains.** `git diff origin/main...HEAD` shows no change to
  `conformance.py`, `feature-close.sh`, `self/tests/brief-conformance.sh`, `LIFECYCLE.md` or
  `README.md`.
- **Docs.** `hooks/README.md` (the `shared_rules.py` entry), `analysis/README.md` (the
  `roots.py` CLI lines) and `self/tests/README.md` (H29, R14, C7, S1) describe the change.

"No findings" is a legitimate verdict.

## Verdict
