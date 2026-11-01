Verdict: escalated

# Review: harness-cloud-pins

## What the batch was supposed to do

Per the manifest's opening paragraph: fixtures name their repositories by URL
(`repo.url`, `spec.url`), and `harness_resolve_repo` turns each URL into a checkout on
whatever machine runs it (env override → local checkout → path hint → origin-identity
search of the roots → clone, with a cloud `add_repo` remedy). Forge calls go through the
vendored `forge.sh` (`pr-find` / `pr-open`), and `HARNESS_FORGE_BIN` replaces
`HARNESS_GH_BIN`, including in the `direct` brief. Experiment **arms**
(`agent_tooling: {<label>: <sha>}`, written by `new-experiment.sh --agent-tooling`) are a
third cell axis. Each arm gets a pin commit, a `<stem><Method><Arm><n>` branch, `arm` /
`agent_tooling` in its ledger row, and arm-vs-arm scorecard comparisons. Two other
changes ride along: the smoke test's `mktemp -t` no longer writes at `/` on Linux, and a
merged manifest on `origin/main` is no longer treated as a second feature on a reused
cloud branch.

## Does it do it

Yes. Every behaviour the paragraph names is in the diff:

- `harness/lib.sh`: the resolver, the forge seam and `harness_pin_agent_tooling`.
- `run.sh`, `new-experiment.sh`, `new-fixture.sh`, `check-fixture.sh` and `publish.sh`
  are wired to them.
- `scorecard.py` has the arm column and the arm-pair comparisons.
- The `direct` template opens its PR with `forge.sh pr-open`.
- `plan-runner-roots.sh`'s `started_features_on` and `feature-start.sh` skip merged
  manifests.
- `self/tests/cloud-start.sh` S2 and the smoke test's sections 5 and 6 cover these.

None of the "Deliberately excluded" items appear: no consumer fixture edits, no A/B run,
`harness_version` unchanged, and the hook's `attachable_branch` untouched. The gate report
is green with nothing SKIPPED. NOTES.md's claims match the diff.

**One amended invariant to note.** `LIFECYCLE.md` step 1 and `self/PROJECT_FACTS.md` now
carry a new owner's rule (2026-10-30) on who builds and how a feature's method is chosen.
The manifest's paragraph doesn't mention it; NOTES.md records it as the owner's ruling.
This is a policy decision, not code, and it is recorded openly, so I'm not escalating it.
I'm naming it so the approver sees it is part of this PR.

## Fixed in this pass

1. **A re-run after a failed pin ran unpinned but was recorded as pinned**
   (`harness/run.sh`, `do_setup`).
   - **What was wrong:** the pin ran only when this run had just created the worktree. If
     the pin died after `worktree add` (an agentTooling clone the cloud proxy refuses, a
     commit missing even after fetch, a failed commit), the tree stayed behind. That
     failure is exactly the one `harness_clone_remedy` tells the user to fix and re-run.
     On the re-run the tree already existed, so the pin was skipped, yet
     `agent_tooling = ARM_SHA` was still written to state and to the ledger row. The arm
     then measured the base's own vendored copy under the pinned version's name, with
     every check green.
   - **The fix:** the pin is now skipped only when `BASE..HEAD` already holds the commit
     `EXPERIMENT ARM (revert before merge): pin agentTooling to upstream <sha7>`.
     Re-pinning a half-done pin is safe: it does `rm -rf agentTooling/`, extracts again,
     then commits.
   - **Docs updated to match:** `harness/README.md` → "Arms" and `harness/SPEC.md` §12.
2. **A malformed `agent_tooling` silently ran every cell unpinned**
   (`harness/lib.sh`, `harness_experiment_arms`).
   - **What was wrong:** `jq … 2>/dev/null` turned a jq error (for example
     `"agent_tooling": "abc123"`) into empty output. That read as the no-pin `- -` line.
   - **The fix:** a jq failure now dies with the expected shape, and `run.sh` exits on it
     (`ARMS=… || exit 1`).
3. **SPEC.md still named the old path field** (§3 stage 1 and §4 "Worktree").
   - **What was wrong:** both still said `<fixture.repo.path>`.
   - **The fix:** both now say the checkout that `repo.url` resolves to.

All three edited scripts pass `bash -n`. The gate was not re-run (see below).

## Escalated to the next round

1. **No test covers resuming after a failed pin** (`harness/tests/smoke.sh`, section 6).
   The fix in item 1 above has no assertion.
   - **What to add:** a cell whose first run dies inside the pin after `worktree add`, for
     example with `HARNESS_AGENT_TOOLING_URL` set to a directory that is not a checkout
     and has no clone root.
   - **Then:** re-run it with the real URL.
   - **Assert:** the pin commit is on the branch, `agentTooling/` is a real directory, and
     the row's `agent_tooling` is the arm's sha.
   - **Also assert:** a second `--from setup` re-run does not add a second pin commit.
2. **No test covers the scorecard's arm-vs-arm or within-arm method comparisons**
   (`harness/scorecard.py`, `render` / `compare`). The smoke experiment has one arm and
   one method, so neither comparison loop ever produces a line.
   - **What to add:** a `results.jsonl` of four rows: fixture `f`, methods `a` and `b`,
     arms `before` and `after`, each with both `cost_method_usd` and `cost_green_usd`.
   - **Assert:**
     - an `f · a: arm after vs arm before` line exists, and so does a
       `f · arm before: a vs b` line;
     - each line shows both "to PR-open" and "to green";
     - a delta inside the band reads "tie inside the band";
     - an unpinned row (`arm: ""`) is never paired with a pinned one.
   - This can be a small Python or shell test beside the smoke test.
3. **No test covers a malformed `agent_tooling`** (the fix in item 2 above). Add a smoke
   check: an experiment.json with `"agent_tooling": "abc"` makes `run.sh --dry-run` exit
   non-zero and print no `branch:` line.

## Unverified

The gate was not re-run after this pass's edits, which the review brief forbids. Only
`bash -n` was run on the edited scripts. The smoke test's existing pinned-run checks
exercise the changed `do_setup` condition on a fresh tree, where `BASE..HEAD` is empty, so
the pin still runs. The next round's gate run confirms that.
