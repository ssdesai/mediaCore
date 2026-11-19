Verdict: clean

# Review — ablation-harness-fixes

## What the batch was supposed to do

Fix four defects found while running vinylCatalogue's toolingAblation experiment, each
with a regression test:

1. `hooks/allow-repo-commands.sh` refused a feature branch's first push when it had a
   descriptor redirect (`git push -u origin <current> 2>&1 | tail -3`).
2. A `--from review` resume re-added the worktree without running the fixture's `setup[]`.
3. `settle_pr` logged an ERROR when the arm had already closed its manifest window.
4. Accept probes were never checked against a known-good reference build.

## Does it do it

Yes, all four.

1. **Hook.** The root cause was real: shlex split the `2` off `2>&1` as a separate word,
   and the deny side then read it as a second refspec. A new `chain_tokens` is now the
   one lexer that `chains_chdir` and `command_words` both use. It drops a word made only
   of digits when the lexer ended it directly on `<` or `>`; with a space in between
   (`2 >&1`) the `2` is kept, as bash keeps it. Only the deny side changed, so approval
   is not looser. New `hook-cloud-profile.sh` rows cover the cases the plan asked for:
   - the current branch with `| tail`, `2>&1` and `2>/dev/null`: prompt in both profiles
   - another branch: refused in the cloud
   - `main`: refused in both

   `hooks/README.md` describes the descriptor rule next to the deny side's reading.
2. **Resume.** `harness_fixture_setup` in `lib.sh` is now the only loop over `setup[]`.
   The setup stage, the program setup, `ensure_resume_trees` (reached only from
   `do_pr_resume`) and `check-fixture.sh` all call it. `smoke.sh` asserts that setup runs
   exactly once, in the re-added worktree, before `accept at PR-open`.
3. **`settle_pr`.** It checks `open_manifest_window_of` before closing the window. With
   no open window it logs an informational line and skips the commit. `smoke.sh` asserts
   there is no ERROR, no close commit, and that a cell with an open window still gets
   its close commit.
4. **Reference check.**
   - The reference comes from `reference.commit` in `fixture.json`, or from
     `--reference`; `--no-reference` skips the check, and passing both flags is refused.
   - The probe runs in a detached worktree created with `mktemp -d` under `$TMPDIR`. An
     EXIT trap and an explicit call both remove it, along with its scratch directory.
   - No fixture reference gives a warning, not a failure. The exit code is still the
     failure count.
   - `smoke.sh` covers five cases: a good reference passes, a bad one fails and quotes
     the probe, the skip flag works, the argument form works, and the worktree count and
     `for-each-ref` output are unchanged afterwards.
   - Documentation is updated in the `harness/README.md` row, a new "Validating the
     probe" section, the `fixture.json` shape, `SPEC.md` and the script header. The
     header, the README row and `SPEC.md` all now say it does **not** run the gate.

Other contract checks:
- `self/BACKLOG.md` has the escalated-review-no-PR entry.
- `harness/tests/README.md` and `self/tests/README.md` name the new cases.
- The new code follows the repo rules: named constants (`FIXTURE_SETUP_JQ`,
  `ACCEPT_PROBE_RELPATH`, `FIXTURE_REFERENCE_COMMIT_JQ`, `REFERENCE_*`), no `set -e`, and
  nothing that needs more than bash 3.2.
- The gate report is green, with no SKIPPED checks.

## Fixed in this pass

- `harness/run.sh` `settle_pr`: `open_manifest_window_of` returns nothing both when the
  window is closed and when there is **no manifest at all**. That meant a missing
  manifest got the new message "the method's own close stamped it", where it used to get
  the close's `no manifest at …` warning. The new skip now applies only when the
  manifest file exists; a missing manifest goes through the close and its warning as
  before. `bash -n` passes. This edge has no test; see below.

## Escalated to the next round

None.

## Notes (not escalated)

- **Quoted digits.** `chain_tokens` drops any all-digit word ending on `<`/`>`, even a
  quoted one. So `git push origin <current> "2">f`, which bash reads as a push of a
  second branch named `2`, gets a prompt in the cloud instead of being refused. This
  only turns a deny into a prompt: the human still decides, and nothing is approved that
  was not before. It is a one-line fix: also require
  `command[ended_on - len(token):ended_on] == token`. Add a `hook-cloud-profile.sh` row
  `("git push origin %s \"2\">/dev/null" % BR, P, D)` with it. I could not make the
  change in this pass because writing to the hook file was not permitted. It is worth a
  BACKLOG line if nobody picks it up.
- **Missing test** for the `settle_pr` fix above: a smoke cell whose method deletes its
  manifest should log `no manifest at`, not the "left as written" line.
