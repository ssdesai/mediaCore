Verdict: escalated

# Review: split-tests-method, round 2

## What the batch was supposed to do

Add `harness/methods/split-tests/`, a method that sits beside `vanilla-conv` and is not a rung of the ladder. It runs two fresh sessions through `harness_claude` with `vanilla-conv`'s flags:

1. A **test author** commits black-box acceptance tests alone, as `<slug>: acceptance tests`.
2. An **implementer** gets `vanilla-conv`'s brief byte for byte plus one paragraph that points it at that commit.

Both briefs live in one `template.md`, split at a marker line. `run.sh` refuses (exit 1, no implementer) an author who:
- commits nothing;
- commits a file that is neither a test nor the `README.md` of a folder holding one of its tests;
- commits after its tests commit, which is also checked when the author stops on a usage limit;
- leaves other work uncommitted.

`run.sh` writes the implementer's test diff to `<experiment>/logs/<branch>-test-diff.txt`.

Round 2 had two jobs:
- Make the author brief and `run.sh` agree on the folder README when tests sit beside their source.
- Close the re-entry gap after the author stops on a usage limit.

## Does it do it

Yes, with one remaining gap in how a resumed run (a re-entry) treats the author's work after a usage-limit stop. I checked the whole diff against `origin/main`, and round 2's own change (`aa3200c..HEAD`), against the spec. I did not rely on the builder's account.

- **Implementer half.** `split-tests-pair.sh` 1h compares it byte for byte: it is `vanilla-conv/template.md` plus one paragraph before `## Finish`. The paragraph names `%%TESTS_SHA%%` and `@@SLUG@@: acceptance tests`. It says to make the tests pass and not to delete or weaken them. It allows changing a test only where it contradicts the spec or guesses an open name or seam, and asks for each change under "Test changes".
- **Template fill.** Both halves go through the harness's own fill. Test 2c shows that an unfilled `@@NAME@@` in the author half still aborts the fill.
- **Author brief.** It asks for black-box tests only, no implementation, one commit with the right subject staged by path, and no push or PR.
- **The brief and `run.sh` now agree on what the author may commit.**
  - The brief allows test files plus "the `README.md` of a folder you add a test file to", and leaves a gate's test list or a runner config for the implementer.
  - `run.sh:273-295` accepts exactly that: a non-test path passes only if it is named `TEST_README_NAME` and its folder is the folder of a test path in the same range.
  - `conftest.py` is in `TEST_NAME_RE`.
  - Pair-test cases `colocated` and `conftest` pass. `strayreadme` is refused, and the refusal names `src/components/README.md`.
- **Re-entry after the author's usage limit.** `run.sh:254-257` refuses (exit 1) a tests commit that is not HEAD, and does so before the exit 2. The `limitafter` case covers it (4h, 4i3).
- **Contract.** Both sessions launch from `"$TREE"` with `vanilla-conv`'s flags (3c, 3d). Exit codes are 0, 2 or 1. The test diff is written whatever the implementer's exit (4m), and nothing lands in the tree (4g). There is no `${x//pat/$var}`: the slot is filled through `harness_replace_literal`.
- **Gate.** `self/gate.sh` records `split-tests-pair.sh`. `self/gate-report.txt` shows "all checks passed", and the split-tests pair self-test is green. I did not re-run it.
- **Out-of-bounds files.** `harness/run.sh`, `harness/lib.sh`, `hooks/` and `harness/check-fixture.sh` show no diff against `origin/main`.
- **READMEs.** `split-tests/README.md`, `self/tests/README.md`, `harness/README.md`, `vanilla-conv/README.md` and the feature manifest describe the round-2 behaviour. One stale line in `harness/methods/README.md` is fixed below.
- **NOTES.md.** Rulings 9–11 match the code and the tests.

## Fixed in this pass

- **`harness/methods/README.md`, the `split-tests/` table row.** It still said "Exit 1 if the author commits nothing or anything but tests", which is round 1's rule. Since round 2, `run.sh` also accepts the `README.md` of a folder holding one of the author's tests. The row now says so.

## Escalated to the next round

1. **Uncommitted work left at the author's usage-limit stop reaches the implementer.**
   - **Where:** `harness/methods/split-tests/run.sh:250-260` together with the re-entry at `:240-242`.
   - **What happens:** the uncommitted-work refusal (`:269-270`) runs only when the author exits 0. Suppose the author makes the tests commit, then writes a source file, say `src/feature.py`, without committing it, and then hits a usage limit. Three things follow:
     - The `limitafter` guard passes, because the tests commit is still HEAD.
     - `run.sh` exits 2.
     - The harness's re-entry finds the tests commit and goes straight to the implementer (`:241-242`). It never compares the tree against `dirty_before`, which no longer exists by then.

     The implementer starts in a tree that holds the author's implementation, which is the contamination the method exists to prevent. Nothing tells it apart afterwards, and every check stays green.
   - **Why it is not fixed here:** the spec promises the limit-stop check only for commits ("commits after its tests commit, which is checked on its usage-limit stop too"). Extending it to uncommitted work is a decision about what a mid-work stop may leave behind, so it is for the next round to make.
   - **Suggested fix:** in the usage-limit branch, run the same `comm -13` comparison against `dirty_before` when `limit_sha` is non-empty and equals HEAD (`:269`), and fail naming the paths.
   - **Missing test:** a `limitdirty` author case in `self/tests/split-tests-pair.sh` that makes the tests commit, leaves `src/feature.py` uncommitted and prints the usage-limit result. It should expect exit 1, one session, and the refusal naming `src/feature.py`. Add it beside `limitafter` in the 4h loop, and update the `self/tests/README.md` entry and the method README's exit-1 list to match.
