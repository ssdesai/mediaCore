# 04 — re-review: hook-hash-chained-cd, round 4

## What round 4 was supposed to do

Round 3 came back clean and the feature was closed. A threat test run afterwards, with
bash 3.2 and zsh 5.9 themselves as the oracle, found two defects in the guard
`unquoted_comment_char`. Both are wrong denies, neither a wrong approval.

1. **zsh reads `$$'…'` the other way from bash.** bash reads `$$` as the PID and the
   quote as a plain one (round 3's fix). zsh reads a `$` and then an ANSI-C quote. Claude
   Code runs the Bash tool in the user's own shell, and on macOS that is zsh by
   default. So `ls $$'a\' ' # '; cd <root>`
   was denied as a chained `cd`, while zsh reads its `#` as a comment and never runs
   the `cd`.
2. **Every reader after the guard lexes with shlex, which has no ANSI-C mode.** The
   guard read `$'a\'…'` correctly and the readers then ended the quote at the escaped
   one. `ls $'a\'; cd src '#\'` was denied though neither shell runs the `cd`, and
   `grep $'\'#' f` was told to close a quote that is closed. `main` has the same defect
   on lines with no `#` (`echo $'\''` is denied as not tokenizing); the branch extended
   it to lines with a quoted `#`, which `main` never judged.

The fix is one rule in the guard, renamed `never_judged`: a `$'…'` that escapes a quote
holds the line back from every deny and rewrite, `#` or no `#`, whatever run of `$`
precedes the quote. The guard no longer tries to model where such a quote ends. A
`$'…'` with no escaped quote ends where a plain quote does and is still judged.

The round also adds `self/tests/hook-quote-oracle.sh`, which checks the guard against
the shells, and records it in `self/gate.sh`.

## The diff

Scope this review to the round-4 commit only: run `git log --oneline -3` and review the
commit whose subject starts `hook-hash-chained-cd: round 4`, with `git show <its sha>`.
Rounds 1 to 3 are already reviewed, so do not re-review them.

## Contracts to hold it to

- **Nothing new is approved.** The only path to an `allow` is `command_allowed`, and
  the round must not touch it. `shell_active_outside_quotes` refuses any `$` outside
  single quotes, so no line with a `$'…'` is ever approved.
- **The two defects are fixed.** `ls $$'a\' ' # '; cd <root>`, `ls $'a\'; cd <root> '\'`
  and `echo $'\''` each prompt, with no deny.
- **A quoted `#` is still no excuse.** `cd <root> && grep $'#' f`,
  `cd <root> && grep $$'#' f`, `cd <root> && grep \$'#' f` and
  `cd <root> && grep $'a\\' f` (an escaped backslash, not an escaped quote) are denied.
- **The stated cost is the only cost.** A real chain carrying a `$'…\'…'`, such as
  `cd <root> && grep $'it\'s' f`, prompts instead of being denied. Probe for any other
  line that `main` denies correctly and this round no longer does. Holding a line back
  is the safe direction, but it should happen only for the two reasons the docstring
  gives.
- **The oracle test is a real check.** Read `self/tests/hook-quote-oracle.sh`: its fifth
  assertion must fail for a guard that returns True for everything, and its first four
  for a guard that returns False for everything. It must run only `:` and `echo` in the
  shells it drives.
- **Every earlier row still holds.** Run `bash self/tests/allow-repo-commands.sh`,
  `bash self/tests/hook-quote-oracle.sh` and `./self/gate.sh`. All must be green. The
  gate takes several minutes; give it a long timeout rather than reading an old report.
- **The READMEs match.** `hooks/README.md` → "The chained `cd`", `self/tests/README.md`
  and `self/README.md` describe the guard and the new test as the code has them.

## Verdict

Either "no findings" or a list of findings, each with a concrete command and its
expected versus actual decision. "No findings" is a legitimate verdict.
