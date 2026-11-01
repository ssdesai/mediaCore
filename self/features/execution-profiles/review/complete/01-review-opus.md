# 01 — review: execution-profiles

Written from the design (`self/DESIGN-2026-10-05-cloud-execution.md` §1, §2, §3, §5, §7,
§8, §9 and §10's `execution-profiles` row) and the rulings in this feature's manifest
**before** the build, never from an implementer's report. Read the code; do not take the
manifest's or `NOTES.md`'s account on trust. "No findings" is a legitimate verdict. Fix
local drift in this pass; anything structural is an escalation, and an escalated report is
round 2's brief. Begin your report with the `Verdict:` line the prompt asks for.

## What the feature was supposed to do

The last feature of the cloud design: **the lifecycle never asks where it is running.**
One detector and a few adapters hold every local/cloud difference.

**Slice A**

1. **§1 detector.** `env-profile.sh` at the root, sourced, sets `AGENTTOOLING_PROFILE` to
   `local` or `cloud`: an explicit `AGENTTOOLING_PROFILE` wins; otherwise
   `CLAUDE_CODE_REMOTE=true` → `cloud`; otherwise `local`. It also holds the checkout-layout
   adapter's functions (`feature_checkout <slug>`, `feature_branch <slug>`,
   `create_checkout <slug> <base>`, per the §1 table).
2. **§1 confinement.** A `self/gate.sh` check fails when `CLAUDE_CODE_REMOTE` or
   `AGENTTOOLING_PROFILE` appears in any tracked file other than the detector, the
   adapters and their tests. How prose (design docs, READMEs) is treated is a ruling the
   build must record; the check must not be vacuous (it must fail on a lifecycle script
   that reads either variable — test that).
3. **`profile` in the fence.** `feature-start.sh` prints one `profile` line naming the
   profile and the variable that decided it, and writes `profile` into the manifest fence
   through `manifest.py`; `check-plans.sh` accepts the key and `report.py` shows it.
4. **§2 the cloud layout.** In the cloud the container is the worktree: the start uses the
   primary itself on the assigned branch. `--branch <name>` names it; the default is the
   current branch when that is not the base; on the base with no `--branch` the start
   refuses naming the flag; the script, never an agent, does any `git checkout -b`. It
   refuses a branch carrying commits not on `origin/<base>` and a dirty tree. One feature
   per container: a second start whose branch already carries a started feature is
   refused, naming it. A refused start is re-runnable without loss: a re-run finds the
   checkout and resumes at the setup hook, deleting nothing. The "primary on main" check
   becomes "the checkout contains `origin/<base>`" in both layouts. The local layout is
   unchanged — every existing `feature-lifecycle.sh` / `start-takeover.sh` assertion
   still passes untouched.
5. **§3 the router is derived.** The start writes `routing.json` only when the session
   running it was launched on a branch other than the feature's. Locally (launched on
   `main`) that is today's behaviour; in the cloud (launched on the assigned branch) the
   session is the coordinator: no routing record, no pin. `ORCHESTRATION.md` gains the
   paragraph §3 names.
