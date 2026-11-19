Verdict: escalated

# Security audit — orchestration-record-fixes

The base is `origin/main` and the head is `HEAD`. Both trees were extracted with
`git archive` into `/tmp/plan-capture.28k3NN/scratch/{head,base}`, each was turned into a git
repo on branch `claude/orchestration-record-fixes`, and the hook was run against them under
`AGENTTOOLING_PROFILE=local` and `=cloud`. Every input below was run on **both** trees so that
a regression can be told apart from a pre-existing gap. Legend: **allow** = the hook
approved it silently, **ask** = the hook printed nothing (the human decides), **deny** = the
hook refused it.

## Rules the diff adds or changes

| # | Rule | What it denies or asks, and for whom |
|---|------|------------------------------------|
| R1 | `mask_quoted_punctuation` + `QuotedWord` in `chain_tokens` | Deny side: a quoted or escaped operator character (`';'`, `"\|"`, `\;`) becomes an argument instead of a separator or redirect, for every git, chained-`cd` and assignment deny. |
| R2 | `quoted_separator_word` in `command_allowed` | Approval: a line holding a quoted word made only of operator characters is never approved (it asks). |
| R3 | `is_bare_descriptor` / `MAX_DESCRIPTOR` / `{name}` | Deny side: a digit run (or `{name}`) right before `<` or `>` is dropped as a file descriptor only when it is a whole unquoted ASCII word no bigger than a C int. |
| R4 | `punctuation_pieces` | Deny side: an operator run is split the way bash reads it (`;>x` is a separator and then a redirect), and only a redirect takes the next word as its target. |
| R5 | `is_heredoc_operator` / `judged_tokens` | Deny side: only an unquoted `<<` is a heredoc. The heredoc's own line is read; its body and **everything after it** are dropped. |
| R6 | `command_words` plain reading (the scoped substitution reading is removed) | Deny side for git, assignments and **build scripts** (`invokes_build_script`). |
| R7 | `fails_closed` in `command_allowed` | Approval: a line with a git word plus `$(`, a backtick, `<(`/`>(`, `<<` or `case` is never approved (it asks). |
| — | `analysis/report.py`, `analysis/roots.py` (`record_repo_root`, `home_root`) | Not a hook rule. These change where an orchestration report's `report` paths are read from, and gate no tool call. Nothing to attack beyond reading a file into `float()`, which is unchanged from base. |

## Attempts

Columns: local head / local base / cloud head / cloud base. `BR` = `claude/orchestration-record-fixes`.

### Quoting and quoted operators (R1, R2)

| Input | Result | |
|---|---|---|
| `git push origin BR ';' ls :main` | deny/ask/deny/ask | fixed (was F1) |
| `git push origin BR '\|' cat :main` | deny/ask/deny/ask | |
| `git push origin BR "&&" ls :main` | deny/ask/deny/ask | |
| `git push origin BR \; ls :main` | deny/ask/deny/ask | |
| `git push origin BR '; ' ls :main` | deny/deny/deny/deny | |
| `git push origin BR ';'x ls :main` / `x';' …` / `$';' …` | deny ×4 each | |
| `git push origin BR ''';' ls :main` / `';'"" …` | deny/ask/deny/ask | |
| `git push origin BR '('ls')' :main` | deny ×4 | |
| `git push -o ';' origin HEAD:main` / `-o '>'` | deny/ask/deny/ask | |
| `git push "origin" ';;' main` / `';;&' main` | deny/ask/deny/ask | |
| `git push origin BR ';'` / `""` / `''` | ask/ask/deny/ask | |
| `git push origin BR x\;` | ask/ask/deny/deny | |
| `echo $'\'' ; git push origin main ; echo $'\''` | ask ×4 | ANSI-C `\'` divergence; never approved, same as base |
| `echo $'\'' ; git push origin main #'` | ask ×4 | same |
| `echo $'\';' ; git push origin main` | ask ×4 | same |
| `git log --oneline \| grep ';'` | ask/allow/ask/allow | R2 over-match; prompts more |
| `git log --oneline \| grep '\('` | allow ×4 | F6 still fine |
| `git log --grep '\|'` | ask/allow/ask/allow | R2 over-match |
| `git log --grep=';'` / `--grep=\;` / `ls 'a;b'` | allow ×4 | |
| `grep ';' README.md` / `grep '\|' README.md` | ask ×4 | |
| `git push origin BR 2>&1 \| tail -3 ';' git push origin :main` | ask/deny/ask/deny | bash runs `tail` with those words as file names and never pushes `:main`, so head is right and base over-denied |

### File descriptors (R3, R4)

