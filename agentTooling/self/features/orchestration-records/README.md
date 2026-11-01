# orchestration-records: the cost of a group of features, read together

An orchestrator session now spawns one implementer session per feature and builds
nothing, so the cost of a group of features is the orchestrator's own transcript
(overhead) plus every feature it spawned. This adds the **orchestration record**,
`self/orchestrations/<slug>/README.md` — a prose paragraph and a JSON fence naming the
orchestrator's session, the full agentTooling commit it ran under (what an experiment
comparing two versions at the orchestrator level pins), its window and its features
(`repo`, `slug`, `session`, `branch`, `pr`, `report`). `orchestration-start.sh` writes it;
`analysis/manifest.py --orchestration <slug>` gains `get`, `add-feature`, `set-feature`
and `set-window-to`; `orchestration-capture.sh` prices the orchestrator's transcript into
the record's `planning.json` through a new `capture_planning.price_session_in_window` (every
filing of the session id across the project directories, the latest priced, inside the
window); a feature manifest's fence gains the optional `orchestration` key,
`feature-start.sh --orchestration <slug>` writes it; and `report.py --orchestration <slug>`
writes the group report — one row per feature, the overhead, the group total with unpriced
features named and left out of it — as `report.md` and a `report.json` a scorecard can read.
The orchestrator commits nothing but its own record, as a records-only PR.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | The review pass against the spec above. |

## Deliberately excluded

- A `--self`/consuming-repo split of the record: it always lives in `self/orchestrations/`.
- Capturing the features' own cost: each feature's `report.json` already is that; the group
  report only reads it.
- Any change to the existing `manifest.py` subcommands, `feature-capture.sh` or
  `feature-close.sh`; the sibling `one-feature-per-branch` owns the rest of `LIFECYCLE.md`.

## Machine-readable

```json
{
  "slug": "orchestration-records",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-opus"],
  "branches": ["claude/orchestration-records"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "session_window": {"from": "2026-10-30T18:27:29.028Z", "to": "2026-10-30T19:00:58Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the branch,
the base, the profile, the gate and `from` (and `orchestration` under `--orchestration`),
with the id lists empty — and `feature-capture.sh` stamps `to` on the branch, provisionally
until the merge freezes it (`agentTooling/LIFECYCLE.md`).
