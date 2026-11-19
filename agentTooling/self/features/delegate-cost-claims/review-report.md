Verdict: clean

# Review: delegate-cost-claims

## What the batch was supposed to do

1. **Stop a silent $0 close.** `feature-close.sh` now asks `capture_planning.py --claim-check <slug>` before the PR. If nothing would be claimed but something was met in the window, the close refuses, printing each id with its pin command. `--allow-unclaimed "<reason>"` lets the close through and records the reason, which ends up in `planning.json` and the report's warnings.
2. **Auto-claim during capture.** The capture pins an unclaimed delegate whose brief's first line names the feature being captured, using `manifest.py`'s own `pin-subagent` code.
3. **The brief header as a rule.** CONVENTIONS.md → "Delegate briefs" states it, `analysis/README.md` → "The brief header" specifies it, `hooks/brief_header.py` implements it, and the hook denies a headerless `Agent` brief.
4. **A record repair.** `ablation-harness-fixes` pins `a93805d6e49ede750`, and its re-captured record carries the build.

## Does it do it

Yes. I read the diff against `origin/main` and checked it against each contract in the brief:

- **`--claim-check` writes nothing.**
  - It calls `capture_feature(..., recapture=True, dry_run=True, ignore_to=True)`.
  - `recapture=True` skips the frozen-record path, which is the only write branch that comes before the walk (`annotate_frozen_record`).
  - `auto_claim_briefed` only prints when `dry_run` is set.
  - The dry-run return (`capture_planning.py:4511`) comes before every write: the refusals, `planning.json`, and `record_claims`/`save_ledger`.
  - No other `return` or write sits between the auto-claim and that point.
- **The dry run selects what the real capture selects.** It is the same function with an early return. A delegate the auto-claim would pin is added to `pinned_agent_ids` in both modes. The one deliberate difference is the window's `to`: the dry run ignores it, and the real on-branch capture re-stamps it from evidence first. That is a recorded ruling in `NOTES.md`.
- **The close's ordering.**
  - The claim check is the last refusal before `## 2. The PR`.
  - `--allow-unclaimed` writes the manifest only after the check returned 5. The `S: PR` commit's `add -A` commits that write.
  - On a capture refusal, `feature-capture.sh`'s snapshot rollback also removes an auto-claim pin, so a refused capture leaves no dirty pin.
  - Any exit code other than 0 or 5 fails closed.
  - The bash is 3.2-safe.
- **Hook.**
  - The orchestrator's deny still runs first and is unchanged.
  - The header deny is guarded by `brief_header is not None`.
  - On `Agent` the hook never prints an allow and does not import `analysis/`.
  - `hook-brief-header.sh` G1–G6 cover these cases, including the case where the module is absent.
- **One header definition.** `brief_feature_of`, the listing column, the auto-claim, the claim check and the hook all go through `brief_header.parse`, `feature_of` and `feature_lines`.
- **README field lists.**
  - `allow_unclaimed` is in the manifest fence, in `planning.json` and in `FENCE_KEY_ORDER`.
  - `hooks/README.md` lists `brief_header.py`.
  - Both new tests are in `self/gate.sh` and on its `bash -n` list.
  - The README-index check passes in the gate.
- **Record repair.** The fence pins `a93805d6e49ede750`, and `planning.json` prices it, total $10.15.
- **Gate.** `self/gate-report.txt` has no failing or SKIPPED checks. The only "FAIL" strings in it are expected-failure test labels.

## Fixed in this pass

- `self/features/delegate-cost-claims/NOTES.md`: the ruling said the auto-claim runs `manifest.py pin-subagent` "as a subprocess" and that `capture_planning.py` "does not import the fence's writer". The code imports `manifest` inside `auto_claim_briefed` and calls `cmd_pin_subagent` in-process, which is what `analysis/README.md` documents. I rewrote the ruling to match the code.
- `LIFECYCLE.md` step 6 and the comment above the claim check in `feature-close.sh`: both said the check lists delegates "briefed for this feature or for none". The code (`claim_check`) lists delegates whose brief names this feature or **carries no header**, and skips a `feature: none — …` brief. `analysis/README.md` already says this correctly. I reworded both to match.

## Escalated

None.

## Not escalated: a test worth adding later

The dry-run/real parity holds by construction today: it is one function with an early return. Nothing asserts it, though, so a later edit to `capture_feature` that runs a selection step only when `dry_run` is unset would go unnoticed. The assertion that would catch it, in `self/tests/delegate-cost-claims.sh`:

- run `--claim-check <slug>` on a fixture that has a claimed session plus an auto-claimable delegate;
- then run the real capture;
- assert that the ids the check reports as claimed (sessions and subagents) equal `planning.json`'s `sessions[].session_id` and `subagents[].agent_id`.

For this the check should print its ids, not only the counts.
