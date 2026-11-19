Verdict: escalated

# Security audit (round 10): orchestration-record-fixes

The base is `origin/main` and the head is `HEAD` (`697654d`). Both trees were extracted with
`git archive` into `/tmp/plan-capture.WQPPAi/scratch/{head,base}`. Each was made a git repo on
branch `claude/orchestration-record-fixes`. The hook was loaded from each tree and run with
crafted PreToolUse payloads under `AGENTTOOLING_PROFILE=local` and `=cloud`.

For the unreadable-ledger path, `driver.py` patches `orchestrator_record` in-process to return
`orchestrator_role.LEDGER_UNREADABLE`. That is the one path where the build-script deny is
active.

Every input ran on both trees, so a regression can be told apart from an existing gap.

Columns are local head / local base / cloud head / cloud base. **allow** = approved
silently, **ask** = no output (the human decides), **deny** = refused. `BR` stands for
`claude/orchestration-record-fixes`.

## Rules the diff adds or changes

| # | Rule | What it denies or asks, and for whom |
|---|------|------------------------------------|
| R1 | `mask_quoted_punctuation` / `QuotedWord` in `chain_tokens` | Deny side: a quoted or escaped operator character is read as an argument, not a separator or redirect. Applies to every git, `cd`-chain and assignment deny. |
| R2 | `quoted_separator_word` in `command_allowed` | Approval: a quoted word made only of operator characters is never approved. |
| R3 | `is_bare_descriptor` (`MAX_DESCRIPTOR`, `{name}`) | Deny side: only a whole, unquoted, int-sized digit run or `{name}` before `<`/`>` is dropped as a file descriptor. |
| R4 | `punctuation_pieces` | Deny side: operator runs are split the way bash splits them, and only a redirect takes a target. |
| R5 | `is_heredoc_operator` / `judged_tokens` | Deny side: the line a heredoc sits on is read. Its body and everything after it are dropped. |
| R6 | `command_words`, one plain reading | Deny side for the git, assignment and build-script judges. |
| R7 | `fails_closed` | Approval: a line holding a git word plus any of `$(`, a backtick, `<(`/`>(`, `<<` or `case` is never approved. |
| **R8 (new this round)** | `invokes_build_script`: `groups = None if HEREDOC_OPERATOR in line else command_words(line)` | Deny side, for every session in a checkout whose ledger cannot be read: any line holding `<<` gets the text fallback, not the tokenized reading. |
| — | `analysis/report.py`, `analysis/roots.py` (`record_repo_root`) | Not hook rules. They change which root a record's `report` paths resolve against, and gate no tool call. |

## Attempts: build-script deny (unreadable ledger; R6, R8)

