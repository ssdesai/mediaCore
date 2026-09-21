# The close, and review rounds

The review pass ends in a verdict with two outcomes and the runner acts on it as if it had
one: every finished review opens the PR and freezes the cost record, so a rework after an
escalated review happens outside every gate — stale PR body, record replaced by hand,
delegates pinned by hand, no second review, no round in the timing file (measured on PR
#46). This feature gives the lifecycle its exit: `run-review.sh` records the verdict and
stops; an escalated review is a new round, briefed from `escalations/<stem>.md`; a real
`feature-close.sh` refuses unless the latest review is clean and judged the tree being
closed, then opens the PR, captures, pushes, and requests the merge **last**, which also
closes the `PR_AUTO_MERGE` race; every stamp carries its round and the report shows
rounds with verdicts. The spec is `self/DESIGN-2026-09-17-close-and-review-rounds.md`
(§2 the rule, §3 the verdict, §4 rounds, §5 the close, §6 the batch, §7 the direct flow,
§9 the tests). Built direct (`AGENT_DIRECT.md`) as two non-overlapping slices by two
implementer delegates coordinated from the primary, tests first in each, then the review
pass, then the close — this feature is the first one closed by its own script.

## Slices

| Slice | What it does |
|---|---|
| A. Acceptance tests, lifecycle | Design §9 V1–V3, X1–X3, RD (the lifecycle half), B1–B2, the rewritten T2/T3/T4/P2, `sync-check.sh`'s version rows — red first, in `self/tests/feature-lifecycle.sh`, `self/tests/sync-check.sh`, `self/tests/template-versions.sh`. |
| A1. The verdict | `run-review.sh`: `Verdict:` line in the prompt and read back (§3); `escalations/<stem>.md` written by the runner on escalated/unreadable; pass commit `<slug>: review round N`; `plan_end` with `verdict=` and `head=`; no PR, no capture; the next step printed. |
| A2. Rounds in the stamps | `plan-runner-roots.sh` `stamp_timing` adds `round` (§4), held per pass; `stamp-timing.sh` computes it fresh. |
| A3. `feature-close.sh` | The real script replacing the shim (§5): the four refusals, PR with the report plus the Rounds table, `pr_opened`, capture, `pr.sh --merge-request` last; re-runnable. The verdict reader shared with the batch (§6). |
| A4. `pr.sh` template-version 4 | `--merge-request` as a second entry point in `templates/plans/pr.sh` and `self/pr.sh`; the open step no longer requests the merge; contract comments rewritten. |
| A5. `run-batch.sh` | Clean → close; escalated → brief path, exit 1 (§6). |
| A6. Docs | `LIFECYCLE.md` (5 Review, 6 Close, 7 Merge, Propagate), `AGENT_DIRECT.md` §"The review is not optional" (§7), `RUNNER.md`, `AGENT_PLANS.md` → "Review plans", `ORCHESTRATION.md`, root `README.md` rows, `templates/plans/README.md`, `self/PROJECT_FACTS.md`, `self/README.md`, `self/tests/README.md`, the superseded note in `DESIGN-2026-09-16-lifecycle-restructure.md` §3.2. |
| B. Acceptance tests, report | Design §9 RD (the report half) and the no-`round` fallback — red first, in a new `self/tests/report-rounds.sh`. |
| B1. Rounds in the report | `analysis/report.py`: `rounds[]` in `report.json`, the Rounds table in `report.md` (§4), a renderer the close can call for the PR body; `analysis/README.md` field list. |
| C. Rulings and what is left | `NOTES.md`, `CHECKPOINT.md`, the `PR_AUTO_MERGE` entry removed from `self/BACKLOG.md`, `self/features/README.md`'s row. |

## Deliberately excluded

- **`hooks/`** — a parallel feature owns it. `feature-close.sh` is already listed there as
  an entry point that keeps prompting, which this feature makes true again.
- **`feature-start.sh`, the plan numbering, the capture's stray rule** — the lifecycle pair
  in the backlog; a follow-up, since the close commits before the capture and the
  by-hand capture path is unchanged here.
- **A script that writes the re-review brief** — the coordinator scopes it and picks its
  model; judgment, not procedure, for now.
- **An escalation count per round** — the brief is model-written; the report links it and
  does not parse it.

## Machine-readable

```json
{
  "slug": "feature-close-and-review-rounds",
  "method": "direct",
  "plans": ["110-review-opus"],
  "branches": ["feature-close-and-review-rounds"],
  "base": "main",
  "session_window": {"from": "2026-09-17T18:21:28Z", "to": "2026-09-17T20:32:52Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["ae0165e2b1626d066", "aa1e343c022b2e9e1"]
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
  regardless of branch, window or `cwd` — the top-level twin of `subagents`. **A pin is
  the exception now, not the rule.** `feature-start.sh` pins nothing unless given
  `--pin`: the session that starts a feature is a *router*, it opens several features and
  belongs to none of them, and its spend is routing overhead reported from
  `plans/routing/<session-id>.json` rather than billed to any feature
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
