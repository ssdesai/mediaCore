# 06 — re-review: hook-audit-gaps, round 6

Written by the coordinator before the rework, from round 5's audit escalation, not from the
builder's report. A security audit (`NN-audit-opus.md`) runs beside this review because the
diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 5's review was clean (`review/complete/05-review-opus.md`). Its audit
(`escalations/05-audit-opus.md`) escalated B1: a destructive git command on line 1, then a
later line whose quote never closes and whose raw text holds `<<` or `#`
(`git push -f origin y⏎echo '#`, `git push -f origin y⏎echo "$(cat <<EOF`,
`git push -f origin y⏎gh pr create --body "$(cat <<'EOF'⏎x`, `git push -f origin y⏎echo '<<`),
got a prompt while bash (and `eval`) runs line 1 before the parse error. The same held for
`git push origin main`, `git reset --hard`, `git clean -fdx`, `git branch -D y` and
`git stash drop` on line 1. `origin/main` prompts too; it was recorded in `self/BACKLOG.md`;
but this feature's own `hooks/README.md` sentence says such a line is denied.

The owner chose a coarse rule: **a line that does not tokenize and names git is denied**, as
a git command that cannot be read (the same answer the doubt, brace and torn-reading caps
give), whatever `<<` or `#` it holds. A line that does not tokenize and names no git keeps
the tokenize rewrite deny or the prompt it has today. Every B1 reproduction and its listed
variants is denied; `hooks/README.md` and `self/BACKLOG.md` say so and agree with the code;
the round-5 review's suggested test row is added.

Added after the build reported (the builder's choices and the coordinator's rulings on them,
for you to check against the code, not to take on trust):

- One test at the return of `judged_texts`: when no reading lexes under `chain_tokens` and the
  line names git, it takes the `unread()` git deny. An ANSI-C reading held back by
  `never_judged` counts as lexing (`git commit -m $'it\'s'` stays a prompt). NOTES.md rulings
  64–69. Using `chain_tokens` also closes BACKLOG's other half (an unplaced heredoc body
  with an odd quote on a git line).
- **"Does not tokenize" means for the hook.** A line where some reading the hook builds lexes
  is outside this rule even if bash refuses it: `(ls) # it's⏎git push …⏎cat <<EOF⏎echo '`
  (a comment-in-doubt kept as text) and `echo "x$(cat <<"E'F"⏎…⏎E'F )" ; git push …`
  (text before `$(`, the BACKLOG scope class). Both prompt on `origin/main` too and are
  recorded in NOTES "Found, not fixed (round 6)". Not escalations.
- **Ruled acceptable:** two reason assertions moved stricter (`git rebase 'main` now carries the
  git deny's reason and does not decay; ruling 67); the "seventh is the plainest" README
  example is superseded by a named sentence in the round-6 paragraph rather than edited in
  place, to stay within the approval-prompt limit.

## How to judge this round

Six rounds have each found a new spelling of one family. This round closes the last
recorded escape the owner chose to close. Judge it on whether B1 is closed as stated, and
whether the round broke anything that held. **Escalate:** a silent approval; a regression
against `origin/main` or round 5; a line naming git that does not tokenize and is still not
denied. **Do not escalate** (record under "Not counted"): a new spelling that is a prompt on
`origin/main` too and falls in a class already recorded (NOTES.md "Found, not fixed",
`self/BACKLOG.md`, `hooks/README.md` "What still reaches a prompt", the ANSI-C class, the
quoted-substitution class, git behind a wrapper or env prefix, a name built at run time), or
one that needs a construct this feature never touched. Those are BACKLOG items, and the
owner has said this feature should close.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 6 rework`.

## Contracts to hold it to

- A row for each B1 reproduction and variant in `self/tests/allow-repo-commands.sh` (both
  profiles) and `self/tests/hook-cloud-profile.sh`; all hook test files pass.
- The usual `git commit -m "$(cat <<'EOF'⏎…⏎EOF⏎)"` message and PR body stay where they
  were.
- No existing assertion weakened or deleted; a row moved to a stricter verdict is named in
  NOTES.md.
- Everything rounds 1–5's audits list under "What held" still holds.
- `hooks/README.md` and `self/BACKLOG.md` agree with the code.
- Named constants for every new literal (beside its user is accepted).
- `.claude/settings.json` unchanged; `self/gate.sh` green.
- READMEs current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
