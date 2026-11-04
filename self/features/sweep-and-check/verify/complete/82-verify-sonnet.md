# 82 — verify

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`).

Read `self/gate-report.txt` first; do not re-run install, lint, tests or syntax checks.
If it shows failures, triage and fix those first, then re-run only the failing check.

Then read the three tests this batch wrote — `self/tests/check-plans.sh`,
`self/tests/sync-check.sh`, `self/tests/sweep.sh` — and phase 17 of
`self/tests/capture-guard.sh`, and check only what they leave uncovered:

- **The lint against the real corpus.** Run `./check-plans.sh --self <slug>` for every
  directory under `self/features/`. Features closed before this batch were never held
  to these rules; a FAIL on one of them is a finding to report with the label, not a
  defect to fix in the script — unless the script is wrong about a rule the doctrine
  actually states (`AGENT_PLANS.md` → "Plan file format"), in which case fix the script.
  `./check-plans.sh --self sweep-and-check` must pass.
- **`sync-plans.sh --check` against this checkout's own copies.** There is no `plans/`
  here, so run it in a scratch consumer: `git worktree add` is forbidden for this, but
  a `mktemp -d` holding a copy of `templates/` and the two scripts is not. Confirm the
  seeded `pr.sh` and `gate.sh` read `in-sync` at versions 2 and 2, and that a copy of
  `templates/plans/pr.sh` from `git show main:templates/plans/pr.sh` reads `DRIFT … 0 < 2`.
- **`run-batch.sh` still behaves under the older tests.** The gate ran
  `level-sentinel.sh`, `tiered-gates.sh` and `feature-lifecycle.sh`; if any is red, the
  cause is almost certainly plan 76's insertion in `run-batch.sh` — fix the insertion,
  not the tests.
- **`sweep.sh --self` on this checkout, dry.** It will capture nothing new (every
  closed feature is frozen) and must exit 0 with the done banner; its `--list-*` output
  is real data — read it, do not act on it.
- **`update.sh` refuses here.** Run `./update.sh` from this checkout: exit 1, "source
  checkout".

Fixes stay local: a wrong exit code, a mis-shaped output line, a README sentence that
contradicts a flag. Anything that needs a new function or a changed contract block is
reported for the next batch.
