# The self gate is green in a cloud container

`self/gate.sh` returned a red verdict in a fresh cloud container, so nothing could be
gated there (`self/DESIGN-2026-10-05-cloud-execution.md` §10). Each of the three red
checks was the test depending on the machine it ran on, not a defect in what it tests.
Each is fixed in the fixture or the checkout, and no assertion changed. Built by hand in
the cloud session on its assigned branch, the bootstrap §10 describes.

## Fixes

| Red check | Cause | Fix |
|---|---|---|
| `feature-lifecycle` S4h–S4n | The bare `origin.git` was made with a plain `git init --bare`, so its HEAD named the machine's `init.defaultBranch`. The container sets none, so HEAD was `master`, and the forge clone at S4h checked out an empty head (`fatal: Non-fast-forward commit does not make sense into an empty head`). Every later S4 assertion inherited that. It passed locally only because the author's global config says `main`. | `git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main`, the idiom the primary and `propagation-pull.sh` already use. Applied to the same latent gap in `recover-at-close.sh`, `plan-numbering.sh` and `start-takeover.sh`. None of those clones its origin today. |
| `allow-repo-commands` | `link-home` linked the real `$HOME`. A container's `/root` holds only dotfiles, so `cat link-home/*` matched nothing and fell back to a path that names nothing. The hook approves that by design (`hooks/README.md`, "a file that does not exist cannot be read"). The denial held only where the home directory had a visible file, and `cat link-home/.zshrc` only where it had a `.zshrc`. This was not a confinement bug: nothing outside the tree is read. | `link-home` points at a home directory the test builds under its own temp directory, holding `.zshrc` and a visible file. |
| `hook-wiring` | The checkout had no `.claude/settings.json`. The file is generated and git-ignored, so a fresh clone never has one. | Generated with `python3 -B hooks/wire-settings.py --self --repo <root> --write`. Making a cloud checkout start with the file is `execution-profiles`' `cloud-setup.sh` (§7), not this feature. |

## The cost record carries the design session

`planning.json` bills $8.47 and 587 minutes as build. Almost all of it is the session that
wrote `self/DESIGN-2026-10-05-cloud-execution.md`, which planned all four features; this
feature's own work is the last ~14 minutes. The record was captured by hand because
`feature-capture.sh` looks for a branch named after the slug (design §2). The session was
launched on `main` and moved to the assigned branch mid-session, so it is pinned. A pin
with no other claimant is billed whole: the window only splits a session between
claimants, it does not cut a sole claimant down. The figures were kept, not dropped,
because the transcript goes with the container and nothing can recapture it. Read this
record as the design plus this feature, not as the cost of the fix. The sole-claimant cut
is `cost-capture-collisions`' to decide.

## Deliberately excluded

- **Isolating every fixture's global git config** (`GIT_CONFIG_GLOBAL`,
  `GIT_CONFIG_NOSYSTEM`), which §10 proposed while the cause was unknown. The cause turned
  out to be one unpinned default, and pinning it is the narrower fix. Blanket isolation
  would also hide the config a real checkout runs with.
- **Changing the hook's "names nothing" rule.** I tried refusing a relative path whose
  existing prefix leaves the tree, then reverted it. It reverses a documented ruling for a
  case that reads nothing, and the defect was the fixture's.
- **Wiring `.claude/settings.json` at container start**, which belongs to
  `execution-profiles` (§7).

## Machine-readable

```json
{
  "slug": "cloud-self-gate",
  "method": "hand",
  "plans": ["01-review-opus"],
  "branches": ["claude/cloud-execution-design"],
  "base": "main",
  "session_window": {"from": "2026-10-05T15:23:54Z", "to": "2026-10-05T15:37:28Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["df1f4271-9d04-563c-80ce-30d0feb1f6db"],
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
