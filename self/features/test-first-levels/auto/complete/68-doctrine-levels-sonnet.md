# 68 — Doctrine: "Levels: tests first, gate between layers"

Feature `test-first-levels`, plan 4 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

Summary: write the authoring rules that use the mechanics plans 65–67 add —
`AGENT_PLANS.md`'s new section, manifest tables, checklist item and file-format bullet,
the manifest template, and the `self/` index lines.

Depends on: 65, 66, 67 for the mechanics the text describes (no file overlap).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Facts:
- Mechanics being documented: `NN-gate.md` in `auto/incomplete/` is a sentinel; the build
  runner runs `gate.sh NN` there, which writes `gate-report.NN.txt`; if a verify plan
  numbered ≤ NN is queued, `run-plans.sh` exits 4 and `run-batch.sh` runs
  `run-verify.sh --up-to NN` before resuming the build; the final gate, verify and review
  are unchanged. The gate's `record_skip` makes a SKIPPED check a non-green verdict.
- `AGENT_PLANS.md` is ~350 lines; keep each addition short. Sections, in order, that this
  plan touches: "Plan file format" (line ~108), "Split work by executor capability"
  (~244), "Verify plans" (~250), "The feature manifest" (~135), "Plan completeness
  checklist" (~329).
- Plan numbering in `self/` is documented in `self/PROJECT_FACTS.md`'s last bullet as
  global across features: `plan-analytics` 48–58, `agenttooling-self-host` 59–64.

## Files

- `AGENT_PLANS.md` (modify)
- `templates/plans/features/TEMPLATE.md` (modify)
- `self/features/README.md` (modify)
- `self/PROJECT_FACTS.md` (modify)

## `AGENT_PLANS.md`

**New section** `## Levels: tests first, gate between layers`, placed after "Split work
by executor capability" and before "Verify plans". Seven short numbered points, in this
order — write each as two to four sentences, no more:

1. **Plan 01 of every batch is the wanted behaviour as tests.** Black-box, top-down from
   the requirement, through the real boundaries the feature crosses (the real request
   body, the real producer of the string being compared, the real store the view reads).
   Red for the whole build; that is expected. Its assertions are the feature's
   enumeration — an "all X" in the requirement is one assertion per X, and the manifest's
   plan table says so.
2. **A level is one layer:** its tests plan, then its build plan(s), then a sentinel
   `NN-gate.md`. Order levels bottom-up by dependency. Two or three levels per batch; five
   means the batch is too big.
3. **Level tests are white-box and cheap; plan 01 is black-box.** Leaf tests written from
   the author's own model of a shape pass against that model; only the black-box test at
   the top catches a shape the other layer cannot produce. Never let level tests stand in
   for plan 01.
4. **The sentinel runs the gate at no model cost.** Red at a boundary is normal; the point
   is that the next level's author knows, at authoring time, which gate sections must be
   green at each boundary, and says so in the optional level-verify brief.
5. **A level-verify plan is optional and scoped.** Add one only where the next level builds
   on this level's contract (a schema the frontend mirrors, a route the client calls). It
   is a verify plan — bash, `sonnet`, same fix policy — numbered between its sentinel and
   the next build plan (`05-gate.md` → `05-level-backend-sonnet.md` in `verify/`), and its
   brief names which gate sections must be green and tells the executor to stop
   immediately if they are. Assume one per batch is affordable and two is not until the
   pilot measures it.
6. **The final verify shrinks.** Its brief is "read plan 01's test file and the level
   tests; check only what they leave uncovered." Everything in "Verify plans" still
   applies.
7. **Ran and passed, never "no failures".** A SKIPPED section in any level's gate report
   means that level is unverified, not green; `record_skip` in `gate.sh` and the verify
   prompt both say so.

Then show the target shape once, as a fenced tree (copy it exactly):

```
auto/incomplete/
  01-acceptance-tests-sonnet.md      # wanted behaviour, black-box, RED until the end
  02-backend-tests-haiku.md          # level 1: tests for the pieces 01 depends on
  03-backend-schema-haiku.md         # level 1: build
  04-backend-service-sonnet.md       # level 1: build
  05-gate.md                         # sentinel — gate runs here, labelled "05"
  06-frontend-tests-haiku.md         # level 2
  07-frontend-store-haiku.md         # level 2
  08-frontend-view-sonnet.md         # level 2
  09-gate.md                         # sentinel — gate runs here, labelled "09"
verify/incomplete/
  05-level-backend-sonnet.md         # optional level-verify, drained after 05-gate
  10-verify-sonnet.md                # the final verify, smaller than before
review/incomplete/
  11-review-opus.md
```

**"The feature manifest"** — after the JSON-fence bullets and before "See
`templates/plans/features/TEMPLATE.md`…", add a paragraph introducing two optional tables
in the human-readable part (the JSON is unchanged — sentinels are not plans and never
appear in `plans[]`):

- **Levels** — `| Level | Plans | Sentinel | Level-verify | Must be green |`, one row per
  level; the last column names gate sections.
- **Contracts across levels** — `| Value / identifier | Produced by (plan, file:line) |
  Consumed by (plan, file:line) | Asserted by |`, one row per thing that crosses a level
  boundary; the last column is a test in plan 01 or in a level tests plan, and an empty
  last column is a finding at authoring time.

**"Plan completeness checklist"** — add item 6: *Identifier introduced in one file and
resolved in another?* (a route path, an event name, a field the other side reads) — both
files in one plan, or two plans that name each other in `Depends on:` and spell the
identifier identically; and one row in the manifest's contracts table.

**"Plan file format"** — add a bullet: `NN-gate.md` is a sentinel, not a plan — no model
suffix, no content required (an empty file works; a one-line comment naming the level is
better), never listed in the manifest's `plans[]`, never sent to an executor.

## `templates/plans/features/TEMPLATE.md`

After the `## Plans` table, add `## Levels` and `## Contracts across levels` with the two
table headers above and one placeholder row each, plus a one-line note under each: delete
the section when the batch has a single level.

## `self/features/README.md`

Append to the "Features" list:
`- \`test-first-levels\` — level sentinels (\`NN-gate.md\`), the per-level gate label and
\`record_skip\`, \`run-verify.sh --up-to\`, the \`run-batch.sh\` level loop, and the
"Levels" doctrine. Plans \`65\`–\`70\`.`

## `self/PROJECT_FACTS.md`

Last bullet: append `test-first-levels` is `65`–`70`. Add a new bullet: a file named
`NN-gate.md` in `auto/incomplete/` is a level sentinel, never executed; `run-plans.sh`
exits 4 at one when a verify plan ≤ NN is queued.