| Input | Result | |
|---|---|---|
| `git -C '1'>/dev/null push origin main` | deny/ask/deny/ask | fixed (bypass 2) |
| `git -C \1>/dev/null push origin main` | deny/ask/deny/ask | |
| `git -C 99999999999>/dev/null push origin main` | deny/ask/deny/ask | |
| `git -C 2147483648>/dev/null push origin main` | deny/ask/deny/ask | |
| `git -C 2147483647>/dev/null push origin main` | ask ×4 | bash also reads `-C push` here, so nothing pushes `main` |
| `git -C 0002>/dev/null push origin main` | ask ×4 | same: bash reads fd 2 |
| `git push origin 1>x main` / `git push 2>&1 origin main` / `git push 9>&1 origin main` | deny ×4 | |
| `git push origin {fd}>x main` / `{fd}<&- main` / `{_a1}>y main` | deny/ask/deny/ask | |
| `git push origin x{fd}>y main` / `{9}>y main` | ask ×4 | braces skip the git judge, same as base |
| `git push origin 2<&- main` / `&> x main` / `<<< x main` / `>> main HEAD:main` | deny ×4 | |
| `git push origin > main` | ask ×4 | bash writes a file named `main`; never approved |
| `git push origin BR '1'>/dev/null` / `\1>/dev/null` / `1"">/dev/null` | ask/ask/deny/ask | the quoted `1` is read as a second refspec |
| `git push origin BR 2147483648>/dev/null` | ask/ask/deny/ask | |
| `git push origin BR {fd}>/dev/null` / `3>/dev/null` / `1>&2` / `0</dev/null` / `>out` | ask ×4 | |
| `git push origin BR 2>/dev/null :main` | deny ×4 | |
| `git push origin BR main1>/dev/null` | ask/ask/deny/deny | |
| `git push origin BR >/dev/null` / `2>/dev/null` / `2> /dev/null` / `2>&1` | ask/ask/allow/ask | the intended cloud approval of the feature's own branch |
| `git push [-u] origin BR 2>&1 \| tail -3` | ask/ask/allow/ask | intended |
| `git push origin BR;>x git push origin main` / `;git push origin main` / `&&git push origin :main` | deny ×4 | |
| `git push origin main&` / `\|&cat` / `;;` / `;&` / `;& echo` / `\|& cat` / `echo x;;git push origin main` | deny ×4 | |
| `echo ')' ; git push origin main` / `echo "(" ; …` / `git push origin main ')'` | deny ×4 | |
| `git push origin\tmain` / `origin\rmain` | deny ×4 | |
| `git push origin ma\<NL>in` / `\<NL>main` | deny ×4 | |

### Heredocs (R5, R6)

| Input | Result | |
|---|---|---|
| `cat <<EOF; git push origin main⏎x⏎EOF` | deny/ask/deny/ask | improved |
| `cat <<-EOF; git push origin main⏎…` / `cat <<A <<B; git push origin main⏎…` | deny/ask/deny/ask | |
| `cat <<EOF \<NL>; git push origin main⏎x⏎EOF` | deny/ask/deny/ask | |
| `git push origin main⏎cat <<EOF⏎x⏎EOF` | deny/ask/deny/ask | |
| `git push origin main <<EOF⏎x⏎EOF` / `echo <<EOF git push origin main⏎EOF` | deny ×4 | |
| `cat '<<' x; git push origin main` / `cat \<\< x; …` / `cat <<< x; …` / `cat <<<x; …` | deny/ask/deny/ask | B1 fixed |
| `cat <<EOF⏎x⏎EOF⏎git push origin main` | ask ×4 | documented (the push after the body prompts); never approved |
| `cat <<EOF⏎it's⏎EOF⏎git push origin main` | ask ×4 | same |
| **`cat <<EOF⏎x⏎EOF⏎./run-plans.sh --self x` (unreadable ledger)** | **ask (head) / deny (base)** | **BYPASS 1** |
| `cat <<'EOF'⏎x⏎EOF⏎./run-batch.sh --self x` (unreadable ledger) | ask / deny | BYPASS 1 |
| `true <<EOF⏎EOF⏎./run-verify.sh --self x` (unreadable ledger) | deny (opaque-heredoc rewrite) / deny | still refused, by another rule |
| `cat <<EOF; ./run-plans.sh --self x⏎x⏎EOF` / `cat <<< x; ./run-plans.sh` / `cat '<<' x; ./run-plans.sh` (unreadable ledger) | deny / deny | |
| the same seven build-script lines with a **readable** orchestrator record (allowlist path) | deny / deny | the allowlist has its own lexer and is unaffected |

### Fail-closed rule (R7) and substitutions

