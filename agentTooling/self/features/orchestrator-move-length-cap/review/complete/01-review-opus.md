# 01 — review: orchestrator-move-length-cap

## What the feature was supposed to do

Close three fail-open gaps, per `OWNER_BRIEF.md` (the yardstick; this brief only adds to it):

1. **The orchestrator record move ignored the line cap.** `main()` in
   `hooks/allow-repo-commands.sh` asks `orchestrator_moves_own_record` before
   `orchestrator_command_allowed`, and only the latter checked `ORCHESTRATOR_MAX_LINE_CHARS`
   (20000). So a record move padded past the cap was approved outright. The cap must now be
   checked at the top of `orchestrator_moves_own_record`, the existing check kept, and no new
   literal named.
2. **`orchestration-start.sh` trusted any exit 0** from `roots.py start-refusal` and
   `roots.py self-write`, so an emptied or stubbed `roots.py` let a refused start through. Both
   CLI checks now print one fixed token on the go-ahead, and the start proceeds only on exit 0
   with exactly that output.
3. **The conformance check could flip an owner item** from `done` to `partial` on unchanged
   evidence. Diagnose it in `NOTES.md`, and make a `done` stable unless the evidence for that
   item changed, while a genuinely new gap still fails closed.

Plus three `self/BACKLOG.md` entries:

- an edited `roots.py` defeats the classifier;
- only a record's last fence is counted;
- `run-review.sh` adds a duplicate audit stem to `plans`.

Excluded: fixing those three backlog findings, and changing what the conformance executor is
shown.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The hook cap.** `orchestrator_moves_own_record` returns False for
  `len(command) > ORCHESTRATOR_MAX_LINE_CHARS` before reading the line.
  `orchestrator_command_allowed` keeps its own check. `self/tests/hook-orchestrator-role.sh`
  H29 must show:
  - the move padded to exactly the cap is ALLOW, and to cap+1 is DENY with the orchestrator
    allowlist reason;
  - the same for the `mkdir -p` remedy form;
  - both profiles.
- **The go-ahead token.**
  - It is defined once: `hooks/shared_rules.py` `ROOTS_CLI_GO_AHEAD`. `analysis/roots.py`
    binds it as `CLI_GO_AHEAD` (identity, `shared-rules.sh` S2) and prints it on the go-ahead
    of `start-refusal` and `self-write` only. `orchestration-start.sh` reads it through
    `SHARED_RULES_NAMES`.
  - The start refuses, writing nothing, on any exit 0 whose output is not exactly the token:
    `orchestration-records-in-repo.sh` R14 and `consumer-record-guard.sh` C7, with three stubs
    each (empty, `sys.exit(0)`, another printed line).
  - The real classifier's go-ahead still proceeds.
- **The conformance carry-forward.**
  - `conformance.py check-close` takes optional `--previous <report>` and
    `--changed <paths file>` (both or neither; one alone is exit 2).
  - An item is carried only when all of these hold:
    - the previous table marked it `done`;
    - the previous evidence names a file;
    - the review says `done`;
    - no file named in either round's evidence is among the changed paths.
  - Everything else is still a disagreement.
  - `feature-close.sh` takes the previous report from the `<slug>: review round N-1` commit,
    and the changed paths from `git diff --name-only <that commit>^ <judged head>` with the
    feature directory excluded. With no previous round, nothing is carried.
  - `self/tests/brief-conformance.sh` V1 (unit) and V2 (the real close, rounds 7–10) hold
    this, and K1/K2/D1 must still pass with their renumbered rounds.
- **Docs.** `LIFECYCLE.md` (step 5's item 3, and the close's refusal list), `README.md`'s
  `conformance.py` row, `hooks/README.md`'s `shared_rules.py` entry, `analysis/README.md`'s
  `roots.py` CLI lines and `self/tests/README.md` all describe the new behaviour.

"No findings" is a legitimate verdict.

## Verdict