| Input | Result | Note |
|---|---|---|
| `./run-plans.sh --self x` | deny ×4 | |
| `ls` / `cat run-plans.sh` | allow ×4 | |
| `cat <<EOF⏎x⏎EOF⏎./run-plans.sh --self x` | deny ×4 | **round 9 bypass 1 fixed** (head asked before) |
| `cat <<'EOF'⏎x⏎EOF⏎./run-batch.sh --self x` / `<<-EOF … ./run-verify.sh` / `<<"EOF"` / `<< EOF` / `0<<EOF` | deny ×4 | fixed |
| `cat <<EOF⏎it's⏎EOF⏎./run-plans.sh --self x` | deny ×4 | |
| `cat <\⏎<EOF⏎x⏎EOF⏎./run-plans.sh` (heredoc spelled across a line continuation) / the same with `it's` in the body | deny ×4 | |
| after a heredoc: `./run-pla""ns.sh`, `./run-pla\ns.sh`, `./run-pla$'n's.sh`, `"./run-plans.sh"`, `./run-plan"s".sh`, `.\/run-plans.sh`, `$'./run-plans.sh'`, `$'\x2e/run-plans.sh'`, `./run-plan$'\x73'.sh` | deny ×4 | |
| after a heredoc: `bash run-plans.sh`, `sh -c ./run-plans.sh`, `. ./run-plans.sh`, `source run-plans.sh`, `exec …`, `env …`, `xargs …`, `find -exec {}`, absolute path, tab, CRLF, `${X:-./run-plans.sh}`, `r=run-plans.sh; ./$r`, `${IFS}` | deny ×4 | |
| after a heredoc: `./run-review.sh`, `./feature-close.sh`, `cat run-plans.sh` | deny ×4 | |
| `cat <<EOF;./run-plans.sh⏎x⏎EOF` / `cat <<EOF⏎$(./run-plans.sh)⏎EOF` / backtick body / `<<'EOF'` with a `$(…)` body | deny ×4 | |
| `cat <<< x⏎./run-plans.sh` / `cat '<<' x⏎./run-plans.sh` | deny ×4 | |
| `echo "$(cat <<'EOF'⏎x⏎EOF⏎)"⏎./run-plans.sh` / `git commit -m "$(cat <<'EOF'…)" && ./run-plans.sh`, the same with `./run-pla*.sh` or `$'n'` | deny ×4 | |
| `echo '$"'; ./run-plans.sh; echo '"'` / `echo "$'"; …; echo "'"` / the same around a heredoc / `echo '@(' ; ./run-plans.sh ; echo ')'` | deny ×4 | ANSI-C and extglob mangling does not hide the name |
| `git log --grep='<<' ; ./run-plans.sh` / `echo 'a<<' ; ./run-plans.sh` | deny ×4 | a literal name is caught by the text fallback |
| `./r*s.sh`, `./run-p*.sh`, `./run-p?ans.sh <<< x`, `bash ./run-p*.sh <<< x`, `echo <<< x ./run-p*.sh`, `ls <<< x ./run-p*.sh` | deny ×4 | |
| `echo x ; ./run-p*.sh --self x` / `echo x ; ./run-pl?ns.sh --self x` | deny ×4 | the tokenized reading catches globs |
| **`echo 'a<<' ; ./run-p*.sh --self x`** | **ask/deny/ask/deny** | **BYPASS 1** |
| **`echo a'<<' ; ./run-p*.sh --self x`** | **ask/deny/ask/deny** | BYPASS 1 |
| **`git log --grep='<<' ; ./run-p*.sh --self x`** (also with `&&`) | **ask/deny/ask/deny** | BYPASS 1 |
| **`ls 'a<<b' ; ./run-pl?ns.sh --self x`**, `./run-pla[n]s.sh`, `./run-{plans,x}.sh`, `./r*.sh`, `bash ./run-p*.sh` | **ask/deny/ask/deny** | BYPASS 1 |
| `echo "x<<y" ; ./run-p*.sh --self x` | deny (rewrite) / deny (ledger) ×2 | refused on head by another rule |
| `cat <<< x ; ./run-p*.sh` / `cat <<< x && ./run-p*.sh` | ask ×4 | existing gap: base also falls back to text on a herestring |
| `cat <<EOF⏎x⏎EOF⏎./run-p*.sh`, `./run-pla*.sh`, `./run-plan?.sh`, `./run-p[l]ans.sh`, `./run-{plans,x}.sh`, `./run-@(plans).sh`, `./run-*`, `./r*s.sh`, `./run-plans.s?`, `./run-plans.s[h]`, `bash ./run-p*.sh`, `nohup ./run-p*.sh` | ask ×4 | existing gap, same as base (see observations) |
| `cat <<EOF⏎x⏎EOF⏎f=./run-plans; $f.sh`, `./run-$(echo plans).sh`, a backtick name, `./ru\⏎n-plans.sh` | ask ×4 | same as base |
| `echo "$(cat <<'EOF'⏎x⏎EOF⏎./run-plans.sh --self x⏎EOF⏎)"` / the same as `git commit -m` | ask ×4 | existing gap, same as base (see observations) |
| `echo "$(cat <<'EOF'⏎./run-plans.sh⏎EOF⏎)"` | ask ×4 | only body text; nothing runs |
| `cat <<EOF⏎x⏎EOF⏎make` | ask ×4 | not a build script |

## Attempts: git, shape and approval rules (R1–R7), round-9 battery re-run

