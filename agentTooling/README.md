# agentTooling

Shared Claude Code conventions and a delegated-plan execution harness, vendored
into each repo with `git subtree` so fixes are made once and pulled everywhere.

## Contents

| File | What it is |
|---|---|
| `CONVENTIONS.md` | Repo-agnostic working conventions — README traversal, file access, debugging discipline, named constants. Imported by each repo's root `CLAUDE.md`. |
| `AGENT_PLANS.md` | How to author plans for the delegated-execution workflow. Overrides parts of `CONVENTIONS.md` during plan generation (see its "Precedence" section). |
| `RUNNER.md` | How execution works — the queue state machine, resume semantics, progress and event logs, and the build/verify/review/interactive split. Read when authoring plans or debugging a failed run. |
| `ORCHESTRATION.md` | How to run the tier above the runners — a coordinator session automating the human who would run `run-batch.sh`, across repos or across interleaving features in one repo. The architect plans; the coordinator runs. Read before delegating feature work to subagents. |
| `run-plans.sh` | Build runner. Drains `plans/features/<slug>/auto/incomplete/` unattended with **Bash disabled**, so a build plan can only edit files. Takes the slug as its first argument; with none, infers it from the single feature that has queued work and errors if two do. A plan named `NN-gate.md` is a level sentinel: the runner runs `plans/gate.sh NN` in its place and exits 64 (`LEVEL_PAUSE_RC`) instead of continuing when a verify plan numbered ≤ NN is queued and the level's gate is not green; a green gate files the level-verify as skipped and continues. |
| `run-verify.sh` | Verify runner. Drains `plans/features/<slug>/verify/incomplete/` with **Bash enabled**, so a post-build pass can probe what a script can't express — cross-layer invariants, security boundaries, adversarial inputs. Mechanical checks belong to `plans/gate.sh`; world-building belongs in a test; fixes here stay local. Capped per plan: the final verify by `VERIFY_BUDGET_USD` (`$3.00`), a level-verify (`NN-level-*`, or any plan under `--up-to`) by `LEVEL_VERIFY_BUDGET_USD` (`$6.00`), a synthesized `NN-escalation-*` by `ESCALATION_BUDGET_USD` (`$8.00`); exceeding a cap routes the plan to `failed/`. A level-verify's prompt carries the tier-1 rule (fix the tree, never a contract; write `escalations/NN.md` instead); an escalation gets its own preamble and may edit queued plans. `--up-to NN` (after `--self`) drains only verify plans numbered ≤ NN. |
| `run-review.sh` | Review runner. Drains `plans/features/<slug>/review/incomplete/` after verify, reading the **diff** rather than running the work — the defects that stay green: an invariant with no test, a contract broken on one side, a field list that drifted from its shape. Same tool scope and same fix policy as verify (local fixes, structural escalations). The executor writes its verdict to `plans/review-report.md`; on a clean pass the runner then calls the repo-owned `plans/pr.sh`, which opens a PR with that verdict as its body. Defaults to `opus`; capped by `--max-budget-usd` (default `$7.00`, override `REVIEW_BUDGET_USD`). A cap that fires after the report was written still opens the PR, with a banner in the body. Optional per feature — an empty queue is a clean no-op. |
| `run-batch.sh` | Runs the build pass, then, for each level boundary that paused it, climbs the red-gate tier ladder (level-verify → re-gate → synthesized opus escalation → re-gate → stop; `RUNNER.md` → "Red gates") and resumes the build; then the final gate, verify and review passes, each gated on the one before it. A re-run with an explicit slug settles an unsettled level before building on it. |
| `run-escalation-plan.sh` | Writes the tier-2 `NN-escalation-opus.md` brief into a feature's `verify/incomplete/` (from `write_escalation_plan` in the lib) and refuses to write a second one for the same level. Called by `run-batch.sh`; by hand, how to re-arm tier 2 after editing `escalations/NN.md`. |
| `EXPERIMENTS.md` | How to A/B a doctrine or runner change against the version before it — arms as pinned worktrees, a checklist written first, a behaviour score script through real routes, `report.py` for cost, and what counts as noise. `templates/experiment/CHECKLIST.md` is the skeleton. |
| `harness/` | The experiment harness that runs one: it builds a frozen fixture several ways, reviews and reworks every tree from the same brief, scores each run and appends it to a ledger. `harness/run.sh <experiment-dir>` from the consuming repo root, `--dry-run` first; `new-fixture.sh` / `check-fixture.sh` / `new-experiment.sh` / `publish.sh` scaffold, validate, and publish around it. Isolation between arms is structural rather than a rule — no stage reads across worktrees, and the review brief exists before any method runs. Fixtures and experiments live in the consuming repo under `plans/experiments/`, since they pin other repos' commits. See `harness/README.md`; `harness/SPEC.md` is the design record. |
| `plan-runner-lib.sh` | The queue/resume/logging/routing machinery all three runners source. Single source of truth for the subtle parts — the FIFO-PID wait race, usage-limit detection, stream finalization, and the per-attempt accumulation that keeps a resumed plan's earlier runs from being re-billed as planning cost. Not run directly. `QUEUE` is only ever used to build paths, which is why a new queue costs a wrapper script and no change here. Also owns sentinel handling (`is_gate_sentinel`, `level_verify_queued`, `run_level_gate`) and the `PLAN_MAX_NN` bound on `list_plans`. |
| `plan-runner-roots.sh` | Resolves normal vs `--self` roots (`REPO_DIR`, `FEATURES_DIR`, gate script, PR hook, review-report path) for all the runners. Sourced, never run directly. |
| `sync-plans.sh` | Writes the generated `plans/` stubs (`README.md`, `interactive/README.md`, `features/README.md`, `features/TEMPLATE.md`) from `templates/`, and seeds the three repo-owned files (`PROJECT_FACTS.md`, `gate.sh`, `pr.sh`) only when absent. Run at install and after every `subtree pull`. Never overwrites those three. |
| `migrate-plans-layout.sh` | One-time, repo-agnostic migration from the flat `plans/{auto,verify}/{state}/` queue to the per-feature `plans/features/<slug>/{auto,verify}/{state}/` layout (see `RUNNER.md`). `--dry-run` first; otherwise requires a clean working tree, since it uses `git mv` so history follows the moved files. Not part of the ordinary batch flow — run once, by a human. |
| `templates/` | Source for the generated `plans/` stubs, plus the `PROJECT_FACTS.md`, `gate.sh` and `pr.sh` skeletons. Edited here, never in the consuming repo. The last three are seeded once and then repo-owned. |
| `analysis/` | Stdlib-only Python scripts pricing and reporting what a feature cost to plan and build — the rate table, usage-sidecar backfill, planning-session capture, and the cross-feature cost report. See `analysis/README.md`. |
| `self/` | agentTooling's own plan corpus — features, `PROJECT_FACTS.md`, `gate.sh`, `pr.sh`, and the behavioural checks in `self/tests/` — drained by `--self`. See `self/README.md`. |

