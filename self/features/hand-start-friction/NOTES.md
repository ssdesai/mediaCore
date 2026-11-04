# hand-start-friction — notes

Built by hand in a cloud container on `claude/hand-start-friction`, the coordinator session
building it itself.

## Rulings

1. **The wait contract is the template's to define, and it did not exist.** The brief
   said "the template seeds `--wait`". It did not: `templates/plans/cloud-setup.sh` at
   template-version 2 took no arguments, and `session-start.sh` runs it in the
   foreground. So the race can only come from a repo's own copy detaching its slow steps,
   which musicMap's evidently does. I could not read musicMap's copy: attaching that
   repository to this session was denied, and I did not retry. The contract is therefore
   defined here, at template-version 3:
   - `setup_in_background <command>` detaches a step, its output going to a log. It
     records the step's pid and then its exit code in the clone's own git dir
     (`cloud-setup.{pid,rc,log}`), never in the tree, because an untracked file there
     would make the cloud start refuse the checkout as dirty. It starts nothing while an
     earlier step is still running, so a resumed session does not start the install twice.
   - `plans/cloud-setup.sh --wait` polls every `WAIT_POLL_SECONDS` until that pid is
     gone, for at most `WAIT_TIMEOUT_SECONDS` (1800). It exits 0 when nothing was started
     or the step's recorded exit code is 0. It exits 1 when the step failed, ended with
     no code recorded (killed), or is still running at the timeout.
   - `feature-start.sh` calls `--wait` in the cloud for a consuming repo only (a `--self`
     checkout has no `plans/`, the same rule `session-start.sh` uses). The call comes
     **before the setup hook** as well as before the gate, because the hook racing the
     setup for `.venv` is the other half of the bug. It prints one `setup` line with the
     seconds it waited, and refuses on a non-zero exit, because a gate run after a failed
     setup would only refuse less clearly. A copy is taken to support the contract when
     it contains the literal `--wait`. That covers every v3 copy and also a repo that
     already hand-wrote a `--wait` of its own, which a version-number check would miss.
     A copy without it gets one line naming template-version 3, and the start goes on as
     before. Running such a copy again in the foreground was rejected: if it backgrounds
     a step it would start a second copy of that step and recreate the race.
2. **vinylCatalogue's ".venv already exists" is repo-owned code.** No template creates a
   venv in a way that fails when one exists. The commented examples in
   `templates/plans/worktree-setup.sh` and `templates/plans/gate.sh` use
   `python3 -m venv .venv`, which succeeds on an existing venv, and `uv` appears only as
   `uv run` / `uv pip install`. The error message matches `uv venv` refusing to replace an
   existing environment, so the creating call is in vinylCatalogue's own
   `plans/worktree-setup.sh` or `plans/cloud-setup.sh`. This matches `self/BACKLOG.md`'s
   earlier entry about a repo-owned `worktree-setup.sh` whose `uv` refused to recreate
   `.venv`. The race that exposed it (the start's hook creating `.venv` while the
   backgrounded setup was still creating it) is closed by ruling 1. Making that repo's
   step idempotent, e.g. `[[ -x .venv/bin/python ]] || uv venv`, is left to that repo,
   untouched here. The v3 template's commented example shows the idempotent shape.
