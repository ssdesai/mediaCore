# brief-conformance-checks — rulings

The coordinator's decisions where the orchestrator brief left the design open ("design the
exact file names and flags yourself and record the decisions in NOTES.md"). The behaviours
the brief fixes are not restated here; these are the choices around them.

## Names

- **R1. The owner brief is `<features>/<slug>/OWNER_BRIEF.md`** (`self/features/` under
  `--self`, `plans/features/` in a consuming repo). `feature-start.sh --owner-brief <file>`
  copies the file byte for byte (`cp`, never through a model) into the feature directory
  before the `<slug>: start` commit, which carries it. The start refuses, before any write,
  a path that is missing, not a regular file, unreadable or empty (whitespace only). An
  orchestrator that did not supply it at start may add the same file later, before the
  review, as an ordinary commit on the branch; nothing checks how it arrived.
- **R2. The helper is `conformance.py` at the tooling root**, executed (never imported) by
  `run-review.sh`, `feature-close.sh` and `pr.sh` (template-version 8), and added to
  `AUDIT_TOOLING_PATHS` in `plan-runner-roots.sh` and to LIFECYCLE's audit-path list: the
  close refuses on what it reads, so a change to it is a change to an enforcing file. Not
  under `analysis/`, which is cost analysis. Subcommands (stdout, exit codes in its
  docstring): `items <owner-brief>`, `table <report> <heading>`, `check-close …`,
  `pr-body <report> [--conformance <report>]`, `deviations <body>`, `summary …`.
- **R3. Item ids.** `conformance.py items` enumerates the owner brief's items
  deterministically: every markdown heading (`#`–`######`) whose text begins with a number
  followed by `.` or `)` is item `<number>`, titled by the rest of the heading. A brief with
  no such heading is one item, id `1`, "the owner's request". `templates/plans/ORCHESTRATOR_BRIEF.md`
  already numbers its items as `### N. <item>`, so an orchestrated brief yields one id per
  item. The runner prints the id list into both the review prompt and the conformance
  prompt, and both tables key their rows by it.

## Report shapes (fixed headings; the parsers are `conformance.py`)

- **R4. `## Acceptance`** — a markdown table whose header row is `Item | Evidence | Result`.
  The Item cell begins with the id (`1`, `1.`, `1 —`, `1:` all read as `1`); rows whose id
  is no owner item are the review's own acceptance lines and are held to the same rule.
  Result is `done`, `partial` or `not done` (case and surrounding space ignored); any other
  value is read as not done and named (fail closed).
