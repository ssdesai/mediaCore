# 01 — review: pull-agenttooling-pr121

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `plans/features/pull-agenttooling-pr121/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`plans/features/pull-agenttooling-pr121/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`plans/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own contracts:

- The pull merged agentTooling main at `114e7ea393f8495ec205b942b9216a3e50f738c1`
  (agentTooling PRs 118–121, range since `0e28a4c`) via `agentTooling/update.sh`: one
  no-change re-anchor merge commit (the `chain` line was `broken`), then the subtree merge.
  The `agentTooling/` diff must be the upstream range and nothing else; nothing under
  `agentTooling/` or `.claude/` was hand-edited.
- `agentTooling/sync-plans.sh --check` is clean; the sync wrote nothing in `plans/` and
  printed no DRIFT line.
- The gate state is in the report below (base gate green at start; post-pull gate in
  `plans/gate.sh` output). The README-index check (PR 119) is deliberately not opted in.
- Outside `agentTooling/`, the diff is only this feature's manifest and this review brief.

## Verdict
