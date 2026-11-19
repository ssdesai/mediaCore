Verdict: escalated

# Security audit (round 5): orchestration-record-fixes, hook rules changed against `origin/main`

Head audited: `HEAD` of `claude/orchestration-record-fixes`, run from a `git archive HEAD`
copy of `hooks/`. The same payloads also ran against `origin/main`'s `hooks/` for comparison.
Fixture: a consuming repo on its started feature branch `claude/feat-x` (tracked manifest,
`branches[0]`), with the hook vendored under `agentTooling/hooks/` and an `origin` holding
`main` and the branch. Every payload ran in both profiles (`AGENTTOOLING_PROFILE=local` /
`cloud`). In the tables, `prompt` means no output, so the human is asked. `BR` is
`claude/feat-x` and ⏎ is a line break.

## Rules the diff adds or changes

| # | Rule (what it denies or asks, for whom) |
|---|---|
| R1 | `mask_quoted_punctuation` + `QuotedWord` in `chain_tokens`: a quoted or escaped operator character is an argument, not a separator or redirect, on the deny side (git rules, `chains_chdir`, `assigned_names`, `invokes_build_script`). |
| R2 | `quoted_separator_word` in `command_allowed`: a line with a quoted operator-only word is never approved silently. |
| R3 | `is_bare_descriptor` / `MAX_DESCRIPTOR` / `VARIABLE_DESCRIPTOR_RE`: only a whole unquoted ASCII digit run ≤ INT_MAX, or `{name}`, directly before `<`/`>` is dropped as a descriptor. |
| R4 | `punctuation_pieces`: a punctuation run is split as bash splits it. Only redirect pieces take a target, and separators start a new command. |
| R5 | Substitution scoping (`$(…)`, backticks, `<(…)`/`>(…)`). The mask lifts a `$(…)` or backtick pair out of the double quotes around it so its body is judged. **New this round:** `command_words` returns the union of the *scoped* reading and a *flat* reading (`chain_tokens(lift=False)`, every operator ends a command). This is the fix for round 4's B1. |
| R6 | `git_subcommand_args` skips a `<(`, `>(` or `$` stand-in among git's global options. This applies on the deny side only. |
| — | `analysis/report.py`, `analysis/roots.py` (`record_repo_root`, `home_root`) are not PreToolUse rules, and no hook input reaches them. `hooks/README.md` is documentation. |

Round 4's B1 is fixed. Every unquoted form it listed is DENY again, in both profiles. Batch 1 is below.

## Bypass found

### B2 (R5, the lift rule): a `case` arm's `)` inside a **double-quoted** `$(…)` or backtick pair still hides the command after it

The flat reading added for B1 does not cover this form. It masks quotes only, so everything
inside `"…"` is one word to it. The scoped reading's mask (`mask_quoted_punctuation`, lift
on) closes the lifted substitution at the case pattern's `)`, then returns to
`CONTEXT_DOUBLE` and masks the rest of the substitution, which is the command bash actually
runs. Neither reading sees that command, so no git rule judges it.

The lift rule exists so that `echo "$(git push origin main)"` is judged as the push it is.
It is (DENY on this head, prompt on base). The same push behind a case arm is not:

| Input (prompt on base and head, both profiles) | bash runs |
|---|---|
| `echo "$(case x in x) git push origin main;; esac)"` | `git push origin main` |
| ``echo "`case x in x) git push origin main;; esac`"`` | `git push origin main` |
| `echo "x$(case x in x) git push origin main;; esac)y"` | `git push origin main` |
| `echo "$(case x in x) git reset --hard HEAD~1;; esac)"` | `git reset --hard` |
| `echo "$(case x in x) git push origin HEAD:other;; esac)"` (cloud refuses this push when unhidden) | push elsewhere |
| `echo "$(case x in x) git stash;; esac)"` (`echo "$(git stash)"` is DENY on head) | `git stash` |
| `X="$(case x in x) git push origin main;; esac)"` | `git push origin main` |
| `echo $(case x in x) echo "$(case y in y) git push origin main;; esac)";; esac)` | `git push origin main` |

To confirm that bash really runs the hidden command, I ran `bash
/tmp/plan-capture.BsH7wj/scratch/bashcheck.sh` with `echo RAN-…` in place of the git
command. It printed `RAN-quoted-dollar`, `RAN-quoted-backtick`, `RAN-quoted-mid`,
`RAN-assign` and `RAN-nested`.

