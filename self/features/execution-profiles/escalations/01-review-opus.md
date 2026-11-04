Verdict: escalated

# Review: execution-profiles (round 1)

## What the batch was supposed to do

This is the last feature of the cloud-execution design (`self/DESIGN-2026-10-05-cloud-execution.md`). The rule it delivers is that **the lifecycle never asks where it is running**:

- **Detector (§1).** `env-profile.sh` decides `local` or `cloud` and holds the checkout-layout adapter. A gate check confines the two profile variables to the detector, the adapters and their tests.
- **Cloud start layout (§2).** In the cloud the container is the worktree. The start refuses on the base branch without `--branch`, on foreign commits, on a dirty tree and on a second feature, and a refused start can be resumed.
- **Router derived (§3).** Whether the session gets a routing record follows from the branch it was launched on, and the start-instant fix means a coordinator needs no `set-window-from`.
- **Forge (§5).** `forge.sh auto-merge` and `forge.sh reachable` differ by profile, and `pr.sh` v6 sends its merge request through `forge.sh`.
- **Environment adapters (§7).** `environment.sh` and `cloud-setup.sh` are seeded, and a `SessionStart` hook is wired for `cloud-setup.sh`.
- **`profile` and `gate` fence keys**, and `--check` reporting the two new files when they are missing.
- **Resumable gate (§8)**, plus the long-run doctrine.
- **`sleep` rewrite reason (§9)** in the permission hook.

## Does it do it

Mostly yes, and carefully. Base `cf74b35`, diff `cf74b35...HEAD` (60 files).

**The detector and confinement are correct.**
- The detector is three-case and exported. A bogus explicit value is refused rather than treated as `local`.
- Confinement checks tracked files only, matches whole words, exempts prose, and has an explicit allowlist.
- It is shown to fail on a planted read of either variable (env-profile C2a/C2b).

**The cloud start keeps the local path intact.**
- Every local branch is gated on `! profile_is_cloud`, and the local start lock is byte-identical to before.
- Changes to existing assertions are limited to:
  - forcing `AGENTTOOLING_PROFILE=local` in fixtures;
  - the version pins that moved because their bodies changed;
  - the `gh pr merge` stub resolving a url.
- All of these are justified in `NOTES.md` → "Existing assertions changed".
- Every refusal, the resume path and the routing-record rule have black-box assertions in `self/tests/cloud-start.sh`. That includes the hand fix surviving outside the start commit (R3d) and the coordinator being selected by its branch with no `set-window-from` (A3b).

**The rest matches the brief.**
- `forge.sh auto-merge` and `reachable` match §5, with no squash and no `gh pr` or `auth status` under cloud.
- `pr.sh` is v6 in both copies, the hash is re-recorded, and the hand-merge note is in `README.md` → "Adopting the forge adapter".
- Template versions are bumped and re-hashed for gate 3, worktree-setup 2 and open-session 4, and the two new templates start at 1.
- The `SessionStart` merge is additive and guarded by the script itself.
- The `sleep` rewrite only tightens: `sleep` was never approved before.
- READMEs, `LIFECYCLE.md`, the doctrine docs and design §10 are updated.
- **No sibling feature directory changed.**

The cost consequence of the start-instant fix is recorded in NOTES ruling 18: the coordinator's spend before the start is billed to the feature.

**Gate:** `self/gate-report.txt` (level final) reads `# VERDICT` / `all checks passed`, with no SKIPPED checks. I did not re-run it, as this pass's instructions say. Since that report, the working tree has changed only by the harness's `timing.jsonl` append and this plan's queue move.

## Fixed in this pass

Nothing. I found no local drift worth an edit.

## Escalated to round 2

### 1. The resumable gate never resumes when a runner runs it

The runners and the start were supposed to get resume (design §8, plan item 11). Only the start actually does.

**The mechanism.**
- `gate_tree_sha` (`templates/plans/gate.sh`, `self/gate.sh`) hashes the whole checkout, untracked non-ignored files included. Only the gate's own outputs are left out (`GATE_TREE_EXCLUDES = gate-report*.txt, gate-state`).
- Every runner gate call is immediately preceded by `stamp_timing gate_start …`:
  - `plan-runner-lib.sh` `run_level_gate`;
  - `run-batch.sh`'s final gate;
  - `run-batch.sh`'s `regate`.
- `stamp_timing` appends a line to `<features>/<slug>/timing.jsonl` inside the same checkout. That file is tracked (for example `self/features/cloud-close/timing.jsonl`), and neither `.gitignore` covers it.
- The runners also move queued plans between `incomplete/`, `inprogress/` and `complete/`, and write `*.progress.md` and `*.usage.json`. None of those paths are ignored either.

**The consequence.**
- Every gate a runner starts sees a tree sha that differs from the one before it.
- So a gate killed with its container and re-run by `run-batch.sh` or `run-plans.sh` re-runs every check, and `gate_state_init` deletes the previous tree's records.
- The ~13-minute self-gate case that motivated §8 is exactly this case.
- Only `feature-start.sh`'s base gate (no stamp between runs) and a gate run by hand actually resume.

**Why the tests stay green.** `self/tests/gate-resume.sh` K1–K10 drive the gate scripts directly and never through a runner, and nothing asserts the runner-level promise.

**What it should be (a design decision, so not fixed here).** Decide which paths count as gate inputs. Either:
- (a) leave the feature corpus's run records out of the tree sha: `timing.jsonl`, the plan queues, `*.progress.md`, `*.usage.json`, `*.stream.jsonl`; or
- (b) take the sha from tracked content plus untracked files outside `<features>/`.

Then record the ruling in NOTES and design §8/§10. Note one interaction: a gate that itself validates the feature corpus would then resume across corpus edits.

**The assertion that would catch it** (new, in `self/tests/gate-resume.sh`):
1. Run the template gate through `run_level_gate` (or `run-batch.sh`'s final-gate path), with `stamp_timing` live and a feature directory present.
2. Kill it during check 3.
3. Re-run through the same runner entry point.
4. Assert that only c3 and c4 run.

On today's code this fails with `c1 c2 c3 c4`.

### Noted, not escalated

`forge.sh auto-merge`'s cloud body field (`merge_method=merge` on `ccr/auto_merge`) has not been checked against the live route. This is already recorded: NOTES ruling 19 and `self/BACKLOG.md`. The call is advisory, so a refusal warns and leaves the PR open for a human.

## Files this pass touched

- `self/review-report.md` (this file)
