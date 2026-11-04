# Permissions policy, inherited

The permission policy this harness works under had been living in per-machine
`settings.local.json` files — and, in agentTooling's own checkout, nowhere at all. This
feature moves it into the two channels that already reach every consuming repo: the
`PreToolUse` hook, which now approves the harness's own read-only entry points and denies
every git command that moves a ref, and `wire-settings.py`, which now merges `Bash` deny
rules beside the `Edit` ones and can write agentTooling's own checkout with `--self`. The
same policy therefore binds here, in a committed `.claude/settings.json` the gate keeps in
sync with the constants that generate it. Built direct (`AGENT_DIRECT.md`), one
implementer, tests first.

## Slices

| Slice | What it does |
|---|---|
| acceptance tests | `self/tests/allow-repo-commands.sh` gains the entry-point and git-deny cases, `self/tests/hook-wiring.sh` the `Bash`-rule and `--self` cases, and `self/tests/plan-numbering.sh` is new; all red, committed on their own. |
| 1. entry-point approvals | `allow-repo-commands.sh` approves `gate.sh`, `check-plans.sh`, `bash -n`, `shellcheck`, `python3 [-B] -m py_compile`, `report.py`, a listing `capture_planning.py` and `manifest.py get` — matched by basename, only inside the root. |
| 2. the git deny | A second deny shape: any ref-moving or history-rewriting git command, wherever it sits on the line, with a reason naming `LIFECYCLE.md` rule 2 and the two lifecycle scripts. |
| 3. `Bash` deny rules | `BASH_DENY_RULES` in `wire-settings.py`, merged into `permissions.deny` exactly as the `Edit` rules are, counted per kind in both modes' messages. |
| 4. `--self` wiring | `wire-settings.py --self` writes this checkout's hook path and `Edit(/hooks/**)`; the resulting `.claude/settings.json` is committed and `self/gate.sh` records the matching `--check`. |
| 5. plan numbering | `feature-start.sh`'s `--self` branch reads a leading digit run of any length and sorts numerically, so the corpus's next stem is `105` rather than a second `100`. |
| 6. docs | `hooks/README.md`, root `README.md`, `LIFECYCLE.md` rule 2, `self/README.md`, `self/tests/README.md`, `self/PROJECT_FACTS.md`, and a `self/BACKLOG.md` entry. |

## Deliberately excluded

- **Sandboxing.** Deny rules and a hook bind the Edit/Write tools and the Bash permission
  check; a subprocess that opens a file itself is unaffected, as `hooks/README.md` already
  says. OS-level enforcement is a different mechanism and a different feature.
- **Widening the approvals past the harness's own entry points.** Every rule here is one
  command the executors already run many times a batch; anything that writes, freezes a
  cost record or moves a ref still prompts.
- **`CONVENTIONS.md`.** The git deny is lifecycle authority, not command shape;
  `LIFECYCLE.md` rule 2 names it instead (`NOTES.md`).
- **The vendored `agentTooling/.claude/settings.json` that ships with the subtree.**
  Nothing reads it today; the hazard if that changes is filed in `self/BACKLOG.md` rather
  than fixed by changing what the split carries.

## Machine-readable

```json
{
  "slug": "permissions-policy-inherit",
  "method": "direct",
  "plans": ["100-review-opus"],
  "branches": ["permissions-policy-inherit"],
  "base": "main",
  "session_window": {"from": "2026-09-16T16:07:00Z", "to": "2026-09-16T18:03:27Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["8a695645-c764-471b-98f3-751e6c484adf"],
  "subagents": ["aca83fbc6e0d979be"]
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
