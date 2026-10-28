# templates

The three prompts the harness itself owns. A method's own brief lives in
`../methods/<name>/template.md`; these are the parts that must be identical on every
tree of an experiment, whatever built it.

| File | What it is |
|---|---|
| `isolation.md` | The isolation paragraph pasted into every brief and both preambles at `@@ISOLATION@@`. Names the one worktree the delegate may write in, every sibling worktree of the fixture repo it must not read (computed per run from `git worktree list`), the experiments directory holding the scoring instruments, and the vendored `agentTooling/`. |
| `review-preamble.md` | The review stage's prompt. Titled `# Harness review pass`, which is also what tells a run apart in a transcript. Says how to review — establish the diff first, look for what stays green, fix what is local and escalate the rest — and pins the exact shape of `review/findings.md`. The fixture's own `review-brief.md`, which says *what* to check, is appended at `@@REVIEW_BRIEF@@`. |
| `rework-preamble.md` | The rework stage's prompt, titled `# Harness rework pass`. Fix every escalated item and nothing else, one commit, gate green, push. The findings file is appended at `@@FINDINGS_TEXT@@` and is the **only** input: no other tree is read, which is the isolation failure this harness exists to rule out. |

Placeholders are filled by `harness_fill_template` in `../lib.sh` from the values
`run.sh` resolves per cell. Any `@@NAME@@` left unfilled aborts the run — a literal
placeholder reaching a model is a silently wrong experiment, not a typo.

Two facts these files depend on that are not visible from reading them:

- The **titles are load-bearance for the smoke test**: `harness/tests/smoke.sh`'s fake
  `claude` decides what to do by matching `# Harness review pass` / `# Harness rework
  pass` in the prompt. Renaming a heading here means renaming it there.
- The findings shape in `review-preamble.md` is parsed by `harness_findings_count`
  (`../lib.sh`), which reads the `fixed:` / `escalated:` counts and falls back to
  counting `- id:` rows per section. The escalated count decides whether the rework stage
  runs at all.
