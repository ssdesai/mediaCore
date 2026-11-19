# 02 — review: split-tests-method, round 2

A hand build, round 2. Round 1 (`review/complete/01-review-opus.md`) escalated one finding,
recorded in `self/features/split-tests-method/escalations/01-review-opus.md`. This round's
rework was done by hand. Review the **whole** diff again against the spec below — never
against the builder's account of it — and say "no findings" when there are none: that is a
legitimate verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/split-tests-method/README.md`: its opening paragraph
and its "Deliberately excluded" list. Read it before the diff.
`self/features/split-tests-method/NOTES.md` is the builder's record, with the round-2
rulings (9–11). Read it after the diff, to check its claims.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. For this round's own change,
also read `git diff <the 'split-tests-method: review stamps' commit of round 1>..HEAD`.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date").
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold.

This feature's own, all of round 1's still binding:

- `harness/methods/split-tests/template.md`: the text after the marker line
  `<!-- split-tests: the implementer brief starts on the next line -->` is
  `harness/methods/vanilla-conv/template.md` byte for byte plus exactly one paragraph before
  `## Finish`. That paragraph names `%%TESTS_SHA%%` and `@@SLUG@@: acceptance tests`, says to
  make the tests pass and not delete or weaken them, limits changes to tests that contradict
  the spec or guess an open name or seam, and asks for each change with its reason under
  "Test changes". Every `@@NAME@@` is harness-filled, and an unfilled one still aborts. The
  author brief asks for black-box tests only, no implementation, one commit with the right
  subject staged by path, and no push or PR.
- `harness/methods/split-tests/run.sh`: both sessions go through `harness_claude` from
  `"$TREE"` with `vanilla-conv`'s flags, and exit 0, 2 or 1 per the methods contract. The
  test diff goes to `$HARNESS_LOG_DIR/<branch>-test-diff.txt` whatever the implementer's
  exit, and nothing lands in the tree. No `${x//pat/$var}`.
- **Round 2, the escalated finding.** What the author brief asks for and what `run.sh`
  accepts must now agree:
  - The brief allows test files plus "the `README.md` of a folder you add a test file to",
    and leaves anything else (a gate's test list, a runner config) for the implementer.
  - `run.sh` accepts exactly that: a non-test path passes only when it is named
    `TEST_README_NAME` and sits in a folder holding a test file of the same range.
  - `conftest.py` is a test name.
  - `split-tests-pair.sh` covers it: `colocated` (`src/components/Foo.test.tsx` plus that
    folder's README) and `conftest` pass, and `strayreadme` is refused, naming the file.
- **Round 2, the noted re-entry gap.** On the author's usage-limit stop, a tests commit
  that is not HEAD is refused with exit 1 before exit 2. `limitafter` covers this.
- `self/tests/split-tests-pair.sh` is recorded by `self/gate.sh`. Its README entry and the
  method README describe the round-2 behaviour.
- Out of bounds: `harness/run.sh`, `harness/lib.sh`, `hooks/` and
  `harness/check-fixture.sh` stay unchanged by this feature (the merge of `origin/main`
  carries #132's changes to them, which are not this feature's diff against `origin/main`).

## Verdict
