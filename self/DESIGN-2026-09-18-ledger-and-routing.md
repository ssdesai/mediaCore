# Design 2026-09-18 — the routing record per feature, and three ledger rules

Feature slug: `ledger-and-routing`. Base: `main` (after PR #50 and the policy PR). Four
backlog entries, each a defect in what the cost ledger records or where: the routing
record's add/add conflict, the unbounded in-flight co-claimant, the zero-cost pin that
is "unclaimed forever", and the head's remedy with no tool. Built direct as two
non-overlapping slices, coordinated from the worktree.

## §1 The routing record lives in the feature it links (D1)

**Defect.** `feature-start.sh` writes `<corpus>/routing/<session-id>.json` on each
feature's branch. Two features started by one router before either merges each add or
modify that one path with different content, so the second merge conflicts and a human
resolves it by hand — which happened to `policy-module` on 2026-09-18, the day after the
entry was written. The record is a pure function of the router's transcript at an
instant, so the "right" resolution is always the later `captured_at`; that rule lives in
a human's head at merge time instead of in a reader.

**Rule.** A routing record is a record *of a link* — this router started this feature —
so it lives in the feature it links: `<features root>/<slug>/routing.json`, one per
feature, the field set unchanged (`captured_at, cost_usd, duration_s, ended_at,
features_started[{slug, at}], git_branch, launched_in, model, session_id, started_at`).
A router that starts three features has three copies, each derived from the same
transcript at its own `captured_at`; the copies never conflict because no two features
share a path, and a reader that wants one row per router takes the copy with the latest
`captured_at` — the rule the human applied, written once, in `routing.load_records`.

- **Writers.** `feature-start.sh` writes `<slug>/routing.json` through `routing.py
  --session --slug`; it is inside the feature directory the start commit already adds,
  so `ROUTING_PATHS` and `ROUTING_LABEL` go. `feature-capture.sh`'s `--refresh-for <slug>`
  rewrites only `<slug>/routing.json` from the router's transcript as it stands — it no
  longer touches records other features' branches also carry.
- **Readers.** `routers_of(features_dir, slug)` reads the one file `<slug>/routing.json`
  (a feature has one router; zero when nothing started it through the script).
  `load_records(features_dir)` globs `*/routing.json`, groups by `session_id`, keeps the
  latest `captured_at` — the Routing table shows one row per router naming every feature
  it started. `is_router_lines` is unchanged (it reads transcripts).
- **The stray reader.** `routing.json` joins `COST_FILES` in `plan-runner-roots.sh`; the
  `ROUTING_REL`/`ROUTING_DIR_NAME`/`ROUTING_RECORD_SUFFIX` labels are deleted from
  `stray_labels`, `stray_paths`' guard shrinks to the three labels that remain, and
  `feature-capture.sh`'s `git add` of the routing directory becomes the feature's own
  file. `self/tests/verdict-readers.sh`'s stray phase follows.
- **Migration.** `routing.py [--self] --migrate` copies each legacy
  `<corpus>/routing/<id>.json` into the directory of every slug its `features_started`
  names (skipping a target whose `captured_at` is already later or equal), deletes the
  legacy file, and prints each move; idempotent, nothing to do when the directory is
  absent. This feature runs it on `self/` and commits the moves; `sync-plans.sh` runs it
  in a consuming repo after every pull and tells the human to commit what moved. No
  reader reads the legacy directory: one location, one reader, a migration tool.
- **Docs.** Root `README.md` rows for `feature-start.sh`, `feature-capture.sh`,
  `sync-plans.sh`; `LIFECYCLE.md` step 2 and step 5; `analysis/README.md` → `routing.py`
  (the paragraph on the add/add conflict is replaced by the per-feature rule);
  `self/README.md` (the `routing/` row goes; `features/README.md` gains `routing.json`
  in its per-feature file list); `self/features/README.md`; the consuming-repo
  `plans/README.md` template if it lists `routing/`.

**Assertions.** `feature-lifecycle.sh`: two features started by one router session from
the same `main`, each closed and merged in turn, reach `main` with no conflict, two
`routing.json` copies, and `report.py --all`'s Routing table holding one row for the
router naming both. `routing-record.sh`: the per-feature path; `--refresh-for` touching
only its own slug's file; `load_records` collapsing two copies to the later
`captured_at`; `--migrate` moving a legacy record into two named feature directories and
running clean a second time.

## §2 An open co-claimant is bounded by its own evidence (D2)

**Defect.** The share split reads every other claimant's window as written, and a
feature not yet closed carries `to: null`, so on a shared coordinator the in-flight
feature takes an equal share of every response from its `from` to the end of the
transcript. The capturing feature already bounds *itself* from evidence
(`--last-branch-instant`); the same derivation is refused to the others on the ground
that a bound derived here might disagree with the one their close stamps.

**Rule.** In `build_claimant_index`, a claimant other than the capturing feature whose
`to` is `null` is bounded provisionally by `last_branch_instant(slug, its features_dir,
sessions_dir)` — the identical function its own close will call, so the two figures agree
whenever the transcripts agree. When that returns nothing (no branch session yet), the
claim's window is empty and the existing empty-claim rule drops it with a warning
naming it as open with no evidence. Every `share_basis[]` entry for such a claimant
carries `open: true` and `provisional_to`, and `planning.json` gains top-level
`open_claimants: ["<repo>/<slug>", …]` so the record says which claimants were open
when it was frozen. `annotate_corpus` (which every capture already runs over the corpus)
compares each frozen record's `provisional_to` with the claimant's manifest `to` as it
stands now and prints one WARN naming the record and `--recapture` when they differ —
the case where that feature kept working after this capture.

**Assertions** (`session-share.sh`): a feature captured while a co-claimant is open
records `open_claimants`, and its share equals the share a capture after that
co-claimant's close reports when the close stamps the same bound; an open co-claimant
with no branch sessions is dropped with the warning; the annotation warns when the
stamped bound differs from the provisional one.

## §3 A pin is a claim whether or not it cost anything (D3)

**Defect.** The ledger's subagents section is written from priced entries, so a pinned
delegate whose transcript holds no billable response never reaches the ledger, and
`--list-subagents --unclaimed` lists it forever, telling the human to write a pin that is
already written.

**Rule.** The ledger records claims, not prices: every entry in the capture's
`subagents[]` — pinned or parent-selected, priced or not — is written to the ledger with
its `cost_usd` (0 when nothing was billable). `--list-subagents --unclaimed` then omits
it by the existing lookup. A transcript with no `assistant` line is still captured into
`subagents[]` when pinned (verify; the backlog says it is).

**Assertion** (`subagent-capture.sh` or `claims-ledger.sh`): a manifest pinning a
delegate whose transcript has no `assistant` line captures it, the ledger names the
feature for that id with `cost_usd` 0, and `--unclaimed` does not list it.

## §4 The head's remedy has a tool (D4)

**Defect.** The "unclaimed by any feature" warning names two repairs for a head nobody
planned; one has a tool (`sessions` pin) and the other is "move the earliest claimant's
`from` back by hand", the one thing every manifest says not to do.

**Rule.** `manifest.py [--self] <slug> set-window-from <instant> --session <id>`: prints
the old and new bound; refuses an instant earlier than that session's first timestamped
instant (found by the transcript glob `routing.find_transcript` uses — `manifest.py`
imports `routing`, never `capture_planning`, which imports `manifest`'s reader; verify
the direction); refuses to move `from` later (narrowing is not this command's job — say
which command, if any, is); on a feature already captured says a `--recapture` is needed
for the figure to move. The unclaimed warning names this command with the session id and
the head's first instant instead of "by hand".

**Assertions** (a manifest test — `self/tests/README.md` says which file holds
`set-window-to`'s; the `from` cases go beside them): a `from` moved back to cover a
disclosed head is applied and echoed old→new; an instant before the session's first
instant is refused; a later instant is refused; the warning text names the command.

## §5 Deliberately excluded

- A merge driver for the routing record (needs per-clone git config; GitHub's merge
  never runs it).
- One shared routing file per router with a union merge — the add/add is the shape, not
  the content.
- Bounding a co-claimant by anything but its own close's derivation.
- The per-feature budget and `git stash list` (the user's decision).

## §6 Build

Two opus implementers in the one worktree, direct, tests first, non-overlapping files:

| Slice | Owns |
|---|---|
| A1 routing (§1) | `analysis/routing.py`, `feature-start.sh`, `feature-capture.sh`, `plan-runner-roots.sh`, `sync-plans.sh`, `analysis/report.py` (the two routing renderers and the import line only), `self/routing/*` (migrated away), `self/tests/routing-record.sh`, `self/tests/feature-lifecycle.sh`, `self/tests/verdict-readers.sh`, `self/tests/sync-check.sh` if it lists `routing/`, root `README.md`, `LIFECYCLE.md`, `self/README.md`, `self/features/README.md`, `templates/plans/README.md`, the `routing.py` entry of `analysis/README.md`, its own entries of `self/tests/README.md`, `NOTES.md` rulings 1–N |
| A2 ledger (§2–§4) | `analysis/capture_planning.py`, `analysis/manifest.py`, `self/tests/session-share.sh`, `self/tests/session-claims.sh`, `self/tests/claims-ledger.sh`, `self/tests/subagent-capture.sh`, the manifest test, the `capture_planning.py` and `manifest.py` entries of `analysis/README.md`, its own entries of `self/tests/README.md`, `NOTES.md` rulings from N+1 (appended by the coordinator from A2's report) |

Each slice `git add`s only its own paths; both edit `analysis/README.md` and
`self/tests/README.md` in their own entries only. `self/BACKLOG.md`: A1 removes the
routing entry, A2 the other three. The coordinator commits the pins and the review runs
once, opus.
