# Feature plan trees

Every agentTooling feature gets one directory here, named by its slug:

    self/features/<slug>/
      README.md          the feature manifest — goal, plan table, exclusions, machine-readable JSON
      auto/{incomplete,inprogress,complete,failed}/     file-edit-only build plans (Bash disabled)
      verify/{incomplete,inprogress,complete,failed}/   post-build verification plans (Bash enabled)
      review/{incomplete,inprogress,complete,failed}/   post-verify diff review (Bash enabled)
      interactive/       bash-heavy steps run by hand, belonging to THIS feature
      escalations/NN.md  written by a level's tier-1/tier-2 pass, never by hand
      escalations/<review-stem>.md  an escalated review's report, written by run-review.sh
      brief.md, NOTES.md, CHECKPOINT.md   a DIRECT feature's own record (../../AGENT_DIRECT.md)
      routing.json       the record of the router session that started this feature
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
  rather than running the work, and the end of a **round**: its verdict decides whether
  `../../feature-close.sh --self` may close the feature or whether the rework is round
  N+1. The round is the number of plans in `review/complete/` plus one, and every
  `timing.jsonl` line carries it. Optional; an empty queue is a clean no-op.
- `interactive/` — this feature's bash-heavy steps run by hand. Distinct from the
  top-level `../interactive/`, which holds standing runbooks that outlive any one
  feature.
- `routing.json` — the **router** that started this feature: the session that ran
  `../../feature-start.sh`, which writes this record from that session's own transcript
  and commits it in the `<slug>: start` commit, so the link is in git before the
  transcript can expire. `{ captured_at, cost_usd, duration_s, ended_at,
  features_started[{slug, at}], git_branch, launched_in, model, session_id, started_at }`;
  `../../analysis/README.md` → `routing.py` says what each field is derived from. A router
  is never pinned into a feature (`../../LIFECYCLE.md`, rule 1): its spend is routing
  overhead, reported per repo by `report.py --all`, never split across the features it
  opened — and a router that opened three features leaves this file in each of the three,
  identical but for how much of its own transcript had happened when each was written.
  Rewritten whole by `../../feature-capture.sh`'s refresh and committed with the cost
  records. Absent from a feature nobody started through the script. Records written before
  this rule sat in `self/routing/<session-id>.json`, one file every feature of one router
  shared; `routing.py --migrate` moved them here.
- `escalations/` — one `NN.md` per level whose gate stayed red, written by the tier ladder
  (`../../RUNNER.md` → "Red gates"). It records a contract the batch changed after
  authoring, which is why the review brief should name it. It also holds
  `<review-stem>.md`, the report of a review round that came back escalated or unreadable,
  copied there by `../../run-review.sh`: that file **is** the rework brief for the next
  round, one file with one writer. Not a queue; no state folders.

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

The plan numbers quoted below for features started before `lifecycle-records-and-numbering`
were issued under this corpus's retired shared sequence (`../PROJECT_FACTS.md`); every
feature since numbers its own plans from `01`, per `../../AGENT_PLANS.md` → "Plan file
format".

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
- `stale-failed-sidecars` — a plan killed at a usage limit and retried by hand leaves a
  `.progress.md` + `.usage.json` pair in `<queue>/failed/` with no `.md` beside it, which
  crashed `analysis/report.py` reading a sibling plan file the retry had moved away. The
  pair stays where the runner put it — it is the only surviving copy of the killed
  attempt's session id — and the analysis absorbs it: `build_usage_index` ranks the two
  sidecars claiming the stem and returns the loser as a prior attempt whose dollars are
  rolled in once. Built direct (`method: "direct"`); plan `84-review-opus` is its review.
  It also created `../BACKLOG.md` and its first four entries.
- `stream-capture-file-first` — nine merged reviews were recorded at `$0.00` with 0-byte
  progress logs although every one of them ran to completion: the runner captured the
  event stream with a `tee` in the *middle* of a pipeline whose last stage wrote to the
  caller's stdout, so a consumer that stopped reading killed the capture from the far end
  backwards while `claude` ran on to a clean exit. `claude` now writes `.stream.jsonl`
  itself and a follower feeds the progress FIFO and the display from that file, so nothing
  downstream of the record can reach it; the runner survives a closed stdout instead of
  dying on its next `echo`; and `rc == 0` with no `result` event in the stream — the one
  combination that is never normal — is warned about by name. Built direct
  (`method: "direct"`); plan `86-review-opus` is its review. It adds
  `../tests/stream-capture.sh` and one `../BACKLOG.md` entry (`run-batch.sh` still dies of
  SIGPIPE on a closed stdout), and deletes the entry `recover-cost-at-close` raised for
  the defect this feature fixes.
