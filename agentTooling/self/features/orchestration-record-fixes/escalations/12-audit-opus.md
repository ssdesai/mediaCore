Verdict: escalated

# Security audit — orchestration-record-fixes (plan 12, opus)

Attacked: `git archive HEAD` and `git archive origin/main`, each extracted under the pass's
scratch directory, each made a git repo on `claude/feat` (branched from `main`), so every
input was run against HEAD's hook **and** the base hook. Two harnesses ran:

- **The full hook**: a PreToolUse payload on stdin, with `CLAUDE_PROJECT_DIR` set to the
  copy and `AGENTTOOLING_PROFILE` set to `local` or `cloud`.
- **The judges called directly**: the hook loaded as a module, then `git_denial`,
  `chains_chdir`, `uses_own_assignment` and `invokes_build_script` called on their own.

Real bash was also checked on the descriptor shapes the new `is_bare_descriptor` models.
Result: bash agrees with the hook on every one (`2147483648>x`, `99999999999>x`, `2&>x`,
`{9}>x`, `'1'>x`, `\1>x`, `١>x` are arguments; `1>x`, `{fd}>x`, `{_}>x` are redirects;
`2147483647>x` is a redirect that fails, so the command does not run).

## Rules the diff adds or changes

1. **R1, the redirect/descriptor reading** (`chain_tokens`, `is_bare_descriptor`,
   `punctuation_pieces`, `command_words`). The deny side drops a redirect and its target
   from every command's words, and drops a digit or `{name}` only when bash would take it
   as a descriptor. It applies to every git deny, local and cloud.
2. **R2, quoted operator characters** (`mask_quoted_punctuation`, `QuotedWord`,
   `quoted_separator_word`). On the deny side a quoted or escaped `;`/`|`/`>` is an
   argument. On the approval side a line holding one is never approved.
3. **R3, the fail-closed rule** (`fails_closed`). A line holding a git word together with
   `$(`, a backtick, `<(`/`>(`, `<<` or `case` is never approved. The deny side denies what
   its plain reading finds.
4. **R4, heredocs** (`is_heredoc_operator`, `judged_tokens`). The deny side reads a
   heredoc's own line and stops at its body. Only an unquoted `<<` counts as a heredoc.
5. **R5, the build-script judge** (`invokes_build_script`, now routed through
   `chain_tokens`/`command_words`). For a checkout whose orchestrator ledger is unreadable,
   it denies any line that may run a build script.
6. **The `chains_chdir` and `uses_own_assignment` rewrite denies**, now read through the
   same tokenizer.

## Inputs tried

`head`/`base` = the outcome under HEAD's hook / origin/main's hook. Full-hook rows show
`allow`/`ask`/`deny`. Direct-judge rows show `DENY`/`—` (git), `True`/`False` (chdir,
assign, build).

### Git deny, direct (`git_denial`, local profile)

