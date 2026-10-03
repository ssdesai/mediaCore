Verdict: escalated

# Review, round 2 — hook-hash-chained-cd

## What the batch was supposed to do
Fix the round-1 escalation. `unquoted_comment_char` read `$'…'` as a plain single quote, so `ls $'\'' # '; cd src` was denied for a `cd` that bash never runs. Add the `'^'"#"` DENY row.

## Does it do it
Yes, for every contract in the brief, checked by reading the state machine in `git show HEAD`. I did not run anything.
- The round-1 regression is fixed. `$'\''` stays inside ANSI mode, so the `#` after it is unquoted and the line is left unjudged.
- `$'#'` and `$'\'#'` keep the `#` inside ANSI mode. They are literals, so these lines are denied.
- An escaped `\$'#'` does not enter ANSI mode (`literal` is true for the `$`). It is denied.
- A `$` inside double or single quotes does not enter ANSI mode. `"$"'#'` is read as plain quotes.
- An unclosed `$'…'` counts like any other unclosed quote.

## Fixed in this pass
Nothing. I started a fix to the `$$` case below. The hook file was write-protected in this session, so I reverted the one test row I had added. The tree matches the round-2 commit.

## Escalated to the next round
1. **`$$'…'` is read as ANSI-C quoting.** In `unquoted_comment_char` (`hooks/allow-repo-commands.sh`), `after_dollar` is set by every unescaped `$`. That includes the second `$` of `$$`, which is the PID parameter. Bash reads `$$'a\' # b'; cd src` as the PID, then the plain quote `'a\'`, then a comment that runs to the end of the line. The scanner reads `$'a\' # b'` as one ANSI string, finds no unquoted `#`, and returns False. The chain reader then denies a `cd` bash never runs.
   - Expected: `prompt`. Actual: deny (inferred from the code, not run).
   - The line has to contain `$$'…\'…#` followed by `; cd`, so the case is rare.
   - Fix: only an odd run of `$` can prefix a quote. Change the last statement of the loop to `after_dollar = (ch == ANSI_C_QUOTE_PREFIX and not literal and not after_dollar and not (in_single or in_double or in_ansi))`. Add the NOT_DENIED row `("ls $$'a\\' # b'; cd src", "prompt")`. Also add a DENY row for `$$$'#'`, which is a literal `#`.
