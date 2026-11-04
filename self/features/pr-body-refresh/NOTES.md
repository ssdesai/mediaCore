# Notes: pr-body-refresh

Rulings made during the hand build, each with its reason. The brief is the spec; these
are what it left open.

## Why the already-open path never read the body

1. **`pr.sh` predates rounds.** Its "already open" branch was there by template-version 3
   (`README.md` → "Adopting capture on the branch" names it), when a second run of `pr.sh`
   on the same branch could only be a re-run of the same close and the body it would have
   sent was the one already on the PR. It was a safety check against opening a
   second PR, never a second-round path. Rounds came later
   (`feature-close-and-review-rounds`, template-version 4), and made every escalated
   round's re-close a call with a *new* body, but nothing revisited that branch: the
   versions after it (5, the forge adapter; 6, the merge request through it) changed how
   the forge is asked, not what is asked on a re-close. So round 1's report stayed on
   the PR while later rounds' closes printed `already open` and moved on.

## Decisions

2. **Refresh on every re-close, not only when the round changed.** The body is defined as
   the current review's report plus the Rounds table, and the close builds it fresh each
   time. Knowing whether it changed would need a GET of the current body and a byte
   compare — a second API call and a second code path to save one PATCH that is harmless
   when it rewrites identical bytes. A re-close inside the same round (a capture retry)
   rewrites the same body, which is a no-op on the forge.
3. **A refused refresh is a failure (exit 1), not a warning.** The brief asked for it, and
   it matches the template's contract since 5: a forge that is there and refuses is never
   a skip. A PR whose body describes a tree two rounds old is the defect this feature
   exists for; exiting 0 would hide it again.
4. **The close's warning splits on whether a url came back.** `feature-close.sh` read any
   non-zero `pr.sh` rc as "nothing opened" and said "open the PR by hand". With a v7
   `pr.sh` a non-zero rc can now come with an open PR, and `pr.sh` prints its url, so
   `PR_URL` is set (where it is read from was changed in round 2, ruling 10). A non-zero rc with a url
   now warns that the PR is open with a possibly stale body; without one the old warning
   stands. The `pr_opened` stamp keeps rc 1 and the url, which is an accurate record: the
   PR exists, the step failed. Nothing branches on `pr_opened rc` (the merge request
   runs on the capture's rc), so no other caller changed.
5. **The body file is resolved before the already-open test.** Both paths need it — the
   fallback text when no report was written included — so the block moved up rather than
   being duplicated. A fresh open is byte-for-byte unchanged in behaviour.
6. **`pr-edit` mirrors `pr-open` and `auto-merge`**: the PR number is the url's last path
   segment and must be digits (as `auto-merge` already required), the body file must be
   readable before any call, the body travels as `-F body=@<file>` so no shell reads it,
   the response's `html_url` is printed and its absence is a failure. One REST path in
   both profiles — the cloud proxy serves REST PATCH as it serves POST.
7. **Version 7 for both copies; `self/pr.sh` keeps its one difference** (`AUTO_MERGE=0`
   above the REPO-SPECIFIC line). `git diff --no-index self/pr.sh templates/plans/pr.sh`
   shows the same hunks before and after, with the new comment text on both sides.
8. **`fixtures/pr-v6.sh` is frozen** from `origin/main`'s template, as `pr-v4.sh` and
   `pr-v5.sh` were for their bumps, so `sync-check.sh` 4i shows a consumer at 6 reading
   `DRIFT 6 < 7`. The older fixtures' drift lines now read `< 7`.

## Tests

9. **A new test file, not more of `feature-lifecycle.sh`.** The three cases the brief
   named, for both copies, need only a repo with a bare origin and a stub forge — no
   start, no review, no capture — so `pr-body-refresh.sh` runs in a second or two where a
   lifecycle phase costs a full close. `forge.sh pr-edit`'s own contract (Part E) sits
   beside it rather than in the lifecycle's F block for the same reason. The lifecycle
   gets the whole-close view: X3d (a re-close PATCHes once) and X3e–X3f (a refused PATCH
   warns with the url and stamps rc 1), through a `GH_PATCH_RC` knob on its stub `gh`.

## Round 2 (review escalation: any url in pr.sh's output was taken for an open PR)

10. **The close reads the PR url only from `pr.sh`'s lines beginning `  pr `.** It used
    to take the last `https?://` anywhere in `pr.sh`'s stdout, and `pr.sh` runs
    `git push … 2>&1`: a refused push names the remote's url, an http proxy url in every
    cloud container. Round 1's new branch then turned that into "the PR is open at
    <remote>". Of the reviewer's two options, the existing `  pr ` line was chosen over a
    new `pr-url:` contract line: every template version (4, 5, 6 and 7) already prints its
    url on a `  pr ` line, so no consumer copy has to change for the url to be stamped,
    and no version bump beyond round 1's 7 is needed. The contract block's `stdout` line
    now says so. A customised `pr.sh` that prints its url elsewhere loses only the stamp's
    url, which the "Adopting pr.sh version 7" section says.
11. **A refused refresh prints `  pr      already open, body NOT refreshed: <url>`** before
    its `fail` line, so the open PR's url is on a `  pr ` line too; the `fail` line no
    longer carries it. Still template-version 7: `main` is at 6, and the template-versions
    check compares against the fork point, so re-recording the hash is correct here.
12. **The test refuses the push with a `git` wrapper ahead on `PATH` for one close**
    (`feature-lifecycle.sh` X3g–X3h), refusing only `git push …` with no `-C`, which is
    `pr.sh`'s spelling; the capture pushes with `git -C <checkout> push` and goes through,
    so the close still exits 0 and the assertion is about the warning and the stamp
    alone. A real https origin would need the network.
