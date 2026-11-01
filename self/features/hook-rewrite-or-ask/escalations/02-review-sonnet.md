Verdict: escalated

# Review — hook-rewrite-or-ask (round 2, sonnet)

Diff read: `git diff 15eca93...HEAD` (round 1's head, `hook-rewrite-or-ask: review round 1`).
Gate report `level: final`: every check `exit: 0`, none SKIPPED, including
`allow-repo-commands`, `hook-escalation`, `hook-wiring` and `policy-table`.

## What the rework was supposed to do

Round 1 found two false denials, both quote-blindness in a raw-text reader: a line break
inside a quoted argument (`git commit -m "subject\n\nbody"`) and a brace inside quotes
(`jq -r ".[] | {name}" data.json`, `git show "stash@{0}"`). Each had been a prompt before
this feature and was denied with a rewrite that cannot be carried out. This round was to
make both prompts again, and only for quoted text.

## Does it?

Yes, on every contract in the brief.

- **ALLOW did not widen, by construction.** `carries_line_break` and
  `brace_expansion_refused` are called only from `rewrite_reason_lines`, which
  `command_verdict` reaches only after `command_allowed` has declined
  (`hooks/allow-repo-commands.sh:1437-1455`). Neither function can turn a refusal into an
  approval; the most they can do is turn a REWRITE into an ASK. `command_allowed`,
  `braces_simple` and everything they call are not in the diff. No test case moved into an
  ALLOW group.
- **Only the two shapes narrowed, and only for quoted text.** Both new walks
  (`carries_line_break`, `brace_outside_quotes`) keep the same three states and the same
  escape rule as `active_var_uses` and `raw_words`: a backslash outside single quotes
  escapes the next character and skips the quote toggles; a quote toggles only when the
  other is not open. An escaped `\n` outside both quotes still counts (the `\`
  continuation), and an escaped brace outside both quotes still counts as unquoted, so
  `cat \{src,/etc/passwd\}` and `cat {'/etc/passwd',x}` still refuse, as ruled. Each new
  `prompt` case has its newline or its braces inside quotes; every unquoted spelling in
  the REWRITE groups still denies with its reason.
- **The docs match the code — in the two table rows.** `CONVENTIONS.md`,
  `hooks/README.md`, and the design's table all say "a line break outside a quote or a
  heredoc" and "a quote or backslash mixed into an unquoted brace group".
- **The moved case is listed.** `NOTES.md` ruling 13 records `ls "{src,/etc}"` moving back
  to `BRACE_PROMPT` with the coordinator's ruling and why, and the "Every moved case"
  section is corrected to match.
- **Scope of the diff** is what the brief expected: the hook, the tests, the two docs
  tables, the design table, `NOTES.md`, `CHECKPOINT.md`, the feature README's manifest
  block and `timing.jsonl`. The replay fixture did not move, and no record's verdict
  changed.

## Fixed in this pass

- **Test coverage for the two walks' edges** (`self/tests/allow-repo-commands.sh`). Three
  cases pin invariants the batch's own cases left unasserted, so a simplification of
  either walk could not have gone red:
  - `git commit -m "a\nb"\nls` in `LINE_BREAK_REWRITE`: a quoted newline does not excuse
    an unquoted one after the closing quote (the walk resets its state).
  - `git commit -m 'subject\n\nbody'` in `ASK_CASES`: the single-quote state, which the
    double-quoted cases do not exercise.
  - `cat "{a}"{b,c}` in `BRACE_REWRITE`: the test is "every brace is inside a quote", not
    "some brace is" — a quoted brace beside a bare group must still refuse.
  I ran `self/tests/allow-repo-commands.sh` once after adding them (all checks passed);
  that was to check my own edit, not to redo the verify pass.
- **Drifted prose** naming the line-break rule as "outside a heredoc" (it is now "outside a
  quote or a heredoc") and the brace rule as "a quote or backslash mixed in":
  `README.md` (the `hooks/` row), `self/tests/README.md` (the `allow-repo-commands.sh`
  entry, which now also names the quoted-brace and quoted-newline ASKs), and in
  `self/tests/allow-repo-commands.sh` the header comment and the group label at the
  rewrite-shape loop.

## Escalated to the next round

Two doc lines under `hooks/`, which the Edit rule refused this pass ("requested
permissions to write … you haven't granted it yet"); I did not shell a write around it.
Both are the same drift the fixed lines above had — a prose summary that still says a line
break is refused "outside a heredoc" — so a reader of either would conclude
`git commit -m "a\nb"` is a REWRITE, which it no longer is. They are documentation only:
no code, no test and no design decision moves, so they can be applied by hand in an
attended session without a build pass.

1. `hooks/allow-repo-commands.sh:19-20`, the module docstring's REWRITE list. Change
   `a line break outside a` / `heredoc, or a sequence mixing …` to
   `a line break outside a quote` / `or a heredoc, or a sequence mixing …`.
2. `hooks/README.md:25-26`, the `allow-repo-commands.sh` entry. Change
   `a line` / `break outside a heredoc, and a sequence …` to
   `a line` / `break outside a quote or a heredoc, and a sequence …`.

No test can catch prose drift; nothing mechanical asserts these two lines, which is why
they drifted while the table rows were corrected.

Not escalated, on purpose: `LINE_BREAK_REWRITE_REASON` still says "outside a heredoc
body". It is the message to the model for a break that really is unquoted, so it is not
wrong, only less exact than the table row; no test or fixture pins the phrase.

## Files this pass touched

`self/review-report.md`, `README.md`, `self/tests/README.md`,
`self/tests/allow-repo-commands.sh`.
