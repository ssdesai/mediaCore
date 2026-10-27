# Sweep retirement and the audit fixes

The last of the three lifecycle-restructure features (`self/DESIGN-2026-09-16-lifecycle-restructure.md`
§3.5, §3.8). With the capture running on the branch before the merge, every step of the
weekly `sweep.sh` is either historical (the backfills that served features predating
runner-side usage capture) or belongs at capture (the frozen-record annotation, the
residue listing of unclaimed sessions and the rates check), so the sweep is deleted and
its survivors move: repair tools to a section of `analysis/README.md`, the residue to
`feature-capture.sh`'s output. The audit's small items ride along — `report.py --all`
fills missing reports, `check-plans.sh` lints window ordering, `run-batch.sh` lints an
inferred slug, `RUNNER.md`'s review cap reads what the runner does — and so does the
`capture-on-branch` review's escalation: `run-review.sh` commits its own pass before
`pr.sh`, so the capture succeeds where no forge is logged in. Stacked on
`capture-on-branch` (base in the fence). Built direct (`AGENT_DIRECT.md`), one
implementer, tests first, then the review pass.

## Slices

| Slice | What it does |
|---|---|
| Acceptance tests | The contracts, red first, in `self/tests/feature-lifecycle.sh` (the residue and the stale-rates line a capture prints, the frozen-record annotation at capture, the review runner's own commit and none on the base branch, P2b's `--merge`), `self/tests/check-plans.sh` (window ordering) and the new `self/tests/audit-fixes.sh` (`report.py --all` fills gaps, `run-batch.sh` lints an inferred slug). |
| 1. `report.py --all` fills gaps | `fill_missing_reports` renders every feature holding a `planning.json` with no `report.json` before the trend table reads it, and prints how many it wrote (`GAP_FILL_LINE`, on every run, zero included). One feature's failure is named and skipped. |
| 2. `check-plans.sh` window ordering | Check 7 covers the whole fence in one line (`WINDOW_LABEL`): both bounds carry a zone, and `to` is null or an instant strictly after `from`, compared as instants rather than as text. |
| 3. `run-batch.sh` lints an inferred slug | `run_corpus_lint`, idempotent through `LINTED`: before the build pass when the slug was given, otherwise as soon as the build pass resolves it — before the gate and the verify and review passes. |
| 4. `RUNNER.md` review cap | `$7.00` in both places it is stated, matching `REVIEW_BUDGET_USD`; the derivation stays in `run-review.sh`'s comment. |
| 5. The runner commits its own pass | `run-review.sh`'s `commit_pass_output` commits `<slug>: build, verify and review passes` — `pr.sh`'s own subject, only on a branch that is not the feature's `base`, advisory on every failure — before calling `pr.sh`, whose identical commit becomes the fallback for an un-updated consumer. Both `pr.sh` copies' contract comments and both READMEs say so. |
| 6. Annotation and residue at capture | `capture_planning.py --annotate-frozen [--except SLUG]` (`annotate_corpus`) refreshes `sessions[].also_claimed_by` on every other frozen record in this corpus from the claims ledger, opening no transcript and moving no figure; `feature-capture.sh` runs it after its own capture, re-reports each record it changed, commits them (`ANNOTATION_FILES` exempted in `stray_paths`, each slug named in the `git add`), and then prints the residue — the rate table's date and the corpus-wide unclaimed sessions and delegates over `RESIDUE_LOOKBACK_DAYS`, routers excluded, never a refusal. |
| 7. `sweep.sh` retired | `sweep.sh` and `self/tests/sweep.sh` deleted, with their rows in `self/gate.sh`'s script and test lists and every live reference; the repair tools it wrapped are now a section of `analysis/README.md`. |
| 8. Docs | `LIFECYCLE.md` (six steps, step 7 now "Propagate"), the root `README.md` rows for `run-review.sh`, `feature-capture.sh` and `analysis/`, `analysis/README.md` ("How to run them" rewritten around per-feature capture, plus "Repair tools"), `self/PROJECT_FACTS.md`, `self/README.md`, `self/tests/README.md`, `RUNNER.md`, `AGENT_DIRECT.md`, `templates/plans/README.md`. |
| 9. Rulings and what is left | `NOTES.md` (14 rulings), three `self/BACKLOG.md` entries — the hook's surviving `sweep.sh` approval, `feature-start.sh`'s duplicate plan numbers across branches, the audit's two undecided design points — and this table. |

## Deliberately excluded

- **The open design points** — a per-feature budget in the fence, relaxing the
  `git stash list` deny. Undecided; not built.
- **`hooks/`** — `hook-opaque-commands-and-audit` owns it in parallel.
- **The shared-session machinery** (ledger, split, `--recapture`, `--carry-lost`) — kept
  for the existing corpus; not exercised by features started under the new rule.

## Machine-readable

```json
{
  "slug": "sweep-retirement-and-audit-fixes",
  "method": "direct",
  "plans": ["109-review-opus"],
  "branches": ["sweep-retirement-and-audit-fixes"],
  "base": "capture-on-branch",
  "session_window": {"from": "2026-09-17T15:25:34Z", "to": "2026-09-17T17:36:50Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["af023996702385bf4", "a89e6fcdb8ad01afc"]
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
