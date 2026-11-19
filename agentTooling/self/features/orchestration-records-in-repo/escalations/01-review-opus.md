Verdict: escalated

# Review — orchestration-records-in-repo

## What the batch was supposed to do

Move a consuming repo's orchestration records out of the vendored
`agentTooling/self/orchestrations/` and into the consumer's own `plans/orchestrations/`, with
`--self` keeping agentTooling's own records at `self/orchestrations/`. That means:
`roots.orchestrations_root(self_mode)`; `--self` on the start and capture scripts,
`orchestration_capture.py`, `manifest.py --orchestration` and `report.py --orchestration`;
group-report `report` paths resolved against the record's own repo root; the role hook and the
coordinator advisory reading both roots; a `git mv` refusal for a record left at the old place;
the harness falling back to the old path; and the docs updated to match.

## Does it do it

Mostly, yes. The diff matches the rulings item by item:

- `roots.py` is the one definition. The hook's constants and `orchestration-start.sh`'s mirror it, and U3 in `self/tests/orchestrator-role.sh` checks the hook against both roots. The consumer path in `orchestration-start.sh` is checked by what it does: R1 in the new test confirms the start writes to `plans/orchestrations/`.
- `report.py` resolves `report` paths with `artifact_root(self_mode)` and works out the home repo from `corpus_identity`. A consumer feature is priced with no `--checkout` (R2). Under `--self` the home repo is still `agentTooling`, so existing records price as before.
- The record fence shape and the `report.json` fields are unchanged.
- The harness reads the record from the new path and falls back to the old one. The smoke test now expects the pushed record at `plans/orchestrations/`.
- The new test file has its row in `self/tests/README.md` and is recorded by `self/gate.sh`. The README index check is green.
- The gate report is fully green. Nothing was SKIPPED.

There are two defects the gate cannot see. Both sit in the new default (no `--self`) path, and both need a design decision, so both are escalated below.

## Fixed in this pass

None.

## Escalated to the next round

1. **The legacy-record check confuses agentTooling's own shipped records with a consumer's
   stranded ones.** Files: `analysis/roots.py` `legacy_record_refusal` (~line 344) and
   `orchestration-start.sh` (~line 625).
   - `git subtree` vendors all of `self/`, so every consumer's `agentTooling/self/orchestrations/` already holds agentTooling's own records: `readme-structure`, `agenttooling-roles`, `rehearsal-prep`, `ablation-wave` and `program-ab`.
   - The check flags any slug that is absent from `plans/orchestrations/` but present in the vendored folder. So if a consumer starts an orchestration called `program-ab` or `rehearsal-prep`, it is refused and told "the record is at the old place … move it: `git mv agentTooling/self/orchestrations/program-ab plans/orchestrations/program-ab`".
   - That `git mv` would move agentTooling's own record out of the subtree. That is exactly the kind of local edit to shipped code this feature exists to prevent. `report.py`, `manifest.py` and `orchestration-capture.sh` give the same wrong advice for such a slug.
   - The fix is a design decision: how to tell "a consumer's stranded record" from "agentTooling's own record". Options include checking whether the path is in agentTooling's upstream tree, a fence marker, or the record's `agent_tooling` field.
   - Missing test: in a consumer-shaped tree, a slug that matches one of agentTooling's shipped records must not get the `git mv` advice. For the start, a plain name-collision refusal is the most it should get.

2. **Running `orchestration-start.sh <slug>` without `--self` in a standalone agentTooling
   checkout writes outside the repository, silently.** Files: `orchestration-start.sh` (~lines 617–623) and `hooks/orchestrator_role.py` `record_roots`.
   - Without `--self`, `resolve_roots` sets `REPO_DIR` to the checkout's parent directory. A no-flag start in a standalone checkout therefore runs `mkdir -p <parent>/plans/orchestrations/<slug>` and exits 0. In a cloud container that is `/home/user/plans/orchestrations/`, which is in no repository.
   - This is the exact invocation that was correct before this branch, and it is still written in every existing record's opening paragraph under `self/orchestrations/*/README.md`.
   - The hook then also reads `<parent>/plans/orchestrations/`, so that stray record becomes a live orchestrator role for the session. From then on, builds in the agentTooling checkout are refused.
   - The script can already detect this case: it computes `TOPLEVEL` and compares it with `SCRIPT_DIR` (equal means a standalone checkout, not a vendored copy). A refusal saying "this is agentTooling's own checkout: pass `--self`" would close it. Whether to refuse, or to default to `--self` there, is a decision for the next round.
   - Missing test: a no-`--self` start in a standalone checkout is refused (or redirected) and writes nothing outside the checkout.

### Minor, for the same round

- The coordinator advisory in `analysis/coordinator_check.py` (`UNCLAIMED_TEMPLATE`) still prints `orchestration-start.sh <slug> --coordinator --session …` with no `--self`. Once item 2 is settled, the advisory should name the flag when it is printed from a `feature-start.sh --self`.

## Checks

The gate report (`self/gate-report.txt`, level final) is green throughout, with no SKIPPED checks. This pass re-ran nothing.
