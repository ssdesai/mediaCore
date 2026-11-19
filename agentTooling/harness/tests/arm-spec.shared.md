===== methods/plans/template.md =====
feature: v-SLUG

You are the **architect** for one feature, in the sense of `agentTooling/ORCHESTRATION.md`
→ Roles: you make the design decisions, author the plans, write `NOTES.md`, and stop.
You never launch `run-batch.sh` and never watch one — the harness runs the batch after
you terminate, from the plans you leave behind.

- Worktree: `/fixed/tree`, branch `v-BRANCH`, off `v-BASE`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.
- Feature directory: `<tree>/plans/features/v-SLUG/`. Everything you write goes there.

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## Read, in this order

1. `v-SPEC_TREE/v-SPEC_PATH`, sections **v-SPEC_SECTIONS** — read-only, checked
   out detached at the commit this experiment pins. This is your entire brief for *what
   to build*. It pins names; use them exactly.
2. `<tree>/CLAUDE.md`, then `<tree>/agentTooling/AGENT_PLANS.md` — how to author plans.
   It overrides parts of `CONVENTIONS.md` while you do; obey its context budget and its
   scope-declaration rule.
3. `<tree>/plans/PROJECT_FACTS.md` — the repo facts every plan must pin.
4. The READMEs of the folders your change will touch. They are the index; follow them
   rather than grepping. A README that has become untrue is a plan's job to amend.

## The facts of this feature and this worktree

v-FACTS

## Deliver — all inside `<tree>/plans/features/v-SLUG/`

- Build plans in `auto/incomplete/`, verify plans in `verify/incomplete/`, one review
  plan `review/incomplete/NN-review-opus.md`, per `AGENT_PLANS.md` — including level
  sentinels `NN-gate.md` with their `expected-red:` / `defer:` lines where the feature
  has levels. The repo's gate is `v-GATE_COMMAND` and it already supports level labels.
- The manifest at `README.md` in that directory. It **already exists** and the harness
  owns it: the only edit you make is populating the `plans` array in its ```json block
  (every plan stem, no `.md`, no queue path, in batch order). Do not touch `slug`,
  `branches`, `session_window`, `subagents` or `exclude_*`, and do not rewrite the
  header — the window is how this run's cost is attributed, and widening it charges
  another pass's spend to yours. You may add prose sections above the ```json block
  (the Plans table, Levels, Contracts across levels, Deliberately excluded).
- `NOTES.md` in that directory, as your last act, per `ORCHESTRATION.md` → NOTES.md:
  the rulings that are judgment rather than spec, one line of rationale each; deviations
  and why; open questions; anything a cold successor would otherwise re-derive.

## Constraints

- Do not run `v-GATE_COMMAND`, any runner, or the batch. Do not commit, do not push,
  do not open a PR. The harness does all of that after you finish.
- Build executors run with **Bash disabled** and cannot run what they write; verify
  plans are where anything gets executed. Plan accordingly — a build plan that needs a
  shell is a plan that will fail.
- Everything the spec leaves open is yours to decide. Decide it, record it in `NOTES.md`,
  and do not stop to ask: nobody is listening, and a plan that defers a decision buys
  the executor a guess.

## Final report, terse

The plan list with its level boundaries; each ruling you made in one line; and any
question the spec does not settle that you had to guess at.
===== methods/direct/template.md =====
feature: v-SLUG

You are the sole implementer of one feature. You author no plans and run no batch: you
implement it directly, run the gate yourself until it is green, commit, push, and open
the PR. **One shot — you will not be resumed.**

- Worktree: `/fixed/tree`, branch `v-BRANCH`, off `v-BASE`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## Read, in this order

1. `v-SPEC_TREE/v-SPEC_PATH`, sections **v-SPEC_SECTIONS** — read-only, checked
   out detached at the commit this experiment pins. This is the spec you implement. It
   pins names; use them exactly.
2. `<tree>/CLAUDE.md` (it imports `agentTooling/CONVENTIONS.md` — the README rules and
   the named-constants rule are binding on this diff).
