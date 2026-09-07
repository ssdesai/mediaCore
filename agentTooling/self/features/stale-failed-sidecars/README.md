# Stale failed sidecars: a killed attempt's leftovers must not crash the cost report

A plan killed by a session usage limit and retried by hand leaves two files behind in
`<queue>/failed/` — a `.progress.md` and a `.usage.json` with `total_cost_usd: null` —
with no `.md` beside them, because the retry moved the plan file back to `incomplete/`
and from there to `complete/`. `analysis/report.py` then had two sidecars claiming the
same plan stem, picked between them by filesystem order, and read a plan file beside
whichever it picked. On 2026-09-04 that crashed `feature-close.sh` in vinylCatalogue
with a `FileNotFoundError` for a path that has not existed since the retry. This feature
makes the analysis handle the pair instead of the runner cleaning it up: the pair is the
record of the killed attempt and the only place its session id survives.

## The defect

For vinylCatalogue's `group-commit-all-adjudication`, review plan `01-review-opus` was
killed on its first run and succeeded on a manual retry. The layout afterwards:

    review/complete/01-review-opus.md + .progress.md + .stream.jsonl + .usage.json
    review/failed/01-review-opus.progress.md + .usage.json      (no .md)

Four facts compose into the crash:

1. `plan-runner-lib.sh::finalize_plan` files all four sidecars as a set — success to
   `complete/`, any non-zero rc to `failed/`. The graceful usage-limit branch (rc==2)
   never fired, because `stream_shows_usage_limit` only recognises a final
   `type=="result"` event and a hard-killed session emits none; the kill was filed as an
   ordinary failure. Retry is manual (`RUNNER.md`), and the retry writes a *fresh*
   progress log and usage sidecar beside the plan's new location. Nothing reconciles the
   pair left behind.
2. `analysis/report.py::build_usage_index` walked `feature_dir.rglob("*.usage.json")`
   and keyed one dict by each file's `"plan"` field, last visited winning — which is
   filesystem order, and `failed/` beat `complete/`.
3. `compute_plan_length_vs_loc` then read `usage_path.with_name(f"{stem}.md")` beside the
   *winning* usage file, i.e. `failed/01-review-opus.md`, which does not exist.
4. `find_orphan_usage` flags stems missing from the manifest, so a same-stem twin is not
   an orphan and nothing else in the pipeline notices.

The workaround was to delete the two `failed/` files (vinylCatalogue `48e0f12`). That
threw away a session id, which is exactly what this feature exists to stop being the
answer.

## The rulings

1. **The `failed/` pair stays where the runner put it.** It is the record of the killed
   attempt and carries the session id `analysis/recover_attempts.py` needs to recover
   that attempt's cost from its transcript. No runner change files, renames or deletes
   it. `RUNNER.md`'s `failed/` paragraph documents this as a decision: after a retry
   succeeds, a stale pair may sit in `failed/` beside nothing, and the analysis handles
   it.
2. **`build_usage_index` becomes deterministic and plan-aware.** Candidates for a stem
   are sorted, never taken in filesystem order. Among several usage files claiming one
   `plan`, the **live** one is the one whose sibling `<stem>.md` exists; if more than one
   has a sibling, or none does, the tie breaks by directory rank
   `complete` > `inprogress` > `incomplete` > `failed`. The index returns, per stem, the
   live usage path **and** the other same-stem paths as prior attempts, in one shape
   every caller consumes.
3. **A missing sibling `.md` is a warning, never a crash.** Every reader of a sibling
   plan file skips the plan with one warning line naming the path it looked for.
4. **A prior attempt's money counts once.** A plan's cost is the live sidecar's
   `total_cost_usd` plus, for each prior attempt, its `total_cost_usd` when non-null and
   its `attempts[].recovered_cost_usd` when present — so a killed attempt whose cost the
   weekly sweep later recovers into the `failed/` sidecar is not dropped merely because
   that file lost the index. A plan is "priced without cost" only when the live file has
   null cost **and** no prior attempt contributed anything.
5. **A regression test, written first.** `self/tests/stale-failed-sidecars.sh`, in the
   style of the existing scripts: a throwaway `mktemp -d` checkout, no model, no network.
   It stands up the layout above and asserts that `report.py` exits 0, that the reported
   cost is the `complete/` sidecar's, that a `recovered_cost_usd` planted in the
   `failed/` sidecar's `attempts[]` is added to it, and that the choice does not depend
   on which directory the filesystem offers first.
6. **What is found and left goes to a backlog file**, not to `NOTES.md`. The repo had
   none; `self/BACKLOG.md` is created in the shape of `vinylCatalogue`'s, one bullet per
   item phrased as the assertion that would catch it.

## Plans

| Plan | Model | Does |
|---|---|---|
| `84-review-opus` | opus | Independent review of the diff against `main`, from this manifest, not from the builder's report. |

Built direct (`method: "direct"`): no `auto/`, no `verify/`. `CHECKPOINT.md` and
`NOTES.md` are the implementer's; the regression test is the acceptance test, written
and confirmed red before the fix.

## Deliberately excluded

- **The runner's routing.** `finalize_plan` still files all four sidecars as a set and
  still sends a non-zero rc to `failed/`. Ruling 1 is the whole answer: nothing about
  where the pair lands changes, so nothing in `plan-runner-lib.sh` does.
- **`write_usage_sidecar`.** The sibling feature `recover-cost-at-close` owns it. A
  fresh sidecar beside the retried plan is correct behaviour, not the defect.
- **`stream_shows_usage_limit`'s blindness to a hard-killed session.** It is the reason
  the kill was filed as an ordinary failure and the graceful rc==2 path is dead for that
  case — a real defect, but a runner-routing one, and fixing it would not have prevented
  the crash (a usage-limit kill leaves the plan in `inprogress/`, which the retry moves
  the same way). First entry in `self/BACKLOG.md`.
- **`feature-close.sh`.** It crashed because `report.py` did; it is the sibling
  feature's file, and a close that survives a broken report by catching the exception
  would hide the next such defect rather than fix it.
- **`analysis/recover_attempts.py`.** It walks the feature tree with its own `rglob`
  rather than through the index, so it already reaches the `failed/` sidecar and needs
  no change. Confirmed by reading, recorded in `NOTES.md`; also the sibling's file.
- **The printed wording of the unpriced-plan warning.** Ruling 4 changes what triggers
  it. The string itself belongs to `recover-cost-at-close`.
- **A cleanup step anywhere.** No script gains a "tidy `failed/`" mode. Ruling 1 makes
  the pair durable on purpose; a cleanup would be the deletion this feature exists to
  make unnecessary.
- **Cross-feature stem collisions.** `build_usage_index` is still scoped to one feature
  directory, which is what makes a same-stem collision within a feature the only one
  reachable. Unchanged.

## Machine-readable

```json
{
  "slug": "stale-failed-sidecars",
  "method": "direct",
  "plans": ["84-review-opus"],
  "branches": ["stale-failed-sidecars"],
  "base": "main",
  "session_window": {"from": "2026-09-06T14:00:51Z", "to": "2026-09-06T14:27:21Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["2d8b1236-3e77-450f-bc9e-8165c0cf9f9c"],
  "subagents": ["ab4d692c430b2d183", "a14960570a76ddd81"]
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
