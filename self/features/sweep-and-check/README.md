# Sweep and check: the cadence, the corpus lint, drift detection and the consumer update as scripts

`LIFECYCLE.md` step 7 and `README.md` → "Updating" are the last two procedures in this
repo still written as prose for a human or a model to follow by hand: the weekly cost
sweep (rates, backfill, recover, capture, report — five commands in a fixed order, each
a silent under-count when skipped) and propagating this directory to its four consumers
(subtree pull, `sync-plans.sh`, then a hand-merge of each repo-owned script that nothing
detects the need for). The plan corpus has the same gap in front of a paid run: a plan
named without a model suffix, a stem missing from `plans[]`, a review stub still
carrying `@@TODO@@` — each is caught late, by a runner mid-batch, by a cost report that
omits a plan, or by the review pass refusing after build and verify have already
billed. This feature turns all three into scripts (`feature-lifecycle`'s manifest
deferred them as "second tier") and fixes the one capture rule that stops a
plans-method feature from closing.

## The scripts

- `check-plans.sh [--self] <slug>` — fourteen checks over one feature's manifest fence
  and plan files, one `ok`/`FAIL` line each, exit 1 on any failure. `run-batch.sh` runs
  it before the build pass and stops on a failure, so a malformed corpus costs nothing.
- `sync-plans.sh --check` — read-only: every generated stub in sync or `STALE`, every
  repo-owned script at the template's `template-version` or `DRIFT`, `PROJECT_FACTS.md`
  filled or `unfilled`. The write path now ends with the repo-owned part of the same
  report, so a `sync-plans.sh` after a pull says which hand-merges the pull owes.
- `update.sh [--remote <url>] [--branch <name>]` — from a consuming repo: refuse on a
  dirty tree, `git subtree pull --squash`, then the freshly pulled `sync-plans.sh`. The
  four consumers are updated with one command each.
- `sweep.sh [--self]` — the cadence in order, every python with `-B`, then the unclaimed
  delegates and sessions of the last week, then what changed under the features tree.
- `analysis/capture_planning.py` — a feature whose only sessions on its branch are
  excluded ones (runner sessions, whose cost `usage.json` holds; or `exclude_sessions`)
  no longer trips the zero refusal: a session on the branch was met, so the branch name
  is right and the zero is evidenced. A plans-method feature planned by a session pinned
  elsewhere — this one — can now close.
- `analysis/manifest.py set-plans <stem>...` — written by hand before the batch: how the
  architect records the batch in the fence after `feature-start.sh` wrote it with only
  the review stub, which it numbers first. The stub was renumbered from `73` to `83` so
  the review still sorts last.

## Also carried: the sweep leaves in-flight features alone

The verify pass ran `sweep.sh --self` on this very checkout and its `capture --all`
froze `planning.json` for two features whose windows were still open — this one and
`feature-lifecycle`, both unclosed at the time — which their closes would then have
skipped as "already captured". `capture_planning.py --all` now skips a feature whose
`session_window.to` is null as in flight (naming the slug still captures it);
`capture-guard.sh` phase 18 pins it, and the two premature records were dropped in the
merge from `main`.

## Also carried: the rate table

The first `sweep.sh --self` run reported the table stale, so this batch did step 1 of
the cadence by hand: `claude-fable-5-1` and `claude-mythos-5-1` added ($10/$50, cache
read at 0.025x per the published page — a per-entry `cache_read_multiplier` the table
did not have), and Sonnet 5's introductory $2/$10 made open-ended because the
announced September increase was withdrawn. `RATES_VERIFIED` is 2026-09-04. Without
the first, the session that planned `feature-lifecycle` priced at `$0.00` with a
warning; its cost record is recaptured after this merges.

## Plans

| Plan | Model | Does |
|---|---|---|
| `73-tests-check-plans-sonnet` | sonnet | `self/tests/check-plans.sh`: the lint's contract, black-box, plus its `run-batch.sh` stop. Wires every new file into `self/gate.sh`. RED until 76. |
| `74-tests-sync-check-sonnet` | sonnet | `self/tests/sync-check.sh`: `--check` on a fresh seed, a stale stub, a drifted script; `update.sh` through a real local subtree cycle; the self copies at the template versions. RED until 77. |
| `75-tests-sweep-sonnet` | sonnet | `self/tests/sweep.sh`: one run captures and reports, a second skips, a refusal is exit 1 and still finishes. RED until 78. |
| `76-check-plans-sonnet` | sonnet | `check-plans.sh`; `run-batch.sh` runs it before the build pass. |
| `77-sync-check-and-update-sonnet` | sonnet | `sync-plans.sh --check`, `template-version` lines in the three templates and the three self copies, `update.sh`. |
| `78-sweep-sonnet` | sonnet | `sweep.sh`. |
| `79-zero-with-evidence-sonnet` | sonnet | The refusal condition in `capture_planning.py`; a `capture-guard.sh` phase. |
| `80-gate.md` | — | Level 1 sentinel: everything above must be green. |
| `80-level-scripts-sonnet` | sonnet | Level-verify: tests and scripts were written by different executors; fix the tree to the contract blocks, never the blocks to the tree. |
| `81-docs-haiku` | haiku | `LIFECYCLE.md` step 7, `README.md` index and Updating, `analysis/README.md`, `templates/README.md`, `RUNNER.md`, `AGENT_PLANS.md`, the `self/` READMEs and facts. |
| `82-verify-sonnet` | sonnet | Final verify: what the three tests leave uncovered. |
| `83-review-opus` | opus | Review of the diff against `main`. |

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| 1 scripts | 73–79 | `80-gate.md` | `80-level-scripts-sonnet` | shell syntax, python syntax, every self-test |
| 2 docs | 81 | final gate | — | all of the above |

