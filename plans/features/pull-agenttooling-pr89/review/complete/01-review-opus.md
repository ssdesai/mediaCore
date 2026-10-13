# 01 — review: pull-agenttooling-pr89

Review brief. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Pull agentTooling `b88137c..75eb0fb` (split `75eb0fb2c3548743a35bb128bb6a1d550582b08b`),
which carries #87 "cloud-pull-fixes", #88 "env-profile-set-e" and #89
"rates-haiku-live-warning". Then run the freshly pulled `sync-plans.sh` and hand-merge
any repo-owned script it reported as `DRIFT`. It reported one: `plans/cloud-setup.sh`
(template-version 1 < 2), a header-only bump.

Run in a Claude Code cloud container on the session's assigned branch
`claude/sharp-newton-9fbqfd`: the manifest's `branches` names that branch, its fence
carries `"profile": "cloud"`, and the coordinating session is pinned in `sessions`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The `agentTooling/` prefix diff vs `origin/main` is exactly the upstream range
  `b88137c..75eb0fb` and nothing else. Expect upstream's own records under
  `agentTooling/self/features/{cloud-pull-fixes,env-profile-set-e,rates-haiku-live-warning}/`
  and the new `agentTooling/self/tests/{claimant-case,template-version-bump,update-cloud-branch}.sh`.
- The pull was run by hand, not by `update.sh`: the vendored copy predated
  `cloud-pull-fixes` and had no cloud path. The `git subtree pull --squash` (squash
  commit `b4ca9e2`, trailer `git-subtree-split: 75eb0fb2c3548743a35bb128bb6a1d550582b08b`)
  plus `sync-plans.sh` was run by hand, as `agentTooling/LIFECYCLE.md` → "Propagate"
  says. The manifest prose says so.
- `agentTooling/sync-plans.sh --check` is clean. The only non-`agentTooling/` changes
  besides the feature's own `plans/features/pull-agenttooling-pr89/` directory are
  `plans/README.md` (sync-owned) and `plans/cloud-setup.sh`.
- `plans/cloud-setup.sh` above its `# ── REPO-SPECIFIC` line is byte for byte the
  template's (`agentTooling/templates/plans/cloud-setup.sh`), version line `2`
  included; from that line down it is unchanged from `origin/main`. `bash -n` passes.
- Every other repo-owned script reports `in-sync` at its current template version (gate
  3, pr 6, worktree-setup 2, open-session 4, environment 1). Nothing else was
  hand-merged.
- The gate is green (the start's base gate was), or any red check is shown to be red on
  `main` too and untouched by this diff (the diff changes no package code).

## Verdict
