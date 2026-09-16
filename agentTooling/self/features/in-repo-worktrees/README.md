# Feature worktrees inside the primary checkout

`feature-start.sh` creates each feature's worktree as a sibling of the primary checkout,
`<R>-<S>`. That is outside the folder a session launched in the primary can reach. Where
reads outside the launch folder are blocked, and the parent directory is deliberately
not granted, every feature has needed a manual `/add-dir`, and its delegates have
prompted on nearly every call. This feature moves the worktree to `<R>/.worktrees/<S>`,
kept out of git, so the primary session reaches it with no access beyond its own
folder. The branch, the manifest, and every lifecycle step are unchanged. Two things
move with the path:
- `capture_planning.py`'s claimable roots, so other features' nested worktrees stay
  unclaimable and legacy sibling worktrees stay claimable;
- every doc that names the path.

Built **direct** (`AGENT_DIRECT.md`): bash plus one Python module, well under 1,000 lines.

## Plans

| Plan | What it does |
|---|---|
| (implementer delegate) | Build, tests first, per `AGENT_DIRECT.md`; no `auto/` or `verify/` plans. |
| `review/incomplete/100-review-opus.md` | Review: claimability of nested vs other vs legacy worktrees, the git ignore, legacy close, docs. |

## Deliberately excluded

- **Migrating existing sibling worktrees.** A feature started under the old layout keeps
  its `<R>-<S>` until it closes. Close and capture support both layouts rather than
  moving a live worktree out from under a running session.
- **The billing rule.** `LIFECYCLE.md` rule 1 (a session is billed to its launch
  directory's branch) and the pin semantics are unchanged; only the path they name moves.
- **Pushing to upstream `ssdesai/agentTooling`.** Done after this merges, by the vendored
  push-back procedure, not in this PR.
- **Consuming repos' tool configs.** Each consuming repo scopes its own tools. This one
  already does: pytest `testpaths`, ruff `src tests`, `npm --prefix frontend`. A warning
  for other consumers is a review judgment call, not a config change here.

## Machine-readable

```json
{
  "slug": "in-repo-worktrees",
  "method": "direct",
  "plans": ["100-review-opus"],
  "branches": ["in-repo-worktrees"],
  "base": "main",
  "session_window": {"from": "2026-09-11T14:34:13Z", "to": "2026-09-11T14:59:56Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["d561930d-cc5c-4acd-9b54-d222e9f66c16"],
  "subagents": ["a57641e7ee9ac479a"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, `from`, and a pin for the session that ran it — and
`feature-close.sh` stamps `to` when the feature is closed
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
  `feature-start.sh --base` said otherwise. `run-review.sh` reads it and exports
  `FEATURE_BASE`, which is the base `plans/pr.sh` opens the PR against, so a feature
  stacked on one that has not merged shows only its own diff. Cost capture ignores it.

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
  regardless of branch, window or `cwd` — the top-level twin of `subagents`.
  `feature-start.sh` pins the session that ran it, which is what claims a planning
  session that began on `main` before the branch existed; widening `branches` to `main`
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
  until the feature closes. `agentTooling/feature-close.sh` sets it, from evidence: one
  second past the last instant of the sessions this feature's `branches` and
  `session_window` select and of their subagents, stamped before the capture so the
  shared-session split runs against the real bound (`agentTooling/LIFECYCLE.md` → step 6).
  Do not hand-write one, and never widen one already set — `analysis/manifest.py
  set-window-to --tighten` is the only path that may move it, and only inwards. A window
  left open after the work is done is what goes wrong: two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
