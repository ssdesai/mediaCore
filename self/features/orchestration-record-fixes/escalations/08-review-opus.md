Verdict: escalated

# Review — orchestration-record-fixes, round 8

## What this round was supposed to do

Close round 7's B4. The crude reading (`command_words_crude`) cut a line at quotes and kept
backslashes, so a quoted refspec or a quoted `git` word could hide a push from the push rules.
Commit `7bffa68` now deletes `"`, `'` and `\` before the cut (`CRUDE_JOINED_CHARS`). It then
cuts at operators, parens, braces, backticks and `$`. Fifteen round-7 rows were added to table T
in `self/tests/hook-cloud-profile.sh`, and `hooks/README.md` and the docstrings were updated.

## Does it do it

It fixes what it set out to fix. I ran the hook on each probe with a fresh `session_id` under
both profiles:

- **Quoting no longer hides anything.** These are all DENY in both profiles: `git"" push`,
  `""git push`, `$'git'`, `ma""in` and `git -C . push`. So are a push with a trailing
  `>/dev/null` and a push after a nested `!`.
- **The pinned shapes behave as pinned.** The documented false deny `grep -n "case $(x) git
  push origin main" README.md` is still DENY. `grep -n "case" README.md` and
  `grep -n '\(case' README.md` are ALLOW. `cat "$(echo case-x)" README.md` prompts.
- **Gate:** `self/gate-report.txt` says all checks passed, with nothing SKIPPED.

One gap stays green: **a redirect placed before the command** still hides it from the crude
reading, which goes against the feature's main contract ("a redirection never hides … the git
command").

## Fixed in this pass

Nothing. My fix to `hooks/allow-repo-commands.sh` (a single regex constant) was refused: this
pass cannot write to the hook file. The fix is given below so the next round can apply it as
written.

## Escalated

### B5 — a redirect before the command hides the push in the crude reading

**Payloads.** Each of these PROMPTs in **both** `cloud` and `local`. The contract says DENY:

```
echo "$(! case x in x) 2>&1 git push origin main;; esac)"
echo "$(case x in x|esac) 2>&1 git push origin main;; esac)"
echo "$(! case x in x) >&2 git push origin main;; esac)"
echo "$(! case x in x) >x git push origin main;; esac)"
echo "$(! case x in x) 2>&1 git stash;; esac)"
```

**Same shapes with no `case`, denied in both profiles:** `2>&1 git push origin main`,
`>&2 git push origin main` and `echo $(true) 2>&1 git push origin main`. The `case` shape of
`>/dev/null git push …` and `</dev/null …` is also DENY, but only because a different rule
fires ("hides code"), not the push rule.

**Cause.** `CRUDE_CUT_RE` (`hooks/allow-repo-commands.sh:1044`) cuts at `>` and `&` but keeps
the redirect's target. That leaves `1`, `2` or `x` as the first word of the fragment:
`1 git push origin main`. The fragment's command becomes `1`, so the push rules never see `git`.

**Fix (checked offline on the payloads above):** cut each redirect out whole, meaning its fd,
operator and target word together:

```python
CRUDE_CUT_RE = re.compile(r"(?:(?<!\S)\d+)?[<>]+[&|]?[ \t]*[^\s;&|()<>{}`$]*"
                          r"|[;&|()<>{}\n`$]")
```

- **The target is never longer than bash's.** Its character class stops at every character
  where bash ends a word, plus `{}`$`. So a real command is never swallowed as a target.
- **Process substitution still works.** `<(git push origin main)` gets an empty target, then
  cuts at `(`.
- **`>&-` works.** The `-` is consumed as the target.
- **The pinned false deny holds.**
- **One known edge, safe.** In `>"" git push …` the deleted empty quotes would let the target
  swallow `git`. Bash does not run that command either, because the redirect fails, so there is
  nothing to deny.

**Also needed:**

- Update the comment at `:1039-1042`. It currently says the line is cut "at a redirect's file
  descriptor".
- Update the crude-reading sentence in `hooks/README.md` (~line 529).
- Add the five payloads above to table T as `D, D`, plus
  `echo "$(! case x in x) 2>&1 git push origin HEAD:other;; esac)"` as `P, D`. It prompts in
  both profiles today; the cloud should refuse it.
- **The missing invariant to assert:** every round-7 row, with `2>&1 ` inserted before its git
  word, keeps the row's expected answer.

## Noted, not escalated

`x=1 git push origin main` (an assignment prefix) prompts at the top level in both profiles, and
inside the `case` shapes too. It has no redirect, quote or substitution, so it falls in the same
class as the `env`/`command`/`exec` wrappers this round marks as decided and out of scope. I do
not think the contract covers it. It is recorded here with its payload in case the owner
decides it should.
