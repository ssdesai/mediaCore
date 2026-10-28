# Lifecycle records, and one numbering rule

The lifecycle's records have two readers where the design says one, and its plan numbers
two rules where consuming repos have one. **Numbering:** `feature-start.sh` numbers a
self feature's plans as one sequence across the corpus, so two features started from the
same base both see the same highest number and both get it (twice on 2026-09-17), and a
corpus past 99 holds stems of two widths that every reader must order numerically (the
defect `feature-close-and-review-rounds`' review fixed). Consuming repos number per
feature from `01`, and `AGENT_PLANS.md` already says nothing compares numbers across
features. The self corpus's exception is deleted: one rule, both modes, `01` for every
new feature. **The stray rule:** `feature-capture.sh` owns the reader that says which
dirty paths are the harness's own records, and `feature-close.sh` carries a looser copy,
so a half-written file inside the feature directory passes the close and is refused by
the capture after the PR is open. The reader moves to `plan-runner-roots.sh`, both call
it, and a sibling feature's annotated record is admitted only after the annotation names
it — which also closes the capture's hole for a sibling record dirty before the run.
**The review's two filed gaps:** the close reads its round from the review's own
`plan_end` stamp instead of counting `review/complete/`, and the verdict readers get a
unit test that calls them directly. Beside those: a fixture for the close's skip of the
merge request on a `pr.sh` older than template-version 4, and `report.py` on a feature
not yet captured says so in one line instead of a traceback. Built direct
(`AGENT_DIRECT.md`) as two non-overlapping slices, coordinated from the primary, tests
first in each, then the review pass, then the close.

## Slices

| Slice | What it does |
|---|---|
| A. One stray reader | `COST_FILES`, `ANNOTATION_FILES`, the sidecar constants, `is_cost_usage_path` and `stray_paths` move from `feature-capture.sh` to `plan-runner-roots.sh`; `stray_paths` takes the sibling slugs whose annotation files are admitted (none before the annotation, the returned slugs after it); the close's pre-PR check calls it with none. Assertions in `self/tests/feature-lifecycle.sh`: a close with an untracked `<features>/<slug>/NOTES.md.tmp` refuses, names the path, opens no PR; a capture with a sibling's `report.md` dirty before the run refuses and names it. |
| A1. The close's round | `feature-close.sh` reads `round` from the latest review's `plan_end` (`review_plan_end … round`), falling back to `completed_review_count` for a `timing.jsonl` written before rounds existed. Assertion: a round-2 review capped after writing a clean report closes with `pr_opened` carrying `round=2`. |
| A2. Verdict readers, directly | New `self/tests/verdict-readers.sh`, sourcing `plan-runner-roots.sh`: a report whose first line is prose and whose body says `Verdict: clean` reads `unreadable`; `  VERDICT:  CLEAN ` with a trailing `\r` reads `clean`; with `98-review-opus.md` and `101-review-sonnet.md` filed complete `latest_review_plan` returns the 101 stem; a stem in `failed/` is read but not counted. Enumerated in `self/gate.sh`. |
| A3. Pre-4 `pr.sh` | A fixture `pr.sh` at template-version 3 in `self/tests/feature-lifecycle.sh`: the close says it skipped the merge request, names the version, and calls the forge exactly once. |
| A4. Docs and the record | Root `README.md` rows (`plan-runner-roots.sh`, `feature-close.sh`, `feature-capture.sh`, and `feature-start.sh`'s wording from slice B), `LIFECYCLE.md` where it describes the check, `self/tests/README.md`, `NOTES.md`, `CHECKPOINT.md`, and the five closed entries removed from `self/BACKLOG.md`. |
| B. One numbering rule | `feature-start.sh` writes `01-review-opus` in both modes and its self-mode sequence is deleted; its "Next" text names the close, not the review, as what opens the PR. `self/tests/plan-numbering.sh` asserts `01` whatever another feature's corpus holds. `self/PROJECT_FACTS.md`'s sequence rule is rewritten; `self/features/README.md` says the ranges before this feature were global. A grep over `analysis/` and the runners confirms nothing keys a plan by bare stem across features. |
| B1. The report on an uncaptured feature | `analysis/report.py --self <slug>` before the close exits non-zero with one line naming `planning.json` and `feature-close.sh`, no traceback; asserted in the report test file that fits (`self/tests/README.md` says which). `analysis/README.md` if its entry describes the failure. |

## Deliberately excluded

- **`hooks/`** — the policy feature that follows this one owns every entry there (the six
  deny-rule twins, opaque = unreadable, scratch arguments, the `sweep.sh` and
  `feature-close.sh` wording, the worktree `hooks/` Edit deny, the settings-drift check,
  the bare entry-point name, `git branch --list`).
- **This feature's own stub keeps the number it was issued under** — no: it is renamed to
  `01-review-opus` before the brief is written, so the feature that deletes the exception
  is the first one numbered under the rule. Nothing else in the corpus is renumbered; the
  historical ranges in `self/features/README.md` stay as history.
- **`routing.slug_of_start_command`'s multiline regex, `open-session.sh` quoting, the
  per-attempt duration walk, the in-flight co-claimant, the zero-cost pin, `set-window-from`,
  the routing add/add conflict** — each is its own backlog entry with its own reason, and
  none is a lifecycle record read in two places.
- **Per-feature budget, `git stash list`** — deferred by the user's decision.

## Machine-readable

```json
{
  "slug": "lifecycle-records-and-numbering",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet"],
  "branches": ["lifecycle-records-and-numbering"],
  "base": "main",
  "session_window": {"from": "2026-09-17T21:20:44Z", "to": "2026-09-18T04:03:32Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["ae5e415d4d94044fc", "a2bf066885e3f28cc", "ac424f4dd98ecea09"]
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
