# 109 — review: sweep-retirement-and-audit-fixes

Written before the build, from `self/DESIGN-2026-09-16-lifecycle-restructure.md` (§3.5,
§3.8, §4) and the `capture-on-branch` review's escalation
(`self/features/capture-on-branch/review/complete/107-review-opus.md` verdict — read it
from `self/review-report.md` on the base if the archived copy has been overwritten),
never from the implementer's report. "No findings" is a legitimate verdict. Fix local
drift in this pass; anything structural is an escalation. `run-review.sh` and
`feature-capture.sh` are escalate-only here — this pass is driven by the worktree's copy
of the former and ends by running the latter.

## What the feature was supposed to do

The last of the three lifecycle-restructure features: it deletes what the first two made
redundant and folds in the audit's small items. The base is `capture-on-branch` (stacked;
`FEATURE_BASE` in the manifest), so the diff to read is `git diff capture-on-branch...HEAD`.

1. **`sweep.sh` retired.** Every step is either historical or belongs to the capture:
   - the rates warning is already in capture's `warnings[]`;
   - `backfill_usage.py`, corpus-wide `recover_attempts.py` and `capture_planning.py --all`
     served features that predate runner-side usage capture and all have a `planning.json`
     now — they move to a **"Repair tools"** section of `analysis/README.md` with the
     `--all --recapture`, `--carry-lost` family, each with the one reason you would reach
     for it;
   - the frozen-record annotation (`also_claimed_by`) runs **at capture**, scoped to this
     repo's corpus (ledger read only, no transcript opened) and converges cross-repo on
     the other repo's next capture;
   - the residue — the corpus-wide unclaimed listing (sessions and delegates, routers
     excluded) and the rates-stale check — is **printed by `feature-capture.sh`** after
     its own report, informational, never a refusal.
   `sweep.sh` and `self/tests/sweep*.sh` (whatever tests drive it) are deleted; its rows
   in the root `README.md`, `self/PROJECT_FACTS.md` → Commands, `self/gate.sh`'s script
   list, `LIFECYCLE.md` step 7 (which becomes "Propagate": `update.sh` in each consumer)
   and `analysis/README.md` → "How to run them" (rewritten around per-feature capture)
   go with it. The shared-session machinery (ledger, split, `--recapture`, `--carry-lost`)
   is **kept** for the existing corpus.
2. **`report.py --all`** renders every feature that has a `planning.json` and no
   `report.json` — writing the missing `report.json`/`report.md` — and says how many it
   filled in.
3. **`check-plans.sh`** gains two lints: `session_window.to` is null or strictly after
   `from`; both bounds carry a zone (it already checks the zone — keep one check, extend
   it to ordering).
4. **`run-batch.sh`** runs `check-plans.sh` on an inferred slug too, once the build pass
   has resolved it (today `if [[ -n "$FEATURE_SLUG" && … ]]` skips the lint when no slug
   was given).
5. **`RUNNER.md`** review cap `$5.00` → `$7.00` in both places it is stated.
6. **The runner commits its own pass before the capture.** The `capture-on-branch` review
   escalated this: when `pr.sh` makes no commit (no `gh`, not authenticated, detached
   HEAD, or no `pr.sh` at all) the review pass's own files are still dirty and
   `feature-capture.sh` refuses them as stray, so every clean review in such a repo ends
   with "capture exited 1". Decided: `run-review.sh` commits the pass's output itself
   (`<slug>: build, verify and review passes`, the same subject `pr.sh` uses, so a
   consumer's seeded `pr.sh` then finds a clean tree and commits nothing) **before** it
   calls `pr.sh`, and only when on a branch that is not the base. `pr.sh`'s own commit
   stays as a no-op fallback for consumers whose runner has not updated. `pr.sh`'s
   contract comment and the root README's row say so.
7. **Missing assertion from that review:** `self/tests/feature-lifecycle.sh` P2b asserts
   the recorded `gh pr merge` call carries `--merge` and not `--squash`.
8. **Docs.** `LIFECYCLE.md` (six steps: route, start, brief, build, review + PR, merge;
   then "Propagate"), root `README.md` rows (`sweep.sh` → gone; `analysis/`, `run-review.sh`),
   `analysis/README.md` (cadence prose rewritten; repair tools), `self/PROJECT_FACTS.md`,
   `self/README.md`, `self/tests/README.md`, `RUNNER.md`, `ORCHESTRATION.md` wherever it
   mentions the weekly sweep, `templates/plans/README.md` if a stub names the sweep.

Not in this feature: the open items (per-feature budget, `git stash list`), anything in
`hooks/` (a parallel feature owns it), `pr.sh`'s body beyond the contract comment.

## The diff

Base is `capture-on-branch`. `git diff capture-on-branch...HEAD --stat`, then the full
diff. Expect: `sweep.sh` deleted, `feature-capture.sh` (residue listing, annotation at
capture), `analysis/{capture_planning,report}.py`, `check-plans.sh`, `run-batch.sh`,
`run-review.sh`, `RUNNER.md`, `LIFECYCLE.md`, the READMEs, `self/gate.sh`, `self/tests/`.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **`sweep.sh` is gone** and nothing references it: `grep -rn "sweep.sh"` over the tree
  finds only historical feature corpora under `self/features/`, `self/BACKLOG.md`, the
  design and triage records, and this feature's own directory.
- **Capture prints the residue.** In `feature-lifecycle.sh` (or `capture-from-worktree.sh`)
  with fixture transcripts: after a capture on the branch the output contains an unclaimed
  listing that includes a fixture `main` session with no `feature-start.sh` call, excludes
  a router fixture, and a rates line; neither a stale rates table nor an unclaimed session
  makes the capture exit non-zero.
- **Annotation at capture.** Two fixture features claiming one session; capturing the
  second annotates the first's frozen `planning.json` with `also_claimed_by` and changes
  nothing else in it (byte-compare the rest); the first's `report.json` is regenerated.
- **`report.py --all` fills gaps.** A fixture corpus with one feature holding
  `planning.json` and no `report.json`: after `--all`, `report.json` and `report.md`
  exist, the trend table has its row, and stdout says `1 report(s) written`.
- **`check-plans.sh` lints.** `to` before `from` → FAIL naming both; `to` null → ok; a
  bound with no zone → FAIL (existing).
- **`run-batch.sh` lints an inferred slug.** With one feature in the corpus and no slug
  argument, the batch output contains the `check-plans` banner and stops on a lint failure
  before any pass runs.
- **The runner commits its own pass.** With a stub `pr.sh` that exits 0 without committing
  (the `skip` path): a clean `run-review.sh` leaves a `<slug>: build, verify and review
  passes` commit on the branch, the capture then succeeds, and the worktree is clean. On
  the base branch itself the runner commits nothing (the existing `pr.sh` refusal still
  prints).
- **P2b** asserts `--merge` and no `--squash`.
- **`RUNNER.md`** contains no `$5.00` for the review cap.
- **Named constants** for every new message prefix, subject and lookback; bash 3.2;
  `set -uo pipefail`, no `set -e`; no chained `cd`; every python `-B`.
- **README Rule 2** on the `feature-capture.sh` row for the residue and the annotation
  (a ledger read, scoped to this corpus) and on `run-review.sh`'s row for the commit it
  now makes before `pr.sh`.
- **Every item above** is present or named in `NOTES.md` as a deliberate exclusion with a
  `self/BACKLOG.md` entry.

## Verdict

Write it as the PR body will read it: what the diff does, each contract above as
holds / fixed here / escalated, and the files touched by this pass.
