# 02 — review: self-cloud-bootstrap (round 2: the merge of main)

## What the feature was supposed to do

Round 1's review (`review/complete/01-review-opus.md`) judged the feature clean at
`0ab64b6`: agentTooling's whole `--self` policy in a tracked, generated
`.claude/settings.json` with a guarded hook command (`NOTES.md` → "The open question
(live)"). Since then `main` gained `session-start-precision` (#83, `c8e36ad`), which
touched the same files, and the branch merged it (`e57a8f6`). This round judges **the
merge only**: that both features' behaviour survived and that the combined tree is
coherent.

## The diff

Base is `main`. Read `git show --stat e57a8f6` and `git diff 0ab64b6 e57a8f6` (what the
merge changed on this branch), and `git show c8e36ad --stat` (what #83 brought). Read
`NOTES.md` → "Rulings" for the merge ruling, but judge against this brief.

## Contracts to hold it to

- #83's behaviour is intact: `manifest.py session-start` truncates to the millisecond;
  `set-window-from` is unchanged; `self/gate.sh`'s settings check runs under
  `record_fresh` (blocking, never reused, never recorded); `check-plans.sh` 7g/7h and
  `cloud-start.sh` A2/A6 are present.
- This feature's behaviour is intact: `.claude/settings.json` tracked and byte for byte the
  generator's; no `settings.json` generation in `feature-start.sh` or
  `self/worktree-setup.sh`; `self-settings.sh` sections 0 and A–F unchanged in intent.
- `self-settings.sh` section G (#83's former F1–F4) asserts what #83 meant — a deleted or
  drifted settings file fails a resumed gate, and no gate-state record is written — and
  is meaningful now that the file is tracked; `SETTINGS_STATE_NAME` matches the gate's
  real label mapping.
- No text anywhere still says agentTooling's own `.claude/settings.json` is ignored,
  untracked or generated per checkout, except as history (feature records, the design's
  dated findings).
- READMEs (`README.md`, `self/README.md`, `self/tests/README.md`) and `self/BACKLOG.md`
  describe both features; no conflict markers anywhere.
- `git diff origin/main -- self/features` shows only `self-cloud-bootstrap/`.
- `self/gate.sh` is green (`self/gate-report.txt`).

Fix local findings in the pass. Escalate structural ones. "No findings" is a legitimate
verdict. You may not edit `hooks/` or `.claude/`.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
