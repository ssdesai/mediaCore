# capture-merges-committed-record — the committed planning.json is the baseline

`analysis/capture_planning.py` treated a committed `planning.json` as a frozen record to
protect: `check_frozen_cost` listed every priced session or subagent whose transcript the
scan could not reach, and the capture refused to write unless `--carry-lost` kept those
rows or `--force` discarded them — and `feature-capture.sh` passed neither. That rule was
designed for a laptop, where every round runs on one machine and an unreachable
transcript meant it had aged out or the capture ran from the wrong checkout (the
documented accident that zeroed eleven features). In a Claude Code cloud container the
unreachable transcript is the normal case from round 2 on: each round runs in a new
container, the previous container's transcript is gone, and its cost survives only
because that container's close committed `planning.json` to the branch. So every
multi-round cloud close refused, and a human ran the capture by hand with `--carry-lost`
(`propagate-agenttooling-access`, ruling 9; PRs #92 and #94 both hit it).

This feature makes the committed record the baseline every capture merges into: rows the
scan reaches are re-priced, rows it cannot reach are kept with `carried_from` set to the
capture that originally priced them (a row carried twice keeps its first stamp; the
top-level `carried_from` is the earliest), one WARN names them, and nothing refuses.
Deselected-but-reachable and runner-reclassified sessions are still dropped; `--force`
still rebuilds from one scan; `--carry-lost` is a deprecated no-op alias. `report.py`
prints one line saying how many rows were carried and from which capture dates, so a
reader sees the figure is a chain across containers. `NOTES.md` records the reasoning.

Built by hand (`--method hand`).

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Reviews the merge, the report line, the docs and the tests against the spec |
| `review/incomplete/02-review-sonnet.md` | Round 2, after round 1's escalation: reviews the ledger assertions added for the carried rows (tests only) |

## Deliberately excluded

- **Persisting transcripts beyond the container.** Ruled out by the cloud design (§12);
  the merge is what makes that unnecessary for cost.
- **Renaming `check_frozen_cost`.** It no longer guards, but it is still the one reader
  of "which prior rows can this scan not reach", and every doc and test that names it
  stays valid; its docstring says what it feeds now.
- **The hook's `CAPTURE_WRITING_FLAGS`.** `--carry-lost` still implies `--recapture`, so
  the hook still treats it as a writing flag. Correct as is.
- **Design records that mention `--carry-lost` as history** (`DESIGN-2026-09-16-…`,
  `TRIAGE-2026-09-03-…`). They describe what was true when written.

## Machine-readable

```json
{
  "slug": "capture-merges-committed-record",
  "method": "hand",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["claude/capture-merges-committed-record"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "session_window": {"from": "2026-10-27T14:15:52.443Z", "to": "2026-10-27T14:52:09Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, the profile, the gate and `from`, with the id lists empty — and
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
- **`profile`** — `"local"` or `"cloud"`: where the start ran, as
  `agentTooling/env-profile.sh` decided it (`"cloud"` in a Claude Code cloud container,
  where the feature's checkout is the container itself and `branches` names the session's
  assigned branch). A record of where the cost was made, shown by `analysis/report.py`;
  nothing branches on it. Absent from a manifest started before it, which reads as "not
  recorded".
- **`gate`** — `"green"` or `"skipped"`: whether the start's base gate ran and was green,
  or no gate ran at all (`feature-start.sh --no-gate`, or the repo has no gate script), so
  a feature started on an unverified base says so in its record
  (`agentTooling/self/DESIGN-2026-10-05-cloud-execution.md` §7). Written by the start
  through `analysis/manifest.py init --gate`, shown by `analysis/report.py`; nothing
  branches on it. Absent from a manifest started before it, which reads as "not recorded".

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
  where rule 1 claims it by branch with no pin at all — and a session that starts the
  feature already ON its branch, and any session that starts one in a Claude Code cloud
  container (on its assigned branch, or cutting it with `--branch`), is that
  coordinator: no routing record, no pin, and `from` set to its own first instant. What is left for this field is the
  case it was written for — a session that genuinely worked on this feature from
  somewhere else, typically one that began on `main` before the branch existed; widening
  `branches` to `main`
  instead sweeps in every later session in that checkout. A pinned session that branch
  and window would also select is priced once, and every entry in `planning.json`
  records how it was selected (`selected_by`: `"pinned"` or `"branch"`) and the `cwd` it
  was launched in. A pin that is also in `exclude_sessions` warns, and the pin wins.
  Pin with `python3 agentTooling/analysis/manifest.py <slug> pin-session <id>`, and take
  one out with `… unpin-session <id>` — never by editing the fence.
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
  id claims it outright. Pin with `python3 agentTooling/analysis/manifest.py <slug>
  pin-subagent <agent-id>` — the one writer of this list; a repeat is a no-op and a
  malformed id is refused — never by editing the fence; `unpin-subagent <agent-id>` is how
  a pin comes out. Find the id with
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
- **`exclude_subagents`** — optional, and legacy: leave it empty. Delegates of a session
  this manifest *does* select that belong to another feature. A delegate another feature
  pins now **yields** on its own — the capture leaves it to that feature and records it in
  `planning.json`'s `yielded_agent_ids` — so nothing new needs listing here. The list is
  still read, so a record captured before the yield rule recaptures as it did; take an
  entry out with `python3 agentTooling/analysis/manifest.py <slug> unexclude-subagent
  <agent-id>`, never by editing the fence.
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
