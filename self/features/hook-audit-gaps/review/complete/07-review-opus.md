# 07 — re-review: hook-audit-gaps, round 7

Written by the coordinator before the rework, from round 6's review and audit escalations,
not from the builder's report. A security audit (`NN-audit-opus.md`) runs beside this review
because the diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 6 added one test at the return of `judged_texts`: a line where no reading lexes and
that names git gets the unreadable-git deny. Both of round 6's reports escalated it:

- **The review** (`escalations/06-review-opus.md`): valid bash such as
  `git commit -m "$(echo "it's")"`, `git commit -m "$(echo "it's #1")"` and
  `git commit -m "$(printf "%s" "don't")"` became hard git denies. Also,
  `hooks/README.md` said "NOT one: anything bash tokenizes", which is false.
- **The audit** (`escalations/06-audit-opus.md`, B1): the ANSI-C excuse let through
  `git push -f origin y⏎echo $'\'' "` and its variants as a prompt, though bash runs line 1.

The owner chose this fix: round 6's deny also requires that `bash -n` refuses the line, and
the ANSI-C excuse no longer applies when bash refuses it. A line bash accepts goes back to its
round-5 verdict. The bash call must:

- send the text on stdin, never via `-c` or a file;
- run with `--norc --noprofile` and an emptied environment with a fixed PATH;
- have a named timeout;
- fail closed, so a missing bash, an error, a timeout or any output counts as refused;
- only ever add denies, never approve;
- run only when round 6's condition already holds.

Added after the build reported (the builder's choices, for you to check against the code,
not to take on trust):

- `bash_refuses` and five constants (`BASH_SYNTAX_*`, `BASH_UNREADABLE_CHAR`,
  `BASH_REFUSALS`). The condition is that no reading is *judged*: `chain_tokens` is None, or
  `never_judged` holds the reading back. This is broader than "no reading lexes", because
  shlex lexes `git push -f origin y⏎echo $'\'' '` by pairing its quotes wrongly. See NOTES.md
  rulings 70–75.
- An unterminated heredoc makes bash exit 0 with a warning. Any output counts as refused.
- **Accepted over-denies:** an extglob line next to an ANSI-C quote; the other four classes
  the builder listed. A one-line `git push -f origin y; echo $'\'' "` is denied even though
  bash runs nothing.
- **Accepted, left open (BACKLOG):**
  - Valid bash that no reader judges gets a prompt (round 6 denied it; the owner gave that
    back).
  - About 1,320 bash-refused lines where one reading *is* judged are not sent to bash. They
    prompt, as they do on round 5 and on `origin/main`.
  - The bash asked is the system's, not the session's shell.
  - One sentence in "The git shape" still says an unlexable line is "refused whole".

## How to judge this round

This is the last round the owner will run for this feature. Judge it on two things: whether
the two round-6 escalations are closed as stated, and whether the subprocess call is safe.

**Escalate:**
- a silent approval;
- a regression against `origin/main` or round 5;
- any way the `bash -n` call executes code, reads inherited state, or turns a deny into a
  prompt or an approval;
- a line from either round-6 escalation that still has the wrong verdict.

**Do not escalate** (record under "Not counted"): a new spelling that is a prompt on
`origin/main` too and falls in a class already recorded. The recorded classes are:
- NOTES.md "Found, not fixed";
- `self/BACKLOG.md`, including the leftovers above;
- `hooks/README.md` "What still reaches a prompt";
- the ANSI-C class and the quoted-substitution class;
- git behind a wrapper or env prefix;
- a name built at run time.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Use the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 7 rework`
(`ced8e00`).

## Contracts to hold it to

- **Tests.**
  - Each line from the round-6 review is back at its round-5 verdict. Each B1 line and
    variant from the round-6 audit is a git deny in both profiles.
  - `git commit -m $'it\'s'` and `git push -f origin y⏎echo $'\''` stay prompts.
  - The fail-closed cases are pinned in `self/tests/hook-cloud-profile.sh` H20.
  - All hook test files pass.
- **Messages.** The usual `git commit -m "$(cat <<'EOF'⏎…⏎EOF⏎)"` message and PR body keep
  their earlier verdicts.
- **No weakening.** No existing assertion is weakened or deleted. A row moved to a stricter
  verdict is named in NOTES.md.
- **Docs.** `hooks/README.md` and `self/BACKLOG.md` agree with the code, apart from the one
  stale sentence named above.
- **Constants.** Every new literal is a named constant.
- **Settings and gate.** `.claude/settings.json` is unchanged, and `self/gate.sh` is green.
- **READMEs.** The README is current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
