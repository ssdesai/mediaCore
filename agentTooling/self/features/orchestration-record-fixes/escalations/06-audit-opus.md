Verdict: escalated

# Security audit (round 6): orchestration-record-fixes, hook rules changed against `origin/main`

Head audited: `HEAD` of `claude/orchestration-record-fixes` (the hook's last change is
`314904b`, round 5's rework). It ran from a `git archive HEAD` copy of `hooks/`, and
`origin/main`'s `hooks/` ran the same payloads for comparison. The fixture is a consuming
repo on its started feature branch `claude/feat-x`, with a tracked manifest naming the
branch as `branches[0]`, the hook vendored under `agentTooling/hooks/`, and an `origin`
holding `main` and the branch. Every payload ran in both profiles
(`AGENTTOOLING_PROFILE=local` / `cloud`). In the tables, `prompt` means the hook printed
nothing, so the human is asked. `BR` is `claude/feat-x` and ⏎ is a line break.

## Rules the diff adds or changes

| # | Rule (what it denies or asks, for whom) |
|---|---|
| R1 | `mask_quoted_punctuation` + `QuotedWord`: a quoted or escaped operator character is an argument, not a separator or a redirect, on the deny side. |
| R2 | `quoted_separator_word` in `command_allowed`: a line holding a quoted operator-only word is never approved silently. |
| R3 | `is_bare_descriptor`: a descriptor is only a whole unquoted ASCII digit run no larger than INT_MAX, or a `{name}`, directly before `<`/`>`. |
| R4 | `punctuation_pieces`: a punctuation run is split the way bash splits it. |
| R5 | Substitution scoping: `$(…)`, backticks and `<(…)`/`>(…)` each form a scope, a `$(…)` or backtick pair is lifted out of double quotes, and `command_words` returns the union of the scoped and flat readings. |
| R6 | `git_subcommand_args` skips a `<(`, `>(` or `$` stand-in among git's global options (deny side only). |
| **R7** | **New since round 5:** `CASE_KEYWORD_RE` / `CASE_COMMAND_PRECEDERS` / `CASE_PATTERN_SEPARATOR`. The mask counts the open `case`s in each substitution or backtick frame. A `case` or `esac` counts only when the text before it ends in one of `;&\|(⏎{`. While the count is above zero, a `)` in that frame is a separator and does not close the substitution. This is the fix for round 5's B2. |
| — | `analysis/report.py` and `analysis/roots.py` (`record_repo_root`, `home_root`) are not PreToolUse rules, and no hook input reaches them. `hooks/README.md` is documentation. |

Round 5's B2 forms are fixed: every row of its list is DENY in both profiles (batches 1–2).
R7's condition for counting a keyword is narrower than bash's in two ways, though, and each
brings B2 back.

## Bypasses found

Both bypasses have the same effect as B2. When R7 miscounts, a case pattern's `)` closes the
lifted substitution. The mask returns to `CONTEXT_DOUBLE` and masks the rest of the
substitution, which is the command bash actually runs. The flat reading treats the whole
double-quoted word as one word. Neither reading sees the command, so no git rule judges it.

Severity: neither bypass is ever a silent allow. The allow side refuses every `$` and
backtick, so the human is prompted with the command in plain sight. Neither is a regression
either, because `origin/main` prompts for all of them. But each gets past the deny rule this
diff adds, and the unquoted spelling of the same line is DENY.

### B3a (R7): a `case` after a reserved word is not counted

`CASE_COMMAND_PRECEDERS` holds only punctuation. Bash also reads `case` as a keyword after
the reserved words that start a command: `!`, `time`, `then`, `do`, `else`, `elif`, `if`,
`while` and `until`.

| Input (prompt on base and head, both profiles) | bash runs |
|---|---|
| `echo "$(! case x in x) git push origin main;; esac)"` | `git push origin main` |
| `echo "$(time case x in x) git push origin main;; esac)"` | `git push origin main` |
| `echo "$(! case x in x) true;; esac; git push origin main)"` | `git push origin main` |
| `echo "$(time case x in x) true;; esac; git push origin main)"` | `git push origin main` |
| `echo "$(while case x in x) false;; esac; do :; done; git push origin main)"` | `git push origin main` |
| `echo "$(! case x in x) git stash;; esac)"` | `git stash` |
| `echo $(echo "$(! case x in x) git push origin main;; esac)")` | `git push origin main` |

The rows where the push follows `;` show that the cause is the miscount, not the
pre-existing `then git …` gap (see "Not counted"). The `then`, `do` and `else` forms also
prompt, but their git command sits behind `then`/`do`/`else` as well, so they are not
counted here.

### B3b (R7): an `esac` inside a pattern list is counted as closing the `case`

An `esac` after `|` passes R7's check, because `|` is in `CASE_COMMAND_PRECEDERS`, so the
count drops to zero. In a pattern list, bash reads `esac` as an ordinary pattern word.

| Input (prompt on base and head, both profiles) | bash runs |
|---|---|
| `echo "$(case x in x\|esac) git push origin main;; esac)"` | `git push origin main` |
| `echo "$(case x in x \| esac) git push origin main;; esac)"` | `git push origin main` |
| `echo "$(case x in y) true;; x\|esac) git push origin main;; esac)"` | `git push origin main` |
| ``echo "`case x in x\|esac) git push origin main;; esac`"`` | `git push origin main` |
| `X="$(case x in x\|esac) git push origin main;; esac)"` | `git push origin main` |
| `echo "$(case x in x\|esac) true;; esac; git push origin main)"` | `git push origin main` |
| `echo "$(case x in x\|esac) git reset --hard HEAD~1;; esac)"` | `git reset --hard` |
| `echo "$(case x in x\|esac) git stash;; esac)"` | `git stash` |
| `echo "$(case x in x\|esac) git push origin HEAD:other;; esac)"` (the cloud refuses this push when unhidden) | push elsewhere |
| `echo "$(case x in x) echo \"$(case y in y\|esac) git push origin main;; esac)\";; esac)"` | `git push origin main` |

To confirm that bash really runs the hidden command, I ran
`/tmp/plan-capture.bvpezK/scratch/bashcheck.sh` and `bashcheck2.sh` with `echo RAN-…` in
place of the git command. They printed `RAN-bang`, `RAN-time`, `RAN-then`, `RAN-else`,
`RAN-do`, `RAN-while`, `RAN-until`, `RAN-pipe-esac`, `RAN-second-arm`, `RAN-spaced`,
`RAN-backtick`, `RAN-assign`, `RAN-after`, `RAN-bang-after`, `RAN-nested-bang` and
`RAN-nested-pipe-esac`. `esac|x)` is no bypass, because bash rejects it (it printed nothing
and the hook denies it anyway). `\case` is no bypass either, because bash does not treat a
quoted `case` as a keyword.

### What the rule should do instead

- **B3a:** also count a `case` whose preceding word is a reserved word at command position:
  `!`, `time` (and `time -p`), `then`, `do`, `else`, `elif`, `if`, `while` and `until`.
  Counting too often only keeps a scope open longer, which denies more. When in doubt,
  count every `case` that is not glued to an identifier character.
- **B3b:** decrement only on an `esac` that ends the statement: after `;;`, `;&` or `;;&`,
  after `;` or a newline in an arm's body, or directly after `in`. Never decrement on one
  that sits in a pattern list (after `|`, or between `in`/a terminator and that pattern's
  `)`). That needs a per-frame state for pattern versus body. A simpler fail-closed option
  is to never decrement before the frame's first arm has started.
- **Either bypass, structurally:** round 5's option (b) still applies. Once a lifted
  substitution closes inside double quotes, add a deny-side reading that keeps the rest of
  that quoted text unmasked. It can only deny more, and it closes the family no matter how
  the `case` count goes wrong.

Add the rows above to `self/tests/hook-cloud-profile.sh` table T as DENY in both profiles.
The cloud-only `HEAD:other` row should get the cloud refusal (prompt locally).

## Not counted (pre-existing, unchanged by this diff, never a silent allow)

- `then`/`do`/`else` followed by a git command inside a substitution
  (`echo "$(if true; then case x in x) git push origin main;; esac; fi)"`,
  `echo "$(if case x in x) true;; esac; then git push origin main; fi)"`): these prompt on
  base and head. Inside a substitution, a git word right after a keyword is not read as git
  even without a `case`, and round 5 recorded the same thing for
  `echo $(if true; then git push origin main; fi)`.
- Wrappers and indirection (`env`, `env env`, `/usr/bin/env`, `command`, `exec -a`,
  `nohup`, `sudo`, `xargs`, `find -exec`, `… | sh`): these prompt on base and head. The deny
  side does not see through them, but none is ever approved silently, and this diff does not
  touch them.

## Every input tried

Columns: base local · base cloud · head local · head cloud.

### Batch 1: the R7 `case` count and its neighbours

| Input | base local | base cloud | head local | head cloud |
|---|---|---|---|---|
| `git status` | ALLOW | ALLOW | ALLOW | ALLOW |
| `git push origin main` | DENY | DENY | DENY | DENY |
| `git push origin BR` | prompt | ALLOW | prompt | ALLOW |
| `echo "$(case x in x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| **`echo "$(! case x in x) git push origin main;; esac)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(time case x in x) git push origin main;; esac)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| `echo "$(if true; then case x in x) git push origin main;; esac; fi)"` (pre-existing `then`) | prompt | prompt | prompt | prompt |
| **`echo "$(while case x in x) false;; esac; do :; done; git push origin main)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| `echo "$(for i in 1; do case x in x) git push origin main;; esac; done)"` (pre-existing `do`) | prompt | prompt | prompt | prompt |
| `echo "$(if false; then :; else case x in x) git push origin main;; esac; fi)"` (pre-existing `else`) | prompt | prompt | prompt | prompt |
| `echo "$(if case x in x) true;; esac; then git push origin main; fi)"` (pre-existing `then`) | prompt | prompt | prompt | prompt |
| **`echo "$(! case x in x) true;; esac; git push origin main)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(time case x in x) true;; esac; git push origin main)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x\|esac) git push origin main;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| `echo "$(case x in esac\|x) git push origin main;; esac)"` (bash rejects it) | prompt | prompt | DENY | DENY |
| **`echo "$(case x in y) true;; x\|esac) git push origin main;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x \| esac) git push origin main;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **``echo "`case x in x\|esac) git push origin main;; esac`"``** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`X="$(case x in x\|esac) git push origin main;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x\|esac) true;; esac; git push origin main)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| `echo $(case x in x\|esac) git push origin main;; esac)` (unquoted, so the flat reading catches it) | DENY | DENY | DENY | DENY |
| `echo $(! case x in x) git push origin main;; esac)` (unquoted) | DENY | DENY | DENY | DENY |
| **`echo "$(case x in x\|esac) git reset --hard HEAD~1;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x\|esac) git stash;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x\|esac) git push origin HEAD:other;; esac)"`** (B3b) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(! case x in x) git stash;; esac)"`** (B3a) | prompt | prompt | **prompt** | **prompt** |
| `echo "$({ case x in x) git push origin main;; esac; })"` | prompt | prompt | DENY | DENY |
| `echo "$(true&&case x in x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) case y in y) true;; esac; git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) echo esac; git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) true; esac; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in @(x\|y)) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in (x\|esac) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) (true); git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case "x" in "x") git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) echo ')'; git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) true;& y) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) true;;& x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(\case x in x) git push origin main;; esac)"` (bash: no keyword, the push never runs) | prompt | prompt | prompt | prompt |
| `echo "$(case x in x)⏎git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in⏎x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(⏎case x in x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) true;;⏎esac⏎git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(case<TAB>x in x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo "$(case x in x) git push origin main;; esac)" ; ls` | DENY | DENY | DENY | DENY |
| `git push origin BR "$(case x in x\|esac) :main;; esac)"` | prompt | DENY | prompt | DENY |
| **`echo $(echo "$(! case x in x) git push origin main;; esac)")`** (B3a, nested) | prompt | prompt | **prompt** | **prompt** |
| **`echo "$(case x in x) echo \"$(case y in y\|esac) git push origin main;; esac)\";; esac)"`** (B3b, nested) | prompt | prompt | **prompt** | **prompt** |
| `echo "$(echo case; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(echo case) $(git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(case_x=1; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(esac; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(x=case; git push origin main)"` | prompt | prompt | DENY | DENY |
| `echo "$(echo x \| case x in x) cat;; esac; git push origin main)"` | prompt | prompt | DENY | DENY |
| `ls ';'` (R2 by design) | ALLOW | ALLOW | prompt | prompt |
| `grep -n '\(' README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `grep -n 'case x in x)' README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `grep -n "case x in x)" README.md` | ALLOW | ALLOW | ALLOW | ALLOW |
| `git log --grep 'esac)' -1` | ALLOW | ALLOW | ALLOW | ALLOW |
| `cd /tmp && ls` | DENY | DENY | DENY | DENY |
| `echo "$(case x in x) cd /tmp;; esac)" && ls` | DENY | DENY | DENY | DENY |