| Input | Result | |
|---|---|---|
| `echo $(git push origin main)` / `echo $(case x in x) git push origin main;; esac)` / `case x in x) git push origin main;; esac` | deny ×4 | |
| `echo "$(git push origin main)"` / ``echo `git push origin main` `` / `git push -o >(cat) origin HEAD:main` | ask ×4 | documented prompt, same as base |
| `git push -u origin "$(git branch --show-current)"` | ask/ask/deny/deny | |
| `git push origin BR "$(echo :main)"` / `'$(x)'` | ask/ask/deny/deny | |
| `git log --format='%(describe)' -1` | allow ×4 | |
| `git log --grep='$(x)'` / `--grep='<<'` / `--grep=case` | ask/allow/ask/allow | R7 over-match; prompts more |
| `git log --grep='<<' && git push origin main` / `--grep='$(x)' && …` | deny ×4 | |
| `g\it …` / `g''it …` / `"git" push origin main` | deny ×4 | |

### Wrappers and indirection (none of these code paths changed in this diff)

| Input | Result |
|---|---|
| `env git push origin main`, `env env …`, `/usr/bin/env …`, `command …`, `exec -a x …`, `nohup …`, `sudo …`, `time …`, `! …`, `x=1 git push origin main`, `{ git push origin main; }`, `echo origin main \| xargs git push`, `find . -maxdepth 0 -exec git push origin main \;` | ask ×4. These go to the human and are never approved; base behaves the same. |
| `bash -c 'git push origin main'`, `echo git push origin main \| sh`, `if git push origin main; then :; fi`, `(git push origin main)` | deny ×4 |
| `git push origin ma""in`, `m\ain`, `'main'`, `HEAD:refs/heads/main` | deny ×4 |
| `git push origin ma{i,}n` | ask ×4 |
| `git push origin mai?` | ask/ask/deny/deny |

### Differential fuzz

`fuzz.py` built 20,672 generated lines: 10 line heads × 17 quoted-operator forms × 7 separators
× 8 writes (git push and reset variants, `./run-plans.sh`, `cd /tmp && ls`, `rm -rf x`), plus
12 redirect forms and heredoc prefixes/suffixes. Each line ran on head and base under both
profiles.

- **0** lines where head allows and base does not.
- **0** lines where head allows a write.
- 700 lines where base denies and head asks. **All 700** are the "this line mixes commands"
  rewrite deny (for example `git status ";" ; rm -rf x`): base read the quoted `;` as a
  separator. On head, R2 sends the line to the human whole. That is a shape rewrite, not a
  security deny, so none of the 700 is a bypass. The fuzz ran with no orchestrator record,
  so the build-script deny was never active in it. Bypass 1 came from the targeted
  unreadable-ledger run, not the fuzz.

## Bypasses

### Bypass 1 — a build script after a heredoc escapes the unreadable-ledger build-script deny (R5/R6 regression)

**Rule.** `build_script_denial` → `invokes_build_script` is the one deny every session gets
in a checkout whose orchestrator ledger cannot be read (`LEDGER_UNREADABLE`, the fail-closed
case in `main()`).

**Reproducer.** Run the hook with `orchestrator_record` returning `LEDGER_UNREADABLE`.
`unreadable.py` patches it in-process, because editing `.git` in the copy needed approval.

```
cat <<EOF
x
EOF
./run-plans.sh --self x
```

- head: **ask** (no output)
- base: **deny** ("this checkout's orchestrator ledger … ")

The same happens with `cat <<'EOF'` and `./run-batch.sh`.

**Cause.** On `origin/main`, `command_words` returned `None` for any line holding a heredoc,
and `invokes_build_script` then fell back to scanning the whole text for a build-script name.
`command_words` now uses `judged_tokens`, which keeps the heredoc's own line and drops the
body **and everything after it**, so `invokes_build_script` sees only `[['cat']]` and reports
no run. `fails_closed` does not catch this line because it holds no git word, and
`UNANALYSABLE` keeps it from approval but cannot deny it. Under a headless runner the line
then falls through to the runner's own policy instead of this deny.

**What the rule should do instead.** A build script anywhere in the line must still be
caught. Either:

- have `invokes_build_script` fall back to the whole-text name scan whenever `judged_tokens`
  truncated the line (a heredoc was found, so what follows the body was not read), or
- give `invokes_build_script` its own `chain_tokens`-based reading that keeps
  `command_words`' old `None`-on-heredoc behaviour.

Add the reproducer above to `self/tests/` as a must-deny case for the unreadable-ledger path.

## Non-bypass observations (no action required by this audit)

- R2 and R7 over-match by design: `git log --grep='$(x)'`, `--grep=case`, `--grep '|'` and
  `git log | grep ';'` were approved on base and now ask.
- When a quoted-separator word is present, the "mixes commands" rewrite deny now becomes a
  prompt (the 700 fuzz lines above). The human still sees the whole line.
- A git command placed after a heredoc's body (`cat <<EOF⏎x⏎EOF⏎git push origin main`)
  prompts rather than denies. That is documented, and base did the same.
