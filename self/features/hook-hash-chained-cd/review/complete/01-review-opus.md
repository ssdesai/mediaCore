# 01 — review: hook-hash-chained-cd

## What the feature was supposed to do

A consuming-repo user reported this subagent command:
`cd <root>; grep -n '^#' TEST_SPEC.md | head -300; wc -l TEST_SPEC.md`.
`hooks/allow-repo-commands.sh` **approved** it. The same line with `'^x'` was denied
with the "run cd as its own call" rewrite. Claude Code's reads fence then stopped the
approved line for the human anyway, because it cannot follow a `cd`. So the human got a
prompt and the model got no rewrite.

There were two causes, and the feature fixes both:

1. **The `#` guard was not quote-aware.** `chains_chdir` (and the other deny/rewrite
   readers) skipped any line containing a `#`, even one inside quotes. The fix is one
   helper, `unquoted_comment_char`. It is True only for a `#` outside quotes and
   unescaped, or for any `#` on a line whose quotes never close. Every place that used
   to test `COMMENT_CHAR in …` now calls it: `chains_chdir`, `command_words`,
   `does_not_tokenize`, `rewrite_reason_lines` and `authoring_reason_lines`.
2. **The approval analysis approved chained cds.** `command_allowed` tracked the `cd`
   and resolved later members against the new directory. Approving that bought nothing,
   since the fence overrides it. Now a `cd` is approved only as the whole command, and
   no cwd is threaded between members: `subcommand_allowed` and `expansion_allowed`
   return a bool. A chain the deny cannot judge (an unquoted `#`, a heredoc) now
   reaches the ordinary flow instead of an `allow`.

## The diff

Base is `main`. Run `git diff main...HEAD --stat`, then read the full diff. The files
are `hooks/allow-repo-commands.sh`, `hooks/README.md` and
`self/tests/allow-repo-commands.sh`.

## Contracts to hold it to

- **The reported line is denied with `DENY_REASON`.** Its double-quoted and
  backslash-escaped twins are denied too (new `DENY` rows).
- **A chain with an unquoted `#` is never `ALLOW`** (new `CHAINED_NOT_APPROVED` rows).
- **No widening.** Nothing that prompted before may be approved now. Removing the cwd
  threading must not change any single-member verdict.
- **No new deny on a guess.** A real comment (`ls src # don't`), a mid-word `#` hiding
  a heredoc (`cat a#<<EOF …`) and a heredoc body must all still be left unjudged. Check
  the `UNREADABLE_NOT_DENIED` and `NOT_DENIED` rows, and think about other quote/escape
  edge cases: `\#` inside double quotes, `'…'"#"`, and a `#` inside `$(…)`.
- **The rewrite rows are newly reachable.** Lines with a quoted `#` are now judged by
  the `$NAME`, `~`, brace, `..`, relative-cd, mixed-sequence and authoring rows. Make
  sure none of them misfires on a quoted `#`.
- **`member_allowed` still holds.** It assumes no member of a sequence moves the
  directory. That is now true by construction.
- **`hooks/README.md` matches the code.**
- **`./self/gate.sh` is green.**

## Verdict

Either "no findings" or a list of findings, each with a concrete failing command and its
expected versus actual decision. "No findings" is a legitimate verdict.
