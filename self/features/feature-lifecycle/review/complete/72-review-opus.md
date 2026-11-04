# 72 — review: feature lifecycle

Independent review of one hand-built feature's diff. Written before the build, from the
manifest; nothing here comes from the builder's report.

## What the feature was supposed to do

`self/features/feature-lifecycle/README.md`: "The rule", then "The items, with the
decision each one is built to", sixteen items in six groups. Read both sections first
and hold the diff to them item by item. The decisions are not reopened; a diff that
picked a different design for one of them is a finding, however good the design.

## The diff

Base is `main` at `396f4f2`. `git diff main...HEAD --stat`, then the full diff. Expect:
`README.md` restructured; `EXPERIMENTS.md` moved under `harness/` with every reference
updated; `migrate-plans-layout.sh` deleted; `analysis/capture_planning.py`,
`analysis/report.py`, a new `analysis/manifest.py`; new top-level `feature-start.sh`,
`feature-close.sh` and `LIFECYCLE.md`; `plan-runner-roots.sh` (`manifest_field`),
`plan-runner-lib.sh` (the stub-marker refusal), `run-review.sh` (`FEATURE_BASE`),
`sync-plans.sh`; `templates/plans/pr.sh`, `self/pr.sh`, a new
`templates/plans/worktree-setup.sh` and `self/worktree-setup.sh`; self tests
(`capture-guard.sh`, `subagent-capture.sh`, `direct-timing.sh`, a new
`feature-lifecycle.sh`) and `self/gate.sh`; docs (`AGENT_DIRECT.md`, `AGENT_PLANS.md`,
`ORCHESTRATION.md`, `RUNNER.md`, `analysis/README.md`, `templates/README.md`,
`templates/plans/features/README.md`, `templates/plans/features/TEMPLATE.md`,
`self/README.md`, `self/features/README.md`, `self/tests/README.md`,
`self/PROJECT_FACTS.md`). Also `self/features/feature-lifecycle/` itself and the moved
triage under `self/`, which are the record, not the feature.

## Contracts to hold it to

- **The rule is exact.** Slug pattern `^[a-z0-9]+(-[a-z0-9]+)*$`; branch equals slug;
  worktree equals the primary path plus `-` plus the slug. Every place that derives one
  of these — `feature-start.sh`, `feature-close.sh`, `capture_planning.py`'s
  `repo_match`, the tests — derives the same string. A second spelling anywhere is a
  finding.
- **Every new behaviour has a self test that pins it, and the test fails without the
  change.** `self/PROJECT_FACTS.md` → Tests. For items 4, 5, 6, 7, 9, 11, 12 and 13,
  find the assertion, read it against the manifest's decision rather than the
  implementation, and check it would go red against `main`'s copy of the file under
  test. `capture-guard.sh` assertions 1–14 must still pass unchanged.
- **`./self/gate.sh` is green**, `shell_scripts` lists every new script, and the new
  test is `record`ed.
- **bash 3.2**: no associative arrays, no `${var^^}`, `${a[@]+"${a[@]}"}` for
  possibly-empty arrays under `set -u`. The runners and the lib keep
  `set -uo pipefail` with no `set -e`; the two lifecycle scripts may use `set -euo
  pipefail` as `sync-plans.sh` does, but any exit status they branch on — the hook,
  the gate, capture — is checked with `if`, never left to `-e`.
- **Roots are unchanged.** `REPO_DIR` is still one directory above the script; the
  session root is still the nearest `.git` ancestor; the mount constraint in
  `README.md` still holds. `feature-start.sh` and `feature-close.sh` resolve the primary
  checkout from their own location, never from `cwd`.
- **`sync-plans.sh` never overwrites a repo-owned file.** `worktree-setup.sh` is seeded
  the way `gate.sh` and `pr.sh` are, and the generated list is unchanged.
- **`templates/plans/pr.sh` and `self/pr.sh` carry the same logic** below their
  REPO-SPECIFIC line; diff them. Neither creates a branch. Both refuse on the base.
- **Capture's guards are untouched.** The frozen-cost refusal, the already-captured
  skip, `--carry-lost`, the claims ledger and the branch-overlap warning behave as
  before; the zero refusal sits in front of the write and nowhere else. A pinned
  session is priced once even when branch and window also select it.
- **`method: "hand"` changes nothing for other methods.** A planned feature's
  `report.md` is byte-identical before and after; a direct feature's too.
- **Field lists** (`CONVENTIONS.md` → Rule 1): `analysis/README.md` → JSON artifacts
  lists `cwd` and `selected_by` on session entries and `sessions` and `base` on the
  manifest; `AGENT_PLANS.md` → "The feature manifest" and `TEMPLATE.md` document the
  same fields with the same names.
- **Every touched folder's README is current** (`CONVENTIONS.md` → "Keeping READMEs up
  to date"), and every reference to `EXPERIMENTS.md` and `migrate-plans-layout.sh`
  in this repo resolves or is gone: `grep -rn` both names outside `self/features/`
  and `.git/`.
- **The prune removed procedure, not judgment.** Read the removed hunks of
  `AGENT_DIRECT.md`, `ORCHESTRATION.md`, `AGENT_PLANS.md` and `analysis/README.md`:
  each removed sentence is something a script now enforces, and the sentence that
  replaces it names the script. `LIFECYCLE.md` says when to run which script and
  contains no rule a script already refuses on.
- **This feature's own manifest** names only `feature-lifecycle` in `branches`, pins
  the building session by id, and has `to: null` until `feature-close.sh` stamps it.
  That file is not to be edited by this review beyond the "Deliberately excluded"
  prose, and never its fence.

## Verdict

"No findings" is a legitimate verdict. Findings are phrased as assertions — what must
hold, and what in the diff does not — with the file and line. Local findings (a stale
README row, a missing `shell_scripts` entry, a test that passes vacuously) are fixed
here and listed as fixed. Anything structural — a design that departs from an item's
decision, a rule with two spellings — is a finding for the human, not a rework done
here.
