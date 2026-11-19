# 02 — re-review: python-entry-exact (round 2)

Round 1's review (`self/features/python-entry-exact/escalations/01-review-opus.md`) found the
fix correct and escalated two items. This pass checks that both are resolved, and that the
rework changed nothing else. Say "no findings" when there are none: that is a legitimate
verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the opening paragraph of `self/features/python-entry-exact/README.md` and its
"Deliberately excluded" list. Read it first. `NOTES.md` is the builder's record — check its
round-2 rulings (11, 12) and its "Not changed" and "Pre-existing findings" sections against
the diff, not the other way round.

## The diff

Base is `main`. Run `git fetch origin main`, then `git diff origin/main...HEAD --stat` for the
whole feature, and for this round's rework the diff since round 1's judged head:
`git log --oneline origin/main..HEAD` names the commit `python-entry-exact: review round 1`;
`git diff <that sha>..HEAD` is the rework (plus the `review stamps` commit's `timing.jsonl`).

## Contracts to hold it to

- **Escalation 1 is resolved.** `self/tests/manifest-window.sh` M9 asserts, at run time,
  that `manifest.py` (both its parsers), `capture_planning.py` and `report.py` refuse an
  abbreviated option with exit 2 and argparse's "unrecognized arguments" — and each row
  would fail if `allow_abbrev=False` were removed from the parser it exercises (check that
  the abbreviation each row uses is a unique prefix of a real option of that parser). The
  rows write nothing outside the test's sandbox: the `capture_planning.py`/`report.py` rows
  run the checkout's own scripts, so confirm argparse refuses them before any root is
  resolved or file touched.
- **Escalation 2 is resolved.** `hooks/README.md` → "Cross-layer dependencies", the bullet on
  the approved forms restating their parsers, says what a renamed option does: the hook
  still approves the old word and argparse refuses it — a usage error, never a write.
- `self/tests/README.md`'s `manifest-window.sh` entry and that file's header list M9.
- The rework touches no hook code (`hooks/allow-repo-commands.sh`) and no analysis script;
  everything round 1 judged stays as it was.
- The gate (`self/gate.sh`) is green on this tree: `self/gate-report.txt` says so, and the
  review does not re-run it. `bash self/tests/manifest-window.sh` alone is cheap and may be
  run.
- NOTES.md's pre-existing finding (the orchestrator `report.py` row's `.match`) is identical
  on `origin/main` and untouched by the diff.

## Verdict

The first line of `self/review-report.md` is `Verdict: clean` or `Verdict: escalated`.
