# split-tests-method — notes

Built by hand by the coordinator, in a separate clone
(`/home/user/agentTooling-split-tests-method`). Another feature (`ablation-harness-fixes`)
held the container's own checkout at the time. Started off `main` at 2f6d4ee. That feature
merged as #132 (2e558c2) mid-build, and it came in through a merge commit, not a rebase:
the policy denies `rebase`, and nothing here had been pushed. The merge had no conflicts and
changed nothing this feature depends on.

## Rulings

1. **Two briefs, one `template.md`.** The harness fills `methods/<m>/template.md` and hands
   the method only the filled file. It exports just `HARNESS_METHOD_RESULT`,
   `HARNESS_LOG_DIR` and `HARNESS_BRANCH_NAME` to the method's process, and
   `harness_fill_template` reads `${HARNESS_<NAME>-}`, so a second template filled inside
   `run.sh` would get an empty facts, spec and isolation and pass the unfilled-placeholder
   check anyway. So the author brief, a marker line, and the implementer brief share one
   file. The harness's one fill covers both. `run.sh` splits at the marker, refuses a brief
   where it is not exactly once, and refuses any leftover `@@NAME@@` again.
2. **The sha slot is `%%TESTS_SHA%%`, deliberately not `@@`-shaped.** The harness would
   abort on an `@@` name it does not fill. `run.sh` refuses an implementer half without the
   slot and fills it with `harness_replace_literal`, never `${x//pat/$v}`.
3. **The added paragraph sits right before `## Finish`.** It also asks for "none" under
   "Test changes" when nothing changed, so an empty section reads as a claim, not an
   omission. The pair test derives the paragraph from its position, then demands the rest be
   `vanilla-conv`'s template byte for byte.
4. **What a test file is**: a path through `test/`, `tests/`, `__tests__/` or `e2e/`, or a
   name shaped `test_*`, `conftest.py` (round 2), `*_test.*`, `*.test.*`, `*.spec.*`,
   `*Test(s).*`. `spec/` is left
   out on purpose: consuming repos keep their spec there.
5. **Author refusals (exit 1, no implementer):** nothing committed; any non-test path in
   `<start>..<tests sha>`; a tip that is not the `<slug>: acceptance tests` commit; newly
   dirty paths outside `plans/features/<slug>/`, where the harness's untracked manifest and
   `BRIEF.md` live. The brief tells the author to stage by path because of those files.
6. **Re-entry.** The HEAD the author started from is kept in
   `<logs>/<branch>-author-start` (discarded when it is no longer an ancestor of HEAD, as
   after a cell reset). A re-run after a usage-limit stop that finds the subject in
   `<start>..HEAD` runs the implementer alone. On the author's usage-limit stop, its result
   is copied to `HARNESS_METHOD_RESULT`, where `do_method` reads the reset time.
7. **Side outputs live in the log directory, never in the tree** (the `plans` method's
   lesson: a dirty path stops `feature-close.sh`). `<branch>-test-diff.txt` is written
   whatever the implementer's exit; empty means untouched.
8. **No smoke-test cell.** `harness/tests/smoke.sh` drives whole cells of `null` and
   `direct`, not each method. The stub-`claude` coverage for this method is section 4 of
   `self/tests/split-tests-pair.sh`. `arm-spec.sh`'s arm-mode list gains the template.

## Round 2 (the review's escalation)

9. **Tests kept next to their source.** Round 1's brief asked the author to add a test
   file's line to its folder's README, and `run.sh` then refused that README whenever the
   folder was not a test directory (`src/components/Foo.test.tsx`). The ruling is the
   narrow form of the review's option (a): a `README.md` passes only in a folder where the
   same range adds or changes a test file (`TEST_README_NAME`). `conftest.py` joins
   `TEST_NAME_RE` as pure test support. The brief now names the boundary: anything else a
   test needs outside those files (a gate's test list, a runner config) is left for the
   implementer and named in the author's report. A named list of other support files was
   not added, because it would be a per-repo guess.
10. **The re-entry gap the review noted** is closed where it can be told apart. On the
   author's usage-limit stop, a tests commit that is not the tip is refused (exit 1) before
   the exit 2, so the re-entry, which trusts the commit it finds, never inherits the
   author's own later commits.
11. Pair-test cases `colocated`, `conftest` (pass), `strayreadme` and `limitafter` (refused)
   hold both rulings.

## Round 3 (the round-2 review's escalation)

12. **Uncommitted work at the author's usage-limit stop.** Round 2 checked only the commits
    there. An author that commits its tests, writes `src/feature.py` without committing it,
    then hits the limit would hand the implementer a tree holding its source, by way of
    the re-entry. Ruling: once the tests commit exists, the usage-limit branch runs the same
    uncommitted-work refusal as a clean exit (`refuse_author_leftovers`, one copy for both)
    and exits 1 naming the paths. With no tests commit yet, a stop is left to the re-run
    author, whose own `dirty_before` then includes its earlier partial files, and the
    post-run checks still apply to it. Pair-test case `limitdirty`.

## Left undone

Nothing in scope.
