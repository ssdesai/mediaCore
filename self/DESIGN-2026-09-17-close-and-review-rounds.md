# Design 2026-09-17 — the close, and review rounds

Supersedes §3.2 ("no close") of `DESIGN-2026-09-16-lifecycle-restructure.md`. Everything
else in that record stands: no pins by default, the router, capture on the branch before
the merge, the sweep retired.

## 1. The defect

The review pass ends in a verdict with two outcomes — **clean**, or **escalated** with
structural findings the executor may not fix — and `run-review.sh` acts on it as if it had
one. Every finished review commits the pass, calls `pr.sh` (PR opened, verdict as body),
and calls `feature-capture.sh` (window stamped, records committed, branch pushed). A
rework then happens outside any gate: the PR body describes a tree that has since
changed, the frozen record is replaced by hand, the rework's delegates are pinned by hand,
no second review is required, and the timing file cannot tell one round from the next.

Measured on `hook-opaque-commands-and-audit` (PR #46, `timing.jsonl`): review 16:00–16:04
escalating four findings; PR opened and cost captured at 16:04; rework 17:25–17:36 with
three checkpoint stamps and no round marker; delegates pinned and the record re-captured
by hand; no second review; merged.

The `PR_AUTO_MERGE` race in `self/BACKLOG.md` (raised by `capture-on-branch`) is the same
defect seen from the other end: the merge request is issued by `pr.sh` before the capture
has pushed, because the order lives in a runner rather than in the step that owns it.

## 2. The rule

**A feature is a sequence of rounds, and the close is the only way out.**

- A **round** is build → gate → verify → review. It ends in the review's verdict.
- An **escalated** round stops there. Nothing after the review runs. The rework is routed
  like a build (direct, plans, or by hand; a cheaper model where the findings are
  precise), then the next review brief is queued and the review runs again. Round N+1.
- **`feature-close.sh`** refuses unless the latest completed review is clean and the tree
  being closed is the tree it judged. Then, in this order: PR → `pr_opened` stamp →
  capture (records committed, branch pushed) → merge request. The race disappears by
  ordering.
- **Runners are runners.** `run-review.sh` records the verdict and stops. `run-batch.sh`
  ends a clean round by calling the close and an escalated one by naming the brief.
- **Every stamp carries its round**, and the report shows rounds with their verdicts —
  the first quality measure the record collects.

`feature-start.sh` already gates entry (green base, worktree, fence). With the close, the
two scripts bracket the feature and nothing between them can open a PR or freeze a record.

## 3. The verdict

The review report (`REVIEW_REPORT`, the file prompt step 10 names) **begins with one
line**: `Verdict: clean` or `Verdict: escalated`. Constants in `run-review.sh`
(`VERDICT_PREFIX`, `VERDICT_CLEAN`, `VERDICT_ESCALATED`); the prompt says so, and says
that "clean" means the "escalated" list is empty. `run-review.sh` reads the line after the
plan completes; a missing or unrecognised line is `unreadable` (`VERDICT_UNREADABLE`) and
is treated exactly like escalated for everything that follows — **fail closed** — with a
line saying the report carried no verdict.

When the verdict is escalated, the **runner** copies the report to
`<features>/<slug>/escalations/<review-stem>.md`. That is the rework brief, in the same
directory the tier ladder writes `NN.md` into (`RUNNER.md` → "Red gates"), and the
executor writes nothing extra: one file, one writer, and the report already carries the
two lists (fixed here / escalated) the prompt asks for.

The runner still commits its own pass output — the review's local fixes, the queue move,
the sidecars — on a branch that is not the feature's base, as it does today, under the
subject **`<slug>: review round N`** (`PASS_COMMIT_SUFFIX` changes; `pr.sh`'s fallback
commit keeps its old subject and is now only ever a no-op). Then it stamps `plan_end` for
the review plan with `verdict=<clean|escalated|unreadable>` and `head=<sha of HEAD after
that commit>`, and `pass_end`. It opens no PR and runs no capture. Its last lines name the
next step: clean → the close command; escalated → the brief's path, and that a rework is
a new round (brief from that file; queue `NN+1-review-<model>.md`; `manifest.py
set-plans`; run the review again).

The budget-capped-after-report path stays: a complete report with a verdict is a verdict.

## 4. Rounds

`round` is the number of review plans in `<features>/<slug>/review/complete/` **plus
one**, computed once when a runner pass starts (`stamp_timing` in `plan-runner-roots.sh`
adds it to every event of that pass, held in `TIMING_ROUND`) and fresh at each by-hand
stamp (`stamp-timing.sh`, so a direct implementer's checkpoint stamps during a rework
read round 2). The close's own stamps (`pr_opened`) carry the count itself — the round
that closed. A `timing.jsonl` line that predates this carries no `round` and is read as
round 1.

`analysis/report.py` adds a **Rounds** table to `report.md` / `report.json`
(`rounds[]: { round, build_usd, build_min, verify_usd, verify_min, review_usd,
review_min, review_plan, verdict, escalations_file }`), one row per round, derived from
the stamps and the sidecars the existing tables already read. Verdict comes from the
review plan's `plan_end`; `escalations_file` is the path when the verdict was escalated
and the file exists, else null. No parsing of the model-written brief.

## 5. `feature-close.sh [--self] <slug> [--no-push]`

Run from the feature's worktree, on its branch, by the coordinator or by `run-batch.sh`.
The retired shim is replaced by the real script. Every refusal names what to do.

1. **Refuse** when: not on branch `<slug>` in its worktree (the post-merge repair path is
   `feature-capture.sh` from the primary and stays there); no review plan is complete;
   the latest completed review's `plan_end` has no `verdict=clean`; HEAD is not that
   stamp's `head` and any commit since it has a subject other than the harness's own
   (`<slug>: cost records`, `<slug>: PR`) — the tree being closed must be the tree that
   was judged, and a fix after the review is a new round; or the worktree holds a dirty
   path that is not a cost record (the capture's stray rule, so the refusal comes before
   a PR is opened rather than after).
2. **PR.** Compose the body: the report as the executor wrote it, then the Rounds table
   as `report.py` renders it (call `report.py` for the markdown fragment, or render the
   same rows; one renderer). Call the repo-owned `pr.sh <slug> <body>` — the existing
   contract — which pushes and opens, or says already open, or skips where there is no
   forge. Stamp `pr_opened` with rc and url.
3. **Capture.** `feature-capture.sh [--self] <slug> [--no-push]` — stamps `to`, captures,
   reports, commits `<slug>: cost records` (the `pr_opened` stamp rides it), pushes.
   Advisory as today: a refusal is printed with the re-run command.
4. **Merge request, last.** `pr.sh --merge-request <slug>` — new in the template
   (`template-version: 4`, both copies), the auto-merge moved out of the open step into a
   second entry point that the close calls only after the capture has pushed. Under
   `PR_AUTO_MERGE` unset it returns 0 saying nothing was requested; `self/pr.sh` keeps
   `AUTO_MERGE=0`. A seeded `pr.sh` older than 4 has no such entry point: the close says
   so once (`sync-plans.sh --check` already reports the drift) and skips the request.
5. Print the PR URL and "merge the PR — nothing runs after it".

Re-runnable: a second run finds the PR already open and the capture replacing its own
record, and ends at the same place.

## 6. `run-batch.sh`

After the review pass returns 0: read the latest review's verdict the same way the close
does (factor the reader into `plan-runner-roots.sh` or a small `feature-lib.sh` both
scripts source — one reader). Clean → call `feature-close.sh`; the unattended path still
ends in a PR. Escalated or unreadable → print the brief's path and exit 1.

## 7. The direct flow

Build → `run-review.sh` → `feature-close.sh`. `AGENT_DIRECT.md` → "The review is not
optional" is rewritten around rounds: a rework is briefed from `escalations/<stem>.md`
and is a new round; the re-review brief may be scoped to the escalations and run at a
cheaper model (`NN+1-review-sonnet.md`); the close opens the PR. The by-hand capture
"after a rework that skipped a full review" is gone: the close refuses a tree no review
judged.

## 8. What this closes in `self/BACKLOG.md`

- `PR_AUTO_MERGE=1` can merge before the cost commit is pushed (raised by
  `capture-on-branch`) — by ordering.

What it does not touch: `hooks/` (a parallel feature owns it; `feature-close.sh` is
already named there as an entry point that keeps prompting, which is now true again),
`feature-start.sh`, the numbering, the capture's stray rule internals.

## 9. Tests

All in `self/tests/feature-lifecycle.sh` unless named; the stub `gh` there records every
call and can record the origin branch's head at the moment of a `pr merge`.

- **V1** a review whose report begins `Verdict: clean`: `plan_end` carries
  `verdict=clean` and `head=<HEAD>`; the pass commit is `<slug>: review round 1`; no
  `pr create`, no capture, no push; the output names the close command.
- **V2** `Verdict: escalated`: `escalations/<stem>.md` equals the report; no PR, no
  capture; the output names the file and the next-round steps.
- **V3** no verdict line: `verdict=unreadable`, treated as V2, and said so.
- **X1** (replaces the shim test) the close refuses after V2; refuses after V1 when a
  commit with a non-harness subject follows the stamped `head`, naming the sha; refuses
  from the primary.
- **X2** after V1, unchanged tree: the order is `pr create` → `pr_opened` stamp →
  `<slug>: cost records` on the branch and pushed → `pr merge` (with `PR_AUTO_MERGE=1`
  and the template `pr.sh`), and the origin head at the `pr merge` call contains the
  cost commit. Under `self/pr.sh` no `pr merge` is ever called.
- **X3** a second close run ends at the same place, with one PR and one record.
- **RD** V2, then a rework commit, then a second review brief that reports clean: the
  second review's stamps carry `round=2`, the close succeeds, and `report.json` has two
  `rounds[]` rows with verdicts `escalated` then `clean` and the first row's
  `escalations_file` set.
- **B1/B2** `run-batch.sh` with a clean review calls the close (stub `pr create` seen);
  with an escalated one exits 1 with no PR.
- **T2/T3/T4/P2** rewritten to the new owner of each behaviour; `sync-check.sh` 1d and
  the versions test read `template-version 4` for `pr.sh`; a stamp with no `round` is
  read as round 1 in `report-footnotes.sh` or a new `report-rounds.sh`.
