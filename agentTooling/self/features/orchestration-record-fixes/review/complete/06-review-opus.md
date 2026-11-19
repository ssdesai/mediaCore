# 06 — review: orchestration-record-fixes (round 6)

Round 5 escalated (`escalations/05-review-opus.md`, `escalations/05-audit-opus.md`: B2, the
`case` arm's `)` inside a double-quoted substitution, and the missing "the union approves
nothing" row). Commit `314904b` closes both. Review it against the findings below. "No
findings" is a legitimate verdict, and a bypass you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff b8731d8..HEAD --
hooks/allow-repo-commands.sh hooks/README.md self/tests` closely, and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`).

## Contracts to hold it to

- B2: the eight lines of the audit's table (double-quoted `$(case …)`, backtick, mid-word,
  `reset --hard`, `HEAD:other` (cloud refusal, local prompt), `stash`, an assignment, nested)
  are DENY; `echo $(case x in (x) git push origin main;; esac)` too.
- `mask_quoted_punctuation(lift=True)` counts open `case`s per substitution/backtick frame
  (`CASE_KEYWORD_RE`, `CASE_COMMAND_PRECEDERS`) and reads a `)` met while one is open as a
  separator (`CASE_PATTERN_SEPARATOR`); the substitution still closes on its own `)`.
- `echo $(true) git status` stays a prompt (the union approves nothing); `grep -n "(x)"`,
  `git log --format="%H $(echo case)" -1` are unchanged.
- Look for a shape where the case counter is fooled: `case` as an argument or in a string
  (false depth leaves a scope open: is it fail-safe?), `esac` missing, a pattern with `|`,
  `;&` / `;;&` terminators, nested cases, a `case` inside a `(…)` subshell inside the
  substitution, a backtick pair, `if … then git push …` inside a substitution (named
  pre-existing by the audit).

## Verdict
