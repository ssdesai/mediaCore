# hooks

Claude Code hook scripts, vendored with the rest of `agentTooling/`. A hook does nothing
until a settings file names it; `sync-plans.sh` does that wiring, so a repo gets it at
install and after every `subtree pull`. All three files are Python 3, standard library
only.

- `allow-repo-commands.sh` — `PreToolUse` hook for the `Bash` tool. Reads the hook payload
  `{ tool_name, cwd, tool_input{command} }` on stdin and prints
  `{ hookSpecificOutput: { hookEventName, permissionDecision, permissionDecisionReason } }`
  with `permissionDecision: "allow"` when the whole command is confined to the project
  root and built only from allowlisted read/test programs and the harness's own read-only
  entry points. Its analysis answers one of three verdicts — ALLOW, **REWRITE** (it could
  not read the command and can name the rewrite) or **ASK** (it read the command and
  cannot vouch for it) — and prints nothing for the last, so the normal permission flow
  runs over a command it has read. It emits `permissionDecision: "deny"` for three shapes
  it reads and refuses outright — a command chaining `cd` or `pushd` with any other
  command, with a reason naming the rewrite; a git command that moves a ref or rewrites
  history, with a reason naming `LIFECYCLE.md` rule 2, `feature-start.sh` and
  `feature-close.sh`; an assignment at command position whose own `$NAME` is used later on
  the same line, with a reason saying to inline the literal — and for every REWRITE, whose
  reason is the rewrite: a heredoc into an interpreter, code as a string, a pipe into one,
  a program or a path decided at run time, a one-line compound, a line that does not
  tokenize (which names the quote instead), a `$NAME` the shell expands, a `~`, a brace
  group the expansion refuses, a `..` path component, a bare or relative `cd`, a line
  break outside a quote or a heredoc, a sequence mixing approved reads with a command
  only the human can judge, and a file authored through the shell — `echo`/`printf`
  redirected to a path, `cat`/`tee` fed literally with output to a path, `sed -i` — whose
  reason names the Write and Edit tools and is judged ahead of the opaque shapes. Its git
  deny reads `policy.py`'s constants and nothing of its own.
  After `OPAQUE_REWRITE_ATTEMPTS` opaque commands in one session it emits
  `permissionDecision: "ask"` instead, keyed on the payload's `session_id` and `agent_id`
  through a state file under `$TMPDIR`; under `AGENTTOOLING_HEADLESS` it prints nothing
  there. `AGENTTOOLING_SCRATCH` names the one directory outside the root it approves a
  script from. Every approval rule is a refusal and the default is to
  refuse: a token it does not understand makes the whole command fall through to the prompt.
- `policy.py` — the git policy as **data**, and the one file both scripts above and below
  read it from. Constants: `GIT_PROGRAM`; `READ_ONLY` / `MUTATING` (how an entry is
  marked); `GIT_ALWAYS_MUTATING` (`clean`, `stash`, `rebase`); `GIT_PUSH` with
  `GIT_PUSH_FORCE_FLAGS` and `GIT_PUSH_FORCE_LEASE_FLAG`; `GIT_RESET` with
  `GIT_RESET_MUTATING_FLAG`; `GIT_WORKTREE` with `GIT_WORKTREE_SUBCOMMANDS`
  (`list` READ_ONLY; `add`, `remove`, `prune`, `move`, `lock`, `unlock`, `repair`
  MUTATING); `GIT_CHECKOUT` / `GIT_CHECKOUT_BRANCH_FLAGS`; `GIT_SWITCH` /
  `GIT_SWITCH_BRANCH_FLAGS`; `GIT_BRANCH` / `GIT_BRANCH_MUTATING_FLAGS` /
  `GIT_BRANCH_LIST_FLAGS`; and `BASH_RULE_TEMPLATE`. Functions: `worktree_read_only()`,
  `worktree_mutating()`, `denied_git_commands()` and `bash_deny_rules()`, which renders
  the `permissions.deny` prefix twin in the fixed order below. Every constant a rule is
  rendered from is an **ordered tuple**, not a frozenset: the rendering is compared byte
  for byte with the committed settings file, and a set has no order to compare.
  Both scripts import it by **sibling path**
  (`sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))`) with
  `sys.dont_write_bytecode = True`, because neither runs from a fixed directory — the
  hook is invoked by Claude Code from wherever the session sits, the writer with a
  `--repo` that is somebody else's checkout — and because that directory is inside the
  repo being guarded, where a `__pycache__` has no business. It is on the gate's
  `py_compile hooks` line and asserted by `self/tests/policy-table.sh`.
- `wire-settings.py` — `wire-settings.py [--self] --repo <dir> (--check | --write)`.
  Maintains the `PreToolUse` entry for `allow-repo-commands.sh`, the `Edit` and `Bash`
  deny rules and the `hooks/` **ask** rule in `<dir>/.claude/settings.json`. The Bash
  rules are `policy.bash_deny_rules()`, never a list of its own. Prints one
  `status<TAB>message` line for the
  caller to format and exits 0 when nothing needs attention, 1 otherwise. Statuses:
  `in-sync`, `missing`, `UNWIRED`, `INVALID` for `--check`; `created`, `wired`, `kept`,
  `INVALID` for `--write`. `--self` works on agentTooling's own checkout instead of a
  consuming repo's, and differs in more than the spelling: that file is wholly
  **generated**, so `--check` is a byte comparison against a fresh write (`INVALID` is a
  merge status and never reached there) and `--write` restores those bytes. Called by
  `sync-plans.sh` (without `--self`) and by `self/gate.sh` (with it, in `--check`);
  tested by `self/tests/hook-wiring.sh`.

## Why `allow-repo-commands.sh` exists

`permissions.blockReadsOutsideWorkingDirectories` refuses any command whose paths resolve
at run time. That is every `cd X && cmd` chain — including `cd X && ls`, and including
commands an allow rule already covers, since the block is checked before rule matching.
`CONVENTIONS.md` § Shell commands tells agents not to write that shape, but nothing else
enforces the rule, and every miss costs the human a prompt while teaching the model
nothing. So the hook answers a `cd X && cmd` chain with a deny whose reason is the fix,
not with an approval, and approves the rewritten, unchained commands without turning the
fence off.

## The three outcomes

