# 01 — review: orchestrator-brief

Read-only review of one feature's diff against its spec. "No findings" is a legitimate
verdict. First line of your report: `Verdict: clean` or `Verdict: escalated`.

## What the feature was supposed to do

An orchestrator session spawns one implementer per feature; the implementer has NO
assigned branch (detached HEAD at origin/main) and the start refuses without `--branch`.
Briefs written from memory said "the branch this session was assigned", which was untrue.
The feature:

1. adds `templates/plans/ORCHESTRATOR_BRIEF.md`, a template with sections Role, Branch,
   Read first, Lifecycle, Why, Items, Report; consistent `<placeholder>` markers; an
   authoring note; the literal start line
   `./feature-start.sh [--self] <slug> --method <method> --branch claude/<slug> [--orchestration <orchestration>]`;
   no use of the phrase "assigned branch"; under about 80 lines. It is registered as a
   generated stub in `sync-plans.sh` (`GENERATED`), so it reaches a consumer's `plans/`;
2. points at it from `LIFECYCLE.md` → "Orchestrator and implementer sessions" and, in a
   clause, `self/PROJECT_FACTS.md`;
3. adds `--branch` to `START_VALUE_FLAGS` in `analysis/routing.py`, with case R10a3 in
   `self/tests/routing-record.sh` and the `analysis/README.md` entry updated;
4. adds `self/tests/orchestrator-brief.sh`, recorded in `self/gate.sh` (the `bash -n`
   list and a `record` line);
5. updates every README the change makes wrong (`templates/README.md`,
   `templates/plans/README.md`, root `README.md`, `self/tests/README.md`,
   `self/PROJECT_FACTS.md`).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Adding a name to `GENERATED` must not break `sync-plans.sh --check`/write for a
  consumer (read `self/tests/sync-check.sh`, `generated-hand-edit.sh`); the template must
  need no `template-version` line, and `TEMPLATE_VERSIONS` must be unchanged.
- The template says the branch outright, tells the implementer a detached HEAD is
  expected, and contains none of "assigned branch" (any case).
- `--branch` handling: the slug is recovered whether `--branch <v>` comes before or
  after it; `--self`, `--method`, `--base`, `--session`, `--orchestration` still work.
- Nothing under `.claude/`, `self/orchestrations/` or another feature's folder changed;
  no model identifier in a committed file; bash 3.2 compatible, no `set -e`, named
  constants in the new script.
- Report anything the READMEs still state wrongly (for example "five generated stubs").

## Verdict