3. **Item 2: option (a), a complete brief under `--method hand`, plus (b)'s clearer
   refusal for everyone else.** The planned-build rule exists so that a brief is written
   from the spec before the build, by someone other than the builder. A hand build has no
   delegate and no plans: the coordinator is the builder, so a stub it must fill in buys
   no independence. It only adds a refusal that every hand session hit. So under
   `--method hand` the start writes a brief with no marker:
   - **Spec:** the manifest's opening paragraph and its "Deliberately excluded" list.
     These are written before the build, as LIFECYCLE step 3 already asks. A reviewer who
     finds the paragraph still the template placeholder returns `Verdict: escalated`, so
     a missing spec fails closed at the reviewer and needs no new runner code.
   - **Builder's record:** `NOTES.md`, read after the diff, only to check its claims.
   - **Diff:** the same "The diff" section the stub carries.
   - **Contracts:** the standard hand-build checks (spec met, a failing-first test, gate
     green, READMEs current, named constants, NOTES' claims true), plus a line asking the
     coordinator to add the feature's own contracts.

   The start's "Next" step 1 for hand asks for exactly that, and says `run-review.sh`
   runs the brief as written, so a hand session following the printed instructions never
   hits a refusal. `plans` and `direct` keep the stub, the `^@@TODO@@` refusal and
   check-plans' lint unchanged. Their refusal (`plan-runner-lib.sh`'s `run_all`) now names
   the file as it was queued and as filed to `failed/`, plus the three things a brief
   holds, and the "Next" line for those methods lists the same three. This feature's own
   brief was written by hand, because this feature was started by the old
   `feature-start.sh`.
4. **Item 3** ends the `intact` line with "the vendored tree's own commit; a pull merges
   from it cleanly", the counterpart of `broken`'s "a pull from the stale base
   conflicts…". No doc quoted the cut-off text. `subtree-chain.sh` C4b now asserts the
   whole line.

## What changed

- `templates/plans/cloud-setup.sh` → template-version 3 (`TEMPLATE_VERSIONS` re-recorded;
  `sync-check.sh` 1m, `template-version-bump.sh` B2/B7, README "Adopting cloud-setup.sh
  version 3").
- `feature-start.sh`: the cloud wait (`CLOUD_SETUP_LABEL`, `CLOUD_SETUP_WAIT_FLAG`)
  before the hook. The hand-method brief (`REVIEW_BRIEF`, `REVIEW_NOTE`). The "Next"
  step 1 for each case.
- `plan-runner-lib.sh`: the stub refusal's text.
- `update.sh`: the chain line.
- `session-start.sh`: a header comment pointing at the wait.
- Tests: the new `self/tests/cloud-setup-wait.sh` (registered in `self/gate.sh`);
  `feature-lifecycle.sh` S3d2–S3d4, T1c2, and T3, which now runs the hand start's own
  brief with one line appended; `subtree-chain.sh` C4b.
- Docs: root `README.md` (feature-start row, templates row, the adoption section),
  `LIFECYCLE.md` steps 2–3, `templates/README.md`, `templates/plans/README.md`,
  `self/README.md`, `self/tests/README.md`.

## Round 2

Round 1's review escalated four contracts that held but had no test. Each now has one:
- `cloud-setup-wait.sh` W1f covers a step that recorded no exit code.
- W1g covers a step still running at a timeout shortened in the copy.
- W1h covers the local profile writing nothing, `--wait` included.
- `cloud-start.sh` R4 covers a resumed hand start keeping an extended brief byte for byte.
  The brief is planted after a refusal at the hook, standing for an earlier start that got
  that far.

The round-1 pass itself fixed two lines in `feature-start.sh`:
- The wait refusal now says to re-run `plans/cloud-setup.sh`, because `--wait` only
  re-reads the recorded failure.
- The hand brief no longer tells the reviewer to re-run the gate.

No code changed in round 2.

## Not done / for the next propagation round

- Each consuming repo merges cloud-setup.sh v3 by hand (`sync-plans.sh --check` reports
  `DRIFT 2 < 3`) and routes its own backgrounded steps through `setup_in_background`.
  musicMap is the one known to background a step. Until a repo merges, its start prints
  the "has no --wait" line and behaves as before.
- vinylCatalogue: make its venv creation idempotent (ruling 2).
- `feature-lifecycle.sh` prints one stray `No such file or directory` from T5's `printf`
  into the primary's `review/incomplete/`. That is a pre-existing fixture quirk, not
  touched by this feature; every assertion passes.
