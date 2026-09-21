# Lifecycle

The steps a feature runs through, from an instruction to a costed merge, and the
script or doc that governs each. This file says *when* to run *what*. It does not
restate the constraints the scripts already refuse on — a rule written in two places
drifts in one of them.

Everything derives from the slug. For a feature with slug `S` in a repo whose primary
checkout is `R`:

    slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
    branch    S
    worktree  R/.worktrees/S               inside the primary checkout, kept out of git

The primary checkout stays on `main`, and nothing is built in it: features are started
there, and a coordinator launched there may reach the worktree (rule 1 says how such a
session is claimed). The worktree sits inside `R` precisely so that a session launched in
`R` reaches it with no access outside its own folder. `feature-start.sh` keeps
`.worktrees/` out of git by appending `/.worktrees/` once to the common git dir's
`info/exclude`, which no repo tracks — so the primary's `git status` stays clean, and
nothing needs committing in a consuming repo. A feature started before this layout keeps
its sibling worktree `R-S`; the cost capture keeps `R-S` claimable for good, so a
`--recapture` of such a feature finds every session it found before.

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

    ./agentTooling/feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>] [--open]

From the primary checkout, once per feature. It prunes the feature worktrees whose
branches have merged into `origin/main` — the whole of post-merge teardown, and nothing
is committed or pushed by it — creates branch `S` and worktree
`R/.worktrees/S`, runs `plans/worktree-setup.sh` and the repo's gate inside the new worktree, writes the
feature directory — the manifest with its fence filled, and a review-brief stub carrying
`@@TODO@@` — and commits it as `S: start`.

**Start before you edit.** A session asked to change something runs this first and then
edits inside the worktree; nothing is written in the primary to be moved across later.

**A primary behind `origin/main` is updated, not started from.** The script runs from the
primary's copy of this directory but branches from `origin/<base>`, so a stale primary
would have old code write into a new branch. When `main` lags `origin/main` the script
fast-forwards it, starts nothing, and exits 3 with the command to run again — the rerun
is the new code. A primary off `main`, diverged, or with a local change in the way is
refused untouched.

**The session that runs it is a router, and a router is never pinned.** Its spend is
routing overhead, a category of its own: it opens several features and belongs to none of
them, so pinning it would bill one transcript to every feature it started. What goes into
the `S: start` commit instead is the **routing record**, written inside the feature
directory the commit already carries — `plans/features/S/routing.json` (`self/features/`
under `--self`) — derived from that session's own transcript by `analysis/routing.py`: the
link from router to feature, in git before the transcript can expire, and what
`report.py --all` reports the overhead from. A record of a link lives in the feature it
links, so a router that opens three features leaves three copies and no two features ever
write one path; the Routing table keeps the copy with the latest `captured_at`
(`analysis/README.md` → `routing.py`). Coordinate the feature from
a session launched **inside the worktree**, where rule 1 claims it by branch with no pin:
`--open` launches one through the repo-owned `plans/open-session.sh`.

