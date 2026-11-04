# Stream capture, file first: a closed consumer must not truncate the record

Nine merged reviews were recorded at `$0.00` — `total_cost_usd: null`, `num_turns: null`
— although every one of them ran to completion, exited 0 and opened its PR. Their
`.progress.md` files are **0 bytes** and their `.stream.jsonl` files stop a few hundred
bytes in, right after the `init` event. Nothing was wrong with the runs or with the CLI:
the *capture* was truncated, because the file was written by a `tee` in the middle of a
pipeline whose last stage wrote to the caller's stdout. When the caller stopped reading,
the pipeline died from the far end backwards and took the record with it, while `claude`
— which never noticed — carried on to a clean exit. This feature makes the captured
stream and the progress log independent of anything downstream of them, and makes the
one combination that can only mean a lost capture say so out loud.

## The defect

In `plan-runner-lib.sh::run_plan`:

    claude -p ... --output-format stream-json --verbose "$(build_prompt ...)" 2>&1 \
      | tee "$stream_file" \
      | tee "$log_fifo" \
      | display_stream
    local exit_code=${PIPESTATUS[0]}

Five facts compose into the loss:

1. `$stream_file` is written by a `tee` in the **middle** of the pipeline. Its liveness
   depends on the stage after it, and on the stage after that.
2. The last stage, `display_stream`, inherits the caller's stdout. Every affected review
   was launched by a coordinator session as a backgrounded Bash command whose stdout was
   piped onward; the reviews launched in the foreground priced normally.
3. When that consumer closes early, `display_stream` dies of SIGPIPE, then each `tee`
   dies on its next write. The file stops growing at whatever byte the second `tee` had
   reached — 689 bytes, the `init` event and nothing after.
4. `claude` does not die with them: its stdout is the pipe into the first `tee`, and it
   had already written everything the pipe would take. It runs to completion, so
   `PIPESTATUS[0]` is 0 and `finalize_plan` files the plan as a success.
5. Everything downstream of the stream file is then reading a stump.
   `write_usage_sidecar` finds no `result` event and records null cost and null turns;
   `log_stream_events`, fed by the same dead pipeline through the FIFO, writes an empty
   `.progress.md`; and `stream_shows_usage_limit` and `stream_shows_budget_exhausted`,
   which both inspect the final `result` event, are blind.

Probed on this machine: a producer that ignores SIGPIPE, piped through
`tee FILE | head -2`, leaves 38 of 50,000 lines in `FILE`.

The nine: musicMap `pin-ruff`, seven vinylCatalogue features, and agentTooling
`stale-failed-sidecars`. Their transcripts under `~/.claude/projects/` all end normally
with `end_turn`, which is how the loss was identified as a capture failure rather than a
CLI omission.

## The rulings

1. **The stream file is complete no matter what happens downstream of it.** Nothing that
   consumes the runner's stdout may be able to truncate `$stream_file`. The preferred
   design, taken where it can be made deterministic on bash 3.2 + macOS: **file first** —
   `claude` writes `$stream_file` directly (`> "$stream_file" 2>&1`, keeping the existing
   stderr merge), and the progress FIFO and `display_stream` are fed by a follower of
   that file. The follower must drain deterministically after `claude` exits — every byte
   `claude` wrote reaches the FIFO logger before `run_plan` moves on — without writing
   any sentinel into the stream file, which `write_usage_sidecar` and
   `stream_shows_usage_limit` parse. The fallback, if that cannot be made deterministic,
   is to keep the pipeline with SIGPIPE ignored in the two `tee`s and in
   `display_stream`, so a dead consumer stops only the display. Either way `run_plan`
   still reports `claude`'s own exit code, a closed consumer does not fail the plan, and
   the FIFO/`wait "$log_pid"` race the existing comment guards stays closed.
2. **The progress log is complete too.** `log_stream_events` receives every event
   `claude` wrote, consumer or no consumer. A `.progress.md` for a run that edited files
   can never again be 0 bytes.
