# The start procedure, and routing overhead

The first of the three lifecycle-restructure features (`self/DESIGN-2026-09-16-lifecycle-restructure.md`
§2). It settles who pays for the session that *opens* a feature. That session — the
**router** — runs `feature-start.sh`, belongs to no one feature, and used to be pinned into
whichever manifest it happened to write, billing one transcript to every feature it
started. It is now pinned into none of them: the start writes a derived **routing record**
beside the feature corpus, commits it in `S: start` so the router-to-feature link is in git
before the transcript can age out, and `report.py` reports that spend as a category of its
own. Around that, the start grew the rest of its procedure — it prunes the worktrees whose
branches have merged, and `--open` hands the new worktree to a repo-owned hook that puts a
coordinator session inside it, which is where a feature's work is claimed with no pin at
all. Built direct (`AGENT_DIRECT.md`), one implementer, tests first, then a review pass and
a rework one-shot for what that review escalated.

## Slices

| Slice | What it does |
|---|---|
| acceptance tests | `self/tests/routing-record.sh` is new (the record, router detection, the report table); `self/tests/allow-repo-commands.sh` gains the assignment-deny cases and `self/tests/feature-lifecycle.sh` the S phases. All red, committed on their own. |
| 1. `analysis/routing.py` | Derives one router's record from its own transcript — byte-identical for identical input, `captured_at` from the content and not the clock — plus the router predicate `capture_planning` imports and the `routers_of` lookup `report` imports. |
| 2. `feature-start.sh` | Pins nothing by default (`--pin` is the opt-in, `--no-pin` an accepted no-op); prunes every merged worktree under `.worktrees/`; writes and commits the routing record in `S: start`; `--open` runs the repo's session hook. |
| 3. `open-session.sh` | A fifth repo-owned seeded script: `templates/plans/open-session.sh`, `self/open-session.sh`, their `sync-plans.sh` and `TEMPLATE_VERSIONS` rows, and the `sync-check.sh` / `template-versions.sh` assertions that keep the two copies honest. |
| 4. hook deny | `hooks/allow-repo-commands.sh` denies an assignment at command position whose own `$NAME` is used later on the same line, with the `CONVENTIONS.md` § Shell commands paragraph that explains it. |
| 5. `capture_planning.py` | Routers drop out of `--list-sessions --unclaimed` — they have a category, and no manifest will ever pin them. |
| 6. `report.py` | `--all` gains the Routing table and routing spend as a fraction of feature spend; `report.py <slug>` gains the "routed by" line. |
| 7. sandboxes | Thirteen test files copy `routing.py` too, since `capture_planning.py` and `report.py` both import it and a missing copy is an `ImportError` in every capture. |
| 8. rework | The six items the first review escalated: `git branch -D` in the prune, a vendored-checkout start phase, the `captured_at` conflict rule, command-position router detection, a quoted worktree path in both `open-session.sh` copies, and `routers_of` called rather than re-implemented. |

## Deliberately excluded

- **Everything else in the design.** Nothing from §3.2, §3.3, §3.5, §3.6's close-side
  items or §3.8 is touched — they are the next two features (§6). `feature-close.sh`,
  `run-review.sh`, `pr.sh`, `sweep.sh` and the close half of
  `self/tests/feature-lifecycle.sh` carry no diff from this feature.
- **A `wire-settings.py` deny twin for the assignment rule.** A `permissions.deny` entry
  is a command *prefix*, and the shape being denied is a relation between two tokens
  anywhere on the line, which no prefix can express. Hook-only, as design §3.7 already
  anticipated; recorded in `hooks/README.md` beside the deny.
- **A mergeable routing-record layout.** One file per (session, slug) would make the
  add/add conflict go away, and it would also break the "one copy cannot disagree with
  itself" rule the record exists for. The conflict stays accepted, with a resolution rule
  (later `captured_at` wins) and a `self/BACKLOG.md` entry carrying the assertion that
  would close it.
- **Copying the routing record into `report.json`.** The record is the durable link
  (design §3.4); a frozen second copy inside a feature report could only disagree with it.

## Machine-readable

```json
{
  "slug": "start-procedure-and-routing",
  "method": "direct",
  "plans": ["105-review-opus", "106-review-opus"],
  "branches": ["start-procedure-and-routing"],
  "base": "main",
  "session_window": {"from": "2026-09-16T18:13:50Z", "to": "2026-09-16T21:46:33Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["a57d5db3e13584636", "adb65da1ae50a5e00"]
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
