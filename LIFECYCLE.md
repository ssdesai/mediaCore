# Lifecycle

The seven steps a feature runs through, from an instruction to a costed merge, and the
script or doc that governs each. This file says *when* to run *what*. It does not
restate the constraints the scripts already refuse on — a rule written in two places
drifts in one of them.

Everything derives from the slug. For a feature with slug `S` in a repo whose primary
checkout is `R`:

    slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
    branch    S
    worktree  R-S                          a sibling directory of the primary checkout

The primary checkout stays on `main` and is used only to start and close features.

## 1. Route

Decide the method first, from the size of the diff the spec implies: under roughly a
thousand lines, **direct** — one opus implementer, `AGENT_DIRECT.md`; above it,
**plans** — an architect and the runners, `AGENT_PLANS.md`; when the coordinator is
going to type it itself, **hand**. The measurements behind that threshold, and the
cases that override it either way, are in `AGENT_DIRECT.md` → "When it is the right
choice". The answer becomes `--method` in the next step and the manifest's `method`
field, which is what tells `analysis/report.py` whether `planning.json` holds planning
or the build.

## 2. Start

    ./agentTooling/feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>]

From the primary checkout, once per feature. It creates branch `S` and worktree `R-S`,
runs `plans/worktree-setup.sh` and the repo's gate inside the new worktree, writes the
feature directory — the manifest with its fence filled, and a review-brief stub carrying
`@@TODO@@` — commits it as `S: start`, and pins the session that ran it. `--base` is for
a feature stacked on one that has not merged; `--no-gate`, `--no-pin` and
`--session <id>` are for the cases that need them. Read the "Next" lines it prints:
they are steps 3 and 6 below with the paths filled in.

## 3. Brief

Two things before any delegate is spawned. **Replace the `@@TODO@@` stub** in
`review/incomplete/NN-review-opus.md` with a real review brief, written from the spec
and never from a builder's report — `AGENT_PLANS.md` → "Review plans" says what it must
hold. **Fill the manifest's prose**: the goal, the plan table, what was deliberately
excluded. `check-plans.sh [--self] <slug>` says whether the stub was replaced and the fence and plan files are well-formed, and `run-batch.sh` runs it before spending anything. Then launch the coordinator session inside `R-S` and write the delegate's
brief per `ORCHESTRATION.md` → Rules, or `AGENT_DIRECT.md` → "The brief" for a direct
implementer.

## 4. Build

**Direct**: one opus implementer follows `AGENT_DIRECT.md` → "The procedure" —
acceptance tests first, `CHECKPOINT.md` and `NOTES.md` kept current as it goes, gate to
green, commit. **Plans**: the architect authors into `auto/`, `verify/` and `review/`
per `AGENT_PLANS.md`, then `./agentTooling/run-batch.sh <slug>` drains them
(`RUNNER.md`). `run-batch.sh` lints the corpus first (`check-plans.sh`) and stops on a failure. **Hand**: the coordinator builds it itself and writes `NOTES.md` as it
goes. Whichever it is, the work happens in `R-S`. A delegate spawned by the coordinator
inside `R-S` inherits its branch and is claimed with it; one spawned from anywhere else
is pinned in the manifest's `subagents` while its transcript still exists.

## 5. Review and PR

    ./agentTooling/run-review.sh [--self] <slug>

The pass every method ends in, and the one thing that is never the builder's: an
independent executor reads the diff against the manifest's `base` and writes its verdict
to `plans/review-report.md`. On a clean pass the runner calls the repo-owned
`plans/pr.sh`, which commits what the pass left, pushes `S`, and opens the PR against
that base with the verdict as its body. Local findings are fixed in the pass;
structural ones are a rework brief or the next feature.

## 6. Close

    ./agentTooling/feature-close.sh [--self] <slug> [--recapture] [--keep-worktree] [--no-push]

By the human, from the primary checkout, after the PR has merged **and** every session
the feature cost has ended: a capture prices what a transcript holds at that moment, so
a session still running is under-counted, and a window stamped shut drops any session
that starts after it. It pulls `main`, carries home the trailing timing stamps the last
pass wrote after its PR hook had already committed — `pr_opened`, with the PR URL, and
`pass_end` — captures
and reports the cost, prints every session and subagent the capture claimed — id, how it
was selected, where it was launched, cost — so the number can be read before it is
quoted, stamps `session_window.to`, commits the cost records, and removes the worktree
and the branch. No model is involved.

## 7. Sweep and propagate

Weekly, `./agentTooling/sweep.sh` (and `./sweep.sh --self` here) runs the cadence in order — backfill the usage sidecars, recover killed attempts, `capture_planning.py
--all`, `report.py --all`. That pass is what catches the feature closed before a
delegate was pinned and the batch whose event stream was never converted, both of which
read as a correct number until someone looks. A feature whose window is still open is skipped as in flight — its close captures it. It prints the unclaimed delegates and sessions. Then propagate this directory's own changes: `./agentTooling/update.sh` in each consuming repo pulls this directory and runs `sync-plans.sh`, whose report names the repo-owned scripts that need a hand-merge (`README.md` → "Updating").

## The three rules

1. **A session is billed to the branch of the directory it was launched in**, at every
   message, whatever it `cd`s into afterwards. So the coordinator session is launched
   inside `R-S`. A session that began somewhere else — on `main`, before the feature
   existed — is claimed by pinning its id in the manifest's `sessions`, never by
   widening `branches`.
2. **Agents never create branches or worktrees.** No `git worktree add`, no
   `git checkout -b`, no `git branch`. `feature-start.sh` is the only way in — run from
   the primary checkout by the human, or by the planning session that will then be
   pinned as the feature's — and `feature-close.sh` the only way out, run by the human
   from the primary checkout with no model involved.
3. **The manifest's fence is written by the scripts, its prose by whoever authors the
   feature.** `feature-start.sh` fills the fence, `feature-close.sh` closes the window,
   and `analysis/manifest.py` is what edits it in between. An executor may correct the
   prose above it — a plan table that drifted, an exclusion that turned out wrong — and
   never the fence.
