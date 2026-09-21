# Capture on the branch

The second of the three lifecycle-restructure features (`self/DESIGN-2026-09-16-lifecycle-restructure.md`
§3.2, §3.3, §3.6, §4). A feature's cost capture used to be a manual post-merge close,
run by the human from the primary checkout on `main`, which committed and pushed the cost
records straight to `main`. It now runs **on the feature branch, before the merge**:
`feature-close.sh` becomes `feature-capture.sh`, run from the worktree, and `run-review.sh`
calls it after `pr.sh` on a clean pass, so the cost records, the trailing timing stamps
and the router's refreshed routing record ride the PR, and the merge is the freeze.
Teardown already belongs to the next `feature-start.sh`'s prune. Merging the PR is the
last step of a feature. Built direct (`AGENT_DIRECT.md`), one implementer, tests first,
then the review pass — which is the first to capture itself.

## Slices

| Slice | What it does |
|---|---|
| acceptance tests | `self/tests/feature-lifecycle.sh` rewritten for the new flow (capture on the branch, the review tail, `PR_AUTO_MERGE`, the shim, prune after merge, post-merge repair and legacy captures, the W phases from the worktree); new `self/tests/capture-from-worktree.sh`; `recover-at-close.sh` C/E/F moved to `feature-capture.sh`; `routing-record.sh` R6; `sync-check.sh` at `pr.sh` v3. All red, committed on their own. |
| 1. analysis | `roots.session_root` follows a linked worktree's `.git` file to its primary checkout, so the worktree's copy selects what the primary's would; `manifest.py set-window-to --replace`, the pre-merge rule that moves `to` either way; `routing.py --refresh-for <slug>`, which re-derives every record naming the slug and keeps the entries its transcript never carried. |
| 2. `feature-capture.sh` | The capture, renamed from the close and rebuilt: on the branch it refuses stray dirt, stamps `to` from evidence, recovers, captures, reports, refreshes the router, warns about unclaimed delegates, commits the cost records and pushes the branch; after the merge it captures a legacy or repaired feature locally, committing and pushing nothing. `feature-close.sh` is a shim that refuses and names it. |
| 3. `run-review.sh` | After a clean pass: `pr.sh` → `pr_opened` → `pass_end` (once, `stamp_pass_end` in `plan-runner-lib.sh`) → the capture, advisory, with the re-run command on failure. |
| 4. `pr.sh` | Both copies at `template-version: 3`: an `auto_merge` step behind `PR_AUTO_MERGE` (template reads the environment, `self/pr.sh` pins it off), `TEMPLATE_VERSIONS` re-recorded, the consumer hand-merge in the root README's "Adopting capture on the branch". |
| 5. docs | `LIFECYCLE.md` steps 5–6 and rules 2–3, root `README.md` rows and "Updating", `AGENT_DIRECT.md`, `ORCHESTRATION.md`, `RUNNER.md`, `AGENT_PLANS.md`, `analysis/README.md`, `TEMPLATE.md`, `templates/plans/README.md`, `self/PROJECT_FACTS.md`, `self/README.md`, `self/tests/README.md`, `feature-start.sh`'s printed last step, and every stale `feature-close.sh` reference in code comments. |

## Deliberately excluded

- **`sweep.sh` retirement and the §3.8 audit fixes** — the third feature,
  `sweep-retirement-and-audit-fixes`, which deletes what this one makes redundant.
- **The open design points** — a per-feature budget in the fence, relaxing the
  `git stash list` deny. Undecided; not built.
- **`PR_AUTO_MERGE` on for agentTooling.** The opt-in exists in the template, off by
  default; `self/pr.sh` keeps it off regardless, because a change here ships to every
  consumer and a human reads the PR first.

## Machine-readable

```json
{
  "slug": "capture-on-branch",
  "method": "direct",
  "plans": ["107-review-opus"],
  "branches": ["capture-on-branch"],
  "base": "main",
  "session_window": {"from": "2026-09-17T14:37:32Z", "to": "2026-09-17T15:22:39Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["afc62e34408848a2b"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base and `from`, with the id lists empty — and
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