Requires `claude` and `jq` on `PATH`. The runners check both at startup and exit 127
if either is missing — `jq` in particular would otherwise fail silently, since both of
its call sites suppress stderr, leaving an empty progress log and no terminal output
while plans still got filed as complete.

## Installing into a repo

**Mount at `agentTooling/`, exactly one level below the repo root.** The runners derive
`REPO_DIR` as `$SCRIPT_DIR/..` and the plan queue as
`$REPO_DIR/plans/features/<slug>/{auto,verify,review}`. Mounting deeper
(`tooling/agentTooling/`) silently resolves `REPO_DIR` to the wrong directory — `claude`
then runs from a subdirectory and the queue is never found. The scripts under
`analysis/` inherit the same constraint one level deeper (`parents[2]` from the script
file); see `analysis/README.md` → Where to run them.

```bash
git subtree add --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

Then, in the consuming repo:

**1. Import the conventions from the root `CLAUDE.md`.** Keep that file thin — the
import plus whatever is genuinely project-specific:

```markdown
@agentTooling/CONVENTIONS.md

## Project-specific examples

[real field lists and file paths for README Rules 1 and 2, build/test commands]
```

Relative imports resolve against the file containing them, so `@agentTooling/CONVENTIONS.md`
is correct from a root `CLAUDE.md`. Paths in backticks are not imported, so
`` `@agentTooling/CONVENTIONS.md` `` stays literal text when you want to mention it.

**2. Add the runner's scratch output to `.gitignore`:**

```gitignore
# run-plans.sh / run-verify.sh / run-review.sh raw event streams — kept next to a failed
# plan for debugging, and next to a completed one as the full record of what the model did.
plans/**/*.stream.jsonl
plans/**/*.logfifo
```

**3. Create `plans/`:**

```bash
./agentTooling/sync-plans.sh
```

That creates `features/`, `interactive/`, writes their README/template stubs, and
seeds `plans/PROJECT_FACTS.md`, `plans/gate.sh` and `plans/pr.sh` from the skeletons.
The last opens the PR after a clean review pass — check its `BASE_BRANCH` and forge CLI
(`gh` by default) before relying on it; it is repo-owned precisely so a non-GitHub repo
can swap that out. A feature's own queue state
directories (`incomplete/`, `inprogress/`, `complete/`, `failed/`, under
`features/<slug>/auto/`, `.../verify/` and `.../review/`) are not created here — git
doesn't track empty directories, and the runners make them on first use.

Sync rather than a one-time copy because the stubs are pointers *into this directory*.
Rename the subtree prefix or restructure the queue, and every hand-copied stub in every
repo silently goes stale. Re-running the script is the fix; it overwrites the four
generated stubs unconditionally, which is safe because none of them contain
repo-specific content.

**4. Fill in `plans/PROJECT_FACTS.md`.** It ships as a list of prompts. It holds the
repo-specific facts that plans must pin — where generated types live, API route
templates, the test command, naming gotchas — so a plan author copies from one place
instead of rediscovering them per batch. This is `AGENT_PLANS.md` → "Pin the facts
executors would otherwise hunt for" applied to the repo as a whole. The README stubs
need no editing; they point at `RUNNER.md` for the execution model, which is why that
model is documented once rather than restated per repo.

You're ready: author plans per `AGENT_PLANS.md` into
`plans/features/<slug>/auto/incomplete/`, then run the batch.

## What stays in the consuming repo

Everything under `plans/` — `features/`, `interactive/`, the plan corpus and
its execution history, `PROJECT_FACTS.md`, and `plans/README.md`. Only the shared
machinery and doctrine live here. There are two separate corpora: everything under the
consuming repo's `plans/` is that repo's own, and everything under `agentTooling/self/`
is the harness's own and ships with the subtree.

## Running

From the consuming repo's root:

```bash
./agentTooling/run-batch.sh      # build pass, then verify pass, then review pass
./agentTooling/run-plans.sh      # build pass only
./agentTooling/run-verify.sh     # verify pass only
./agentTooling/run-review.sh     # review pass only
./agentTooling/run-batch.sh --self <slug>    # build + verify + review agentTooling itself
./agentTooling/run-verify.sh --up-to 05 <slug>   # only the level-verify plans numbered ≤ 05
```

`--self` goes first, before the optional slug. See `RUNNER.md` → "Self-hosted mode".

All three runners are resumable: an interrupted plan is left in `inprogress/` and picked
up on the next run. See `RUNNER.md` for the full execution model — state folders,
resume phases, what the progress and `.stream.jsonl` logs contain, and how to read a
failure.

## Updating

Pull the latest into a repo:

```bash
git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
./agentTooling/sync-plans.sh
```

**Always run `sync-plans.sh` after a pull.** The pull updates this directory; it does
not touch the generated stubs in `plans/`, which point back here. Skipping it leaves
them pointing at whatever the layout used to be — and a stale pointer fails silently,
since nothing validates that a README's paths still resolve.

Push a fix made in a consuming repo back upstream, then pull it straight back:

```bash
git subtree push --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main
git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

