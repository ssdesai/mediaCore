# 05 — re-review: hook-audit-gaps, round 5

Written by the coordinator before the rework, from round 4's audit escalation, not from the
builder's report. A security audit (`NN-audit-opus.md`) runs beside this review because the
diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 4's review was clean (`review/complete/04-review-opus.md`). Its audit
(`escalations/04-audit-opus.md`) escalated one case, R4-1: inside a whole-argument
`"$(cat <<…)"` head, the opened reading covers only a delimiter that is a bare or fully
quoted identifier (`HEREDOC_ARGUMENT_HEAD_RE`). A partly quoted delimiter (`E'O'F`,
`E"O"F`, `'E'OF`, `E\OF`, …), an empty one (`''`, `""`, `-''`) or a non-identifier one
(`E-F`, `123`, `'E O F'`, `'E)F'`, …) left the line read as one quoted word, so a command
after `)"` was judged by nothing while bash ran it.

The owner chose a coarse fix: such a head is not read for a message at all. A `"$(cat <<`
head (in every spelling round 4's `HEREDOC_OPENED_HEAD_RE` matches) whose delimiter is not a
bare or fully quoted identifier is treated as a torn reading (round 4's `torn_reading`): the
git deny when the line names git, the tokenize rewrite deny otherwise. Commit messages never
use such a delimiter. Every row in the audit's R4-1 table (p2–p8, p13, e5, e6, e8, e9, e11,
e12, e14, c5, c6, c8, c10, c12, c13, c22) and their rN twins is denied; q5 and c1 stay
denied; the usual `git commit -m "$(cat <<'EOF'⏎…⏎EOF⏎)"` message and PR body stay where
they were.

Added after the build reported (the builder's choices and the coordinator's rulings on them,
for you to check against the code, not to take on trust):

- `unread_head` (with `HEREDOC_HEAD_WORD_RE`) is asked of every reading in `judged_texts` and
  feeds round 4's `torn` path; the delimiter word is cut at the next blank or operator, not
  parsed. NOTES.md rulings 57–63.
- **Ruled acceptable:** a message under a backslash-quoted delimiter
  (`git commit -m "$(cat <<\EOF…`) moved from prompt to deny (ruling 61), as do two lines
  naming the head's text inside single quotes on a git line (`git log --grep '"$(cat <<' -1`).
  Documented over-denies, not findings.
- **Ruled not an escalation:** an odd delimiter behind a head the opened reading does not
  match (`"x$(cat <<`, `"$$$(cat <<`, `"$(cat - <<`) stays one quoted word — the recorded
  BACKLOG scope entry; and a no-git line's tokenize deny names an open quote it lacks.

## How to judge this round

Five rounds have now each found a new spelling of the same family: a construct inside a
heredoc or quoted substitution that the hook reads differently from bash. The rounds have
closed each one coarsely. Judge this round on:

- whether R4-1 is closed as stated, and
- whether the round broke anything that held.

**Escalate:**

- a silent approval;
- a regression against `origin/main` or against round 4;
- a construct this feature touched that still hides a command behind a delimiter spelling the
  fix was meant to cover.

**Do not escalate (record it under "Not counted" instead):**

- a new spelling that is a prompt on `origin/main` too and falls in a class already
  recorded (NOTES.md "Found, not fixed", `self/BACKLOG.md`, `hooks/README.md` "What still
  reaches a prompt", the ANSI-C class, the quoted-substitution class);
- a spelling that needs a construct this feature never touched.

Those are BACKLOG items, and the owner has said this feature should close.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 5 rework`.

## Contracts to hold it to

- A row for each R4-1 reproduction above, plus rows pinning round 4's two documented
  over-denies (round 4 review's optional note), in `self/tests/allow-repo-commands.sh` (both
  profiles) and `self/tests/hook-cloud-profile.sh`; all hook test files pass.
- No existing assertion weakened or deleted; a row moved to a stricter verdict is named in
  NOTES.md.
- Everything rounds 1–4's audits list under "What held" still holds.
- `hooks/README.md` (over-deny list, the opened-reading rule) and `self/BACKLOG.md` agree
  with the code.
- Named constants for every new literal (a name placed beside its user, as in round 4, is
  accepted).
- `.claude/settings.json` unchanged; `self/gate.sh` green.
- READMEs current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
