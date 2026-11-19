# 01 — review: orchestration-record-fixes

Review the diff against the spec below. Hold it to the contracts; do not read the builder's
report for what it should have done. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Two fixes from an orchestration run in a consuming repo (humanNetworkMap):

1. **Push reading ignores redirections.** `git push origin <current branch> 2>&1` was refused
   as "pushes somewhere other than this branch": a redirection word read as a refspec. A
   redirection word (`2>&1`, `>out`, `> out`, `2>/dev/null`, `>>log`, `&>x`, `<in`) is never
   a refspec nor the remote in `push_reading`, so `push_goes_elsewhere` and
   `push_reaches_protected` judge only the real arguments. A push to `main` with a
   redirection (`git push origin main 2>&1`) and a real elsewhere-push with one
   (`git push origin other 2>&1`) are still denied. The builder found the redirects already
   stripped where words are produced (`command_words`/`chain_tokens`, since
   `ablation-harness-fixes`) — check that claim, and that the tests now pin every spelling.
2. **Orchestration report resolves feature reports from the project root.**
   `report.py --orchestration` resolves a feature's `report` path against the consuming
   repo's root (the directory holding `agentTooling/`) in a consuming repo, and against
   agentTooling's own root for agentTooling's entries and in a standalone checkout. Cross-repo
   entries (another repository) are out of scope: they keep #138's `--checkout` and the
   `UNPRICED_NEEDS_CHECKOUT` reason. `--checkout` stays the override.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `self/tests/hook-cloud-profile.sh` table T holds: the current branch with `2>&1`,
  `2>&1 | tail -3`, `2> /dev/null` and with `-u` is allowed in the cloud; with `> log`, `>out`,
  `>> log`, `&>x`, `< in` it prompts (a write, never a deny); `main` and another branch with
  a redirection in any position are denied.
- `compute_orchestration_report(record, folder, repo_root, checkouts=None, home_root=None)`:
  an `agentTooling` entry resolves against `home_root` (`repo_root` when omitted); any other
  entry against `checkouts[repo]` else `repo_root`; the existing call shapes in
  `self/tests/coordinator-records.sh` (K4) still hold.
- `roots.record_repo_root()` is the agentTooling directory when it has a `.git` of its own,
  else its parent; `artifact_root` is untouched.
- `self/tests/orchestration-records.sh` S7 prices a consuming-repo fixture
  (`plans/features/<slug>/report.json`) and an `agentTooling/self/features/...` entry; S6 (the
  standalone layout) still prices.
- `hooks/README.md`, `analysis/README.md`, `ORCHESTRATION.md` say how each is read; NOTES.md
  records the choices and the untrue fact in the brief.

## Verdict
