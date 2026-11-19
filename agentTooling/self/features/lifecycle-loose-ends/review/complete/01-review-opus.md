# 01 — review: lifecycle-loose-ends

Review the diff against the spec below, never against the builder's account. "No findings"
is a legitimate verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

Four lifecycle snags, fixed in code and docs:

1. **Review-brief stub.** `feature-start.sh`'s last lines name the review-brief file to fill
   and the sections it needs; `templates/plans/ORCHESTRATOR_BRIEF.md` tells the implementer
   to fill it before the build. `run-review.sh` still refuses an unfilled stub.
2. **Blank feature README.** `feature-close.sh` refuses, before any PR, a feature README
   still matching `templates/plans/features/TEMPLATE.md` (placeholders or template-identical
   sections), naming the sections to fill. A `--method hand` manifest (prose: goal, one
   review row, optional exclusions) passes when filled.
3. **Unreachable pins.** `harness_resolve_commit` falls back: sha fetch, then one deepen of a
   shallow clone, then one fetch of `refs/pull/*` (into FETCH_HEAD, no ref created), then
   fails naming the sha and what was tried. Applied to the arm pin's agentTooling lookup and
   the spec commit too. `check-fixture.sh` warns when a pin is reachable only via a PR ref.
   No local branch ref is ever created or moved.
4. **Never move bytes through a model.** ORCHESTRATION.md and the orchestrator brief say:
   copy files between repos with git, inside the session owning the destination, never by
   retyping/pasting/base64 in a prompt.

Out of scope: branch-deletion permissions, harness methods.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Item 1: the start's final lines name `review/incomplete/01-review-opus.md` and list its
  sections; the brief template has a fill-before-build step; run-review's refusal intact.
- Item 2: a template-identical README is refused naming sections; a filled one passes; a
  hand-pull-shaped manifest passes; refusal happens before the PR/any write.
- Item 3: tests against a local bare repo cover a commit beyond a shallow clone's depth and
  a commit only on `refs/pull/*`; the failure message names the sha and what was tried; no
  ref is created (`for-each-ref` unchanged).
- Item 4: rule present in both docs; the brief template stays within its 80-line test cap.
- Gate green; touched folders' READMEs and LIFECYCLE.md describe the new behaviour; every
  new tracked file is indexed in its folder README; no magic literals (CONVENTIONS.md →
  "Named constants").

## Verdict