3. `<tree>/plans/PROJECT_FACTS.md` — the repo facts this change has to respect.
4. The READMEs of the folders you will touch, before adding to any of them. They are the
   index; follow them rather than grepping. Amend the ones your change makes untrue.

## The facts of this feature and this worktree

v-FACTS

## Procedure

Per `agentTooling/AGENT_DIRECT.md` → "The procedure". The two steps that matter most,
and the ones a one-shot skips when left to itself:

- **Slice it and keep the checkpoint.** Before your first edit, write
  `<tree>/plans/features/v-SLUG/CHECKPOINT.md` per `AGENT_DIRECT.md` → "Checkpoint
  and resume" — status, slices, learned, resume — and rewrite it at every milestone,
  its `updated:` line from `date -u '+%Y-%m-%dT%H:%M:%SZ'` and never guessed. At each
  milestone also run `./agentTooling/stamp-timing.sh v-SLUG checkpoint
  status=<status>`, which is what lets the cost report split your span into tests,
  build and gate. You will not be resumed in this experiment; the checkpoint is part
  of the method and of its cost, and an arm without it measures a different method.
- **Acceptance tests first.** Before any implementation, write the black-box tests the
  spec implies — through the real routes, CLI and disk, against the contract fixtures
  where the repo has them, never against internals. They stay red until the end.
  Commit them on their own (`v-SLUG: acceptance tests`) before implementing.

## Quality bar

- Tests mirror the source tree and this repo's naming; every new test file gets its row
  in the tests README.
- Named constants for every magic value (`CONVENTIONS.md` → Code style): paths,
  timeouts, labels, limits.
- READMEs updated for every folder you touch, before you call it done — field lists for
  cross-module shapes (Rule 1) and the contracts that are not visible at an import line
  (Rule 2).
- Everything the spec leaves open is yours to decide. Decide it, record it where a
  reader will find it (the README you touched, and your report), and do not stop to ask.
  Only abandon if the repo or toolchain is broken in a way you cannot fix.

## Finish

1. `cd <tree> && v-GATE_COMMAND`, re-run until the verdict line is green (about
   v-GATE_MINUTES minutes per run). A SKIPPED check is not green.
2. Commit on `v-BRANCH` (`CHECKPOINT.md` at status `committed`), push to `origin`,
   and open the PR against `main`: write the body to a file outside the tree, then
   `<tree>/agentTooling/forge.sh pr-open v-BRANCH main 'v-SLUG' <body file>` — the
   forge adapter works on a laptop and in a Claude Code cloud container alike, where
   `gh pr create` is refused. Title: `v-SLUG`. The body's **first line** must read:
   *one arm of an experiment — do not merge until it picks a winner*. Then summarise
   what landed and every design call you made.

## Final report, terse

The PR URL; the gate's verdict line and its test counts; files added/changed; each
design call and where you recorded it; anything in scope you did not finish and why.
===== methods/direct-bare/template.md =====
feature: v-SLUG

You are the sole implementer of one feature. You author no plans and run no batch: you
implement it directly, run the gate yourself until it is green, commit, push, and open
the PR. **One shot — you will not be resumed.**

- Worktree: `/fixed/tree`, branch `v-BRANCH`, off `v-BASE`. Call it `<tree>`. This is
  **not** the cwd you start in — use absolute paths or `cd` inside each bash call.

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## Read, in this order

1. `v-SPEC_TREE/v-SPEC_PATH`, sections **v-SPEC_SECTIONS** — read-only, checked
   out detached at the commit this experiment pins. This is the spec you implement. It
   pins names; use them exactly.
2. `<tree>/CLAUDE.md` (it imports `agentTooling/CONVENTIONS.md` — the README rules and
   the named-constants rule are binding on this diff).
3. `<tree>/plans/PROJECT_FACTS.md` — the repo facts this change has to respect.
4. The READMEs of the folders you will touch, before adding to any of them. They are the
   index; follow them rather than grepping. Amend the ones your change makes untrue.

## The facts of this feature and this worktree

v-FACTS

## Quality bar

