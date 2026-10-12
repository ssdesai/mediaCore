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
     `plans/batch.log` — `>>`, because `>` lost one WP7 arm's first run when the batch
     was resumed.

On a non-zero batch exit: if `escalations/` holds anything or a plan sits in any queue's
`failed/`, that is a tier-3 stop or a mis-scoped plan and the method exits 1 without
retrying. Otherwise the stop is a usage limit or an interrupt, both of which leave the
plan in `inprogress/`, so the batch is re-run once (it resumes) and the method exits 2 if
it still has not finished.

The batch's own review plan and `plans/pr.sh` are part of this method, not of the
harness: the harness's review stage runs afterwards, from the same preamble every other
method's tree gets.

**Resume.** A usage-limit stop in the architect makes the harness call this script again.
It re-enters the architect as a fresh session with a paragraph appended to the brief
saying a partial corpus is already on disk — not through `claude --resume`, which exists
on this install but is not what the runners do: the plans on disk are the durable state,
and a session id is not (`RUNNER.md` → "How resume works"). The batch half resumes on its
own, from `inprogress/`.

`plans/batch.log` is inside the tree, so `pr.sh`'s `git add -A` commits it — that is
deliberate, it is the arm's process record. In a repo whose `.gitignore` covers `*.log`
it will not be committed, and the log then lives only on the machine that ran it.
