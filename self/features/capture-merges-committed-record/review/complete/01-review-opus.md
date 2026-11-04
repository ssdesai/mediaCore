# 01 — review: capture-merges-committed-record

## What the feature was supposed to do

The spec, from the coordinator's brief. `analysis/capture_planning.py` treated a committed
`planning.json` as a frozen record: `check_frozen_cost` listed every priced session or
subagent whose transcript the scan could not reach, and the capture REFUSED to write
unless `--carry-lost` (keep those rows, stamped `carried_from`) or `--force` was passed.
`feature-capture.sh` passed only `--recapture`. On a laptop an unreachable transcript meant
it had aged out or the capture ran from the wrong checkout; in a Claude Code cloud
container it is the normal case from round 2 on, because each round runs in a new
container and the previous container's transcript is gone — so every multi-round cloud
close refused and the human ran the capture by hand with `--carry-lost`
(`self/features/propagate-agenttooling-access/NOTES.md`, ruling 9).

Scope:

1. `capture_planning.py`: when a prior `planning.json` exists, merging is the default.
   Rows the scan can reach are re-priced from transcripts; rows it cannot reach are kept
   from the committed record, each marked `carried_from` with the date it was ORIGINALLY
   captured — an entry that already carries `carried_from` keeps that value rather than
   being re-stamped. The top-level `carried_from` is whatever is most useful for the
   report; the choice must be documented. A deliberately deselected session (a narrowed
   `session_window`, a corrected `branches`) is still reachable and is still dropped; a
   session reclassified as runner cost by a usage.json (`excluded_ids`) is still dropped.
2. The REFUSING path for lost rows goes away, keeping the one WARN naming the carried
   rows. `--force` stays as the explicit "throw the record away and rebuild from what this
   scan reaches" overwrite.
3. `--carry-lost` becomes an accepted no-op alias with a deprecation note in its help text,
   removed from the places that recommended it (refusal text, `analysis/README.md`,
   `feature-capture.sh` header comments, `LIFECYCLE.md`).
4. `feature-capture.sh`: step 4's refusal text and header comments no longer describe a
   hand `--carry-lost` step; the stamp rollback still fires only on a real refusal.
   `feature-close.sh` and `LIFECYCLE.md` steps 5/6 checked for the same.
5. `analysis/report.py`: when `planning.json` holds carried rows, one line in the report
   (stdout and `report.md`) saying how many rows and from which capture date(s).
6. READMEs updated (`analysis/README.md` for both scripts; root `README.md` rows for
   `feature-capture.sh`/`feature-close.sh`; the cloud design doc). Design reasoning in the
   feature's `NOTES.md`: why refusal was right on a laptop and wrong in the cloud, and
   why merge is safe on both.
7. Tests in `self/tests/`, wired into `self/gate.sh`: (a) prior record with an
   unreachable session → capture writes, keeps the row with its original `carried_from`,
   adds the reachable session, prints the WARN; (b) a row already carried once keeps its
   first `carried_from` after a second capture; (c) a deliberately deselected but
   reachable session is dropped; (d) `--force` rebuilds without the carried rows;
   (e) `report.py` prints the carried line.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Use the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The merge keeps only what cannot be seen.** Trace `capture_feature` from
  `check_frozen_cost` to the write: a reachable session deselected by the manifest is
  not in `lost` and is not carried; a session in `excluded_ids` is not carried; a row in
  `lost` is carried unless `--force`. No path refuses over a lost row any more, and the
  refusals that remain (nothing matched, a delegate another feature claims) are
  unchanged.
- **Provenance.** `carry_lost_entries` stamps a row with the prior record's `captured_at`
  only when the row has no `carried_from`; an existing stamp is kept. The top-level
  `carried_from` is the earliest stamp among carried session and subagent rows, present
  only when some row is carried, and `analysis/README.md`'s `planning.json` field list
  says so. Check that `priced[]` rows are carried beside their session/subagent rows and
  that the totals sum them (the test's A4/B7).
- **The carried rows reach the ledger.** `record_claims` and `record_session_claims` see
  the carried delegates and sessions (`agent_selected_by`, `session_selected_by`), as they
  did under `--carry-lost`.
- **`--carry-lost`** parses, is a no-op beyond implying `--recapture`, and its help says
  deprecated. The hook's `CAPTURE_WRITING_FLAGS` still lists it, correctly.
- **`report.py`**: `compute_carried` counts session and subagent entries (not `priced[]`
  rows), `carried` is in `report.json` only when non-empty (byte-identical reports for
  every record with none), `carried_line` appears once on stdout and once in `report.md`,
  and the field list in `analysis/README.md` names `carried{rows,captured_at[]}`.
- **`feature-capture.sh`** still rolls the stamp and the recovered sidecars back only when
  `capture_planning.py` exits non-zero; its header no longer describes a `--carry-lost`
  hand step. `feature-close.sh` needed no change — say so if you agree.
- **Docs agree with the code**: `analysis/README.md` (the capture entry's merge
  paragraph, the repair-tools paragraph, both field lists), root `README.md` rows,
  `LIFECYCLE.md` → Propagate, `AGENT_PLANS.md`'s `subagents` entry, the cloud design doc
  §12, `self/tests/README.md`. No remaining text recommends `--carry-lost` as a step.
  `NOTES.md` records the design reasoning the spec asked for.
- **Tests**: `self/tests/capture-merge.sh` covers (a)–(e) and the alias, is listed in
  `self/gate.sh`'s `shell_scripts` and `record`ed; `capture-guard.sh` phases 3, 8 and 13
  and `subagent-capture.sh` phases 5 and 15 now assert the merge instead of the refusal,
  and their header comments and README entries say so. Nothing is skipped or weakened to
  pass.
- `./self/gate.sh` is green.
- CONVENTIONS.md → Named constants for anything new (`CARRIED_KEY`, `CARRIED_LINE`).

"No findings" is a legitimate verdict.

## Verdict
