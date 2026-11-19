# 04 — re-review: hook-audit-gaps, round 4

Written by the coordinator before the rework, from round 3's audit escalation, not from the
builder's report. A security audit (`NN-audit-opus.md`) runs beside this review because the
diff touches `hooks/`. "No findings" is a legitimate verdict.

## What the round was supposed to do

Round 3's review was clean (`review/complete/03-review-opus.md`). Its audit
(`escalations/03-audit-opus.md`) escalated one narrow class in
`hooks/allow-repo-commands.sh`, and the owner chose a small round 4 to close it:

- **R3-1**: a reading the walk builds (bash's run-on placement of a heredoc inside
  `"$(cat <<…)"`, or ruling 45's opened head) that then fails to tokenize was dropped
  quietly, so the git, `cd` and assignment denies were lost to a prompt while bash ran the
  command. Fixed coarsely: a built reading that does not tokenize is never dropped — the line
  is denied, as unreadable when it names git (as the doubt cap and brace cap do) or with the
  tokenize rewrite deny. The audit's rows w1, w2, o13p, w11, w12, w8, w9, x3, x4, x8,
  o13s/o13t/o13v, o13u, w10 and w14 are denied; its controls w4, x1, x5, x7 stay denied.
- **R3-2**: ruling 45's opened reading matches its head with any whitespace bash allows
  after `$(` and around `cat`/`<<` (and the continuation-joined text): o3 and o3p are
  denied. `"x$(cat <<…"` (o9) stays the documented class.

Added after the build reported (the builder's choices and the coordinator's rulings on them,
for you to check against the code, not to take on trust):

- The loss was in the walk, not a tokenizer `try/except`: a line whose quotes never close
  now comes back as a `TornReading`, and `torn_reading` / `tears_a_reading` are the one
  helper `judged_texts` and `does_not_tokenize` ask. NOTES.md rulings 49–56.
- **Ruled acceptable:** w10 and w14 take the tokenize rewrite deny (which decays to an ask
  after two), not the cd-chain and own-assignment reasons. The brief allowed either; check
  they are denied, not which reason they give.
- **Ruled not an escalation:** a built reading whose quotes close but which holds an ANSI-C
  `$'…\'…'` is still dropped by `never_judged` (e.g. `… ; git push -f origin y ; echo $'\'' "`).
  That is the recorded ANSI-C class (NOTES, `self/BACKLOG.md`), the same on `origin/main`.
- **Ruled acceptable:** the new names (`TornReading`, `torn_reading`, `tears_a_reading`,
  `CONTINUATIONS_PATTERN`, `HEREDOC_OPENED_HEAD_RE`) are named but sit beside `judged_texts`,
  not in the top-of-file block, to keep the hooks/ approval prompts to three (NOTES ruling
  54). A literal with no name is still a finding; a named constant's position is not.
- New over-deny: a heredoc body line that begins with its own delimiter word followed by an
  odd quote (`git commit -m "$(cat <<'EOF'⏎EOF notes⏎it's fine⏎EOF⏎)"`) is denied; listed in
  `hooks/README.md`. The usual message shape did not move.

Not in this round, and not an escalation when restated: the classes in NOTES.md → "Found, not
fixed" and `self/BACKLOG.md`, round 3's audit "Not counted" list, and round 3's review's two
minor observations (a quote after the heredoc body inside `"$(…)"` — the quoted-substitution
class; the own-assignment check naming a wrong reason). They are prompts, never silent
approvals, and the same on `origin/main`. Escalate a silent approval, a regression against
`origin/main`, or a bypass of a rule this feature states in a construct it touched — in
particular a built reading that is still dropped without a deny.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round's own change is the commit `hook-audit-gaps: round 4 rework`.

## Contracts to hold it to

- A row for each of round 3's audit reproductions and controls above, in
  `self/tests/allow-repo-commands.sh` (both profiles) and `self/tests/hook-cloud-profile.sh`;
  all hook test files pass.
- The usual `git commit -m "$(cat <<'EOF'⏎…⏎EOF⏎)"` message, with apostrophes and quotes in
  its body, is still approved where it was.
- No existing assertion weakened or deleted; a row moved to a stricter verdict is named in
  NOTES.md.
- Everything rounds 1–3's audits list under "What held" still holds.
- `hooks/README.md` (the over-deny list, the opened-reading sentence), `CONVENTIONS.md` →
  "Shell commands" and `self/BACKLOG.md` agree with the code.
- Named constants for every new literal.
- `.claude/settings.json` unchanged; `self/gate.sh` green.
- READMEs current for every folder touched.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
