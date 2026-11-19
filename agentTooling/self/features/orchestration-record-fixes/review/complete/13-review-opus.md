# 13 — review: orchestration-record-fixes (round 13)

Round 12 (after merging #141) came back clean on review; its security audit escalated one
finding (B1: a build script run from a substitution inside a reader's arguments,
`ls "$(./run-plans.sh --self x)"`, was not a run for the build-script judge) and was stamped
stale. Commit `17d7019` closes B1 with the git rule's fail-closed shape (`NOTES.md` → "Round
12 → 13"). "No findings" is a legitimate verdict, and a bypass you find is a finding.

**Do not edit any file in this pass.** The security audit runs before you; any edit to an
audited path after it stamps the audit stale and blocks the close. A doc nit goes in your
report as a note, not a change.

## What the feature is supposed to do

- Item 1: a redirection word is never read as a refspec or remote by the push rules; a quoted
  operator word is an argument; a quoted digit is no descriptor.
- The fail-closed rule (`NOTES.md` → "Round 9"): a line holding a git word and a `$(…)`, a
  backtick, `<(`/`>(`, a `<<` or the word `case` — quoted or not — is never approved; the deny
  side has one plain reading and refuses what it finds; what it misses there prompts. A quoted
  `<<` or a `<<<` never switches a deny off; a heredoc's own line is read.
- The build-script judge (`invokes_build_script`, the one deny a checkout with an unreadable
  orchestrator ledger gives): a real heredoc sends the line to the text scan (round 11), and
  now `substitution_may_build` — a substitution marker plus a build-script name or a pattern
  that could match one, after whole-argument heredocs become placeholders — is a run.
- Item 2, merged with #141: report paths resolve against the record's own repo root; an
  `agentTooling` entry against the agentTooling directory, with no `--checkout`.

## The diff

Base is `main` (`git fetch origin main`, then `git diff origin/main...HEAD --stat`). For this
round read `git diff c0567e3..HEAD -- hooks self/tests` closely and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>","session_id":"<fresh>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, `AGENTTOOLING_PROFILE=cloud`
and `local`). `self/tests/hook-cloud-profile.sh` H3–H5 call `invokes_build_script` directly.

## Contracts to hold it to

- Every line `origin/main`'s build-script judge refuses, HEAD's refuses too; round 12's B1
  inputs are runs; `ls "$(pwd)"`, `git log "$(git branch --show-current)"` and a heredoc commit
  message that only mentions a script are not.
- Nothing `origin/main` refuses is approved; the orchestrator allowlist's documented shapes
  keep their `origin/main` answers.
- Decided, not in scope (prompts, never an allow, identical on `origin/main`): wrappers, brace
  groups, comments, assignment prefixes, a git command or globbed build script after a real
  heredoc's body, and the bundled force flag `git push -fu` (a recorded follow-up).

## Verdict
