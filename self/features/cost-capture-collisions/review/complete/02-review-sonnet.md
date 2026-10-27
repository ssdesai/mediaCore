# 02 — review: cost-capture-collisions (round 2, scoped)

Written before the rework, from round 1's escalation
(`self/features/cost-capture-collisions/escalations/01-review-opus.md`), never from the
reworker's report. Read the code; do not take `NOTES.md` on trust. "No findings" is a
legitimate verdict. Fix local drift in this pass; anything structural is an escalation.
Begin your report with the `Verdict:` line the prompt asks for.

## What the rework was supposed to do

Round 1 judged §4, §6 and the sole-claimant cut sound on their main paths and escalated
one defect in `analysis/capture_planning.py`'s fallbacks:

1. **A pinned coordinator found outside this repo's directories loses its pinned
   delegates.** `runner_only_ids` was computed, and the pinned-delegate fallback
   (`find_pinned_anywhere`) run, before the pinned-session fallback loop — the only place
   a session reached through `find_session_elsewhere` can be found collided — so a
   delegate whose parent is such a collided coordinator was skipped as a runner's.
2. **The fallback never consulted the spawning tree.** A pinned delegate the fallback
   reaches under a collided parent was priced even when the runner tree spawned it — a
   double count with the usage.json, with no warning.

The fix should judge a fallback hit's parent from that parent's own transcript (the
collision test and the spawning-tree attribution the main walk already uses), or run the
session fallback first and carry its results forward — the reworker's call, recorded in
`NOTES.md`.

## The diff

Read `git diff <round 1 head>..HEAD`, where round 1's head is the `head=` on the
round-1 `plan_end` line in `self/features/cost-capture-collisions/timing.jsonl` (the
`cost-capture-collisions: review round 1` commit). Expect `analysis/capture_planning.py`,
`self/tests/subagent-capture.sh`, `self/tests/README.md`, possibly `analysis/README.md`,
and this feature's `NOTES.md` / `CHECKPOINT.md` / manifest. **No other feature's
directory under `self/features/` may change.** Anything else that moved is a finding.

## Contracts to hold it to

- **The assertions round 1 named exist, in `subagent-capture.sh`, and would fail on
  round 1's code:** a pinned coordinator whose collided transcript is filed under a second
  project directory, with a pinned implementer under it, prices the implementer; in the
  same fixture a pinned delegate whose `meta.json` `toolUseId` points into the runner tree
  is not priced, and the capture warns that the pin is ignored.
- **Nothing round 1 judged sound regressed:** every existing check in the touched tests
  unchanged; a genuine runner session's delegates still never priced; a usage.json id
  with no recognisable runner tree still excluded exactly as before.
- **The gate passes**: run `./self/gate.sh` and report its verdict line, and
  `bash self/tests/subagent-capture.sh` on its own.
- **READMEs** describe the fallback order or rule as built.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the rework was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
