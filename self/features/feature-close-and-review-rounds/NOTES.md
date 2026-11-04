# Notes — feature-close-and-review-rounds (slice A)

Rulings, deviations and open questions from the lifecycle half of this feature (slices A,
A1–A6 and C of the manifest). Slice B (`analysis/report.py`, `analysis/README.md`,
`self/tests/report-rounds.sh`) reports its own to the coordinator.

## Rulings

1. **The verdict constants live beside the one reader, in `plan-runner-roots.sh`.** The
   design puts `VERDICT_PREFIX` / `VERDICT_CLEAN` / `VERDICT_ESCALATED` /
   `VERDICT_UNREADABLE` in `run-review.sh` (§3), but §6 also requires ONE reader shared by
   the runner, the batch and the close. A reader in `plan-runner-roots.sh` with its
   constants in `run-review.sh` would leave the batch and the close reading a spelling
   they cannot see, so both moved to the roots file, which all three source.
   `run-review.sh` splices the same constants into the prompt that asks for the line.

2. **`plan_end` is deferred, not duplicated.** `verdict` and `head` both belong on the
   review plan's `plan_end`, but `head` is the sha of the commit the runner makes *after*
   `finalize_plan` already has the exit code. So `plan-runner-lib.sh` grew
   `PLAN_END_DEFERRED` / `hold_or_stamp_plan_end` / `flush_plan_end`: `run-review.sh` sets
   the flag, the lib holds the latest plan's stamp, and the runner flushes it with the two
   details after its commit. Exactly one `plan_end` per plan either way — a second plan
   finishing flushes the one before it, and the EXIT trap flushes whatever is still held,
   so an interrupted pass still records the plan that finished. The alternative, a second
   `plan_end` line carrying the verdict, would have left two lines per plan for
   `report.py` to disambiguate.

3. **`latest_review_plan` reads `review/complete/` and `review/failed/`; only
   `complete/` counts toward the round.** A review whose budget cap fired *after* it
   wrote its report is filed to `failed/` with a complete verdict (§3, "a complete report
   with a verdict is a verdict"), and reading only `complete/` would have made that round
   uncloseable. A review that failed for any other reason stamped no verdict at all, so
   the close still refuses it — on the verdict, which is the honest reason, rather than on
   the state directory. The round advances when a review *finishes judging*, so a
   re-scoped capped plan does not bump it.

4. **The close commits the review pass's trailing stamps as `<slug>: PR`, before
   `pr.sh`.** The runner's `plan_end` and `pass_end` are written after its own commit (see
   ruling 2), so the worktree is always dirty with `timing.jsonl` when the close starts.
   Left alone, `pr.sh`'s fallback `git add -A` would commit it under the old subject
   `<slug>: build, verify and review passes` — which is neither of the harness subjects the
   close's head check tolerates, so a second close run would refuse. Committing it here
   keeps pr.sh's fallback the no-op the design says it is (§3) and uses the `<slug>: PR`
   subject §5 reserves for exactly this.

5. **The close's pre-PR dirty check is its own, and deliberately looser than the
   capture's.** It refuses any dirty path outside the corpus's `features/` and `routing/`
   directories. Everything it refuses the capture refuses too, and the narrower cases (a
   non-record file *inside* the feature directory) are still caught by the capture at step
   3. Single-sourcing `feature-capture.sh`'s `stray_paths` would mean moving it out of
   that script, whose internals this slice may not touch — filed in `self/BACKLOG.md`.

6. **A refused capture skips the merge request and makes the close exit 1.** The capture
   stays advisory towards the PR (it is reported with the command that re-runs it, and the
   PR stays open), but not towards the merge: asking the forge to merge before the cost
   commit is pushed is the exact race this feature closes by ordering. The close therefore
   prints why it skipped the request and exits non-zero, so `run-batch.sh` reports the
   round as unfinished with the PR already open.

7. **`--no-push` is forwarded to the capture only.** `pr.sh` pushes as part of opening a
   PR — that is what makes a PR possible at all — so `feature-close.sh --no-push` means
   "do not push the cost commit", the same thing it means for `feature-capture.sh`.

8. **Every timing line carries `round`, as a string.** `stamp_timing` adds it from
   `TIMING_ROUND` when a caller fixed one for the pass (`run_all` does, at `pass_start`)
   and otherwise computes it fresh. `stamp-timing.sh` leaves it unset, so a by-hand
   checkpoint stamp during a rework reads the next round; `feature-close.sh` sets it to
   the completed count, the round that closed. A line written before this feature carries
   no `round` and is read as round 1 (`analysis/report.py`, slice B).

