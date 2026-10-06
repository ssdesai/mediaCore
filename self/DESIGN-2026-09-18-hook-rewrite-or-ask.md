# Design 2026-09-18 — the hook asks for a rewrite it can name, and asks the human about a write it has read

Feature slug: `hook-rewrite-or-ask`. Base: `minutes-slug-and-quoting` (its S5 edits the same
hook, so this stacks on it; retarget to `main` at the close once the chain has merged).
Built direct by one implementer, tests first; the review is opus, because the hook is
the safety boundary.

The user's rule, 2026-09-18: *"there should be some way for the hook to ask for a rewrite
if possible for a command that can't be analyzed. if analysis runs and says potentially
unsafe then it should go to the user, not just because it can't be read."* And: the
coordinator's working rules go in the repo as guidelines, not in a memory.

## §1 Three outcomes, decided by what the analysis learned (D1)

**Defect.** `command_allowed` returns a bool. Every refusal — "I could not read this" and
"I read it and it writes" alike — collapses to `False`, and the only refusals that carry
a rewrite are the seven opaque shapes checked afterwards over the raw text. Everything
else the analysis could not read prints nothing and costs the human a prompt, and the
model learns nothing: a `$NAME` in an argument (`grep x $FILE`), a `~`, a brace group the
expansion refuses, a `..` component in a path, a lone relative `cd`, a line break outside
a heredoc. Replaying one coordinating session's 24 commands on 2026-09-18: 5 approved, 18
prompted with no reason, 1 denied.

**Rule.** The approval analysis returns a *verdict*, not a bool — for each subcommand and
then for the line — one of three:

- **REWRITE** — the analysis could not read the command, and a rewrite exists. Denied,
  the rewrite is the reason, and it counts toward the existing escalation
  (`OPAQUE_REWRITE_ATTEMPTS`, then `ask`; headless falls through) exactly as the seven
  opaque shapes do today. The seven keep their reasons and join this class.
- **ASK** — the analysis read the command and cannot vouch for what it does: a program
  outside the read-only list, the runners and the harness entry points; a forbidden flag;
  a git subcommand that is not read-only (a ref mutation is still the older deny); a
  redirect that writes; a path outside the root; an environment prefix; a `$(…)` that is a
  whole argument (the documented exemption — there is no literal to inline, so the human
  judges). Prints nothing, as today, so the settings' own `permissions.allow`/`deny` rules
  and then the human decide. The command the human sees is one the hook has read.
- **ALLOW** — every subcommand read-only and confined. Unchanged.

Precedence on a line: any REWRITE member makes the line REWRITE (the human is never
handed an unreadable line); else any ASK member makes it ASK; else ALLOW. The three
older shape denies (chained `cd`, git refs, own assignment) still run first, unchanged.

The rewritable shapes, each with a named constant for its reason:

| Shape | Example | Rewrite the reason names |
|---|---|---|
| the six code-hiding shapes and the line that will not tokenize | as today | as today |
| a `$NAME` / `${NAME}` the shell will expand, anywhere in a word | `grep x $FILE`, `ls "$HOME/f"` | inline the literal |
| a `~` | `ls ~/x` | write the absolute path |
| a brace group the expansion refuses (a quote or backslash mixed into an unquoted brace group, nesting, past the cap) | `cat {a,{b,c}}` | expand it yourself or write a script |
| a `..` component in a path token | `cat ../x`, `ls a/../b` | write the path from the root |
| a lone relative or bare `cd` | `cd src`, `cd` | `cd <absolute path>` |
| a line break outside a quote or a `cat` heredoc body, or a `\` continuation | two commands on two lines | one call per line |
| a sequence mixing approved members with one the hook would ask about | `grep x f && git commit -m m` | run the reads on their own (they are approved) and the write alone — §2 |

Round 1 of this feature's own review (`escalations/01-review-opus.md`) corrected both rows
above: a raw-text reader that does not track quotes had denied a brace inside quotes
(`jq -r ".[] | {name}" data.json`) and a line break inside a quoted argument
(`git commit -m "subject\n\nbody"`), neither of which bash treats as the shape named —
both are literals, and are ASK.

Not rewritable, and therefore ASK rather than REWRITE: `..` in a token that is not a
path (`git diff main...HEAD` has no `..` *component*; the raw `".." in command` guard is
replaced by the component test, which still catches `../x` and `a/../b` — the lexical
scratch-argument rule from the policy feature is unchanged and still runs first); a CR or
NUL in the command; an environment prefix; a `>` redirect. The `UNANALYSABLE` tuple goes,
its members judged one by one as above.

**A quote inside the other quote.** `unquoted_index` tracks single quotes only, so a `'`
inside double quotes opens a span it thinks is single-quoted and everything after it reads
as literal: `cat "'"$(pwd)/x` is a `$(…)` in a path that today falls through to a prompt
instead of being denied (the coordinator's audit of `minutes-slug-and-quoting` S5a,
2026-09-18). The walk tracks both quotes — a `'` inside `"…"` is a character, a `"` inside
`'…'` is a character — and that command is REWRITE like any other substitution in a path.
This is the reader every shape above depends on, so it is fixed first.