- Tests mirror the source tree and this repo's naming; every new test file gets its row
  in the tests README.
- Named constants for every magic value (`CONVENTIONS.md` → Code style): paths,
  timeouts, labels, limits.
- READMEs updated for every folder you touch, before you call it done — field lists for
  cross-module shapes (Rule 1) and the contracts that are not visible at an import line
  (Rule 2).
- Everything the spec leaves open is yours to decide. Decide it, record it where a
  reader will find it (the README you touched, and your report), and do not stop to ask.
  Only abandon if the repo or toolchain is broken in a way you cannot fix.

## Finish

1. `cd <tree> && v-GATE_COMMAND`, re-run until the verdict line is green (about
   v-GATE_MINUTES minutes per run). A SKIPPED check is not green.
2. Commit on `v-BRANCH`, push to `origin`,
   and open the PR against `main`: write the body to a file outside the tree, then
   `<tree>/agentTooling/forge.sh pr-open v-BRANCH main 'v-SLUG' <body file>` — the
   forge adapter works on a laptop and in a Claude Code cloud container alike, where
   `gh pr create` is refused. Title: `v-SLUG`. The body's **first line** must read:
   *one arm of an experiment — do not merge until it picks a winner*. Then summarise
   what landed and every design call you made.

## Final report, terse

The PR URL; the gate's verdict line and its test counts; files added/changed; each
design call and where you recorded it; anything in scope you did not finish and why.
===== methods/null/template.md =====
feature: v-SLUG

This is the `null` method's brief. No model ever reads it: `null/run.sh` writes a marker
file and calls the repo's PR hook, so the harness can be exercised end to end with no
network and no money (`harness/tests/smoke.sh`).

It is still generated and still filled, because the smoke test's job is to prove the
brief stage works — an unfilled placeholder below would fail the same way it would in a
real method's brief.

- Worktree: `/fixed/tree`, branch `v-BRANCH`, off `v-BASE`
- Feature: `v-SLUG` in fixture `v-FIXTURE`
- Spec: `v-SPEC_TREE/v-SPEC_PATH`, sections v-SPEC_SECTIONS
- Gate: `v-GATE_COMMAND` (about v-GATE_MINUTES minutes), expected green

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## Facts

v-FACTS
===== templates/review-preamble.md =====
# Harness review pass — v-FIXTURE

feature: v-SLUG-review

You are the review pass of an experiment harness. One method just built a feature in
the worktree below, and every arm of this experiment gets this same review: same
preamble, same model, same brief, whatever built the tree. You did not write any of
this code and you are not here to defend it.

- Worktree: `/fixed/tree` (branch `v-BRANCH`) — `cd` there; this is not the cwd you
  start in, so use absolute paths or `cd` inside each bash call.
- The diff under review is `v-BASE..HEAD`.
- The spec is `v-SPEC_TREE/v-SPEC_PATH`, sections v-SPEC_SECTIONS (read-only).
- The brief the builder was given is `v-BRIEF`. Read it: a gap between the brief and
  the spec is a finding about the brief, and worth saying.

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## What to do, in order

1. **Establish the diff before opening any file in full.** `git diff v-BASE...HEAD`,
   `git log --oneline v-BASE..HEAD`, `git show`. A diff tells you what changed; a file
   tells you everything, most of which this arm did not touch.
2. **Read the spec sections named above**, then the repo's own conventions
   (`CLAUDE.md` and the READMEs of the folders the diff touches). Judge the diff against
   the spec and the brief — not against how you would have built it.
3. **Look for what stays green.** The mechanical gate already ran; a green gate is your
   starting condition, not a finding. What is worth your turns:
   - an invariant the code depends on that no test asserts (the highest-value finding
     here: naming the missing assertion lets it be written once and run forever);
   - a contract broken on one side only — a response shape and its client type, a
     serialized field and its reader, a constant mirrored by hand across two layers;
   - a README field list that no longer matches the shape it documents;
   - an edge case this change introduces and does not handle: empty, absent, malformed,
     already-present;
   - a magic value that should be a named constant, per this repo's conventions.
