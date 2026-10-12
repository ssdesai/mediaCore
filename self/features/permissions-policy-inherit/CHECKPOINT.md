# Checkpoint: permissions-policy-inherit

status: committed        planned | tests-written | implementing | gating | committed
updated: 2026-09-16T16:40:32Z
gate: all checks passed          (77 checks, 0 failed, 0 skipped)

## Slices
- [x] acceptance tests — `self/tests/allow-repo-commands.sh` (entry points, git deny),
      `self/tests/hook-wiring.sh` (Bash rules, `--self`), `self/tests/plan-numbering.sh`
      (new), gate rows for both; committed on their own, red
- [x] 1. hook: entry-point approvals (gate.sh, check-plans.sh, bash -n, shellcheck,
      py_compile, report.py, capture_planning.py --list-*, manifest.py get)
- [x] 2. hook: the git-mutation deny, after the cd deny, before the approval analysis
- [x] 3. `wire-settings.py`: `BASH_DENY_RULES` merged like the Edit rules, counted per kind
- [x] 4. `wire-settings.py --self`, this checkout's `.claude/settings.json`, the gate check
- [x] 5. `feature-start.sh` `--self` plan numbering past 99
- [x] 6. READMEs: `hooks/`, root, `LIFECYCLE.md` rule 2, `self/`, `self/tests/`,
      `self/PROJECT_FACTS.md`, `self/BACKLOG.md`
- [x] 7. NOTES.md, manifest prose, gate green, commit

## Learned
- The worktree a start makes is cut from `origin/<base>`, so a plan-numbering fixture has
  to be on `main` and pushed before the start runs — which is why the numbering
  assertions are a sibling test rather than a phase of `feature-lifecycle.sh`.
- The git deny had to skip words containing a brace: it expands nothing, and
  `git branch {-a,new}` would otherwise be denied on a reading it cannot make. The
  approval analysis, which does expand, still refuses it.
- Seven cases moved from the test's PROMPT list to its DENY list (`git stash`,
  `git reset --hard`, `git branch -D main`, …) — a stronger refusal for the same command.

## Resume
- Nothing outstanding. `git log --oneline main..HEAD` is the build; the review pass
  (`./run-review.sh --self permissions-policy-inherit`) is next and is not the builder's.
- Gate: `./self/gate.sh` (~2 min). Single tests: `bash self/tests/<name>.sh`.
