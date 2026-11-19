Verdict: escalated

# Review — orchestration-record-fixes, round 7

## What the batch was supposed to do

Round 6 found that a `case` after a reserved word (`!`, `time`, `then`, `do`, `else`), or an
`esac` used as a pattern word (`x|esac)`), threw off the case counter in
`mask_quoted_punctuation`. That let a `git push origin main` inside a substitution go unseen.
Commit `3964af3` handles this with a third reading, `command_words_crude`
(`hooks/allow-repo-commands.sh`). It applies only to a line that holds a substitution and the
word `case`. It cuts the line at every operator, quote, paren, brace, `$` and descriptor, then
drops reserved words from the front of each fragment. It feeds only the deny judges.

## Does it do it?

Partly. All 15 new rows in `self/tests/hook-cloud-profile.sh` hold, and so does the gate (its
one red line is the non-blocking rates-staleness probe). `command_allowed` is untouched. The
false-depth rows still prompt or allow as pinned. In my own runs, the crude reading also
catches descriptors, redirects, `${IFS}`, backticks, `<(…)`, `[[ … ]] ||`, `for`/`select`/
`function` bodies, `git -C`/`-c`, `/usr/bin/git` and `;;esac`, in both profiles.

**But cutting at quotes is the dangerous way to be crude.** Inside `"$(…)"` the shell starts a
fresh quoting context, so a quote or backslash inside the substitution only joins pieces of the
same word. The crude cut instead splits that word in two. When the structural readings are
already fooled by the `case` (which is what this reading is for), splitting the word hides the
refspec or the `git` word. These lines were driven through the hook; each plain form is
**DENY** in both profiles:

| Line | cloud | local |
|---|---|---|
| `echo "$(! case x in x) git push origin "main";; esac)"` | PROMPT | PROMPT |
| `echo "$(! case x in x) git push origin 'main';; esac)"` | PROMPT | PROMPT |
| `echo "$(! case x in x) git push "origin" main;; esac)"` | PROMPT | PROMPT |
| `echo "$(! case x in x) 'git' push origin main;; esac)"` | PROMPT | PROMPT |
| `echo "$(! case x in x) \git push origin main;; esac)"` | PROMPT | PROMPT |
| `echo "$(! case x in x) true;; esac; git push origin "main")"` | PROMPT | PROMPT |
| `echo "$(! case x in x) git push origin ma""in;; esac)"` | DENY | PROMPT |
| `echo "$(! case x in x) git push origin m\ain;; esac)"` | DENY | PROMPT |

These are pushes to `main`, and in bash each one really pushes `main`. The feature's contract
is that pushes to `main` stay DENY in both profiles even when a quote is present, and these
lines break it. The `!` can be replaced by any reserved word from round 6 (`time`, `then …`,
`x|esac)`).

## Fixed in this pass

Nothing. Only one local fix was needed, a docstring update (below), and the policy refused
edits to `hooks/allow-repo-commands.sh` in this pass. So it is escalated with the rest.

## Escalated to the next round

1. **`command_words_crude` must join a word across quotes and backslashes, not cut it**
   (`hooks/allow-repo-commands.sh`, `CRUDE_CUT_RE` at about line 1044 and the split in
   `command_words_crude`). Suggested shape:
   - Remove `"` and `'` from `CRUDE_CUT_RE`.
   - Before splitting, delete every `"`, `'` and `\` from the line, for example with a
     `CRUDE_JOINED_CHARS = "\"'\\"` constant and `str.translate`.

   The result is still crude and still only denies more, so it is safe in the
   fail-closed direction. For example, `$'git'` becomes `$git`, then the cut at `$` leaves
   `git`. Add every row of the table above to `self/tests/hook-cloud-profile.sh` as
   `D, D`. Also add the rows `echo "$(time case x in x) git push origin "main";; esac)"` and
   ``echo "`! case x in x) git push origin "main";; esac`"``. Keep the false-depth rows
   (`cat "$(echo case-x)" README.md` → P, P; `grep -n "case" README.md` → A, A) green.
   Choosing to join rather than cut is a design decision about the crude reading, which is why
   it is escalated and not patched here.

2. **Docstring drift** in `command_words` (`hooks/allow-repo-commands.sh:1303`). It still says
   "The line is read twice and the commands of both are returned". It should say the line is
   read two ways, or three for a line with a substitution and the word `case` (the third being
   `command_words_crude`), and that the commands of every reading are returned. The
   `hooks/README.md` paragraph is accurate.

## Observed, not caused by this round

- With no substitution and no `case`, `! git push origin main`, `command git push …`,
  `env git push …`, `X=1 git push …`, `exec`/`nohup`/`coproc git push …` and `gi? push …`
  all **prompt** rather than deny, in both profiles. This is unchanged by this round: the
  crude reading never applies to these lines. A prompt still goes to the human, so nothing is
  approved. Still, the `!` case is a shell grammar shape the structural readings do not
  follow, and it hides the push from the deny. The next round should decide whether the
  deny's contract covers reserved words and command wrappers, and pin the answer with a row
  either way.