**The pull after a push is not redundant.** `subtree push` sends commits upstream but
writes nothing locally, so the repo's recorded split — the `git-subtree-split:` trailer
naming the upstream commit this directory last matched — stays where it was before the
push. The pull records the new one. It changes no files, since the content is already
what you just pushed.

Skip it and the *next* push fails, because subtree rebuilds the branch it pushes from
the recorded split. From a stale one, that branch omits everything upstream gained since
— so the tip it offers is behind the remote and git rejects it:

```
error: failed to push some refs
hint: Updates were rejected because a pushed branch tip is behind its remote counterpart.
```

The hint is misleading here: `git pull` is not the fix, and neither is force-pushing —
the content is already in sync, only the pointer is stale. Run the `subtree pull` above
to record the current split, then push again.

A squash merge is the usual way this pointer gets left behind. It preserves the trailers
from the commits it flattens, so pulls keep working, but the split it records is whatever
the branch last pulled — not what a `subtree push` from that branch sent upstream
afterward.

Use `--squash` consistently. Mixing squashed and unsquashed pulls on the same
prefix produces conflicts that are tedious to unpick.

**All three subtree commands require a clean working tree** and abort with
`fatal: working tree has modifications. Cannot add.` otherwise — including for changes
in files that have nothing to do with this prefix. Commit or stash first. A tracked
`.DS_Store` is a common culprit on macOS.

**Renaming the prefix** is not a `git mv`: subtree records the directory in a
`git-subtree-dir:` trailer on its commits, and a moved directory leaves that trailer
pointing at the old path, so the next pull can't find its baseline. Remove the
directory, commit, then `subtree add` at the new prefix.

### Adopting levels and tiered gates

A repo whose `plans/gate.sh` predates level sentinels needs these once. `sync-plans.sh`
cannot do it: the gate is repo-owned and never overwritten, and a gate that ignores the
level contract fails silently — sentinels still run, but every level reads as unlabelled
and a skipped check reads as a pass.

1. `sync-plans.sh` as always.
2. Hand-merge the gate edits from `templates/plans/gate.sh` into `plans/gate.sh`: accept
   `$1` as a level label, copy the report to `gate-report.<label>.txt`, add `record_skip`
   and the SKIPPED verdict, honour `GATE_DEFERRED` in `_record`, and turn
   `GATE_EXPECTED_RED` into test-runner ignore flags.
3. Widen the repo's gitignore pattern from `plans/gate-report.txt` to
   `plans/gate-report*.txt`.
4. Author the next feature in the shape `AGENT_PLANS.md` → "Levels" describes, giving each
   sentinel its `expected-red:` / `defer:` lines.
