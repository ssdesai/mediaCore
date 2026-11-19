# 01 — review: branch-sync-and-fanout-docs

Review the diff below against the spec in the two sections that follow, written before the
build from the implementer brief and the two `self/BACKLOG.md` entries it closes. Read the
diff, not the builder's report. "No findings" is a legitimate verdict: return `Verdict:
clean` when the items are closed and nothing regressed.

Scope rule from the repository owner: a finding blocks only if it is an item below that is
not closed, or a regression this feature introduces. Anything else is non-blocking, to be
filed in `self/BACKLOG.md`; say which of your findings are which.

## What the feature was supposed to do

**Item 1 — a lifecycle script that merges `origin/main` into the feature's branch.**
BACKLOG (Loose harness items): "No lifecycle script brings a feature branch up to date with
main." A new script at the repo root, in the `feature-*.sh` family (`feature-sync.sh`), taking
`[--self] <slug>` like its siblings. It:

- fetches `origin main` (the manifest's `base`, `main` when absent) and merges `origin/<base>`
  into the current branch with a normal merge commit — never a rebase, a reset, a
  `checkout -B` or a force-push, and it pushes nothing;
- refuses a dirty working tree (tracked or untracked changes);
- refuses when the checkout is not on the started feature's branch: the slug's tracked
  manifest exists and its `branches[0]` (`manifest_branch`) is the current branch — read the
  way `feature-close.sh` and `attach-branch.sh` read it, never derived from the slug;
- refuses in an orchestrator's session (`refuse_orchestrator_session`), as the other
  lifecycle scripts that write do;
- on a conflict leaves the merge in progress (MERGE_HEAD present), names every conflicted
  file, and prints the next commands: resolve, `git add`, `git commit`; or `git merge --abort`;
- on success says to re-run the gate and a review scoped to the merge (and, where they
  collide, to renumber migration or test ids and keep every sibling's fields);
- moves nothing on any refusal (HEAD and the branch ref unchanged).

The hook must let an implementer run it the way `attach-branch.sh` / `feature-start.sh` are
treated: not on the read-only entry-point list, so it prompts. Nothing else in the hook is
widened. A `self/tests/` test covers: a clean merge; a dirty tree refused; not-a-feature-
branch refused; a conflict leaves the merge in progress and names the file; the branch never
moves on a refusal. Documented in `LIFECYCLE.md` (where rule 2 says the quick shapes are
denied, pointing at the script) and indexed in the root `README.md`; the BACKLOG entry is
removed.

**Item 2 — close the cloud fan-out documentation entry.** BACKLOG: "Running several features
at once from one cloud orchestrator is undocumented." Compare that entry's points with
`ORCHESTRATION.md` → "Cloud sessions" and add only what is missing, within the "Cloud
sessions" bullets. At least: permission prompts must be answered in each child's own
session; overlapping features merge in PR order, and the later one merges `origin/main`
(with the new script), renumbers any colliding migration or test ids, keeps every sibling's
fields, and re-runs the gate and a review scoped to the merge; about 5 concurrent Opus
children is the practical usage-limit ceiling, and a usage-limit stop is reported once, then
the children are resumed after the reset. The BACKLOG entry is removed.

Excluded: the orchestrator's `BUILD_SCRIPTS` list in the hook (sibling features edit
`hooks/allow-repo-commands.sh`; the orchestrator's Bash is an allowlist that already denies
an unlisted script), `ORCHESTRATION.md`'s `--branch` text (a sibling's), and any automation
of renumbering.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `feature-sync.sh` at the repo root: `set -uo pipefail`, no `set -e`, bash 3.2 (no
  associative arrays; empty arrays expanded with `${a[@]+"${a[@]}"}`), named constants at
  the top, sources `plan-runner-roots.sh` and uses `resolve_roots`, `manifest_field`,
  `manifest_branch`, `refuse_orchestrator_session`; refusals print `  refused  …` on stderr
  and exit 1, usage exits 2, a conflict exits non-zero and distinct from a refusal.
- No `git push`, `reset`, `rebase`, `checkout -B`/`-b`, `branch -f` or `update-ref` in it; the
  only ref it moves is the current branch, by `git merge --no-ff`-or-equivalent normal merge.
- `self/tests/feature-sync.sh` exists, is recorded by `self/gate.sh`, runs offline in a
  `mktemp -d`, forces the profile per `self/PROJECT_FACTS.md` if it touches one, and asserts
  the five behaviours above; `self/tests/README.md` has its entry.
- The root `README.md` names `feature-sync.sh`; `LIFECYCLE.md` rule 2 points to it;
  `self/PROJECT_FACTS.md` → Layout lists it among the shared machinery if that list is the
  index of lifecycle scripts.
- `hooks/` unchanged, or changed only to keep the new script prompting; `.claude/` untouched.
- `ORCHESTRATION.md` edits confined to the "Cloud sessions" bullets.
- `self/BACKLOG.md` no longer carries either entry.
- The gate (`./self/gate.sh`) is green, the README-index check included.

## Verdict
