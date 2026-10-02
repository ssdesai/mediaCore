# 02 — re-review: hook-hash-chained-cd, round 2

## What round 2 was supposed to do

Round 1 (`escalations/01-review-opus.md`) escalated two items:

1. **`unquoted_comment_char` misread `$'…'` (ANSI-C quoting).** `ls $'\'' # '; cd src`
   was denied with the chained-cd reason. Bash reads `$'\''` as a single `'`, so the
   rest of that line is a comment and the `cd` never runs.
   - **Fix:** a new constant, `ANSI_C_QUOTE_PREFIX`, plus an `in_ansi` state inside
     `unquoted_comment_char`. A `'` that follows an unquoted, unescaped `$` enters that
     state. Inside it a backslash escapes the next character and only an unescaped `'`
     closes it.
   - **Unclosed lines:** an unclosed `$'…'` counts like any other unclosed quote.
2. **A missing `DENY` row for `'^'"#"`.**

## The diff

Scope this review to the round-2 commit only: `git show HEAD`. Round 1 already reviewed
everything else; do not re-review it.

## Contracts to hold it to

- **The round-1 regression is gone.** `ls $'\'' # '; cd src` and
  `echo $'\'' # x' && cd src` now prompt, with no deny.
- **A real ANSI-quoted `#` is still a literal.** `cd <root> && grep $'#' f` and
  `cd <root> && grep $'\'#' f` are denied.
- **An escaped `\$'#'` is still a literal.** It is a plain single quote, so it is denied.
- **The scanner's state machine is sound.** Check that an escaped `\$` does not enter
  ANSI mode, that a `$` inside double quotes does not either, and that `$$'x'` is
  handled sensibly. Leaving a line unjudged is always the safe direction. Approving a
  line, or denying one bash reads differently, is not.
- **`./self/gate.sh` is green.**

## Verdict

Either "no findings" or a list of findings, each with a concrete command and its
expected versus actual decision. "No findings" is a legitimate verdict.
