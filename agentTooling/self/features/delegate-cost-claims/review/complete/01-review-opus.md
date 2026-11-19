# 01 — review: delegate-cost-claims

Review the diff of this feature's branch against `main`. The manifest
(`self/features/delegate-cost-claims/README.md`) states what it was supposed to do, and
`NOTES.md` beside it holds the rulings. Read the diff; do not re-run the gate — its report
is `self/gate-report.txt`.

## What the feature was supposed to do

1. **The close must not record a $0 build silently.** Before the PR, `feature-close.sh`
   asks `analysis/capture_planning.py --claim-check <slug>`. When the capture would claim
   no session and no subagent, but excluded sessions on the branch, or unclaimed sessions
   or delegates in the window, were met, the close stops — non-zero, no forge call,
   nothing written — naming each id and the exact `manifest.py … pin-session` /
   `pin-subagent` command. `--allow-unclaimed "<reason>"` lets it proceed and records the
   reason in the manifest fence (`allow_unclaimed`), from where the capture copies it into
   `planning.json` and `report.py` into the report's warnings. A claimed build behaves
   exactly as before. Local, cloud and `--self` layouts all go through the same check.
2. **Auto-claim during capture.** An unclaimed subagent whose brief's first line is
   `feature: <repo>/<slug>` naming the feature being captured is pinned through
   `manifest.py`'s own `pin-subagent` code path, using the unclaimed listing's matching
   rules and code; never one pinned to another feature, never on a partial or ambiguous
   match; the capture says so.
3. **The brief header as a rule**: CONVENTIONS.md → "Delegate briefs" (the rule and why);
   the hook sends back an `Agent` call whose prompt's first non-empty line is not a header,
   with the orchestrator-role deny intact; one specification (`analysis/README.md` → "The
   brief header") and one implementation (`hooks/brief_header.py`) shared by hook and
   capture.
4. A record repair: `ablation-harness-fixes` pins delegate `a93805d6e49ede750` and its
   re-captured record carries the build.

It excludes pinning any other delegate, changing the orchestrator-role deny, and passing
`--allow-unclaimed` from `run-batch.sh`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `LIFECYCLE.md` rules 1 and 3: a pin is written by `manifest.py`, never a hand edit of
  the fence; the close writes nothing and opens no PR when it refuses.
- The close's ordering (LIFECYCLE step 6): every refusal before the PR; the dirty manifest
  an auto-claim or `allow-unclaimed` leaves must be a cost record the close or capture
  commits. `--claim-check` must write nothing — check that no path in it reaches a write
  (ledger, manifest, `planning.json`).
- `capture_feature(dry_run=True)` must select exactly what the real capture selects; a
  drift between the two is a close that passes and a capture that records $0, or the
  reverse.
- The hook never exits non-zero; on `Agent` it never prints an allow; the guarded import
  leaves the rule silent where `brief_header.py` is absent; it still does not import
  `analysis/`.
- README field lists: the manifest fence and `planning.json` in `analysis/README.md` name
  `allow_unclaimed`; `hooks/README.md` lists `brief_header.py`; each new test is in
  `self/tests/README.md` and recorded by `self/gate.sh`; the README-index check holds.
- Named constants for every magic value (`CONVENTIONS.md` → "Named constants"); bash 3.2
  in the shell scripts (`self/PROJECT_FACTS.md`).

## Verdict

A verdict, and "no findings" is a legitimate one. Two lists: what you fixed in this pass
(local fixes), and what you escalate (structural). Phrase each finding as the assertion
that would catch it, so it can become a test.
