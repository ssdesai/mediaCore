# vanilla-conv

The second rung of the tooling-ablation ladder (`vanilla` → `vanilla-conv` → `direct-bare`
→ `direct` → `plans`): a minimal brief with **no agentTooling doctrine in it**, run in a
tree whose `CLAUDE.md` (and the `CONVENTIONS.md` it imports) and `.claude/settings.json`
(the command hook and deny rules) load as they normally would.

- `template.md` — the brief: the spec sections, the fixture's facts, "implement it, make the
  gate pass, commit, push, open the PR". What stays is the harness's, not the doctrine's:
  the `feature:` first line (what cost capture reads), the isolation paragraph, the
  decide-don't-ask line (a headless run has nobody to ask), the gate command and the PR
  mechanics (`<tree>/agentTooling/forge.sh pr-open`, the experiment banner). What is left
  out, against `../direct-bare/template.md`: reading `CLAUDE.md`, `PROJECT_FACTS.md` and the
  folder READMEs, and the whole quality bar (tests mirroring the tree, named constants,
  README field lists). Byte-identical to `../vanilla/template.md`.
- `run.sh` — `../direct/run.sh` with only the method name changed: one `claude -p` from the
  tree's root (`harness_claude`'s cwd is the worktree), no budget cap, no resume.

So `vanilla-conv` vs `direct-bare` measures the doctrine *in the brief*, and `vanilla` vs
`vanilla-conv` the doctrine *loaded by the session* (the conventions and the hook).
`self/tests/vanilla-pair.sh` fails the gate if the two vanilla briefs diverge, if either
picks up doctrine, or if either `run.sh` drifts from its pair. `../split-tests/`'s
implementer brief is this `template.md` plus one paragraph, so an edit here also fails
`self/tests/split-tests-pair.sh` until `split-tests/template.md` follows it. Like every method, it gets
the same harness review and rework afterwards.