9. **`auto_merge` now says when it is off.** It is called only from `--merge-request`, so
   the silent `return 0` it had (as one of two callers on the open path) would have made
   the close's last step print nothing at all. `self/pr.sh` keeps `AUTO_MERGE=0` above the
   repo-specific marker, so the two copies still differ only in the header and that line.

10. **The close reads `pr.sh`'s `# template-version:` line.** A seeded copy below 4 has no
    `--merge-request` entry point; the close says so once, naming the version, and skips
    the request rather than falling back to the open path's old behaviour. No test covers
    that branch (both copies here are at 4) — filed in `self/BACKLOG.md`.

## Test notes

- The stub `claude` now writes the review report, since the verdict is what every new
  assertion turns on: `CLAUDE_REPORT_OUT` says where and `CLAUDE_REPORT_FIRST_LINE` what
  its first line is, empty for V3's report with no verdict.
- The stub `gh` remembers per branch that a PR was created (`GH_PR_DIR`), so X3's second
  close finds it already open the way a forge would, and records the origin branch's head
  at a `pr merge` (`GH_MERGE_HEAD_OUT`), which is how X2 asserts the cost commit was
  already pushed when the merge was requested.
- `self/tests/feature-lifecycle.sh` runs under `set -o pipefail`, so
  `git log … | grep -q …` fails the whole pipeline when `grep` exits on the first match and
  leaves `git` dead of SIGPIPE. The new assertions match the subject as a string instead.
- The batch sections (B1/B2) need `run-plans.sh` and `run-verify.sh` in the fixture; their
  queues are empty, which is a clean no-op, so what the batch exercises is the review pass
  and the branch after it. `check-plans.sh` is deliberately *not* copied — the lint is
  skipped when absent, and the fixture's corpus is not lint-clean.

## Slice B rulings (the Rounds table, `analysis/report.py`)

11. **No second arithmetic.** `compute_cost_rollup` / `compute_time_rollup` gained optional
    out-params collecting the per-plan figures they already compute, and `compute_rounds`
    partitions those; a round's dollars cannot drift from `cost.build`. Test 1c asserts
    the rows sum to `cost.build + cost.verify + cost.review`.
12. **A plan belongs to the round of its last `plan_start`/`plan_end` stamp.** A plan
    re-run in a later round has one sidecar summing every attempt; that figure describes
    the round it last ran in and is not splittable.
13. **A transcript-priced build (direct/hand) is attributed by its `checkpoint` stamps'
    round.** Exactly one distinct round → that round, unmarked. None or several → the
    whole figure sits in round 1 and the build column is marked in every row, with one
    footnote saying where it went; raised only when the feature has more than one round.
14. **Marking reuses `MISSING_FIGURE_MARK` / `bucket_mark` / `bucket_footnote_lines`**,
    keyed by column label. No new glyph.
15. **A stamp with no `round` is round 1**; an unreadable `round` warns and reads as 1.
16. **`verdict` is null when the review's `plan_end` carries none** — never `clean`.
    `escalations_file` is set only when the verdict is escalated/unreadable *and* the file
    exists; when it is missing the report warns that the rework has no brief.
17. **Before the first capture** (`--rounds-md` with no `planning.json`) the build column
    is marked with a footnote saying the capture has not frozen it yet.
18. **New keys are additive and defaulted**: `rounds` always written;
    `rounds_unpartitioned` only when non-empty; both read with defaults so an old
    `report.json` re-renders.

## Open questions, decided by the coordinator (2026-09-17)

- **A capped-after-report review stays in `failed/`.** The state directory records what
  happened to the run; the verdict records what the round decided. Ruling 3 already reads
  both. Moving the plan would erase the one fact the directory carries.
- **The close warns, and does not refuse, when `--rounds-md` fails.** The PR body is for
  the human and is advisory; the committed record is what `report.py` writes at capture,
  and that path is not the one that failed.
- **The backlog entry slice A drafted about a `VAR=value program` prefix was dropped.**
  The policy already rules it: `subcommand_allowed` refuses any assignment at command
  position, so `FOO=1 ls` prompts (`hooks/README.md` → "Considered and not a bypass").
  What the implementer saw was a prompt auto-approved by the session's permission mode,
  not an unruled shape.