3. **A silent capture failure becomes loud.** In `finalize_plan`, `rc == 0` together with
   a stream holding no `type == "result"` event — the one combination that is never
   normal — prints a warning naming the plan and the stream file, and the stream file
   stays on disk. This is the catch behind the fix, so the next occurrence leaves
   evidence instead of a `$0.00` row.
4. **Tests, first.** A new script in `self/tests/`, in the style of its neighbours: a
   throwaway `mktemp -d` checkout, a stub `claude`, no model and no network, driving a
   real runner invocation. The stub ignores SIGPIPE, emits an `init` event, a few
   thousand `assistant`/`tool_use` events and a `result` event with a cost, and exits 0.
   Asserted with the runner's stdout piped to a consumer that closes after two lines,
   again with stdout to a file, again with a stub that emits no `result` event, and once
   more over the existing usage-limit routing. Registered in `self/gate.sh`, which does
   not glob.
5. **Backlog.** This feature fixes the defect, so it adds no entry for it. The sibling
   feature `recover-cost-at-close` carries one on its branch that this feature closes;
   whoever merges last deletes it. Anything found and not fixed goes into
   `self/BACKLOG.md` in that file's shape.
6. **Docs.** `RUNNER.md` wherever it describes the capture pipeline and the stream and
   progress files, the comment block above the capture in `run_plan`, and
   `self/PROJECT_FACTS.md` if it states anything about how the stream is captured.

## Plans

| Plan | Model | Does |
|---|---|---|
| `86-review-opus` | opus | Independent review of the diff against `main`, from this manifest, not from the builder's report. |

Built direct (`method: "direct"`): no `auto/`, no `verify/`. `CHECKPOINT.md` and
`NOTES.md` are the implementer's; the new `self/tests/` script is the acceptance test,
written and confirmed red before the fix.

## Deliberately excluded

- **`write_usage_sidecar`.** The sibling feature `recover-cost-at-close` owns it. It read
  the stump honestly — null cost from a stream with no `result` event is the correct
  answer to the question it was asked. The fix is upstream of it, in what the file
  contains.
- **`feature-close.sh` and the `analysis/` scripts.** The sibling's files. `report.py`
  and `recover_attempts.py` read the sidecars this feature stops corrupting; neither
  needs to change for the capture to be whole.
- **The sidecar's `result_event: "seen"|"missing"` field.** The sibling adds it. Ruling 3's
  warning is derived from the stream file itself — the last event, and `total_cost_usd` —
  so nothing here depends on that field and nothing here writes one. (It was not on `main`
  when this manifest was written; the sibling merged during the build. The independence is
  what matters, and it is unchanged either way.)
- **The accounting of the nine already-affected features.** Recovering their spend from
  the transcripts is `recover-cost-at-close`'s work and needs the transcripts, not the
  runner. This feature stops the tenth.
- **`stream_shows_usage_limit`'s blindness to a hard-killed session** (`self/BACKLOG.md`,
  first entry, raised by `stale-failed-sidecars`). A different defect with a similar
  smell: that one is a session cut off mid-turn so no `result` event was ever *emitted*;
  this one is a `result` event emitted and thrown away. Ruling 1 makes the second
  impossible and does nothing about the first, which still needs a second signal beside
  the `result` event.
- **Making `display_stream` prettier, or configurable.** It is a consumer, and the point
  of the ruling is that a consumer's fate no longer matters. Its output is unchanged.
- **Retrying or resuming a plan whose capture was lost.** Ruling 3 warns; it does not
  re-run. A plan that finished its work and opened its PR must not be re-executed on the
  strength of a missing event, and a human reading the warning is the right next step.

## Machine-readable

```json
{
  "slug": "stream-capture-file-first",
  "method": "direct",
  "plans": ["86-review-opus"],
  "branches": ["stream-capture-file-first"],
  "base": "main",
  "session_window": {"from": "2026-09-06T15:06:37Z", "to": "2026-09-06T16:05:10Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["2d8b1236-3e77-450f-bc9e-8165c0cf9f9c"],
  "subagents": ["a5200f02c1d0f33da", "a4278d692d2a9f192"]
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