| Input | head | base |
|---|---|---|
| `git push --force origin x` | DENY | DENY |
| `git push origin main` | DENY | DENY |
| `git push origin main 2>&1` | DENY | DENY |
| `git push origin other > log` | — | — |
| `git -C '1'>/dev/null push origin main` | DENY | — |
| `git -C \1>/dev/null push origin main` | DENY | — |
| `git -C 1>/dev/null push origin main` (bash: `-C push`, not a push) | — | — |
| `git push -o 2&>x origin HEAD:main` | DENY | DENY |
| `git push origin {fd}>x main` | DENY | — |
| `git push origin {fd}>x>y main` | DENY | — |
| `git push origin {_}>x main` | DENY | — |
| `git push origin {9}>x main` (brace word: prompts by the old brace rule) | — | — |
| `git push origin{fd}>x main` (bash: remote `origin{fd}`) | — | — |
| `git push origin 99999999999>x main` | DENY | DENY |
| `git push origin 2147483648>x main` | DENY | DENY |
| `git push -o 2147483647>x origin HEAD:main` (bash: bad fd, nothing runs) | — | — |
| `git push -o ١>x origin HEAD:main` | DENY | — |
| `git push -o ';' origin HEAD:main` | DENY | — |
| `git push -o ";" origin HEAD:main` | DENY | — |
| `git push -o \; origin HEAD:main` | DENY | — |
| `git push -o '>' origin HEAD:main` / `">"` / `\>` / `\>\>` | DENY | — |
| `git push -o '>'x origin HEAD:main` / `"a>"b` | DENY | DENY |
| `git push -o '<<' origin HEAD:main` / `\<\<` | DENY | — |
| `git push origin HEAD:main <<EOF⏎x⏎EOF` | DENY | — |
| `cat <<EOF; git push origin main⏎x⏎EOF` | DENY | — |
| `cat <<EOF⏎x⏎EOF⏎git push origin main` | — | — |
| `cat <<<x; git push origin main` | DENY | — |
| `git push origin main <<<x` | DENY | — |
| `cat <<'EOF'⏎it's⏎EOF⏎git push --force origin x` | — | — |
| `echo $(git push origin main)` | DENY | DENY |
| `echo "$(git push origin main)"` | — | — |
| ``echo `git push origin main` `` | — | — |
| `echo $(case x in x) git push origin main;; esac)` | DENY | DENY |
| `case x in x) git push --force origin x;; esac` | DENY | DENY |
| `(git push --force origin x)` | DENY | DENY |
| `echo $(true) git push origin main` | DENY | DENY |
| `echo x;>y git push origin main` | DENY | — |
| `echo x;2>y git push origin main` | DENY | DENY |
| `echo x &>y; git push origin main` | DENY | DENY |
| `echo x\|&git push origin main` | DENY | DENY |
| `git push origin x >(cat) main` | — | — |
| `git push -o >(cat) origin HEAD:main` | — | — |
| `git push origin HEAD:main ;; true` | DENY | DENY |
| `git push origin HEAD:ma'in'` / `HEAD:"main"` / `HEAD:m\ain` | DENY | DENY |
| `git push origin ':main'` / `':'main` / `\:main` | DENY | DENY |
| `g""it push origin main` / `\git …` / `/usr/bin/git …` | DENY | DENY |
| `env git push origin main` / `command git push origin main` | — | — |
| `git push origin main #'` | — | — |
| `echo #' ⏎git push --force origin x⏎#'` | — | — |
| `echo $'\'' ; git push --force origin x ; echo '\'` | — | — |
| `{fd}>x git push origin main` | DENY | — |
| `2>x git push origin main` / `x 2>y; git push origin main` | DENY | DENY |
| `git push 2>x>y origin main` / `git push origin main 2>x>y` / `git push 2>x origin 3<y main` | DENY | DENY |
| `git push origin 1<>x main` / `1>\|x` / `1<&-` / `1>&-` | DENY | DENY |
| `git push -o x 1>&2 origin HEAD:main` | DENY | DENY |
| `git push --force-with-lease=x origin y` | DENY | DENY |
| `git reset --hard 2>&1` / `git stash 2>/dev/null` | DENY | DENY |
| `git push -fo';' origin x` (see "Outside this diff") | — | — |
| `git push origin x"";git push --force origin y` | DENY | DENY |
| `git push origin x';'" "git push --force origin y` | DENY | DENY |

### Full hook (local and cloud)

