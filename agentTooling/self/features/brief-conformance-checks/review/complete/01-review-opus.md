# 01 — review: brief-conformance-checks

Judge the diff against the orchestrator's items below (the owner's ruling of 2026-11-19),
not against the implementer's NOTES.md; NOTES.md records the design choices the items left
open (file names, flags, report shapes), and a choice there that narrows an item is a
finding. "No findings" is a legitimate verdict — say it outright rather than manufacture
concerns.

## What the feature was supposed to do

Four checks become part of the harness, so that a review can no longer be clean while the
PR does something other than what the owner asked. Each needs a mechanism, a `self/tests/`
assertion, and docs (`LIFECYCLE.md`, `ORCHESTRATION.md`, the templates) saying how to use it.

1. **The owner's request is the review's yardstick.** A feature can carry the owner's
   request verbatim as a file in its feature directory, supplied at start by a
   `feature-start.sh` option taking a file, or added by the orchestrator before the review.
   When it exists, every review plan is given it word for word, with the instruction that the
   work is judged against it and not against the implementer's restatement; a review brief
   may add contracts but may not narrow it. `ORCHESTRATION.md` and
   `templates/plans/ORCHESTRATOR_BRIEF.md` say the orchestrator writes or supplies it.
   Assertion: a feature started with the option has the file committed in its start commit,
   and the review prompt the runner builds contains its text verbatim.
2. **Acceptance table.** Each owner-brief item and each acceptance line maps to the test(s)
   proving it, with the result. The review report carries a fixed section (item → evidence:
   test name or file:line → result: done / partial / not done). `pr.sh` puts it at the top of
   the PR body. A report whose table is missing, or has a row not "done", cannot be closed as
   clean: `feature-close.sh` refuses, naming the row. Assertion: a stub report with a
   "partial" row is refused by the close; with all rows "done" the close proceeds and the PR
   body begins with the table.
3. **Independent conformance check.** A separate pass, a fresh `claude -p` given ONLY the
   owner's brief and the feature's diff against its base (not the implementer's NOTES,
   review brief or transcript), returns per item done / partial / not done with evidence and
   lists every changed file it cannot tie to an item. It runs in the review round or as its
   own runner the close requires; its cost is recorded like any other pass; the close
   refuses unless it agrees with the review's table. Model: the review's tier. Assertion:
   with a stubbed answer of "not done" for an item the review marked done, the close refuses
   naming the disagreement; with an out-of-scope file listed, the PR body's deviations
   section names it.
4. **Deviations section.** The review report and the PR body carry a fixed "Deviations from
   the brief" section (different reading, omission, out-of-scope edits including item 3's
   list); empty is "None". Non-empty does not block the close, but `pr.sh` marks the PR (a
   title prefix or label that works in both profiles) and `ORCHESTRATION.md` states that an
   orchestrator never merges a PR with a non-empty deviations section without the owner's
   word. Assertion: one deviation yields a marked PR body/title; "None" an unmarked one.
5. **Rollout.** Without an owner brief, items 1–3 degrade to today's behaviour with a
   one-line notice, so no consuming repo breaks on its next pull; `LIFECYCLE.md` says so.
   `self/BACKLOG.md` gains an entry for making the owner brief mandatory for orchestrated
   features once one wave has used it.

Excluded: making the owner brief mandatory (that is the backlog entry); the sibling
features' files (`hooks/`, `orchestration-start.sh`, `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`,
`ORCHESTRATION.md` → "Cloud sessions").

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **No owner brief, no change.** A feature without `OWNER_BRIEF.md` must review, close and
  open its PR exactly as on `main`, plus one notice line each; walk the `run-review.sh`,
  `feature-close.sh` and `pr.sh` paths for that case. The existing tests (`security-audit.sh`,
  `feature-lifecycle.sh`, `pr-body-refresh.sh`, `close-backlog.sh`, `review-base.sh`) must
  hold unchanged in what they assert.
- **The isolation of item 3 is mechanical.** The conformance executor's prompt holds only
  the fixed instructions, the item list, the owner brief and the diff with the feature's own
  directory excluded; it is launched with no tools; nothing it could read reaches it. The
  per-plan launch hook in `plan-runner-lib.sh` must leave every other plan's launch
  byte-for-byte as before.
- **Round mechanics stay intact.** The conformance plan is no round: `completed_review_count`,
  `latest_review_plan` and `queue_security_audit`'s review detection skip it; the review
  still runs last in the pass and its `plan_end` is the one stamped with verdict and head;
  the audit's stem, NN and template checks are unchanged.
- **The close reads evidence from git at the judged head**, like the audit check, and every
  new refusal happens before anything is written or any PR is opened, naming the row or the
  disagreement. A conformance report not written by a review-round commit is no evidence.
- **Templates.** `templates/plans/pr.sh` and `self/pr.sh` move to template-version 8 in
  step, the `TEMPLATE_VERSIONS` row re-recorded (`templates/README.md`); `pr.sh`'s contract
  for older callers (no `CONFORMANCE_SCRIPT`) is unchanged; `forge.sh pr-edit` without a
  title behaves as before. `ORCHESTRATOR_BRIEF.md` stays a generated template whose test
  (`self/tests/orchestrator-brief.sh`) holds.
- **Audit paths.** The new helper the close executes is added to `AUDIT_TOOLING_PATHS` and to
  `LIFECYCLE.md`'s list of audit paths.
- **READMEs** of every touched folder name the new files (`check-readme-index.py`), and the
  new test is listed in `self/tests/README.md` and run by `self/gate.sh`.
- **Each item has its assertion** in `self/tests/`, exercising the real scripts with a stubbed
  `claude` and a stubbed forge, not a re-implementation of their logic.

## Verdict

The report's first line is the verdict the runner's prompt specifies. Then: what the
feature was supposed to do, whether it does it item by item, what you fixed, and what you
escalate — each escalation phrased as the assertion or change that would settle it.
