# Checkpoint: lifecycle-records-and-numbering (round 2)

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-18T03:57:08Z
commit: 406a551 "lifecycle-records-and-numbering: round 2 — stray_paths fails closed"
gate: `all checks passed` (self/gate-report.txt VERDICT, exit 0) — full tree, all shell
      syntax, level-sentinel self-tests including `verdict readers self-test`, python
      syntax, permission policy, rate table, runner prerequisites; shellcheck skipped
      (not installed), no other SKIPPED, no FAIL

## Slices
- [x] acceptance tests — `self/tests/verdict-readers.sh`'s new "stray reader" phase
      (S1-S6): verified RED against the pre-round-2 `stray_paths` (S2 failed — `set -u`
      killed the subshell with a bare "unbound variable", naming no function), then
      restored and reconfirmed GREEN against the fix below.
- [x] 1. `plan-runner-roots.sh` — `STRAY_UNJUDGED_RC=2`; `stray_paths` checks
      `FEATURE_REL`/`FEATURES_REL`/`ROUTING_REL`/`STRAY_SLUG` with `${X:-}` before its
      loop, names the missing one(s) and `stray_labels` on stderr, returns
      `STRAY_UNJUDGED_RC`; rewrote the function's header comment to state the return-code
      contract
- [x] 2. the three call sites — `feature-capture.sh` (pre-run, pre-commit) and
      `feature-close.sh` (pre-PR) — all now `if ! STRAY="$(stray_paths …)"; then refuse
      …; fi`, `-n "$STRAY"` branch unchanged after it
- [x] 3. docs — root `README.md`'s `plan-runner-roots.sh` row, `self/tests/README.md`'s
      `verdict-readers.sh` entry; `LIFECYCLE.md` left alone (no sentence there describes
      the check's own failure, only what it refuses on)
- [x] 4. `NOTES.md` ruling 21 under `## Round 2`
- [x] gate: `bash self/gate.sh` to green
- [x] commit — 406a551, files named explicitly; the coordinator's uncommitted
      `review/incomplete/02-review-sonnet.md` and this feature's manifest fence left
      untouched, as briefed

## Learned
- The pre-round-2 `stray_paths` already returned 0 on every SUCCESSFUL run (bash's
  `while … done <<<"$1"` loop reports the last body command's status, not the failing
  `read`'s, when the loop runs at least once — confirmed empirically). The bug was never
  in the success path's return value; it was `set -u` killing the subshell on a missing
  global before the loop ever ran, silently, with no return-code contract at all for a
  caller to check.
- `stray_labels` needs `REPO_DIR` and `FEATURES_LABEL` (not just the four globals it
  sets) to derive its output — `verdict-readers.sh` never calls `resolve_roots`, so the
  stray-reader phase sets those two by hand for a `--self`-shaped checkout
  (`REPO_DIR="$TMP/checkout"`, `FEATURES_LABEL="self/features"`) before calling
  `stray_labels x "$TMP/checkout"`, rather than hand-setting the four derived globals.

## Resume
- Worktree `/Users/sahildesai/dev/agentTooling/.worktrees/lifecycle-records-and-numbering`,
  branch `lifecycle-records-and-numbering`, base `main`.
- `bash self/tests/verdict-readers.sh` is the test this round touched; all 22 assertions
  pass against the fix.
- Gate: `bash self/gate.sh` from the worktree; every check must be `ok`.
- Do not touch `self/features/lifecycle-records-and-numbering/review/incomplete/` or the
  manifest's fence in this feature's `README.md` — the coordinator's, uncommitted, not
  this round's.
