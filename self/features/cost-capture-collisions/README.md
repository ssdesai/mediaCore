# The cost capture survives id collisions, partial ledgers and sole-claimant pins

Three capture defects that bite locally as well as in the cloud
(`self/DESIGN-2026-10-05-cloud-execution.md` §4, §6, §10). **§4:** a runner's `claude -p`
child inherits `CLAUDE_CODE_SESSION_ID`, reports the parent's id, and appends its lines to
the parent's own transcript file (reproduced in this container, below), so the parent's id
lands in a `usage.json`, the capture excludes the coordinator as a runner session, and
`find_pinned_elsewhere` then skips the directory holding its pinned delegates —
`cloud-close` recorded $1.92 of roughly $9.30. **§6:** `--annotate-frozen` reads absence
from the claims ledger as "no longer a claimant", so a fresh container's empty ledger
deleted `also_claimed_by` from 11 frozen sibling records at `cloud-close`'s close. **The
sole-claimant cut:** a pinned session with no other claimant is billed whole, so
`cloud-self-gate` carries a 9.7-hour design session for a 14-minute feature. Built
direct, by one opus implementer, in the cloud session on its assigned branch; the first
feature started and closed through the scripts' steps in the cloud (§10).

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Independent review of the build against design §4, §6 and the sole-claimant ruling below, written before the build. Round 1: escalated (`escalations/01-review-opus.md`). |
| `review/incomplete/02-review-sonnet.md` | Round 2: the re-review scoped to round 1's escalation — the pinned fallbacks' collided-parent handling. Clean; closed as PR #80. |
| `review/incomplete/03-review-sonnet.md` | Round 3: the design §10 bullet recording what the close found, committed after the close and so reviewed on its own. |

## §4 reproduced (2026-10-05, this container)

`claude -p --model haiku --output-format stream-json --verbose "…"`, run from this
session with its environment inherited, reported `session_id` equal to the parent's
`CLAUDE_CODE_SESSION_ID` on every event, and wrote **no transcript file of its own**: its
lines were appended to the parent's `<id>.jsonl` as a new root (`parentUuid: null`, a
`user` line with `promptSource: "sdk"`), carrying the parent's `entrypoint` (`remote`,
itself inherited through `CLAUDE_CODE_ENTRYPOINT`) — so no field a line carries for
certain says "headless". The same call under `env -u CLAUDE_CODE_SESSION_ID -u
CLAUDE_CODE_REMOTE_SESSION_ID` with `--session-id <uuid>` reported that uuid and wrote its
own `<uuid>.jsonl`.

## The sole-claimant cut: decided

**A pinned session is cut to its window whatever the number of claimants; a
branch-selected session with one claimant is still billed whole.** Concretely, the
single-claimant shortcut in `select_parent` no longer applies to a pin: a pinned session
goes through the split `share_owners` and `partition_seconds` already apply, with the
claim set `[this feature]` when nobody else claims it. Its responses inside `[from, to)`
are this feature's; the opening stretch before `from` is this feature's for as far back as
the window is long (`head_bound`, unchanged); everything else is the unclaimed remainder
— `unclaimed_usd` and `unclaimed_duration_s`, disclosed by the existing warning with its
remedies (`set-window-from`, or a pin elsewhere). A window whose `to` is still `null` cuts
nothing at the tail and keeps the unbounded head, exactly as the shared path does.

Why the line falls there:

- **A pin is the claim that reaches past the feature's own evidence.** It claims a
  session "regardless of branch, window or `cwd`" (`LIFECYCLE.md` rule 1), and the
  sessions it is written for — a coordinator launched on `main`, a design session moved
  to the assigned branch half-way — did other work too. The window is the only thing the
  manifest says about which part was this feature's.
- **One rule for one claimant and for two.** Today a second claimant appearing on a
  pinned session takes the first one's tail away from it; with one claimant it is paid
  in full. The figure should not jump on whether somebody else happened to pin the same
  session.
- **A branch session is the feature's by rule 1**, and its window is stamped from the
  same evidence (`last_branch_instant`): selection requires its start inside the window,
  and `to` is one second past its last instant at the capture, so a cut would remove
  nothing at the first capture. Cutting it would change every consuming repo's ordinary
  path for no measured case.
- **The old objection — "a disclosed over-count traded for a silent under-count" — no
  longer holds for a pin**: the cut part is not dropped but reported as the unclaimed
  remainder with the remedy named, as the head and tail of a shared session already are.

Frozen records of merged features are not recaptured: `cloud-self-gate`'s stays as its
README describes it, and the cut applies from the next capture of each feature.

## Deliberately excluded

- **Branch selection of a session that started before `from`** (design §3). In the cloud
  the coordinator is launched on the assigned branch before the feature exists, so its
  start precedes the `from` the start stamps, and the branch route does not select it at
  all (`select_parent` matches on the session's start). That is `execution-profiles`'
  start (`create_checkout`, the window it stamps); until then the remedy is the existing
  `manifest.py set-window-from`, which this feature's own close uses.
- **Recapturing `cloud-close` and `cloud-self-gate`.** Their transcripts went with their
  containers, and merged records are not rewritten.
- **`forge.sh auto-merge`, the detector, and the cloud start** — `execution-profiles`.

## Machine-readable

```json
{
  "slug": "cost-capture-collisions",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet", "03-review-sonnet"],
  "branches": ["claude/cost-capture-collisions"],
  "base": "main",
  "session_window": {"from": "2026-10-05T17:34:54.986Z", "to": "2026-10-05T18:30:24Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
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