Severity: this is never a silent allow. The allow side refuses any `$` or backtick, so the
human is prompted with the command in plain sight. It is also not a regression: `origin/main`
prompted for all of these. But it gets past the deny rule this diff adds, and it is the same
mechanism as B1. The B1 fix took round 4's option (b), which only reaches unquoted text.

What the rule should do instead: never let a case pattern's `)` close a substitution
scope. Either option fixes both B1 and B2:

- **(a)** In `mask_quoted_punctuation`, track `case … in` / `esac` depth per
  `CONTEXT_SUBSTITUTION` / `CONTEXT_BACKTICK` frame. A `)` seen while a `case` in that frame
  is open (between `in`/`;;` and its pattern's end) is a pattern terminator, not the scope's
  end.
- **(b)** Fail closed on the deny side only. Add a third reading in which, once a `$(` or
  backtick is lifted inside double quotes, the text up to the closing `"` stays unmasked.
  This can only deny more.

Add the eight lines above to `self/tests/hook-cloud-profile.sh` table T as DENY in both
profiles. The cloud-only `HEAD:other` line should get the cloud refusal.

## Not counted (pre-existing, unchanged by this diff, never a silent allow)

- `echo $(if true; then git push origin main; fi)` / `echo "$(if …; fi)"`: prompt on base
  and head. The `then git …` head word is not read as git inside a substitution, while the
  top-level `if true; then git push origin main; fi` is DENY. This is a keyword-stripping
  gap that predates this diff.
- Comments with line breaks inside a substitution (`echo $(true # )⏎git push origin main⏎)`):
  prompt everywhere, from the existing never-judged guards.
- Round 4's pre-existing items (ANSI-C `$'\''`, braces, wrappers) were not re-run for this
  round. The code paths they exercise are untouched since round 4, and its table stands.
- Malformed payloads were not re-run either. Payload parsing is unchanged since round 4,
  which tested them (all exit 0, no crash).

## Every input tried

Columns: base local · base cloud · head local · head cloud.

### Batch 1: the B1 fix and its quoted variants

| Input | base local | base cloud | head local | head cloud |
|---|---|---|---|---|
| `git status` | ALLOW | ALLOW | ALLOW | ALLOW |
| `git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR` | prompt | ALLOW | prompt | ALLOW |
| `git push origin BR 2>&1 \| tail -3` | prompt | ALLOW | prompt | ALLOW |
| `echo $(case x in x) git push origin main;; esac)` | DENY | DENY | DENY | DENY |
| ``echo `case x in x) git push origin main;; esac` `` | DENY | DENY | DENY | DENY |
| `cat <(case x in x) git push origin main;; esac)` | DENY | DENY | DENY | DENY |
| `echo $(case x in x) git push origin HEAD:other;; esac)` | prompt | DENY | prompt | DENY |
| `echo $(case x in x) git reset --hard HEAD~1;; esac)` | DENY | DENY | DENY | DENY |
| `echo $(case x in x) git switch main;; esac)` | prompt | DENY | prompt | DENY |
| **`echo "$(case x in x) git push origin main;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| **``echo "`case x in x) git push origin main;; esac`"``** (B2) | prompt | prompt | **prompt** | **prompt** |
| **`echo "x$(case x in x) git push origin main;; esac)y"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x) true;; esac; git push origin main)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x) git reset --hard HEAD~1;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x) git push origin HEAD:other;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| `echo $(echo $(case x in x) git push origin main;; esac))` | DENY | DENY | DENY | DENY |
| `echo $(case x in x)git push origin main;; esac)` | DENY | DENY | DENY | DENY |
| `echo $(case x in x\|y) git push origin main;; esac)` | DENY | DENY | DENY | DENY |
| `( case x in x) git push origin main;; esac )` | DENY | DENY | DENY | DENY |
| `echo $(case x in x) "git" push origin main;; esac)` | DENY | DENY | DENY | DENY |
| `echo $(case x in x) g""it push origin main;; esac)` | DENY | DENY | DENY | DENY |
| **`echo "$(case x in x) g''it push origin main;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| `if true; then git push origin main; fi` | DENY | DENY | DENY | DENY |
| `echo $(if true; then git push origin main; fi)` (pre-existing) | prompt | prompt | prompt | prompt |
| `echo "$(if true; then git push origin main; fi)"` (pre-existing) | prompt | prompt | prompt | prompt |
| `echo $(true) git push origin main` | DENY | DENY | DENY | DENY |
| `echo "$(echo ')'; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(echo ")"; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(echo \); git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$( (true) ; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$((1)) $(git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(( 1 ))"; git push origin main` | DENY | DENY | DENY | DENY |
| `echo $((1)) git push origin main` | DENY | DENY | DENY | DENY |
| `echo "$(echo $((1)) ; git push origin main)"` | prompt | prompt | DENY | DENY |
| `git push origin BR "$(case x in x) :main;; esac)"` | prompt | DENY | prompt | DENY |
| `git push origin $(case x in x) main;; esac)` | prompt | DENY | DENY | DENY |
| `git push origin "$(case x in x) main;; esac)"` | prompt | DENY | prompt | DENY |
| `git $(case x in x) push;; esac) origin HEAD:main` | prompt | prompt | prompt | prompt |
| `echo "$(cat <(case x in x) git push origin main;; esac))"` (B2) | prompt | prompt | prompt | prompt |
| ``echo "a`echo b`c $(case x in x) git push origin main;; esac)"`` (B2) | prompt | prompt | prompt | prompt |