| Input | Result |
|---|---|
| `git push origin BR ';' ls :main` / `'\|' cat :main` / `\; ls :main` / `git push -o ';' origin HEAD:main` | deny/ask/deny/ask |
| `git -C '1'>/dev/null push origin main` / `git -C 99999999999>/dev/null push origin main` / `git push origin {fd}>x main` | deny/ask/deny/ask |
| `git push [-u] origin BR 2>&1 \| tail -3` / `git push origin BR >/dev/null` | ask/ask/allow/ask (the intended cloud approval) |
| `git push origin BR 2>/dev/null :main` / `git push origin BR;>x git push origin main` | deny ×4 |
| `cat <<EOF; git push origin main⏎x⏎EOF` / `git push origin main⏎cat <<EOF⏎x⏎EOF` / `cat '<<' x; git push origin main` / `cat <<< x; git push origin main` | deny/ask/deny/ask |
| `cat <<EOF⏎x⏎EOF⏎git push origin main` | ask ×4 (documented; same as base) |
| `echo $(git push origin main)` / `git log --grep='<<' && git push origin main` / `g\it push origin main` / `bash -c '…'` / `… \| sh` / `git push origin ma""in` | deny ×4 |
| `echo "$(git push origin main)"` / `env git push origin main` | ask ×4 (same as base) |
| `git push -u origin "$(git branch --show-current)"` / `git push origin BR "$(echo :main)"` / `git push origin BR 'a<<b'` | ask/ask/deny/deny |
| `git log --oneline -3` / `git status` / `git log --oneline \| grep '\('` | allow ×4 |
| `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | ask ×4 |
| the same `&& git push origin main` | deny ×4 |
| `git commit -m "$(cat <<'EOF'⏎x⏎EOF⏎git push origin main⏎EOF⏎)"` | ask ×4 (same as base) |
| `echo 'a<<' ; git push origin main` / `ls 'a<<b' ; git push origin :main` / `git push origin BR <<< x` | deny ×4 |
| `cd /tmp && ls` / `echo 'a<<' ; cd /tmp && ls` / `X=/p; cat $X/f` / `echo 'a<<'; X=/p; cat $X/f` | deny ×4 |

R1–R7 behave exactly as the round-9 audit tabled them, and no git input regressed.

## Bypasses

### Bypass 1: a quoted `<<` anywhere on the line hides a globbed build script from the unreadable-ledger deny (R8 regression)

**Rule.** `build_script_denial` → `invokes_build_script`. In a checkout whose orchestrator
ledger cannot be read, this is the one deny every session gets.

**Reproducer** (run with `orchestrator_record` returning `LEDGER_UNREADABLE`):

```
ls 'a<<b' ; ./run-pl?ns.sh --self x
```

- head: **ask** (no output)
- base: **deny** ("this checkout's orchestrator ledger …")

Bash expands `./run-pl?ns.sh` to `./run-plans.sh` and runs it. In the copy, `ls
…/head/run-pl?ns.sh` lists only `run-plans.sh`.

These variants behave the same way: `echo 'a<<' ; ./run-p*.sh --self x`, `git log
--grep='<<' ; ./run-p*.sh --self x`, `./run-pla[n]s.sh`, `./run-{plans,x}.sh`, `./r*.sh`,
and `bash ./run-p*.sh`.

**Cause.** Round 10 added `groups = None if HEREDOC_OPERATOR in line else
command_words(line)`. That test is a raw substring test, so it is also true for a `<<`
inside quotes or inside a larger word (`'a<<b'`, `--grep='<<'`). Base's `command_words`
refused only a token that *starts with* `<<`. For `--grep=<<` it read the line by
tokens, and `pattern_matches_build_script` caught the glob in launch position.

Head now sends every such line to the text fallback. That fallback calls
`pattern_matches_build_script` only when the line holds ANSI-C quoting
(`ansi and pattern_matches_build_script(word)`). A plain glob therefore goes unread, and
the deny becomes a prompt. Under a headless runner the line then falls through to the
runner's own policy.

**What the rule should do instead.** It should deny this line, as base does. Either
change is enough:

- Route to the text fallback only when the line has a heredoc that `command_words`
  would truncate. That means testing tokens with `is_heredoc_operator` (from
  `chain_tokens(line)`), not `HEREDOC_OPERATOR in line`. A quoted `'<<'`, a `\<\<` or a
  `<<<` herestring then keeps the tokenized reading.
- Or make the text fallback also apply `pattern_matches_build_script` to every word,
  with ANSI-C quoting or without. This fails closed on the after-heredoc glob as well
  (see the first observation below).

Add `ls 'a<<b' ; ./run-pl?ns.sh --self x` and `git log --grep='<<' ; ./run-p*.sh --self x` to
`self/tests/` as must-deny cases on the unreadable-ledger path.

## Observations (not regressions; base behaves the same)

- **A globbed build script after a real heredoc's body asks on both trees.** Examples:
  `cat <<EOF⏎x⏎EOF⏎./run-p*.sh`, `./run-plan?.sh`, `./run-{plans,x}.sh` and
  `bash ./run-p*.sh`. The text fallback pattern-matches only when the line holds ANSI-C
  quoting. The second fix above closes this too, and is the more robust choice.
- **`HEREDOC_ARGUMENT_RE` can end a heredoc later than bash does.** Example:
  `echo "$(cat <<'EOF'⏎x⏎EOF⏎./run-plans.sh --self x⏎EOF⏎)"`. Bash ends the heredoc at the
  first `EOF` line and runs `./run-plans.sh` inside the substitution. The regex extends to
  the `EOF⏎)"` and parks the command as body text. The line asks on head and on base,
  because the regex is unchanged. The same shape with `git push origin main` also asks
  (never approved, because of R7).
- R2 and R7 still over-match by design. For example, `git log --grep='<<'` asks.
