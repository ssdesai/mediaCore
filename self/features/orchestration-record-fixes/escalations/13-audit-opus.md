Verdict: escalated

# Security audit — orchestration-record-fixes (plan 13, opus)

## Setup

Two throwaway copies were extracted under the pass's scratch directory: `git archive
HEAD` and `git archive origin/main`. Each hook was loaded as a module and driven three
ways:

- **judge**: `invokes_build_script(command)` called directly.
- **unreadable**: the full `main()`, given a PreToolUse payload on stdin, with
  `orchestrator_record` patched to return `LEDGER_UNREADABLE`. That is the only path
  where the build-script deny applies (`main()` lines 4243–4248). The round-12 audit
  could not make the ledger unreadable inside the copy; patching the function replaces
  that.
- **no record**: the full `main()` with the record set to None, for contrast.

Each full-hook call used a fresh `session_id`. For the rewrite-deny rows, one session was
also replayed three times (see "Rewrite denies" below). `CLAUDE_PROJECT_DIR` and `cwd`
pointed at the copy, under the `local` profile.

Every candidate bypass was then run in **real bash**, in a directory holding a fake
`run-plans.sh` that leaves a marker file. Each one marked "RAN" below did execute the
script.

## What changed since round 12

`git diff 17d7019~1 17d7019` shows that round 13 changes the hook in one place. It adds
`substitution_may_build`, the build-script judge's fail-closed rule, along with
`BUILD_SCRIPT_FAIL_CLOSED_MARKERS` and `BUILD_SCRIPT_FAIL_CLOSED_CUT_RE`, and calls it
from `invokes_build_script`. Every other rule in the feature's diff (R1–R4 and the
rewrite denies in round 12's report) is byte-identical to what round 12 attacked. Its
results still hold, and a spot-check reproduced them (last table).

**The rule.** On a checkout whose orchestrator ledger is unreadable, every session is
denied a Bash line that may run a build script. Round 13 adds one condition to that
deny: a line holding `$(`, a backtick, `<(` or `>(` is denied when, after quoting is
removed and the line is cut at whitespace, operators, parens, backticks and `$`, any
word names a build script or is a glob that could match one. The check runs **after**
`HEREDOC_ARGUMENT_RE`, `ANSI_C_QUOTE_RE` and `EXTGLOB_RE` have rewritten the line.

## Inputs tried

Outcome key:
- **judge**: True or False.
- **full-hook columns**: `deny (role)` is the build-script deny. `deny (other)` is a
  rewrite or other deny. `none` means the hook printed nothing, so the human is asked.
  `allow` means approved silently.
- **bash**: RAN means real bash executed the fake script.

### Round 12's B1 rows and variants (the rule's target)

| Input | judge head | unreadable head | judge base | unreadable base |
|---|---|---|---|---|
| `./run-plans.sh --self x` | True | deny (role) | True | deny (role) |
| `ls "$(./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `echo "$(./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `cat "$(./run-p*.sh --self x)"` | True | deny (role) | False | none |
| ``cat "`./run-plans.sh --self x`"`` | True | deny (role) | False | none |
| ``ls `./run-plans.sh --self x` `` | True | deny (role) | False | none |
| `wc -l "$(bash ./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `ls x"$(./run-plans.sh)"` | True | deny (role) | False | deny (other) |
| `git log "$(./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(cd x; ./run-p*.sh)"` | True | deny (role) | False | none |
| `cat <(./run-plans.sh --self x)` | True | deny (role) | False | none |
| `echo x >(./run-p*.sh)` | True | deny (role) | False | none |
| `ls "$(./run-pl""ans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-pl\ans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-p?ans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-{plans,x}.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-plans.s[h] --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-plans.$'s'h --self x)"` | True | deny (role) | False | none |
| `ls "$(./run-plans.${X:-sh} --self x)"` | True | deny (role) | False | deny (other) |
| `ls "$(./RUN-PLANS.SH --self x)"` | True | deny (role) | False | none |
| `ls "$(⏎./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(. ./run-plans.sh --self x)"` | True | deny (role) | False | none |
| `ls "$(${SHELL} ./run-plans.sh --self x)"` | True | deny (role) | False | deny (other) |
| `cat <<EOF⏎$(./run-plans.sh --self x)⏎EOF` | True | deny (role) | True | deny (role) |
| `ls "\$(./run-plans.sh)"` (not a run; over-match) | True | deny (role) | False | allow |
| `git log --grep=run-plans.sh $(echo x)` (not a run; over-match) | True | deny (role) | False | none |
| `git commit -m "$(cat <<'EOF'⏎mentions run-plans.sh only⏎EOF⏎)"` (not a run) | False | none | False | none |
| `git commit -m "$(cat <<'EOF'⏎$(./run-plans.sh --self x)⏎EOF⏎)"` (quoted delimiter: not a run, bash: no) | False | none | False | none |

Round 12's B1 is fixed: all twelve of its rows now deny. The two over-matches refuse
only on an unreadable checkout, which the rule's docstring accepts.

### Attacks on the new rule

| # | Input | judge head | unreadable head | judge base | unreadable base | bash |
|---|---|---|---|---|---|---|
| A1 | `git commit -m "$(cat <<EOF⏎$(./run-plans.sh --self x)⏎EOF⏎)"` | **False** | **none** | False | none | RAN (echo form) |
| A2 | ``git commit -m "$(cat <<EOF⏎`./run-plans.sh --self x`⏎EOF⏎)"`` | **False** | **none** | False | none | RAN (echo form) |
| A3 | `echo "$(cat <<EOF⏎$(./run-p*.sh --self x)⏎EOF⏎)"` | **False** | **none** | False | none | RAN |
| A4 | `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎./run-plans.sh --self x⏎EOF⏎)"` | **False** | **none** | False | none | RAN (echo form) |
| A5 | `echo "$(cat <<'EOF'⏎msg⏎EOF⏎./run-p*.sh --self x⏎EOF⏎)"` | **False** | **none** | False | none | RAN |
| B1 | `ls '$' "$(./run-plans.sh --self x)" ''` | **False** | **none** | False | none | RAN |
| B2 | `echo '$' "$(./run-p*.sh --self x)" ''` | **False** | **none** | False | none | — |
| B3 | `ls $"$(./run-plans.sh --self x)"` | **False** | deny (other), then **none** on the 3rd try | False | deny (other) | RAN |
| B4 | ``ls $"`./run-plans.sh --self x`"`` | **False** | deny (other) | False | deny (other) | — |
| C1 | `ls "$(./run-plan[s$].sh --self x)"` | **False** | **none** | False | none | RAN |
| C2 | ``ls `./run-plan[s$].sh --self x` `` | **False** | **none** | False | none | RAN |
| C3 | `./run-plan[s$].sh --self x` (command position) | True | deny (role) | True | deny (role) | — |
| D1 | `ls "$(./run-plans.${SHELL: -2} --self x)"` | **False** | deny (other), then **none** on the 3rd try | False | deny (other) | RAN |
| D2 | `./run-plans.${SHELL: -2} --self x` | **False** | deny (other) | False | deny (other) | — |
| D3 | `./run-plans.${SHELL:(-2)} --self x` / inside `"$(…)"` | **False** | deny (other) | False | deny (other) | — |

"Echo form" means the bash check ran the same line with `echo` in place of `git commit`.
The heredoc and substitution semantics are identical, and it needs no repository.

### Spot-check of round 12's git rows (head, full hook)

| Input | no record | unreadable |
|---|---|---|
| `git status` | allow | allow |
| `git push --force origin x` | deny | deny |
| `git log ';' ls` | none | none |
| `git log "$(git rev-parse HEAD)"` | none | none |
| `case x in x) git log;; esac` | deny (rewrite) | deny (rewrite) |
| `cat <<EOF⏎x⏎EOF⏎git push --force origin x` | none | none |
| `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | none | none |
| `echo $(true) git push origin main` | deny | deny |
| `git -C '1'>/dev/null push origin main` | deny | deny |
| `ls '$' "$(git push origin main)" ''` | none | none |

None of these is an allow of a mutating command. The last row is the fail-closed
rule's documented prompt, the same as round 12's `echo "$(git push origin main)"`.

## Bypasses

Each bypass below is a line that runs a build script, confirmed in real bash. On an
unreadable-ledger checkout the build-script deny does not fire for it, and the hook only
asks the human. The bare `./run-plans.sh --self x` is denied there. Every row also
behaves the same on origin/main, so none is a regression. Each one defeats the
condition round 13 adds: "a line holding a substitution and a build-script name or glob
is a run". That condition reads the line only after three earlier rewrites, and each
rewrite can remove the substitution or the name before the check sees it.

### A — `HEREDOC_ARGUMENT_RE` hides a substitution that runs (A1–A5)

    git commit -m "$(cat <<EOF
    $(./run-plans.sh --self x)
    EOF
    )"

`invokes_build_script` swaps every whole-argument `"$(cat <<…EOF…)"` for a placeholder
before `substitution_may_build` looks at the line. The `$(` disappears with it, so the
rule never fires. The body is then only `named_in_exempt` in `git commit`, which needs a
launcher on the line to count. The swap is unsafe in two ways:

1. **An unquoted delimiter.** `HEREDOC_ARGUMENT_RE` accepts `<<EOF` as well as
   `<<'EOF'`, and bash expands `$(…)` and backticks inside an unquoted heredoc's body
   (A1–A3).
2. **The regex ends the body at the wrong line.** It ends the body at the first
   delimiter line followed by `)"`. Bash ends it at the first delimiter line of any
   kind, and runs whatever follows inside the substitution. That holds even with a
   quoted delimiter (A4, A5):

       git commit -m "$(cat <<'EOF'
       msg
       EOF
       ./run-plans.sh --self x
       EOF
       )"

**What the rule should do instead.** Treat a body as text only when the delimiter is
quoted (`'EOF'` or `"EOF"`), and only when the body holds no line equal to the
delimiter before the closing one. Any other match should be left on the line, or read
as a run. The simplest fix is to run `substitution_may_build` on the line *before*
`HEREDOC_ARGUMENT_RE`, with only quoted-delimiter bodies, the body ending where bash
ends it, exempted.

### B — `ANSI_C_QUOTE_RE` swallows a substitution (B1–B4)

    ls '$' "$(./run-plans.sh --self x)" ''

`ANSI_C_QUOTE_RE` runs before the check, and it does not know about quoting. It reads
the single-quoted `$` of `'$'` as the start of `$'…'` and matches up to the next `'`,
which swallows `"$(./run-plans.sh --self x)"`. The line becomes `ls '*'`: no marker, an
exempt reader, a judge result of False, and the human is asked.

A locale string `$"…"`, which bash expands like double quotes (B3, B4), is replaced by
`*` in the same way. Those rows draw the general rewrite deny first. After
`OPAQUE_REWRITE_ATTEMPTS` (two) in one session the hook asks instead. The build-script
deny never fires, though it is meant to be the one deny that stays (replayed: deny,
deny, none).

**What the rule should do instead.** Run `substitution_may_build` on the line before
the ANSI-C and extglob rewrites, since neither one can add a marker. Alternatively,
match `$'…'`/`$"…"` only outside single and double quotes, and treat `$"…"` as a
double-quoted word rather than as `*`.

### C — a `$` inside a bracket glob splits the name (C1, C2)

    ls "$(./run-plan[s$].sh --self x)"

`BUILD_SCRIPT_FAIL_CLOSED_CUT_RE` cuts at `$`, which leaves `./run-plan[s` and
`].sh`. Neither one matches as a glob. Bash reads `$]` as a literal `$`, so the class
`[s$]` matches `s`, and the substitution runs `./run-plans.sh` (RAN). At command
position (C3) the judge does catch it, because there the word is not cut.

**What the rule should do instead.** Do not cut at a `$` that is not followed by a
name, `{` or `(`. Or, more simply, read a word that holds an unclosed `[` as `*`.

### D — `${VAR: -N}` (D1–D3; weaker, and also outside the new rule)

    ls "$(./run-plans.${SHELL: -2} --self x)"

`BUILD_SCRIPT_EXPANSION_RE` reads `${…}` as `*` only when it is one word. The space in
`${SHELL: -2}` splits it, both under the new cut and under shlex at command position
(D2), so `./run-plans.` is not read as a pattern. Every such row gets the `$NAME`
rewrite deny first, which turns into a prompt on the third try in one session (D1
replayed: deny, deny, none). Bash runs the script (RAN).

**What the rule should do instead.** Read `${` up to its matching `}`, across
whitespace, as `*` before the line is cut or tokenized.

## Scope

- Only the unreadable-ledger path reaches this judge, and there only the build-script
  deny is meant to stand. A readable orchestrator record goes to the allowlist first,
  which this round does not change.
- These bypasses do not lead to a silent allow. Every bypass row ends in a human
  prompt.
- The prior rounds' out-of-diff findings still stand and are not counted here: the
  bundled force flag `git push -fu`, wrappers in front of git, and `{9}>x`.
