# A router that built its feature is refused at the close until it is pinned

The session that runs `feature-start.sh` is the feature's **router**. `feature-start.sh`
records it in `<slug>/routing.json`, and its cost is reported as routing overhead, never
in the feature's total. The design expects a different session, launched in the worktree,
to build the feature. When the router builds the feature itself instead, the build's cost
lands in routing overhead and the feature reports only its review. `--pin` exists for
exactly this case, and nothing checked that it was used. It happened twice on 2026-09-23:
- `carry-stream-sections` (PR #61) reported $0.38 while its $3.60 build sat in its routing
  record;
- `litellm-pricing`'s coordinator noticed the same thing and repaired its fence by hand.

This feature makes it a refusal:
- **The refusal.** `feature-close.sh` refuses, before the PR, a feature whose routing
  record names a session that no manifest pins and whose transcript shows it at work in
  this feature's worktree: a line whose `cwd` is at or under `<primary>/.worktrees/<slug>`,
  or an `Edit`/`Write`/`NotebookEdit` aimed at a path under it.
- **One reader.** The predicate lives in `analysis/routing.py`, the module that already
  owns routers and pins. `feature_worktree_path` and `WORKTREES_DIR_NAME` move there from
  `capture_planning.py`, which imports them back, so the layout has one owner.
- **The remedy is a script.** A new `manifest.py pin-session <id>` adds the session to the
  fence's `sessions[]`, so no one edits the fence by hand. The manifest is already a cost
  record (`COST_FILES`), so the close's dirty-files check admits it and the capture commits
  it. The routing record stays on disk, and `split_pinned` already stops counting it.

It also adds the `self/BACKLOG.md` entry for re-render drift. A frozen report re-rendered
by the annotate step still takes on the renderer's newer format — new keys, the rounds
table, the rates footer — inside another feature's cost-records commit.

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md` | Independent review of the hand build against the spec above |
| `review/incomplete/02-review-sonnet.md` | Round 2: the merges of `litellm-pricing` (#62) and `backlog-unclaimed-delegates` (#64) from `main`, and nothing else |

## Deliberately excluded

- **Claiming the router automatically at capture.** The evidence is clear, but a router
  that started several features and built one of them is the same session in every one
  of their routing records. Moving all of it to one feature is a judgement the human
  should make, and the refusal names the one command that makes it.
- **Refusing at `feature-start.sh`.** At the start there is nothing yet to judge. A plain
  start, followed by a coordinator launched in the worktree, is the intended flow and
  looks identical to this defect until the router starts working.
- **Reads.** A `Read`, or a `grep` run from the primary against a worktree path, is not
  counted. Only a `cwd` inside the worktree or a write aimed into it counts as working
  there. A router may inspect what it started.
- **Repairing merged features.** `carry-stream-sections` stays as it merged, by the
  user's decision on 2026-09-23.

## Machine-readable

```json
{
  "slug": "router-built-pin",
  "method": "hand",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["router-built-pin"],
  "base": "main",
  "session_window": {"from": "2026-09-23T16:35:16Z", "to": "2026-09-23T16:49:53Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["a36d75f7-506a-41f8-8488-3c43f07d57a4"],
  "subagents": []
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