**Which existing test cases move.** The `NOT_DENIED` groups in
`self/tests/allow-repo-commands.sh` assert today's prompts, and some of those prompts are
shapes the table now rewrites: `cat $HOME/f` (`ASSIGN_NOT_DENIED`), every `~` case, every
`..`-path case, every brace group the expansion refuses, `cd src`. Each such case is
**moved** into the matching REWRITE group with its reason asserted, never deleted, and the
implementer lists every moved case in `NOTES.md`. A case whose shape is *not* in the table
(`ls \`id\``, `x=$(cd dir && pwd)`, `git diff main...HEAD`, `X=1 make`) still prompts and
stays where it is. Every `ALLOW` and every `DENY` case is unchanged.

## §2 One write per call (D2)

A sequence (`&&`, `||`, `;`) is REWRITE when at least one member is approved and at least
one is ASK: the reason lists the approved members as "run on their own — approved" and
the others as "run alone". A sequence whose members are all ASK (`git add x && git commit
-m m`) is one ASK — one prompt, not two; the rule removes noise from the prompt, it does
not multiply prompts. A **pipeline** (`|`) is one command, judged by its members but never
split: `./run-review.sh --self x 2>&1 | tail -25` is ASK for the runner it starts with,
its `tail` is part of the command, and a pipe into an interpreter is still the deny it is
today. A `cat <<'EOF' … EOF` inside a `$(…)` is a literal, as today.

## §3 The reason names the member (D3)

Every REWRITE reason names the member as written (truncated at a named length), the
shape, and the rewrite, one line per shape when a line has several. The escalation
reason and the headless behaviour are unchanged; `hook-escalation.sh` gains one case per
new shape to show the counter advances, and one to show an ASK resets it.

## §4 The guidelines live in the repo (D4)

`CONVENTIONS.md` § Shell commands is rewritten around the three outcomes, in this order:
what is approved silently (read-only, confined); what is sent back with a rewrite (the
table above, in prose, each shape with its rewrite); what reaches the human (a write, a
path outside the root) — and the model's rule for that last class: **one write per Bash
call, nothing else on the line**, reads in their own calls, so the human approves one
thing; `cd <absolute path>` as its own call rather than `git -C <another tree>`; the
Read, Grep, Write and Edit tools rather than `sed -n`, `cp`, `cat >`. § Writing files
names `cp` beside `cat >` and `sed -i`. `hooks/README.md` § What it denies and § What it
approves become one section, "The three outcomes", with the table; § The opaque shape is
absorbed into it; § Escalation stays. `AGENT_DIRECT.md` and `RUNNER.md` get a pointer only
where they restate a shape. The coordinator's memory is a pointer to `CONVENTIONS.md`,
not a copy of the rule.

## §5 Assertions

`self/tests/allow-repo-commands.sh`:

- Each rewritable shape is DENIED with a reason containing that shape's phrase and the
  member's text: `grep x $FILE`, `ls ~/x`, `cat {a,{b,c}}`, `cat ../x`, `cd src`, a
  two-line command, `grep x f && git commit -m m` (reason names `grep x f` as approved
  and `git commit -m m` to run alone), `cat "'"$(pwd)/x`.
- Each ASK case prints nothing: `git diff main...HEAD`, `x=$(cd dir && pwd)`,
  `git add x && git commit -m m`, `./run-review.sh --self x 2>&1 | tail -25`, `X=1 make`,
  `echo x > f`, `cat /etc/hosts`.
- Still denied: `ls src | python3`, `python3 -c 'x'`, `cat 'x`, the three older shapes.
- Every existing ALLOW / DENY case is unchanged; every NOT_DENIED case is unchanged or
  moved as §1 says, and the moved ones are listed.
- A replay table: the 24 commands of 2026-09-18 (in a fixture file under
  `self/tests/fixtures/`, one command per record with its expected verdict) — the
  design's own claim, asserted.

`self/tests/hook-escalation.sh`: a new-shape deny advances the counter; an ASK resets it;
the third unreadable command is `ask`; headless prints nothing.

`self/tests/hook-wiring.sh` / `policy-table.sh`: unchanged and green (no prefix-rule twin
for any of this; the git table is untouched).

## §6 Deliberately excluded

- Emitting `ask` with a reason for the read-and-unsafe class: an explicit `ask` would
  override `permissions.allow` rules the human wrote, and the prompt already shows the
  command.
- Approving any new program (`ps`, `cp`, …): a policy change, not this feature.
- A rewrite for a `$(…)` whole-argument substitution: the exemption stands as documented.
- Anything `minutes-slug-and-quoting` S5 changed (the single-quoted literal through
  `path_body`, `git -C <in-root>` through `git_location_args`): this feature builds on
  them and keeps their tests green.

## §7 Build

One opus implementer, direct, tests first, from the worktree; review opus, once.