- **R5. `## Deviations from the brief`** — free text; empty is written `None` (`None.`
  accepted). A missing section is read as non-empty ("section missing from the review
  report"), so a report outside the format is marked rather than merged blind.
- **R6. The conformance report**, `<features>/<slug>/conformance-report.md`, written by the
  RUNNER from the conformance executor's final message (the `result` event of its stream),
  never by the executor: it has no tools. Sections `## Conformance` (same table shape as
  R4, one row per owner item) and `## Out of scope` (`- <path> — <why>` lines, or `None`).
  The runner deletes any earlier copy before the pass, so a report can only be this pass's.

## The conformance pass (item 3)

- **R7. It runs inside the review round** as a third kind of review-queue plan,
  `NN-conformance-<model>.md`, queued by `run-review.sh` (like the audit) when the feature
  has an `OWNER_BRIEF.md` and a review is queued: NN the review's, model the review's
  suffix ("the review's tier"), stem added to `plans[]` so `report.py` prices it like any
  plan. Sort order in one pass: `NN-audit` < `NN-conformance` < `NN-review`, so the review
  stays last and keeps the held `plan_end` the pass stamps. `completed_review_count`,
  `latest_review_plan` and the audit queueing skip it, as they skip the audit
  (`is_conformance_stem`). Chosen over a separate runner the close requires: one pass, one
  round commit, one cost record, no new entry point to forget.
- **R8. Isolation is enforced by the launch, not asked of the model.** The plan body is
  never put in the prompt (a hand-edited plan changes nothing). The prompt is built by the
  runner from exactly: fixed instructions, the item list, `OWNER_BRIEF.md` verbatim, and
  `git diff --stat` plus `git diff <diff-base>...HEAD` with the feature's own directory
  excluded (`:(exclude)<features>/<slug>/` — that is where NOTES.md, CHECKPOINT.md, the
  review briefs and the reports live). The executor is launched with `--tools ""` (no tool
  at all, so it cannot open NOTES or a transcript) and the prompt on stdin (a diff can pass
  the 128 KiB single-argument limit). Mechanism: an optional per-plan hook in
  `plan-runner-lib.sh`, `executor_args_for_plan <plan>`, which may replace the plan's tool
  arguments (`PLAN_TOOL_ARGS`) and set `PLAN_PROMPT_ON_STDIN=1`; a wrapper that does not
  define it launches exactly as before. Accepted residue: `claude -p` still auto-loads the
  repo's `CLAUDE.md`, which is project instructions, not the implementer's restatement.
- **R9. Budget** is the review's (`REVIEW_BUDGET_USD`); no tools means a short run.

## The close (items 2 and 3)

- **R10. Read from git at the judged head, never the working tree**, like the audit: the
  archived `review-report.md`, `conformance-report.md` and `OWNER_BRIEF.md` at
  `JUDGED_HEAD`, the conformance plan in that tree's `review/complete/`. Only when
  `OWNER_BRIEF.md` exists there; otherwise one `note` line and nothing new is required.
- **R11. With an owner brief, the close refuses** (before anything is written), naming the
  row: a missing `## Acceptance` table; a row whose result is not `done`; an owner item id
  with no row; a missing `## Deviations from the brief` section; no conformance plan with
  the review's NN and model in the judged tree; no conformance report at the judged head, or
  one last written by anything but a `<slug>: review round N` commit; an owner item the
  conformance table does not mark `done` (named as "review says X, conformance says Y");
  an `OWNER_BRIEF.md` the start commit carried that differs at the judged head.
- **R12. Deviations never block the close.** The conformance report's out-of-scope list is
  merged into the PR body's deviations section.

## The PR (items 2 and 4)

- **R13. `pr.sh` composes and marks, through `conformance.py`.** `feature-close.sh` exports
  `CONFORMANCE_SCRIPT` (the helper's path) and, when there is one, `CONFORMANCE_REPORT` (the
  judged head's conformance report, extracted to a temp file), beside `FORGE_SCRIPT`.
  `pr.sh` template-version 8 runs `conformance.py pr-body`, which puts `## Acceptance`
  first, `## Deviations from the brief` (with the out-of-scope list appended) second, then
  the rest of the report and the Rounds table. A body with no acceptance section is passed
  through in order. An older `pr.sh` ignores both variables: the body is the report as
  before, which is the rollout.
- **R14. The mark is a title prefix, `[deviations] `**, before the title `pr.sh` already
  uses (the slug). A label needs the label to exist on the repository; a title is set by the
  same REST calls in both profiles. `forge.sh pr-edit` takes an optional title so a re-close
  sets or clears the prefix on a PR an earlier round opened.

## Rollout

- **R15.** No owner brief: the review prompt carries no owner section and the runner prints
  `  note      no OWNER_BRIEF.md …` once; no conformance plan is queued; the close prints one
  `note` and requires no table. The deviations section and the title mark apply to every
  report (item 4 is not among the items that degrade).
- **R16.** This feature's own round runs without an owner brief: the orchestrator's text
  reached this session only as a message, and retyping it into a file is the byte-moving the
  rules forbid. The BACKLOG entry the brief asks for covers the first wave that supplies one.

- **R17. Round 2 (the coordinator's rulings on round 1's review and audit).**
  - **Items (amends R3).** Numbered headings stay items. With no numbered heading, every
    top-level numbered list item (`^\d+[.)]\s+` at column 0, outside a fence) is an item, its
    title the opening `**`/`__` span when the line opens with one, else the line with the
    markers removed. Headings win when both exist; neither is the one fallback item `1`.
    Said in LIFECYCLE.md, ORCHESTRATION.md "Rules" and `ORCHESTRATOR_BRIEF.md`.
  - **No owner brief, no acceptance section asked (amends R15).** `run-review.sh` asks such
    a review only for `## Deviations from the brief`; the acceptance table and the "owner's
    request listed above" wording only when `OWNER_BRIEF.md` exists.
  - **The PR mark.** Item 4's mark applies to every report, but a report with NO deviations
    section is marked only when the feature has an owner brief. `feature-close.sh` already
    exports `CONFORMANCE_REPORT` only then, so `pr.sh` (template-version 8, hash re-recorded,
    version unchanged because 8 is not on main yet) passes `--owner-brief-present` to
    `conformance.py deviations` exactly when it is set; without the flag a missing section
    reads as `none` (reason on stderr). A no-brief report without the section keeps the plain
    slug as its title, exactly today's; a section with a deviation marks it either way.
  - **plans[].** `queue_conformance_check` appends the stem only when absent (a review moved
    back to `incomplete/` after its check finished queues the same stem again).
  - **A conformance plan the feature does not owe is refused** (audit B1 and non-blocking 1-2).
    `refuse_unowed_conformance_plans` in `run-review.sh` runs first, before
    `queue_security_audit` pairs the audit with its review and before
    `queue_conformance_check`'s early returns: any queued `NN-conformance-<model>` plan, in
    `incomplete/` or `inprogress/`, with no `OWNER_BRIEF.md`, no review queued beside it, or a
    stem other than `<review NN>-conformance-<review model>` exits 1 with a "delete it"
    message, before anything runs.

## Implementation notes

What differs from, or goes past, the rulings as written, and why.

- **R13, the body's first lines.** `conformance.py pr-body` puts the report's text before its
  first heading (its `Verdict: clean` line) under a heading of its own, `## Review verdict`,
  after the deviations section. Left bare it would read, to the parser and to a markdown
  renderer, as the tail of `## Deviations from the brief`, and a `None` section would read as
  non-empty.
- **R11, the conformance report's writer.** It must be last written by the `<slug>: review
  round N` commit of the round that judged the tree (N from the review's own `plan_end`), not
  by any round: an earlier round's report that a later round failed to rewrite is not evidence
  for this tree. The close also refuses a missing archived `review-report.md` and, beyond
  R11's list, a `<slug>: cost records` / `<slug>: PR` commit after the judged head that
  touches `OWNER_BRIEF.md`, `conformance-report.md` or a conformance plan (the same rule the
  audit's evidence already has).
- **R7, a conformance plan queued by hand.** `run-review.sh` rewrites a plan with the right
  stem (its body is never read) and refuses one with any other stem, or one resumed from
  `inprogress/` with no conformance plan beside it, the way it refuses a stray audit.
- **R8, a cap on the diff.** The prompt carries at most `CONFORMANCE_DIFF_MAX_BYTES` of the
  diff, says when it cut it, and tells the executor an item it cannot verify from the part it
  has is `partial`; `--stat` always lists every changed file.
- **R5/R15, the title mark.** `pr.sh` marks any report whose deviations section is non-empty or
  missing, owner brief or not, as R15 says; the review prompt always asks for the section, so
  a report written by this runner is unmarked when it says `None`. A `pr.sh` with no report at
  all (the fallback body) is marked, since it says nothing about deviations.
- **R14.** `pr.sh` passes the title to `pr-edit` only when `CONFORMANCE_SCRIPT` is set, so a
  seeded copy at 7 and every stub forge that knows two arguments behave as before.
- **Existing tests that pinned `pr.sh` at template-version 7** (`feature-lifecycle.sh` P2e,
  `sync-check.sh` 1d, 1f, 4b, 4d, 4g-4i) now pin 8: the version bump is the feature's own
  contract, and no check was loosened.