6. **The start-instant finding** (design §10, `cost-capture-collisions`' findings): a cloud
   coordinator is launched on the assigned branch before the start stamps `from`, so the
   branch route (which selects by a session's *start*) does not select it, and
   `set-window-from` had to be run by hand. The cloud start must handle this so no hand
   step is needed, and a test must show the capture selecting such a coordinator. The
   chosen mechanism and its cost consequence (what happens to the session's spend before
   the start) must be recorded in `NOTES.md` and the design's §10.
7. **§5 forge.** `forge.sh auto-merge <pr-url>`: local `gh pr merge --auto --merge
   --delete-branch`; cloud `gh api -X PUT …/pulls/{n}/ccr/auto_merge` with merge method
   `merge`, never squash. A reachability verb: local `gh auth status`; cloud `gh api
   /repos/{o}/{r}`, never `auth status`. `pr.sh`'s merge request goes through
   `forge.sh auto-merge`. `pr.sh` was already at `template-version: 5` with the README's
   "Adopting the forge adapter" section (from `cloud-close`); any body change to the
   template must bump its version, re-record `TEMPLATE_VERSIONS`, carry the same logic
   into `self/pr.sh` below its REPO-SPECIFIC line, and extend that README section with the
   hand-merge.

**Slice B**

8. **§7 seeded files.** `plans/environment.sh` (facts only: DB connection, browser path,
   anything that differs by profile; a commented example of each profile; no `brew`) and
   `plans/cloud-setup.sh` (once per container), both seeded by `sync-plans.sh`,
   template-versioned and in `TEMPLATE_VERSIONS`. `sync-plans.sh` wires `cloud-setup.sh` as
   a `SessionStart` hook in the repo's `.claude/settings.json`, guarded to run only under
   the cloud profile, merged additively — added once, never duplicated. The gate template
   and `worktree-setup.sh` template source `environment.sh`. `templates/README.md` names
   the cloud environment's own setup script as the alternative and when to prefer it.
9. **`sync-plans.sh --check`** reports a missing `environment.sh` or `cloud-setup.sh` as
   `MISSING`, like `BACKLOG.md`.
10. **The `gate` key.** The start records `gate: "skipped"` under `--no-gate`, otherwise
    `"green"`; `check-plans.sh` accepts it, `report.py` shows it.
11. **§8 resumable gate** (the template gate): each check's result written to
    `gate-state/<tree-sha>/<label>` as it finishes; under `GATE_RESUME=1`, which the
    runners and the start set, a check already recorded for the same tree is skipped. The
    tree sha is `git write-tree` over the checkout with untracked inputs included, computed
    without disturbing the real index. The state directory must not dirty the tree.
12. **§8 doctrine** in `ORCHESTRATION.md` and `AGENT_DIRECT.md`: the coordinator owns any
    long run; an implementer's brief ends at "commit and checkpoint, then stop"; in a cloud
    session the coordinator arms one `send_later` check-in before such a run.
13. **§9** `sleep` gains a rewrite reason in `hooks/allow-repo-commands.sh` ("nobody polls:
    run it in the background and wait for the notification"), with its row in
    `self/tests/allow-repo-commands.sh`. It may only tighten the policy.

## The diff

Base `main`; read `git diff origin/main...HEAD` (this cloud checkout may have no local
`main`). Expect the root scripts (`env-profile.sh` new, `feature-start.sh`, `forge.sh`,
`check-plans.sh`, `sync-plans.sh`, the runners for `GATE_RESUME`), `analysis/manifest.py`
and `analysis/report.py`, `hooks/` (the sleep reason, the SessionStart wiring),
`templates/plans/*` and `TEMPLATE_VERSIONS`, `self/pr.sh`, `self/gate.sh`, `self/tests/*`,
the doctrine docs, every touched README, the design's §10, `self/BACKLOG.md` if anything
is left, and `self/features/execution-profiles/`. **No other feature's directory under
`self/features/` may change** — a sibling's record in the diff is a finding of the first
order.

## Contracts to hold it to

- **Tests came first and test the promise**, black-box through the scripts and disk, in
  the existing `self/tests` files or a new `gate-resume.sh`:
  - §1: the detector's three cases; the confinement check failing on a planted read.
  - §2: under `cloud`, a start on an assigned branch uses the primary, writes
    `branches: [<that branch>]`, `profile: "cloud"`, no routing record; refuses on the
    base without `--branch` (naming it), a branch with foreign commits, a dirty tree, and a
    second feature; a refused start re-run resumes without deleting a hand fix.
  - The start-instant fix: a capture selects the cloud coordinator that began before the
    start, with no `set-window-from`.
  - §5: under `cloud` the close opens the PR through `gh api` and never calls `gh pr` or
    `gh auth status`; under `local` the merge request calls `gh pr merge --auto --merge`;
    under `cloud` it calls the `ccr/auto_merge` route; a stubbed REST failure exits
    non-zero and stamps the rc with no url; `pr-find` returning a url skips `pr-open`.
  - §7: seeding and versions; the `SessionStart` entry added once and never duplicated;
    `--check` reporting both files MISSING; the `gate` key `skipped` / `green`.
  - §8: a gate killed after check k re-runs from k+1 on the same tree, and from the start
    on a changed one.
  - §9: the `sleep` row.
  Check each would fail on `main`'s code; mutate one site mentally per item and name the
  assertion that catches it.
- **No assertion weakened.** Existing `check` lines are unchanged unless the behaviour they
  pinned is what this feature changes, and each such change is justified in `NOTES.md`.
- **The local path is unchanged.** Nothing a local user runs behaves differently except
  the additions (the `profile`/`gate` keys, the printed `profile` line, `GATE_RESUME`).
- **Shell discipline:** bash 3.2, `set -uo pipefail` with no `set -e`, named constants
  (CONVENTIONS "Named constants"), no new place outside the detector, adapters and tests
  that reads either profile variable.
- **Template versions:** every seeded template whose body changed has a bumped
  `template-version`, a re-recorded hash, and a hand-merge note in `README.md`; seeded
  copies at the old version are reported as `DRIFT`.
- **The gate passes.** Run `./self/gate.sh` and report its verdict line.
- **READMEs** (CONVENTIONS "Keeping READMEs up to date"): root `README.md` rows for
  `env-profile.sh`, `forge.sh`, `feature-start.sh`, `sync-plans.sh`; `templates/README.md`;
  `self/README.md`; `self/tests/README.md` rows; `hooks/README.md`; `analysis/README.md`
  for the fence keys; `LIFECYCLE.md` step 2 for the cloud layout; the design's §10 for what
  was built and found.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
