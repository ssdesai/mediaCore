# Claim-window precision

Closes the four backlog entries `shared-session-share` raised. That feature split a
multiply-claimed session between its claimants by the windows they claim it with, which
made the windows load-bearing — and exposed that `feature-close.sh` stamps every
feature's `to` at its close time, so features started from one coordinator nest inside
each other and keep drawing an equal share for hours after their work stopped. This
feature stamps `to` from evidence (one second after the feature's last branch-selected
instant, before the capture, tighten-only, repairable per feature with
`feature-close.sh --recapture`); quantifies what a single-claimant session carries past
its window instead of only saying it does; makes the `predates the share rule` repair
warning fire on every sweep rather than the first; and indexes the claimant manifests
once per capture instead of once per selected session. Built direct
(`AGENT_DIRECT.md`): one opus implementer from `brief.md`, reviewed from a brief written
before the build.

## Plans

| Plan | What it does |
|---|---|
| `brief.md` | The implementer's brief: the four items, their rulings, the assertions each must go red against. Not a plan; recorded for resume. |
| `rework-brief.md` | The rework one-shot's brief, written from the review's five escalations: where, what to read, the rulings already settled (the widen refusal's exit code is 3, and a stamp refusal rolls back the carry and the recovery as the capture refusal does), and the procedure. Not a plan. |
| `NOTES.md` | The implementer's rulings, its one substantive deviation from the brief, and the mutation every new assertion was proved red against — then a `# Rework` half carrying rulings 12–18 and its own red-proof table, for the five escalations. |
| `CHECKPOINT.md` | The shape of the build, at `status: committed` — the direct feature's `auto/complete/`. Rewritten whole by the rework one-shot for its own slices. |
| `review/incomplete/97-review-opus.md` | Independent review of the diff against `shared-session-share`, from the spec: nothing frozen moves, the stamp is tighten-only and precedes the capture, the evidence selection is the capture's own, the unshared path is byte-identical. |

**One deviation from the brief, and the review should look at it first.** The brief scopes
the evidence to "what `select_parent` selects by `branches` + `session_window`", and
`select_parent` is never reached for a session some `usage.json` already holds — a runner
session. Read that way the bound exists for **1** of agentTooling's sixteen features;
counting runner sessions it exists for **9**, each one to eleven hours tighter than the
`to` the close had stamped, and every one of them earlier, so tighten-only holds corpus
wide. The capture's exclusion answers "what may this record price"; the bound answers
"when did work on the branch stop", and a `claude -p` executor draining a plan in the
feature's own worktree is the plainest evidence of that. The manifest's own
`exclude_sessions` is still honoured, and pins are still not consulted. `NOTES.md` ruling
3 carries the measurements.

## Deliberately excluded

- **Bounding another in-flight feature's claim.** A co-claimant whose `to` is still
  `null` stays unbounded in this feature's split; bounding it would mean walking that
  feature's transcripts from here. Its own close bounds its own record. Recorded in
  `self/BACKLOG.md` by this feature.
- **Git evidence for `to`.** The branch's last commit is a second source the backlog
  named; transcript evidence subsumes it for every feature that has a branch session,
  and a feature with none falls back to the close time with a warning, as today.
- **Re-stamping the two corpora's existing `to` bounds in bulk.** The repair is per
  feature — `feature-close.sh --self <slug> --recapture` tightens the bound from evidence
  and re-splits — and the two frozen over-counts need exactly that run anyway. A sweep
  that rewrote every closed feature's window would move boundaries other manifests chain
  onto without a human reading each.
- **Slicing a single-claimant session to its window.** Still deliberately unsliced: it
  removes no double-count and turns a disclosed over-count into a silent under-count.
  The warning now says how much lies outside, which is the disclosure the backlog asked
  for.

## Machine-readable

```json
{
  "slug": "claim-window-precision",
  "method": "direct",
  "plans": ["97-review-opus"],
  "branches": ["claim-window-precision"],
  "base": "shared-session-share",
  "session_window": {"from": "2026-09-09T00:14:17Z", "to": "2026-09-09T14:48:25Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["ed76cd6f-477a-4b4e-84fd-c7a340538f14"],
  "subagents": ["a9e292006a01bdc3b", "a371d315de59ab809"]
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
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
