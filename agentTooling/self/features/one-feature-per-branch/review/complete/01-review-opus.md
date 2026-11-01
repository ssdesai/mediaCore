# 01 — review: one-feature-per-branch

## What the feature was supposed to do

Three things, on the cloud profile where one session holds one branch holds one feature:

1. **Withdraw the merged-manifest exception** `harness-cloud-pins` added. `feature-start.sh`
   must refuse a start when a tracked manifest names the branch, whether or not
   `origin/<base>` already carries it, and the refusal names the feature.
   `plan-runner-roots.sh`'s `started_features_on` must name such a manifest too;
   `STARTED_MERGED_REF` is gone. Every doc outside `self/features/` that described the
   exception reads as the one-branch-one-feature rule again. `self/tests/cloud-start.sh`
   S2 asserts the inverse.
2. **Document orchestrator and implementer sessions** in `LIFECYCLE.md`, in a section
   before the Review step, about 15 lines, naming `orchestration-records` without defining
   it; two lines in `self/PROJECT_FACTS.md`'s cost-rule paragraph point at it.
3. **Price a session once when its id has two transcripts.** Claude Code writes
   `~/.claude/projects/<dir from cwd>/<id>.jsonl`; when the cwd moves, a second file with
   the same id starts under another project directory holding the whole session, so it is
   a superset. `analysis/capture_planning.py` must, for every session id it prices (by
   branch, cwd or pin), find every copy across every project directory, price the one whose
   latest timestamp is latest, count the session once, and warn `session <id> has
   transcripts in <n> project directories; priced <path>`. Matching rules are otherwise
   unchanged. `self/tests/capture-guard.sh` phase 19 covers it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Nothing under `self/features/harness-cloud-pins/` or `self/features/claude-md-chain/`
  or `.claude/` is touched. `grep -rn` for `STARTED_MERGED_REF`, `merged manifest` and
  `already on the base` outside `self/features/` finds no description of the exception.
- bash 3.2 compatibility, no `set -e`, named constants (`self/PROJECT_FACTS.md`).
- Item 3: a session in the main walk is visited once per id (`walked_session_ids`); its
  subagents are looked for beside every copy and still priced once per agent id; the
  pinned-elsewhere loop uses the best copy among directories the walk did not scan; a
  lone copy draws no warning; the warning fires only for a session actually priced.
  Look for a path where two copies are both priced, or where the shorter copy is priced
  while a longer one exists, or where a session that was previously selected is no longer
  selected.
- READMEs of every touched folder (`analysis/`, `self/tests/`, the root, `self/`) describe
  the change accurately, including the project-directory contract in
  `analysis/README.md`.
- "No findings" is a legitimate verdict.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
