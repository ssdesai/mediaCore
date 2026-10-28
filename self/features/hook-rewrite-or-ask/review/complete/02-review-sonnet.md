# 02 — review: hook-rewrite-or-ask (round 2)

Round 1 (`review/complete/01-review-opus.md`, report in
`escalations/01-review-opus.md`) found the build sound on every contract — ALLOW did not
widen, DENY did not narrow, ASK prints nothing, the escalation counter behaves — and
escalated two false denials: a shape the hook sent back with a rewrite that cannot be
carried out. Both are quote-blindness in a raw-text reader, both were prompts before this
feature and must be prompts again. The coordinator ruled on each; the rework was briefed
from the escalation with those rulings. This round checks the rework and nothing else:
read `git diff <round-1 head>...HEAD`, where the round-1 head is the commit
`hook-rewrite-or-ask: review round 1`. "No findings" is a legitimate verdict. Begin your
report with the `Verdict:` line the prompt asks for. This feature edits `hooks/`; if the
Edit rule refuses you there, say so in the report and escalate the fix instead of
shelling a write around it.

## What the rework was supposed to do

1. **A line break inside a quoted argument is one argument, not a second command.**
   `carries_line_break` walks the text with the single/double/escape state the other
   readers keep and returns True only for a `\n` outside both quotes (an escaped `\n`
   outside quotes — the `\` continuation — still counts). `git commit -m "subject\n\nbody"`
   and `gh pr create --title t --body "a\n\nb"` are ASK (prompt); `ls src \\\n tests` is
   still REWRITE. The `CONVENTIONS.md` and `hooks/README.md` table row says "a line break
   outside a quote or a heredoc".
2. **A brace inside quotes is a literal.** The ruling: a quote or backslash counts as
   "mixed in" only when the braces themselves are unquoted. `brace_expansion_refused`
   returns False for a word whose every brace is inside quotes. `jq -r ".[] | {name}"
   data.json` and `git show "stash@{0}"` are ASK (prompt); `cat {'/etc/passwd',x}` and
   `cat \{src,/etc/passwd\}` are still REWRITE; `ls "{src,/etc}"` moves back to
   `BRACE_PROMPT`, and the move is recorded in `NOTES.md`. The design table row and the
   two docs tables say "a quote or backslash mixed into an unquoted brace group".

Accepted and not reworked: `grep -rn "../" src` is REWRITE for a `..` component (the
reviewer noted it; a pattern and a path are the same characters, and the single-quoted
spelling is a literal that passes).

## The diff

Expect only: `hooks/allow-repo-commands.sh` (the two functions and their docstrings),
`self/tests/allow-repo-commands.sh` (the new ASK cases, the moved brace case),
`self/tests/fixtures/hook-replay-2026-09-18.json` only if a record's verdict changed,
`CONVENTIONS.md` and `hooks/README.md` (the two table rows), `self/DESIGN-2026-09-18-hook-rewrite-or-ask.md`
only if the table row is corrected, `NOTES.md`, `CHECKPOINT.md`, `timing.jsonl`. Anything
else that moved is a finding.

## Contracts to hold it to

- **ALLOW did not widen.** `command_allowed` and everything it calls are not in the
  diff; no test case moved into an ALLOW group; every existing ALLOW and DENY case passes.
- **Only the two shapes narrowed, and only for quoted text.** Each new `prompt` case has
  its newline or its braces inside quotes; every unquoted spelling in the REWRITE groups
  still denies with its reason. Read both functions' quote walks against
  `active_var_uses`'s: same three states, same escape rule.
- **The docs match the code.** Both table rows, in both files, say what the functions do.
- **The moved case is listed** in `NOTES.md` with the ruling.
- **Green.** `allow-repo-commands.sh`, `hook-escalation.sh`, `hook-wiring.sh`,
  `policy-table.sh` and the gate all pass.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then whether the rework does what round 1 asked, what you fixed, what you escalated
(with the assertion that would catch it), and the files this pass touched.
