# 01 — review: harness-driver-measures

You review a finished feature against the spec below, not against the builder's report.
"No findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix what is local
and mechanical; escalate anything that needs a design decision.

## What the feature was supposed to do

Principle: **the arm's own `agentTooling/` only does the building; the harness (the
driver — the copy `harness/run.sh` lives in) does all measuring and bookkeeping.** Every
fixture's `base` is a historical commit, so an arm's worktree carries an old vendored
`agentTooling/`. Four defects, four items, plus one resume requirement:

1. **Template fill.** `harness_fill_template` (`harness/lib.sh`) must substitute literally
   on bash 4.4 through 5.2+, whether or not `patsub_replacement` is on: a value holding
   `&`, `\&`, `\`, `/`, `@@OTHER@@` or newlines comes out byte for byte. No other
   `${x//pat/$var}` with a variable replacement may remain in the harness. A test must fail
   before the fix on bash 5.2.
2. **Measure with the driver's copy.** Cost capture and the cost report run from the
   driver's `analysis/`, never `$TREE/agentTooling/analysis/`; transcripts are found as
   before (the worktree's project directory, the claim root from `claim_roots`). Explicit
   root argument rather than the script's own location. A test: an arm whose vendored rates
   lack a model is priced at the driver's rates. Old-arm feature directories must not break
   the driver's capture.
3. **PR lookup and fallback with the driver's forge.** `harness_pr_url` uses the driver's
   `forge.sh` pointed at the arm checkout's origin (`HARNESS_FORGE_BIN` still overrides).
   When a method exits 0, its branch is pushed with commits beyond the base and no PR is
   open, the harness opens the PR itself, records the new boolean row field
   `pr_opened_by_harness` and an `interventions` entry (never silent). A method that exits
   non-zero or leaves no commits is still `method_failed`. The field is documented in
   `harness/README.md` → "File shapes" in full (README Rule 1).
4. **check-fixture / setup fetch the base.** When `base` does not resolve, run
   `git fetch origin <base>` once, retry, only then fail. By sha only: no ref is created or
   moved.
5. **Resume (added by the orchestrator).** A cell recorded `method_failed` only because no
   PR was open (state `stages.method.outcome == no-pr`) resumed with
   `run.sh <exp> --from review` runs only the PR check/open step, then review, rework and
   accept; it must never re-run the method; it records `pr_opened_by_harness` and the
   intervention and re-captures the method cost with the driver's rates. A test covers it.

Out of scope (must not appear in the diff): the spec-worktree `Read` denial, leftover
worktree cleanup, anything in the method templates (`harness/methods/*/template.md`).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `forge.sh` ships to every consuming repo: the new `FORGE_CHECKOUT` must be optional,
  default to the old behaviour (origin of the script's own checkout), and break nothing
  that calls `forge.sh` without it (`pr.sh` templates, `self/tests/pr-*.sh`).
- `analysis/roots.py`: `--arm-root` only changes the ordinary (non-`--self`) artifact root;
  `--self` and the session root derivation are unchanged; `--arm-root` with `--self` is a
  usage error. Scripts that do not call `apply_arm_root` behave exactly as before.
- Bash 3.2 compatibility (self/PROJECT_FACTS.md): no associative arrays, no `${v^^}`,
  empty arrays under `set -u`, `printf -v` is allowed. No `set -e`.
- README Rules 1 and 2 and "Keeping READMEs up to date" for every touched folder
  (`harness/`, `harness/tests/`, `analysis/`, `self/tests/`); `harness/README.md`,
  `SPEC.md` and `EXPERIMENTS.md` say "measuring is the driver's, building is the arm's"
  where they describe cost capture and PR lookup.
- Named constants for magic values (CONVENTIONS.md → Code style) in new code.
- The resume path: `method_failed` is cleared in state and the row; the worktree and the
  spec worktree are re-added only when missing; no model call happens; a missing PR that
  cannot be opened still ends as a recorded failure, not a silent pass.
- Tests: `self/tests/harness-driver-measures.sh` (wired into `self/gate.sh`) and the new
  sections of `harness/tests/smoke.sh` must exercise the behaviours above, and would fail
  if the behaviour regressed. Check that the assertions are not vacuous.
- Known limitation, not a finding: `git fetch origin <abbreviated sha>` generally fails
  against GitHub; a full sha works.

## Verdict

The first line of the report is `Verdict: clean` or `Verdict: escalated`, followed by
findings (file, line, gap, fix).
