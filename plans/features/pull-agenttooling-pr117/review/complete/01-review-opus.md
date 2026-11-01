# 01 — review: pull-agenttooling-pr117

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `plans/features/pull-agenttooling-pr117/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`plans/features/pull-agenttooling-pr117/NOTES.md` is the builder's record — its rulings and what it left
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

- What was pulled: agentTooling main at PR 117's merge, split sha
  `0e28a4caa042cd0626e9352732e81088318054c7`, via `agentTooling/update.sh`
  (`git subtree pull --squash`; clean, no conflicts; `chain` line `fragile`).
- The `agentTooling/` diff is the upstream range and nothing else: no hand edit anywhere
  under `agentTooling/` or `.claude/` (the one `.claude/settings.json` change is what
  `sync-plans.sh` wired: a retired `Edit(**/agentTooling/hooks/**)` deny rule removed).
- `agentTooling/sync-plans.sh --check` is clean, and what the sync wrote
  (`plans/README.md`, `plans/features/TEMPLATE.md`, `plans/ORCHESTRATOR_BRIEF.md`,
  `.claude/settings.json`) is committed in `pull-agenttooling-pr117: commit what
  sync-plans.sh wrote`.
- Repo-owned `plans/` files (`PROJECT_FACTS.md`, `BACKLOG.md`, `gate.sh`, `pr.sh`, ...)
  are untouched.
- Gate: the base gate at the start was green, and `plans/gate.sh` after the pull was
  green (install, lint, fixture idempotent, wheel contains fixture, tests).
- The manifest's opening paragraph names agentTooling PR 117 and the split sha.
- mediaCore has no harness fixtures, so the same-repo rule changes nothing here.

## Verdict
