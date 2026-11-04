Verdict: escalated

# Review: pr-body-refresh

## What the batch was supposed to do

Every round's `feature-close.sh` builds a fresh PR body (the closing review's report plus the
Rounds table) and hands it to `pr.sh <slug> <body-file>`. At template-version 6, `pr.sh`
found the PR already open, printed `already open: <url>` and exited 0 without reading the
body. So round 1's body stayed on the PR and every later round's was dropped (PRs #92 and
#94). The batch adds `forge.sh pr-edit <pr-url> <body-file>` (`PATCH /repos/{o}/{r}/pulls/{n}`,
REST in both profiles). It has both `pr.sh` copies call it on the already-open path, bumps
the template to 7, and makes `feature-close.sh` warn about a stale body instead of saying
"open the PR by hand" when `pr.sh` fails but printed a url. It also updates the docs and
adds tests.

## Does it do it

Yes, for the case it targets. Checked by reading against each contract in the brief:

- **`pr.sh` contract.** Exit 0 now covers three cases only: opened, already open with the body
  refreshed, or no forge CLI. A refused `pr-edit` exits 1 with a `fail` line naming the url.
  The path where no PR is open behaves as before. The `body_file` block, including the
  fallback body and its `trap … EXIT` cleanup, moved above the already-open test, so both
  paths share it and the temp file is removed on every exit.
- **Two copies.** `git diff --no-index self/pr.sh templates/plans/pr.sh` shows only the three
  hunks it showed before (header, merge-request contract line, `AUTO_MERGE` block). The logic
  below REPO-SPECIFIC is identical.
- **`TEMPLATE_VERSIONS`.** `pr.sh 7` is re-recorded. `fixtures/pr-v6.sh` is byte-identical
  to `origin/main:templates/plans/pr.sh`. The gate (including `template-versions.sh`) is
  green.
- **`forge.sh pr-edit`.** Every value is its own argv word (`-F body=@file`), and no shell
  reads the body. The PR number is taken from the url the same way `auto-merge` takes it.
  The number and the file's readability are both checked before any call. A failure names
  `PATCH <endpoint>`, and an answer with no `html_url` is a failure. It never uses `gh pr`,
  `gh auth status` or GraphQL. The verb is documented in the header table, the REST-path
  table, the usage text and the root README's `forge.sh` row, and that row matches the code.
- **Readers of `pr_opened`.** `analysis/report.py` (`compute_wall_clock`) reads only `_at`
  and `url`, never `rc`. The merge request decides by `pr.sh`'s version, not by `PR_RC`. The
  capture does not read the stamp. None of them assumes that a non-zero rc means there is
  no PR.
- **"Adopting pr.sh version 7".** A consuming repo can follow it to hand-merge 6 → 7: move
  the body block, add the `pr-edit` call and its failure, update the contract line, bump
  the version line.

## Fixed in this pass

- `README.md` → "Adopting pr.sh version 7": the only step was numbered `5.`, copied from
  another section's list. It is now `1.`.
- `self/tests/feature-lifecycle.sh`, header entry X3: the inserted X3d–X3f text had split
  the existing sentence across a broken line ("exit 0, the PR already open and no" alone on
  its own line). The entry is reflowed, with the original sentence first and X3d–X3f after
  it. This was a comment-only change.

## Escalated to the next round

1. **`feature-close.sh` treats "any url in pr.sh's stdout" as "the PR is open"
   (`feature-close.sh:284–291`).**
   - **The problem:** `PR_URL` is the last `https?://…` anywhere in `pr.sh`'s stdout, and
     `pr.sh` runs `git push -q … 2>&1`. When a push is rejected or the remote can't be
     reached, git prints `error: failed to push some refs to '<remote url>'` or
     `fatal: unable to access '<remote url>/': …`. With an http(s) origin, `PR_URL` is then
     that remote url. In a cloud container the origin is always the http proxy.
   - **The failure:** after this batch, a failed push now hits the new branch and prints
     `exited 1 with the PR open at http://…/git/o/r' — its body may still describe an
     earlier round`. No PR exists, and the old, correct advice ("open the PR by hand") is no
     longer printed. The closing summary (`feature-close.sh:325`) and the `pr_opened.url`
     that `report.py` reports also carry the remote url. That part predates this batch, but
     the batch turned that url into a statement that the PR is open.
   - **No test catches it:** every fixture origin is a local path, so no url reaches the log.
   - **The fix is a design decision:** `feature-close.sh` should get the "PR is open" signal
     from a contract line `pr.sh` prints, not from whatever text matches a url pattern. For
     example, take the url only from a `  pr      …` or `  fail  … pr-edit <url>` line, or
     add a contract line such as `pr-url: <url>` to `pr.sh`'s contract block. The contract
     block would change, so this needs a template bump.
   - **Test to add:** a `feature-lifecycle.sh` check whose `pr.sh` stub (or a refused push
     to an `http://` origin) prints `error: failed to push some refs to 'https://example.invalid/o/r.git'`
     and exits 1. Assert that the close prints "open the PR by hand", does not print
     "with the PR open at", and stamps `pr_opened` with an empty url.

## Unverified

Nothing the gate skipped. The real `PATCH` against GitHub and the cloud proxy has not been
run (the tests use stub `gh`). The same is true of `pr-open`.
