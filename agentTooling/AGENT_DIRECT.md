# AGENT_DIRECT.md

Instructions for the **direct one-shot**: one opus implementer that builds a feature
straight from its spec, tests first, gates it green, commits, and terminates — no plan
corpus, no batch. The counterpart to `AGENT_PLANS.md`; a coordinator points a brief at
this file the way it points an architect at that one. Nothing here changes either the
plan workflow or the runners.

## When it is the right choice

Measured, not asserted (`harness/EXPERIMENTS.md` → "What the pilots established", round 3:
five features across four repos, each built both ways, n=1 per cell). The one-shot's
cost tracks the size of the diff — about $4.50 at 400 lines, about $21 at 1,800 —
while the plan workflow's architect barely moves with size and its sonnet/haiku build
and verify stay in a narrow band. So:

- **Under roughly a thousand lines of diff → direct.** Cheaper or tied, 2–4× faster to
  PR, and the tree was picked on design every time: one context makes the more
  coherent calls (a vocabulary shared by core and wire, honest wire shapes).
- **Above that → plans** (`AGENT_PLANS.md`). The margin widens with size.
- **The foundation or seam module, or anywhere the hour matters more than $5–10 →
  direct** regardless of size.
- **Either way, an independent review afterwards.** Both arms' remaining defects were
  found there, never by the builder.

A tie within about 15% is noise at n=1. When in doubt on size, count the files the
spec touches and the tests they need; three layers of small edits are still small.

## What the plan workflow gives you that this must replace

The one thing the plan workflow reliably added *before* any review was **test
surface**: its acceptance-tests-first plan wrote black-box assertions the one-shot never
did (the nothing-stored snapshot, the dry-run-plus-store case, the redirect case), and
the review then had to ask the direct tree for them. That is the transferable half of
the doctrine, and it is step 2 below, before any implementation, rather than a
suggestion in a brief.

What it does not replace, and does not need to: the build/verify split (the implementer
has bash and runs what it wrote), the level gates (one context has no seams to mock),
the resume machinery (a checkpoint the implementer keeps replaces it — see
"Checkpoint and resume" below).

## The brief

Every direct brief carries these, in this order. Point at files and sections; do not
paste the spec.

1. **`feature: <repo>/<slug>`** on the first line, before anything else
   (`ORCHESTRATION.md`) — what cost capture reads.
2. **Where.** The worktree `feature-start.sh` made for this feature — `<repo>-<slug>`,
   on branch `<slug>`, off the base its manifest records (`LIFECYCLE.md`). Name it by
   absolute path, and every command in absolute paths under it; the primary checkout is
   not it.
3. **Read, in this order.** The spec sections (or the triage decisions) this feature
   implements — pinned names, used exactly; `CLAUDE.md` (which imports
   `CONVENTIONS.md`: the README rules and named constants are binding); the repo's
   `plans/PROJECT_FACTS.md`; the READMEs of the folders it will touch, before touching
   them. READMEs are the index — follow them rather than grepping.
4. **The facts.** What `AGENT_PLANS.md` → "Pin the facts executors would otherwise
   hunt for" pins for a plan, pinned here for the implementer: the gate command and
   how long it takes, test file conventions and where fixtures live, the shapes it
   must keep, anything decided already. Decisions the spec settles are not reopened.
5. **The procedure** (next section), by reference to this file plus whatever this
   feature adds to it.
6. **The finish.** Commit on the branch; do not push or open the PR — the review pass
   does that (see "The review is not optional").
7. **The report.** Terse: the gate's verdict line and counts, files added/changed,
   each design call and where it is recorded, anything in scope left undone and why.

## The procedure

1. **Slice it, and write the checkpoint.** After the reading list, decide the slices —
   the acceptance tests, then the pieces of the build in the order they will land,
   then the READMEs — and write them to `plans/features/<slug>/CHECKPOINT.md` (next
   section) before the first edit. The decomposition is the one thing a kill destroys
   that the tree cannot give back.
2. **Acceptance tests first.** Before any implementation, write the black-box tests
   the spec implies: through the real routes, CLI and disk where the repo has that
   pattern, against the contract fixtures where it has those, never against
   internals. They are red now and stay red until the end; that is the point. A
   reviewer reading them should be able to tell what the feature promises without
   opening the implementation. Commit them on their own — `<slug>: acceptance tests`
   — so the branch itself shows they came first.
3. **Build**, slice by slice, ticking each in the checkpoint as it lands. To the
   repo's quality bar: tests mirror the source tree and its naming, every new test
   file gets its row in the tests README, named constants for every magic value,
   READMEs amended for every folder touched — field lists for cross-module shapes,
   contracts an import line does not show.
4. **Decide everything the spec leaves open.** Record each ruling where a reader will
   find it — the README it affects, and `plans/features/<slug>/NOTES.md`, the same file
   an architect writes: rulings with a one-line rationale each, deviations from the
   spec and why, open questions. As each is made, not at the end: a ruling that lives
   only in the implementer's head dies with it. Never stop to ask; nobody is
   listening, and a run that stalls on a question is a failed run.
5. **Gate to green.** Run the repo's `plans/gate.sh` and read its report; fix; re-run
   only the checks that failed, then the whole gate once more at the end. A SKIPPED
   check is not green. Do not paper over a red check by weakening its test. The
   verdict line goes in the checkpoint.
6. **Commit.** On the feature's branch, everything, including `NOTES.md`,
   `CHECKPOINT.md` at status `committed`, and the feature manifest. Never mutate
   repo-wide VCS state — no stash, checkout, reset, clean, branch switch or rebase.
7. **Report and terminate.**

## Checkpoint and resume

