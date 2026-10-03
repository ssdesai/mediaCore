# 03 — review: hook-rewrite-or-ask (round 3)

Round 2 (`review/complete/02-review-sonnet.md`, report in
`escalations/02-review-sonnet.md`) found the round-2 rework correct on every contract,
fixed three edge-case assertions and three drifted prose lines itself, and escalated two
doc lines under `hooks/` that its Edit rule refused: the module docstring of
`hooks/allow-repo-commands.sh` and the `allow-repo-commands.sh` entry in
`hooks/README.md`, both still saying a line break is refused "outside a heredoc" where the
rule is "outside a quote or a heredoc". The coordinator applied both by hand. This round
checks those two lines and nothing else: read `git diff <round-2 head>...HEAD`, where
the round-2 head is the commit `hook-rewrite-or-ask: review round 2`. "No findings" is a
legitimate verdict. Begin your report with the `Verdict:` line the prompt asks for.

## What the fix was supposed to do

Two prose lines, no code: the docstring's REWRITE list and the README entry each say
"a line break outside a quote or a heredoc". `LINE_BREAK_REWRITE_REASON` ("outside a
heredoc body") is deliberately left as it was — it is the message for a break that really
is unquoted, and round 2 ruled it accurate enough.

## The diff

Expect only: `hooks/allow-repo-commands.sh` (docstring lines), `hooks/README.md` (one
entry), and this feature's `README.md` fence (`plans` gains this stem), `timing.jsonl`,
this brief. If the manifest's `base` now says `main`, `origin/main` was merged in before
this round; that merge commit and the fence's `base` line are expected too. Anything else
that moved is a finding.

## Contracts to hold it to

- **No code moved.** The diff of `hooks/allow-repo-commands.sh` is docstring text only;
  `python3 -m py_compile hooks/allow-repo-commands.sh` passes.
- **The two lines say what the table rows say.**
- **Green.** `bash self/tests/allow-repo-commands.sh` and `bash self/tests/hook-escalation.sh`
  end with `all checks passed`; the gate report's VERDICT is `all checks passed`.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then whether the two lines are right, what you fixed, what you escalated, and the files
this pass touched.
