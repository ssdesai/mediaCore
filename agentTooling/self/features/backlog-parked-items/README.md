# backlog-parked-items: record the parked README/spec-structure items and loose harness items

Docs only. Adds entries to `self/BACKLOG.md` so the open items an orchestrator carried in a
session-only task list can be found by a later session. Eight entries (items 1–8) are the
README/spec-structure work the owner **parked on 2026-11-07** (not to be started without the
owner's word), under a lead sentence saying so, raised by `readme-structure`. Items 9, 12–15
are loose harness items, ordinary backlog, raised by the orchestrator's notes of 2026-11-07.
Items 10 (program-cell `--reset`) and 11 (a time budget between plans) were already entries and
are left as they are. Changes `self/BACKLOG.md` and this feature's own records only.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Round 1: the independent review of the hand build against this paragraph. |

## Deliberately excluded

- **Any consuming-repo fact the tree cannot show.** The entries about humanNetworkMap, musicMap,
  mediaCore and vinylCatalogue are phrased from the readme-structure record or as the
  orchestrator's note "as of 2026-11-07", not as verified state.
- **Duplicating items 10 and 11.** Both are already entries in `self/BACKLOG.md`.

## Machine-readable

```json
{
  "slug": "backlog-parked-items",
  "method": "direct",
  "plans": ["01-review-opus"],
  "branches": ["claude/backlog-parked-items"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "session_window": {"from": "2026-11-07T19:35:15.232Z", "to": "2026-11-07T20:00:00Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```
