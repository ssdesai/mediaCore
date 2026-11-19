Verdict: escalated

# Security audit — hook-audit-gaps (round 3)

Scope: the diff `origin/main...HEAD` of `hooks/allow-repo-commands.sh` and `hooks/README.md`.
I ran the attacks on throwaway copies under the pass's scratch directory, made with
`git archive` and each turned into a fresh repo:

- `head` is HEAD, on `claude/hook-audit-gaps`.
- `main` is `origin/main`.
- `broken` is HEAD with a `.git` file that names no directory. That makes the ledger
  unreadable, so the build-script judge applies to every session.

The `head` and `main` copies have a ledger line that names session `sess-S` as an
orchestrator.

I also ran every input under bash with a logging `git` stub and logging stubs for the build
scripts, all on `PATH`. The "bash ran" column comes from those logs, and "—" means bash ran
neither git nor a build script. Each hook call used a fresh session id, so the counter that
turns repeated rewrite denies into asks never changed a result.

I wrote one file in this checkout: this report.

## Rules the diff adds or changes (as attacked this round)

1. **The walk deletes `\⏎` before each test that looks ahead** (rulings 39 and 44). The
   tests it covers are the operator, the delimiter, the whole-argument head and tail, and
   `substituted()` / `HEREDOC_SHIFT_RE`. `judged_texts` also reads the line with every
   continuation deleted. `unreadable_ledger_refuses` checks for its markers both with and
   without continuations.
2. **Joining heredoc body lines** (ruling 40, `heredoc_body_line`, `joins=`). For an unquoted
   delimiter, the walk joins a body line where bash does: at an odd run of backslashes. For a
   quoted delimiter it joins nowhere. The walk keeps the as-written reading next to the
   joined one (ruling 42).
3. **Backticks** (rulings 42 and 43). Inside backticks the walk halves each run of
   backslashes. After any backtick it reads a quoted delimiter's body both ways.
4. **The opened reading of a `"$(cat <<…` head that is not stood in** (ruling 45,
   `open_heads`).
5. **`uses_own_assignment` searches every reading** (ruling 46).
6. Carried from rounds 1 and 2 and spot-checked here: `bundles_push_force`, `brace_words`,
   the cloud own-branch push (with `branches[0]` read from the manifest at HEAD), the
   orchestrator allowlist, and the build-script judge.

## Bypasses

### R3-1: a run-on terminator inside `"$(cat <<…)"`, with an odd `"` after it, loses the git deny silently

In bash 5.2, inside `$(…)`, a heredoc body ends at a run-on line such as `EOF )`, `EOF)` or
`EOFS)`. The diff adds a rule that reads the commands on and after that line. If the line
and what follows it are balanced, that rule works (w4 and x1 below are DENY). If the text
after the body leaves an odd `"` in the reading where bash ends the body there, the hook
gives a **silent prompt**. Bash runs the push anyway, and only then stops on the open quote,
or never stops at all when the `"` is escaped or sits in a comment.

This is not the BACKLOG "does not tokenize" class:

- That class answers with the tokenize rewrite deny (x7 is DENY).
- These lines tokenize under the hook's own placement of the body, where the quotes are
  balanced.

The reading that would deny is dropped without a word. So the BACKLOG assertion ("a line
holding a git word that does not tokenize is denied") would not catch these.

The quoted delimiter (`'EOF'`, the stood-in shape) fails the same way as the unquoted one
(ruling 45's opened reading). `main` prompts on all of them too, so this is no regression.
But the round-1 rule ("a run-on line ends the body; what follows is read") and the round-3
rule (BACKLOG: "Round 3 closed the whole-argument spelling … the run-on line above … [is]
denied") do not hold.

| case | input | head | main | bash ran |
|---|---|---|---|---|
| w1 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| w2 | `echo "$(cat <<"EOF"⏎x⏎EOF )" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| o13p | `echo "$(cat <<EOF⏎x⏎EOF )" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| w11 | `echo "$(cat <<EOF⏎x⏎EOFS)" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| w12 | `echo "$(cat <<-EOF⏎x⏎⇥EOF )" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| w8 | `echo "$(cat <<EOF⏎x⏎EOF )" ; git reset --hard⏎EOF⏎)"` | **prompt** | prompt | **reset --hard** |
| w9 | `echo "$(cat <<EOF⏎x⏎EOF )" ; git branch -D main⏎EOF⏎)"` | **prompt** | prompt | **branch -D main** |
| x3 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y # ⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| x4 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; echo \"⏎EOF⏎)"` | **prompt** | prompt | **push -f origin y** |
| x8 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y⏎)"` | **prompt** | prompt | **push -f origin y** |
| o13s / o13t / o13v | the same with the terminator split by a continuation (`EO\⏎F )`, `EOF\⏎ )`, `EOF\⏎)`) | **prompt** | prompt | **push -f origin y** |
| o13u | `git commit -m "$(cat <<EOF⏎x⏎EOF \⏎)" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **commit, push -f** |
| w10 | `echo "$(cat <<EOF⏎x⏎EOF )" ; cd /tmp && ls⏎EOF⏎)"` | prompt | prompt | cd chain runs (the cd rewrite deny is lost) |
| w14 | `echo "$(cat <<EOF⏎x⏎EOF )"; X=/p; cat $X/f⏎EOF⏎)"` | prompt | prompt | `cat /p/f` (the assignment rewrite deny is lost) |

Controls, where the same line is balanced for bash:

| case | input | head |
|---|---|---|
| w4 | `echo "$(cat <<EOF⏎x⏎EOF )" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY |
| x1 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; : '⏎EOF⏎)"'` | DENY |
| x5 | `… ; git push -f origin y ; cat <<'Z'⏎EOF⏎)"⏎Z` | DENY |
| x7 | `git push -f origin y⏎echo '` | DENY (tokenize rewrite) |

The orchestrator role deny and the build-script judge on the unreadable ledger **both hold**
on this shape (or4, or5 and u2, u3 below). Only the git, `cd` and assignment denies lose it.

What the rule should do instead: a reading that the walk builds (bash's run-on placement,
or the opened head) and then fails to tokenize must not be dropped quietly. Either deny the
line as unreadable when it names git, as the doubt cap and brace cap do, or take the
tokenize rewrite deny the plain line gets (x7).

### R3-2 (minor): ruling 45's opened reading keys on the literal `"$(cat <<` and misses whitespace after `$(`

| case | input | head | main | bash ran |
|---|---|---|---|---|
| o1 | `echo "$(cat <<EOF⏎EO\⏎F⏎git push -f origin y⏎EOF⏎)"` | DENY | prompt | push -f |
| o3 | `echo "$( cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f** |
| o3p | `echo "$( cat <<EOF⏎x⏎EOF⏎git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | **push -f** |
| o9 / o9p | `echo "x$(cat <<EOF⏎x⏎EO\⏎F⏎git push…⏎EOF⏎)"` (with and without the continuation) | prompt | prompt | push -f |

NOTES ruling 45 calls the reading "narrow on purpose — only the `"$(cat <<` head", and
BACKLOG leaves "every other `"$(…)"`". So o9 (text before `$(`) is documented. o3 is the
same head with one space, which bash treats identically. I list it so the reviewer can rule
on whether "only the head" was meant to include its whitespace spellings. The fix would be
to match the head with `\$\(\s*cat\s*<<` (and the `\⏎`-joined text).

## Attempts

### Round 2's bypasses, retested

| case | input | head | main | bash ran |
|---|---|---|---|---|
| tc1 | `cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| tc2 | `cat <<EOF⏎x⏎EOF\⏎⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| tc5 | `cat <<-EOF⏎x⏎⇥EO\⏎F⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| tc7 | `ls; cat <<EOF⏎x⏎E\⏎O\⏎F⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| cd2 | `cat <<EOF⏎x⏎EO\⏎F⏎cd /tmp && ls⏎EOF` | DENY (cd) | prompt | cd chain |
| ps1 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | DENY | prompt | push -f |
| ps5 | `cat <\⏎(cat <<'EOF'⏎x⏎EOF) ; git push -f origin y⏎EOF⏎)` | DENY | prompt | push -f |
| ps6 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git reset --hard⏎EOF⏎)` | DENY | prompt | reset --hard |
| as3 | `a=(x)#b; X=/p; cat $X/f` | DENY (assignment) | prompt | — |

### Continuations in the heredoc operator, delimiter and terminator

| case | input | head | main | bash ran |
|---|---|---|---|---|
| n1 | `cat <<-EOF⏎x⏎⇥EOF\⏎⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| n2 | `cat <\⏎<EOF⏎x⏎EOF⏎git push -f origin y` | DENY | DENY | push -f |
| n3 | `cat <<E\⏎OF⏎x⏎EOF⏎git push -f origin y⏎E` | DENY | prompt | push -f |
| n4 | `cat <<"E\⏎OF"⏎x⏎EOF⏎git push -f origin y⏎E` | DENY | prompt | push -f |
| n5 | `cat <<'E\⏎OF'⏎x⏎EOF⏎git push -f origin y⏎E` | DENY (over-deny) | prompt | — |
| n6 | `cat <<\⏎EOF⏎x⏎EOF⏎git push -f origin y` | DENY | prompt | push -f |
| n7 | `cat <<EOF\⏎⏎x⏎EOF⏎git push -f origin y` | DENY | prompt | push -f |
| n8 | `cat <<EOF⏎x⏎\⏎E\⏎OF⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| n9 | `cat <<EOF⏎x⏎EOF\\\⏎⏎git push -f origin y⏎EOF` | prompt | prompt | — |
| n10 | `cat <<EOF⏎x⏎EOF\\⏎git push -f origin y⏎EOF` | prompt | prompt | — |
| n11 | `cat <<EOF⏎x⏎\⏎EO\⏎F⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| n12 | `cat <<EOF⏎x⏎EOF \⏎⏎git push -f origin y⏎EOF` | prompt | prompt | — |
| n13 | `cat <<EOF⏎x⏎EO\⏎\⏎\⏎F⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |

### Backticks: halving inside them, and none after them

| case | input | head | main | bash ran |
|---|---|---|---|---|
| bt1 | ``echo `true`; cat <<EOF⏎x\\⏎EOF⏎git push -f origin y⏎EOF`` | DENY | prompt | push -f |
| bt2 | ``echo `true`; cat <<'EOF'⏎x\⏎EOF⏎git push -f origin y⏎EOF`` | DENY | prompt | push -f |
| bt3 | ``echo `true`; cat <<EOF⏎EO\\⏎F⏎git push -f origin y⏎EOF`` | DENY (over-deny) | prompt | — |
| bt4 | ``echo `true`; ls # a \\⏎git push -f origin y`` | DENY | prompt | push -f |
| bt5 | ``echo `true`; ls 'a\\⏎'; git push -f origin y`` | DENY | DENY | push -f |
| bt6 | ``echo `cat <<EOF⏎x⏎EO\\⏎F⏎git push -f origin y⏎EOF⏎` `` | DENY | DENY (opaque) | push -f |
| bt7 | same with `<<'EOF'` | DENY (opaque) | DENY (opaque) | — |
| bt8 | same with `EO\\\\⏎F` | DENY (opaque) | DENY (opaque) | — |
| bt9 | same with `EO\\\\\\⏎F` | DENY (opaque) | DENY (opaque) | — |
| bt10 | ``echo `echo '#\\⏎'; git push -f origin y` `` | DENY | DENY | push -f |
| bt11 | ``echo `ls # \\⏎git push -f origin y` `` | DENY | prompt | push -f |
| bt12 | ``echo "`cat <<EOF⏎x⏎EO\\⏎F⏎git push -f origin y⏎EOF⏎`"`` | DENY (opaque) | DENY (opaque) | push -f |

### Comments and single quotes, where bash joins nothing

| case | input | head | main | bash ran |
|---|---|---|---|---|
| c1 | `ls # \⏎git push -f origin y` | DENY | prompt | push -f |
| c2 | `ls #\⏎\⏎git push -f origin y` | DENY | prompt | push -f |
| c3 | `ls # x\\\⏎git push -f origin y` | DENY | prompt | push -f |
| c4 | `ls x\⏎# y\⏎git push -f origin y` | prompt | prompt | — (`x#` is no comment; all one word) |
| c5 | `ls x \⏎# y⏎git push -f origin y` | DENY | prompt | push -f |
| c6 | `cat <<EOF # \⏎x⏎EOF⏎git push -f origin y` | DENY | prompt | push -f |
| c7 | `echo $(ls # \⏎)⏎git push -f origin y⏎)` | DENY | prompt | push -f |
| q1 | `echo 'a\⏎'; git push -f origin y` | DENY | DENY | push -f |
| q2 | `cat <<EOF⏎x⏎EOF⏎echo 'a\⏎b'; git push -f origin y` | DENY | prompt | push -f |

### The git word, `cd` and assignment, split by continuations

| case | input | head | main | bash ran |
|---|---|---|---|---|
| g1 | `gi\⏎t push -f origin y` | DENY | DENY (line break) | push -f |
| g2 | `git pu\⏎sh -\⏎f origin y` | DENY | DENY (line break) | push -f |
| g3 | `git push -\⏎-force origin y` | DENY | DENY (line break) | push --force |
| g4 | `git push origin \⏎+main` | DENY | DENY (line break) | push +main |
| g5 | `g\⏎i\⏎t re\⏎set --ha\⏎rd` | DENY | DENY (line break) | reset --hard |
| g6 | `git branch -\⏎D main` | DENY | DENY | branch -D |
| g7 | `cat <<EOF⏎x⏎EOF⏎gi\⏎t push -f origin y` | DENY | prompt | push -f |
| g8 | `git push -u\⏎f origin y` | DENY | DENY (line break) | push -uf |
| g9 | `git -C . push -\⏎f origin y` | DENY | DENY (line break) | push -f |
| g10 | `"gi\⏎t" push -f origin y` | DENY | prompt | push -f |
| g11 | `git push -fu origin y` | DENY | prompt | push -fu |
| g12 | `git push -{u,f} origin y` | DENY | prompt | push -u -f |
| cd3 | `c\⏎d /tmp && ls` | DENY (cd) | DENY (line break) | — |
| cd4 | `cd /tmp &\⏎& ls` | DENY (cd) | DENY (cd) | — |
| cd5 | `cd /tmp \⏎&& ls` | DENY (cd) | DENY (cd) | — |
| as4 | `X=/p; cat $\⏎X/f` | DENY (assignment) | DENY (line break) | — |
| as5 | `X\⏎=/p; cat $X/f` | DENY (assignment) | DENY (line break) | — |
| as6 | `X=/p; cat ${\⏎X}/f` | DENY (assignment) | DENY (line break) | — |
| as7 | `cat <<EOF⏎x⏎EO\⏎F⏎X=/p; cat $X/f⏎EOF` | DENY (assignment) | prompt | — |

### The opened reading (ruling 45) and quoted-substitution variants

| case | input | head | main | bash ran |
|---|---|---|---|---|
| o1 | `echo "$(cat <<EOF⏎EO\⏎F⏎git push -f origin y⏎EOF⏎)"` | DENY | prompt | push -f |
| o2 | `echo "$(cat<<EOF⏎x⏎EOF⏎)"; git push -f origin y` | DENY | DENY | push -f |
| o3 | `echo "$( cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | push -f (R3-2) |
| o4 | `echo "$(command cat <<EOF⏎x⏎EO\⏎F⏎git push…⏎EOF⏎)"` | DENY (opaque) | DENY (opaque) | push -f |
| o5 | `echo "$(cat <<-EOF⏎x⏎⇥EO\⏎F⏎git push -f origin y⏎EOF⏎)"` | DENY | prompt | push -f |
| o6 | `echo "$(cat <<EOF⏎x⏎EOF⏎)" ; git push -f origin y` | DENY | DENY | push -f |
| o7 | `echo "$(cat <<EOF⏎x⏎EOF⏎)$(git push -f origin y)"` | DENY | prompt | push -f |
| o8 / o8b–e | `echo "$(cat <<EOF⏎x⏎EOF⏎)`git push -f origin y`"` and kin; `echo "x`git push…`"` alone | prompt | prompt | push -f (BACKLOG scope entry: a command inside a quoted substitution) |
| o9 | `echo "x$(cat <<EOF⏎x⏎EO\⏎F⏎git push…⏎EOF⏎)"` | prompt | prompt | push -f (documented: R3-2) |
| o10 | `echo "$(cat <<EOF⏎x⏎EO\⏎F⏎git push…⏎EOF⏎)""$(cat <<EOF⏎EOF⏎)"` | DENY | prompt | push -f |
| o11 | `echo "$(cat <<EOF⏎x⏎EO\⏎F⏎)"; git push -f origin y; echo "⏎EOF⏎)"` | DENY | DENY | push -f |
| o12 | `echo "$(cat <<'EOF'⏎x⏎EOF⏎)" ; git push -f origin y` | DENY | DENY | push -f |
| o13 | `echo "$(cat <<EOF⏎x⏎EOF \⏎)" ; git push -f origin y⏎EOF⏎)"` | **prompt** | prompt | push -f (R3-1) |
| o13r / o13x / o13y | `echo $(cat <<EOF⏎x⏎EOF \⏎) ; git push…⏎EOF⏎)` (unquoted; also `EO\⏎F )`) | DENY | prompt | push -f |
| o13z | `cat <(cat <<EOF⏎x⏎EOF \⏎) ; git push…⏎EOF⏎)` | DENY | prompt | push -f |
| o14 | `echo "$(cat <<EOF⏎x⏎EOF⏎) # " ; git push -f origin y` | DENY | DENY | push -f |
| w3 | `echo "$(cat <<EOF⏎x⏎EOF )" ; git push -f origin y` | DENY | DENY | push -f |
| w5 | `git commit -m "$(cat <<EOF⏎x⏎EOF git push -f origin y)"` | DENY | prompt | push -f, commit |
| w6 | same with `<<'EOF'` | DENY | prompt | push -f, commit |
| w7 | `echo "$(cat <<EOF⏎x⏎EOF ; git push -f origin y)"` | DENY (over-deny) | prompt | — |
| w13 | `gh pr create --body "$(cat <<EOF⏎x⏎EOF )" ; git push… ; echo "⏎EOF⏎)"` | DENY | DENY | push -f |
| w1–w14, x1–x8 | see R3-1 | | | |

### Orchestrator allowlist (session `sess-S`)

| case | input | head | main | bash ran |
|---|---|---|---|---|
| or1 | `./feature-start.sh zz` | DENY (role) | DENY (role) | BUILD |
| or2 | `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | prompt | prompt | commit |
| or3 | `… <<'EOF'⏎x⏎EOF )" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` | DENY (role) | prompt | commit, BUILD |
| or4 | `git commit -m "$(cat <<'EOF'⏎x⏎EOF )" ; ./feature-start.sh zz⏎EOF⏎)"` | DENY (role) | prompt | commit, BUILD |
| or5 | same with `<<EOF` | DENY (role) | DENY (role) | commit, BUILD |
| or6 | same as or4 with `EOFS)` | DENY (role) | prompt | commit, BUILD |
| or7 | `… <<'EOF'⏎x⏎EO\⏎F⏎)" ; ./feature-start.sh zz⏎EOF⏎)"` | prompt | prompt | commit only (quoted: no join) |
| or8 | `… <<EOF⏎x⏎EO\⏎F⏎)" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` | DENY (role) | DENY (role) | commit, BUILD |

### Build-script judge (`broken`, unreadable ledger)

Every DENY here carries the ledger reason.

| case | input | broken | bash ran |
|---|---|---|---|
| u1 | `./run-plans.sh --self x` | DENY | BUILD |
| u2 | `echo "$(cat <<'EOF'⏎x⏎EOF )" ; ./run-plans.sh⏎EOF⏎)"` | DENY | BUILD |
| u3 | same with `<<EOF` | DENY | BUILD |
| u4 | `cat <<EOF⏎x⏎EO\⏎F⏎./run-plans.sh⏎EOF` | DENY | BUILD |
| u5 | `./run-pl\⏎ans.sh` | DENY | BUILD |
| u6 | `bash <\⏎< ./run-plans.sh` | DENY | — |
| u7 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; ./run-plans.sh⏎EOF⏎)` | DENY | BUILD |
| u8 | ``echo `cat <<EOF⏎x⏎EO\\⏎F⏎./run-plans.sh⏎EOF⏎` `` | DENY | BUILD |
| u9 | `ls # \⏎./run-plans.sh` | DENY | BUILD |
| u10 | `bash < run-pla\⏎ns.sh` | DENY | BUILD |
| u11 | `echo $\⏎(./run-plans.sh)` | DENY | BUILD |
| u12 | `ba\⏎sh run-plans.sh` | DENY | BUILD |
| u13 | `cat run-plans.sh \|\⏎ sh` | DENY | BUILD |

