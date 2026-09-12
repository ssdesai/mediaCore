feature: agentTooling/claim-window-precision

# Rework one-shot brief — review escalations 1–5

## Where

Worktree `/Users/sahildesai/dev/agentTooling-claim-window-precision`, branch
`claim-window-precision`, base `shared-session-share`. The review pass has committed and
pushed (`34fbfee`, PR #36 open); you commit on top. Every command in absolute paths under
the worktree; never touch `/Users/sahildesai/dev/agentTooling`.

## Read, in this order

1. This file, then `AGENT_DIRECT.md` — the procedure and checkpoint rules apply unchanged.
2. `self/review-report.md` → **"Escalated to the next batch"**, items 1–5. That section is
   the spec; each item names the file, the line, the defect and the assertion.
3. `self/features/claim-window-precision/brief.md` → "The facts" — the test scaffolding,
   the two-place gate registration, bash 3.2, the do-nots. Not repeated here.
4. `self/features/claim-window-precision/NOTES.md` and `CHECKPOINT.md` — you append to the
   first (a `## Rework` section: rulings 12+, and the red-proof table for every assertion
   below) and rewrite the second whole.
5. `analysis/manifest.py`, `feature-close.sh` around the stamp, and the three tests the
   items name. Nothing else.

## Rulings (settled)

- **Item 3 — the exit code.** Give the *widen* refusal its own exit code in `manifest.py`,
  as a named constant. **Not 2** — argparse exits 2 on a usage error, and the close must
  not mistake a malformed invocation for a declined widen. Use 3. `feature-close.sh`
  tolerates exactly that code (warn, continue) and **refuses on any other non-zero**,
  with a message naming what `set-window-to` printed. The stamp now precedes the capture,
  so a refusal at the stamp must roll back the carry and the recovery exactly as the
  capture refusal does — call `rollback_carry` and `rollback_recovery` on that path.
  Assertion (`feature-lifecycle.sh`): a close over a manifest whose fence carries no `to`
  key refuses, and `git status --porcelain` in the primary is empty afterwards.
- **Item 4 — the `from` check.** `--tighten` refuses a bound at or before the fence's
  `from` (compared as instants, the same parsing the widen check uses; no `from` → no
  check), naming both, exit 1 (a plain failure, not the widen code — the close refuses on
  it, and it is unreachable from evidence: a branch-selected session starts at or after
  `from`, so its bound is strictly after). Assertion: refused, fence byte-identical.
- **Item 5 — a measurement of nothing.** When the outside cost is zero *and* the overrun
  is under a second, the warning keeps its old qualitative sentence and states that no
  billable response falls past `to`, rather than printing `$0.0000 and 0s`. Assertion
  (`session-share.sh`): a solo session whose only line past `to` is a non-billable user
  line (a `user_line` helper exists in `recover-duration.sh` — reuse or add it to
  `build-transcript.sh`) warns without a dollar figure.
- **Items 1 and 2** — exactly the reviewer's fixture lines: a subagent under W1's session
  with its last line at `13:00:00Z`, `to == 2026-06-01T13:00:01Z`; and W1's fixture
  timestamp `…:00.700Z` with W1b still expecting `…:01Z`. Two assertions, two mutations.

## Procedure

`AGENT_DIRECT.md` → "The procedure", with these specifics:

- Tests first, committed alone: `claim-window-precision: rework acceptance tests`.
- **Every assertion proved red against its mutation** (the review names the mutation for
  1 and 2; for 3, 4, 5 it is reverting your change). Record each in NOTES.md's rework
  table. An assertion that passes without its change is not written yet.
- READMEs: `self/tests/README.md` rows for the phases you extend; `analysis/README.md`
  for the exit code and the `from` refusal; `feature-close.sh`'s header for the
  stamp-refusal path.
- Gate to green (`bash self/gate.sh`, `all checks passed`, no SKIP). Commit as
  `claim-window-precision: rework — review escalations 1–5`, ending with

      Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
      Claude-Session: https://claude.ai/code/session_01VxZTtQTa3JKBocEpbdpg1Z

  Do not push. Never stop to ask. Report tersely: verdict line, files, per item the
  assertion and its mutation.
