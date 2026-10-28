# The routing record per feature, and three ledger rules

Four defects in what the cost ledger records or where, each a backlog entry, closed as
one feature. **The routing record** — `feature-start.sh` writes
`<corpus>/routing/<session-id>.json` on each feature's branch, so two features one
router starts before either merges each add that one path with different content and
the second merge conflicts (`policy-module`, 2026-09-18); the record is a record of a
link, so it moves to `<features>/<slug>/routing.json`, one per feature, never two on one
path, and the reader that wants one row per router keeps the latest `captured_at` — the
rule the human applied at merge time, written once in `routing.load_records`. **The open
co-claimant** — a feature not yet closed carries `to: null` and takes an equal share of a
shared coordinator to the end of the transcript; it is bounded provisionally by the same
`last_branch_instant` its own close will stamp, the record says which claimants were
open, and the corpus annotation warns when the stamped bound later differs. **The
zero-cost pin** — the ledger is written from priced entries, so a pinned delegate with no
billable response is "unclaimed forever"; the ledger records claims, every `subagents[]`
entry with its cost, 0 included. **The head's remedy** — the unclaimed-head warning
says "move `from` back by hand"; `manifest.py set-window-from` is the tool, with the
guards that make it safe, and the warning names it. The full reasoning is
`self/DESIGN-2026-09-18-ledger-and-routing.md` (§1–§6). Built direct (`AGENT_DIRECT.md`)
by two implementers in this one worktree on non-overlapping files, tests first, then
one review pass, then the close.

## Slices