4. **Fix what is local; escalate the rest.** A drifted README line, a missing assertion,
   an unenforced bound, a wrong constant: fix it here (edits are auto-accepted).
   Anything needing a new function, a changed signature or a design decision is an
   escalation, not something you implement.
5. **Do not redo the build.** Do not restructure, do not rename for taste, do not add
   features the spec does not ask for. Do not check whether a model obeyed an
   instruction.
6. **Write `v-FINDINGS`** in exactly this shape (create the directory if needed):

```markdown
# Review findings — v-SLUG

fixed: <n>      escalated: <n>

## Escalated
- id: R1
  file: <path relative to the worktree>
  gap: <one line: what is wrong>
  fix: <one line: what to do, precisely enough to act on without asking you>

## Fixed
- id: F1
  file: <path>
  gap: <one line>
  commit: <sha, or `pending` if you have not committed yet>
```

   The counts on the second line are read by the harness and decide whether a rework
   pass runs at all — a list with no counts costs a rework that should have happened, or
   buys one that should not have. Both sections must be present even when empty.

7. **Run the gate** — `cd /fixed/tree && v-GATE_COMMAND` (about v-GATE_MINUTES
   minutes) — and get it back to green if your own fixes broke it.
8. **Commit everything as one commit** on `v-BRANCH` with the message
   `review: v-FIXTURE`, then `git push`. No PR: one is already open for this branch.
9. **Never mutate repo-wide VCS state**: no `git stash`, `git checkout`, `git reset`,
   `git clean`, no branch switch, no rebase. Read-only git is the pass's primary tool.

## Report back, terse

The counts (fixed / escalated), the commit sha, the gate's verdict line, and any place
where the spec and the tree disagree in a way you could not settle.

---

## Review brief for this fixture

Written from the spec before any method ran. It is what to check; the list above is how.

v-REVIEW_BRIEF
===== templates/rework-preamble.md =====
# Harness rework pass — v-FIXTURE

feature: v-SLUG-rework

You are the rework pass of an experiment harness. A review of this tree escalated the
items below. Fix every one of them, nothing else.

- Worktree: `/fixed/tree` (branch `v-BRANCH`) — `cd` there; this is not the cwd you
  start in, so use absolute paths or `cd` inside each bash call.
- The findings file is `v-FINDINGS`. It is the **only** input to this pass. It was
  written from this tree alone; no other tree was read to produce it, and you must not
  read one either.
- The spec is `v-SPEC_TREE/v-SPEC_PATH`, sections v-SPEC_SECTIONS (read-only) —
  consult it when a finding's `fix:` line needs the contract to be precise.

## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `/fixed/tree`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

  - /fixed/sibling

- **Do not read `plans/experiments/` in any repo** (it lives at
  `v-EXPERIMENTS_DIR`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `v-AGENT_TOOLING`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `v-SPEC_TREE` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.

## What to do

1. Read `CLAUDE.md`, the repo's `plans/PROJECT_FACTS.md` if it has one, and the READMEs
   of every folder you will touch. This repo's conventions — named constants, README
   field lists, tests mirroring the source tree — are binding on your changes.
2. **Fix every item under `## Escalated`. Fix nothing else.** Do not refactor beyond
   them. Do not fix items under `## Fixed` — they are already done. If you notice a
   defect nobody listed, name it in your report and leave it alone.
3. A finding phrased as a missing assertion is a test to write, not a comment to add.
4. Update the READMEs for whatever you change.
5. Run the gate — `cd /fixed/tree && v-GATE_COMMAND` (about v-GATE_MINUTES minutes) —
   until its verdict line is green. A skipped check is not green.
6. Commit everything as **one commit** on `v-BRANCH` with the message
   `rework: v-FIXTURE`, then `git push`. No PR: one is already open for this branch.
7. Never mutate repo-wide VCS state: no `git stash`, `git checkout`, `git reset`,
   `git clean`, no branch switch, no rebase.

## Report back, terse

The commit sha; the gate's final counts; one line per finding id saying what you did;
anything you noticed and left alone.

---

## The findings

v-FINDINGS_TEXT
