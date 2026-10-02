# Live model rates

A model released after the last rate-history refresh is priced at `None` in every repo
until someone refreshes `rates_history.json` in an agentTooling self feature — even
though LiteLLM, which `refresh_rates.py` already reads, carries its price. humanNetworkMap's
access-views-write close reported $29.03 (partial) while four `claude-sonnet-5-5` helpers
went uncounted. This feature makes pricing ask LiteLLM itself, at the moment a model is
missing, so a new model is priced on the day it first appears; then refreshes the
history and recaptures this repo's one short record (sandbox-consumer-reads, one 4-second
sonnet-5-5 session). access-views-write is recaptured in humanNetworkMap after its
subtree pull (`self/BACKLOG.md`).

## The spec

1. **Live fallback in `analysis/pricing.py`.** When `get_rates(model_id, as_of)` finds no
   history entry for the model, it consults LiteLLM's price list (the same URL,
   selection and conversion `refresh_rates.py` uses) and, if the model is there, returns
   its rates with `source: "litellm-live"` and `from` the history-convention first date
   (`0000-01-01`). `compute_cost` then prices with them as normal. The fetch happens
   **only on a miss**, **at most once per process** (success or failure is cached), with
   the existing `FETCH_TIMEOUT_S`. Import of `pricing.py` stays network-free.
2. **One parser.** The fetch and the LiteLLM-entry → five-rates conversion
   (`upstream_entries` / `upstream_rates`, rounding to `RATE_DECIMALS`) move out of
   `refresh_rates.py` into a module both import, so the live price and a later refresh
   cannot disagree. `refresh_rates.py` already imports `pricing.py`, so `pricing.py`
   cannot import it back. `refresh_rates.py`'s behaviour and output are unchanged.
3. **The history is never written by the fallback.** `rates_history.json` ships through
   the subtree; only `refresh_rates.py` in a self feature appends to it. Because a new
   model's first history entry starts at `0000-01-01`, a later `--recapture` after the
   refresh reproduces the live figure unless LiteLLM changed the price in between.
4. **Failure stays loud.** A fetch that fails, or a model LiteLLM lacks (Mythos 5.1), is
   `(None, None)` exactly as today, and the existing unknown-model warnings still fire.
   Every caller that surfaces where a price came from (warnings, report, close summary)
   names a `litellm-live` price as such, so a figure resting on an unrefreshed history is
   visible, not silent.
5. **Offline seam.** The same seam the tests use for `refresh_rates.py`
   (`--source` / `RATES_CHECK_SOURCE`) points the live lookup at a local file; one env
   var also disables the lookup entirely. The test suite never touches the network.
6. **Repair, in this feature.** Run `python3 analysis/refresh_rates.py` (appends
   `claude-sonnet-5-5` and `claude-mythos-preview`, sets `checked`), then bring
   `self/features/sandbox-consumer-reads/planning.json` (and its report) up to the
   refreshed history with the repo's own repair tools, committing the diff.
   hook-hash-chained-cd needs nothing: its sonnet review `usage.json` costs are the
   CLI's own, and the `$0.0000 †` cells are the Rounds table's per-round build column.

## Deliberately excluded

- **Writing the history from the fallback.** It would make consuming repos diverge from
  the subtree and conflict on the next pull — the reason refresh is self-feature-only.
- **A third source (scraping Anthropic's pricing page).** Fragile; a model neither
  source carries stays `None` and is added by hand as a `"manual"` entry, as today.
- **Sandbox allowlisting.** The OS sandbox wraps only the executor's `claude -p`; the
  runner and capture that price usage run outside it, so no domain is added.
- **Consuming repos' own corpora.** Records there short on sonnet-5-5 are recaptured in
  those repos after the subtree pull, not from here.

## Machine-readable

```json
{
  "slug": "live-model-rates",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["live-model-rates"],
  "base": "main",
  "session_window": {"from": "2026-10-02T04:03:53Z", "to": "2026-10-02T04:42:05Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["27b81552-275d-43e8-a128-be68b0393419"],
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
  malformed id is refused — never by editing the fence. Find the id with
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
