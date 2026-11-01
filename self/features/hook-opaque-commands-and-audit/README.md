# Opaque commands are denied first, asked about second; and a hook audit

`hooks/allow-repo-commands.sh` approves what it can read and denies three shapes whose
fix is a substitution; everything it *cannot* read — a heredoc into an interpreter, code
as a string, a `$(…)` in a path — fell through to the permission prompt, so the human
paid a prompt and the model learned nothing. Decided with the user on 2026-09-17: an
unreadable command is **denied with the rewrite as its reason** (write the script to the
scratchpad, run it by name), and after `OPAQUE_REWRITE_ATTEMPTS` such denials in one
session the hook returns `ask`, so the human sees only what the model could not fix.
Under a headless runner (`AGENTTOOLING_HEADLESS=1`, exported by `plan-runner-lib.sh`
along with a per-pass `AGENTTOOLING_SCRATCH` directory the hook approves scripts from) the
escalation prints nothing, since nobody can answer. While the hook is open, an
adversarial audit of its approval analysis: every bypass found is closed and asserted,
every one considered is a row in `hooks/README.md`. Built direct (`AGENT_DIRECT.md`),
one implementer, tests first, then the review pass. The review brief is
`review/incomplete/108-review-opus.md`; its §1–§6 are the spec.

## Slices

| Slice | What it does |
|---|---|
| Acceptance tests | The six opaque shapes as denies and the four exemptions as not-denies in `self/tests/allow-repo-commands.sh`; a new `self/tests/hook-escalation.sh` for the counter, the `ask`, the reset, subagent keying, a corrupt state file, the headless fall-through and the scratch entry point; `self/tests/stream-capture.sh` phase 10 for the runner's two exports. Red, committed alone, registered in `self/gate.sh`. |
| The opaque deny | `is_opaque` in `hooks/allow-repo-commands.sh`: its own scanner (`opaque_segments`) over the raw text, since the whole category is text shlex could not read, and six checks over it — a heredoc feeding anything but `cat`, `-c`/`-e` code as a string at a command position, a pipe into an interpreter, a `$`/backtick program, a `$(…)` inside a path, a one-line compound. Runs last, after the approval declines, so an approved command is never opaque. |
| Escalation | A per-caller count keyed on `session_id` + `agent_id`, one digest-named file under `$TMPDIR/agenttooling-hook-state/`. Two denies, then `ask`; any readable command clears it; a missing, empty or corrupt file counts as zero. |
| Headless and scratch | `AGENTTOOLING_HEADLESS` turns the `ask` into silence with the count still advancing; `AGENTTOOLING_SCRATCH` is the one directory outside the project root a script is approved from, by name, resolved through symlinks. |
| The runner exports | `plan-runner-lib.sh`'s `claude -p` launch site sets both through `env`, makes the scratch directory inside `CAPTURE_TMPDIR` so the existing teardown removes it, and appends one line naming it to whatever `build_prompt` composed. |
| The security audit | Seven closures — an assignment word read as the program (which executed a repo file), an attached-value flag path (a read outside the tree), `ls -L`/`du -L` through a symlink out, rg's and git's exec-through flags, `ruff --fix`/`ruff format`/`mypy --install-types` writing and installing, and `capture_planning.py --force` as a tightening — each asserted beside the near-miss that must stay approved. Everything considered and rejected is a row in `hooks/README.md`. |
| The git reason | Names `feature-start.sh` and its prune alone; `feature-close.sh` is gone from it, and its absence is asserted rather than assumed. |
| Docs | `hooks/README.md` (the opaque shape, the counter, headless and scratch, both audit tables, the `wire-settings.py` gap, the constants), `CONVENTIONS.md` § Shell commands, `RUNNER.md` → "The executor's environment", `self/tests/README.md`, `NOTES.md`, three `self/BACKLOG.md` entries. |
| Rework (review E1–E4) | `--add-dir "$scratch_dir"` at the `claude -p` site, without which `acceptEdits` refused the very Write the deny asks for (stream-capture 10h–10i, through the stub's recorded argv); `interpreter_takes_code` stops at the first non-flag word, so a *script's* own `-c` is no longer a false-positive deny; a `cat` heredoc no longer excuses the rest of its first line, closing `cat <<'EOF' \| python3` and `bash -c "$(cat <<'EOF' … EOF)"` while the `git commit -m` exemption stays; the env-prefix row in "Considered and not a bypass". Plus the ruling that the `hooks/` Edit deny *does* reach a worktree for a session rooted there — which is why the review pass could not fix any of this itself. |

## Deliberately excluded

- **Anything `capture-on-branch` touches** (`feature-*.sh`, `run-review.sh`, `analysis/`,
  `pr.sh`, the lifecycle docs, `self/tests/feature-lifecycle.sh`) — in flight on its own
  branch; this feature stays in `hooks/`, `CONVENTIONS.md`, `RUNNER.md`, the runner's
  launch line and the hook tests, so the two merge without a conflict.
- **A per-shape counter.** The count is per session: a model denied a heredoc tends to
  reach for `python3 -c` next, and a per-shape count would miss the switch.

## Machine-readable

```json
{
  "slug": "hook-opaque-commands-and-audit",
  "method": "direct",
  "plans": ["108-review-opus"],
  "branches": ["hook-opaque-commands-and-audit"],
  "base": "main",
  "session_window": {"from": "2026-09-17T15:16:52Z", "to": "2026-09-17T16:04:01Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["ae6246767f0c37d11", "aaa12f9412ee892b5", "a78ed8aa0cb1e8441"]
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
