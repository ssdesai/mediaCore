feature: @@SLUG@@

Write the acceptance tests for one feature in the repository at the worktree below, and
commit them. **Tests only: you write no implementation.** Someone else implements the
feature afterwards, in a separate session, from the same spec and against your tests.
**One shot — you will not be resumed.** Nobody is listening while you work: decide anything
the spec leaves open yourself and do not stop to ask.

- Worktree: `@@TREE@@`, branch `@@BRANCH@@`, off `@@BASE@@`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

@@ISOLATION@@

## The spec

`@@SPEC_TREE@@/@@SPEC_PATH@@`, sections **@@SPEC_SECTIONS@@** — read-only, @@SPEC_PROVENANCE@@. This is what the tests are written from.

## The facts of this feature and this worktree

@@FACTS@@

## The tests

- Black-box acceptance tests of what the spec implies: drive the feature through its real
  routes, CLI and files on disk, and against the repo's contract fixtures where it has
  them. Never against internals — no private function, no module layout the spec does not
  name. Where the spec leaves a name or a seam open, choose one and say so in a comment
  at the test.
- Put them where the repo's own tests live, following its layout and naming and the README
  rules its `CLAUDE.md` sets — a new test file gets its line in its folder's README.
- **No implementation.** Commit test files and nothing else: no source, no stub, no
  config, no fixture the feature itself would ship. The one exception is the `README.md`
  of a folder you add a test file to, for that file's line. Anything else a test needs
  outside them — a gate's list of test scripts, a test runner's config — is left for the
  implementer: name it in your report.
- Run them once. They must collect and fail **because the feature is missing** — a missing
  route, command, module or file — and not on a syntax error, a typo or a broken import of
  your own test code. The gate is `cd <tree> && @@GATE_COMMAND@@` (about @@GATE_MINUTES@@
  minutes); it will be red, and that is expected. A narrower command over your files is
  enough where the repo has one.

## Finish

Commit the test files, and only them, on `@@BRANCH@@` as **one** commit with the subject
`@@SLUG@@: acceptance tests`. Stage them by path (`git add <file>...`), never `git add -A`
or `git add .`: the tree holds files that are not yours to commit. Leave nothing else
changed. Do not push and do not open a PR.

## Final report, terse

The commit sha; each test file and what it covers; every name or seam you chose where the
spec left it open; anything the spec implies that you could not test black-box, and why.

<!-- split-tests: the implementer brief starts on the next line -->
feature: @@SLUG@@

Implement one feature in the repository at the worktree below, make its gate pass, commit,
push, and open the PR. **One shot — you will not be resumed.** Nobody is listening while
you work: decide anything the spec leaves open yourself and do not stop to ask.

- Worktree: `@@TREE@@`, branch `@@BRANCH@@`, off `@@BASE@@`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

@@ISOLATION@@

## The spec

`@@SPEC_TREE@@/@@SPEC_PATH@@`, sections **@@SPEC_SECTIONS@@** — read-only, @@SPEC_PROVENANCE@@. This is what to build.

## The facts of this feature and this worktree

@@FACTS@@

The commit `%%TESTS_SHA%%` (`@@SLUG@@: acceptance tests`) holds acceptance tests written from
the spec by someone else; make them pass. Do not delete or weaken them. Change one only
where it contradicts the spec or guesses a name or seam the spec leaves open, and list every
such change, with its reason, in the PR body under a heading "Test changes" (write "none"
there when you changed none).

## Finish

1. `cd <tree> && @@GATE_COMMAND@@`, re-run until the verdict line is green (about
   @@GATE_MINUTES@@ minutes per run). A SKIPPED check is not green.
2. Commit on `@@BRANCH@@`, push to `origin`, and open the PR against `main`: write the body
   to a file outside the tree, then
   `<tree>/agentTooling/forge.sh pr-open @@BRANCH@@ main '@@SLUG@@' <body file>` — it works
   on a laptop and in a Claude Code cloud container alike, where `gh pr create` is refused.
   Title: `@@SLUG@@`. The body's **first line** must read:
   *one arm of an experiment — do not merge until it picks a winner*.

## Final report, terse

The PR URL; the gate's verdict line; anything in scope you did not finish and why.
