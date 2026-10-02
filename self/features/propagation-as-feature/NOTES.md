# Notes: propagation-as-feature

Direct build, one implementer. Rulings are judgment calls the brief left open; each has
a one-line rationale.

## Rulings

- **"A feature branch" is a branch `B` with `plans/features/B/README.md` in the
  checkout.** `update.sh` refuses a detached HEAD and any branch without that manifest,
  which covers `main` without naming it. Rationale: the consumer's base branch name is
  not knowable from inside `update.sh`, while the manifest is exactly what
  `feature-start.sh` writes, so the check says "a started feature" rather than "not main".
- **The branch check comes before the dirty check.** On `main` with a dirty tree the
  refusal names the recipe, not the dirt — the wrong place to pull is the more basic
  mistake.
- **`update.sh` prints a `split <sha>` line** read from the squash commit's
  `git-subtree-split:` trailer. Rationale: the recipe's manifest prose names the sha
  pulled, and this makes that a copy rather than a `git log` hunt.
- **The dirty-tree refusal says "commit them first"**, no longer "commit or stash":
  `git stash` is denied in every consumer (`hooks/policy.py`).
- **Slug: `pull-agenttooling-pr<N>`**, `N` the agentTooling PR; a pull of several merged
  PRs is named for the newest. Kept from the 2026-09-24 pulls, per the brief.
- **Method stays `hand` even when a delegate does the pull.** `hand` and `direct` both
  file `planning.json` under build, so the dollars land in the same bucket; `direct`
  would promise `AGENT_DIRECT.md`'s procedure (tests first, checkpoint), which a pull
  does not follow. The report's row label reads "build: by hand" for a delegated pull —
  accepted.
- **Who is pinned** (`LIFECYCLE.md` → "Propagate" step 4): the session that ran the start
  and the pull is started with `--pin` (or `pin-session` afterwards); a session opened in
  the worktree needs nothing; a delegate is pinned with `pin-subagent`. Rationale: a
  router that runs the worktree's `update.sh` by absolute path never `cd`s there, so
  `routing.worked_in` does not see it and the close would *not* refuse it — unpinned, its
  pull would silently be routing overhead. The recipe has to say so; the close cannot.
- **The review runs on every pull.** The close refuses without a clean one anyway, and
  the 2026-09-26 hand features' reviews cost about a dollar each; a bad hand-merge of a
  repo-owned script found after the merge costs more. The recipe names what the brief
  should check.
- **No allow rule.** Neither `git subtree` nor `git merge` is in `hooks/policy.py`'s
  table, and the hook sees only the top-level command (`update.sh`, a prompt), so nothing
  blocks the pull. `self/tests/propagation-pull.sh` P5–P6 pin that, so a later deny that
  would break the recipe fails the gate.
- **`sync-check.sh` phase 9 now pulls on a started feature's branch** — it pulled on
  `main`, which the new refusal rejects. Its refusal cases are `propagation-pull.sh`'s.

## The assertion, as a dry description

The entry's assertion — after a round, the residue lists none of the round's delegates
and a report shows the total — is not asserted end to end (backlog entry "No end-to-end
test of a propagation pull's cost record"). It follows from parts that are:

1. The pull happens on branch `pull-agenttooling-pr<N>` in its worktree
   (`propagation-pull.sh` P1–P4: nowhere else).
2. Whoever did it is claimed: a worktree session by branch (`feature-lifecycle.sh` C1), a
   pinned session outright (`capture-from-worktree.sh`), a pinned delegate as `pinned`,
   after which the capture stops naming it (`feature-lifecycle.sh` C2f–C2i). A claimed
   delegate is not in `--list-subagents --unclaimed`, which is what the residue prints.
3. The close runs that capture on the branch, and `report.py pull-agenttooling-pr<N>`
   renders the frozen record — the total.

## Disclosed remainder

The 24 propagation delegates of 2026-09-16 through PR #60 ($16.55, counted 2026-09-23 in
the retired backlog entry) stay unclaimed. They predate any `pull-agenttooling-pr<N>`
feature, so there is no manifest to pin them in; they remain in the corpus-wide unclaimed
listing as a known remainder, not a new backlog entry.
