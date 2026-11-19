# plans

Delegated plan execution as a method: an architect authors the corpus, the runners
execute it. This is the WP7 "plans" arm, restated so nothing feature-specific is left in
it.

- `template.md` — the architect's brief. Its shape came from the WP7 F5 delegate brief:
  read the pinned spec sections, then `CLAUDE.md` / `AGENT_PLANS.md` / `PROJECT_FACTS.md`
  and the folder READMEs; author build, verify and review plans plus level sentinels;
  fill in the manifest's `plans` array and write `NOTES.md`; terminate without ever
  running the batch.
- `run.sh` — the two halves of the method:
  1. one `claude -p --model opus` with the brief (no budget cap — an architect's
     spend is one of the things being measured);
  2. an assertion that `auto/incomplete/`, `verify/incomplete/` and `review/incomplete/`
     are non-empty and `NOTES.md` exists. An empty queue makes `run-batch.sh` a silent
     no-op, and the run would score a method that never built anything as one that built
     something badly;
  3. `./agentTooling/run-batch.sh <slug>` from the tree, output **appended** to
     `$HARNESS_LOG_DIR/<branch>-plans-batch.log` — `>>`, because `>` lost one WP7 arm's
     first run when the batch was resumed. The log is **outside the tree**: a log inside it
     is a dirty path, and `feature-close.sh` refuses to close over one (both
     `exportStoreMethodEffortDefault` cells ended with no PR that way).

On a non-zero batch exit: if `escalations/` holds anything or a plan sits in any queue's
`failed/`, that is a tier-3 stop or a mis-scoped plan and the method exits 1 without
retrying. Otherwise the method exits 2 (resumable) **only on positive evidence** in the
output this batch invocation appended: the runners' closing summary naming a usage limit
(`stopped: Claude usage limit reached on …`) or an interrupt (`interrupted by signal …`),
both printed by `plan-runner-lib.sh` when a plan is left in `inprogress/`. Any other
non-zero exit — a close refusal included — exits 1 at once with the last lines of the log
in the warning, and the batch is not re-run. The harness waits and calls the method again
on exit 2, and that call resumes the batch: when any plan already sits in an `inprogress/`
or `complete/` queue the architect and the incomplete-queue assertions are skipped, since
the batch has by then drained the queues the architect filled. `harness/tests/plans-method.sh` pins all of
this, and that the two strings are still in `plan-runner-lib.sh`.

The batch's own review plan and `plans/pr.sh` are part of this method, not of the
harness: the harness's review stage runs afterwards, from the same preamble every other
method's tree gets.

**Resume.** A usage-limit stop in the architect makes the harness call this script again.
It re-enters the architect as a fresh session with a paragraph appended to the brief
saying a partial corpus is already on disk — not through `claude --resume`, which exists
on this install but is not what the runners do: the plans on disk are the durable state,
and a session id is not (`RUNNER.md` → "How resume works"). The batch half resumes on its
own, from `inprogress/`.

The batch log is no longer part of the arm's committed record; it lives with the cell's
other harness logs on the machine that ran it.
