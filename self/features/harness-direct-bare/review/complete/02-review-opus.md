# 02 — review: harness-direct-bare (round 2)

Re-review after round 1 escalated one finding. "No findings" is a legitimate verdict
(AGENT_PLANS.md → "Review plans"). Round 1's content findings (template diff, run.sh,
pair test, docs) were judged correct; do not redo them except where this round's diff
touches them.

## What the feature was supposed to do

Add `direct-bare`, the control arm for measuring what `direct`'s procedure steps cost: its
brief is `direct`'s with exactly the `## Procedure` section and the
``(`CHECKPOINT.md` at status `committed`)`` parenthetical removed, guarded by a gate test.

Round 1 found that the hyphenated name made the cell branch `exportStoreDirect-bare`,
breaking SPEC §4's bare-camelCase rule. The decision (from the orchestrator): keep the
method name `direct-bare`, and make the branch builder camelCase a hyphenated method name
(`direct-bare` → `DirectBare`, branch e.g. `exportStoreDirectBare2`), minimally: the one
builder, a test, and the docs of the `<stem><Method><Arm><n>` shape. The row's `method`
field stays the directory name.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The round-2 change is the last
`harness-direct-bare:` commit that touches `harness/lib.sh`.

## Contracts to hold it to

- `harness_capitalise` / `harness_branch_name` in `harness/lib.sh`: hyphenated names
  camelCase correctly (including three parts and a leading/trailing hyphen not crashing),
  non-hyphenated names and arm labels behave exactly as before, and it works in bash 3.2
  (no `${x^}`, no associative arrays). Check every caller (`run.sh`, `new-experiment.sh`,
  `program-stages.sh`): nothing parses a branch back into a method, and the manifest's
  `method` is still the directory name.
- `self/tests/direct-bare-pair.sh` section 5 pins the names and the rule
  `^[a-z][A-Za-z0-9]*$` for every directory under `harness/methods/`; it would fail on the
  old builder.
- `harness/SPEC.md` §4, `harness/README.md` "Naming" and the tests README row describe
  the behaviour accurately.

## Verdict
