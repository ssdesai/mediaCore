# Checkpoint: session-start-precision

status: committed
updated: 2026-10-05T22:25:39Z
gate: not run (the coordinator's). Run one by one, all green: cloud-start.sh,
      self-settings.sh, gate-resume.sh, manifest-window.sh, session-share.sh,
      timestamps-are-utc.sh, check-plans.sh, feature-lifecycle.sh, sync-check.sh,
      template-versions.sh; check-plans.sh --self session-start-precision 14/14.

## Slices
- [x] acceptance tests — cloud-start.sh A2 + A6 (4 red on the old manifest.py),
      self-settings.sh F (F2-F4 red against origin/main's self/gate.sh, staged in scratch)
- [x] 1. manifest.py session-start: truncated to the millisecond (fence_instant,
      FENCE_INSTANT_TIMESPEC, FENCE_INSTANT_UTC_SUFFIX), docstrings, help
- [x] 2. feature-start.sh comments
- [x] 3. self/gate.sh record_fresh: RECORD_FRESH in the constants, header names the exception
- [x] 4. fence-`from` readers audited, none changed; check-plans.sh 7g/7h added
- [x] READMEs (analysis/, self/, self/tests/, root), NOTES.md, BACKLOG.md entry

## Learned
- `main` is not a local ref in the container; `origin/main` is.
- self-settings.sh stages self/gate.sh from the checkout, so a check "against main" is a
  scratch copy with origin/main's gate.sh (D2 fails there only for want of a .git).

## Resume
- Nothing to resume. Next: the coordinator's gate (./self/gate.sh), then the review.
