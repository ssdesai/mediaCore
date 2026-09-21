# 02 — review: ledger-and-routing, round 2

Round 1 (`review/complete/01-review-opus.md`, report in the round-1 commit
`ledger-and-routing: review round 1`) judged every contract of the feature held and
fixed three stale docs in its pass. It escalated one finding, test-only:
`self/features/ledger-and-routing/escalations/01-review-opus.md` — nothing exercised
`sync-plans.sh`'s `migrate_routing` hook, the only path by which a consuming repo's
`plans/routing/` ever moves. The rework added a phase to `self/tests/sync-check.sh`.
This round reads only the commits after the round-1 commit; "no findings" is a
legitimate verdict. Begin your report with the `Verdict:` line the prompt asks for.

## What the rework was supposed to do

A `sync-check.sh` phase in a vendored scaffold asserting, per the escalation:

- `plans/routing/<id>.json` naming `a` and `b`, with `plans/features/a/` and
  `plans/features/b/` present: the write path leaves `plans/features/a/routing.json`
  and `plans/features/b/routing.json` equal to the legacy record, removes
  `plans/routing/`, and prints one `routing  moved …` line per move.
- A second write-path sync prints no `routing` line.
- `sync-plans.sh --check` over the same fixture leaves `plans/routing/<id>.json` in place.

No code change was expected. `self/tests/README.md`'s `sync-check.sh` entry names the
phase.

## Contracts to hold it to

- **The diff.** `git log --oneline` from the round-1 commit to HEAD shows the rework
  commit(s); `git diff <round-1 commit>...HEAD --stat` names `self/tests/sync-check.sh`,
  `self/tests/README.md`, and nothing else but this feature's own `NOTES.md`,
  `CHECKPOINT.md` or `timing.jsonl`. Any code file that moved is a finding.
- **Not vacuous.** The phase runs `sync-plans.sh`'s write path, not `routing.py
  --migrate` directly, and the features root the sync resolves is the one the
  assertion reads (`plans/features/`). Reason it through: with the `migrate_routing`
  call removed from `sync-plans.sh`, would the phase fail? With the call moved onto
  the `--check` path, would it fail? Both must be yes.
- **Exact wording.** The `routing  moved` line the test expects is the line
  `sync-plans.sh`/`routing.py` prints, matched by content and not by a loose grep for
  `routing`.
- **Idempotence and `--check`.** The second-sync and `--check` assertions are present
  and each compares the file tree, not only the output.
- **Green.** `bash self/tests/sync-check.sh` passes; `self/gate.sh`'s last line is
  `all checks passed`; every test round 1 relied on still passes (the gate runs them).
- **Style.** Bash 3.2; named constants; no chained `cd`; the phase follows the file's
  existing scaffold helpers and numbering.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the rework was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