`--base` is for a feature stacked on one that has not merged; `--no-gate`, `--pin` (the
opt-in for the rare case where the starting session really is this feature's coordinator)
and `--session <id>` are for the cases that need them, and `--no-pin` is still accepted
and does nothing. Read the "Next" lines it prints:
they are steps 3 to 7 below with the paths filled in.

## 3. Brief

Two things before any delegate is spawned. **Replace the `@@TODO@@` stub** in
`review/incomplete/NN-review-opus.md` with a real review brief, written from the spec
and never from a builder's report — `AGENT_PLANS.md` → "Review plans" says what it must
hold. **Fill the manifest's prose**: the goal, the plan table, what was deliberately
excluded. `check-plans.sh [--self] <slug>` says whether the stub was replaced and the fence and plan files are well-formed, and `run-batch.sh` runs it before spending anything. Then launch the coordinator session — inside the worktree, or in the primary checkout
under the pin step 2 wrote for it (rule 1) — and write the delegate's
brief per `ORCHESTRATION.md` → Rules, or `AGENT_DIRECT.md` → "The brief" for a direct
implementer.

## 4. Build

**Direct**: one opus implementer follows `AGENT_DIRECT.md` → "The procedure" —
acceptance tests first, `CHECKPOINT.md` and `NOTES.md` kept current as it goes, gate to
green, commit. **Plans**: the architect authors into `auto/`, `verify/` and `review/`
per `AGENT_PLANS.md`, then `./agentTooling/run-batch.sh <slug>` drains them
(`RUNNER.md`). `run-batch.sh` lints the corpus first (`check-plans.sh`) and stops on a failure. **Hand**: the coordinator builds it itself and writes `NOTES.md` as it
goes. Whichever it is, the work happens in the worktree. A delegate spawned by a
coordinator launched inside the worktree inherits its branch and is claimed with it; one
spawned from anywhere else — a coordinator in the primary checkout included — is pinned
in the manifest's `subagents` while its transcript still exists.

## 5. Review

    ./agentTooling/run-review.sh [--self] <slug>

The pass every method ends in, and the one thing that is never the builder's: an
independent executor reads the diff against the manifest's `base` and writes its verdict
to `plans/review-report.md`, whose **first line** is `Verdict: clean` or
`Verdict: escalated` (`AGENT_PLANS.md` → "Review plans"). Local findings are fixed in the
pass; structural ones are escalated.

**A feature is a sequence of rounds, and the review ends one.** A round is build → gate →
verify → review. The runner commits what the pass left, as `S: review round N` and only
when on a branch that is not this feature's base, stamps the round's `plan_end` with
`verdict=` and `head=` — the sha of that commit, the tree the verdict judged — and stops.
It opens no PR and runs no capture: those are step 6, and putting them behind the verdict
is what stops a rework happening behind a PR body and a frozen record that describe the
tree before it.

- **Clean** → step 6, which the runner names.
- **Escalated**, or a report whose first line carries no verdict the harness can read
  (which is treated as escalated — fail closed) → **nothing after the review runs.** The
  runner copies the report to `plans/features/S/escalations/<review-stem>.md`; that file
  is the rework brief. Route the rework like a build — direct, plans or by hand, at a
  cheaper model where the findings are precise — then queue the re-review as
  `review/incomplete/NN-review-<model>.md`, add its stem with `analysis/manifest.py
  [--self] S set-plans …`, and run the pass again. That is round N+1, and **every stamp
  carries its round**, which is what the report's Rounds table is built from.

`run-batch.sh` ends a round the same way: clean, it calls the close, so the unattended
path still ends in a PR; escalated, it names the brief and exits non-zero.

## 6. Close

    <worktree>/agentTooling/feature-close.sh [--self] <slug> [--no-push]

The only way out of a feature, and the counterpart of `feature-start.sh`: the two bracket
a feature and nothing between them opens a PR or freezes a record. Run from the feature's
worktree, on its branch, by the coordinator or by `run-batch.sh`. No model is involved.

**It refuses unless this is the tree a clean review judged**, before anything is written —
so a refusal leaves the worktree as it was, and comes before a PR rather than after one.
It refuses a checkout that is not on branch `S` (the post-merge repair path is
`feature-capture.sh` from the primary, step 7), a feature no review has finished, a latest
review whose verdict is not clean (naming the escalations file and the round that would
follow), a `HEAD` that is not the stamped `head` with any commit since carrying a subject
other than the harness's own (`S: cost records`, `S: PR`), and a worktree holding a dirty
path that is not one of the harness's records — **the same reader the capture refuses on**
(`stray_paths`, `plan-runner-roots.sh`), so a half-written file inside the feature
directory is named here, before the PR, rather than by the capture after one is open.

The round it names in its banner, its refusals and its `pr_opened` stamp is the one the
closing review stamped on its own `plan_end`; the count of completed reviews is only the
fallback for a `timing.jsonl` written before every line carried its round.

Then, in exactly this order — **the order is the point**:

1. **PR.** The body is the review's report as the executor wrote it, then the Rounds table
   `analysis/report.py --rounds-md` renders. `plans/pr.sh` pushes `S` and opens the PR
   against the manifest's `base`, or says it is already open, or skips where there is no
   forge.
2. **`pr_opened`**, stamped with that call's rc and url.
3. **Capture** — `feature-capture.sh` below, which commits the cost records on `S` (the
   `pr_opened` stamp rides that commit) and pushes. Advisory towards the PR: a refusal is
   printed with the command that re-runs it.
4. **The merge request, last.** `plans/pr.sh --merge-request S` asks the forge to merge
   under `PR_AUTO_MERGE` — and only now that the capture has pushed, which is what closes
   the race the request used to run into. A refused capture skips it and the close says
   so; a seeded `pr.sh` older than `template-version: 4` has no such entry point, and the
   close says that once and skips it.

Re-runnable: a second run finds the PR already open and the capture replacing its own
record, and ends at the same place.

    <worktree>/agentTooling/feature-capture.sh [--self] <slug> [--no-push]

From the worktree, on the branch, by the close or by hand. No model is involved. It stamps
`session_window.to`, recovers from
their session transcripts the attempts the CLI never priced (`recover_attempts.py --for
<slug>`, reported and never fatal — a plan that ran but whose stream carried no `result`
event is otherwise recorded at `$0`), captures and reports the cost, prints every session
and subagent the capture claimed — id, how it was selected, where it was launched, cost —
refreshes `S`'s own routing record (never another feature's copy of the same router's),
warns about any delegate
whose brief names `S` and that no route claims, commits exactly the cost records as
`S: cost records`, and pushes `S`. Never `main`. It refuses first when anything else is
dirty in the worktree — including a **sibling feature's** record dirtied before this run,
which is somebody else's work until the annotation step makes it this run's; after that
step the same check admits exactly the slugs the annotation returned — and a capture that
refuses rolls its stamp and recovered sidecars back, so the run can be repeated. **A
second run replaces the first**: scope that grows
before the merge is another round — the rework, a re-review brief queued in
`review/incomplete/` with its stem added to `plans`, `run-review.sh` again, and the close
again, which pushes to the PR already open — and the capture that round ends with
rewrites the record.

**`to` is stamped from evidence, and before the capture, and until the merge it is
provisional.** The bound is one second past the last instant of the sessions this
feature's `branches` and `session_window` select and of their subagents
(`capture_planning.py --last-branch-instant <slug>`, which consults no pin); with no such
session it falls back to the capture's own clock and says so in one line. Before the
merge it moves **either way** (`manifest.py set-window-to --replace`), so a re-run after
more work moves it later. Before the capture, because the capture splits a session several
features claim by the windows they hold it with, so a bound written afterwards freezes
this feature's own record against a window that is still open. A stamp that fails for any
reason — a fence with no `to` key, a bound that will not parse, one that would empty the
window — refuses the capture, since carrying on would record a feature with an open
window.

The frozen record covers the work up to the last capture: the coordinator's reading of the
PR and the merge click are not in it, by design.

## 7. Merge

On the forge, by the human, once the PR reads right — or by the forge itself, where the
close's merge request asked for it (step 6, `PR_AUTO_MERGE`). **Nothing runs after it**:
the merge is the freeze, and the next `feature-start.sh` prunes the merged worktree and
its local branch (step 2).

`feature-capture.sh` still runs from the primary after a merge, for two cases, and there
it **writes locally, commits nothing and pushes nothing** — a repair goes through a PR of
its own, which the human opens:

- **A feature merged under the old flow and never closed** — consuming repos have them.
  A plain run captures it.
- **`--recapture`**, the repair path for a merged record at the wrong number. Under it the
  stamp is `manifest.py set-window-to --tighten`, which replaces a bound already written
  only with an **earlier** one and refuses a later one, so a repair can narrow a window
  and no path can ever widen it; that one refusal warns and the capture carries on.

Neither needs the branch: a forge with delete-on-merge takes it, so with no branch left the
capture proceeds on the ancestry the branch was only ever evidence *for* — the feature's
manifest tracked in the checkout, and its `<slug>: start` commit in its history. Both,
never either; a slug that was never started refuses `nothing to capture`. A branch that is
still there but not merged is refused with the worktree copy to run instead.

`feature-close.sh` has no part here: it runs from the worktree, on the branch, before the
merge (step 6), and refuses from anywhere else — naming this capture for the repair.

## Propagate

Not a step of a feature — a step of *this directory*. A change here ships to every
consuming repo on its next pull: `./agentTooling/update.sh` in each of them pulls this
directory and runs `sync-plans.sh`, whose report names the repo-owned scripts that need a
hand-merge (`README.md` → "Updating").

**There is no weekly cost sweep any more.** Every step of it either belongs to a feature's
own capture (step 6) or is a repair somebody reaches for with a reason:

- the rate table's age and the corpus-wide sessions and delegates nobody has claimed are
  printed by `feature-capture.sh`, after its report and before its commit — informational,
  never a refusal;
- the frozen-record annotation (`sessions[].also_claimed_by`) runs at capture too, from
  the claims ledger, so a feature frozen before another claimed the session they share
  comes to say so without any transcript being re-read;
- the recovery of attempts the CLI never priced runs at capture, scoped to that feature,
  while its transcripts still exist;
- what is left — `backfill_usage.py`, a corpus-wide `recover_attempts.py`,
  `capture_planning.py --all`, `--recapture`, `--carry-lost` — is in
  `analysis/README.md` → "Repair tools", each with the one reason you would run it.

## The three rules

1. **A session is billed to the branch of the directory it was launched in**, at every
   message, whatever it `cd`s into afterwards. A coordinator launched inside the worktree
   is on branch `S` and is claimed by it, with no pin. One launched anywhere else — the
   primary checkout, on `main`, which reaches the worktree because the worktree sits
   inside it, or wherever a session began before the feature existed — is claimed only
   by pinning its id in the manifest's `sessions`, and its delegates only by pinning
   theirs in `subagents`. Never by widening `branches`. **A pin is now the exception**:
   `feature-start.sh` pins nothing unless asked (`--pin`), because the session that
   starts a feature is a router whose spend is its own category (step 2), and the
   coordinator belongs in the worktree where no pin is needed.
2. **Agents never create branches or worktrees.** No `git worktree add`, no
   `git checkout -b`, no `git branch`. `feature-start.sh` is the only way in — run from
   the primary checkout by the human or a router session — and `feature-close.sh` the
   only way out, run from the worktree on the branch, after which merging the PR is the
   last step and the next `feature-start.sh` prunes the worktree and the branch.
   Where `hooks/allow-repo-commands.sh`
   is wired, those commands are **denied** rather than prompted for — along with
   `push --force`, `reset --hard`, `clean`, `stash`, `rebase`, `switch -c` and the rest
   of the ref-moving set — and the denial's reason is this rule (`hooks/README.md` →
   "The git shape").
3. **The manifest's fence is written by the scripts, its prose by whoever authors the
   feature.** `feature-start.sh` fills the fence — with `sessions` empty, since it pins
   nothing by default — `feature-capture.sh` stamps `to`, which is provisional until the
   merge freezes it, and `analysis/manifest.py` is what edits it in between. An executor may correct the
   prose above it — a plan table that drifted, an exclusion that turned out wrong — and
   never the fence.
