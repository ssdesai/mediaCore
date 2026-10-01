# 01 — review: manifest-pin-subagent

## What the feature was supposed to do

Close three `self/BACKLOG.md` entries (as they stand on base `backlog-rulings-2026-09-26`):

1. **`manifest.py` can pin a session but not a subagent.** Add
   `analysis/manifest.py [--self] <slug> pin-subagent <agent-id>`: appends the id to the
   fence's `subagents[]` once (a repeat is a no-op that writes nothing), refuses an empty or
   malformed id with the fence untouched, works in both the `--self` and the consuming-repo
   layouts, and a subsequent `feature-capture.sh` claims the pinned delegate. It becomes the
   only sanctioned writer of `subagents[]`.
2. **`capture_planning.py` keeps its own `parse_manifest`.** After the fold,
   `capture_planning.parse_manifest is routing.parse_manifest`, and
   `self/tests/session-claims.sh`'s counter still counts.
3. **`ORCHESTRATION.md` does not say which coordinator shape fits a wave.** It now names
   both: one feature → coordinate from its worktree; a wave → one coordinator spawning
   delegates and pinning each with `pin-subagent`, never peer coordinators via `--open`.

Every doc that tells a coordinator to pin a delegate in `subagents` (LIFECYCLE §4, the
manifest template's `subagents` bullet, `analysis/README.md`) names the command. The three
backlog entries are deleted; anything deliberately left unbuilt has a new entry.

## The diff

Base is `backlog-rulings-2026-09-26`. `git diff backlog-rulings-2026-09-26...HEAD --stat`,
then the full diff. Read `self/features/manifest-pin-subagent/NOTES.md` for the
implementer's rulings, but judge against this brief, not against the notes.

## Contracts to hold it to

- The id-shape check matches the agent ids `capture_planning.py --list-subagents` actually
  emits (e.g. `abdc44b0d582d0b92`); a real id is never refused.
- Idempotent, and a refusal writes nothing — check the tests assert the fence bytes, not
  just the exit code.
- `render_fence`/`last_fence` round-trip unchanged for every other key.
- The new test is wired into `self/gate.sh` and has its row in `self/tests/README.md`;
  `self/gate.sh` is green.
- A template change bumps its `template-version` if `self/tests/template-versions.sh`
  requires it, and consumers seeded from it are not broken.
- `ORCHESTRATION.md`'s addition is short, in the file's voice, and does not contradict
  LIFECYCLE §2's advice for a single feature.
- READMEs of every touched folder are current (CONVENTIONS "Keeping READMEs up to date").

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
