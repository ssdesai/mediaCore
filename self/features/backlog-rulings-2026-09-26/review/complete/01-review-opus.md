# 01 — review: backlog-rulings-2026-09-26

## What the feature was supposed to do

Record the user's 2026-09-26 rulings on `self/BACKLOG.md`, and nothing else. It is a
documentation change made by hand. The rulings, entry by entry (identified by their bold
opening sentence):

| Entry | Ruling | Slug |
|---|---|---|
| vendored `agentTooling/.claude/settings.json` | remove the duplicate: stop tracking `.claude/settings.json`, generate it in `self/worktree-setup.sh` via `wire-settings.py --self --write`, gate checks it exists and matches | `self-settings-untracked` |
| two design points from the 2026-09-16 audit | per-feature budget: **no** (ruled out, so that half goes); `git stash list`: allow | `hook-pipe-redirect` |
| pipe into an interpreter followed by a redirect | build | `hook-pipe-redirect` |
| a start interrupted … blocks its own slug | build | `start-takeover` |
| annotated frozen report carries renderer drift | accept it (option a) — **entry removed** | — |
| `capture_planning.py` keeps its own `parse_manifest` | fold it in, with the pin-subagent work | `manifest-pin-subagent` |
| long-context tiered pricing | first report whether any used model has an above-200k tier; build only if so | `rates-tier-check` |
| propagation has no cost record | each propagation pull runs as its own `--method hand` feature | `propagation-as-feature` |
| unclaimed delegates in another repo | pin `abdc44b0d582d0b92` once `pin-subagent` ships; the two exploration delegates are routing overhead | — |
| **new:** OS sandbox for verify/review passes | moved from vinylCatalogue; build here first, after `self-settings-untracked`, then vendor | `runner-sandbox` |
| **new:** `manifest.py` has no `pin-subagent` | build first | `manifest-pin-subagent` |
| **new:** `ORCHESTRATION.md` doesn't name the wave shape | doc gap; one coordinator spawning delegates for a wave, never peer coordinators | — |

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expected:
`self/BACKLOG.md` and this feature's own directory under `self/features/`, nothing else.

## Contracts to hold it to

- Every entry above carries exactly the ruling in the table; no ruling invented or
  softened; no surviving entry's assertion or "Raised by" altered beyond the budget half
  the table rules out.
- The renderer-drift entry is gone and no other entry was removed.
- The moved sandbox entry reads correctly from agentTooling's own layout (paths relative
  to agentTooling, not `agentTooling/...`).
- No file outside `self/BACKLOG.md` and `self/features/backlog-rulings-2026-09-26/` changed.
- Fix a wording slip in place; escalate only a ruling that contradicts the table.

"No findings" is a legitimate verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
