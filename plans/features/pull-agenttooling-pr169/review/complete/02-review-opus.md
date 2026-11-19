# 02 — review: pull-agenttooling-pr169

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

Round 2: round 1 escalated only because the manifest's opening paragraph was still the
template placeholder. It is written now; its one finding is addressed.

## What the feature was supposed to do

The spec is the manifest, `plans/features/pull-agenttooling-pr169/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
There is no NOTES.md for this feature; the coordinator's record is the manifest.

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

This feature's own contracts:

- `plans/pr.sh` is the template at `agentTooling/templates/plans/pr.sh` (template-version 8).
- Nothing under `src/` or `tests/` changes.
- `plans/` generated files match what `agentTooling/sync-plans.sh --check` reports in sync.
- The manifest's opening paragraph, Plans table and exclusions describe the pull, and the
  template's Levels and Contracts sections are removed (single-level batch).

## Verdict
