# 02 — review: pr-body-refresh (round 2)

## What the round was supposed to do

Round 1 (`escalations/01-review-opus.md`, read it first) found the whole feature correct
but escalated one defect: `feature-close.sh` took the last `https?://` anywhere in
`pr.sh`'s stdout as the PR url, and `pr.sh` runs `git push … 2>&1`. A refused push names
the remote's url (an http proxy url in every cloud container), so round 1's new warning
would say "the PR is open at <remote>" when no PR exists, and stamp that url.

The rework:

- `feature-close.sh` reads the url only from lines beginning `  pr ` (`PR_URL_LINE_RE`),
  which every `pr.sh` template version (4–7) already prints its url on.
- Both `pr.sh` copies: the `stdout` line of the contract block says the url goes on a
  `  pr ` line; a refused refresh prints `  pr      already open, body NOT refreshed:
  <url>` before its `fail` line (which no longer carries the url). Still
  template-version 7, the hash re-recorded.
- Tests: `feature-lifecycle.sh` X3g–X3h (a `git` wrapper refusing `pr.sh`'s push with an
  https remote in the message; the close says "open the PR by hand" and stamps no url);
  `pr-body-refresh.sh` R3b/R3d.
- Docs: root README (the close row's dependency, "Adopting pr.sh version 7"),
  `LIFECYCLE.md` step 6, `self/tests/README.md`, `NOTES.md` rulings 10–12.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round-2 rework is the commits after `pr-body-refresh: review
stamps`; read the whole feature diff, but judge the rework against the escalation.

## Contracts to hold it to

- The escalation's failure is gone: no line `pr.sh` prints other than its own `  pr `
  lines can set `PR_URL`. Check every `echo` in both copies and in `fixtures/pr-v4.sh`,
  `pr-v5.sh`, `pr-v6.sh`, and say whether any version prints its url somewhere a `  pr `
  reader would now miss (that would regress `feature-lifecycle.sh` X6 or CB).
- The round-1 contracts still hold (`escalations/01-review-opus.md` → "Does it do it"):
  the two copies differ only in their three known hunks, `TEMPLATE_VERSIONS` matches,
  `forge.sh pr-edit` unchanged.
- X3g–X3h would fail if the close went back to reading any url, and the `git` wrapper
  cannot affect any other assertion in the file.

"No findings" is a legitimate verdict. Phrase any finding as an assertion a test could
make, and keep two lists: fixed here, and escalated to the next round.

## Verdict
write: /home/user/agentTooling/self/review-report.md
