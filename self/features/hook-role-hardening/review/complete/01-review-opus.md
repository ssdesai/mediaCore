# 01 — review: hook-role-hardening

Read the diff against the spec below, not against the builder's notes. "No findings" is a
legitimate verdict; say it outright if that is what you find (AGENT_PLANS.md → "Review
plans").

## What the feature was supposed to do

Four fixes from a security audit of PR #138 (coordinator cost records), plus one lifecycle
rule:

1. **F1 — an orchestrator cannot drop its role with one Edit.**
   - (a) `hooks/wire-settings.py` writes an `ask` rule for Edit (which Claude Code applies
     to Write too) on the orchestration-records folder in both layouts — the same way it
     already guards `hooks/**` — and the tracked `.claude/settings.json` is regenerated
     from it.
   - (b) `hooks/orchestrator_role.py` keeps treating a session as an orchestrator when a
     record that names it says `"kind": "coordinator"` but has an orchestrator's shape: a
     `features[]` entry carrying a non-null `session` or `branch`. A record whose EARLIER
     fence names the session as a role is a role too, so appending a later `{}` or
     coordinator fence no longer drops it. A genuine coordinator record (features carry
     `pr`/`report`, `session`/`branch` null — e.g. `self/orchestrations/ablation-wave/`)
     stays exempt, and `analysis/manifest.py --orchestration` refuses to write
     `session=`/`branch=` into a coordinator record so a real one cannot drift into the
     orchestrator shape.
2. **F2 — `orchestration-start.sh` validates `--session`** (and the
   `$CLAUDE_CODE_SESSION_ID` fallback) against `^[A-Za-z0-9_][A-Za-z0-9_-]*$` (at most 128 characters) before writing it into
   the JSON fence, refusing anything else.
3. **F4 — `invokes_build_script` in `hooks/allow-repo-commands.sh` is no longer fooled by
   a wrapper** (`env …`, `command …`, `env NAME=v …`, `nohup`, `exec -a x`,
   `/usr/bin/env`, quoting). The chosen design and its reason are in the feature's
   NOTES.md; the non-orchestrator verdicts must be unchanged.
4. **A security audit for hook changes, as a lifecycle rule.** When a feature's diff
   against its base touches the hook paths (`hooks/` and `.claude/settings.json` under
   `--self`; `agentTooling/hooks/` and `.claude/settings.json` in a consuming repo),
   `run-review.sh` queues an audit plan beside the review, the audit writes its own
   verdict, and `feature-close.sh` refuses to close until that audit came back clean on
   the tree the review judged. A diff that touches no hook path is unaffected.
   Documented in `LIFECYCLE.md` and `hooks/README.md`.

Excluded: `push_reading` in `allow-repo-commands.sh` and `analysis/report.py`'s default
root (another feature, `orchestration-record-fixes`, owns them).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/orchestrator_role.py` stays the ONE place the role rule lives; the hook and
  `plan-runner-roots.sh` both read it and must give the same answer.
- Its constants that mirror `analysis/roots.py` / `analysis/manifest.py` /
  `orchestration-start.sh` (record folder, `kind`, `coordinator`) move together.
- `.claude/settings.json` is byte-for-byte what `python3 -B hooks/wire-settings.py --self
  --repo . --write` generates (`self/gate.sh` checks it).
- The F4 change must not deny anything for a session that is no orchestrator.
- The audit's verdict line uses `plan-runner-roots.sh`'s `VERDICT_PREFIX`/`report_verdict`;
  `latest_review_plan` and `completed_review_count` must not count an audit plan as a
  review round.
- Tests: `self/tests/hook-orchestrator-role.sh`, `self/tests/coordinator-records.sh`,
  the settings check, and whatever new test holds the audit rule — both directions (a hook
  diff with no clean audit refuses the close; a non-hook diff closes as before).
- `hooks/README.md`, `LIFECYCLE.md`, `ORCHESTRATION.md` and any folder README the diff
  touches describe the new behaviour.

## Verdict

First line exactly `Verdict: clean` or `Verdict: escalated`, then the report.
