# Orchestrator move length cap

Three fail-open gaps, found by consuming repos' pull audits and an owner's report. (1)
The orchestrator's record move (#172) was judged in `main()` before the line cap
`ORCHESTRATOR_MAX_LINE_CHARS`, so a move padded past 20000 characters was approved where it
must be refused unread. (2) `orchestration-start.sh` went ahead whenever `roots.py
start-refusal` / `self-write` exited 0, so an emptied or stubbed `roots.py` let a refused start
through. A third problem was added mid-build and later split out by the owner's ruling
(2026-11-21): the conformance check `feature-close.sh` runs flipped an owner item from `done` to
`partial` on unchanged evidence (humanNetworkMap #385). Its diagnosis stays in `NOTES.md`,
and the carry-forward that three rounds built and audited is filed in `self/BACKLOG.md`; none of
its code ships here. Built by hand (`--method direct`) in a cloud session dispatched by
orchestration `entity-linking-2026-11-20`.

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md`, `02-…` | rounds 1–2: the review, with the security audit and the conformance check beside it |
| `review/incomplete/03-review-opus.md` | round 3, the owner's last authorised round: defects 1 and 2 only |

## Acceptance

| # | Item | Done by | Held by |
|---|---|---|---|
| 1 | Start the feature on `claude/orchestrator-move-length-cap` | `feature-start.sh --self … --owner-brief` | the `orchestrator-move-length-cap: start` commit |
| 2 | The cap is checked at the top of `orchestrator_moves_own_record`, the one in `orchestrator_command_allowed` kept, no new literal | `hooks/allow-repo-commands.sh` `orchestrator_moves_own_record` | `self/tests/hook-orchestrator-role.sh` H29 (red without the two lines) |
| 3 | The move padded to exactly 20000 approved, to 20001 the allowlist denial, both for the `mkdir -p` lead form too; the go-ahead token with empty and exit-0 stub tests for both checks | the hook; `analysis/roots.py` prints `CLI_GO_AHEAD` (`hooks/shared_rules.py` `ROOTS_CLI_GO_AHEAD`); `orchestration-start.sh` checks it | H29; `orchestration-records-in-repo.sh` R14; `consumer-record-guard.sh` C7; `shared-rules.sh` S1/S2 |
| 4 | Backlog: the edited-classifier and last-fence findings, and run-review.sh's duplicate audit stem | `self/BACKLOG.md`, last three entries | review |
| 5 | Gate, review with the security audit, close on clean | `./self/gate.sh`; `run-review.sh --self` | the round's reports; judged by hand at the close (owner's ruling) |
| 6 | Diagnose the conformance flip | `NOTES.md` → "Diagnosis: the conformance flip"; summarised in `self/BACKLOG.md`'s last entry | review |
| 7 | A done does not regress on unchanged evidence | split out by the owner's ruling (2026-11-21): filed in `self/BACKLOG.md`, last entry | — |
| 8 | Tests for item 7 | split out with item 7 | — |
| 9 | Split instead if too large | the owner ruled the split after round 2 (`NOTES.md` → "Owner's ruling: split") | — |

## Deliberately excluded

- **The three backlog findings themselves** (an edited `roots.py`, the last-fence count,
  run-review.sh's duplicate stem): the brief asks for them to be recorded, not fixed.
- **The conformance carry-forward (owner items 7–8)**: built and audited in rounds 1–2, then
  removed by the owner's ruling. `conformance.py`, `feature-close.sh`,
  `self/tests/brief-conformance.sh`, `LIFECYCLE.md` and the root `README.md` are as on `main`.

## Machine-readable

```json
{
  "slug": "orchestrator-move-length-cap",
  "method": "direct",
  "plans": ["01-review-opus", "01-audit-opus", "01-conformance-opus", "02-review-opus", "02-audit-opus", "02-conformance-opus", "03-review-opus", "03-audit-opus", "03-conformance-opus"],
  "branches": ["claude/orchestrator-move-length-cap"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "orchestration": "entity-linking-2026-11-20",
  "session_window": {"from": "2026-11-20T18:02:36.467Z", "to": null},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, the profile, the gate and `from`, with the id lists empty — and
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
- **`profile`** — `"local"` or `"cloud"`: where the start ran, as
  `agentTooling/env-profile.sh` decided it (`"cloud"` in a Claude Code cloud container,
  where the feature's checkout is the container itself and `branches` names the session's
  assigned branch). A record of where the cost was made, shown by `analysis/report.py`;
  nothing branches on it. Absent from a manifest started before it, which reads as "not
  recorded".
- **`gate`** — `"green"` or `"skipped"`: whether the start's base gate ran and was green,
  or no gate ran at all (`feature-start.sh --no-gate`, or the repo has no gate script), so
  a feature started on an unverified base says so in its record
  (`agentTooling/self/DESIGN-2026-10-05-cloud-execution.md` §7). Written by the start
  through `analysis/manifest.py init --gate`, shown by `analysis/report.py`; nothing
  branches on it. Absent from a manifest started before it, which reads as "not recorded".

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
  where rule 1 claims it by branch with no pin at all — and a session that starts the
  feature already ON its branch, and any session that starts one in a Claude Code cloud
  container (on its assigned branch, or cutting it with `--branch`), is that
  coordinator: no routing record, no pin, and `from` set to its own first instant. What is left for this field is the
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
  capture rather than counting twice. **A delegate whose brief opens `feature:
  <repo>/<slug>` for this feature is pinned by the capture itself**, through the same
  command, and the capture says so — the reason every brief opens with that line
  (`agentTooling/CONVENTIONS.md` → "Delegate briefs").
- **`allow_unclaimed`** — absent unless `feature-close.sh --allow-unclaimed "<reason>"`
  let a close through with no session or delegate claimed for the build; it holds that
  reason, written by `analysis/manifest.py allow-unclaimed`, and the capture copies it into
  `planning.json`, where the report prints it. Never hand-written.
- **`exclude_subagents`** — optional, and legacy: leave it empty. Delegates of a session
  this manifest *does* select that belong to another feature. A delegate another feature
  pins now **yields** on its own — the capture leaves it to that feature and records it in
  `planning.json`'s `yielded_agent_ids` — so nothing new needs listing here. The list is
  still read, so a record captured before the yield rule recaptures as it did; take an
  entry out with `python3 agentTooling/analysis/manifest.py <slug> unexclude-subagent
  <agent-id>`, never by editing the fence.
- **`orchestration`** — optional: the slug of the orchestration record (a group of
  features an orchestrator session spawned, `plans/orchestrations/<slug>/` in a consuming
  repo, `self/orchestrations/<slug>/` for agentTooling's own) this feature
  belongs to. `feature-start.sh --orchestration <slug>` writes it, and `manifest.py <slug>
  get orchestration` reads it. Nothing in the cost capture reads it; the group report
  (`analysis/report.py [--self] --orchestration <slug>`) is what joins the two.
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
