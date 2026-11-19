# 02 — review: consumer-record-guard (round 2)

Round 2 re-reviews the whole feature, not only the rework. Read the diff against the
contracts below. "No findings" is a legitimate verdict.

## What the feature was supposed to do

When agentTooling is vendored into a consuming repo, no orchestration-record tool may write
under the vendored `agentTooling/self/orchestrations/`, `--self` included. That covers:

- `orchestration-start.sh`, both the orchestrator and the coordinator kind;
- the writes of `manifest.py --orchestration`: `add-feature`, `set-feature` and
  `set-window-to`;
- `orchestration-capture.sh` and the `orchestration_capture.py` it runs;
- `report.py --orchestration`.

Each one refuses before it writes anything, and the refusal names
`plans/orchestrations/<slug>/` as the place for the record.

These must not change:

- `--self` writes in agentTooling's own standalone checkout;
- a shipped record in a vendored copy still reads with `--self`: `manifest.py … get`, the
  role hook, the coordinator advisory;
- the behaviour of a consumer's runs without `--self`.

The tests sit under `self/tests/`. The docs that must state the refusal are `LIFECYCLE.md` →
"Orchestration records", `analysis/README.md`, and the README of every folder the feature
touched.

The round-1 review escalated two findings
(`self/features/consumer-record-guard/escalations/01-review-opus.md`):

1. **The advisory gave a command that is now refused.** `analysis/coordinator_check.py`
   worded its command as `orchestration-start.sh --self …` whenever the start ran under
   `--self`, including from a vendored copy, where that command is now refused. It must name
   `--self` only where the start may write, decided through the same `roots` classifier. Its
   R9 test in `orchestration-records-in-repo.sh` must assert that.
2. **No test showed the advisory still reads a shipped record.**
   `self/tests/consumer-record-guard.sh` C3 must assert it.

Round 2 claims to fix both: ruling 6 and ruling 7 in `NOTES.md`.

Out of scope:

- the Edit tool writing under a vendored `self/orchestrations/` (a consumer's settings
  already ask first);
- `feature-start.sh --orchestration`, which writes a manifest key, not a record;
- `feature-close.sh` and the "file before close" rule, which belong to a sibling feature.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **One classifier.** `analysis/roots.py` decides whether this is a vendored copy, through
  `is_standalone_checkout`. `self_record_write_allowed` exposes that answer, and
  `record_write_refusal` and `coordinator_check.py` both ask it. The shell start asks the
  same decision through `roots.py self-write <slug>`. No second `.git` probe and no path
  comparison is added.
- **Refusal before any write.**
  - A refused run leaves both record roots and the ledger byte-identical.
  - It exits 1.
  - Every tool prints the same text, `VENDORED_SELF_WRITE_REFUSAL`.
  - The shell start also refuses when `roots.py` cannot be asked: it fails closed.
- **Reads are not writes.** `manifest.py --self --orchestration <slug> get`,
  `hooks/orchestrator_role.py` and `analysis/coordinator_check.py` still read a shipped
  record in a vendored copy.
- **The advisory's wording.** It names `--self` only in a standalone checkout.
  - From a vendored copy, its command must not be one the start refuses there.
  - Asserted by `orchestration-records-in-repo.sh` R9.
- **Standalone `--self` is unchanged.** `orchestration-records.sh` and
  `coordinator-records.sh` pass.
- **Fixtures.**
  - The one fixture that broke, `orchestrator-role.sh` G10, now copies `analysis/roots.py`.
  - The copy rule is written down in `self/PROJECT_FACTS.md` and `self/tests/README.md`.
- **Tests assert behaviour** by running the real scripts. "Wrote nothing" is shown by
  comparing snapshots taken before and after.
- **Docs agree with the code.** `LIFECYCLE.md`, `analysis/README.md`,
  `self/tests/README.md`, `self/orchestrations/README.md`, the root `README.md`,
  `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md` and `NOTES.md`.
- **Code conventions.** Named constants for new literals. bash 3.2 and
  `set -uo pipefail`.
- **The gate.** `./self/gate.sh` is green.

## Verdict
