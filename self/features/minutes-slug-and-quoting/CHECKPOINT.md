# Checkpoint: minutes-slug-and-quoting

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-18T14:28:00Z
gate: `=== gate: done — all checks passed ===` (self/gate-report.txt VERDICT
      `all checks passed`, exit 0) — full tree: shell syntax, every self-test
      including the new `open session self-test`, python syntax, the byte-for-byte
      permission policy check, rate table, runner prerequisites; shellcheck not
      installed, no SKIPPED, no FAIL

One implementer, direct (`AGENT_DIRECT.md`), against
`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §1–§5 and the manifest's S1–S5.
S5b was paused for the coordinator and built to its ruling (`NOTES.md` 4 and 11).

## Slices
- [x] acceptance tests, RED first — `report-footnotes.sh` 15 red (S1, S4),
      `routing-record.sh` 3 red (S2), new `self/tests/open-session.sh` 4 red (S3),
      `allow-repo-commands.sh` 9 red (S5), `feature-lifecycle.sh` S5d–S5f 3 red;
      `self/gate.sh` registers the new file
- [x] 1. S1 — `report.py`: `attempt_copies` is the one per-attempt walk, shared by the
      cost and time roll-ups; `attempt_duration`/`plan_duration`/`PlanDuration` read it
      for the minutes; the two entry shapes gain their attempt counts
- [x] 2. S2 — `routing.slug_of_start_command` reads the start's own line
- [x] 3. S3 — both `open-session.sh` copies, two escaping layers, version 3,
      `TEMPLATE_VERSIONS` re-recorded
- [x] 4. S4 — `report.py`'s `write_record` writes only when the masked body differs
- [x] 5a. S5a — the opaque scan reads a path through `path_body`, so a `$` or a
      backtick inside single quotes is a literal. Deny → prompt only.
- [x] 5b. S5b — `git_location_args` on the approval side, three options, to the
      coordinator's five constraints (`NOTES.md` 11)
- [x] READMEs — `analysis/`, `hooks/`, `self/tests/`, `self/`, `templates/plans/`
- [x] `self/BACKLOG.md` minus exactly three entries; `NOTES.md` 11 rulings

## Learned
- `prior_attempt_cost`'s seat-and-merge loop is exactly "first copy with a figure wins
  per attempt", so the shared walk reproduces it without a behaviour change — the
  proof is `stale-failed-sidecars.sh` and `cost-recovery.sh` staying green untouched.
- `${text//$VAR/…}` silently does nothing when `$VAR` is a backslash: bash reads it as
  a pattern escape. The AppleScript patterns have to be literals (`NOTES.md` 8).
- The opaque scan never read `SHELL_ACTIVE_CHARS` at all; the quote bug was
  `word_body` stripping single quotes (`NOTES.md` 6).

## Resume
- Worktree `/Users/sahildesai/dev/agentTooling/.worktrees/minutes-slug-and-quoting`,
  branch `minutes-slug-and-quoting`, base `ledger-and-routing`.
- Tests: `bash self/tests/report-footnotes.sh`, `bash self/tests/routing-record.sh`,
  `bash self/tests/open-session.sh`, `bash self/tests/allow-repo-commands.sh`,
  `bash self/tests/feature-lifecycle.sh`, `bash self/tests/template-versions.sh`.
- Gate: `bash self/gate.sh` from the worktree; last line `all checks passed`.
- The fence pin in `self/features/minutes-slug-and-quoting/README.md` is the
  coordinator's and stays uncommitted.
- Not from here: `run-review.sh`, `feature-close.sh`, a push, a PR.
