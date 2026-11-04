Verdict: clean

# orchestrator-brief — review round 2

## What the rework was supposed to do

Round 1 escalated two items (`self/features/orchestrator-brief/escalations/01-review-opus.md`):

1. The brief template hardcoded `./feature-start.sh` and bare `CONVENTIONS.md` / `LIFECYCLE.md`. Those paths are wrong in a consuming repo, where the scripts live under `./agentTooling/`.
2. The list of generated stubs is kept by hand in three places (`sync-plans.sh` `GENERATED`, the `templates/README.md` table and `sync-check.sh` 1b's loop), and no test checked that the three agree.

## Whether it does

Yes.

- **Brief (`templates/plans/ORCHESTRATOR_BRIEF.md`)**
  - The authoring note explains `<tooling>`: `.` in agentTooling itself, `./agentTooling` in a consuming repo.
  - The start line and all three paths into the tooling directory now carry the `<tooling>/` prefix. That includes the second `LIFECYCLE.md` mention, in the Lifecycle section.
  - `CLAUDE.md` and `<PROJECT_FACTS path>` stay unprefixed.
  - The literal `--branch claude/<slug>` is still there, and the phrase "assigned branch" is not.
  - The file is 68 lines, under the 80-line limit.
- **B3** now asserts the `<tooling>/feature-start.sh …` start line.
- **B10** can actually fail. It removes the prefixed forms and then greps for any remaining bare path, so a bare `./feature-start.sh` or `CONVENTIONS.md` would trip it.
- **B11–B13**
  - B11 reads the names out of `GENERATED` and fails if it gets none.
  - B12 is anchored to the start of a `plans/<name>   generated` table row.
  - B13 is fixed in this pass; see below.
- **Style:** bash 3.2 compatible, no `set -e`, named constants.
- **Scope:** nothing under `.claude/`, `self/orchestrations/` or another feature's folder changed.
- **`self/tests/README.md`** describes B10–B13.

## Fixed in this pass

- **`self/tests/orchestrator-brief.sh` B13 could not fail for `README.md`.**
  - The problem: `^for rel in .*README.md` also matches `interactive/README.md`. If someone removed the bare `README.md` from sync-check's loop, which is exactly what this check is meant to catch, the check would still pass. The dots were also unescaped regex wildcards.
  - The fix: B12 and B13 now escape the dots, and B13 matches each name only as a whole word, so it must be preceded by a space and followed by a space or `;`.
  - Verified: the test file passes on the real checkout, and a scratch check confirmed the tightened pattern fails on a loop line that is missing the bare `README.md`.
- **`self/tests/README.md`:** the entry now says B13 matches whole words.

## Escalated to the next round

None.