## Contracts across levels

Every contract in this batch is a CLI: exact output lines and exit codes, written
identically into the tests plan and the script plan that share it (73/76, 74/77,
75/78). The level-verify holds the tree to those blocks, not to either executor's
reading of them.

| Value / identifier | Produced by | Consumed by | Fixture | Asserted by |
|---|---|---|---|---|
| `check-plans.sh` labels, line format, exit codes | 76 | 73; `run-batch.sh` | — | `self/tests/check-plans.sh` |
| `# template-version: N` line | 77, templates and self copies | `sync-plans.sh --check`; 74 | — | `self/tests/sync-check.sh` |
| `sync-plans.sh --check` status words, exit codes | 77 | 74; `update.sh` | — | `self/tests/sync-check.sh` |
| `sweep.sh` banners, exit code | 78 | 75 | — | `self/tests/sweep.sh` |
| an excluded session **carrying one of the manifest's `branches` and past `repo_match`** lifts the zero refusal — `excluded_on_branch`, not the wider serialized `excluded_session_ids` | 79, narrowed by the review escalation | `feature-close.sh` | — | `self/tests/capture-guard.sh` phases 17a–17d |
| `NN-escalation-MODEL.md` under `verify/` is well-formed and exempt from check 11 (`plans[]`) — not from 8, 9 or 13 | 76, added by the review escalation | `run-batch.sh` resume | — | `self/tests/check-plans.sh` 11b/11c; `self/tests/tiered-gates.sh` |
| `templates/plans/TEMPLATE_VERSIONS` rows: `<file> <version> <sha256 of the file with comment-only and blank lines stripped>` | 77, added by the review escalation | `self/gate.sh` | — | `self/tests/template-versions.sh` |

Fixtures are `—` throughout: each test builds its world in a `mktemp -d`, as every
existing test in `self/tests/` does. No serialized shape crosses the level.

## Deliberately excluded

- A `feature:` first line for top-level sessions. Still unnecessary; pins cover it.
- Moving scripts into subdirectories. Consumers invoke them by path.
- Contract-header diffing for the repo-owned scripts. A version line is exact and
  cheap; a header diff cannot see the change below the marker that this rollout
  actually needs (`pr.sh`'s branch step). This is about how a *consumer* detects
  drift, and is not what `self/tests/template-versions.sh` does: that keeps the
  version line honest at the source, where the templates are edited.
- `sweep.sh` propagating to consumers. Propagation runs *in* each consumer
  (`update.sh`); the sweep prints the reminder.
- Deleting the remote branch at close. The forge's delete-on-merge already does it.
- Rolling out to the four consumers. By hand, after this merges, with `update.sh`.

## How this feature is costed

Planned from the session that built `feature-lifecycle`, which is pinned there and can
be claimed only once; `sessions` here is empty on purpose and `feature-start.sh` was run
with `--no-pin`. The runner sessions the batch launches inside the worktree carry the
branch and are excluded as runner sessions (`usage.json` holds their cost), which is
exactly the case plan 79 makes capturable: the planning figure is an evidenced `$0.00`,
and the feature's real cost is the `usage.json` roll-up `report.py` prints.

## Machine-readable

```json
{
  "slug": "sweep-and-check",
  "method": "plans",
  "plans": ["73-tests-check-plans-sonnet", "74-tests-sync-check-sonnet", "75-tests-sweep-sonnet", "76-check-plans-sonnet", "77-sync-check-and-update-sonnet", "78-sweep-sonnet", "79-zero-with-evidence-sonnet", "80-level-scripts-sonnet", "81-docs-haiku", "82-verify-sonnet", "83-review-opus"],
  "branches": ["sweep-and-check"],
  "base": "main",
  "session_window": {"from": "2026-09-04T04:36:36Z", "to": null},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["aa0af908abb54f620"]
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
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
