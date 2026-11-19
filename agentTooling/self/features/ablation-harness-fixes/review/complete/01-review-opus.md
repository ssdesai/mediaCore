# 01 — review: ablation-harness-fixes

Four fixes to defects found while running vinylCatalogue's toolingAblation experiment
(the `importedWhereV2` fixture). Each must arrive with a regression test in the harness's
own test style. "No findings" is a legitimate verdict: report what you checked.

## What the feature was supposed to do

1. **The command hook refuses a feature branch's first push.** In a cloud run the
   implementer's `git push -u origin <current branch> 2>&1 | tail -3` (and the same
   without `-u`) was denied by `hooks/allow-repo-commands.sh` as "pushes somewhere other
   than this branch", while `git push -u origin <current branch>` (no redirect) prompted
   in a sibling run. The builder must find the actual root cause in the hook and fix it
   so the push of the checked-out branch to origin, with or without `-u`, with or without
   a descriptor redirect, keeps the prompt (a push is a write: handed to the human),
   while a push to `main` and a push that targets another branch are still refused
   exactly as before. The approval side must not get looser.
2. **A `--from review` resume leaves the worktree without its environment.**
   `harness/run.sh`'s `do_pr_resume` re-adds the worktree but never ran the fixture's
   `setup[]` commands, so the accept-at-PR-open probe crashed for want of `.venv`. The
   resume must rerun the fixture's setup, through the same code the setup stage uses
   (not a second copy of the loop), before any probe or gate runs.
3. **`settle_pr` errors when the arm already closed its manifest window.** A plans arm's
   own `feature-close.sh` closes the window, and the harness's close then logged `ERROR:
   no open session_window.to`. With no open window the harness must skip the close (and
   its commit) with an informational line, not an error; an open window is still closed
   and committed as before.
4. **Accept probes are never validated against a reference build.** `fixture.json` gets
   an optional reference commit; `harness/check-fixture.sh` runs the fixture's
   `accept/accept.py` against it in a throwaway detached worktree set up with the
   fixture's `setup[]`, and fails when the probe does not pass there. The throwaway
   worktree must be removed, and no branch or ref created. Documented in
   `harness/README.md` (and the fixture shape), and any doc that says `check-fixture.sh`
   rehearses the gate when it does not is corrected where it lives in this repo.

Excluded: the plans workflow's "escalated review = no PR" behaviour (a BACKLOG entry
only); editing a consuming repo's files.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/allow-repo-commands.sh`: the deny side's word lists (`command_words`,
  `chains_chdir`) must read a line the way bash does; every existing row of
  `self/tests/hook-cloud-profile.sh` and `self/tests/allow-repo-commands.sh` keeps its
  answer; new rows cover the redirect shapes for the current branch (prompt), another
  branch (cloud deny) and `main` (deny in both). The hook never exits non-zero.
- `hooks/README.md` describes the descriptor rule where the deny side's reading is
  described.
- `harness/run.sh`: one function runs `setup[]` (the setup stage, the resume, and
  `check-fixture.sh` if it shares it via `lib.sh`); `settle_pr` consults the open window
  (`open_manifest_window_of`) before closing.
- `harness/check-fixture.sh`: exit code is still the failure count; the reference check
  fails the fixture when the probe fails at the reference, warns (does not fail) when no
  reference is named, and can be skipped explicitly; its header and `harness/README.md`
  row say what it does and does not do.
- `harness/tests/smoke.sh` asserts each of fixes 2–4 (resume runs setup before the
  PR-open probe; a closed window is skipped with no ERROR; a good reference passes, a bad
  one fails, the throwaway worktree is gone); `harness/tests/README.md` names the new
  cases.
- bash 3.2, `set -uo pipefail` with no `set -e`, named constants, `mktemp -d` with an
  explicit template under `$TMPDIR` (`self/PROJECT_FACTS.md`).
- `self/BACKLOG.md` gains the escalated-review-no-PR entry.
- `./self/gate.sh` green, including the README-index check.

## Verdict
