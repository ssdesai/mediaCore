# 08 — review: orchestration-record-fixes (round 8)

Round 7 escalated (`escalations/07-review-opus.md`, `escalations/07-audit-opus.md`: B4, the
crude reading cut at quotes and kept backslashes, so a quoted refspec or `git` word hid the
command on exactly the lines the crude reading is for). Commit `7bffa68` closes it:
`command_words_crude` deletes `"`, `'` and `\` first (`CRUDE_JOINED_CHARS`), then cuts at
operators, parens, braces, backticks and `$`. "No findings" is a legitimate verdict, and a
bypass you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff 927471a..HEAD --
hooks/allow-repo-commands.sh hooks/README.md self/tests` closely, and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`; use a fresh `session_id` per call — after two rewrite
denials in one session the policy asks the human instead).

## Contracts to hold it to

- The round-7 rows (fifteen lines in table T) are DENY in both profiles, `HEAD:other` the cloud
  refusal and a local prompt.
- The crude reading only ever denies more (`command_allowed` untouched; a `$` or backtick line
  is never approved) and applies only to a line with a substitution and the word `case`.
- False-depth rows stay safe (`cat "$(echo case-x)" README.md` prompt, `grep -n "case"
  README.md` ALLOW); the documented false deny (`grep -n "case $(x) git push origin main"
  README.md`) is pinned.
- Decided, not in scope: `! git push …`, `env`/`command`/`exec`/`nohup` wrappers and `gi?
  push` prompt at the top level (no substitution, no `case`), as on `origin/main`. Say if you
  think the contract covers them, with a payload; do not file the same item a second time
  without one.
- Look for what the joining gets wrong the dangerous way: a refused git command still hidden
  from a fragment head (a word glued to a deleted quote that makes the *head* a different
  word, e.g. `git"" push`, `"git push" origin main`, an empty-quote word, `$'…'`), or a common
  approved read with a substitution and `case` now refused.

## Verdict
