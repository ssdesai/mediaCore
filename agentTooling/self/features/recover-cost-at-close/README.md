# recover-cost-at-close

A review that runs to completion but whose event stream loses its `result` event is
recorded at `$0`, and the close commits that zero into the cost records — musicMap
`pin-ruff` and seven vinylCatalogue features closed on 2026-09-04/05 carry one. This
feature makes the zero impossible to mistake for a measurement and makes the close repair
it: the sidecar records whether a result event was seen at all, `feature-close.sh` runs
`recover_attempts.py` over the feature before it captures so a transcript-derived figure
reaches the cost commit, and a cost bucket that still has an unpriced plan in it names the
plan and says why instead of printing a bare `$0.0000`.

Built direct (`AGENT_DIRECT.md`), so there are no build or verify plans — one implementer,
acceptance tests first, then the review pass below.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/85-review-opus.md` | The independent review: the `result_event` field and its readers, recovery at close (scoped, non-fatal, its files in the cost commit), no bare zero for a worked bucket, `--recapture` without a worktree, the docstrings, tests RED-then-green, the backlog. |

## Deliberately excluded

- **The root cause of the missing result event on a 0-exit session.** Not known and not
  reproducible: the sessions completed normally (the transcript's last event is an
  ordinary `end_turn`), other single-shot reviews of the same shape priced fine, and the
  `.stream.jsonl` that would say what the stream actually held is gitignored and dies with
  the worktree. Recorded in `self/BACKLOG.md` with the evidence that survives instead of
  chased here — the accounting must be honest whether or not the cause is ever found.
- **`report.py`'s usage index, plan/LOC computation, manifest-plan loading, and the
  *summing* inside `compute_cost_rollup`.** Owned by the parallel `stale-failed-sidecars`
  feature. The edits here are confined to `compute_cost_rollup`'s output and warning path
  and to the two renderings that read it.
- **The runner's failed/complete routing.** `outcome` is computed from the exit code and
  stays that way: these runs really did complete, and re-routing a resultless success to
  `failed/` would make the plan queue lie to fix a bookkeeping problem. Pricing is a
  separate fact from what the plan did, which is exactly what the new field records.
- **Re-capturing the affected consumer features.** The procedure is written for the
  coordinator in `NOTES.md`; running it means writing to vinylCatalogue and musicMap,
  which this feature does not do.
- **Re-pricing recovered dollars anywhere.** `total_cost_usd` stays the CLI's own figure
  forever; a recovered figure stays `recovered_cost_usd` on the attempt, as
  `killed-attempt-cost-recovery` established.

## Machine-readable

```json
{
  "slug": "recover-cost-at-close",
  "method": "direct",
  "plans": ["85-review-opus"],
  "branches": ["recover-cost-at-close"],
  "base": "main",
  "session_window": {"from": "2026-09-06T14:01:40Z", "to": "2026-09-06T15:27:26Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["2d8b1236-3e77-450f-bc9e-8165c0cf9f9c"],
  "subagents": ["aafc1ca6b6fa70fd0", "afe8e7432e489837b"]
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