The approval analysis answers a **verdict**, not a bool
(`../self/DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1). Before that, "I could not read
this" and "I read it and it writes" both collapsed into the same silence: the human paid
an approval for each and the model learned from neither.

| Verdict | What it means | What the hook prints |
|---|---|---|
| **ALLOW** | every subcommand read-only and confined to the project root | `permissionDecision: "allow"` |
| **REWRITE** | the analysis could not read the command, and a rewrite exists | `permissionDecision: "deny"`, the reason being the rewrite — and `"ask"` after `OPAQUE_REWRITE_ATTEMPTS` of them in one session |
| **ASK** | the analysis read it and cannot vouch for it: a write (a captured output, a copy, a move — a file authored in the command is a REWRITE), an unknown program, a path outside the root, an environment prefix, a whole-argument `$(…)` | nothing, so the settings' own rules and then the human decide |

Precedence on a line: any REWRITE member makes the line REWRITE — the human is never
handed a line no reader here could split — else any ASK member makes it ASK, else ALLOW.
The three shape denies below run first and are unchanged.

**ALLOW is `command_allowed`'s answer and nothing else.** The verdict layer sits on top
of that oracle rather than replacing it, and is reached only once it has declined, so it
can turn a silent prompt into a deny that names the fix and can never turn a prompt into
an approval. Re-deriving approval from per-member verdicts would widen it — `ls ;; ls`
has two approved members and a separator nothing here recognises — and so would dropping
the `UNANALYSABLE` refusal in favour of the per-shape tests: `ls\nls`, `cat ../absent` and
`git diff main...HEAD` would all be approved. That tuple therefore stays exactly where it
was, and what the design replaced is its *judgement*, not its refusal.

**No `ask` decision is ever emitted for the ASK class**, only for the escalation. An
explicit `ask` would override the `permissions.allow` rules a human wrote, and the prompt
already shows a command this hook has read.

### The chained `cd`

A `cd` or `pushd` at command position alongside any other command, where commands are
separated by `&&`, `||`, `;`, `|`, `&`, a line break, or a `(` subshell. The reason tells
the model to run `cd <absolute path>` as its own call, or to name every path absolutely.

A `$(…)` command substitution is its own scope, quoted or not: nothing inside it counts
as a command of the outer line, and the word after its `)` is read where the `$(` left
off. A `cd` in there moves no path the outer command resolves — `x=$(cd dir && pwd)` is
the usual way to make a path absolute — so `x=$(cd dir && pwd)` and
`x="$(cd dir && pwd)"` are both left alone, while `x=$(pwd) && cd dir` is still a chain.

The check runs before, and independently of, the approval analysis, and it needs neither
`CLAUDE_PROJECT_DIR` nor `cwd`: the shape is wrong wherever it runs. It deliberately does
not deny a standalone `cd`; `cd` as an argument (`echo cd`, `find . -name cd`) or inside
quotes; a redirect target; a heredoc body — any command containing `<<` is never denied;
any command containing `#`, since a mid-word `#` bash reads literally could otherwise
hide a heredoc; or a command that does not tokenize (an unbalanced quote). Those fall through to the
approval analysis as before.

In a consuming repo the deny also reaches the runners' Bash-enabled executors (verify,
review). That is intended: they are held to the same convention.

### The git shape

A git command that moves a ref, rewrites history or throws work away, **wherever it sits
on the line** — after a `&&`, `;`, `|` or `&`, inside a `(…)` subshell or a `$(…)`
substitution, behind `-C <path>`, `--git-dir=…` or `-c k=v`. The reason names
`LIFECYCLE.md` → "The three rules", rule 2, and **both ends of the sanctioned route**:
`feature-start.sh` is the way in — it makes the branch and the worktree, is run from the
primary checkout by the human or by the session itself (with the command spelled out, and
the instruction to start the feature *before* editing and then edit only inside the
worktree), and its next run prunes away the ones whose work has merged — and `feature-close.sh` is the way out, run from the feature's worktree, on its
branch, after a clean review and *before* the merge. Merging the PR is the last step and
nothing runs after it (`self/DESIGN-2026-09-17-close-and-review-rounds.md`;
`LIFECYCLE.md` → step 6). `self/tests/allow-repo-commands.sh` asserts both names are in
the reason, and nothing in this directory says the close runs after the merge.

The constants behind all of this are `policy.py`'s, not this script's: the same table
`wire-settings.py` renders the `permissions.deny` prefix rules from.

Denied: `push` with `--force`, `-f` or `--force-with-lease[=…]`; `reset --hard`; `clean`;
`stash`; `rebase`; `worktree` with any subcommand but `list` — `add`, `remove`, `prune`,
`move`, `lock`, `unlock`, `repair`, and an unknown one, since a subcommand the table has
not heard of is not one it can vouch for; `checkout -b`/`-B`;
`switch -c`/`-C`; `branch` with a positional argument or `-d`/`-D`/`--delete`/`-m`/`-M`/
`--move`. `clean`, `stash` and `rebase` are denied whatever follows, read-only spellings
included — `git stash list` is one keystroke from `git stash`, and the prompt is the right
place to tell them apart.

Not denied: `git branch --show-current`, `git branch --merged main` (the value of a
listing flag is not a positional), `git branch --list 'feat*'` (after `--list` or `-l` a
positional is a pattern to filter by, not a name to create — the mutating flags are
judged first, so `git branch --list --delete old` is still denied),
`git worktree list`, a plain `git push`,
`git checkout -- <file>`, `git reset <file>`. Nor is anything the analysis cannot read,
for the same reason the `cd` deny leaves those alone: a heredoc, a `#`, a line that does
not tokenize (which the opaque check below denies with its own reason — the *git* deny
does not judge it), a `git …` that is an argument rather than a command (`echo 'git rebase'`),
or a word carrying a brace — no brace expansion happens here, so `git branch {-a,new}`
prompts, and it is the approval analysis, which does expand, that refuses it.

The check runs after the `cd` deny and before the approval analysis, and like the `cd`
deny it needs neither `CLAUDE_PROJECT_DIR` nor `cwd`.

**Both sides read past git's global options now, but not the same ones**
(`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §5b). The deny side skips the whole
of `GIT_GLOBAL_VALUE_FLAGS` (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`,
`--exec-path`, `--config-env`) to find the subcommand, because finding a *mutating*
subcommand behind an option is never a risk. The approval side skips only
`GIT_GLOBAL_LOCATION_OPTIONS` — `-C`, `--git-dir`, `--work-tree` — each of which names a
location and nothing else, so confining its value to the project root is the whole of what
it can do. `git -C <a path inside the root> status`, the commonest read a coordinator
makes across its own worktrees, is therefore approved rather than prompting; before this
only the deny side skipped anything, so `-C` read as the subcommand and matched nothing.

The asymmetry is deliberate and the four left out are the reason: `-c` and `--config-env`
set arbitrary config, so `git -c core.pager='sh -c id' log` runs `sh`; `--exec-path` moves
where git looks for its own binaries; `--namespace` names a ref namespace rather than a
path, so nothing needs it and unlisted means prompt. **Nothing else in front of the
subcommand is skipped either**, and a bare flag is not exempt for taking no value —
`--paginate`/`-p` forces the pager config names even when stdout is not a tty, so `git
--paginate log` and `git -p -C <root> log` prompt (as does `git --no-pager -C <root> log`,
the accepted cost of a listing rule). A location option whose value is missing or is
itself a flag (`git -C`, `git -C --git-dir status`) names no location and is not approved.

Confinement is **not** repeated in `git_location_args`: `subcommand_allowed` has already
put every argument through `token_confined`, which covers the attached and separate
spellings and every repetition — `git -C <root> -C /tmp status` fails there on the second
value. Finding the subcommand is not approving it, either: `git -C <root> branch new` and
`git -C <root> worktree add x` are still denied by the deny side, and the forbidden-flag
list still applies to what follows the subcommand (`git -C <root> diff --ext-diff`
prompts).

### The run-time-value shape

An **assignment at command position** whose own `$NAME` or `${NAME}` appears later on the
same line: `X=/p; cat $X/f`, `export X=/p && ls $X`. This is the generalisation of the
chained `cd` — what blocks the reads fence is a path decided at run time, not several
commands on a line — narrowed to the one case where the literal is provably still in hand
two words earlier, so the correction is a substitution rather than a rewrite. The reason
says to inline it: every path a literal, one command per call.

A command whose words are *all* assignments is an assignment command; one with anything
else after them is an **environment prefix** (`X=1 make`), which decides nothing the shell
re-reads on the same line, and is not denied. Nor is an assignment nobody dereferences
(`X=/p`), a `$NAME` with no assignment on the line (`cat $HOME/f`), a `$` the shell will
not act on (`echo '$X'`, a backslash-escaped one), or a `$(…)` substitution, which is not
a variable use. The three guards the other denies keep hold here too, through the same
`command_words`: a heredoc, a `#`, or a line that will not tokenize is never judged.

**There is no prefix-rule twin for this one**, unlike the git deny. A
`permissions.deny` entry is a command *prefix*, and this is a relation between two tokens
anywhere on the line; no prefix rule can express it, so nothing of it is in `policy.py`
and the hook is the whole of the enforcement. `allow-repo-commands.sh` says so beside the
constants.

### The rewritable shapes

The rest of the rule — no `$(…)` in a path, no heredoc into an interpreter — used to stay
prose in `CONVENTIONS.md`, on the grounds that a deny must not demand a rewrite
(`self/DESIGN-2026-09-16-lifecycle-restructure.md` §3.7). That was the wrong trade: such a
command fell through to the human's prompt, which cost an approval and taught the model
nothing, and there is a rewrite that always works. **Decided 2026-09-17, superseding
§3.7**: a command the analysis cannot read is denied with the rewrite as its reason, and
the human is only asked once the model has tried.

Seven shapes. Six hide code from anyone reading the command line:

| Shape | Example |
|---|---|
| a heredoc feeding anything but `cat` | `python3 - <<'EOF'`, `bash <<EOF` |
| code as a string at a command position | `python3 -c`, `bash -c`, `node -e`, `perl -ne`, `eval`, and the same behind `xargs` or `find -exec`/`-execdir`/`-ok`/`-okdir`. The scan for the code flag stops at the first non-flag word, so a *script's* own `-c` is the script's business: `python3 tool.py -c config.yaml` is readable and is not denied. |
| a pipe into an interpreter with no script | `… \| sh`, `… \| python3` |
| a program decided at run time | `$CMD …`, `${CMD} …`, `$(which x) …` |
| a `$(…)` or backtick inside a word that is a path | `ls $(cd dir && pwd)/src`, ``cat `pwd`/README.md`` |
| a one-line compound | `for … do … done`, `while`, `until`, `if`, `case` |

The reason is the same for all six: write the script to the scratchpad with the Write
tool and run it by name; or use the Read/Grep tool instead of a one-liner; or inline the
literal you already have.

**The seventh is the plainest, and has a reason of its own.** A line that does not
tokenize at all — a quote left open (`cat 'x`, `git rebase 'main`), or a word shlex
refuses — is a line no reader here can even split into words, so none of the six checks
above, none of the three shape denies and no part of the approval analysis ever judged
it: it printed nothing and cost the human an approval. `does_not_tokenize` denies it with
`UNREADABLE_DENY_REASON`, which names the quote and says to close it, because "write the
script to the scratchpad" is not the fix for an apostrophe. It counts toward the
escalation like the other six. The heredoc and `#` guards hold here too, looked for in
the raw text since a line that will not lex cannot be asked where its quotes are: a body
line and a comment are data, so `cat <<'EOF' … don't … EOF` and `ls src # don't` still
prompt. `opaque_deny_reason` is the tri-state the three answers meet in — the six shapes'
reason, the quote's, or `None` for a command the analysis can read.

**Exempt.** A heredoc feeding `cat` is a literal string, not code — `git commit -m
"$(cat <<'EOF' … EOF)"` is the shape Claude Code itself uses for a commit message, and
the operator's owner is read out of the substitution it sits in, so `git` is not mistaken
for the program being fed. A `$(…)` that is a *whole* argument decides a value rather
than a path or a program: `x=$(cd dir && pwd)`, `echo $(pwd)`, `ls $(cat f)` and
`AT="$(cd "$(dirname "$0")/.." && pwd)"` are all left alone. An interpreter named in a
flag's **value** (`rg --pre 'sh -c id'`, `git -c core.pager='sh -c id'`) is one token and
not a command position.

**And a `$`, a backtick or a `<` inside SINGLE QUOTES is a literal, not a substitution**
(`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §5a). The path check reads a word
through `path_body`, which strips a leading `NAME=` and one layer of surrounding *double*
quotes and leaves single quotes exactly where they are; `unquoted_index`, which reads what
is left, carries its own single-quote state, so a word quoted only in part (`cat
'$HOME'/x`) is judged character by character. Double quotes still come off, because `$`
and a backtick stay active inside them — `cat "$(pwd)/README.md"` really is a path decided
at run time, and `AT="$(cd … && pwd)"` is the whole-argument exemption above. Before this
the check used `word_body`, which strips either quote, so the backticks in `sed -n
'/```json/,/```/p' <file>` read as a command substitution: the line was **denied** as
unreadable when its file sat outside the root, while the same line with a file inside it
was approved by the read-only rule one branch earlier. A literal in single quotes is a
literal, and the human should have been asked. This is a narrowing only — it feeds
`is_opaque`, which runs only after the approval analysis has declined, so it can turn a
deny into a prompt and can never turn a prompt into an approval. The unquoted forms are
untouched: ``cat `pwd`/README.md`` and `` `which ls` src `` are still denied.

And a line carrying any heredoc is judged on the heredoc alone,
since its body lines read as commands to every scanner here — the same guard the other
three denies keep. **With one exception**: when every heredoc feeds `cat`, the segments
*before the first line break* are still checked for a pipe into an interpreter and for
code as a string, because that first line is a command line and not a body. Otherwise
`cat <<'EOF' | python3` and `bash -c "$(cat <<'EOF' … EOF)"` — the first two rewrites a
model reaches for once `python3 - <<EOF` is denied — would read as a plain `cat`, fall
through to the human's prompt, and reset the escalation counter on the way. The body
lines are after that break, so they stay unjudged and the `git commit -m "$(cat <<'EOF' …
EOF)"` exemption is untouched.

**The check runs last**, after the three shape denies and after the approval analysis has
declined to approve. A command this hook understands well enough to allow is readable by
construction, so `ls src # list it` keeps its approval instead of collecting a deny for
its comment; and a command it refuses for what it *does* — `rm -rf src`, `curl …`, `cat
/etc/passwd` — is *refused*, not *opaque*, and still prints nothing. That is the whole
distinction: opacity is about what the command hides, never about whether it was allowed.

**Seven more shapes joined them on 2026-09-18**, judged after the seven above and by the
same test for membership: the analysis could not read the command, and there is a rewrite
that always works. Each has a named reason constant, each names the member as written
(`MEMBER_TEXT_MAX_CHARS`), and a line carrying several gets one line per shape.

| Shape | Example | Reason names |
|---|---|---|
| a `$NAME`/`${NAME}` the shell will expand, anywhere in a word | `grep x $FILE`, `ls "$HOME/f"` | inline the literal |
| a word starting with `~` | `ls ~/x` | write the absolute path |
| a brace group the expansion refuses — a quote or backslash mixed into an unquoted brace group, nesting, past `MAX_BRACE_WORDS` | `cat {a,{b,c}}` | expand it yourself, or write a script |
| a `..` **component** of a path token | `cat ../x`, `ls a/../b`, `--out=../x` | write the path from the project root |
| a bare or relative `cd`/`pushd` | `cd src`, `cd` | `cd <absolute path>` as its own call |
| a line break outside a quote or a heredoc, or a `\` continuation | two commands on two lines | one call per line |
| a sequence (`&&`, `\|\|`, `;`) mixing approved members with members only the human can judge | `grep x f && git commit -m m` | which members to run on their own (approved) and which to run alone |

**One write per Bash call** is what the last row is for (design §2). A sequence whose
members are **all** ASK (`git add x && git commit -m m`) is one ASK — one prompt, not two;
the rule takes noise out of the prompt, it does not multiply prompts. A **pipeline** is
one command, judged by its members and never split: `./run-review.sh --self x 2>&1 | tail
-25` is ASK for the runner it starts with, and a pipe into an interpreter is still the
deny it always was. A `&` is a job, not a sequence, and is not eligible either.

**Not rewritable, and therefore ASK.** A `..` in a token that is not a path
(`git diff main...HEAD` carries no `..` component); a CR or a NUL; an environment prefix
(`X=1 make`); a command's output captured to a file (`pytest > out.log`, `cat a > b`,
`cmd | tee log`); a path outside the root; a whole-argument `$(…)`, the documented
exemption above — there is no literal to inline, so the human judges it. Each prints
nothing, exactly as before.

### A file authored through the shell

**Added 2026-09-21** (`../self/features/shell-write-rewrite/`). `CONVENTIONS.md` →
"Writing files" says to author files with the Write and Edit tools and never by shelling
out, because a write made by a subprocess gets past the repo's `Edit` allow and deny rules
and leaves the generic Bash approval as the only check. Nothing enforced it:
`cat >> tests/test_x.py <<'EOF' … EOF` was read as a write and returned ASK, which printed
nothing, and the model learned nothing. The shape always has a rewrite, so by the
membership test above it is a REWRITE. A member **authors a file through the shell** when
content written in the command itself lands in a file:

| Spelling | Example | Not this |
|---|---|---|
| `echo` or `printf` with its output redirected to a path — `>`, `>>`, `>\|`, `N>`, `&>`, `&>>`, attached or separate, anywhere among the words | `echo x > f`, `echo a>f`, `> f echo x` | `echo x 2>&1`, `echo x >&2`, `echo "a > b"`, `echo x > /dev/null` |
| `cat` or `tee` fed literally — a heredoc or herestring on the member, or for `tee` a pipe from `echo`/`printf` or a heredoc-fed `cat` — with output to a path (a redirect, or a file operand of `tee`) | `cat > f <<'EOF'`, `tee f <<'EOF'`, `cat <<< x > f`, `echo x \| tee f` | `cat a > b`, `cmd \| tee log`, `git commit -m "$(cat <<'EOF' … EOF)"` |
| `sed` editing in place — `-i` in any single-dash spelling (`-i`, `-i.bak`, `-Ei`, `-ni`, `-i ''`) or `--in-place[=…]` | `sed -i 's/a/b/' f` | `sed -n 5p f`, `sed 's/a/b/' f` |

A path is any redirect target except `NON_FILE_TARGETS` (`/dev/null`, `/dev/stdout`,
`/dev/stderr`, `/dev/tty`); an fd duplication and a process substitution (`>(…)`) are not
targets at all. **Where the file is does not matter**: the scratchpad, the root and `/tmp`
are all denied, because the Write tool reaches all three and is checked against the rules
the shell write bypasses. `cp`, `mv`, `touch`, `mkdir`, `rm` and `ln` stay ASK — none has
a Write/Edit rewrite that always works — and so does an interpreter script that writes
files (`python3 gen.py`), which is readable and runs by name.

**The reason** (`SHELL_AUTHORING_REWRITE_REASON`) names the member as written and gives
the rewrite: the Write tool for a new file or a whole rewrite, the Edit tool for a change
to an existing one — an append is an Edit anchored on the file's last lines — with the
*why* in one clause, since the session that prompted this knew the rule and broke it for
speed.

**Its own reader.** `opaque_segments` breaks at every `&` and `|`, so `2>&1`, `&> f` and
`>| f` come apart there; `redirect_members` reads the operators the way bash does, with
the same quote, backslash, backtick and `$(…)` tracking — a `>` inside quotes is text, and
a write inside a substitution is not judged. It hands back each member's words with the
redirects taken out, so `tee`'s file operand is never a heredoc delimiter or a redirect
target.

**Where it is judged.** In `command_verdict`, after `command_allowed` has declined and
**before** `opaque_deny_reason`, so `tee f <<'EOF'` — a heredoc into something other than
`cat`, and so the opaque deny before this — gets the Write reason rather than "write a
script to the scratchpad"; a heredoc into an interpreter (`python3 - <<EOF > f`) is still
the opaque deny. When a line carries a heredoc only the text before its first line break
is judged, the cut `segments_before_line_break` makes for the `cat` exemption: the body is
data, so a Markdown body full of `> quote` lines is never read as redirects. A `#` on the
judged text means the line is not judged, the guard every rewrite keeps, and a line whose
quotes are still open at the end is left to the unreadable shape. Only the members that
author a file are named: whatever else the line carries is judged when the model sends
what is left. It is a narrowing of ASK and never touches ALLOW — every case it fires on
printed nothing, or was the opaque deny, before it — and like every REWRITE it counts
toward `OPAQUE_REWRITE_ATTEMPTS`.

**The same two guards the three shape denies keep hold over all seven**: a line carrying a
heredoc, or a `#` anywhere, is judged on the shapes above alone. A heredoc's body lines
and the text after a `#` are data, not a command line, so `cat <<'EOF' … cd x … EOF` is a
file being written and not a relative `cd`, and `ls src # X=/p; cat $X` is a comment and
not a variable the shell will expand. A deny must not fire on a guess about a body.

**And the reader every one of them depends on tracks both quotes.** `unquoted_index`
carried single-quote state only, so a `'` inside `"…"` opened a span it thought was
single-quoted and everything after it read as literal: `cat "'"$(pwd)/x` is a `$(…)` in a
path that fell through to a prompt instead of being denied. Both quotes are tracked now,
and only one of them hides anything — a `$`, a backtick and a `<<` stay **active** inside
double quotes, so the needle is still reported there; what the double-quote state is for
is knowing that the `'` inside it is an ordinary character.

### Escalation after N rewrites

A deny must not demand the same rewrite forever. The hook counts opaque commands per
caller: the first `OPAQUE_REWRITE_ATTEMPTS` (2) are denied with the rewrite reason, and
the next returns `permissionDecision: "ask"` with a reason saying the command is still
unreadable after two rewrites and is the human's call. **Any command the analysis can
read resets the count** — approved, merely refused, or denied for one of the three older
shapes alike — because each of those is the model demonstrating it can write something
this hook reads.

The counter is keyed on the payload's `session_id` **and** its `agent_id`. `agent_id` is
present only when the hook fires inside a subagent call (Claude Code hooks reference), and
a subagent's payload carries its *parent's* `session_id` — so without the pair a
delegate's rewrites would escalate its coordinator. A payload with no `session_id` has no
counter at all and is denied every time rather than ever reaching `ask`.

State is one file per key under `$TMPDIR/agenttooling-hook-state/`, named by a digest of
the key so nothing from the payload reaches the filesystem. A missing, empty, corrupt or
unwritable file counts as **zero**: this state may turn into neither a crash nor a deny,
and the safe direction of every failure here is another deny rather than an `ask`.

### Headless runners and the scratch directory

`plan-runner-lib.sh` exports two variables into the `claude -p` it launches, at that one
site (`RUNNER.md` → "The executor's environment"):

- **`AGENTTOOLING_HEADLESS=1`** — the escalation step prints **nothing** instead of `ask`.
  An `ask` is a question for a human and there is none at a terminal in a batch; falling
  through lets the runner's own non-interactive policy decide. The counter still advances,
  so the state is the same as an interactive session's.
- **`AGENTTOOLING_SCRATCH=<dir>`** — a per-pass directory (inside the run's capture
  directory, so the existing teardown removes it; the same launch passes `--add-dir` for
  it, without which `acceptEdits` would refuse the Write). `bash <scratch>/x.sh` and `python3
  [-B] <scratch>/x.py` are approved from it, like the harness's own entry points and for
  the same reason: it is the place the opaque deny tells the model to write a script.
  Resolved through symlinks, so a link out of the directory is not a script in it; the
  file must exist; and the same basename anywhere else, or any of it with
  the variable unset, is not approved. The script **may take arguments**, and each is
  checked like any other path — `token_confined` against the project root, or inside the
  scratch directory lexically *and* through its symlinks. Existence never decides that
  check, though: a relative, non-flag argument (including the value after `=` in
  `--out=../x`) is judged LEXICALLY first, against the project root or the scratch
  directory, whether or not anything is there yet — an argument may well be the script's
  own OUTPUT path, so "names nothing on disk" cannot be the reason it passes. A bare flag
  (`--flag`, `-v`) carries no path and needs no such check. So `bash <scratch>/x.sh
  src/a.py`, `… <scratch>/helper.sh`, `… new-output.txt` and `… --flag` are approved, and
  `… /etc/passwd`, `… ../x` (whether or not `../x` exists) and `… --out=../x` prompt. A
  flag BEFORE the script is not a script: `bash -x <scratch>/x.sh` prompts, since it
  changes how bash runs the file. This is the only rule in the file that reaches outside
  the project root.

### What is approved silently

A command is approved only when **every** subcommand (split on `&&`, `||`, `;`, `|`, `&`)
passes, against a cwd that starts at the payload's `cwd` and moves with each `cd` (a
chained `cd` only reaches this analysis when § What it denies declined to judge it):

- `cd` — one argument, absolute, resolving inside the root through symlinks.
- Every argument that is a path must resolve inside the root: absolute ones through
  symlinks; relative ones against the effective cwd, expanded as globs first, so
  `dir/*` is judged by what it will actually name. `--flag=value` and `key=value`
  carry their path in the value. A value that names nothing on disk is not a path.
- The program: a read-only program (`READ_ONLY_PROGRAMS`) with none of its writing,
  executing or symlink-following flags (`FORBIDDEN_FLAGS`, whole token or the part
  before `=`; `FORBIDDEN_SHORT_LETTERS`, any letter of a single-dash token, which also
  catches `-ni` and `-i.bak`); `sed` with only `-n`/`-E`/`-r` and a script matching
  *optional address or range, then `p`*, because `w` inside a script writes a file;
  `git` with a read-only subcommand and no `--output`, where `branch` takes only listing
  flags and `worktree` only `list` — and where the subcommand may sit behind the global
  LOCATION options `-C`, `--git-dir` and `--work-tree` (`git_location_args`; their values
  are path-checked by the rule above like any other argument, and no other flag in front
  of the subcommand is read past — see § The git shape); a runner prefix
  (`RUNNER_PREFIXES`) — pytest,
  ruff, mypy, `npx playwright test`, and `npm run` for the named scripts only, since
  `npm run` executes whatever `package.json` says; or one of the harness's own entry
  points below.

#### The harness's own entry points

The commands an executor runs to read the state of its own work. Each is matched by
**basename**, and only when the script path exists and resolves inside the root, so one
rule covers both spellings of the same script — `plans/gate.sh`,
`agentTooling/check-plans.sh` and `agentTooling/analysis/report.py` in a consuming repo,
`self/gate.sh`, `./check-plans.sh` and `analysis/report.py` in agentTooling's own
checkout. A basename on its own vouches for nothing: `python3 /tmp/report.py` and
`python3 ../report.py` refuse, and so does one reached through a symlink that leaves the
tree.

**The token must carry a directory component.** `./check-plans.sh` and `self/gate.sh` are
approved; a bare `check-plans.sh` prompts, because bash resolves a word with no `/` along
`$PATH` rather than from the cwd — so the file this analysis found in the repo and the
program bash would run are two different things, and the one bash runs is whichever copy
`$PATH` names first.

| Approved | Held to |
|---|---|
| `gate.sh` | no arguments, or one level label |
| `check-plans.sh` | any arguments (they are `--self` and a slug) |
| `bash -n <files>` | only `-n`, at least one file |
| `shellcheck <files>` | no flags, at least one file |
| `python3 [-B] -m py_compile <files>` | at least one file |
| `python3 [-B] <…>/report.py` | any arguments |
| `python3 [-B] <…>/capture_planning.py` | some argument starts with `--list-`, and none is `--recapture`, `--all` or `--carry-lost` |
| `python3 [-B] <…>/manifest.py` | the subcommand — the second positional — is `get` |

Nothing else. `feature-start.sh`, `feature-close.sh`, `stamp-timing.sh`,
`capture_planning.py` in a capturing form, `manifest.py init` and `set-*`, `python3 -c`,
`bash <script>` without `-n` and every other script still prompt: each either freezes a
cost record, rewrites a manifest, moves a ref, or runs whatever it is handed.
`manifest.py get init` is a feature named `get` being initialized, which is why the
subcommand is read positionally rather than searched for.

This does **not** widen `python3`. The interpreter is approved only in front of
`-m py_compile` or one of those scripts, and every file argument is checked against the
root like any other path.

Refused outright, before any of that: `..` anywhere; a line break or NUL; a token
beginning with `~`; and, outside single quotes or a backslash, any of `< > $ \`` —
(each of these refusals is a REWRITE or an ASK above, never an approval; the refusal
itself is untouched, and only what is said about it changed) —
redirection, substitution. The harmless `2>&1`, `>/dev/null`, `2>/dev/null` and
`&>/dev/null` are stripped first. Unbalanced quotes refuse. A leftover punctuation token
that is not a recognised separator (`|&`, `;;`, `(`, `>&`) refuses.

Brace lists (`ls {src,tests}`, `cat src/{a,b}.py`) are expanded, not refused, when they
are simple. Every raw word of the command — split as bash splits it, quotes and
backslashes kept — that contains a brace must either be wholly single-quoted (bash reads
the brace literally) or carry no quote or backslash at all and consist only of simple
groups: `{` + comma-separated alternatives, at least one comma, no brace, whitespace,
quote, `$` or backtick inside, + `}`. The groups are removed in one pass and any brace
left over refuses, which is what refuses nesting (`{a,{b,c}}`), a comma-less `{a}`, and
`{}`. `..` is already refused, which covers sequence expressions (`{a..c}`). Each
subcommand is then checked twice with the same cwd: as its **literal** tokens, which keeps
a single-quoted `'{-a,-v}'` from approving `git branch`, and as its **expanded** words
(left to right, cartesian, as bash does), which checks every path and flag bash will
really see — so `cat {src/a.py,/etc/passwd}` and `sort -{r,o}x` refuse, and `cd {a,b}`
refuses for having two arguments. A token expanding to more than `MAX_BRACE_WORDS` (256)
words refuses, and an expanded word beginning with `~` refuses, since bash expands the
tilde after the braces.

## What the audit found and closed

Each of these approved something in the first version. All are now refused and asserted
in `self/tests/allow-repo-commands.sh`:

| Bypass | Was |
|---|---|
| `cat $HOME/.ssh/id_rsa` | `$` never rejected; a relative-looking token skipped the path check |
| `sort --output=~/.zshrc f`, `git log --output=…`, `pytest --junit-xml=/tmp/x` | `--flag=value` never split |
| `sed -i.bak`, `sed -ni`, `sort -o/tmp/x` | short flags matched as whole tokens only |
| `sed 's/a/b/w ~/.zshrc' f` | sed's `w` command writes from inside the script |
| `git branch -D main`, `git branch new` | `branch` allowlisted wholesale |
| `rg --pre 'sh -c …'`, `sort --compress-program=…` | exec-through flags not forbidden |
| `cat {/etc/passwd,}` | brace expansion produced a path the checker never saw; now expanded and each word checked |
| `ls \|& sh` | `\|&` is not a separator, so `sh` hid inside the `ls` group |
| `ls x#; rm -rf src` | shlex starts a comment at any `#`, bash only at a word's start, so the `rm` was never lexed; shlex comments are now off |
| `cat link-out/.zshrc`, `head dir/*` | relative paths and globs never resolved through symlinks |
| `grep -R`, `find -L`, `rg -L` | symlink-following recursion reads outside the tree |
| `tree -o f`, `uniq in out`, `npm run <any>`, `npx playwright install` | allowlist too wide |
| `ls > /dev/nullx` | redirect stripped by substring, not whole word |
| `ls <NUL>` | bash truncates at NUL; the analysis read past it |

### The second audit (2026-09-17)

Run against the analysis as it stood with the three denies in place. Each row was tried
against the real hook with a crafted payload before it was called a bypass; each is now
refused and asserted in `self/tests/allow-repo-commands.sh`, beside the near-miss that
must stay **approved**, so a closure that over-reached fails there.

| Bypass | Was | Guard beside it |
|---|---|---|
| `X=/tmp/e/pytest src/a.py` — an env prefix executes `src/a.py` | `program_name()` took the basename of the *assignment* word, so the hook read the next word as an argument to an allowlisted runner while bash read it as the program. An assignment at command position is now refused outright. | `X=1 make`, `FOO=1 ls` still prompt |
| `grep -f/etc/hosts src`, `file -m/etc/hosts README.md`, `rg -f/etc/hosts src` — a read outside the tree | `value_confined` returns True for any token starting with `-`, and where an attached option value begins is the program's business. A flag with no `=` that carries a `/` is now refused outright. | `ls -- src`, `git log --oneline -5`, `--flag=path` (still split and checked) |
| `ls -RL .`, `du -L .`, `du --dereference .` — lists or sizes every file under whatever an in-tree symlink points at | neither reader had a `FORBIDDEN_SHORT_LETTERS` entry; `find -L` and `grep -R` did | `ls -la src`, `du -sh .venv`, `grep -d recurse` (= `-r`, which does not follow) |
| `rg --hostname-bin=id x src`, `rg -z x src` | both run an external program — a hostname binary, a decompressor off `PATH` — like `--pre`, which was already forbidden | `rg -n pattern src` |
| `git show --textconv`, `git diff --ext-diff`, `git blame --textconv` | run whatever the repo's own config names for them | `git log --format=%x41`, `--pretty=format:%H` (formatting only) |
| `ruff check --fix src`, `ruff format src`, `mypy --install-types` — a write and an install | runner prefixes were matched and never inspected. "Repo code runs" covers a suite executing what the repo contains, not a linter rewriting it. `RUNNER_FORBIDDEN_FLAGS` and the `ruff format` report-flag rule close it. | `ruff format --check src`, `ruff format --diff src`, `ruff check src`, `python -m ruff check src` |
| `capture_planning.py --list-sessions --force` | not reachable to a write today (a listing mode exits first), but `--force` is what makes a capture overwrite a frozen record and a reader should not have to reason about argparse's ordering. Tightened into `CAPTURE_WRITING_FLAGS`. | the other listing forms |

### Considered and not a bypass

Each was tried; none is. They are here so the next audit does not re-derive them.

