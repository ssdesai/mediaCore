# 03 — re-review: hook-audit-gaps, round 3

Written by the coordinator before the rework, from round 2's two escalations, not from the
builder's report. A security audit (`NN-audit-opus.md`) runs beside this review because the
diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 2 (`escalations/02-review-opus.md`, `escalations/02-audit-opus.md`) escalated one class
in `hooks/allow-repo-commands.sh`: the walk compares **raw** text where bash first deletes a
backslash-newline (`\⏎`), so a construct split by a continuation hides a command from the
deny side. None is a regression against `origin/main`; each breaks coordinator ruling 7 in
`NOTES.md` (judge both readings, deny if either denies). Round 3 closes the class, not the
spellings:

- **R2-1 / review item 1**: in a heredoc with an **unquoted** delimiter, bash joins `\⏎` in
  the body before looking for the terminator. `cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF`,
  `cat <<EOF⏎x⏎EOF\⏎⏎git push …⏎EOF`, the `<<-` form with `⇥EO\⏎F`, `E\⏎O\⏎F`, and the
  `echo "$(cat <<EOF⏎EO\⏎F⏎git push …⏎EOF⏎)"` form are denied. The quoted-delimiter twin
  (`cat <<'EOF'⏎EO\⏎F⏎git push …⏎EOF`, where bash runs no push) is a test row too, at
  whatever verdict the build chose and recorded.
- **R2-2**: a substitution opener split by a continuation (`<\⏎(`, and the `$\⏎(`, `>\⏎(`
  and arithmetic twins, which other paths deny today by luck) is found where bash finds it.
  The audit's rows cs3/ps1, ps5, ps6 and ps7 are denied.
- **R2-3**: `uses_own_assignment` looks for the use in every reading `judged_texts`
  returns, not only the first: `a=(x)#b; X=/p; cat $X/f` is denied.

The coordinator's direction to the build was a reading, not a patch per spelling: the deny
side also judges the command as bash sees it after every `\⏎` it would delete is deleted
(or an equivalent that closes the class), and only ever adds denies. The build records the
choice and any over-deny it brings in `NOTES.md` and `hooks/README.md` → "What the
both-readings rule over-denies".

Added after the build reported (the builder's choices, for you to judge, not to take on trust):

- The build did not add one all-joined reading: it reports that one misses
  `cat <<EOF⏎EO\⏎F⏎ls # x \⏎git push -f origin y⏎EOF`. Instead the walk deletes `\⏎` ahead of
  every look-ahead, `heredoc_body_span` joins an unquoted delimiter's body (`joins=`), and a
  line holding both a heredoc and a continuation gets two more body readings. Backticks halve
  backslash runs. NOTES.md rulings 39–48.
- Nineteen generated lines moved from deny to prompt (NOTES.md ruling 47): a quoted
  delimiter split by one continuation, where round 2 denied by accident. The build reports
  bash runs no denied command on any; check that against bash.
- `echo "$(cat <<EOF⏎EO\⏎F⏎git push …⏎EOF⏎)"` was the quoted-substitution class; the build
  closed it narrowly (a `"$(cat <<` head not stood in is read closed and opened). Judge that
  it touches no other `"$(…)"` and that the usual `<<'EOF'` commit message still passes.
- The over-denies it brings are in `hooks/README.md`.

Not in this round, and not an escalation when restated: the classes in NOTES.md → "Found, not
fixed" and `self/BACKLOG.md` (git behind a wrapper, abbreviated flags, names built at run time,
a quote nested in a backtick inside `"…"`, a payload inside a quoted substitution, a line that
does not tokenize), the chained-`cd` deny reading only the first walk (documented), and
round 2's audit list "Not counted as bypasses". They are prompts, never silent approvals, and
the same on `origin/main`. Escalate a silent approval, a regression against `origin/main`, or a
bypass of a rule this feature states in a construct it touched.

Round 2's audit did not finish its attack on the cloud own push (the manifest read at `HEAD`,
replace refs ignored); attack it this round.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 3 rework`.

## Contracts to hold it to

- A red row for each of round 2's reproductions, in `self/tests/allow-repo-commands.sh`,
  `self/tests/hook-cloud-profile.sh` or `self/tests/hook-orchestrator-role.sh`; all pass.
- No existing assertion weakened or deleted; a row moved to a stricter verdict is named in
  NOTES.md.
- Everything round 1's and round 2's audits list under "What held" still holds.
- `hooks/README.md` ("Where a heredoc's body ends", the continuation sentence, the over-deny
  list) and `CONVENTIONS.md` → "Shell commands" agree with the code.
- Named constants for every new literal.
- `.claude/settings.json` unchanged; `self/gate.sh` green.
- READMEs current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
