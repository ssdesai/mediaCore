# 01 — review: lifecycle-records-and-numbering

Written before the build, from the manifest
(`self/features/lifecycle-records-and-numbering/README.md`), never from the implementers'
reports. "No findings" is a legitimate verdict. Fix local drift in this pass; anything
structural is an escalation, and an escalated report is round 2's brief. Begin your report
with the `Verdict:` line the prompt asks for. `hooks/` is out of scope and escalate-only.

## What the feature was supposed to do

Two lifecycle records read in two places become one reader each, and the self corpus's
plan-numbering exception is deleted. The base is `main`; the diff to read is
`git diff main...HEAD`.

1. **One numbering rule** (slice B). `feature-start.sh` writes `01-review-opus` in both
   modes; the `SELF_MODE` sequence (`find | sed | sort -n`) is gone; its "Next" text says
   the close opens the PR and captures, not the review. `self/PROJECT_FACTS.md` no longer
   says numbers run as one sequence across this corpus; `self/features/README.md` says the
   historical ranges were issued under the old rule. `self/tests/plan-numbering.sh`
   asserts `01` whatever another feature's corpus holds. This feature's own stub is
   `01-review-opus` — the first issued under the rule.
2. **One stray reader** (slice A). `is_cost_usage_path`, `stray_paths` and the constants
   they read (`COST_FILES`, `ANNOTATION_FILES`, the sidecar suffix, queues and states)
   live in `plan-runner-roots.sh` and nowhere else. `stray_paths` takes the sibling slugs
   whose three annotation files are admitted: none before the capture's annotation step,
   the returned slugs after it. `feature-close.sh`'s pre-PR check calls it with none, so
   everything the capture would refuse after the PR the close refuses before it.
3. **The close's round** (slice A1) is read from the latest review's `plan_end` stamp
   (`review_plan_end … round`), with `completed_review_count` only as the fallback for a
   `timing.jsonl` written before rounds existed.
4. **Verdict readers, directly** (slice A2). `self/tests/verdict-readers.sh` sources the
   roots file and calls `report_verdict`, `latest_review_plan` and
   `completed_review_count` without a runner; `self/gate.sh` runs it.
5. **Pre-4 `pr.sh`** (slice A3). A fixture at template-version 3 drives the close's skip
   branch: it says so, names the version, and the forge is called exactly once.
6. **`report.py` on an uncaptured feature** (slice B1) exits non-zero with one line that
   names `planning.json` and the close, and no traceback.

Not in this feature: `hooks/`, `routing.py`'s slug regex, `open-session.sh`, the report's
per-attempt duration walk, the ledger's zero-cost pin, `set-window-from`, the per-feature
budget, `git stash list`.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect:
`feature-start.sh`, `feature-close.sh`, `feature-capture.sh`, `plan-runner-roots.sh`,
`analysis/report.py`, `analysis/README.md`, `self/PROJECT_FACTS.md`,
`self/features/README.md`, `self/tests/plan-numbering.sh`,
`self/tests/feature-lifecycle.sh`, a new `self/tests/verdict-readers.sh`, one report
test, `self/tests/README.md`, `self/gate.sh`, root `README.md` rows, `LIFECYCLE.md` if it
described the check, `self/BACKLOG.md` (seven entries removed), and this feature's
`NOTES.md`/`CHECKPOINT.md`.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **One definition.** `grep -n "stray_paths\|is_cost_usage_path\|^COST_FILES=\|^ANNOTATION_FILES="`
  over `feature-capture.sh`, `feature-close.sh` and `plan-runner-roots.sh` finds each
  definition once, in the roots file, and only calls elsewhere.
- **Strict before, admitted after.** In `feature-capture.sh` the check that runs before
  the annotation admits no sibling's files, and the check before the commit admits
  exactly the slugs `--annotate-frozen` returned. A sibling's `report.md` dirty before the
  run is refused by name. Before this feature it was silently left dirty and the branch
  was pushed that way.
- **The close refuses what the capture would.** An untracked file inside the feature
  directory that is not a cost record refuses the close, names the path, and the forge
  stub records no call.
- **The round comes from the stamp.** A review filed to `review/failed/` after writing a
  clean report with `round=2` on its `plan_end` closes with `pr_opened` carrying
  `round=2`, and the banner says round 2. Where the stamp has no `round`, the count.
- **Verdict is the first line only.** The unit test's prose-first report with
  `Verdict: clean` in its body reads `unreadable`; `  VERDICT:  CLEAN \r` reads `clean`;
  `98-review-opus` and `101-review-sonnet` both complete → the 101 stem; a stem in
  `failed/` is returned by `latest_review_plan` and not counted by
  `completed_review_count`.
- **Pre-4 skip.** With the fixture `pr.sh` at version 3 the close prints the skip naming
  `3` and `4`, the forge log holds one create call and no merge call, and the close still
  exits 0 when the capture succeeded.
- **Numbering.** `feature-start.sh` has no branch on `SELF_MODE` around `NN`; the test
  places `104-x-opus.md` and `08-x-opus.md` in another feature on the base and asserts
  the new stub is `01` in `--self` mode and in a consuming-repo layout alike. No
  runner, `check-plans.sh`, `report.py` or `capture_planning.py` keys a plan by bare
  stem across features — the build's notes say what was checked.
- **`latest_review_plan` stays numeric.** Its comment now gives the surviving reason
  (`AGENT_PLANS.md` → a feature's own numbering past 99), not the corpus sequence.
- **The report's refusal.** `report.py --self <slug>` with no `planning.json` exits
  non-zero, prints one line naming the file and `feature-close.sh`, and the test asserts
  no `Traceback` in stderr.
- **Docs.** `LIFECYCLE.md`, root `README.md`, `self/PROJECT_FACTS.md`,
  `self/tests/README.md` and `analysis/README.md` describe what runs; no sentence
  anywhere still says the self corpus numbers as one sequence, the close's check is
  "looser", or the review opens the PR. `feature-start.sh`'s printed next steps name
  `feature-close.sh`.
- **Style.** Named constants; bash 3.2; `set -uo pipefail`, no `set -e`; no chained
  `cd`; nothing under `hooks/`; README Rules 1 and 2 on every touched entry.
- **Exclusions named.** Every deviation from the manifest has a ruling in `NOTES.md`,
  and each backlog entry the manifest says is closed is gone from `self/BACKLOG.md` —
  the stray rule, the sibling record, the pre-4 test, the verdict readers, the close's
  round, the numbering collision, the report traceback.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the batch was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
