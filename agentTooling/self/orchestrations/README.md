# self/orchestrations

One directory per **orchestration record**: the group of features an orchestrator session
spawned, kept together so their cost can be read as one figure. An orchestrator spawns one
implementer session per feature and builds nothing; its own transcript is **overhead**, and
every feature it spawned is priced by that feature's own record. The same record is what an
experiment comparing two agentTooling versions at the orchestrator level produces, which is
why it carries the agentTooling commit the orchestrator ran under.

The orchestrator commits nothing except its own record, on its assigned branch, as a
records-only PR.

| Path | What it is |
|---|---|
| `<slug>/README.md` | The record: an opening paragraph, then one JSON fence `{ slug, session, agent_tooling, session_window{from,to}, features[{repo, slug, session, branch, pr, report}] }`. Written by `../../orchestration-start.sh <slug>`, edited only by `python3 ../../analysis/manifest.py --orchestration <slug> add-feature\|set-feature\|set-window-to`. `report` is a feature's `report.json` path relative to the agentTooling root, or null when it lives in another repository. |
| `<slug>/planning.json` | The orchestrator's own priced transcript, written by `../../orchestration-capture.sh <slug>`; `planning.json`'s fields, less the claim machinery (`../../analysis/README.md` → "`planning.json`" for the differences). |
| `<slug>/report.md`, `<slug>/report.json` | The group report, written by `python3 ../../analysis/report.py --orchestration <slug>`: one row per feature, the overhead, the group total. `report.json` is what a later scorecard reads. |

Depends on `analysis/roots.py`'s `orchestrations_root()` for this folder's location, and on
each feature's `report.json` carrying `cost.total`.
