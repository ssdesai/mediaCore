# One lifecycle, local and cloud, behind a detector and adapters

The last feature of `self/DESIGN-2026-10-05-cloud-execution.md` (§10): the rest of §1, §2,
§3 and §5, plus §7, §8 and §9's `sleep` reason. One detector (`env-profile.sh`) decides
`local` or `cloud`, and a few adapters with fixed interfaces — the checkout layout,
`forge.sh`, the seeded `open-session.sh`, `worktree-setup.sh`, `environment.sh` and
`cloud-setup.sh` — hold every difference, so `feature-start.sh`, the close, the capture and
the runners never ask where they are running. In the cloud the container is the worktree
and the feature runs on the session's assigned branch; the session that starts it there is
its coordinator, not a router. Also fixes the start-instant finding `cost-capture-collisions`
recorded: a cloud coordinator, launched before the start stamps `from`, was not selected by
the branch route. Built direct, by two implementer delegates in order (slice A, then B), in
the cloud session on its assigned branch, started by hand with `main`'s scripts the way
`cost-capture-collisions` was (this feature changes `feature-start.sh` itself).

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Independent review of both slices against the design sections above and the rulings below, written before the build. Round 1: escalated (`escalations/01-review-opus.md`) — the resumable gate never resumed under a runner. |
| `review/incomplete/02-review-sonnet.md` | Round 2: the re-review scoped to round 1's escalation — the features corpus left out of the gate's tree sha. |

## Rulings taken before the build

- **The start-instant fix lives in the start.** When the start finds that the session
  running it is the feature's coordinator (§3: launched on the feature's branch — in the
  cloud, every session), it stamps `from` at that session's first transcript instant
  rather than at the start's own clock, falling back to the clock with one warning line
  when the transcript cannot be read. That is exactly what `set-window-from` did by hand
  for `cost-capture-collisions`, and it keeps the capture's branch route (select by the
  session's start) unchanged for every consuming repo. Consequence, accepted: the
  session's spend before the start — reading the design for this very feature, since a
  container holds one feature — is billed to the feature, not left in the unclaimed
  residue as §3 first assumed. A router (launched on another branch) is untouched.
- **"Launched on" is the branch the checkout was on when the start began**, before any
  `git checkout -b` the start itself does. Locally that is `main`, never `S`, so the local
  start always writes the routing record exactly as today.
- **`pr.sh`'s merge request through `forge.sh auto-merge` is a body change**, so the
  template moves past `template-version: 5` (which `cloud-close` already shipped, with the
  README's "Adopting the forge adapter" section) and that section gains the hand-merge.
- **No new place reads the profile variables.** Lifecycle scripts call functions the
  detector defines (the profile name, the variable that decided it, the layout functions);
  only the detector, the adapters and their tests spell `CLAUDE_CODE_REMOTE` or
  `AGENTTOOLING_PROFILE`.

## Deliberately excluded

- **§4 and §6** — built by `cost-capture-collisions`.
- **Fixing consuming repos' own scripts and tests** (design §12): each repo's cloud setup
  is its own feature, using the seeded files.
- **Several features per container** (design §12): refused by the start, by rule.

## Machine-readable

```json
{
  "slug": "execution-profiles",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["claude/execution-profiles"],
  "base": "main",
  "session_window": {"from": "2026-10-05T19:07:36.300Z", "to": "2026-10-05T21:37:20Z"},
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