| Slice | What it does |
|---|---|
| A1. Routing record per feature (§1) | `analysis/routing.py`: the record is written to `<features root>/<slug>/routing.json` (`--session --slug`), `routers_of(features_dir, slug)` reads that one file, `load_records(features_dir)` globs `*/routing.json` and keeps the latest `captured_at` per `session_id`, `--migrate` moves each legacy `<corpus>/routing/<id>.json` into every slug its `features_started` names (skip a target already as late or later), deletes the legacy file, prints each move, idempotent. `feature-start.sh` drops `ROUTING_PATHS`/`ROUTING_LABEL` (the file is inside the directory the start commit adds); `feature-capture.sh --refresh-for <slug>` rewrites only `<slug>/routing.json` and `git add`s that. `plan-runner-roots.sh`: `routing.json` joins `COST_FILES`, the three `ROUTING_*` labels leave `stray_labels`, `stray_paths`' guard shrinks. `sync-plans.sh` runs `--migrate` after the pull and tells the human to commit the moves. `report.py`'s two routing renderers read the new location. This feature runs `--migrate` on `self/` and commits the moves (`self/routing/` is gone). Tests: `routing-record.sh` (per-feature path, `--refresh-for` touches only its slug, `load_records` collapses two copies to the later `captured_at`, `--migrate` into two feature directories and clean on a second run), `feature-lifecycle.sh` (two features one router starts from the same `main`, closed and merged in turn, no conflict, two `routing.json`, one Routing row naming both), `verdict-readers.sh`'s stray phase, `sync-check.sh` if it lists `routing/`. Docs: root `README.md`, `LIFECYCLE.md` steps 2 and 5, `analysis/README.md` → `routing.py`, `self/README.md`, `self/features/README.md`, `templates/plans/README.md`, `self/tests/README.md`; the routing entry leaves `self/BACKLOG.md`. |
| A2. Three ledger rules (§2–§4) | `capture_planning.py`: in `build_claimant_index` an open co-claimant (`to: null`, not the capturing feature) is bounded provisionally by `last_branch_instant(slug, its features_dir, sessions_dir)`; nothing found → empty window, dropped by the existing empty-claim rule with a warning naming it open with no evidence; `share_basis[]` entries for it carry `open: true` and `provisional_to`; `planning.json` gains top-level `open_claimants[]`; `annotate_corpus` warns naming the record and `--recapture` when a frozen record's `provisional_to` differs from that claimant's manifest `to` now. The ledger writes every `subagents[]` entry with its `cost_usd` (0 when unpriced), so `--list-subagents --unclaimed` omits a pinned zero-cost delegate. `manifest.py [--self] <slug> set-window-from <instant> --session <id>`: echoes old→new; refuses an instant earlier than the session's first timestamped instant (transcript found the way `routing.find_transcript` does; import direction verified and recorded); refuses to move `from` later (says which command, if any, narrows); on a captured feature says `--recapture` is needed. The unclaimed-head warning names the command with the session id and the head's first instant. Tests: `session-share.sh` (open co-claimant recorded and its share equal to the post-close capture's when the close stamps the same bound; open co-claimant with no branch sessions dropped with the warning; annotation warns on drift), `subagent-capture.sh` or `claims-ledger.sh` (pinned delegate with no `assistant` line captured, in the ledger at 0, not listed unclaimed), the manifest test that holds `set-window-to`'s cases (applied and echoed; earlier than first instant refused; later refused; warning text names the command). Docs: the `capture_planning.py` and `manifest.py` entries of `analysis/README.md`, `self/tests/README.md`; the three entries leave `self/BACKLOG.md`. |

## Deliberately excluded

- **A merge driver for the routing record** — needs per-clone git config, and GitHub's
  merge never runs it.
- **One shared routing file per router with a union merge** — the add/add is the shape,
  not the content.
- **Bounding a co-claimant by anything but its own close's derivation** — a bound that
  can disagree with the stamped one is the objection the backlog entry recorded.
- **The per-feature budget and `git stash list`** — the user's decision, entry stays.
- **Everything `minutes-slug-and-quoting` owns** — the per-attempt minutes walk,
  `slug_of_start_command`, `open-session.sh` quoting.

## Machine-readable

```json
{
  "slug": "ledger-and-routing",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["ledger-and-routing"],
  "base": "main",
  "session_window": {"from": "2026-09-18T12:06:01Z", "to": "2026-09-18T13:26:03Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["abf53d9237956e2f6", "a3362e2991e03df22", "aae3f4d27284108d4"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base and `from`, with the id lists empty — and
`feature-capture.sh` stamps `to` on the branch, provisionally until the merge freezes it
(`agentTooling/LIFECYCLE.md`). Do not hand-copy it. Only `slug`, `plans` and `branches`
are required: `method` reads as `"plans"` when absent, `base` as `main`,
`session_window` as unbounded, and the four id lists as empty. These are the ones that
go wrong quietly:

- **`method`** — optional, `"plans"` when absent. `"direct"` marks a feature built per
  `agentTooling/AGENT_DIRECT.md` by one implementer delegate; `"hand"` one the
  coordinator built itself, with no delegate to pin and no plans. Under either, the
  transcripts `planning.json` captures are the **build**, and `analysis/report.py` files
  their dollars and minutes there instead of under planning — as `build: implementer`
  and `build: by hand` respectively. Leave it out for a planned feature; a wrong value
  here moves money between buckets without a warning about which was right.
- **`base`** — the branch the feature branched from, `main` unless
  `feature-start.sh --base` said otherwise. `feature-close.sh` reads it and exports
  `FEATURE_BASE`, which is the base `plans/pr.sh` opens the PR against, so a feature
  stacked on one that has not merged shows only its own diff. `run-review.sh` reads it
  too, to know whether it is on a branch it may commit its pass to. Cost capture ignores
  it.

- **`branches`** — copy each name from `git branch --show-current`, verbatim. It is
  matched literally against the `gitBranch` in every session transcript, so an added
  owner prefix, or a name retyped from memory, matches nothing and leaves every session
  on it uncounted — the feature then reports `$0.00`, which reads as "planning was free"
  rather than "this manifest is wrong". `analysis/capture_planning.py` warns when a
  declared branch matches no transcript. If a branch was renamed mid-feature, list both
  names: transcripts keep whatever name was current when they were written.
- **`plans`** — every plan stem in the table above, *without* the `.md` extension and
  without its queue/state path, in batch order. `analysis/report.py` prices exactly this
  list: a stem left out is a plan whose cost lands in no report, and an array left out
  entirely drops the whole feature back onto a fallback that can only see plans which
  already ran.
- **`session_window` timezone** — end every bound with `Z`. A bound with no offset is
  read as UTC, and the natural place to find a timestamp is `git log`, which prints
  **local** time — so a value copied from there and pasted bare is silently off by your
  UTC offset, four hours in US Eastern, which is enough to hand a session to the wrong
  feature. Write local time only with its offset spelled out (`2026-07-17T18:00:00-04:00`);
  `analysis/capture_planning.py` warns on any bound that states no zone.
- **`sessions`** — session ids claimed outright, across every project directory,
  regardless of branch, window or `cwd` — the top-level twin of `subagents`. **A pin is
  the exception now, not the rule.** `feature-start.sh` pins nothing unless given
  `--pin`: the session that starts a feature is a *router*, it opens several features and
  belongs to none of them, and its spend is routing overhead reported from
  `plans/features/<slug>/routing.json` rather than billed to any feature
  (`agentTooling/LIFECYCLE.md` → step 2). The coordinator belongs inside the worktree,
  where rule 1 claims it by branch with no pin at all. What is left for this field is the
  case it was written for — a session that genuinely worked on this feature from
  somewhere else, typically one that began on `main` before the branch existed; widening
  `branches` to `main`
  instead sweeps in every later session in that checkout. A pinned session that branch
  and window would also select is priced once, and every entry in `planning.json`
  records how it was selected (`selected_by`: `"pinned"` or `"branch"`) and the `cwd` it
  was launched in. A pin that is also in `exclude_sessions` warns, and the pin wins.
  A session claimed by more than one feature is **split** between them by the windows
  they claim it with, so the bounds on a pinned session decide dollars.
  Find an id with `python3 agentTooling/analysis/capture_planning.py --list-sessions
  [--unclaimed] [--since <date>]`, which prints every session launched in this repo's
  primary checkout or one of its feature worktrees with its branch, `cwd`, cost and
  opening prompt.
- **`subagents`** — optional; usually absent. Agent ids of delegates whose *parent*
  session was not on this feature's branch — the coordinator-on-`main` case. A subagent
  inherits its parent's `gitBranch` at spawn and never records its own, so an architect
  spawned from `main` is invisible to `branches` and `session_window` alike; pinning its
  id claims it outright. Find the id with
  `python3 agentTooling/analysis/capture_planning.py --list-subagents --since <date>`,
  which prints each one's cost and opening prompt. A subagent whose parent *is* on the
  branch needs no pin — it is claimed with its parent when its own start is in the window.
  A pin wins over an `exclude_sessions` entry naming its parent: excluding the coordinator
  drops the coordinator's own context cost and keeps the pinned architect. Runner sessions
  are the exception — their usage.json already holds the cost, pins included. A
  delegate's transcript is filed under its *parent's* cwd, so one spawned by a
  coordinator sitting in another repo is found by `--list-subagents --everywhere`
  and pinned here all the same. `--list-subagents --unclaimed` is the standing
  question — every delegate on this machine no feature has claimed, with the
  feature its brief names; a pin already claimed by another feature refuses the
  capture rather than counting twice.
- **`exclude_subagents`** — optional. Delegates of a session this manifest *does* select
  that belong to another feature — a coordinator's manifest (on `main`, windowed around
  the run) lists the architect it spawned, which the arm's own manifest pins. Without it
  the parent route claims the architect here too and the ledger refuses the other
  capture as a double claim.
- **`session_window.to`** — `null` means "still in flight", and open is the right value
  until the feature's first capture. `agentTooling/feature-capture.sh` sets it on the
  branch, from evidence: one second past the last instant of the sessions this feature's
  `branches` and `session_window` select and of their subagents, stamped before the
  capture so the shared-session split runs against the real bound
  (`agentTooling/LIFECYCLE.md` → step 5). Until the merge it is provisional, and a re-run
  of the capture after more work moves it either way (`set-window-to --replace`). Do not
  hand-write one, and never widen one on a merged feature — `analysis/manifest.py
  set-window-to --tighten` is the only path that may move it then, and only inwards. A window
  left open after the work is done is what goes wrong: two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
