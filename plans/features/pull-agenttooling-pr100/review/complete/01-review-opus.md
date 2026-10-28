# 01 — review: pull-agenttooling-pr100

## What the feature was supposed to do

Propagate agentTooling `main` (upstream split `125b0d71194c1ce343b22e426c57bbf70638160b`,
which contains PR #100 `review-report-never-tracked`) into this repo's vendored
`agentTooling/` subtree, and regenerate the `plans/` stubs from the new templates.
PR #100: `run-review.sh` untracks an ignored-but-tracked `plans/review-report.md` and
archives each round's verdict to `plans/features/<slug>/review-report.md`;
`sync-plans.sh` untracks ignored tracked files and prints `UNTRACKED` lines.
"No findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans").

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

Expect: a no-change re-anchor merge (chain was `broken`, re-anchored at upstream
`00d1ff8`), the subtree pull merge touching only `agentTooling/`, and a commit syncing
`plans/.gitignore`, `plans/README.md`, `plans/features/README.md`.

## Contracts to hold it to

- Outside `agentTooling/` and the three generated `plans/` stubs, nothing changed.
- No edits made by hand inside `agentTooling/` (it must equal upstream's tree).
- `plans/` stubs are byte-identical to what `./agentTooling/sync-plans.sh` generates;
  `./agentTooling/sync-plans.sh --check` and `./agentTooling/update.sh --check` are clean.
- `plans/review-report.md` is not tracked (`git ls-files plans/review-report.md` empty).
- Repo-owned files (`PROJECT_FACTS.md`, `gate.sh`, `pr.sh`, ...) untouched.
- READMEs: the root and `plans/` README descriptions still accurate; generated READMEs
  not hand-edited.

## Verdict

Write the verdict to `plans/review-report.md`; its first line is `Verdict: clean` or
`Verdict: escalated`.
