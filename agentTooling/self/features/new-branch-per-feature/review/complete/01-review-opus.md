# 01 — review: new-branch-per-feature

Review a docs-only change against the owner's ruling below. "No findings" is a legitimate
verdict.

## What the feature was supposed to do

Encode the owner's ruling: **a new feature always gets a new branch, normally in a new
cloud session; a squash-merged branch is never taken over or force-pushed to start the
next feature.** Specifically:

- `ORCHESTRATION.md` → "Cloud sessions" states the rule: one feature per child session and
  per branch; after a feature PR merges, the next feature is a new child session on a new
  `claude/<slug>` branch; an orchestrator's own records branch squash-merged mid-wave gets
  a normal merge of `origin/main` (no reset, no force-push) or a fresh records branch; one
  sentence cites the `git patch-id` hazard (it ignores where in a file a change lands, so a
  branch edit to one of two identical blocks looks "already on main" when main edited the
  other, and a force-push silently loses it) as why a takeover is not automated.
- `LIFECYCLE.md` gets at most a one-line pointer for consistency.
- `self/BACKLOG.md`: the entry "A squash-merged cloud branch can't start its next feature."
  is removed; the "Running several features at once from one cloud orchestrator is
  undocumented" entry is untouched.
- Excluded: any `.sh`, hook, `analysis/` code, or another feature's folder.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The ORCHESTRATION text is consistent with the surrounding bullets, its notation
  (`→ "…"` cross-references) and with `LIFECYCLE.md` → "Orchestrator and implementer
  sessions" (one session, one branch, one feature; a start refuses a tracked manifest's
  branch, merged or not). Every cross-reference it makes resolves.
- The patch-id claim is stated accurately and does not overstate (it is a reason not to
  automate, not a claim the prototype was wrong in all cases).
- No file outside the three docs and this feature's folder changes; no script behaviour
  changes; the README index gate (`./self/gate.sh`) passes.
- Nothing else in `self/BACKLOG.md` is altered or left referring to the removed entry.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`.
