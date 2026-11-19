Verdict: escalated

# Review: split-tests-method

## What the batch was supposed to do

Add `harness/methods/split-tests/`, a method beside `vanilla-conv` (not on the ladder). Two
fresh sessions run in the cell's tree through `harness_claude` with `vanilla-conv`'s model
and flags. First a **test author** writes black-box acceptance tests from the spec and
commits only those, as `<slug>: acceptance tests`. Then an **implementer** gets
`vanilla-conv`'s brief byte for byte plus one paragraph that points it at that commit. Both
briefs live in one `template.md`, split at a marker line. `run.sh` exits 1 (and starts no
implementer) when the author commits nothing, commits a non-test path, ends on a commit that
is not the tests commit, or leaves new uncommitted work. It writes the implementer's test
diff to `<experiment>/logs/<branch>-test-diff.txt`. A gate-recorded pair test holds the
implementer half to `vanilla-conv`'s template plus that one paragraph.

## Does it do it

Yes, with one real gap (escalated below). I checked each point against the diff, not
against NOTES.md:

- **Implementer half:** it matches `vanilla-conv/template.md` exactly, plus one paragraph
  before `## Finish`. That paragraph names `%%TESTS_SHA%%` and `@@SLUG@@: acceptance tests`.
  It says to make the tests pass and not delete or weaken them, to change one only when it
  contradicts the spec or guesses an open name or seam, and to list each change under "Test
  changes". `split-tests-pair.sh` 1h derives the expected text and compares it byte for
  byte. The gate records that test, and it is green in `self/gate-report.txt`.
- **Author brief:** black-box tests only, no implementation, one commit with the right
  subject staged by path, no push and no PR.
- **Template fill:** the harness's fill covers both halves. `harness_fill_template` is
  unchanged, and pair test 2c shows an unknown `@@NAME@@` in the author half still aborts.
- **`run.sh` behaviour:**
  - Both sessions run from `"$TREE"` with `vanilla-conv`'s flags.
  - The exit codes follow the methods contract.
  - Every refusal the plan lists is there.
  - The test diff is written whatever the implementer's exit code.
  - Side outputs go to `HARNESS_LOG_DIR`, never into the tree.
  - A re-entry skips the author when its commit is already there.
  - There is no `${x//pat/$var}`.
- **Out-of-bounds files:** `harness/run.sh`, `harness/lib.sh`, `hooks/` and
  `harness/check-fixture.sh` are untouched.
- **READMEs:** `harness/methods/README.md` (table row, and ladder text that puts it beside
  the ladder), `harness/README.md`, `vanilla-conv/README.md`, `self/tests/README.md` and the
  new `split-tests/README.md` all match the code.
- **NOTES.md:** its rulings match the diff, and "Left undone: nothing in scope" holds.

## Fixed in this pass

- **Missing test for the "tip is not the tests commit" refusal.** `run.sh:250` refuses an
  author who commits again after `<slug>: acceptance tests`, and no test exercised that
  branch. The existing `subject` case fails one line earlier, at `run.sh:249`, because no
  commit has the subject. I added an `after` author case to the fake `claude` in
  `self/tests/split-tests-pair.sh`, plus assertion 4j2: exit 1, no implementer, and the
  refusal names the later commit. I updated the test's header comment and its
  `self/tests/README.md` entry to match. I ran only that one test to confirm the new case:
  all assertions pass.

## Escalated to the next round

1. **The author brief asks for edits that `run.sh` then refuses, whenever a repo keeps tests
   next to its source.**
   - **The brief:** `harness/methods/split-tests/template.md`, under "## The tests", tells
     the author to follow the repo's test layout and README rules: "a new test file gets its
     line in its folder's README".
   - **The refusal:** `run.sh` counts a path as a test only if it matches `TEST_DIR_RE` or
     `TEST_NAME_RE` (`run.sh:173-174`, checked at `run.sh:264`), and exits 1 on anything
     else.
   - **What breaks:** take a repo that puts `src/components/Foo.test.tsx` beside its source.
     An author that does what its brief says also edits `src/components/README.md`, and the
     cell fails as a work failure with no implementer.
   - **Same failure, other files:** test-support files that live outside a test directory,
     such as a root `conftest.py`, a `playwright.config.*`, or a gate script's test list
     like `self/gate.sh` here.
   - **No test covers this.** `make_repo` only builds a `tests/` layout with its README
     inside it.
   - **The decision needed:** either
     - (a) make `run.sh` accept a `README.md` in a folder where the tests commit adds or
       changes a test file, and decide whether to allow a named list of test-support files;
       or
     - (b) change the author brief so a README or config outside a test directory is left
       for the implementer.

     Both are design choices; neither is a local fix. Whichever is chosen, add a pair-test
     case with tests kept next to the source.

## Noted, not escalated

- **A re-entry skips the author checks.** On a re-entry, `run.sh` re-checks only the
  non-test paths (`run.sh:256-264`), not the tip or the uncommitted-work checks. Suppose the
  author commits its tests, then a source commit, and only then hits a usage limit. The
  re-run would hand that to the implementer without refusing it. Checking the tip is not
  sound at re-entry, because an implementer's own commits may already sit on top. The fix,
  if wanted, is to run the tip and uncommitted-work checks on the author's usage-limit path
  before exiting 2. This is rare, so I am not treating it as a defect.
