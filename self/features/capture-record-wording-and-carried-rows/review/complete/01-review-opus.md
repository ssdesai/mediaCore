# 01 — review: capture-record-wording-and-carried-rows

## What the feature was supposed to do

Two small cleanups left over from `capture-merges-committed-record` (PR #95) and
`cloud-off-branch-remedy` (PR #97).

1. **Loose wording.** Since #95, `feature-capture.sh` merges into the committed
   `planning.json` and carries forward any row it cannot reach (stamped `carried_from`).
   The "Re-runnable" sentence in `feature-close.sh`'s header comment and in `LIFECYCLE.md`
   (the "replaces its own record" line near the end of the close step) still described the
   old replace behaviour. Both are reworded to say the capture merges into its record and
   carries forward the rows it cannot reach, and `README.md`'s `feature-close.sh` /
   `feature-capture.sh` rows say the same. Nothing else changes in those files.
2. **`report.py` warnings on carried rows.** In the PR #97 reconcile session `report.py`
   printed WARN lines about missing streams for the round 1 and round 2 review plans while
   saying one planning row was chained from an earlier capture. Those plans ran in a
   container that no longer exists (`*.stream.jsonl` is gitignored), which is exactly what
   #95 designed for. The WARN sites are `compute_re_hunting` and `compute_edit_overlap`
   ("… computed without streams for: …"). Both now take a `streams_carried` flag, set from
   `compute_carried(planning_data)`, and drop that warning when the record holds a carried
   row; the one-line "carried from the capture of …" note is kept. A record with no
   carried row still warns, and the sections are still computed from the streams that
   exist. New test `self/tests/report-carried-streams.sh` (registered in `self/gate.sh`
   and `self/tests/README.md`); `analysis/README.md` describes the behaviour.

Judge one deliberate choice: the link between a plan with no stream and a carried row is
record-level (any carried row quiets the warning for every plan), because the review
plans' session ids are not rows of `planning.json` and so cannot be matched per plan.
Say whether that is acceptable or whether a per-plan link exists that the spec would have
preferred.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The reworded sentences are accurate against `analysis/capture_planning.py`'s merge
  (carry forward, `carried_from` stamps) and nothing else in those files changed.
- `report.py`: with no carried row, behaviour and output are byte-identical to before;
  with one, only the two missing-stream WARNs disappear. The carried line, `report.json`'s
  `carried` key and every other warning are unchanged. `compute_carried` is now called
  before the two sections; nothing it reads is modified in between.
- `self/tests/report-carried-streams.sh` fails against the old `report.py` (carried case)
  and passes against the new; its non-carried case pins that genuine missing streams still
  warn. Same scaffolding conventions as `report-rounds.sh`; registered in `self/gate.sh`
  (syntax list and `record` line) and `self/tests/README.md`.
- READMEs touched are accurate (CONVENTIONS.md → "Keeping READMEs up to date"); the
  README, `self/gate.sh` and `self/tests/README.md` edits are minimal and local (another
  feature edits the same files in parallel).
- Named constants, bash 3.2, no profile variable spelled outside the allowed files.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
