Verdict: clean

# Review — vendored-edit-ask

## What the batch was supposed to do

Close finding B1 of humanNetworkMap's audit of agentTooling PR 141. In a consuming repo,
`hooks/allow-repo-commands.sh`'s orchestrator allowlist runs vendored entry points
(`analysis/report.py`, `analysis/manifest.py`, `orchestration-start.sh`,
`orchestration-capture.sh`, and the `plan-runner-*.sh` files they source) with no prompt. But
`wire-settings.py` only asked before an Edit under `agentTooling/hooks/**` and the records
folders, so an Edit to one of those entry points went through without a prompt, and the
planted code then ran without one too.

The owner's rulings:
- Consumer mode writes `Edit(**/agentTooling/**)`.
- The two narrower vendored asks are removed by exact string in the same write.
- `Edit(**/plans/orchestrations/**)` stays.
- `--self` is unchanged.

## Whether it does it

Yes. I checked the diff (`origin/main...HEAD`) against each contract in the brief:

- **`POLICY_ASK_RULES`** is now `Edit(**/agentTooling/**)` and `Edit(**/plans/orchestrations/**)`.
- **`RETIRED_EDIT_ASK_RULES`** holds exactly the two narrow strings.
  - Removal is by list membership, so only exact strings go and a repo's own spelling is left alone.
  - It is consumer-only: `gaps_in` passes `[]` under `--self`.
  - `apply_gaps` removes the retired asks before it appends the missing broad rule, all in the same write.
- **`--check`** reports a retired ask still present as `N retired Edit ask rule(s) (…)`, through the existing `describe_changes` loop. A missing broad rule is reported as a missing ask.
- **Settings already in order are not touched:** a file with the broad rule and no retired rule has no gap and is left as it is (the existing "complete" case).
- **`--self` is unchanged.** `SELF_POLICY_ASK_RULES` was not touched, and the gate's byte-for-byte `--self --check` of `.claude/settings.json` is green.
- **The reason for the tree-wide rule is documented** in the module docstring, the `POLICY_ASK_RULES` comment and `hooks/README.md`.
- **`self/tests/hook-wiring.sh`** adds two cases:
  - `retired-ask`: narrow asks plus the repo's own ask plus the records ask. The write drops the two narrow ones, keeps the others in order and appends the broad rule.
  - `retired-ask-with-broad`: the write removes only the retired ones.

  It also asserts that no case is left with a retired ask, that the generated consumer file equals `ASK`, and that `--self` carries none of the vendored spellings.
- **Docs agree with the code:** `hooks/README.md` (the rules block, the retired-rules prose, the records section), the root `README.md`, `self/README.md` and `self/tests/README.md` all describe the broad rule. `self/tests/security-audit.sh` does not list these rules. The remaining hits for `agentTooling/hooks/**` are in feature records and a dated design doc, which are history and stay as they are.
- **No consumer-side step uses Edit/Write under `agentTooling/`:** nothing in `templates/`, `LIFECYCLE.md`, `AGENT_PLANS.md` or `ORCHESTRATION.md` tells anyone to Edit or Write there.

**Gate:** all checks passed. The one non-zero exit, "pricing rate history is current" (exit 1), only means the rate table is out of date. It has nothing to do with this diff, and the gate's verdict counts it as passing.

## Fixed in this pass

None.

## Escalated to the next round

None.