### Cloud own push (`AGENTTOOLING_PROFILE=cloud`, `head` on `claude/hook-audit-gaps`; hook only)

| case | input | head |
|---|---|---|
| cp1 / cp2 / cp18 | `git push [-u] origin claude/hook-audit-gaps` (and quoted) | ALLOW (expected) |
| cp29 | same with `2>/dev/null` | ALLOW (expected) |
| cp3 / cp8 | `…:main`, `…\⏎:main` | DENY |
| cp4 / cp5 / cp31 | `HEAD:<br>`, `+<br>`, `refs/heads/<br>` | prompt |
| cp6 / cp7 | `<br> main`, `<br> \⏎main` | DENY |
| cp9–cp12, cp16, cp24 | `--all`, `--mirror`, `--delete`, `:<br>`, `--tags`, `--force-with-lease` | DENY |
| cp13–cp15, cp17, cp23, cp25, cp32 | `--receive-pack=`, `-c remote.origin.url=`, `GIT_SSH_COMMAND=`, `--follow-tags`, `-o x`, `-n`, a URL remote | prompt |
| cp19–cp21 | a second push on the next line, after `;`, and after a comment holding `\⏎` | DENY |
| cp22 | `claude/hook-audit-gap{s,}` | DENY |
| cp26 / cp27 | a continuation inside the push | DENY (line-break rewrite) |
| cp28 | the push after a joined terminator `EO\⏎F` | prompt |
| cp30 | `"2">/dev/null` (B2) | DENY |
| m1 | working-tree manifest edited to `claude/evil`, on `claude/evil` | prompt |
| m2 | the same edit staged | prompt |
| m3 | the same edit committed on `claude/evil` (the manifest at HEAD names it) | ALLOW (by design: the started feature's own branch) |
| m4 | `git replace` of the HEAD manifest blob with one naming `claude/evil` | prompt |

## What held

- Every round-2 bypass is now denied: R2-1 (tc1, tc2, tc5, tc7, cd2), R2-2 (ps1, ps5, ps6)
  and R2-3 (as3).
- Continuations in the operator, the delimiter word, the terminator, the git word, `cd`,
  assignments and the build-script name were all denied wherever bash runs the command.
- Comments and single quotes, where bash joins nothing, were not joined in a way that hid
  anything.
- Backtick halving held at N = 2, 4 and 6.
- The orchestrator role deny and the build-script judge held on every shape I tried,
  including R3-1's.

What remains is R3-1. Inside `"$(cat <<…)"`, the reading bash takes at a run-on terminator
is dropped without a word when it leaves an odd `"`, and the git, `cd` and assignment denies
fall to a prompt. There is also the minor R3-2 (`"$( cat <<`). Both give a prompt, never an
allow, and `main` gives the same prompt.
