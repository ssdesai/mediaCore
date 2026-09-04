# <Feature title>

<One paragraph: what this feature delivers and why the work exists. No plan-level
detail — that's what the table below is for.>

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/NN-description-MODEL.md` | <one line> |
| `verify/incomplete/NN-verify-MODEL.md` | <one line> |
| `review/incomplete/NN-review-opus.md` | <one line> |

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| <1> | <NN-NN> | `NN-gate.md` | `NN-level-*-MODEL.md` or — | <gate sections> |

Delete this section when the batch has a single level.

## Contracts across levels

| Value / identifier | Produced by (plan, file:line) | Consumed by (plan, file:line) | Fixture | Asserted by |
|---|---|---|---|---|
| <name> | <NN, path:line> | <NN, path:line> | `tests/fixtures/contracts/<name>.json` or — | <producer test> / <consumer test> |

An allowed-actions contract (state × action) is one row per cell, not one row. A row
whose Fixture is `—` needs a reason in the Deliberately-excluded list below.

Delete this section when the batch has a single level.


## Deliberately excluded

- <Something that looked in-scope but isn't — and why.>

## Machine-readable

```json
{
  "slug": "<feature-slug>",
  "method": "plans",
  "plans": ["NN-description-MODEL", "NN-verify-MODEL", "NN-review-opus"],
  "branches": ["<branch-name>"],
  "base": "<base-branch>",
  "session_window": {"from": "<YYYY-MM-DDTHH:MM:SSZ>", "to": "<YYYY-MM-DDTHH:MM:SSZ>"},
  "exclude_sessions": ["<session-id>"],
  "exclude_subagents": ["<agent-id>"],
  "sessions": ["<session-id>"],
  "subagents": ["<agent-id>"]
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
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
