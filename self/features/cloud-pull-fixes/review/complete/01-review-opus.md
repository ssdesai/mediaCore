# 01 — review: cloud-pull-fixes

You are reviewing a direct build in agentTooling's own corpus (`--self`), against the
defects it was briefed to fix — never against the builder's report. Read
`self/features/cloud-pull-fixes/README.md` (the goal) and `NOTES.md` (the builder's
rulings: judge each, do not take them as given), `CONVENTIONS.md` (README rules, named
constants) and `self/PROJECT_FACTS.md` (bash 3.2, `set -uo pipefail` with no `set -e`,
stdlib-only analysis, bare imports). "No findings" is a legitimate verdict. Fix what is
local and plainly wrong yourself; escalate what is structural.

## What the feature was supposed to do

Three defects, found propagating PRs 85–86 into four consuming repos from one Claude Code
cloud container:

- **A.** `update.sh` refused every cloud-started feature: it wanted
  `plans/features/<current branch>/README.md`, while in the cloud the branch is the
  session's `claude/…` one and the manifest is `plans/features/<slug>/README.md` with that
  branch in its fence. Wanted: when the branch-named manifest is absent, the one started
  feature whose manifest names the current branch is accepted, reusing the existing
  branch→manifest lookup rather than a second parser; exactly one match pulls and the
  `pull` line names the slug; zero refuses as before; more than one refuses naming them.
  The existing refusals (detached HEAD, dirty tree, source checkout, `main`) stay, and
  everything stays inside `main()` because the pull overwrites the file mid-run.
  `LIFECYCLE.md` → "Propagate" step 2, `README.md` → "Updating" and the script's header
  describe the cloud case.
- **B.** PR 85 reworded `templates/plans/cloud-setup.sh`'s header without bumping
  `template-version 1`, so `sync-plans.sh --check` reported stale copies `in-sync`
  forever. Wanted: cloud-setup.sh bumped to 2 (so repos still on the old comment get
  DRIFT), the comment-only hand-merge described, and a **blocking** `self/gate.sh` check
  that makes "template content changed, version stamp didn't" impossible to merge, working
  in a shallow clone (a committed ledger preferred over git history), with a `self/tests`
  test and its row.
- **C.** Claimant mentions `<repo_name>/<slug>` duplicated by case (`musicmap/x` and
  `musicMap/x`) because repos were cloned to lowercase directories, and every close's
  frozen-record refresh wrote the duplicates into other features' records. Wanted: the
  display name from the repo's origin rather than its directory; every place that compares
  or prints `<repo_name>/<slug>` (`check_brief_headers`, `feature-start.sh`'s "Every
  delegate brief opens with" line, report.py's "also claimed by", the `seen` ledger)
  consistent, comparisons of repo names case-insensitive; ledgers already holding both
  spellings render one mention, preferring the better spelling; a refresh over an
  unchanged corpus still writes nothing.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

1. **A, behaviour.** On a branch with no `plans/features/<branch>/README.md`: exactly one
   **tracked** manifest whose branch is the current branch pulls, and the `pull` line names
   that slug; none refuses (exit 1) naming the path looked for; two or more refuse naming
   every slug; an untracked manifest is not a start. `main` and a detached HEAD refuse
   whatever any manifest says; the dirty-tree and source-checkout refusals are unchanged;
   the local layout (branch-named manifest) behaves exactly as before. No ref moves on a
   refusal. Check that the lookup is the shared reader (`plan-runner-roots.sh`) and is
   loaded before the pull, inside `main()`, and that a copy of `update.sh` without the
   library still behaves for the local layout. `self/tests/update-cloud-branch.sh` and
   `self/tests/propagation-pull.sh` green.
2. **A, docs.** `LIFECYCLE.md` → "Propagate" step 2, `README.md` → "Updating" and the
   `update.sh` row, and `update.sh`'s header all describe the cloud path; no doc still says
   only `plans/features/<branch>/README.md` counts.
3. **B, the stamp.** `templates/plans/cloud-setup.sh` is at 2, `TEMPLATE_VERSIONS` records 2
   and a hash that matches; a consumer copy at 1 reads `DRIFT … (template-version 1 < 2; …)`;
   the hand-merge of a comment-only bump is described (template header and/or README
   "Adopting …"). Judge the ruling that comments now count toward the hash — it reverses
   an earlier deliberate one — and whether re-recording the other five rows at their
   current versions silently hides any real unbumped change (check each template's history
   since its version line last moved).
4. **B, the check.** `self/gate.sh` records it as blocking; it needs no git history; a
   comment-only edit, a body edit, and a bump without re-recording all fail it; the re-record
   command in `TEMPLATE_VERSIONS`' header is exactly what the check computes.
   `self/tests/template-versions.sh`, `self/tests/template-version-bump.sh` and
   `self/tests/sync-check.sh` green.
5. **C, collapse.** A frozen record holding both spellings ends with one mention; a kept
   (unseen) mention and the ledger's differently-cased one are one; the preferred spelling
   is deterministic in the set; `report.py`'s shared-session list cannot print a case-only
   duplicate. Look for any other writer or reader of `also_claimed_by` / `share_basis` /
   `seen` / `<repo_name>/<slug>` the build missed.
6. **C, refresh idempotence.** A second `--annotate-frozen` over an unchanged corpus prints
   nothing and leaves every `planning.json` and the claims ledger byte-identical, and
   `feature-capture.sh`'s commit of annotated siblings therefore carries nothing on a
   repeat run. `self/tests/claimant-case.sh`, `claims-ledger.sh`, `session-claims.sh`,
   `session-share.sh` green.
7. **C, names.** `feature-start.sh`'s brief-header line and `feature-capture.sh`'s `--for`
   name the repo by the same rule as `capture_planning.repo_display_name` (origin, else
   directory; `agentTooling` under `--self`); `check_brief_headers` and `--for` compare the
   repo half case-insensitively and the slug exactly. Judge the builder's finding that the
   cloud origin itself is lowercase, and whether the chosen preference (a spelling with
   capitals over an all-lowercase one) is right given it.
8. **Quality bar.** Named constants for every literal that carries meaning; bash 3.2 (no
   `${x,,}`, no associative arrays, empty arrays expanded safely); every touched folder's
   README current (root, `analysis/`, `templates/`, `self/`, `self/tests/` — a row for each
   new test); deliberate leftovers in `self/BACKLOG.md`.
9. **Gate green.** Read `self/gate-report.txt` from the coordinator's run on this tree; do
   not re-run the whole gate. Run any single test file you need to settle a finding.

## Verdict