| Candidate | Why it is safe |
|---|---|
| an env prefix that changes behaviour (`PAGER=… git log`, `GIT_DIR=`, `PYTHONPATH=`, `LD_PRELOAD=`, `IFS=`) | `subcommand_allowed` refuses any assignment at command position, whatever the name (asserted by `FOO=1 ls` and the `X=/tmp/e/pytest` cases) |
| `grep -d recurse`, `grep --directories=recurse` | the same as `-r`, which does not follow symlinks; `-R`/`--dereference-recursive` does and is forbidden. `grep -D recurse` is a *devices* action, not recursion. |
| `find -H`, `find -P` | `-H` follows only a **command-line** symlink, and every argument is path-checked through `realpath` already; `-L`/`-follow` are forbidden |
| `du --files0-from=…`, `wc --files0-from=…`, `sort --files0-from=…`, `find -newer …`, `grep --file=…`, `git blame --contents=…`, `git diff --no-index …` | the outside path is a token or a `--flag=value`, and the path check refuses it |
| `git grep --open-files-in-pager` | `grep` is not in `GIT_READ_ONLY_SUBCOMMANDS`, so the flag is unreachable |
| `git -c core.pager=…`, `--exec-path=…`, `--config-env=…`, `--namespace=…` | none names a location this analysis can confine, so none is in `GIT_GLOBAL_LOCATION_OPTIONS`; `git_location_args` stops at the first unlisted flag and `git_allowed` then reads it as the subcommand, which matches nothing. Every spelling prompts. (`--git-dir` and `-C` no longer do when their value is inside the root — see "The git shape".) |
| `sed`'s `e`, `w`, `W`, `r`, `s///w`, a newline in the script, `--expression`, `-s`, `--` | none can match `SED_PRINT_SCRIPT_RE`; a newline anywhere is already `UNANALYSABLE`; the flags are not in `SED_ALLOWED_FLAGS` |
| `python3 -m py_compile <symlink out>` | every file argument is path-checked through `realpath` like any other |
| `python3 -m py_compile <file>` leaves a `__pycache__` | a write, confined to the root, and the check's own output; `-B` suppresses it and the gate passes it |
| process substitution `<(…)` | `<` is a shell-active character outside single quotes |
| a `\` line continuation | the literal newline it leaves is in `UNANALYSABLE` |
| a token after `--` | `flag_forbidden` still fires on it, conservatively: `grep -- -R x src` prompts |
| a NUL byte, a unicode look-alike for `/` | NUL is `UNANALYSABLE`; a homoglyph is not `os.sep`, so it can only fail to resolve and name nothing |
| `cat {src,link-home}/a.py` | the expansion names nothing on disk, and a file that does not exist cannot be read |
| `cat -`, `tail -F`, `pytest --pdb`, `npx playwright test --ui` | these block rather than escape: the agent's own Bash call hangs, which is a cost to it and not a read, write or exec outside the tree |
| `rg --search-zip`'s decompressor, `git`'s configured `textconv` | both need a planted file or a planted `PATH` entry first, which is the accepted limit below — and both are forbidden anyway |

### The `wire-settings.py` gap

`bash_deny_rules()` renders command **prefixes**, and the hook reads relations and
shapes, so two things the hook denies have no prefix twin and cannot get one:

- **The run-time-value deny** — a relation between two tokens anywhere on the line.
- **The opaque deny** — a shape, not a prefix; `python3 -c` is a prefix but a heredoc,
  a pipe into an interpreter and a `$(…)` inside a path are not.

In each case the hook is the whole of the enforcement, and `permissions.deny` is the
visible half of only what a prefix can say.

What used to be a third entry here — `git worktree move|lock|unlock|repair` and
`git branch --delete|--move`, which a prefix rule *can* express and which
`permissions.deny` did not name — was the drift `policy.py` closed. There is no fixable
half left: the table renders one rule per mutating entry, and
`self/tests/policy-table.sh` fails if it ever stops.

## Accepted limits

- **Repo code runs.** pytest, ruff, playwright and the `npm run` scripts execute what the
  repo contains. That is what "run the tests" means; a change to that code is a write,
  which this hook never approves — `RUNNER_FORBIDDEN_FLAGS` and the `ruff format` rule
  are where that line is drawn.
- **A command may hang.** `cat -`, `tail -F`, `pytest --pdb` and `npx playwright test
  --ui` are approved and block. The cost is the agent's own Bash call, not a read, a
  write or an exec outside the tree, so they are not the hook's problem.
- **A planted file needs a prior write.** An unquoted glob that expands to `-delete`, a
  look-alike `python` symlink inside the tree, a `.git/config` that points `diff.external`
  at a command — each requires a file to exist first, and creating it prompts.
- **Conservative false negatives.** A grep pattern that looks like an absolute path
  outside the tree (`grep '/usr/lib' src`) prompts. So does `~` anywhere a token starts,
  `..` anywhere at all, and any `$` outside single quotes even when escaped inside double
  quotes. The cost of each is one prompt.
- **`||` short-circuit.** The effective cwd after `cd A || cd B` is taken as `B`. Every
  `cd` target is inside the root regardless, so the approximation only affects which
  inside directory relative arguments are resolved against.

## The deny rules

`wire-settings.py` also maintains two sets of rules in `permissions.deny`, which binds in
every permission mode and cannot be overridden by a mode or an allow rule, and one rule
in `permissions.ask`, which is evaluated before any allow rule and forces a prompt.

### `Edit`

`--permission-mode acceptEdits` — which the batch runners use — accepts every Edit-tool
write under the working directory, unattended. So:

```
Edit(/.git/**)      Edit(**/.git/**)     Edit(**/.git)
Edit(/.claude/**)   Edit(**/.claude/**)
Edit(**/.venv/**)   Edit(**/venv/**)     Edit(**/node_modules/**)
```

`.git/hooks/*` is executable code; `.claude/` is the permission system itself; and the
dependency trees are code that runs on the next test. The `**/`
forms match at any depth, so a worktree's copies are covered; the two root-anchored forms
are insurance for the two that matter most. Deny rules reach the Edit and Write tools and
`> file` redirects,
not a subprocess that opens a file itself — which is also why `sync-plans.sh` can still
write `.claude/settings.json` through this helper. OS-level enforcement is sandboxing.

**`hooks/` is an `ask` rule, not a deny**, and it is the one rule whose spelling depends
on the mode:

```
permissions.ask:
Edit(**/agentTooling/hooks/**)                       # vendored
Edit(**/hooks/**)   Edit(/hooks/**)                  # under --self
```

This directory is the policy, and an unattended executor must not be able to widen what
the hook approves — but a human editing it should be *asked*, not refused. An ask rule is
evaluated before allow rules and fires even under `acceptEdits`, and in a headless
`claude -p` there is no terminal to answer it, so a matching ask is **denied** there.
That is exactly the split wanted: an attended session prompts, a runner's executor is
refused. **Known limit:** under `bypassPermissions` an ask does not fire at all — only
deny binds in that mode — and the runners launch with `acceptEdits`, never bypass
(`RUNNER.md` → "The executor's environment").

The `**/` spelling is what closed the hole the root-anchored deny left: `Edit(/hooks/**)`
is anchored at the *project root*, so for a session rooted at the primary checkout the
copy in `.worktrees/<slug>/hooks/` was neither denied nor asked about, and that is how
this feature's own predecessor edited the policy. At any depth it is covered from either
root. The cost, stated where a consuming repo will meet it: `Edit(**/hooks/**)` under
`--self` matches any directory named `hooks/` at any depth of *this* checkout, which is
the right trade here and is why the vendored spelling keeps its `agentTooling/` segment.

A consuming repo that already has the old `Edit(**/agentTooling/hooks/**)` **deny** rule
keeps it: the merge never removes a rule. Its next `sync-plans.sh` adds the ask rule
beside it, and deny wins over ask, so editing `hooks/` there stays refused until a human
deletes the deny line by hand. Nothing here reaches into another repo to do it.

### `Bash`

`LIFECYCLE.md` rule 2 — agents never create or destroy branches and worktrees, and never
rewrite history — written where `/permissions` will show it:

```
Bash(git push --force:*)   Bash(git push -f:*)   Bash(git push --force-with-lease:*)
Bash(git reset --hard:*)   Bash(git clean:*)     Bash(git stash:*)   Bash(git rebase:*)
Bash(git worktree add:*)   Bash(git worktree remove:*)   Bash(git worktree prune:*)
Bash(git worktree move:*)  Bash(git worktree lock:*)     Bash(git worktree unlock:*)
Bash(git worktree repair:*)
Bash(git checkout -b:*)    Bash(git checkout -B:*)
Bash(git switch -c:*)      Bash(git switch -C:*)
Bash(git branch -d:*)      Bash(git branch -D:*)      Bash(git branch --delete:*)
Bash(git branch -m:*)      Bash(git branch -M:*)      Bash(git branch --move:*)
```

These are **prefix** rules: each matches only a command that begins with the text it
names, so `git -C /repo worktree add x`, `x=$(git rebase main)` and `ls && git stash`
match none of them. The enforcement is the hook's git deny above, which reads every
command on the line; these rules are the visible half of the same policy. They are not a
second list any more: `policy.bash_deny_rules()` renders them from the same table the
hook reads, in the order above — push force ×3, `reset --hard`, the always-mutating
verbs, worktree ×7, checkout, switch, branch — so an entry added to the table reaches
both halves and `self/tests/policy-table.sh` asserts that it did. A rule here is never an
allow rule; nothing this helper writes ever is.

## What `wire-settings.py` will and won't touch

**In a consuming repo**, `.claude/settings.json` is repo-owned and may hold anything, so
everything is **merged,
not copied**. The hook entry is appended when no hook command anywhere in the file
mentions `allow-repo-commands.sh`; each deny and ask rule is appended when its exact
string is absent. Otherwise the file is left byte-for-byte alone. It never removes,
reorders or rewrites another entry, and it never adds an allow rule.

**Under `--self` the file is wholly generated**, because nothing else writes
agentTooling's own: there is no repo to own it but this one. So `--check` compares it
**byte for byte** with what a fresh `--write` into an empty directory produces, and names
where it first differs and which entry one side carries that the other does not; and
`--write` puts those bytes back, reporting `kept` when they were already there. That is
the whole point of the mode: the merge check could only ever see a *missing* entry, so a
hand-added allow rule, a hook command repointed at the vendored path where it would never
run, or a reordered deny list all left `self/gate.sh` green while this file said they
failed it. They fail it now. The corollary is that a hand edit to that file is **lost**
on the next write rather than merged — which is what "generated" means, and why the
`Edit(/.claude/**)` deny rule refuses to let one be made through the Edit tool at all.

The hook marker is the script's basename, so a repo that hand-edits the entry — a
different path, a narrower `matcher`, an added `if:` — keeps its version and never gets a
duplicate. Deleting an entry or a rule is durable in one direction only: the next
write run re-adds it. To opt out of the hook for good, keep an entry that points it
somewhere harmless rather than deleting it; to opt out of a deny rule, remove it from
`EDIT_DENY_RULES` here or from `policy.py`'s table, which changes it for every consuming
repo.

`--self` changes the hook command (which loses the `agentTooling/` segment), the ask
rule's spelling (`Edit(**/hooks/**)` and `Edit(/hooks/**)`, since here `hooks/` is at the
root), and how the file is maintained (generated, not merged). The deny rules are the
same list in both modes. The two are not interchangeable: `--self --check` over a
vendored repo's file reports `UNWIRED`, and an ordinary `--check` over this checkout's
reports it too.

A consuming repo's file that does not parse, or whose `hooks`, `hooks.PreToolUse`,
`permissions`, `permissions.deny` or `permissions.ask` values are the wrong type, is
reported `INVALID` and left untouched. `--self` never reports `INVALID`: a generated file
that does not parse is drift like any other, and the write replaces it.

## Cross-layer dependencies

- **`CLAUDE_PROJECT_DIR`** — `allow-repo-commands.sh` reads this for the project root and
  approves nothing when it is unset. Claude Code sets it for hook processes. In a `git
  worktree` it is the worktree root, so a worktree session approves paths inside its own
  tree only — never the main checkout.
- **`cwd` in the hook payload** — must be present and inside the root, or a relative path
  in the command could resolve anywhere. The hook approves nothing without it. The opaque
  check still runs when it is missing: an unreadable command is unreadable wherever it
  runs, as the three shape denies already were.
- **`session_id` and `agent_id` in the hook payload** — the escalation counter's key.
  `agent_id` is present only inside a subagent call and a subagent carries its parent's
  `session_id`, so the pair is what keeps a delegate's rewrites off its coordinator's
  count. A payload with no `session_id` never escalates.
- **`$TMPDIR`** — where the escalation state lives
  (`$TMPDIR/agenttooling-hook-state/<digest>.count`, `/tmp` when unset). Nothing else in
  the hook touches the filesystem for state, and every read of it tolerates absence and
  corruption.
- **`AGENTTOOLING_HEADLESS` and `AGENTTOOLING_SCRATCH`** — set by
  `plan-runner-lib.sh`'s `claude -p` launch site and by nothing else (`RUNNER.md` → "The
  executor's environment"). The hook is their only reader. Neither is set in an ordinary
  interactive session, where the escalation asks and no scratch directory is approved.
  The scratch directory is only usable if that same launch also passes `--add-dir` for it:
  `--permission-mode acceptEdits` auto-accepts a Write under the working directory alone,
  and this directory is under `$TMPDIR`. Approving a script the executor could never have
  written is a dead end, so the two belong to one contract — asserted together in
  `self/tests/stream-capture.sh` phase 10.
- **`policy.py` beside both scripts** — neither imports it by package name or from the
  cwd: each inserts its own `os.path.dirname(os.path.realpath(__file__))` on `sys.path`
  first, because the hook is run from wherever the session sits and the writer from
  wherever `--repo` points. Moving either script out of this directory, or vendoring one
  without the other two, is an `ImportError` at the first Bash call rather than a silent
  fallback. Both set `sys.dont_write_bytecode` so the import leaves no `__pycache__` in
  the repo being guarded.
- **`python3` on `PATH`** — `sync-plans.sh` skips the wiring with a `SKIPPED` line when it
  is absent. The hook itself is `#!/usr/bin/env python3`.
- **`.claude/settings.json` must be committed** to reach worktrees. A `git worktree` gets no
  `.claude/` of its own, and `.claude/settings.local.json` is ignored globally by Claude
  Code's default `~/.config/git/ignore` entry. The shared file is the only copy a worktree
  or a fresh clone can inherit. `sync-plans.sh` says so when it writes one.
- **This checkout's own `.claude/settings.json` is written, not authored.**
  `python3 -B hooks/wire-settings.py --self --repo <root> --write` produced the committed
  file at the root of agentTooling, and `self/gate.sh` records
  `wire-settings.py --self --repo <root> --check` as a blocking check, which compares it
  byte for byte, so a hand edit of any kind — an added rule as much as a missing one —
  fails the gate. Do not edit that file directly — the
  `Edit(/.claude/**)` rule in it refuses anyway; change the constants here and re-run the
  write. The file ships with the subtree like everything else in this directory, and a
  consuming repo's own wiring is the one at *its* root, written by `sync-plans.sh` without
  `--self`.
- **The hook is trusted code that lives in the repo.** `update.sh` pulls it from the
  agentTooling upstream and re-runs the wiring, so that upstream is the trust root for
  the policy. The `Edit(**/agentTooling/hooks/**)` **ask** rule keeps an unattended
  executor from changing it through the Edit tool — a headless session cannot answer an
  ask, so it is refused there, while an attended one is prompted; a subprocess write is
  the remaining path, and only the sandbox binds that.
- **Hooks are read at session start.** A change to the wiring takes effect in the next
  session; `/hooks` shows what the current one loaded.

## Wiring

`sync-plans.sh` does this. By hand, the equivalent is:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh" }
        ]
      }
    ]
  }
}
```

In agentTooling's own checkout the command is
`${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh`, which is what
`wire-settings.py --self --write` writes.

## Editing the policy

The allowlists are named constants at the top of `allow-repo-commands.sh`:
`READ_ONLY_PROGRAMS`, `FORBIDDEN_FLAGS`, `FORBIDDEN_SHORT_LETTERS`, the `SED_*` grammar,
`GIT_READ_ONLY_SUBCOMMANDS` / `GIT_BRANCH_ALLOWED_FLAGS` / `GIT_WORKTREE_READ_ONLY`,
`RUNNER_PREFIXES`, `RUNNER_BASENAMES`, `RUNNER_ALIASES`, `RUNNER_FORBIDDEN_FLAGS` /
`RUNNER_RUFF*` and `MAX_BRACE_WORDS`, the
`ENTRY_*`, `CAPTURE_*`, `MANIFEST_*`, `SYNTAX_*` and `PYTHON_*` constants for the
harness's own entry points, plus `CHDIR_PROGRAMS` and
`ASSIGNMENT_RE` / `ASSIGNMENT_BUILTINS` / `VAR_USE_RE` for the
three shape denies. **The `GIT_*` mutation constants are not there**: they are
`policy.py`'s, the table `wire-settings.py` renders its prefix rules from, and the hook
binds the same objects under the same names. The opaque deny is `OPAQUE_REWRITE_ATTEMPTS`,
`HEREDOC_LITERAL_PROGRAMS`, `INTERPRETER_CODE_LETTER`, `EVAL_PROGRAM`,
`COMMAND_CARRIER_PROGRAMS`, `FIND_EXEC_FLAGS`, `COMPOUND_KEYWORDS`, `SEGMENT_BREAKS` and
`LINE_BREAK_CHARS` (the subset of `SEGMENT_BREAKS` that ends the command's first line,
which is where `segments_before_line_break` stops for a `cat` heredoc);
`UNREADABLE_DENY_REASON` for the seventh shape; the verdicts and the shapes added on
2026-09-18 are `VERDICT_ALLOW` / `VERDICT_REWRITE` / `VERDICT_ASK`, `MEMBER_TEXT_MAX_CHARS`
/ `MEMBER_TEXT_CUT` / `MEMBER_QUOTE`, `REASON_PREFIX` / `REASON_LINE_SEPARATOR`,
`LINE_BREAK_NEWLINE`, `SEQUENCE_SEPARATORS`, `PARENT_COMPONENT`, `BRACE_EMPTY_GROUP` and
one reason constant per shape (`VAR_USE_REWRITE_REASON`, `TILDE_REWRITE_REASON`,
`BRACE_REWRITE_REASON`, `PARENT_PATH_REWRITE_REASON`, `RELATIVE_CHDIR_REWRITE_REASON`,
`LINE_BREAK_REWRITE_REASON`, `MIXED_SEQUENCE_REWRITE_REASON`); the shell-authored file is
`AUTHORING_ECHO_PROGRAMS`, `AUTHORING_LITERAL_PROGRAMS`, `AUTHORING_TEE_PROGRAM`,
`AUTHORING_HEREDOC_FED_PROGRAM`, `AUTHORING_SED_PROGRAM`, `SED_IN_PLACE_LETTER`,
`SED_IN_PLACE_LONG`, `SED_VALUE_LETTERS`, the `REDIRECT_*` operator constants,
`PROCESS_SUBSTITUTION_PREFIXES`, `FD_DUP_TARGET_RE`, `NON_FILE_TARGETS`,
`AUTHORING_SEPARATOR_CHARS`, `PIPE_SEPARATORS` and `SHELL_AUTHORING_REWRITE_REASON` — a new shape is a constant,
a predicate in `rewrite_reason_lines`'s table, a case in `self/tests/allow-repo-commands.sh`
and the row above;
the escalation is `STATE_DIR_NAME` / `STATE_FILE_SUFFIX` / `STATE_KEY_SEPARATOR` under
`TMPDIR_ENV`, with `HEADLESS_ENV`, `SCRATCH_ENV`, `SCRATCH_BASH` and
`SCRATCH_SCRIPT_MIN_ARGS` for the runner-side pair. Every change to the approval
constants is a widening of
what runs without a prompt: add the command to `self/tests/allow-repo-commands.sh` with
the bypass you checked it does not open, and run `bash self/tests/allow-repo-commands.sh`.
A change to `CHDIR_PROGRAMS` adds a `DENY` case and a `NOT_DENIED` case there. A change
to any opaque constant adds an `OPAQUE_DENY` case *and* an `OPAQUE_NOT_DENIED` case, and
anything touching the counter, the `ask`, the headless fall-through or the scratch entry
point belongs in `self/tests/hook-escalation.sh`, which is the only place the state file
is exercised at all (`bash self/tests/hook-escalation.sh`).

**The git policy is one table.** `policy.py` holds `GIT_ALWAYS_MUTATING`, the flag sets
and `GIT_WORKTREE_SUBCOMMANDS`; the hook imports them for `git_mutates`, and
`bash_deny_rules()` renders the `permissions.deny` prefix twin from the same constants.
So a subcommand is added **once**, and what follows is: a `DENY` case and a `NOT_DENIED`
case in `self/tests/allow-repo-commands.sh`, and
`python3 -B hooks/wire-settings.py --self --repo <root> --write` to regenerate this
checkout's `.claude/settings.json` (the gate's byte-for-byte check fails until you do).
`self/tests/hook-wiring.sh` and `self/tests/policy-table.sh` render the list from the
table rather than repeating it, so neither needs editing. Consuming repos pick the new
rule up on their next `sync-plans.sh`.

This is what replaced "two constants move together", which is how the two lists drifted
for as long as they did: `permissions.deny` named neither
`git worktree move|lock|unlock|repair` nor `git branch --delete|--move`, and nothing
failed.
