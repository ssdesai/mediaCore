# Backlog: unclaimed delegates

This feature adds two `self/BACKLOG.md` entries for the unclaimed delegates that
`litellm-pricing`'s capture reported on 2026-09-23. The first is the design gap: propagation
(subtree pulls into the consuming repos) has no cost record. The second covers three
delegates that belong elsewhere: the vinylCatalogue `audio-checked-mark` implementer, and
two exploration delegates. The work was done by hand, and changes nothing but the backlog.

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md` | Checks the two entries' facts and format — round 1, clean |
| `review/complete/02-review-sonnet.md` | Round 2: the merge of `origin/main` (PR #62, litellm-pricing) only |

## Deliberately excluded

- **Building the propagation record, or pinning the delegates.** Each is its own work,
  and that is exactly what the entries describe.

## Machine-readable

```json
{
  "slug": "backlog-unclaimed-delegates",
  "method": "hand",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["backlog-unclaimed-delegates"],
  "base": "main",
  "session_window": {"from": "2026-09-23T16:54:25Z", "to": "2026-09-23T16:57:55Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```
