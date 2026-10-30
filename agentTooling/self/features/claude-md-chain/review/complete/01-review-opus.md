# 01 — review: claude-md-chain

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/claude-md-chain/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`self/features/claude-md-chain/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own contracts:

- `CONVENTIONS.md` still carries, unchanged in substance: the File Access bullets; every
  row of the shell rewrite table; "Closing a feature"; "Generated READMEs"; "Keeping
  READMEs up to date"; README Rules 1 and 2 with their examples; "Named constants" with
  its example block. It no longer forbids Grep/Glob for discovery and no longer sets a
  file-count stop condition. It names `plans/PROJECT_FACTS.md` (and
  `self/PROJECT_FACTS.md`) as what to read before authoring a plan.
- `CLAUDE.md` and `RUNNER.md` → "Self-hosted mode" no longer say the conventions load
  twice or that a `--self` executor never sees the consuming repo's root `CLAUDE.md`;
  what they say instead matches `self/features/claude-md-chain/NOTES.md`.
- `AGENT_PLANS.md` → "Routing for cost" does not present `/fast` as a cheaper model.
- `hooks/wire-settings.py` exposes `RETIRED_EDIT_DENY_RULES` containing exactly
  `Edit(**/agentTooling/hooks/**)`; `--check` on a consumer file carrying it beside the
  ask rule reports `UNWIRED` naming `1 retired Edit deny rule(s)`, and `--write` removes
  it in place, keeps the ask rule and everything else, and a second write reports `kept`.
  `self/tests/hook-wiring.sh` has the case (`retired-edit`), and `self/gate.sh` is green
  with it. The `--self` generated file is byte-identical to before (the retired string
  never appeared in it).
- `README.md`'s entries for `CONVENTIONS.md`, `sync-plans.sh` and `hooks/`, and
  `hooks/README.md` → "The deny rules" and "What `wire-settings.py` will and won't
  touch", describe the retired Edit deny; the install section's root-`CLAUDE.md` example
  says what does not belong in that file.

## Verdict
