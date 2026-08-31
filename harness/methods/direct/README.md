# direct

One implementer, one shot. This is the WP7 "direct" arm, restated.

- `template.md` — the implementer's brief: read the pinned spec sections, `CLAUDE.md`,
  `PROJECT_FACTS.md` and the folder READMEs; build it; hold to the repo's quality bar
  (tests mirroring the tree, named constants, README field lists); run the gate to green;
  commit, push, and open the PR with the experiment banner as its first line.
- `run.sh` — one `claude -p --model opus --permission-mode acceptEdits --allowedTools
  Bash` with that brief, no budget cap, no resume. Exit 2 if the result event says usage
  limit, 1 on any other non-zero exit, 0 otherwise.

**`direct` is not "one `claude -p`".** It is one `claude -p` plus the same harness review
and the same rework as every other method. Nothing in this directory reviews its own
output, and a comparison that treats the model call as the whole arm is measuring the
wrong thing — which is the mistake the WP7 scorecards had to correct for by hand.

The brief tells the implementer to decide everything the spec leaves open rather than
stop to ask: nobody is listening, and a run that stalls on a question scores as a
failure of the method rather than of the brief.