The plan workflow resumes for free: a killed batch leaves its plan in `inprogress/`
with a harness-written log beside it, and the next run picks it up (`RUNNER.md` → "How
resume works"). A one-shot has no plans, so the runner has nothing to write, and what a
kill destroys is the implementer's own decomposition — what it meant to do, in what
order, how far it got — which the tree cannot give back. The implementer keeps that
itself, in `plans/features/<slug>/CHECKPOINT.md`:

    # Checkpoint: <slug>

    status: implementing        planned | tests-written | implementing | gating | committed
    updated: 2026-09-02T12:40:00Z
    gate: not run yet           or the last verdict line, verbatim

    ## Slices
    - [x] acceptance tests — <test files> (<N> red, expected)
    - [x] 1. <slice>
    - [ ] 2. <slice> — in progress: <what is half-done>
    - [ ] 3. <slice>
    - [ ] READMEs and tests-README rows for every folder touched

    ## Learned
    - <a fact about the tree a cold successor would otherwise re-derive>

    ## Resume
    - <exact commands: tree state, the red tests to run, the gate>

Written before the first edit, once the slices are decided; rewritten whole at every
milestone — tests written, each slice landed, the first gate run, the commit — and
never more than one slice behind. Under about forty lines, and only what the tree does
not show: `git status` says which files changed, the checkpoint says why and what is
next. Rulings are not repeated here; they go to `NOTES.md` as they are made (step 4).
Committed with the rest at status `committed`, as the record of the build's shape —
the direct feature's `auto/complete/`.

**`updated:` comes from `date -u '+%Y-%m-%dT%H:%M:%SZ'`, never from memory.** A guessed
timestamp is worse than none: it is the one line a cold successor uses to judge how
stale the rest of the file is.

**Stamp the same milestone into `timing.jsonl`**, in the same breath as the rewrite:

```bash
./agentTooling/stamp-timing.sh <slug> checkpoint status=<status>
```

The runners stamp their own boundaries as they go, which is how a planned feature's
Time table splits planning from build from verify. A direct build has no runner until
the review pass, so without these its whole span is one undivided figure and the report
cannot say what the hours went to. With them, `analysis/report.py` renders
tests-first (`planned` → `tests-written`), the build (`tests-written` → `gating`) and
the gate (`gating` → `committed`) as sub-rows under the build row. Each stamp is one
append and costs nothing; a skipped one is a span nobody can reconstruct afterwards,
since the checkpoint file itself is rewritten whole and keeps no history.

**The context is never resumed.** A dead implementer's context is the resume cost
`ORCHESTRATION.md` measures and avoids; what survives is on disk. When one dies — a
usage limit, a kill, a session that ended — the coordinator reads the branch and the
checkpoint first: `status: committed` with the commit present needs no resume at all,
and the review pass is next. Otherwise it spawns a fresh implementer with the **same
brief** plus this paragraph, adapted:

> Resume. A previous implementer died. Before anything else read
> `plans/features/<slug>/CHECKPOINT.md` and `NOTES.md`, then `git status --short`,
> `git log --oneline <base>..HEAD` and `git diff --stat`. A ticked slice is a hint,
> not a fact: run the tests the checkpoint names and check each ticked slice on disk
> before trusting it. Continue from the first unticked slice, keep the checkpoint
> current, and finish the procedure from there. If there is no checkpoint, the tree
> is the only record: read it, write one, then continue.

That is the hint-not-truth rule the runners apply to a `.progress.md` log. Pin the
second implementer's agent id beside the first in the manifest's `subagents`; the
build row in the report is their sum (see "Cost and time").

**Model: opus.** This is the judgment case. A feature small enough that sonnet would do
is one where `AGENT_PLANS.md` step 4 already says to do it by hand.

## The review is not optional

An independent review from a brief written **before** the build, from the spec — never
from the implementer's report or by the implementer. Author it as a review plan
(`AGENT_PLANS.md` → "Review plans": what the feature was supposed to do, the base to
diff against, the contracts to hold it to, "no findings" a legitimate verdict) in
`plans/features/<slug>/review/incomplete/NN-review-opus.md`, and run
`./agentTooling/run-review.sh <slug>` once the implementer has committed. On a clean
pass the runner calls `plans/pr.sh`, which opens the PR with the verdict as its body —
the same PR the plan workflow would have opened. Local findings are fixed there;
structural ones are a rework one-shot briefed with the findings file only, or the next
feature.

## The feature directory

`feature-start.sh --method direct` writes it and commits it (`LIFECYCLE.md`): the
manifest, and `review/` holding the stub brief for the pass above. What the build adds
is the implementer's agent id under `subagents`, and `NOTES.md` and `CHECKPOINT.md` from
the implementer, both written as the build goes; `timing.jsonl` comes from the review
runner.

**Cost and time.** The implementer is a delegate (or a `claude -p` session on the
branch), so `capture_planning.py` freezes its dollars and its transcript span into
`planning.json` exactly as it would an architect's. `method: "direct"` is what tells
`analysis/report.py` the difference: it files everything in that file under **build**
— the row reads "build: implementer" — and the review plan's `usage.json` under review.
Planning proper, the coordinator's minutes on the two briefs, is not separated out.
Pin the implementer's id while its transcript exists (`capture_planning.py
--list-subagents --unclaimed`), and a rework one-shot's the same way. A feature that
was resumed pins every implementer that touched it; the build row is their sum.

## Checklist before spawning

`feature-start.sh` is the checklist (`LIFECYCLE.md` → step 2): it refuses a base whose
gate is not green, and it writes the worktree, the manifest with `session_window.from`
set for the pins to go in, and the review-brief stub that `run-review.sh` refuses to run
until a real brief replaces it. What no script checks is the reading list: the READMEs
of the folders in scope have to exist and be current, or the one-shot spends its context
re-deriving them.
