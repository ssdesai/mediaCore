# Feature plan trees

_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`. Edit the template, not this file._

Every feature this repo works on gets one directory here, named by its slug:

    plans/features/<slug>/
      README.md          the feature manifest — goal, plan table, exclusions, machine-readable JSON
      auto/{incomplete,inprogress,complete,failed}/     file-edit-only build plans (Bash disabled)
      verify/{incomplete,inprogress,complete,failed}/   post-build verification plans (Bash enabled)
      review/{incomplete,inprogress,complete,failed}/   post-verify diff review (Bash enabled)
      interactive/       bash-heavy steps run by hand, belonging to THIS feature
      NOTES.md           the architect's or implementer's rulings, deviations and resume commands
      CHECKPOINT.md      direct features only: the implementer's slice list and state, for a resume
      timing.jsonl       appended by the runners: batch, pass, plan, gate and PR instants
      planning.json      written later by the analysis tooling
      report.md / report.json

- `auto/` — build plans, run unattended by `../../agentTooling/run-plans.sh` with Bash
  disabled. Plans move through `incomplete/` → `inprogress/` → `complete/` or `failed/`
  as the runner works, each carrying a `.progress.md` log and a `.stream.jsonl` event
  stream.
- `verify/` — post-build verification plans, run unattended by
  `../../agentTooling/run-verify.sh` with Bash enabled, after this feature's auto plans
  finish. Same four-folder layout as `auto/`.
- `review/` — post-verify review plans, run unattended by
  `../../agentTooling/run-review.sh`, after this feature's verify plans finish. Same
  four-folder layout. Verify generates observations by *running* the work; review
  generates them by *reading the diff*, which is what catches the defects that leave
  every check green. Optional per feature — an empty queue is a clean no-op, so a
  feature authored before this queue existed still runs.
- `interactive/` — this feature's bash-heavy steps run by hand (migrations, one-off
  ops). Distinct from the top-level `../interactive/`, which holds standing runbooks
  that outlive any one feature (e.g. first-run setup).

The execution model itself — state folders, resume semantics, what the logs contain,
how to read a failure — is documented once in `../../agentTooling/RUNNER.md`, not
repeated per feature.

A feature built directly (`../../agentTooling/AGENT_DIRECT.md`, manifest `"method":
"direct"`) has no `auto/` or `verify/` plans: one implementer builds it, keeping
`CHECKPOINT.md` and `NOTES.md` current as it goes so a replacement can resume from
disk, and `review/` is its only queue.

**There is no separate archiving step.** The feature directory IS the archive: a
completed feature's `auto/complete/`, `verify/complete/` and `review/complete/` are its
permanent record, left in place. Nothing moves a finished feature elsewhere.

**The four state folders do not get their own `README.md`** — not per queue, not per
feature. Eight near-identical stubs (`auto/incomplete/README.md`,
`auto/complete/README.md`, and so on, repeated in every feature directory) would
document nothing this one file plus `RUNNER.md` doesn't already say. This README
documents the whole subtree shape once, for every feature that will ever exist here —
do not "fix" the apparent gap by adding one per folder.

To start a new feature, run `../../agentTooling/feature-start.sh <slug>` from the repo
root. It creates the feature's branch and worktree, writes this directory there from
`features/TEMPLATE.md` with the manifest's fence already filled, and commits it — see
`../../agentTooling/LIFECYCLE.md`. Then fill in the manifest's prose;
`../../agentTooling/AGENT_PLANS.md` → "The feature manifest" says what belongs in it.
