# 01 — review: pull-agenttooling-pr77

Review the propagation of agentTooling PRs #76 ("router-brief-writes") and #77 ("unpin-and-yield") into mediaCore.

## What the feature was supposed to do

Pull agentTooling 2a2a4a6..509440e (#76 and #77, split sha 509440eeb9770c5f000428eadfca0ce207f8f421)
into the vendored `agentTooling/` prefix via `agentTooling/update.sh`. The previous pull
was 2a2a4a6 (#75), so the range carries two upstream PRs:

- #76 `router-brief-writes`: the close's unpinned-builder check ignores the router's own
  brief writes (the feature's `review/` and its manifest `README.md` in the worktree);
  `--unpinned-builder` prints `<id>\t<evidence>` and `feature-close.sh` names the evidence.
- #77 `analysis/manifest.py`: `unpin-session`, `unpin-subagent` and `unexclude-subagent`.
- #77: the capture yields a parent-selected delegate that another feature pins, and records
  `yielded_agent_ids` in `planning.json`.

Nothing else should change: the only consumer-side effect is the `plans/` sync output
(`plans/features/TEMPLATE.md`).

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

The `agentTooling/` prefix diff against main must be exactly the upstream range
2a2a4a6..509440e and nothing else: no local edits, no missing files, no extra files.
Both `self/features/router-brief-writes/` and `self/features/unpin-and-yield/` arrive with it.
Outside that prefix expect only `plans/features/TEMPLATE.md` and this feature's own
`plans/features/pull-agenttooling-pr77/` directory.

## Contracts to hold it to

- `agentTooling/sync-plans.sh --check` is clean (everything `in-sync`).
- `plans/gate.sh` is green.
- The `agentTooling/` prefix matches upstream 509440e byte for byte.

"No findings" is a legitimate verdict.

## Verdict
