# self/orchestrations

**agentTooling's own** orchestration records. A record lives in the corpus of the checkout it
was started in, as a feature does: a consuming repo's are `plans/orchestrations/<slug>/`
(`orchestration-start.sh <slug>`, no flag), and this folder holds the ones started with
`--self` — `orchestration-start.sh --self <slug>`, `manifest.py --self --orchestration`,
`orchestration-capture.sh --self`, `report.py --self --orchestration`
(`roots.orchestrations_root(True)`; `../features/orchestration-records-in-repo/`). A record in a
consumer's vendored copy of this folder, `agentTooling/self/orchestrations/<slug>`, is either
agentTooling's own record, shipped with the subtree and never moved (read it with `--self` from an
agentTooling checkout; the tools without `--self` say so), or the consuming repo's **stranded**
one — its last fence lists a feature whose `repo` is the consuming repo's, any case
(`roots.is_stranded_record`) — which the tools refuse, printing the `git mv` to
`plans/orchestrations/<slug>`. Without `--self` inside an agentTooling checkout itself there is no
consuming repo: every record tool refuses, naming `--self`. With `--self` from a consumer's
vendored copy, every tool that would write here — a start, a manifest write, a capture, a group
report — refuses before writing, naming `plans/orchestrations/<slug>/`: a record is written into
this folder only from an agentTooling checkout, while a shipped one still reads with `--self`
(`roots.record_write_refusal`; `../features/consumer-record-guard/`).

One directory per **orchestration record**: the group of features an orchestrator session
spawned, kept together so their cost can be read as one figure. An orchestrator spawns one
implementer session per feature and builds nothing; its own transcript is **overhead**, and
every feature it spawned is priced by that feature's own record. The same record is what an
experiment comparing two agentTooling versions at the orchestrator level produces, which is
why it carries the agentTooling commit the orchestrator ran under.

The orchestrator commits nothing except its own record, on its assigned branch, as a
records-only PR. The record is also the orchestrator's **role**: once its session id is a
record's `session`, the lifecycle scripts refuse to build in that session and the hook
denies the build commands (`../../LIFECYCLE.md` → "Orchestrator and implementer sessions").

A **coordinator record** — fence `"kind": "coordinator"`, written by
`../../orchestration-start.sh --self <slug> --coordinator` (`../features/coordinator-cost-records/`)
— is the same file shape for a different session: one that coordinated several features by
delegating each to an Agent subagent, every delegate claimed by the feature it built. Its
`planning.json` prices the coordinator's own transcript and its own `feature: none`
delegates that no feature claims, and nothing else, so it stands beside the features
without counting any of them twice. It is **no role**: its delegates share its session id,
so nothing is refused in the session or in them. Registered live, or retroactively from any
session with `--session <id>`; `from` defaults to the session's first transcript instant.
Its features may live in other repositories: their `report` paths are relative to that
repository, priced with `report.py --self --orchestration <slug> --checkout <repo>=<path>`.

| Path | What it is |
|---|---|
| `<slug>/README.md` | The record: an opening paragraph, then one JSON fence `{ slug, kind?, session, agent_tooling, session_window{from,to}, features[{repo, slug, session, branch, pr, report}] }` — `kind` present only on a coordinator record (`"coordinator"`). Written by `../../orchestration-start.sh --self <slug>`, edited only by `python3 ../../analysis/manifest.py --self --orchestration <slug> add-feature\|set-feature\|set-window-to`. `report` is a feature's `report.json` path relative to the record's own repo root (here, the agentTooling root; in a consuming repo, that repo's root) — or, for a feature in another repository, relative to that repository, priced when `report.py` is given `--checkout <repo>=<path>` — or null. |
| `<slug>/planning.json` | The orchestrator's own priced transcript, written by `../../orchestration-capture.sh --self <slug>`; `planning.json`'s fields, less the claim machinery (`../../analysis/README.md` → "`planning.json`" for the differences). |
| `<slug>/report.md`, `<slug>/report.json` | The group report, written by `python3 ../../analysis/report.py --self --orchestration <slug>`: one row per feature, the overhead, the group total. `report.json` is what a later scorecard reads. |

Depends on `analysis/roots.py`'s `orchestrations_root(True)` for this folder's location (the
consuming repo's is `orchestrations_root(False)`), on `hooks/orchestrator_role.py` reading this
folder and `plans/orchestrations/` both, and on each feature's `report.json` carrying
`cost.total`.
