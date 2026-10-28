# 03 — re-review: hook-hash-chained-cd, round 3

## What round 3 was supposed to do

Round 2 (`escalations/02-review-sonnet.md`) escalated one item. `$$` is bash's
process-ID parameter. So the quote in `$$'…'` is a plain single quote, but
`unquoted_comment_char` armed ANSI-C mode on the second `$`. That made
`ls $$'a\' # b'; cd src` be denied, even though bash reads its `#` as a comment.

The fix: a `$` that directly follows an unquoted, unescaped `$` no longer counts as a
prefix. Only an odd run of `$` before a `'` starts `$'…'`.

## The diff

Scope this review to the round-3 commit only: `git show 3cb99a4`. Rounds 1 and 2 are
already reviewed, so do not re-review them.

## Contracts to hold it to

- **The round-2 regression is fixed.** `ls $$'a\' # b'; cd src` prompts, with no deny.
- **The quoted `#` cases are still denied.** `cd <root> && grep $$'#' f` (a plain quote)
  and `cd <root> && grep $$$'\'#' f` (`$$` followed by ANSI-C quoting) are both denied.
- **Every earlier row still holds.** Run `bash self/tests/allow-repo-commands.sh` and
  `./self/gate.sh`. Both must be green.
- **Probe for a deny bash would disagree with.** Nothing else about the scanner's
  `$`-run handling should produce one. Leaving a line unjudged is always the safe
  direction.

## Verdict

Either "no findings" or a list of findings, each with a concrete command and its
expected versus actual decision. "No findings" is a legitimate verdict.
