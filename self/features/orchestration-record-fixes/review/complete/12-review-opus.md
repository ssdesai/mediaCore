# 12 — review: orchestration-record-fixes (round 12, after merging #141)

Round 11 came back clean on review and security audit (head `f828a34`). Since then `origin/main`
moved: #141 (orchestration-records-in-repo) merged, touching `hooks/orchestrator_role.py`,
`hooks/allow-repo-commands.sh`, `hooks/wire-settings.py` and `analysis/roots.py`. This round
judges the merge (`8fe2bcf`) and the code as merged. "No findings" is a legitimate verdict, and
a bypass you find is a finding.

## What changed since round 11

- **The merge.** Conflicts in `analysis/report.py` and `analysis/README.md` resolved keeping
  both features: #141's record-own repo root (`artifact_root(self_mode)`, `home_repo` from
  `roots.orchestration_home_repo`) and item 2's `agentTooling` entry resolved against the
  agentTooling directory (`compute_orchestration_report(…, tooling_root=)`,
  `ORCH_TOOLING_REPO`). `roots.record_repo_root()` was superseded by #141 and removed; its
  test (`orchestration-records.sh` S7) became one row in `orchestration-records-in-repo.sh` R2.
  `NOTES.md` → "Item 2" → "After merging #141".
- **The hook auto-merged.** #141 admits `--self` as the first argument of the allowlisted
  `analysis/manifest.py` / `analysis/report.py` record tools (`ORCHESTRATOR_SELF_FLAG`). This
  feature's fail-closed rule (`fails_closed`, `NOTES.md` → "Round 9") and heredoc handling are
  unchanged since round 11.

## The diff

Base is `main` (`git fetch origin main`, then `git diff origin/main...HEAD --stat`). For this
round read the merge closely: `git diff f828a34 8fe2bcf -- analysis hooks self/tests` against
`git diff f828a34...origin/main`, i.e. what the merge resolution did beyond the two sides.
Drive the hook yourself (`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>",
"session_id":"<fresh>"}' | CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`,
`AGENTTOOLING_PROFILE=cloud` and `local`), including as an orchestrator session (a record naming
the session), and compare with `origin/main`'s hook.

## Contracts to hold it to

- The combined hook: the orchestrator allowlist's documented shapes
  (`ORCHESTRATOR_ALLOWLIST_TEXT`: the record tools with and without `--self`, `git commit -m
  "$(cat <<'EOF' … EOF)"`, `git push -u origin "$(git branch --show-current)"`) keep the
  answers they have on `origin/main`; nothing `origin/main` refuses is approved; every round-11
  contract still holds (fail-closed: no ALLOW for a git word with a marker; a quoted `<<` or
  `<<<` never switches a deny off; the build-script judge as round 11 left it).
- `report.py --orchestration`, with and without `--self`, in a standalone and a consuming-repo
  layout: home-repo entries priced from the record's repo root, an `agentTooling` entry priced
  from the agentTooling directory with no `--checkout`, another repo asking for `--checkout`,
  `--checkout` still winning.
- Decided, not in scope (prompts, never an allow, as on `origin/main`): wrappers, brace
  groups, comments, assignment prefixes, a git command or globbed build script after a real
  heredoc's body.

## Verdict
