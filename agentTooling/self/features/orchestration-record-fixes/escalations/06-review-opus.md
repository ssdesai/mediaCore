Verdict: escalated

# Review — orchestration-record-fixes, round 6

## What the batch was supposed to do

Commit `314904b` closes round 5's escalations. The first is B2: inside a double-quoted (or
backtick, or assigned) substitution, a `case` arm's `)` ended the hook's scoped reading of
`$(…)` early. That let `git push origin main` after it read as quoted text, and the flat
reading (which masks by quotes only) hid it too. The second is the missing "the union
approves nothing" row. The fix: `mask_quoted_punctuation(lift=True)` counts the open
`case`s in each substitution or backtick frame. A `case` counts only when it is at command
position, which the code checks as "the character before it is in
`CASE_COMMAND_PRECEDERS` = `;&|(\n{`". While a `case` is open, a `)` is read as a
separator (`CASE_PATTERN_SEPARATOR`).

## Does it do it

It does for the shapes it was written for. I drove the hook in both profiles, and these are
all **deny** in cloud and local: the audit's eight table lines, `echo $(case x in (x) git
push origin main;; esac)`, `x|y)` patterns, `;&` and `;;&` terminators, nested cases, a
`case` inside a `( … )` subshell inside the substitution, and `true && case …`.
`echo $(true) git status` is still a prompt. `grep -n "(x)"` is still approved, and
`git log --format="%H $(echo case)" -1` is unchanged. Fail-safe edges hold:
- **False depth fails safe.** `${case}`, `case-x`, and a missing `esac` only leave a scope
  open. A missing `esac` gives a prompt, and the others gave the same answers as before.
- **`echo case` does not count**, because the word before it is not in the precedes list.

The gate is green, with no SKIPPED checks.

**The command-position test is incomplete, so the B2 bypass is still open behind a reserved
word.** A `case` that follows `then`, `do`, `else`, `elif`, `!` or `time` is at command
position for bash. The counter does not count it, because the character before it is a
letter or `!`, not one of `;&|(\n{`. The pattern's `)` then closes the substitution again,
and the push lands back inside the outer double quotes. Each of these comes back as a
**prompt in both profiles** where the contract requires **deny**:

```
echo "$(if true; then case x in x) git push origin main;; esac; fi)"
echo "$(while true; do case x in x) git push origin main;; esac; done)"
echo "$(if false; then :; else case x in x) git push origin main;; esac; fi)"
echo "$(! case x in x) git push origin main;; esac)"
echo "$(time case x in x) git push origin main;; esac)"
```

In each one bash runs `git push origin main`. Because the result is a prompt and not an
allow, a human still sees the line, but that is the B2 contract failing.

## Fixed in this pass

Nothing. The fix needs a design decision (below), so it is not a local edit.

## Escalated to the next round

1. **`hooks/allow-repo-commands.sh:1101`: `case` at command position after a reserved word
   is not counted.**
   - **What's wrong:** the check `before[-1] in CASE_COMMAND_PRECEDERS` only looks at the
     single character before the keyword.
   - **What it should be:** bash also puts a command, and so a reserved word, after the
     reserved words `then do else elif ! time` (and after `time -p`, and after `{` followed
     by a space, which the current check already covers). The check should also accept
     `before`'s last word when it is in such a set (for example a
     `CASE_COMMAND_PRECEDING_WORDS` constant).
   - **The decision:** this is the same root cause as the pre-existing `if … then git push
     …` inside a substitution (the audit named it pre-existing): the hook has no
     reserved-word model of command position. The next round should decide whether to
     model those words once, for both the case counter and command heads, or patch only the
     counter.
   - **Tests to add:** the five lines above, as `D, D` rows in the `TABLE` of
     `self/tests/hook-cloud-profile.sh`, next to the round-5 B2 rows.
2. **Missing test (no code defect found):** no row asserts the fail-safe direction of a
   false depth. Add these to the same `TABLE`; they were prompts under the current code and
   should stay prompts:
   - `cat "$(echo case-x)" README.md` stays P.
   - `echo "$(case x in x) git push origin main;;)"` (no `esac`) stays P, not A.

   They would catch a later change that made a wrongly opened scope approve something.
