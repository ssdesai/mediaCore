Verdict: escalated

# Review — orchestration-record-fixes, round 3 (`6110b3b`)

## What the batch was supposed to do

Close the independent audit of #139's findings F1–F6 in `hooks/allow-repo-commands.sh`.
The goal: no redirection, quoted operator word or substitution can hide a refspec, the remote
or the git command from the push rules. A push of `main` stays DENY in both profiles, a push
elsewhere gets the refusal of its plain form, and a grep pattern like `'\('` is approved.

## Does it do it?

For F1–F6 as listed, yes. I read `git diff a48717b..HEAD` and drove the hook myself with
about 85 payloads in both profiles: every audit payload, plus variants the audit didn't
list. The F1–F6 variants all give the intended answer:

- **Escaped operator words:** `\> main` and `';' main` are read as refspecs, so the push is
  denied.
- **Substitutions glued to an option:** `-o>(cat)`, `-o x=>(cat)`, `origin =>(cat)` and
  `git -C >(cat) push` are all read correctly.
- **Substitution and redirect mixes:** `cat <(git push …)`, `cat < <(git push …)`,
  `echo a$(git push …)b`, `;>x` and `&>>x` after a push, and `{fd}>x` inside a push's
  arguments all give the intended answer.
- **Descriptor edge cases:** `0002>x`, `\2>x` and `2147483647>x` / `2147483648>x` are all
  handled.
- **Quoting the masker must track:** `"a\"b"`, `'a\'` and `"a\\"` all keep the push that
  follows them DENY.

The F6 approvals hold: `grep -n '\(' …`, `'\|'`, `'\;'`, `rg -n '\(\)'` and
`git log --grep '\|' -1` are all ALLOW. `';'`, `'>'` and `\(` still go to the human.

None of my probes found a silent allow, either new or pre-existing. Every line that runs a
substitution I tried was refused approval.

The audit's payloads are rows of table T in `self/tests/hook-cloud-profile.sh`. NOTES.md
→ round 3 and `hooks/README.md` describe each fix. The gate is green, with nothing SKIPPED.

What remains is the feature's own stated contract for substitutions. The new code doesn't
make it worse, but it doesn't fully meet it either; details are below.

## Fixed in this pass

- `self/features/orchestration-record-fixes/README.md`: the plans table had no row for
  `03-review-opus`, although the manifest's `plans[]` already lists it. I added the row.

## Escalated to the next round

1. **A push of `main` inside a substitution is prompted, not denied, in two shapes.** The
   feature claims every substitution is scoped (NOTES.md round 3 F3; `hooks/README.md`: "`$(…)`
   … a word of the command around them with a scope of their own"). Both shapes below also
   behave this way on the round-2 hook, so this is a gap, not a regression. Both fail safe:
   they prompt, they never allow.
   - **Inside double quotes, or in backticks.**
     - `echo "$(git push origin HEAD:main)"`, ``echo "`git push origin HEAD:main`"`` and
       ``echo `git push origin HEAD:main` `` are each prompted in both profiles.
     - Cause: `mask_quoted_punctuation` (`hooks/allow-repo-commands.sh`, the new function
       above `punctuation_pieces`) masks the `(` of a `$(` inside double quotes, so the
       whole substitution becomes one word and `command_words` never sees the inner
       `git push`. Backticks are never scoped at all.
     - Fix: leave `$(` … `)` unmasked inside double quotes, so it scopes as it does
       unquoted. Handle backticks the same way, or deny a git push word found inside one.
     - Missing rows for table T, expected DENY/DENY:
       - `echo "$(git push origin HEAD:main)"`
       - ``echo `git push origin HEAD:main` ``
   - **As a git global option.**
     - `git $(true) push origin HEAD:main` is prompted in both profiles. Bash drops the
       empty expansion and runs a push of `main`.
     - Cause: after the `$(…)` scope closes, `command_words` leaves the word `$` in
       position, and `git_subcommand_args` takes it as the subcommand. The new
       stand-in skip only covers `<(` / `>(`.
     - Don't fix this by also skipping `$`. Unlike `<(…)`, a `$(…)` can expand into the
       subcommand itself: `git $(echo reset --hard) status` would then read as
       `git status` and could be approved.
     - Proposed fix: when a `$` stand-in sits among git's global options, deny the line
       if any later word would be a push or another denied subcommand, and otherwise
       refuse to judge it (it goes to the human).
     - Missing rows for table T:
       - `git $(true) push origin HEAD:main`: DENY/DENY.
       - `git $(echo reset --hard) status`: prompt, never ALLOW.

2. **Missing assertion: `punctuation_pieces` can hang.** Its `while` loop only advances
   because every character of `CHAIN_PUNCTUATION` (`"();<>|&\n"`) has a one-character
   entry in `PUNCTUATION_OPERATORS`. If someone adds a character to the first without
   the second, the hook spins forever on any line containing it. No test asserts this.
   - I tried to add a `for … else: raise ValueError(…)` guard, but this pass isn't
     allowed to edit the hook, so it's escalated.
   - Fix: add that guard, and add a test that every character in `CHAIN_PUNCTUATION`
     appears as a single-character operator in `PUNCTUATION_OPERATORS`.

### Seen, out of this feature's scope (no action asked)

These also prompt where bash runs a push of `main`, on the round-2 hook too. They involve
no redirection, quoting or substitution, so they fall outside this feature's contract:

- `{ git push origin HEAD:main; }` — a brace group.
- `git push origin HEAD:main #x` — a trailing comment.
- `git push origin {fd} HEAD:main` — a single-element brace word, which bash passes
  through literally.

They're listed only so a later feature on brace and comment handling can pick them up.
