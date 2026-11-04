# 02 — review: capture-merges-committed-record, round 2

## What the feature was supposed to do

Round 1's review (`escalations/01-review-opus.md`) judged the feature — the merge into
the committed `planning.json` by default, the provenance rules, the report line, the
docs and the tests — complete, and escalated one finding, tests only: the brief's
contract "the carried rows reach the ledger" had no assertion. The line
`analysis/capture_planning.py` adds for it passes each carried session's own
`selected_by` into `session_selected_by`, so a carried *pinned* session is ledgered as
`pinned` where it used to fall back to `branch`, and nothing tested that.

The rework, from that escalation, changed tests and their records only:

- `self/tests/capture-merge.sh`: `write_manifest` takes a `sessions` pin list; a
  `session_claims` reader over the fake `$HOME`'s `~/.claude/subagent-claims.json`
  `sessions` section; **A7/A7b** assert phase A's carried branch-selected row and the
  re-priced row are both claimed under this slug as `branch`; new phase **G** pins a
  session launched on `main` (only the pin selects it), captures, removes its transcript,
  recaptures, and asserts the carried row and its ledger claim both say `pinned` while
  the re-priced branch session's claim says `branch`.
- `self/tests/subagent-capture.sh`: the `LEDGER`/`REPO_NAME`/`claim` definitions moved up
  with the helpers (phase 11's comment points there) and a `session_claims` reader added;
  **5c2** asserts the carried delegate's claim still names this feature as `parent`;
  **15f** asserts the carried session's claim as `branch`.
- `self/tests/README.md` entries, `NOTES.md` ruling 12 (and a tightening of ruling 3 to
  match the sentence round 1 corrected in `analysis/README.md`), this feature's README
  plan table and `plans`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Round 1's commits are in it;
the round-2 rework is the commits after `capture-merges-committed-record: review stamps`
(`git log --oneline origin/main..HEAD`), so read those first and the rest as context.
Use the local `main` only when there is no `origin`.

## Contracts to hold it to

- **The escalation is answered, exactly.** A carried session's ledger claim carries the
  `selected_by` of its carried row; a pinned one reads `pinned` (capture-merge G2) — a
  value the old `branch` fallback could not produce — and a branch-selected one reads
  `branch` (A7, subagent-capture 15f); a carried delegate's claim still names this
  feature (subagent-capture 5c2). Each assertion reads the ledger file under the fake
  `$HOME`, never the real one (`self/tests/README.md`'s first rule).
- **Tests only.** No file under `analysis/`, no shell script outside `self/tests/`, and
  no doc outside `self/tests/README.md` and this feature's directory changed in the
  rework. If anything else did, that is a finding.
- **The assertions discriminate.** G0 proves the pin selects the session before it is
  lost (`selected_by: pinned` on a reachable row), so G1/G2 cannot pass vacuously on a
  branch-selected row; the `session_claims` reader fails loudly on a ledger with no
  `sessions` section rather than printing an empty list.
- **Helper move is behaviour-neutral.** `subagent-capture.sh` still passes end to end,
  phase 11 unchanged in what it asserts; moving `REPO_NAME` and `claim` above phase 1
  changed no fixture.
- **Records.** `self/tests/README.md` describes A7, G, 5c2 and 15f; `NOTES.md` ruling 12
  records the round; the manifest's `plans` lists `02-review-sonnet` and the README's
  plan table has its row.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict
