# 71 — review: tooling backlog, September 2026

Independent review of one direct one-shot's diff. Written before the build, from the
manifest; nothing here comes from the implementer's report, and the implementer did not
write it.

## What the feature was supposed to do

`self/features/tooling-backlog-2026-09/README.md` → "The items, with the decision each
one is built to": nine items, each with its decision settled there. Read that section
first and hold the diff to it item by item. Nine items: item 9 (a skipped level-verify is not
missing usage) was appended after the build began and is in scope. The decisions are not reopened; a diff that
picked a different design for one of them is a finding, however good the design.

## The diff

Base is `main` at `c6cb394`. `git diff main...HEAD --stat`, then the full diff. Expect
runner scripts (`run-batch.sh`, `run-plans.sh` or `plan-runner-lib.sh`, `run-review.sh`,
`sync-plans.sh`, a new `stamp-timing.sh`), `templates/plans/pr.sh`, `self/pr.sh`, a new
`templates/plans/.gitignore`, `analysis/report.py` and `analysis/capture_planning.py`,
self tests, and docs (`README.md`, `RUNNER.md`, `ORCHESTRATION.md`, `AGENT_DIRECT.md`,
`analysis/README.md`, `templates/README.md`, `self/tests/README.md`,
`harness/methods/direct/template.md`). Also `self/features/tooling-backlog-2026-09/`
itself — `CHECKPOINT.md`, `NOTES.md` — which is the implementer's record, not the
feature.

## Contracts to hold it to

- **Every runner change has a self test that pins it.** `self/PROJECT_FACTS.md` →
  Tests: a new runner contract belongs in `self/tests/`, never in a verify brief. For
  items 1, 2 and 5, find the assertion; read it against the manifest's decision, not
  against the implementation; and check it would fail without the change (a stub
  scenario that passes on `main` is not a test of this diff — checking out `main`'s
  copy of the one script under test into the scratch checkout is a fair way to see).
- **`./self/gate.sh` is green**, and `shell_scripts` in it lists every new script.
- **bash 3.2** (`self/PROJECT_FACTS.md` → Conventions): no associative arrays, no
  `${var^^}`, `${a[@]+"${a[@]}"}` for possibly-empty arrays under `set -u`; and no
  `set -e` in the runners — `if …; then` over `cond && cmd` where the status is
  unchecked.
- **`templates/plans/pr.sh` and `self/pr.sh` carry the same stacking logic** as the
  reference (`/Users/sahildesai/dev/vinylCatalogue/plans/pr.sh`): branch off the
  checked-out branch, PR against it, `BASE_BRANCH` from the environment only on the
  re-run path. The template's REPO-SPECIFIC header comments still make sense to a repo
  seeding it fresh.
- **Item 9 both ways.** A skipped level-verify no longer marks a total partial; a plan
  with no sidecar and no `skipped:` line still does. Both asserted.
- **A planned feature's report is unchanged.** `python3 analysis/report.py --self
  test-first-levels` (or any planned self feature) before and after the diff: same
  output. The direct sub-rows appear only with `method: direct` and `checkpoint` events.
- **READMEs** (`CONVENTIONS.md` → Keeping READMEs up to date): the top-level table for
  `stamp-timing.sh`; `templates/README.md` for the gitignore stub; `self/tests/README.md`
  for every test touched, in that file's paragraph-per-test style; `analysis/README.md`
  for the `checkpoint` event and the report keys it produces.
- **Docs say what the code does**, not what it did: `README.md`'s install and Updating
  steps for gitignore and for `pr.sh`; `RUNNER.md` → "How resume works" if item 1 or 2
  changed what it describes; `AGENT_DIRECT.md` for the stamp and `date -u` lines.

## Judgment calls to check

1. Item 1: what a finished batch does on re-run when its gate reports are gone (fresh
   clone). The manifest accepts one extra mechanical gate run at that level; anything
   more — a re-run of the level-verify plan, a tier — is a finding.
2. Item 2: the fallback order (`LEVEL_PAUSE_NN_OUT`, then `last_sentinel_nn`, then fail)
   and that the file is created and cleaned up the way `FEATURE_SLUG_FILE` is.
3. Item 4: on the re-run path, an already-open PR keeps its base; `BASE_BRANCH` must not
   be applied to it.
4. Item 5: `stamp-timing.sh` under `--self` writes to `self/features/<slug>/timing.jsonl`
   and in a consuming repo to `plans/features/<slug>/timing.jsonl` — the artifact-root
   rule in `self/PROJECT_FACTS.md`. And the event's key is `status`, its values the five
   checkpoint statuses, nothing else invented.
5. Item 6: `plans/.gitignore` is in `GENERATED` and so overwritten every sync — it must
   therefore hold nothing a repo would customise. If the implementer put anything
   repo-specific in it, that is a finding.

## Verdict

Write it to the path the runner names, for the person approving the PR: what the diff
was supposed to do, whether it does it, then two lists — fixed in this pass, escalated.
Fix local defects here (a missing README row, a wrong message, an assertion that does
not bite); escalate structural ones. "No findings" is a legitimate verdict; say it
outright rather than manufacturing concerns.
