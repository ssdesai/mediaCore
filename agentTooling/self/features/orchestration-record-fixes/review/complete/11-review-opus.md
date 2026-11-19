# 11 — review: orchestration-record-fixes (round 11)

Round 10's review was clean; its security audit escalated one finding: the build-script judge
(`invokes_build_script`, the one deny a checkout with an unreadable orchestrator ledger gives)
took its text scan for any line holding the substring `<<`, so a quoted `'a<<'` sent
`echo 'a<<' ; ./run-p*.sh --self x` to a scan that cannot match a glob — a prompt where
`origin/main` denied. Commit `b94bc73` closes it (`NOTES.md` → "Round 11"). "No findings" is a
legitimate verdict, and a bypass you find is a finding.

## What the feature is supposed to do

- Item 1: a redirection word is never read as a refspec or remote by the push rules; a quoted
  operator word is an argument; a quoted digit is no descriptor.
- The fail-closed rule (`NOTES.md` → "Round 9"): a line holding a git word and a `$(…)`, a
  backtick, `<(`/`>(`, a `<<` or the word `case` — quoted or not — is never approved; the deny
  side has one plain reading and refuses what it finds; what it misses there prompts.
- A heredoc-looking token never switches a deny off: only an unquoted `<<` operator is a
  heredoc, and its own line is read.
- Round 11: `invokes_build_script` takes its text scan only when the line holds a real heredoc
  operator (`is_heredoc_operator` over `chain_tokens`) or does not lex; otherwise it keeps the
  tokenized reading.

## The diff

Base is `main` (`git fetch origin main`, then `git diff origin/main...HEAD --stat`). For this
round read `git diff 697654d..HEAD -- hooks self/tests` closely and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>","session_id":"<fresh>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, `AGENTTOOLING_PROFILE=cloud`
and `local`, a fresh `session_id` per call). The build-script deny is active only with an
unreadable orchestrator ledger; `self/tests/hook-cloud-profile.sh` H3/H4 call
`invokes_build_script` directly. Compare with `origin/main`'s hook.

## Contracts to hold it to

- Every line `origin/main`'s build-script judge refuses, HEAD's refuses too — the round-10
  audit's rows (`echo 'a<<' ; ./run-p*.sh`, `git log --grep='<<' ; ./run-p*.sh`,
  `ls 'a<<b' ; ./run-pl?ns.sh`) and round 9's (a literal name after a heredoc's body).
- Nothing `origin/main` refused is now approved; no ALLOW for a git word with a marker.
- Decided, not in scope: a glob of a build script after a real heredoc's body, wrappers, brace
  groups, comments, assignment prefixes and a git command after a heredoc's body — prompts,
  never an allow, as on `origin/main`.

## Verdict
