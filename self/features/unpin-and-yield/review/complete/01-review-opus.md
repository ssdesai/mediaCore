# 01 — review: unpin-and-yield

Written from the spec before the build. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Read `self/features/unpin-and-yield/README.md` → "The spec" in full; it is the
contract. In short:

1. `analysis/manifest.py` gains `unpin-session`, `unpin-subagent` and
   `unexclude-subagent`, each removing one id from `sessions[]`, `subagents[]` or
   `exclude_subagents[]`, the exact inverse of its twin: same argument order, same
   output shape, same id validation, absent id a no-op, nothing else in the file moved,
   and the frozen-record note when `planning.json` exists.
2. `analysis/capture_planning.py`: a **parent-selected** delegate that **another
   feature pins** yields — skipped and recorded in `planning.json`'s
   `yielded_agent_ids` (`{ agent_id, to }`). "Pins" is the union of manifests in this
   corpus under the primary and every `.worktrees/*/` checkout (not this slug's own), and
   ledger claims by another `(repo, slug)` with `selected_by: "pinned"`. This feature's
   own pin and `exclude_subagents` behave exactly as before. `check_claims`'
   pin-over-parent refusal names the other feature and its recapture.
3. Docs: `analysis/README.md` (manifest.py entry, subagent routes, `planning.json`
   field list), `templates/plans/features/TEMPLATE.md`, `self/tests/README.md`, and
   `ORCHESTRATION.md` / `LIFECYCLE.md` only where they said to hand-edit
   `exclude_subagents` or that a pin cannot come out.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- **Removers are inverses.** Run each pin/unpin pair on a scratch manifest and confirm
  the file returns byte-identical. A remover that reformats any other fence line, or
  writes on a no-op, is a finding.
- **Validation parity.** `unpin-subagent` / `unexclude-subagent` refuse exactly what
  `pin-subagent` refuses, via the same `AGENT_ID_RE` and message — not a copy of the
  regex.
- **Yield is only for parent selection.** Read the subagent loop: the pin arm and the
  `exclude_subagents` arm must come before the yield check and be unchanged. A yield that
  can drop a delegate this feature itself pins, or that fires for a pinned *session*, is
  a finding.
- **Only a pin outranks.** A ledger claim with `selected_by: "parent"` must not cause a
  yield (two parent selections are the double-claim refusal's business). Check the
  ledger read compares `(repo, slug)` and `selected_by`, not slug alone.
- **Worktree scan.** The other-manifest scan must reach `<primary>/.worktrees/*/<corpus
  rel>/*/README.md` through the existing primary resolution in `roots`, and must still
  work when the capture runs from a worktree's copy of the script (`capture-from-worktree.sh`
  is the existing shape). It must not read a manifest from the other corpus as a pin
  (`self/features` vs `plans/features`).
- **Record shape.** `yielded_agent_ids` is present always (`[]` when none), sorted, and
  listed in `analysis/README.md`'s `planning.json` field list. `report.py` must not
  break on records that lack it.
- **Frozen guard.** A recapture that newly yields a delegate must not trip
  `check_frozen_cost` as "lost"; a test must cover it if the code path differs from the
  dropped-cross-repo-pin case.
- **Tests exist for Y1–Y7** and the remover cases in the spec, and fail without the
  change (spot-check one by reading the assertion, not by reverting).
- **Docs match code.** Subcommand count, names, output strings and the field list in
  `analysis/README.md` agree with `manifest.py` and `capture_planning.py`.
- `./self/gate.sh` green.

## Verdict

First line of `self/review-report.md` must be `Verdict: clean` or `Verdict: escalated`.
Fix local defects in place (a wrong message, a missed doc line, a missing assertion);
escalate a structural one (the yield fires in the wrong arm, the scan misses worktrees,
a remover can corrupt a fence).