| # | Profile | Input | head | base |
|---|---|---|---|---|
| F1 | local | `git status` | allow | allow |
| F2 | local | `git push --force origin x` | deny | deny |
| F3 | local | `git push origin main` | deny | deny |
| F4 | local | `git log ';' ls` | ask | allow |
| F5 | local | `git log \; ls` | ask | allow |
| F6 | local | `git log "\|" ls` | ask | allow |
| F7 | local | `grep '\(' README.md` | allow | allow |
| F8 | local | `grep '\|' README.md` | allow | allow |
| F9 | local | `grep ';' README.md` | ask | ask |
| F10 | local | `git log "$(git rev-parse HEAD)"` | ask | ask |
| F11 | local | ``git log `git rev-parse HEAD` `` | ask | ask |
| F12 | local | `git log <(echo x)` | ask | ask |
| F13 | local | `git log <<<x` | deny (rewrite) | deny |
| F14 | local | `case x in x) git log;; esac` | ask | ask |
| F15 | local | `echo "$(git push origin main)"` | ask | ask |
| F16 | local | ``echo `git push origin main` `` | ask | ask |
| F17 | local | `git push -o >(cat) origin HEAD:main` | ask | ask |
| F18 | local | `cat <<EOF⏎x⏎EOF⏎git push --force origin x` | ask | ask |
| F19 | local | `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | ask | ask |
| F20 | local | `git push -fu origin x` | ask | ask |
| F21 | local | `env git push --force origin x` | ask | ask |
| F22 | local | `git log 2>&1` | allow | allow |
| F23 | local | `git log {fd}>x` | ask | ask |
| F24 | local | `ls 1>x` | ask | ask |
| F25 | local | `git log -C '1'>/dev/null` | ask | ask |
| F26 | local | `git log \| sh` | deny (rewrite) | deny |
| F27 | local | `git log ; git push --force origin x` | deny | deny |
| F28 | local | `gi\t log; ls ';'` | deny (mixed) | allow |
| F29 | local | `ls '<(' x` | ask | ask |
| F30 | local | `ls "$(" x` | ask | ask |
| C1 | cloud | `git push origin claude/feat` (no started manifest in the copy) | ask | ask |
| C2 | cloud | `git push origin other` | deny | deny |
| C3 | cloud | `git push origin claude/feat ';' ls :main` | deny | ask |
| C4 | cloud | `git push origin claude/feat \; ls :main` | deny | ask |
| C5 | cloud | `git push origin claude/feat 2>/dev/null` | ask | ask |
| C6 | cloud | `git push origin claude/feat 2>&1 \| tail -3` | ask | ask |
| C7 | cloud | `git push -o ';' origin HEAD:other` | deny | ask |
| C8 | cloud | `git push origin claude/feat "$(echo :main)"` | deny | deny |
| C9 | cloud | `git push origin claude/feat {fd}>x :main` | deny | ask |
| C10 | cloud | `git push origin claude/feat 1>x other` | deny | deny |
| C11 | cloud | `git push origin claude/feat ;>x other` (bash pushes only `claude/feat`; `other` is a command) | ask | deny |
| C12 | cloud | `git push -u origin "$(git branch --show-current)"` | deny | deny |
| C13 | cloud | `git switch main` | deny | deny |
| C14 | cloud | `git switch '-' 2>x` | deny | deny |
| C15 | cloud | `git push origin claude/feat <<<main` | deny (rewrite) | deny |
| C16 | cloud | `git -C '1'>/dev/null push origin other` (git runs in `./1`, which does not exist) | ask | ask |

### `chains_chdir` / `uses_own_assignment`, direct

| Input | chdir head | chdir base | assign head | assign base |
|---|---|---|---|---|
| `cd src && ls` | True | True | False | False |
| `cd src ';' ls` (bash: one `cd` with args) | False | True | False | False |
| `echo ';' cd src` | False | True | False | False |
| `echo x ;>y cd src && ls` | True | False | False | False |
| `echo x <(cd src) ls` / `ls <(cd src && ls)` | False | False | False | False |
| `x=$(cd src && pwd)` | False | False | False | False |
| `(cd src) && ls` | True | True | False | False |
| `cd src <<<x && ls` | True | False | False | False |
| `cd /x '&&' ls` | False | True | False | False |
| `cd src 2>x && ls` | True | True | False | False |
| `{fd}>x cd src && ls` | True | False | False | False |
| `ls >(cd x) ; cd y && ls` | True | True | False | False |
| `cat <<EOF && cd src && ls⏎body⏎EOF` | False | False | False | False |
| `cd src\;ls` | False | False | False | False |
| `X=/p; cat $X/f` | False | False | True | True |
| `X=/p ';' cat $X/f` (bash: no separator) | False | False | False | True |
| `X=/p 2>y; cat $X/f` | False | False | True | True |
| `X=/p {fd}>y; cat $X/f` | False | False | True | False |
| `X=/p ;>y cat $X/f` | False | False | True | False |
| `X="$(pwd)"; cat $X/f` | False | False | True | True |

Every head/base difference above is HEAD matching bash where base did not.

### Build-script judge (`invokes_build_script`), direct

| Input | head | base |
|---|---|---|
| `./run-plans.sh --self x` | True | True |
| `cat $(./run-p*.sh)` | True | True |
| `echo 'a<<' ; ./run-p*.sh` | True | True |
| `cat <<EOF⏎x⏎EOF⏎./run-plans.sh` | True | True |
| `cat <<<x ; ./run-p*.sh` | True | False |
| `cat '<<' ; ./run-p*.sh` / `cat \<\< ; ./run-p*.sh` | True | False |
| `echo ';' ./run-p*.sh` (bash runs only `echo`) | False | True |
| `echo ";" ; ./run-p*.sh` | True | True |
| `echo x 2>y ./run-p*.sh` / `cat 2>x ./run-p*.sh` (args to a reader) | False | False |
| `echo x >(./run-p*.sh)` / `echo x <(./run-p*.sh)` / `cat 1 >(./run-p*.sh)` | True | False |
| `cat x \| ./run-p*.sh` / `(./run-p*.sh)` / `case a in a) ./run-p*.sh;; esac` | True | True |
| `{fd}>x ./run-p*.sh` / `2>x ./run-p*.sh` | True | True |
| `git log $(./run-p*.sh)` | True | True |
| **`ls "$(./run-plans.sh --self x)"`** | **False** | False |
| **`echo "$(./run-plans.sh --self x)"`** | **False** | False |
| **`cat "$(./run-p*.sh --self x)"`** | **False** | False |
| **``cat "`./run-plans.sh --self x`"``** | **False** | False |
| **``ls `./run-plans.sh --self x` ``** | **False** | False |
| **`wc -l "$(bash ./run-plans.sh --self x)"`** | **False** | False |
| **`ls "$(./run-batch.sh --self x)"`** | **False** | False |
| **`ls x"$(./run-plans.sh)"`** | **False** | False |
| **`echo hi "$(./run-plans.sh --self x)" \| wc -l`** | **False** | False |
| **`grep -c x README.md "$(./run-verify.sh --self x)"`** | **False** | False |
| **`git log "$(./run-plans.sh --self x)"`** | **False** | False |
| **`ls "$(cd x; ./run-p*.sh)"`** | **False** | False |
| `ls "${X:-$(./run-plans.sh)}"` (full hook: rewrite deny for hidden code) | False | False |

## Bypass

### B1 — R5: a build script run from a substitution inside a reader's arguments is not denied

A substitution (`"$(…)"` double-quoted, or a backtick, quoted or not) inside the
arguments of a command that `exempt_from_build_judge` exempts is not denied. Those
commands are the `BUILD_SCRIPT_READERS` (`ls`, `cat`, `echo`, `grep`, `wc`, …) and git's
record subcommands. The shortest input that reproduces it:

    ls "$(./run-plans.sh --self x)"

`invokes_build_script` returns False for it, so `build_script_denial` returns None. On a
checkout whose orchestrator ledger is unreadable (`orchestrator_record` →
`LEDGER_UNREADABLE`, `main()` lines 4218–4231), the line is not denied. It falls through
to the approval, which only asks (full hook, row U2: `ask`). Bash runs `./run-plans.sh`.
`./run-plans.sh --self x` on its own is denied on that same checkout.

The glob, backtick and nested forms behave the same: `cat "$(./run-p*.sh --self x)"`,
``ls `./run-plans.sh --self x` ``, `wc -l "$(bash ./run-plans.sh --self x)"`,
`git log "$(./run-plans.sh --self x)"`. The build-script table above lists all twelve
inputs.

**Why.** This diff's plain reading of `command_words` keeps a quoted word that holds a
substitution whole, on purpose (hooks/README.md: "keeps a word with a substitution inside
it whole for … `invokes_build_script`"). A backtick never splits a word. So the build
script is only an argument of `ls`, `exempt_from_build_judge(["ls", …])` exempts the
whole command, and `names_build_script` is only consulted for `named_in_exempt`. That
flag also needs a launcher on the line.

**Regression?** No. origin/main gives the same answer for every row. But R5 is a rule
this diff changes (its routing through `chain_tokens`/`is_heredoc_operator`/
`command_words`), and the input reaches it, so it is recorded as a bypass of that rule.

**Scope.** Only the unreadable-ledger fail-closed path reaches this judge. A readable
orchestrator record goes to the allowlist first, and that was not attacked here. I could
not make the ledger unreadable inside the throwaway copy: the scratch `.git` is a
protected path for this pass's tools. So the end-to-end claim is the direct judge result
plus the `main()` code path that calls it. With no record, the full hook asks (U2–U5, U10).

**What the rule should do instead.** Apply to R5 the same move `fails_closed` applies to
git. In a command that `exempt_from_build_judge` exempts, a word holding `$(`, a
backtick or `<(`/`>(` should be judged as a run: `names_build_script` or
`pattern_matches_build_script` applied to the word's text, with the word's quoting
removed. Alternatively, a line holding a substitution marker and a build-script name or
glob is a run. The over-match only refuses building on an unreadable checkout, which
that rule already accepts.

## No bypass found in R1–R4 or the rewrite denies

- **No row anywhere is a HEAD allow of a mutating command.**
- **No head-vs-base difference weakens a deny without bash agreeing.** The one deny→ask
  change, C11, is correct: bash pushes only `claude/feat` there.
- **R1:** the descriptor reading matched real bash on every shape tried.
- **R2:** the previous round's bypass (`git push origin <current> ';' ls :main`, C3/C4)
  is now denied, and F4–F6 now ask.
- **R3:** under it, git lines with a substitution, `<(`/`>(`, `<<` or `case` only ask,
  never allow.
- **R4:** what follows a heredoc's body is not read for deny (F18, `cat <<EOF⏎x⏎EOF⏎git
  push …`). That is documented, matches base, and the line break keeps it from approval.

Rows that ask where a stricter reading would deny, all documented as the fail-closed
rule's prompt (hooks/README.md → "The fail-closed rule") and identical on base:

- `echo "$(git push origin main)"`
- ``echo `git push origin main` ``
- `git push origin x >(cat) main`
- `git push -o >(cat) origin HEAD:main`

## Outside this diff (pre-existing, not counted toward the verdict)

These shapes ask instead of being denied. They are identical on origin/main, and they
come from code this diff does not change (`git_mutates`, the wrapper and brace handling):

- **`git push -fu origin x`, `git push -fo';' origin x`.** `git_mutates` matches the
  force flag only as a whole word (`-f`/`--force`), so a bundled short flag that includes
  `f` is not read as a force push. git accepts the bundle.
- **`env git push --force origin x`, `command git push origin main`.** The deny side does
  not follow a wrapper.
- **`git push origin {9}>x main`.** A brace word skips the git deny entirely (the old
  brace rule).

Worth a feature of its own: the first is a force push that only prompts.
