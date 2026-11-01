# templates

The prompts the harness itself owns. A method's own brief lives in
`../methods/<name>/template.md`; these are the parts that must be identical on every
tree of an experiment, whatever built it.

| File | What it is |
|---|---|
| `isolation.md` | The isolation paragraph pasted into every brief and both preambles at `@@ISOLATION@@`. Names the one worktree the delegate may write in, every sibling worktree of the consuming (measured) repo it must not read (computed per run from `git worktree list`), the experiments directory holding the scoring instruments, and the vendored `agentTooling/`. |
| `review-preamble.md` | The review stage's prompt. Titled `# Harness review pass`, which is also what tells a run apart in a transcript. Says how to review — establish the diff first, look for what stays green, fix what is local and escalate the rest — and pins the exact shape of `review/findings.md`. The fixture's own `review-brief.md`, which says *what* to check, is appended at `@@REVIEW_BRIEF@@`. |
| `rework-preamble.md` | The rework stage's prompt, titled `# Harness rework pass`. Fix every escalated item and nothing else, one commit, gate green, push. The findings file is appended at `@@FINDINGS_TEXT@@` and is the **only** input: no other tree is read, which is the isolation failure this harness exists to rule out. |
| `program-brief.md` | A program cell's first orchestrator prompt, titled `# Harness program brief`. Gives the orchestrator its role (decide, brief, read reports, write the record; never build, never run the start/close scripts), the arm, the ordered feature list (`@@FEATURES@@`), the implementer-brief template to copy (`@@BRIEF_TEMPLATE@@`) with the start line and close step to replace, the isolation paragraph and where briefs go (`@@BRIEF_DIR@@`); ends by asking for the reply `ready` and no writing yet. |
| `program-feature.md` | The prompt each per-feature `--resume` of the orchestrator carries, titled `# Harness program feature`: the previous feature's outcome (`@@PREV_OUTCOME@@`), then the next feature's facts, branch, worktree, PR base, dependency and method choice, and the path to write its brief to (`@@BRIEF_PATH@@`). The reply must end with `METHOD: <direct\|plans\|hand>`. |
| `program-collect.md` | The final orchestrator turn, titled `# Harness program collect`: run the exact `manifest.py --orchestration` commands the driver built (`@@RECORD_COMMANDS@@`), fill the record's placeholder paragraph at `@@RECORD_PATH@@`, commit it on the program branch and push. |

Placeholders are filled by `harness_fill_template` in `../lib.sh` from the values
`run.sh` resolves per cell, each read from `HARNESS_<NAME>`. Any `@@NAME@@` left unfilled
aborts the run — a literal placeholder reaching a model is a silently wrong experiment,
not a typo. The program templates add: `PROGRAM`, `PROGRAM_SLUG`, `PROGRAM_BRANCH`,
`PROGRAM_TREE`, `ARM`, `FEATURE_COUNT`, `FEATURES`, `POSITION`, `PREV_OUTCOME`, `PR_BASE`,
`PR_FIRST_LINE`, `DEPENDS`, `METHOD_CHOICE`, `BRIEF_PATH`, `BRIEF_DIR`, `RECORD_PATH`,
`RECORD_COMMANDS`, `BRIEF_TEMPLATE`. `FEATURES`, `RECORD_COMMANDS`, `DEPENDS` and
`METHOD_CHOICE` are multi-line values the driver builds and may carry scalar placeholders,
so they are inserted before the scalars; `PREV_OUTCOME` is an implementer's report, free
text, so it is inserted last and never scanned for placeholders.

Two facts these files depend on that are not visible from reading them:

- The **titles are load-bearing for the smoke test**: `harness/tests/smoke.sh`'s fake
  `claude` decides what to do by matching `# Harness review pass` / `# Harness rework
  pass` / `# Harness program brief` / `# Harness program feature` / `# Harness program
  collect` in the prompt. Renaming a heading here means renaming it there.
- `program-brief.md` and `program-collect.md` are filled by `../program-stages.sh` at program
  scope (every feature-specific placeholder emptied), `program-feature.md` with one
  feature's values loaded. Their `@@BRIEF_TEMPLATE@@` is
  `<program tree>/agentTooling/templates/plans/ORCHESTRATOR_BRIEF.md` and `@@RECORD_PATH@@`
  is `<program tree>/agentTooling/self/orchestrations/<PSLUG>/README.md`, the layout
  `orchestration-start.sh` writes; both come from the arm's pinned copy.
- The findings shape in `review-preamble.md` is parsed by `harness_findings_count`
  (`../lib.sh`), which reads the `fixed:` / `escalated:` counts and falls back to
  counting `- id:` rows per section. The escalated count decides whether the rework stage
  runs at all. Likewise `program-feature.md`'s `METHOD:` last line is parsed by the driver
  (`../program-stages.sh`).