### Batch 2: regressions on R1–R6, wrappers and indirection

| Input | base local | base cloud | head local | head cloud |
|---|---|---|---|---|
| `env git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `env env git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `/usr/bin/env git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `command git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `exec -a x git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `nohup git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `sudo git push origin main` (pre-existing) | prompt | prompt | prompt | prompt |
| `echo main \| xargs git push origin` (pre-existing) | prompt | prompt | prompt | prompt |
| `find . -maxdepth 0 -exec git push origin main \;` (pre-existing) | prompt | prompt | prompt | prompt |
| `bash -c 'git push origin main'` | DENY | DENY | DENY | DENY |
| `echo 'git push origin main' \| sh` (pre-existing) | prompt | prompt | prompt | prompt |
| `g""it push origin main` | DENY | DENY | DENY | DENY |
| `git pu\sh origin ma""in` | DENY | DENY | DENY | DENY |
| `git push origin {main,BR}` | prompt | prompt | prompt | prompt |
| `git push origin ma*n` | prompt | DENY | prompt | DENY |
| `B=main; git push origin $B` | DENY | DENY | DENY | DENY |
| `git push -o ';' origin HEAD:main` | prompt | prompt | DENY | DENY |
| `git push origin BR ';'` | prompt | ALLOW | prompt | DENY |
| `git push origin BR '\|' tail` | prompt | ALLOW | prompt | DENY |
| `git -C '1'>/dev/null push origin main` | prompt | prompt | DENY | DENY |
| `git push origin BR {fd}>x :main` | prompt | prompt | DENY | DENY |
| `git push origin BR 99999999999>x :main` | DENY | DENY | DENY | DENY |
| `git push -o >(cat) origin HEAD:main` | prompt | prompt | DENY | DENY |
| `git $(true) push origin HEAD:main` | prompt | prompt | DENY | DENY |
| `echo "$(git push origin HEAD:main)"` | prompt | prompt | DENY | DENY |
| ``echo `git push origin HEAD:main` `` | prompt | prompt | DENY | DENY |
| `echo $(case x in x) git push origin main;; esac)` | DENY | DENY | DENY | DENY |
| ``echo "`case x in x) git push origin main;; esac`"`` | prompt | prompt | DENY | DENY |
| `X="$(case x in x) git push origin main;; esac)"` | prompt | prompt | DENY | DENY |
| `echo $(true) git status` | prompt | prompt | prompt | prompt |
| `git push origin BR 2>&1 \| tail -3` | prompt | ALLOW | prompt | ALLOW |
| `git push -u origin BR` | prompt | ALLOW | prompt | ALLOW |

### Batch 3: malformed and missing payload fields (head only)

| Payload | head local | head cloud |
|---|---|---|
| empty stdin | prompt | prompt |
| not JSON | prompt | prompt |
| no `tool_input` | prompt | prompt |
| `command: null` | prompt | prompt |
| `command` is a list | prompt | prompt |
| no `cwd`, with the B2 push | DENY | DENY |
| `cwd: "/"`, with the B2 push | DENY | DENY |
| 300 nested `case`s around a push | DENY | DENY |

Every payload exited 0. No input produced a silent ALLOW on this head for a command the hook
exists to refuse. Every head-side change from base is a new DENY, or a prompt where base
silently allowed (R2 by design). The two bypasses are the B3a and B3b rows above: the human
is prompted where the diff's own rule should deny.
