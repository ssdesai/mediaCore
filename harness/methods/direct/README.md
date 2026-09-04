# direct

One implementer, one shot. This is the WP7 "direct" arm, restated.

- `template.md` — the implementer's brief: read the pinned spec sections, `CLAUDE.md`,
  `PROJECT_FACTS.md` and the folder READMEs; slice the work into the feature's
  `CHECKPOINT.md` and keep it current, its `updated:` line from `date -u` and each
  milestone also stamped into `timing.jsonl` with the top-level `stamp-timing.sh` (that
  stamp is what gives the cell's Time table a tests/build/gate split instead of one
  undivided span); **write and commit the acceptance tests
  first**, then build it; hold to the repo's quality bar (tests mirroring the tree,
  named constants, README field lists); run the gate to green; commit, push, and open
  the PR with the experiment banner as its first line. The tests-first step was added after WP7
  (`../../EXPERIMENTS.md` round 3): it is the one thing the plan workflow reliably added that
  the one-shot did not, so an arm without it measures the brief, not the method. The
  doctrine itself is `../../../AGENT_DIRECT.md`; this template is its experiment form.
- `run.sh` — one `claude -p --model opus --permission-mode acceptEdits --allowedTools
  Bash` with that brief, no budget cap, no resume. Exit 2 if the result event says usage
  limit, 1 on any other non-zero exit, 0 otherwise. The checkpoint makes a resume
  possible by hand (`AGENT_DIRECT.md` → "Checkpoint and resume"), but a resumed cell is
  a different measurement, so the harness never does it.

**`direct` is not "one `claude -p`".** It is one `claude -p` plus the same harness review
and the same rework as every other method. Nothing in this directory reviews its own
output, and a comparison that treats the model call as the whole arm is measuring the
wrong thing — which is the mistake the WP7 scorecards had to correct for by hand.

The brief tells the implementer to decide everything the spec leaves open rather than
stop to ask: nobody is listening, and a run that stalls on a question scores as a
failure of the method rather than of the brief.
