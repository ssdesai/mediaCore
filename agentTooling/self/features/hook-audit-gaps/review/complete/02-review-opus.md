# 02 — re-review: hook-audit-gaps, round 2

Written by the coordinator before the rework, from round 1's two escalations, not from the
builder's report. A security audit (`NN-audit-opus.md`) runs beside this review because the
diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 1 (`escalations/01-review-opus.md`, `escalations/01-audit-opus.md`) escalated four
bypasses of rules this feature states, in `hooks/allow-repo-commands.sh`. Round 2 fixes them
under one design rule, coordinator ruling 7 in the feature's `NOTES.md`:

> Wherever the hook must decide whether a stretch of text is hidden from the deny side (a
> comment, a heredoc body, a deleted continuation) and bash could read it differently, the deny
> side judges both readings and denies if either denies. It hides text only where the reading
> is certain. An over-deny on an exotic spelling is acceptable and documented; a prompt where
> bash runs a denied command is not.

- **Review item 1**: a bare `{` inside `${…}` no longer deepens the nesting in
  `comment_and_heredoc_free`; `echo ${x:-{} ; git push --force origin x # '` is denied.
- **E1**: inside a `$(…)`, a heredoc body line that begins with the delimiter and is not exactly
  the delimiter (`EOF )`, `EOF\t)`, `EOFS)`, `EOF x)`, `EOFxyz ; true)`, `EOF'q')`) no longer
  hides what follows: the git deny and the orchestrator role denial both fire on round 1's
  reproductions (audit batches c6, c7 and the orchestrator table).
- **E2**: a comment ending in a backslash does not swallow the next line for the build-script
  judge (`ls # x \⏎./run-plans.sh` and the listed variants are denied on the unreadable-ledger
  path).
- **E3**: a `#` right after `)` is not a comment (`a=(x)#b; ./run-plans.sh`,
  `a=(x)#b; git push -f origin y`, `echo $(echo a)#b; git push -f origin y` are denied).
- **Hardening**: the HEAD manifest probes behind `own_push_allowed` ignore replace refs.
- **Minor notes** from round 1's review: the `own_push_allowed` docstring, named constants for
  the bare `"<"` literals, the over-deny line for a quoted brace sequence past the cap.
- The build ran a differential check (hook verdict against what bash 5.2 ran, over round 1's
  tables and a generated corpus); NOTES.md summarises it. The harness is not committed.

Added after the build reported (the builder's choices, for you to judge, not to take on trust):

- E3 was closed by reading a doubtful `#` both ways, not by dropping `)` from
  `COMMENT_PREDECESSORS`: dropping it lost the deny on `git push --force origin y; (ls)# it's`.
  A `#` is certain only when no `(`, `[`, `{` or backtick is in the text kept before it; the
  combinations are capped (`MAX_COMMENT_DOUBTS`), and past a cap a line naming git is denied.
- One row of round 1's audit table moved from deny to prompt: `echo a \⏎#b ; git push -f origin y`.
  Bash deletes the continuation, starts a comment and runs no push (NOTES.md build ruling 37).
  Check that against bash before counting it a regression.
- A payload inside a quoted substitution still prompts, as on `origin/main`:
  `git commit -m "$(cat <<'EOF'⏎x⏎EOF git push -f origin y)"` is the same class as
  `echo "$(git push -f …)"`, recorded in NOTES.md and `self/BACKLOG.md`.
- The over-denies are listed in `hooks/README.md` → "What the both-readings rule over-denies".

Not in this round, and not an escalation when restated: the classes in NOTES.md → "Found, not
fixed" and `self/BACKLOG.md` (git behind a wrapper, abbreviated flags, names built at run time,
a quote nested in a backtick inside `"…"`, a line that does not tokenize). They are prompts,
never silent approvals, and the same on `origin/main`. Escalate a silent approval, a regression
against `origin/main`, or a bypass of a rule this feature states in a construct it touched.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 2 rework`.

## Contracts to hold it to

- A red row for each of the four findings, with round 1's exact reproductions, in
  `self/tests/allow-repo-commands.sh`, `self/tests/hook-cloud-profile.sh` or
  `self/tests/hook-orchestrator-role.sh`; all three pass.
- No existing assertion weakened or deleted; a row moved to a stricter verdict is named in
  NOTES.md.
- Everything round 1's audit lists under "What held" still holds.
- `hooks/README.md` no longer claims `EOF ` and `EOFS` are plain body lines without the
  qualification, lists the round's over-denies, and agrees with the code; `CONVENTIONS.md` →
  "Shell commands" agrees too.
- Named constants for every new literal.
- `.claude/settings.json` unchanged; `self/gate.sh` green.
- READMEs current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