- `claim-window-precision` — the four entries `shared-session-share` left in
  `../BACKLOG.md`, closed together. `feature-close.sh` stamps `session_window.to` from
  evidence (one second past the last instant of the sessions the feature's branches and
  window select, and of their subagents) and stamps it **before** the capture, so the
  share split runs against the real bound instead of against the close's own clock —
  which is what made four features started from one coordinator nest inside each other
  and keep drawing an equal share of it for hours; `--recapture` re-derives the evidence
  and may only *tighten* an existing bound. Beside that: the `may span the window
  boundary` warning now says how many dollars and seconds lie outside and whether they
  were counted, the `predates the share rule` repair warning fires on every sweep rather
  than only on the one that changed something, and the claimant scan is indexed once per
  capture instead of once per selected session. Built direct (`method: "direct"`); plan
  `97-review-opus` is its review. It removes four `../BACKLOG.md` entries and adds one
  (an in-flight co-claimant's `to` is still unbounded in this feature's split), and adds
  no test file — every assertion lands in `../tests/feature-lifecycle.sh` (W),
  `../tests/session-share.sh` (12-13) and `../tests/session-claims.sh` (7d-7f, 9).
- `sweep-retirement-and-audit-fixes` — the last of the three lifecycle-restructure
  features (`../DESIGN-2026-09-16-lifecycle-restructure.md` §3.5, §3.8), stacked on
  `capture-on-branch`. With the capture running on the branch, the weekly `sweep.sh` had
  nothing left that was not either historical or a step of a capture, so it is **deleted**:
  its repair tools become `../../analysis/README.md` → "Repair tools", its frozen-record
  annotation becomes `capture_planning.py --annotate-frozen` run by `feature-capture.sh`,
  and its unclaimed-session and stale-rates listing becomes that script's residue output —
  informational, never a refusal. With it ride the audit's small items (`report.py --all`
  writes the reports that were missing, `check-plans.sh` lints window ordering,
  `run-batch.sh` lints an inferred slug, `RUNNER.md`'s review cap reads `$7.00`) and the
  `capture-on-branch` review's escalation: `run-review.sh` commits its own pass under
  `pr.sh`'s subject before calling it, so a capture no longer refuses the pass's own files
  where no forge is logged in. Built direct (`method: "direct"`), resumed once after a
  usage limit; plan `109-review-opus` is its review. It adds `../tests/audit-fixes.sh`,
  deletes `../tests/sweep.sh`, and adds three `../BACKLOG.md` entries.
- `feature-close-and-review-rounds` — the review pass ended in a verdict with two
  outcomes and the runner acted on it as if it had one, so a rework after an escalated
  review happened outside every gate (measured on PR #46: stale PR body, record replaced
  by hand, no second review, no round in the timing file). Now **a feature is a sequence
  of rounds and the close is the only way out**
  (`../DESIGN-2026-09-17-close-and-review-rounds.md`): `run-review.sh` reads the report's
  first line (`Verdict: clean` / `Verdict: escalated`, `unreadable` failing closed),
  commits its pass as `<slug>: review round N`, stamps that round's `verdict` and the
  `head` it judged, and stops — an escalated round's report becomes the rework brief at
  `escalations/<review-stem>.md` and the rework is round N+1. `feature-close.sh` is a real
  script again: it refuses anything but the tree a clean review judged, then opens the PR
  (the report plus the report's Rounds table), stamps it, captures on the branch, and asks
  for the merge **last** — which closes the `PR_AUTO_MERGE` race by ordering and takes
  `templates/plans/pr.sh` and `self/pr.sh` to `template-version: 4` with a
  `--merge-request` entry point. Every stamp carries its `round`, and `report.py` grows a
  Rounds table. Built direct (`method: "direct"`) as two parallel slices — the lifecycle
  and the report — with plan `110-review-opus` as its review. It adds no test file: the
  lifecycle assertions land in `../tests/feature-lifecycle.sh` (V1–V3, X1–X3, RD, B1/B2
  and the rewritten T3/T4/T5/P2), the report's in `../tests/report-rounds.sh`. It removes
  the `PR_AUTO_MERGE` entry from `../BACKLOG.md` and adds three, and is the first feature
  closed by its own script.
- `hook-special-params` — `VAR_USE_RE` in `../../hooks/allow-repo-commands.sh` matched only
  `[A-Za-z_][A-Za-z0-9_]*`, so a command carrying `$?`, `$$`, `$1` or any other special or
  positional parameter fell through the rewrite layer and reached the human as a silent
  prompt. The pattern now admits them; three suite cases that pinned other exemptions with
  a `"$0"` — and passed only because it fell through — use a literal path instead. Built by
  hand (`method: "hand"`) by the session that started it, pinned; plan `01-review-opus` is
  its review.
