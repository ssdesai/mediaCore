# 01 — review: hook-rewrite-or-ask

Written before the build, from the manifest
(`self/features/hook-rewrite-or-ask/README.md`) and the design
(`self/DESIGN-2026-09-18-hook-rewrite-or-ask.md`), never from the implementer's
report. "No findings" is a legitimate verdict. Fix local drift in this pass; anything
structural is an escalation, and an escalated report is round 2's brief. Begin your
report with the `Verdict:` line the prompt asks for. This feature edits `hooks/`; if the
Edit rule refuses you there, say so in the report and escalate the fix instead of
shelling a write around it.

This hook is the safety boundary. Read the diff as an adversary first: the one finding
that matters more than any other is a command that was a prompt or a deny before and is
an approval after. Nothing in this feature is allowed to widen ALLOW.

## What the feature was supposed to do

The permission hook's approval analysis returns a verdict instead of a bool. The
manifest's `base` says which branch to diff against (`minutes-slug-and-quoting`, or
`main` if the close has retargeted it); the diff to read is `git diff <base>...HEAD`.

0. **The quote walk** (S0). `unquoted_index` tracks both quotes, so `cat "'"$(pwd)/x`
   is a substitution in a path.
1. **Three verdicts** (S1). REWRITE (unreadable, a rewrite exists → deny with the
   rewrite, through the existing escalation), ASK (read, a write or an unknown program →
   print nothing), ALLOW. Line precedence any-REWRITE > any-ASK > ALLOW. The three older
   denies run first, unchanged.
2. **The rewritable shapes** (S2). `$NAME` in a word, `~`, a refused brace group, a `..`
   path component, a lone relative or bare `cd`, a line break or `\` continuation — each
   with a named reason. `UNANALYSABLE` gone; CR/NUL are ASK; `main...HEAD` is ASK.
3. **One write per call** (S3). A mixed approved+ASK sequence is REWRITE naming which
   members to run alone; an all-ASK sequence is one ASK; a pipeline is never split.
4. **The reason names the member** (S4), and `hook-escalation.sh` covers the new shapes.
5. **The guidelines** (S5). `CONVENTIONS.md` § Shell commands around the three outcomes,
   with the one-write-per-call rule; `hooks/README.md` "The three outcomes".
6. **The replay fixture** (S6). 24 commands, expected verdicts, replayed by the test.

Not in this feature: an explicit `ask` with a reason; approving any new program; a
rewrite for a whole-argument `$(…)`; anything `minutes-slug-and-quoting` S5 changed.

## The diff

Expect: `hooks/allow-repo-commands.sh`, `hooks/README.md`, `CONVENTIONS.md`,
`AGENT_DIRECT.md` and `RUNNER.md` (pointers only, if at all),
`self/tests/allow-repo-commands.sh`, `self/tests/hook-escalation.sh`, a new file under
`self/tests/fixtures/`, `self/tests/README.md`, `self/README.md` (the design row),
`self/BACKLOG.md` if an entry closes, and this feature's `NOTES.md`/`CHECKPOINT.md`/
`timing.jsonl`. `hooks/policy.py`, `.claude/settings.json` and `wire-settings.py` must
NOT move: no verdict here has a prefix-rule twin. Anything else that moved needs a ruling
in `NOTES.md` or is a finding.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **ALLOW did not widen.** Every case in every existing ALLOW group still passes, and no
  case anywhere moved *into* an ALLOW group. Run the whole test file and read the diff of
  the test file for any ALLOW-group edit; either is a finding, an escalation if it is a
  new approval.
- **DENY did not narrow.** Every existing DENY case still denies. A NOT_DENIED case may
  move only into a REWRITE group, only when its shape is in the design's table, and every
  move is listed in `NOTES.md`; a NOT_DENIED case that vanished, or that now denies with
  no listed reason, is a finding.
- **REWRITE is denied with the rewrite.** Each shape in the table is denied with a
  reason containing the shape's phrase and the member's own text: `grep x $FILE`,
  `ls ~/x`, `cat {a,{b,c}}`, `cat ../x`, `cd src`, a two-line command,
  `grep x f && git commit -m m` (reason names `grep x f` as approved and
  `git commit -m m` to run alone), `cat "'"$(pwd)/x`. The seven older opaque shapes
  keep their reasons.
- **ASK prints nothing.** `git diff main...HEAD`, `x=$(cd dir && pwd)`,
  `git add x && git commit -m m`, `./run-review.sh --self x 2>&1 | tail -25`, `X=1 make`,
  `echo x > f`, `cat /etc/hosts` — empty stdout, no JSON. No `ask` decision is emitted
  for this class.
- **Precedence.** A line with one REWRITE member and one ASK member is REWRITE; a
  pipeline is judged whole and never split; `ls src | python3` and `python3 -c 'x'` are
  still denied; `cat 'x` still names the quote.
- **Escalation.** A new-shape deny advances the per-session counter; an ASK resets it;
  the third unreadable command in a session is `ask`; under `AGENTTOOLING_HEADLESS` it
  prints nothing. `hook-escalation.sh` asserts each.
- **The replay.** The fixture holds 24 records with the design's counts (5 approved, the
  rest REWRITE or ASK as the table says), and the test replays every one.
- **The guidelines.** `CONVENTIONS.md` § Shell commands reads in the order approved /
  sent back / reaches the human, states one write per Bash call with reads in their own
  calls, `cd <abs>` over `git -C <other tree>`, and the four tools over `sed -n`, `cp`,
  `cat >`; § Writing files names `cp`. `hooks/README.md` has "The three outcomes" with the
  table and no longer has separate "What it denies" / "What it approves" / "The opaque
  shape" sections; § Escalation remains. No rule in either contradicts the code.
- **Style.** Named constants for every verdict, reason and length; Python stdlib only;
  bash 3.2 in the tests; no chained `cd`; every file authored with Edit/Write.
- **Exclusions named.** Every deviation from the manifest or design has a ruling in
  `NOTES.md`; `hook-wiring.sh` and `policy-table.sh` pass untouched.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
