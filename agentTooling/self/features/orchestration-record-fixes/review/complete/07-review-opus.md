# 07 — review: orchestration-record-fixes (round 7)

Round 6 escalated (`escalations/06-review-opus.md`, `escalations/06-audit-opus.md`): a `case`
after a reserved word (`!`, `time`, `then`, `do`, `else`) and an `esac` that is a pattern word
(`x|esac)`) fooled the case counter in `mask_quoted_punctuation`. Commit `3964af3` closes them
by design rather than by another patch: `command_words` returns a third reading,
`command_words_crude`, for a line holding a substitution and the word `case`. "No findings" is a
legitimate verdict, and a bypass you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff 5fb7d90..HEAD --
hooks/allow-repo-commands.sh hooks/README.md self/tests` closely, and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`).

## Contracts to hold it to

- The audit's B3a (seven lines) and B3b (five lines) and the review's five lines are DENY in
  both profiles; `HEAD:other` in that shape is the cloud refusal, local prompt.
- `command_words_crude` is used only to deny more: it applies only to a line with a
  substitution (`$(`, a backtick, `<(`/`>(`) and the word `case`, is None for a heredoc or a
  `never_judged` line, and feeds only the deny judges. `command_allowed` is untouched, so a
  line with a `$` or backtick is still never approved. Its one known cost is pinned by a row
  (`grep -n "case $(x) git push origin main" README.md` is refused).
- False-depth rows stay safe: `cat "$(echo case-x)" README.md` and `echo "$(case x in x)
  true;; esac)" git status` are prompts, `grep -n "case" README.md` is ALLOW.
- Look for what the crude cut gets wrong the dangerous way: a refused git command that the cut
  hides from the fragment head (a word glued to a quote, `{`, a reserved word not in
  `CRUDE_RESERVED_WORDS`, a descriptor, `$IFS`-style splitting), or a common approved read
  with a substitution and `case` that is now refused. Judge whether a line with no `case`
  word is still reachable by an unfollowed grammar shape.

## Verdict
