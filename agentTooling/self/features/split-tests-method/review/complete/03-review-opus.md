# 03 — review: split-tests-method, round 3

A hand build, round 3. Round 2 (`review/complete/02-review-opus.md`) escalated one finding,
recorded in `self/features/split-tests-method/escalations/02-review-opus.md`. This round's
rework was done by hand. Review the **whole** diff again against the spec below — never
against the builder's account of it — and say "no findings" when there are none: that is a
legitimate verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/split-tests-method/README.md`: its opening paragraph
and its "Deliberately excluded" list. Read it before the diff.
`self/features/split-tests-method/NOTES.md` is the builder's record: rulings 1–8 (round 1),
9–11 (round 2) and 12 (round 3). Read it after the diff, to check its claims.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. For this round's own change,
also read `git diff <the 'split-tests-method: review stamps' commit of round 2>..HEAD`.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date").
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold.

This feature's own. Every contract from rounds 1 and 2 still binds:

- `harness/methods/split-tests/template.md`: the implementer half is
  `harness/methods/vanilla-conv/template.md` byte for byte, plus exactly one paragraph
  before `## Finish`. That paragraph names `%%TESTS_SHA%%` and `@@SLUG@@: acceptance
  tests`, and asks for each test change under "Test changes". Every `@@NAME@@` is filled
  by the harness, and an unfilled one still aborts.
- The author brief asks for black-box tests only, with no implementation. It allows test
  files plus the `README.md` of a folder the author adds a test file to, and leaves anything
  else to the implementer. It asks for one commit with the right subject, staged by path,
  and no push or PR.
- `harness/methods/split-tests/run.sh`:
  - Both sessions go through `harness_claude`, from `"$TREE"`, with `vanilla-conv`'s flags.
  - It exits 0, 2 or 1 per the methods contract.
  - Exit 1, with no implementer, when the author:
    - commits nothing;
    - commits a path that is neither a test nor such a `README.md`;
    - leaves a tip that is not the tests commit;
    - leaves new uncommitted work.
  - It writes the test diff to `$HARNESS_LOG_DIR/<branch>-test-diff.txt`, whatever the
    implementer's exit.
  - Nothing lands in the tree.
  - It never uses `${x//pat/$var}`.
- **Round 3, the escalated finding.** On the author's usage-limit stop, once the tests
  commit exists, two checks run before the exit 2: the tip must be that commit, and the
  same uncommitted-work refusal a clean exit runs must pass. That refusal is
  `refuse_author_leftovers`, and both paths share that one copy. Without a tests commit, the
  stop exits 2 as before.
  - Pair-test case `limitdirty`: the tests commit, then `src/feature.py` left uncommitted,
    then the limit. Expected: exit 1, one session, and the refusal naming
    `src/feature.py` (4h, 4i4). `limitafter` and plain `limit` still behave as in round 2
    (4i3, 4k, 4l).
  - The method README, the `self/tests/README.md` entry and the manifest paragraph say so.
- Out of bounds: `harness/run.sh`, `harness/lib.sh`, `hooks/` and
  `harness/check-fixture.sh` show no diff against `origin/main`.

## Verdict
