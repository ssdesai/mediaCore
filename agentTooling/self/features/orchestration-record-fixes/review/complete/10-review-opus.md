# 10 — review: orchestration-record-fixes (round 10)

Round 9 (`9297a93`) replaced the layered command readings with a fail-closed rule
(`NOTES.md` → "Round 9"); its review was clean and its security audit escalated one finding: a
build script after a heredoc's body escaped `invokes_build_script` — the one deny a checkout
with an unreadable orchestrator ledger gives — because `judged_tokens` stops at the body, while
on `origin/main` the judge fell back to a whole-text scan. Commit `2f4295e` closes it
(`NOTES.md` → "Round 10"). "No findings" is a legitimate verdict, and a bypass you find is a
finding.

## What the feature is supposed to do

- Item 1: a redirection word is never read as a refspec or remote by the push rules; a quoted
  operator word is an argument; a quoted digit is no descriptor.
- The fail-closed rule: a line holding a git word and a `$(…)`, a backtick, `<(`/`>(`, a `<<`
  or the word `case` — quoted or not — is never approved; the deny side has one plain reading
  and refuses what it finds, and what it misses there prompts.
- A heredoc-looking token never switches a deny off: only an unquoted `<<` operator is a
  heredoc, and its own line is read.
- Round 10: `invokes_build_script` reads a line still holding `<<` (after whole-argument
  heredocs are swapped for placeholders) as text, as on `origin/main`.

## The diff

Base is `main` (`git fetch origin main`, then `git diff origin/main...HEAD --stat`). For this
round read `git diff 9297a93..HEAD -- hooks self/tests` closely and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>","session_id":"<fresh>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, `AGENTTOOLING_PROFILE=cloud`
and `local`, a fresh `session_id` per call). Compare with `origin/main`'s hook.

## Contracts to hold it to

- Every line `origin/main`'s build-script judge refuses, HEAD's refuses too; in particular
  a build script anywhere after a heredoc, in any spelling `origin/main` caught.
- Nothing `origin/main` refused is now approved; no ALLOW for a git word with a marker.
- Round 9's contracts still hold (B1 rows DENY in both profiles; the decided prompts stay
  prompts, not findings, where `origin/main` also prompted).
- Decided, not in scope: wrappers, brace groups, comments, assignment prefixes, and a git
  command after a heredoc's body — prompts, never an allow, as on `origin/main`.

## Verdict
