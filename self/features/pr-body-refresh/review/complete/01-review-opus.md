# 01 — review: pr-body-refresh

## What the feature was supposed to do

`feature-close.sh` builds the PR body on every close — the closing review's report, then
`analysis/report.py --rounds-md`'s Rounds table — and hands it to the repo-owned
`pr.sh <slug> <body-file>`. At template-version 6 both `self/pr.sh` and
`templates/plans/pr.sh` asked `forge.sh pr-find` and, finding a PR open, printed
`already open: <url>` and exited 0 without reading the body file. Round 1 set the body;
every later round's close left it stale (agentTooling PRs #92 and #94).

The change:

1. `forge.sh` gains `pr-edit <pr-url> <body-file>`: `PATCH /repos/{o}/{r}/pulls/{n}`, the
   body read by gh from the file, the same shape and error handling as `pr-open`
   (readable-file check before any call, a failure naming the endpoint, the url printed),
   the number taken from the url as `auto-merge` takes it. One REST path in both
   profiles. Documented in the header's verb table, the usage text, and the root
   README's `forge.sh` row.
2. Both `pr.sh` copies call `"$FORGE" pr-edit "$existing" "$body_file"` on the
   already-open path, print `  pr      already open, body refreshed: <url>`, and on a
   refusal print a `fail` line and exit 1. The two copies still differ only where they
   did before.
3. `templates/plans/pr.sh` at `template-version: 7`, its row re-recorded in
   `templates/plans/TEMPLATE_VERSIONS`.
4. `feature-close.sh`: a non-zero `pr.sh` rc used to mean "nothing opened" ("open the PR
   by hand"); now a non-zero rc with a url warns that the PR is open with a stale body.
5. Docs: root README (`forge.sh`, `feature-close.sh` and `templates/` rows, a new
   "Adopting pr.sh version 7"), `LIFECYCLE.md` step 6, `templates/README.md`,
   `self/README.md`, `self/PROJECT_FACTS.md`, the tests and fixtures READMEs.
6. Tests: a new `self/tests/pr-body-refresh.sh` (both copies against a stub forge; the
   PATCH itself under both profiles), wired into `self/gate.sh`; `feature-lifecycle.sh`
   X3d–X3f and P2e; `sync-check.sh` moved to 7 with a new frozen `fixtures/pr-v6.sh` (4i).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `pr.sh`'s contract block (`OPEN` entry point): exit 0 only for opened, already open
  with the body refreshed, or the no-forge-CLI skip; a forge that is there and refuses —
  the refresh included — is non-zero. Check the not-open path is behaviourally unchanged,
  including the fallback body and its temp-file cleanup now that the block moved.
- `git diff --no-index self/pr.sh templates/plans/pr.sh` shows the same hunks it shows on
  `main` (the header, the merge-request contract line, the AUTO_MERGE block), with
  identical logic below REPO-SPECIFIC (`feature-lifecycle.sh` P1d).
- `TEMPLATE_VERSIONS`' rule: the hash is of the whole file but its version line, and a
  bump precedes the re-record; `self/tests/template-versions.sh` passes against the fork
  point.
- `forge.sh`'s header: every value its own argv word, no shell reads the body, never
  `gh pr`/`gh auth status`/GraphQL in the cloud; exit codes 0/1/2 as documented.
- `feature-close.sh`'s `pr_opened` stamp: rc and url still recorded; say whether any
  reader of `pr_opened` (report, capture, the merge request) assumes rc != 0 means no PR.
- README Rule 1/2 entries touched (the `forge.sh` row's verb list and REST paths) match
  the code.
- An "Adopting" paragraph that a consuming repo could follow to hand-merge 6 → 7 without
  reading the diff.

"No findings" is a legitimate verdict. Phrase any finding as an assertion a test could
make, and keep two lists: fixed here, and escalated to the next round.

## Verdict
write: /home/user/agentTooling/self/review-report.md
