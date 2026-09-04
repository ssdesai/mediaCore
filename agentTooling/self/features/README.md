# Feature plan trees

Every agentTooling feature gets one directory here, named by its slug:

    self/features/<slug>/
      README.md          the feature manifest — goal, plan table, exclusions, machine-readable JSON
      auto/{incomplete,inprogress,complete,failed}/     file-edit-only build plans (Bash disabled)
      verify/{incomplete,inprogress,complete,failed}/   post-build verification plans (Bash enabled)
      review/{incomplete,inprogress,complete,failed}/   post-verify diff review (Bash enabled)
      interactive/       bash-heavy steps run by hand, belonging to THIS feature
      escalations/NN.md  written by a level's tier-1/tier-2 pass, never by hand
      planning.json      written later by analysis/capture_planning.py --self
      report.md / report.json

- `auto/` — build plans, run unattended by `../../run-plans.sh --self` with Bash
  disabled. Plans move through `incomplete/` → `inprogress/` → `complete/` or `failed/`
  as the runner works, each carrying a `.progress.md` log, a `.stream.jsonl` event
  stream, and a committed `.usage.json` cost sidecar.
- `verify/` — post-build verification plans, run unattended by `../../run-verify.sh
  --self` with Bash enabled, after this feature's auto plans finish. Same four-folder
  layout as `auto/`.
- `review/` — the post-verify pass, run by `../../run-review.sh --self`, reading the diff
  rather than running the work. Optional; an empty queue is a clean no-op.
- `interactive/` — this feature's bash-heavy steps run by hand. Distinct from the
  top-level `../interactive/`, which holds standing runbooks that outlive any one
  feature.
- `escalations/` — one `NN.md` per level whose gate stayed red, written by the tier ladder
  (`../../RUNNER.md` → "Red gates"). It records a contract the batch changed after
  authoring, which is why the review brief should name it. Not a queue; no state folders.

The execution model — state folders, resume semantics, what the logs contain, how to
read a failure — is documented once in `../../RUNNER.md`. The four state folders get no
README of their own, per feature or per queue; this file documents the shape once for
every feature that will ever exist here.

**There is no separate archiving step.** The feature directory IS the archive: a
completed feature's `auto/complete/` and `verify/complete/` are its permanent record.

To start a new feature, run `../../feature-start.sh --self <slug>`. It creates the
feature's branch and worktree, writes `self/features/<slug>/` there from
`../../templates/plans/features/TEMPLATE.md` with the manifest's fence already filled,
and commits it — see `../../LIFECYCLE.md`. Then fill in the manifest's prose;
`../../AGENT_PLANS.md` → "The feature manifest" says what belongs in it. The template is
shared with consuming repos even though the rest of this tree is not.

## Features

- `plan-analytics` — cost measurement and the `plans/features/<slug>/` restructure that
  made a feature addressable. Plans `48`–`58`. Built before `--self` existed, out of
  `vinylCatalogue`'s queue, and moved here afterward.
- `agenttooling-self-host` — `--self` mode itself, this tree, and the move above. Plans
  `59`–`64`. Also built out of `vinylCatalogue`'s queue, necessarily: it is what made
  self-hosting possible.
- `review-pass-and-cost-attribution` — `run-review.sh`, `run-batch.sh`, and the three
  accounting fixes a third queue exposed: a `review` cost bucket, `find_orphan_usage`,
  and `check_branch_overlap` testing whether windows *intersect* rather than whether
  they *exist*. **No plans** — every line was written interactively, so the manifest
  carries an empty `plans[]` and no `usage.json` anywhere. It also claims **no sessions**:
  its interactive sessions are already claimed by `discogs-field-reconciliation` in the
  host repo, and since a session is matched atomically they are listed in
  `exclude_sessions` rather than counted twice. Read its "Attribution honesty" section
  before using it as a model for anything — it is an honest zero, not a normal manifest.
- `test-first-levels` — level sentinels (`NN-gate.md`), the per-level gate label and
  `record_skip`, `run-verify.sh --up-to`, the `run-batch.sh` level loop, and the
  "Levels" doctrine. Plans `65`–`70`. The review's two escalations (reserve the pause
  code; a self-test) and the D3 revision from the first pilot were done by hand in the
  same PR — `self/tests/level-sentinel.sh`, `LEVEL_PAUSE_RC=64`, `skip_level_verify`.
- `killed-attempt-cost-recovery` — recovering a killed attempt's spend from its
  transcript, `pricing.py`'s two-sided intro window, and the tiered-gate wiring. Plans
  `01`–`09`, on branch `ssdesai/killed-attempt-cost-recovery`. **Carries the planning
  cost for `recovered-totals-stay-honest` as well** — see below.
- `recovered-totals-stay-honest` — the two ways a recovered total still reads as whole
  while missing spend, found by the feature above's own review. Plans `01`–`04`, shipped
  on that feature's branch and PR (#58). Its planning cost is **booked to the parent**:
  the branch carries exactly one planning session covering both features, and a session
  is matched atomically on its start, so it cannot be split. This feature's
  `session_window` chains off the parent's `to` and is expected to match nothing — a real
  `$0.00`, not a missed capture. Widening it back over the parent's window double-counts
  the session, which is what `check_branch_overlap` would then warn about.
- `feature-lifecycle` — the naming rule (branch `S`, worktree `<repo>-S`),
  `feature-start.sh` and `feature-close.sh`, session pins, the zero refusal, `pr.sh`
  without a review branch, `LIFECYCLE.md` and the prune, and the README index by
  category. Built by hand (`method: "hand"`) with four pinned delegates for the close
  script, the doctrine, one test fix, and a rework delegate; plan `72` is its review. The bootstrap: the
  first feature costed by the rule it introduces, with the building session claimed by
  pin because it began on `main`.
- `sweep-and-check` — the weekly cost sweep, a pre-run lint of a feature's plan corpus,
  drift detection for repo-owned files and the consumer update: four scripts (`check-plans.sh`,
  `sync-plans.sh`, `update.sh`, `sweep.sh`), the capture change that lifts the zero refusal on excluded
  sessions. Plans `73`–`83`. Built with the plans method, planned from the session pinned to
  `feature-lifecycle`.
- `tooling-backlog-2026-09` — nine small items that accumulated while the direct one-shot and the
  timing work landed and while three vinylCatalogue batches ran on the runners. None is large;
  together they are one direct one-shot, the first run of that method on this repo, with its own
  checkpoint doctrine applied to itself. Plan `71-review-opus`.
