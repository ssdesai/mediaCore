Verdict: escalated

# Review — hook-rewrite-or-ask (round 1, opus)

Diff read: `git diff minutes-slug-and-quoting...HEAD` (the manifest's `base`). Gate report
`level: final`: every check `exit: 0`, none SKIPPED.

## What the batch was supposed to do

The approval analysis in `hooks/allow-repo-commands.sh` answers one of three verdicts
instead of a bool:

- **REWRITE**: the command can't be read and a rewrite exists. It is denied with the
  rewrite as the reason, through the existing escalation.
- **ASK**: the command was read, but it writes or runs an unknown program. The hook prints
  nothing.
- **ALLOW**.

It also covers the new rewritable shapes (`$NAME`, `~`, a refused brace group, a `..`
component, a relative `cd`, a line break) and the one-write-per-call rewrite for mixed
sequences. The quote walk now tracks both quotes. The guidelines in `CONVENTIONS.md` and
`hooks/README.md` are rewritten around the three outcomes, and there is a replay fixture.

## Does it do it

Yes, except for the two defects below.

- **ALLOW did not widen.** This held when I read the diff as an adversary.
  - `command_verdict` returns ALLOW only from `command_allowed`, called with the same
    `realpath(cwd)` as before. Neither `command_allowed` nor anything it calls is in the
    diff.
  - `unquoted_index`, the one shared reader that changed, is called only by the deny
    readers (`heredoc_programs`, `substitution_in_path`), never by the approval path.
  - `member_allowed` only picks the wording of a reason, and it can't produce a verdict.
  - No test case moved into an ALLOW group.
- **DENY did not narrow.**
  - The three older denies still run first in `main()`, unchanged.
  - `opaque_deny_reason` is unchanged and runs before the new shapes.
  - Every NOT_DENIED case that left its group went into a REWRITE group whose shape is in
    the design's table. I checked each removal in the test diff against its destination,
    and every move is listed in `NOTES.md` § Every moved case.
- **ASK prints nothing.** `main()` returns silently and clears the counter. The brief's
  seven cases are asserted in `ASK_CASES` and in the replay.
- **Escalation.** `hook-escalation.sh` §9 asserts four things for the new shapes: the
  counter advances, the third command is `ask`, an ASK resets the counter, and headless
  prints nothing.
- **Protected files.** `hooks/policy.py`, `.claude/settings.json` and `wire-settings.py`
  did not move. `hook-wiring.sh` and `policy-table.sh` are untouched and green.
- **Deviations from the design** each have a ruling in `NOTES.md`:
  - `command_allowed` keeps its bool.
  - `UNANALYSABLE` keeps its refusal.
  - The fixture is composed rather than transcribed, and has 27 records rather than 24.

  Rulings 1 and 2 are sound, because either change as the design wrote it would have
  widened ALLOW. Because of ruling 9, the replay checks each shape. It does not reproduce
  the design's "5 approved / 18 prompted / 1 denied" count, since nobody recorded those
  commands.
- **Guidelines.**
  - `CONVENTIONS.md` § Shell commands reads approved / sent back / reaches the human. It
    states one write per call, `cd <abs>` over `git -C <other tree>`, and the tools over
    `sed -n`/`cp`/`cat >`. § Writing files names `cp`.
  - `hooks/README.md` has "The three outcomes" and § Escalation. The old "What it
    denies" / "What it approves" / "The opaque shape" sections are gone.

## Fixed in this pass

Nothing. I tried to fix escalation 1 in place, but the Edit rule refused the write under
`hooks/`. As the brief instructs, I did not shell a write around it, and it is escalated
below with the exact replacement.

## Escalated to the next round

### 1. A line break inside a quoted argument is denied as "several commands in one call"

**Where:** `hooks/allow-repo-commands.sh`, `carries_line_break` (around line 1288).

**What's wrong:** the function returns `LINE_BREAK_NEWLINE in command` over the raw text,
with no quote state.

**Example:** `gh pr create --title t --body "a<LF><LF>b"`, or
`git commit -m "subject<LF><LF>body"` (no heredoc, and no `#` in the body).

**What happens:** the command is REWRITE, denied with "Send one call per line", and the
denial counts toward the escalation. A newline inside a quoted word is one argument, not a
second command. That rewrite can't be carried out, so the shape fails the design's own
membership test: "a rewrite that always works". Before this feature the command was a
silent prompt, and it should still be ASK.

**Fix (local, same signature):** walk the text with the same single/double/escape state
`active_var_uses` keeps. Return True only for a `\n` that is outside both quotes. An
escaped `\n` outside quotes counts too, since that is the `\` continuation.

```python
    in_single = in_double = escaped = False
    for ch in command:
        if escaped:
            escaped = False
        elif ch == ESCAPE and not in_single:
            escaped = True
            continue
        elif ch == QUOTE_SINGLE and not in_double:
            in_single = not in_single
            continue
        elif ch == QUOTE_DOUBLE and not in_single:
            in_double = not in_double
            continue
        if ch == LINE_BREAK_NEWLINE and not (in_single or in_double):
            return True
    return False
```

**Assertion to add:** in `self/tests/allow-repo-commands.sh` `ASK_CASES`, add
`'git commit -m "subject\n\nbody"'` and `'gh pr create --title t --body "a\n\nb"'`, each
expecting `prompt`. `LINE_BREAK_REWRITE` keeps `"ls src \\\n tests"`, so the continuation
stays pinned. Update the `CONVENTIONS.md` / `hooks/README.md` table row to "a line break
outside a quote or a heredoc".

### 2. A brace inside double quotes is always denied as a "brace group the expansion refuses"

This one needs a design ruling.

**Where:** `brace_expansion_refused`.

**What's wrong:** it returns True for any word that holds a `{`/`}` and any quote or
backslash. Bash does no brace expansion inside quotes, so these are literals. Examples:

- `jq -r ".[] | {name}" data.json`
- `rg "fn main\(\) \{" src`
- `git show "stash@{0}"`

Each is now denied with "Expand it yourself", where it used to be a silent prompt. There
is nothing to expand, and the denial spends an escalation attempt. This contradicts the
function's own docstring and `NOTES.md` ruling 5 ("a brace bash itself leaves alone ... no
rewrite to name").

**Why it's a design decision and not a local fix:** the test deliberately asserts
`ls "{src,/etc}"` as `BRACE_REWRITE`, following the design table's "quotes mixed in".

**Proposed ruling:** a quote or backslash counts as "mixed in" only when the braces
themselves are unquoted. `cat {'/etc/passwd',x}` and `cat \{src,/etc/passwd\}` stay
REWRITE. A wholly double-quoted word is a literal and is ASK.

**Assertion:** `jq -r ".[] | {name}" data.json` and `git show "stash@{0}"` expect
`prompt`. `ls "{src,/etc}"` moves back to `BRACE_PROMPT`, with the move recorded in
`NOTES.md`.

A related false positive is accepted by design (ruling 6 skips only single-quoted words):
`grep -rn "../" src` is REWRITE for a `..` component. I am noting it, not escalating it.

## Files this pass touched

- `self/review-report.md` (this file). The attempted edit to
  `hooks/allow-repo-commands.sh` was refused and left nothing behind.
