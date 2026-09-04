# 81 — docs: the procedures now point at the scripts

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 8 of 8 build plans.

Documentation only. Every procedure that the batch's scripts replace now names the
script; the prose that explained the steps stays as the explanation of what the script
runs.

Depends on: 76, 77, 78, 79 (the scripts exist on disk; read their header comments for
the exact flags before writing about them).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- The scripts and flags: `check-plans.sh [--self] <slug>` (fourteen checks, exit 1 on
  any; `run-batch.sh` runs it first and stops on failure); `sync-plans.sh [--check]`
  (`--check` writes nothing; the write path ends with the repo-owned report; statuses
  `in-sync`, `STALE`, `DRIFT`, `missing`, `unfilled`; exit 1 when anything needs
  attention); `update.sh [--remote <url>] [--branch <name>]` (dirty tree refused,
  `git subtree pull --squash`, then the pulled `sync-plans.sh`); `sweep.sh [--self]`
  (rates, backfill, recover, capture `--all`, report, unclaimed, done; exit 1 if a step
  failed); `analysis/manifest.py [--self] <slug> set-plans <stem>...` (already on
  disk); the `# template-version: N` line (gate.sh 2, pr.sh 2, worktree-setup.sh 1).
- The capture change (plan 79): excluded sessions met on the branch lift the zero
  refusal; the record carries them in `excluded_session_ids` with a warning.
- Under `--self` the scripts are invoked as `./check-plans.sh --self <slug>` and
  `./sweep.sh --self` from the checkout; from a consuming repo as
  `./agentTooling/check-plans.sh <slug>`, `./agentTooling/sweep.sh`,
  `./agentTooling/update.sh`.

## Files

- modify `LIFECYCLE.md`
- modify `README.md`
- modify `analysis/README.md`
- modify `templates/README.md`
- modify `RUNNER.md`
- modify `AGENT_PLANS.md`
- modify `self/PROJECT_FACTS.md`
- modify `self/README.md`
- modify `self/features/README.md`

## `LIFECYCLE.md`

- Step 3 (Brief): after the sentence about filling the manifest's prose, one sentence:
  `check-plans.sh [--self] <slug>` says whether the stub was replaced and the fence and
  plan files are well-formed, and `run-batch.sh` runs it before spending anything.
- Step 4 (Build), the plans sentence: `run-batch.sh` lints the corpus first
  (`check-plans.sh`) and stops on a failure.
- Step 7 (Sweep and propagate): rewrite to two commands. Weekly,
  `./agentTooling/sweep.sh` (and `./sweep.sh --self` here) runs the cadence in order —
  keep the existing sentence about what that pass catches — and prints the unclaimed
  delegates and sessions; then `./agentTooling/update.sh` in each consuming repo pulls
  this directory and runs `sync-plans.sh`, whose report names the repo-owned scripts
  that need a hand-merge. Keep the pointer to `README.md` → "Updating".

## `README.md`

- "Updating": replace the two-command block with `./agentTooling/update.sh` and keep
  the explanation as what it runs (the two commands stay, shown as what `update.sh`
  does). Keep the paragraphs about pushing back upstream, the pull after a push, squash
  consistency and the clean-tree requirement unchanged. Add one paragraph: `sync-plans.sh`
  now ends with a report on the repo-owned files, and `sync-plans.sh --check` gives the
  same report without writing; a `DRIFT` line names a script whose `template-version`
  is behind the template's and points at the hand-merge sections below.
- "Adopting feature-branch PRs" and "Adopting levels and tiered gates": add a closing
  sentence to each — `sync-plans.sh --check` reports the un-merged copy as
  `DRIFT plans/pr.sh (template-version 0 < 2; …)` (respectively `plans/gate.sh`); after
  merging, add the line `# template-version: 2` directly after the script's `set -…`
  line so the check goes quiet.
- Contents rows for `check-plans.sh`, `sweep.sh` and `update.sh` were added by plans 76,
  77 and 78; read the table and fix wording only if a row is missing or contradicts the
  flags above.

## `analysis/README.md`

- "How to run them": open the weekly section with `../sweep.sh [--self]` — it runs
  steps 1–4 below in this order and then lists the unclaimed delegates and sessions —
  and keep the numbered steps as the explanation of each. Replace the closing
  `for s in <slug> …` loop with a sentence: the sweep reports each feature whose cost
  files changed, then `--all`.
- The `manifest.py` row in the scripts table: add `set-plans <stem>...`.
- The zero-refusal sentence was updated by plan 79; leave it.

## `templates/README.md`

After the `gate.sh`/`pr.sh` paragraph: the three seeded scripts carry a
`# template-version: N` line; `sync-plans.sh --check` compares a seeded copy's line
against the template's and reports `DRIFT` when it is behind; bump the template's
number whenever the body below `REPO-SPECIFIC` changes in a way seeded copies must
merge by hand, and say what changed in the README's "Adopting …" section for it.

## `RUNNER.md`

Where `run-batch.sh`'s sequence is described (search `run-batch.sh` in the "Layout and
state" or the tier-ladder section — whichever states the build → gate → verify → review
order), add: it runs `check-plans.sh` on the feature first and stops, running nothing,
when the lint fails.

## `AGENT_PLANS.md`

- "Plan file format": one sentence at the end — `check-plans.sh` enforces the filename
  rule, uniform digit padding, the `plans[]` ↔ file correspondence and the absence of a
  queued `@@TODO@@` stub, and `run-batch.sh` runs it before the build pass.
- "The feature manifest", the `plans` bullet: the architect writes the list with
  `python3 agentTooling/analysis/manifest.py [--self] <slug> set-plans <stem>...`;
  `feature-start.sh` numbers the review stub first, so renumber it to sort last and
  include the new stem.

## `self/PROJECT_FACTS.md`

- Layout: add `check-plans.sh`, `sweep.sh`, `update.sh` to the shared-machinery list.
- Commands: a bullet for `./check-plans.sh --self <slug>` (run by `run-batch.sh --self`
  first) and one for `./sweep.sh --self`; extend the manifest sentence with
  `set-plans`.

## `self/README.md`

The `tests/` row: add `check-plans.sh`, `sync-check.sh` and `sweep.sh` to its list of
scripts.

## `self/features/README.md`

- Add an entry for `sweep-and-check` in the shape of its neighbours, from the manifest's
  first paragraph and plan table: the four scripts, the capture change, plans 73–83,
  built with the plans method, planned from the session pinned to `feature-lifecycle`.
- In the `feature-lifecycle` entry, "three pinned delegates" is now four (a rework
  delegate was pinned after the review); fix the count.
- `tooling-backlog-2026-09` has no entry. Add one from the first paragraph of
  `self/features/tooling-backlog-2026-09/README.md`, in the same shape.