### Batch 2: chdir chaining, descriptors, operator pieces, quoted separators on the allow side

| Input | base local | base cloud | head local | head cloud |
|---|---|---|---|---|
| `cd /tmp && ls` | DENY | DENY | DENY | DENY |
| `cd /home && ls` | DENY | DENY | DENY | DENY |
| `cd /tmp;>x ls` | prompt | prompt | DENY | DENY |
| `cd /tmp\|>x ls` | prompt | prompt | DENY | DENY |
| `cd /tmp ';' ls` (bash: one `cd`, three args; base was a false deny) | DENY | DENY | prompt | prompt |
| `case x in x) cd /tmp;; esac; ls` | DENY | DENY | DENY | DENY |
| `case x in x) cd /tmp;; esac && ls` | DENY | DENY | DENY | DENY |
| `true && case x in x) cd /tmp;; esac; ls` | DENY | DENY | DENY | DENY |
| `cd /tmp 2>/dev/null; ls` | DENY | DENY | DENY | DENY |
| `cd /tmp 2>';' ; ls` | DENY | DENY | DENY | DENY |
| `cd /tmp {fd}>/dev/null; ls` | DENY | DENY | DENY | DENY |
| `cd /tmp <(true); ls` | DENY | DENY | DENY | DENY |
| `cd /tmp $(true); ls` | DENY | DENY | DENY | DENY |
| `cd "/tmp"; ls` | DENY | DENY | DENY | DENY |
| `cd /tmp\;ls` | prompt | prompt | prompt | prompt |
| `cd /tmp;&ls` | DENY | DENY | DENY | DENY |
| `cd /tmp;;&ls` | DENY | DENY | DENY | DENY |
| `git push origin 2<(true) main` | prompt | prompt | DENY | DENY |
| `git push origin BR 2<(true)` (bash: refspec `2/dev/fd/63`) | prompt | prompt | prompt | DENY |
| `git push origin main2>x` | prompt | DENY | prompt | DENY |
| `git push origin BR main&>x` | DENY | DENY | DENY | DENY |
| `git push origin BR 2&>x main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2>x main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2>&1 main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2<>x main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2>\|x main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2<<<x main` | DENY | DENY | DENY | DENY |
| `git push origin BR 0002>x :main` | DENY | DENY | DENY | DENY |
| `git push origin BR 2147483647>x :main` | DENY | DENY | DENY | DENY |
| `git push origin BR {fd}>x :main` | prompt | prompt | DENY | DENY |
| `git push origin BR {fd}<x :main` | prompt | prompt | DENY | DENY |
| `git push origin BR {_}>x :main` | prompt | prompt | DENY | DENY |
| `git push origin BR {fd}>&- :main` | prompt | prompt | DENY | DENY |
| `git push origin ma\⏎in` | DENY | DENY | DENY | DENY |
| `git push origin BR ;;& git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR ;& git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR \|& git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR >\| x git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR >\|x main` | DENY | DENY | DENY | DENY |
| `git push origin BR <>x main` | DENY | DENY | DENY | DENY |
| `git push origin BR &>>x main` | DENY | DENY | DENY | DENY |
| `git push origin BR >&2 main` | DENY | DENY | DENY | DENY |
| `git push origin BR >& main` (bash: `main` is the redirect target) | prompt | prompt | prompt | prompt |
| `git push origin BR 2>&1 \| tail -3 ';' main` | prompt | prompt | prompt | prompt |
| `git push origin BR ';' \| tail -3` | prompt | ALLOW | prompt | DENY |
| `git push origin BR ';'\| tail -3` | prompt | ALLOW | prompt | DENY |
| `git push origin BR '\|' tail` | prompt | ALLOW | prompt | DENY |
| `git push origin BR "\|"` | prompt | ALLOW | prompt | DENY |
| `git push origin BR \\|` | prompt | ALLOW | prompt | DENY |
| `git push origin BR \\| tail` | prompt | ALLOW | prompt | DENY |
| `git push origin BR '' \| tail` | prompt | prompt | prompt | DENY |
| `git push origin BR $'\|' tail` | prompt | DENY | prompt | DENY |
| `git push -u origin BR ';'` | prompt | ALLOW | prompt | DENY |
| `git push -u origin BR '&'` | prompt | ALLOW | prompt | DENY |
| `ls ';'` | ALLOW | ALLOW | prompt | prompt |
| `ls '\|' README.md` | prompt | prompt | prompt | prompt |
| `grep -n '\|' README.md` | prompt | prompt | prompt | prompt |
| `grep -n x'\|'y README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `grep -n 'a\|b' README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `grep -nE '(a\|b)' README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `grep -n \( README.md` | prompt | prompt | prompt | prompt |
| `grep -n '\(' README.md` | ALLOW | ALLOW | ALLOW | ALLOW |

### Batch 3: the quoted-case family and its neighbours

| Input | base local | base cloud | head local | head cloud |
|---|---|---|---|---|
| `echo "$(case x in (x) git push origin main;; esac)"` (balanced pattern) | prompt | prompt | DENY | DENY |
| `echo $(case x in x) "$(git push origin main)";; esac)` | prompt | prompt | DENY | DENY |
| **`echo $(case x in x) echo "$(case y in y) git push origin main;; esac)";; esac)`** (B2) | prompt | prompt | **prompt** | **prompt** |
| `echo $(true # )⏎git push origin main⏎)` (pre-existing, `#`) | prompt | prompt | prompt | prompt |
| `echo "$(true # ")⏎git push origin main⏎)"` (pre-existing, `#`) | prompt | prompt | prompt | prompt |
| `echo "$(case x in x) git push origin main;; esac)" ; ls` (mixed-line deny) | DENY | DENY | DENY | DENY |
| **`X="$(case x in x) git push origin main;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| `cat "$(case x in x) git push origin main;; esac)"` (B2) | prompt | prompt | prompt | prompt |
| `ls "$(case x in x) git push origin main;; esac)"` (B2) | prompt | prompt | prompt | prompt |
| `git log "$(case x in x) git push origin main;; esac)"` (B2) | prompt | prompt | prompt | prompt |
| `echo "$(case x in x) git checkout -- .;; esac)"` (B2) | prompt | prompt | prompt | prompt |
| `echo "$(case x in x) git clean -fdx;; esac)"` (B2) | prompt | prompt | prompt | prompt |
| **`echo "$(case x in x) git stash;; esac)"`** (B2) | prompt | prompt | **prompt** | **prompt** |
| `echo "$(git stash)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) cd /tmp;; esac)" && ls` | DENY | DENY | DENY | DENY |
| `echo "$(case x in x) ./run-plans.sh --self x;; esac)"` (hidden-code deny) | DENY | DENY | DENY | DENY |
| `echo $(case x in x) ./run-plans.sh --self x;; esac)` (no orchestrator role: the build-script judge does not apply) | prompt | prompt | prompt | prompt |
| `echo "$(case x in x) X=/tmp;; esac); cat $X/f"` | DENY | DENY | DENY | DENY |

No input produced a silent ALLOW on this head that runs a command the hook exists to refuse.
Every head-side change from base is a new DENY, a prompt where base wrongly denied
(`cd /tmp ';' ls`), or a prompt where base silently allowed (`ls ';'`, R2 by design).
