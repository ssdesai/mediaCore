# self/tests

Behavioural checks for the harness, run by `../gate.sh`. Each is a plain bash script that
exits non-zero on a failed assertion and prints one `ok`/`FAIL` line per check; none
calls a model or the network. `../PROJECT_FACTS.md` → Tests says there is no test
*runner* here — that is still true; these are scripts the gate `record`s directly.

- `level-sentinel.sh` — copies the runner scripts into a `mktemp -d` checkout with a stub
  `claude` (exit code from `CLAUDE_STUB_RC`) and a stub `self/gate.sh` (verdict from
  `GATE_STUB_VERDICT`), then asserts the level-sentinel contract `run-batch.sh` depends
  on: a sentinel is filed with no sidecars and the gate runs labelled; a red gate with a
  queued level-verify exits `LEVEL_PAUSE_RC` (64); a green gate files the level-verify as
  skipped and continues (D3); `run-verify.sh --up-to 08` drains `08` and not `09`; a
  `claude` exiting 64 is a failure, not a pause; `run-batch.sh` resolves the pausing
  sentinel's number and finishes; and the `LEVEL_PAUSE_NN_OUT` handshake — `run-plans.sh`
  writes the pausing sentinel's `NN` to that file, `run-batch.sh` reads it in preference
  to re-deriving the number from a sort over `auto/complete/` (asserted with that
  directory empty, so the sort has nothing to offer), and a pause that reports no number
  at all stops the batch with a message instead of running `run-verify.sh --up-to ""`.
  Its last phase replaces `run-plans.sh` and `run-verify.sh` in the throwaway checkout
  with stubs, since what is under test there is the batch's own resolution rather than
  the runners' behaviour; it is last for that reason. Depends on `plan-runner-roots.sh`
  defining `LEVEL_PAUSE_RC` and on the stub gate honouring the label contract
  (`gate-report.<label>.txt`) the real template implements.
- `tiered-gates.sh` — same scaffolding, with the stub gate's verdict read from a file the
  stub `claude` can flip green (`CLAUDE_STUB_FIX_AT=tier1|tier2`, recognised from the
  prompt's preamble) and every `claude` call's flags logged. Asserts the tier ladder
  `run-batch.sh` → `settle_level` implements: tier 1 green → no escalation, build resumes;
  tier 1 red → `NN-escalation-opus` synthesized, run on opus under `ESCALATION_BUDGET_USD`
  with the escalation preamble; red after both → exit 1, next level not built, and a
  re-run neither re-escalates nor rebuilds; a resumed batch settles a crossed level before
  its build pass, **including when `auto/incomplete/` is empty** — the ladder is owed to
  the level, not to the queue behind it, and without it a batch killed during its last
  level's level-verify reports that level's failure only at the final gate, with no tier
  in between — and a settled level is not re-settled on a re-run; `run-review.sh` opens
  the PR when the cap fires after the report was written and not when it fires before; a sentinel's `expected-red:`/`defer:` lines reach
  the gate at that level only and make it green without a tier. It also copies
  `check-plans.sh` into the sandbox, so the corpus lint really runs at the head of every
  `run-batch.sh` call here rather than being skipped by that script's `-x` guard: two
  assertions pin `check-plans: 14 checks, 0 failed` in the batch output, one on the first
  build and one on the re-run that has a synthesized `NN-escalation-opus` on disk — the
  resume the lint used to block. That is why this test's fixture manifest is a real
  fenced JSON manifest declaring the stems each phase writes, with a non-empty `branches`
  and a body naming the slug in every queued plan. Depends on `run-escalation-plan.sh`,
  `run-verify.sh`'s `budget_for_plan` hook and `level_expectations` in
  `plan-runner-roots.sh`.
- `feature-lifecycle.sh` — stands up a throwaway agentTooling checkout that is a real git
  repo with a bare `origin` beside it, copies in the real `feature-start.sh`,
  `feature-close.sh`, `run-review.sh`, `plan-runner-{lib,roots}.sh`, `self/pr.sh` and
  `analysis/*.py`, adds a stub gate, a stub setup hook and stub `claude`/`gh` on `PATH`,
  and drives the whole loop with `--self` — start a feature, refuse its stub brief,
  review it, open its PR, merge it, close it — synthesizing under a redirected `$HOME`
  the transcripts the close captures. The rule under test (`../../LIFECYCLE.md`): for
  slug `S` and primary checkout `R`, branch `S`, worktree `R-S`, and every session a
  feature costs is either launched in `R-S` or pinned by id. Asserts that
  `feature-start.sh` creates the branch and worktree off `origin/main` leaving the
  primary on `main` and clean, writes the manifest (`branches [S]`, `base main`, a `Z`
  `from`, `to` null, the running session pinned from `$CLAUDE_CODE_SESSION_ID`) and a
  `@@TODO@@` review stub numbered next in the global sequence, commits `S: start`, and
  refuses a bad slug, an existing branch and a worktree's copy while creating nothing;
  that `run-review.sh` files a brief still carrying `@@TODO@@` to `failed/` without
  calling `claude`, and that a real one reaches the PR hook, which pushes `S` itself and
  calls `pr create --base main --head S`, honours `FEATURE_BASE`, and refuses on the base
  branch; and that `feature-close.sh` refuses from a worktree, on an unmerged branch and
  on a dirty primary, stops on an unclaimed delegate whose brief names the feature until
  it is pinned while a sibling delegate briefed for `S-two` is never taken for one of
  `S`'s and never stops it, records `selected_by`/`cwd` for a branch-selected and a pinned session
  alike, carries the review pass's trailing timing stamps home — the `pr_opened` line
  with its URL, written after the PR hook had already committed, reaches `main` exactly
  once, and a second close over a kept worktree duplicates nothing — stamps `to`, commits
  exactly the cost files as `S: cost records`, removes the
  worktree and branch (keeping both under `--keep-worktree --no-push`), and writes and
  stamps nothing when the capture matches nothing — rolling that carry back, so a refused
  close leaves the primary byte-identical and clean rather than dirty and refusing its own
  re-run. No model, no network. A missing
  script fails its own assertions loudly rather than aborting the run, the convention
  `cost-recovery.sh` uses. Depends on `plan-runner-lib.sh` refusing the `@@TODO@@`
  marker, on `capture_planning.py`'s `--list-subagents`/`--list-sessions --unclaimed`
  and its zero refusal, and on `analysis/manifest.py`'s `init`, `get`, `claimed` and
  `set-window-to`.
- `check-plans.sh` — copies the real `check-plans.sh` and `plan-runner-roots.sh` into a
  throwaway checkout (a missing `check-plans.sh` is tolerated — RED until it lands, the
  `cost-recovery.sh` convention) and drives it against synthesized feature manifests and
  plan-directory trees under `$TMP/plans/features` (the ordinary corpus) and
  `$TMP/agentTooling/self/features` (the `--self` one). Asserts the usage contract (exit
  2 on no slug, an unknown flag, or an extra argument); that a well-formed feature prints
  exactly 14 `  ok    ` lines, no `  FAIL  ` line, and ends `check-plans: 14 checks, 0
  failed`; and, one at a time, each of the fourteen ordered checks — feature directory
  exists, manifest present, fence parses, fence slug matches directory, method known,
  branches non-empty, window bounds carry a zone, plan filenames well-formed, plan
  numbers padded alike, no `@@TODO@@` stubs queued, every plan file listed in `plans[]`,
  every `plans[]` entry has a file, every queued plan names the feature, plans method has
  a queue — FAILing on the input built to trip it, naming the offending path or stem in
  the detail where the contract specifies one, and passing otherwise; a missing feature
  directory still ends with a `check-plans: ` summary line. Pins both halves of the
  escalation exemption (`11b`/`11c`): a `verify/complete/NN-escalation-MODEL.md` absent
  from `plans[]` still prints `ok    every plan file listed in plans[]` — it is
  synthesized at runtime and no manifest can list it — while the same filename under
  `auto/` FAILs check 8, the way an `NN-gate.md` outside `auto/` does (`8b`). Also
  asserts the batch stop:
  `run-batch.sh` spends no `claude` call on a feature whose corpus fails check 8
  (malformed filenames) and does spend one on a well-formed feature — copying in
  `run-batch.sh`, the other runners and a stub `claude` (logging its args to
  `$TMP/claude.log`) for that last phase only. No model, no network. Depends on
  `plan-runner-roots.sh`'s `resolve_roots` and `manifest_field`, and — for check 10 — on
  `plan-runner-lib.sh`'s refusal rule (`grep -q '^@@TODO@@'`, any line) matching the
  lint's, since the lint exists to predict that refusal: the `10c` fixture is the stub
  `feature-start.sh` really writes, marker on line 3 under a title.
- `cost-recovery.sh` — copies `analysis/pricing.py`, `analysis/roots.py`,
  `analysis/report.py`, `analysis/transcript.py` and `analysis/recover_attempts.py` into a
  throwaway checkout, synthesizes a `self/features/` corpus of `usage.json` sidecars (and,
  for the report.py-level assertions, minimal feature dirs with a manifest `README.md` and
  `planning.json`) and, under a redirected `$HOME`, the
  `~/.claude/projects/*/<session_id>.jsonl` transcripts they point at, and asserts the
  killed-attempt-cost-recovery contract: `pricing.py`'s intro tier is a two-sided window (a
  date before it starts, or after it expires, prices standard; a date inside it prices intro
  at exactly 2/3 of standard); `recover_attempts.py` fills a killed attempt's
  `recovered_cost_usd` / `recovered_tokens` / `recovered_from` / `recovered_at` /
  `rates_applied` from its transcript without touching `total_cost_usd`; a usage.json's
  top-level `recovered_cost_usd` sums its recovered attempts; the 5m/1h cache-creation
  split prices in the `CACHE_WRITE_1H_MULTIPLIER` / `CACHE_WRITE_5M_MULTIPLIER` ratio (the
  guard against reading `usage.json`'s flat, unsplit `cache_creation_input_tokens` instead);
  an already-measured attempt and a second run are both no-ops; a missing transcript is
  reported unrecoverable rather than erroring; per-`message.id` dedup bills one API response
  once; a killed attempt on a model absent from `pricing.RATES` is marked
  `recovered_is_partial` with `unpriced_models` naming it (propagating the models it could
  price rather than refusing the whole attempt), and `report.py` classes such a plan's total
  as partial rather than recovered-and-whole; attempt-level recovery survives
  `write_usage_sidecar` erasing the sidecar's top-level `recovered_cost_usd` (`report.py`
  sums `attempts[]` instead, using the top-level field only as a cross-check that warns
  naming both figures on disagreement); and a level-verify the runner filed as **skipped**
  — `verify/complete/NN-level-*.md` with a `.progress.md` opening `skipped:` and no
  `.usage.json`, by design (`AGENT_PLANS.md` → Levels, D3) — is neither listed under
  `missing_usage_plans` nor allowed to mark the feature's total a lower bound, while a
  plan with no sidecar and no `skipped:` line still is; and `backfill_usage.py` over a
  `.stream.jsonl` holding an `init` event and assistant events but **no** `result` event
  writes the sidecar `write_usage_sidecar` would — `result_event: "missing"`, the
  session id from the first event, null figures, one null attempt — rather than skipping
  the file and leaving the plan in `missing_usage_plans`, which reads as "never ran".
  That last phase runs after the idempotency snapshot, so the sidecar it writes cannot
  disturb it. Builds its fixtures with the shell helpers in
  `fixtures/`. No model, no network. Depends on `analysis/pricing.py`'s
  `get_rates`/`compute_cost`, `analysis/report.py`'s `compute_cost_rollup` and
  `analysis/transcript.py` and `analysis/recover_attempts.py` — a missing copy of the
  latter two is tolerated rather than fatal (the script was authored RED against
  `pricing.py` alone), so every recovery assertion fails loudly instead of the run
  aborting; the `report.py`-level assertions (13-14) were likewise authored RED against
  `self/features/recovered-totals-stay-honest`'s plan 02, which has since landed.
  `record`ed by `../gate.sh` alongside the other two.
- `recover-at-close.sh` — three throwaway checkouts under one `mktemp -d`, a stub `claude`
  whose closing `result` event is suppressed by `CLAUDE_STUB_NO_RESULT`, a stub `gh`, and
  synthesized transcripts under a redirected `$HOME`. Asserts the contract that a review
  which ran to completion is never recorded at `$0` unexplained
  (`self/features/recover-cost-at-close/README.md`): `write_usage_sidecar` writes
  `result_event: "missing"` when the stream held no `result` event and `"seen"` when it
  did — driven through the real `run-plans.sh`, since what is under test is the field a
  real stream produces — while `outcome` still says `complete` (it is the exit code's
  fact, not pricing's), `total_cost_usd` stays null, the plan is still filed to
  `auto/complete/`, and the sidecar still carries the session id from the stream's first
  event; `recover_attempts.py --for <slug>` recovers a **`complete`**-outcome null-cost
  attempt (recovery was never gated on `outcome`, and this is the case its docstring used
  to omit) while leaving every other feature's sidecar byte-identical, refuses an unknown
  slug without writing, and leaves the flagless whole-tree walk `sweep.sh` calls
  unchanged; and `feature-close.sh` recovers before it captures — with the transcript
  present the review bucket carries real dollars and the rewritten `usage.json` is inside
  the `<slug>: cost records` commit rather than named as a stray (which would refuse the
  close), and with the transcript gone the close still exits 0, names the plan as
  unrecoverable, and prints `review $0.0000 (0.0%, unpriced: <stem> — no result event,
  transcript not found)` instead of the bare `review $0.0000 (0.0%)` the defect printed.
  Its last phase is the repair path for the features whose zero is already committed:
  `--recapture` over the feature the previous phase just closed — worktree removed, local
  branch deleted, only `origin/<slug>` left — re-commits the cost records and leaves
  `session_window.to` where the first close put it. That is why the fixture pushes each
  branch the way `plans/pr.sh` does; without the remote ref the re-close refuses "nothing
  to close", which is `../BACKLOG.md`'s delete-on-merge entry.
  Three later phases came out of the review: **D** pins each of `report.py`'s three
  `unpriced_reason` strings by exact text, from a sidecar of that shape — no
  `result_event` at all (which every sidecar on disk still has, so it is the branch the
  documented repair runs), `missing`, and a `killed` attempt the runner harvested — so no
  single return value satisfies them all, and pins `set(QUEUE_COST_BUCKETS) ==
  QUEUE_DIRS` by asserting a drifted copy of `report.py` refuses to import. **E** is the
  mirror of `feature-lifecycle.sh`'s C5f for `rollback_recovery`: a capture that refuses
  *after* recovery rewrote a sidecar leaves the primary clean and the sidecar as it was,
  and the re-run refuses for the same reason rather than for dirt this run made. **F**
  pins the narrowed sidecar match at the teardown — the other caller of `stray_paths`,
  and the only one a fixture can reach, since an untracked file in the primary trips the
  dirty refusal first: a worktree holding `notes/left-behind.usage.json` is kept with a
  warning, while one holding `review/complete/99-extra-sonnet.usage.json` comes away.
  The B4, C9 and D6 assertions carry their own anti-vacuity guards, since argparse reads
  `--for` as an abbreviation of `--force`, the bare-zero line is a *substring* of the
  annotated one, and a guard that is merely true today is not a guard. Builds its sidecars with `write_unpriced_usage_json` from `fixtures/` and
  its transcripts with `transcript_line`/`session_line`. Its C phase runs on past that
  repair to the state a forge with delete-on-merge really leaves — the remote branch
  deleted from the bare origin AND its remote-tracking ref removed, since the close's
  fetch does not prune — and pins that `--recapture` then proceeds on the manifest being
  tracked on `main` and the `<slug>: start` commit being in `main`'s history, while a
  plain close still refuses "nothing to close" and so does `--recapture` for a feature
  that was never started. No model, no network. Depends on
  `plan-runner-lib.sh`'s `write_usage_sidecar`, `analysis/recover_attempts.py`'s `--for`,
  `analysis/report.py`'s `cost.unpriced_plans[]`, `unpriced_reason` and its
  `QUEUE_COST_BUCKETS` import guard, and `feature-close.sh`'s recovery step,
  `rollback_recovery`, `closed_feature_on_main` and `is_cost_usage_path`; RED until each
  landed.
- `capture-guard.sh` — copies `analysis/{pricing,roots,transcript,capture_planning}.py` into
  a throwaway checkout, synthesizes one feature manifest and, under a redirected `$HOME`,
  the `~/.claude/projects/*/<session_id>.jsonl` transcripts capture selects on, and asserts
  `capture_planning.py`'s frozen-cost guard: a re-capture whose priced session has lost its
  transcript is refused (non-zero exit, `planning.json` byte-identical, the session id and
  the preserved dollar figure both named), `--force` overrides it, and the three safe cases
  stay quiet — transcript still present, a session dropped by a `session_window` edit while
  its transcript survives, and a session now claimed by a `usage.json` as runner cost. Also
  covers that a zero-cost prior capture needs no `--force`. Resolves its `mktemp -d` through
  `pwd -P` because `roots.py` resolves `AGENT_TOOLING_DIR` with `Path.resolve()`: on macOS
  the unresolved `/var/...` fixture path matches no transcript, and every assertion would
  then pass or fail vacuously against an empty scan. Uses `session_line` from
  `fixtures/transcripts/build-transcript.sh`. No model, no network.
  Also pins the two failures found after the guard first shipped: a transcript moved
  into an **orphaned worktree's** project directory (name still contains the repo's
  fragment, so the scan walks it; `cwd` is the worktree, so `repo_match` fails forever)
  must be treated as lost and refused — the filename-glob version vouched for it and
  re-zeroed the feature with exit 0 — and a declared branch matching no transcript must
  be warned about, the failure that silently held five features at `$0.00`.
  Covers the **already-captured skip** in the same file, since it is the guard in front
  of that one: a second run over a feature with a `captured_at` exits 0 leaving
  `planning.json` byte-identical and naming `--recapture`, skips the same way when the
  transcripts are gone (quiet, not a refusal — the cadence crosses a corpus of expired
  features every week), yields to `--recapture` and to `--force`, and under `--all`
  captures only the feature that had none. It also pins that `--all --recapture`
  does not abort on a refusal: the feature after the refusing one is still captured and
  the run exits non-zero at the end. The helpers say which is which — `capture` is the
  raw invocation, `recapture` adds the flag, and every frozen-cost phase goes through
  `recapture` because those assertions are about what the scan does, not about whether
  it runs.
  Its last phase pins `check_empty_window`, the sibling of the unmatched-branch warning:
  a window with `from == to` — and its inverted twin, `from > to` — is warned about even
  though the branch matches and the transcripts are present, while an open-ended window
  and a real interval whose two bounds are written in different zone formats
  (`05:00:00-04:00` .. `13:00:00Z`) are not. That last pair is what pins the check to
  instants rather than strings, and it is the assertion that fails if someone
  "simplifies" it to a lexicographic compare. RED until `check_empty_window` landed.
  Its phase 17 pins the evidenced-zero case: a session excluded by the manifest's
  `exclude_sessions`, or claimed elsewhere by a `usage.json` as a runner session, proves
  the branch name is right when the scan meets it **on one of the manifest's branches**
  — capture writes the $0.00 without `--force` and says `evidenced` on stdout,
  `excluded_session_ids` names the id, and `sessions` stays empty — while a branch no
  transcript carries at all is still refused, asserted right beside it for contrast
  (`17c`). `17d` is what scopes the evidence to the branch rather than to the corpus: an
  excluded session that is present, reachable and runner-excluded but carries branch
  `other`, under a manifest declaring `typo`, must still refuse and write no
  `planning.json`. It is the shape of every repo that has ever run a batch, so were the
  serialized (repo-wide) `excluded_session_ids` the set behind the refusal instead of
  `excluded_on_branch`, a branch typo would read as an evidenced $0.00 everywhere. Phase 18: `--all` skips a feature whose `session_window.to` is still null as in flight and writes nothing, while naming the slug still captures it — a sweep must not freeze a feature `feature-close.sh` has not captured.
- `subagent-capture.sh` — same scaffolding as `capture-guard.sh`, plus the
  `<session_id>/subagents/agent-<id>.jsonl` files beside the parent transcripts (built with
  `subagent_line` / `subagent_prompt_line` from `fixtures/transcripts/build-transcript.sh`).
  Asserts `capture_planning.py`'s subagent attribution: a selected parent's in-window
  subagent is priced and the total rises by exactly `cost_usd.subagents`, with
  `subagents[]` naming it as selected by `"parent"`; one starting after the window's `to`
  is not; a subagent under a parent on `main` — the coordinator case, where the child
  inherits the parent's `gitBranch` and can never be branch-matched — is unpriced until
  the manifest pins its id, then priced as `"pinned"` while the parent stays out of
  `sessions[]`; a pin matching nothing is warned about by id; the frozen-cost guard
  refuses a re-capture whose subagents directory is gone, naming `agent-<id>`, and
  `--force` still overrides; `--list-subagents` prints every reachable subagent with its
  opening prompt and parent, and `--since` drops earlier ones; a subagent of a runner
  session (parent claimed by a `usage.json`) is not priced even when pinned, and the pin
  is reported unmatched; two manifests pinning one id are warned about, naming the
  other feature; and `--unclaimed --for <repo>/<slug>` keeps exactly the delegates whose
  brief names that feature — a `<slug>-two` one is not among them, one whose
  `<repo>/<slug>` outruns the 26-character pin column is, the agent id prints untruncated
  for `feature-close.sh` to read, and `--for` without `--unclaimed` or not shaped
  `<repo>/<slug>` is a usage error. RED until the subagent walk landed.
- `timestamps-are-utc.sh` — same scaffolding, asserting the UTC convention in
  `analysis/README.md` → "Every instant is UTC": `transcript.utc_date` dates an offset
  timestamp by its UTC day (`2026-07-01T23:00:00-04:00` → `2026-07-02`), a session's start
  is the earliest *instant* rather than the lexicographically smallest string, a
  `session_window` bound with an explicit offset selects exactly what its `Z` equivalent
  selects, an offset-less bound means UTC (what the committed corpus already means), windows
  chained across the two formats raise no false overlap warning, and `pricing.utc_today()`
  is identical under `TZ=Pacific/Kiritimati` and `TZ=Pacific/Midway` — whose local dates
  always differ, since the two offsets span 25 hours, making that a deterministic check that
  it is not `date.today()`. The assertion worth the most: a session at
  `2026-08-21T23:00:00-04:00` is `2026-08-22` UTC and must price at sonnet-5's **intro**
  tier, 2/3 of standard — the old `timestamp[:10]` slice dated it locally and priced it
  standard. Calls `reset_capture` between phases, since the frozen-cost guard would
  otherwise (correctly) refuse a write once a previous phase's transcript is removed, and
  passes `--recapture` on every call, since capture otherwise skips a feature that
  already has a `planning.json` and several phases here re-capture under a changed
  manifest with no reset in between.
  Also covers `check_naive_bounds`: a bound with no zone is warned about by field name
  and value, a `Z`-suffixed or explicit-offset one is not, and a *sibling* manifest's
  naive bound is not — that last one is what keeps the warning actionable rather than a
  standing complaint about every other feature in both corpora.
- `sync-check.sh` — copies the real `sync-plans.sh`, `update.sh` and `templates/` (a
  missing `update.sh` is tolerated — RED until plan 77 lands, the `cost-recovery.sh`
  convention) into two throwaway fixtures. Fixture A is a consuming repo at
  `$TMP/consumer` holding copies of the three under `agentTooling/`; it asserts the
  `sync-plans.sh --check` contract: a fresh seed reports the five generated stubs and
  the three repo-owned scripts (`gate.sh`, `pr.sh`, `worktree-setup.sh`) in-sync with
  their `# template-version: <N>` line (2, 2, 1 in that order) and only
  `PROJECT_FACTS.md` unfilled, exit 1, `needs attention: 1 item(s)`; that the seeded
  `BACKLOG.md` is `in-sync` rather than a second unfilled item — an *empty* backlog is
  the correct steady state for a repo that has closed everything it found, so only its
  absence is an item — and that the generated `plans/README.md` names it, the line
  humanNetworkMap had added by hand and a sync overwrote; filling
  `PROJECT_FACTS.md` brings it to exit 0 `is in sync`; a stale generated stub is
  reported `STALE` with `--check` writing nothing, and the plain sync repairs it; a
  repo-owned script stripped of its `template-version` line is reported `DRIFT` by both
  `--check` and the plain sync (which still keeps the file); a body-only edit below a
  script's `REPO-SPECIFIC` marker is not drift; a deleted repo-owned script is reported
  `missing` and the plain sync recreates it; a `BACKLOG.md` carrying the repo's own
  entry survives a plain sync byte-identical as `kept` and is not drift, while a deleted
  one is `missing` and is re-seeded; and an unknown flag is a usage error, exit
  2. It also reads — never writes — the real checkout, asserting `gate.sh`/`pr.sh`/
  `worktree-setup.sh` carry the same `template-version` in `templates/plans/` and in
  `self/`. Fixture B is a subtree cycle: a bare `$TMP/upstream.git`, a `$TMP/work` clone
  that commits the same three copies as `main`, and `$TMP/consumer2`, which
  `git subtree add`s it at `agentTooling/`, seeds `plans/` and fills
  `PROJECT_FACTS.md`; it asserts `update.sh`: a pull with a clean tree brings across a
  new upstream file and re-runs `sync-plans.sh`, exit 0; a dirty tree refuses without
  pulling, naming the untracked file, exit 1; running it from the source checkout
  itself (no prefix to pull into) refuses naming "source checkout", exit 1; and an
  unknown flag is a usage error, exit 2. No model, no network. Depends on `git subtree`
  being available and on the three templates carrying a `template-version` line, which
  plan 77 adds.
- `sweep.sh` — copies `sweep.sh`, `plan-runner-roots.sh` and `analysis/*.py` (a missing
  `sweep.sh` is tolerated — RED until plan 78 lands, the `cost-recovery.sh` convention)
  into a throwaway `agentTooling` checkout that is a real git repo with one commit —
  unlike `capture-guard.sh`'s bare `mkdir .git`, the report step's `git status` needs a
  real one — and, under a redirected `$HOME`, one synthesized transcript (`session_line`
  from `fixtures/transcripts/build-transcript.sh` and `project_dir` from
  `feature-lifecycle.sh`, both copied rather than sourced). Asserts: an unknown flag,
  with or without `--self`, is a usage error, exit 2; a clean run over one well-formed
  feature exits 0, prints the seven banners — `rates`, `backfill`, `recover`, `capture`,
  `report`, `unclaimed`, `done` — strictly in that order, captures a `planning.json`
  with one session, writes `report.md`, and the done banner names a nonzero
  changed-file count and the `./agentTooling/update.sh` propagate line; a second run is
  a no-op on the frozen capture, `planning.json` byte-identical; and a second feature
  whose declared branch matches no transcript makes the capture step refuse — the sweep
  still exits with the done banner's two lines printed and the first feature's
  `planning.json` untouched. No model, no network. Depends on
  `analysis/capture_planning.py --all` skipping an already-captured feature
  (`capture-guard.sh` assertion 10) and exiting non-zero on a refusal without stopping
  the rest of the run (`capture-guard.sh` assertion 13).
- `template-versions.sh` — the odd one out: it reads the checked-in tree rather than
  standing up a sandbox, and calls no runner. For each of the three repo-owned templates
  (`templates/plans/{gate,pr,worktree-setup}.sh`) it asserts that the
  `# template-version: N` line matches the version recorded in
  `templates/plans/TEMPLATE_VERSIONS` (rows `<file> <version> <sha256>`) and that the
  file's content hash matches the one recorded beside it — sha256 over the file with
  comment-only and blank lines stripped, so a comment edit is free and any change to the
  code is not. A body edited without a bump FAILs, naming the file and saying to bump
  `template-version` and re-record the hash. Blocking in `../gate.sh` because such an edit
  reports `in-sync` in every consuming repo while their seeded copies are stale, which
  `sync-check.sh` assertion 8 cannot see (it only compares `templates/plans/X` and
  `self/X` to each other). Depends on the three templates carrying a `template-version`
  line and on `TEMPLATE_VERSIONS` being kept in step with them by hand.
- `direct-timing.sh` — copies `plan-runner-roots.sh`, the top-level `stamp-timing.sh` and
  `analysis/{pricing,roots,transcript,report}.py` into a throwaway checkout and
  synthesizes a `self/features/` corpus of hand-written manifests, `planning.json` files
  and `timing.jsonl` streams, asserting the direct build's milestone record
  (`../../AGENT_DIRECT.md` → "Checkpoint and resume"): `stamp-timing.sh --self <slug>
  checkpoint status=<status>` appends one line carrying that event, that key and a UTC
  `at` to the second, and appends rather than replaces; it refuses — non-zero, writing
  nothing — a missing slug or event, an unknown feature (naming it), and a detail
  argument that is not `key=value`, because a silently dropped milestone is a hole in the
  only record a direct build leaves between commits; `report.py` derives `tests_s`
  (`planned` → `tests-written`), `direct_build_s` (`tests-written` → `gating`) and
  `gate_s` (`gating` → `committed`) for a `method: direct` feature that has checkpoint
  events and renders them as `↳` sub-rows under "build: implementer" whose minutes sum to
  that row; and neither the keys nor the rows appear for a direct feature without
  checkpoint events or for a `method: plans` feature that has them. A missing
  `stamp-timing.sh` is tolerated rather than fatal, the same convention `cost-recovery.sh`
  uses, so the phases fail loudly instead of the script aborting. No model, no network.
  Depends on `stamp_timing` (`plan-runner-roots.sh`) writing through `jq`, and on
  `report.py`'s `compute_time_rollup` / `render_time_section` reading
  `event: "checkpoint"` with a `status`.
- `stale-failed-sidecars.sh` — copies `analysis/{pricing,roots,transcript,report}.py`
  into a throwaway checkout and synthesizes a `self/features/` corpus of hand-written
  manifests, `planning.json` files, plan `.md` files and `usage.json` sidecars. No
  transcripts, no model, no network: every dollar is a literal in a sidecar, which is
  what `report.py`'s no-recompute contract says it reads. The layout under test is what
  a usage-limit kill plus a manual retry leaves behind (`../../RUNNER.md` → the
  `failed/` paragraph): the runner files a plan's four sidecars as a set, so the killed
  run's `.progress.md` and `.usage.json` sit in `<queue>/failed/` while the retry's
  four sit in `complete/` — two sidecars claiming one stem, and a `failed/` pair with
  no `.md` beside it, which is exactly what crashed `feature-close.sh` on
  vinylCatalogue's `group-commit-all-adjudication`. Every fixture creates `failed/` (or
  `inprogress/`) **before** `complete/`, so a filesystem-ordered walk offers the wrong
  file first — that ordering is the assertion, since the defect was
  `build_usage_index` keeping whichever file `rglob` reached last. Asserts: the stale
  pair does not crash the report and the plan prices at the `complete/` sidecar's
  figure, whole rather than a lower bound; the live sidecar really is `complete/`'s,
  read off the plan-length table, which can only have found the `.md` that exists
  there; the stem is neither missing usage nor an orphan; a `recovered_cost_usd`
  planted in the `failed/` sidecar's `attempts[]` is added to the live figure exactly
  once and reported as recovered dollars, so money the sweep recovers into a file that
  lost the index is not dropped with it; directory rank breaks a tie when **both**
  candidates have a sibling `.md` (`complete` > `inprogress`, whichever the filesystem
  offers first — the sibling rule cannot decide there, so this is the only assertion
  that pins the rank); and a missing sibling `.md` is a warning naming the path rather
  than a crash, the plan dropped from the plan-length table but still priced. Three later phases are
  the 2026-09-06 backlog items: a prior attempt with **neither** a cost nor a recovered
  figure now marks the total a lower bound and names its `session_id` under
  `cost.unrecoverable_attempts[]`, exactly as the same shape on the live sidecar already
  did — which REVERSES what assertion 2c asserted before, since ruling 4 deliberately
  let such a prior read as free and widening it changes what `total_is_partial` means
  for every feature in both corpora; an attempt reachable through both sidecars (a
  hand-copied file: `write_usage_sidecar` merges by `session_id` into the file at the
  plan's current path) contributes its dollars once and is named once; and
  `cost.multi_sidecar_stems[]` plus one line under the Cost table report a stem with
  more than one sidecar, absent when every stem has exactly one. The recovered-twin
  phase is the contrast that keeps the first of those precise: a prior that WAS
  recovered leaves the total whole. Three further phases are that batch's review
  escalation, closed by its rework: WHICH copy of a deduplicated attempt the dollars
  come from. A live copy null on both figures beside a prior carrying
  `recovered_cost_usd` contributes that figure once, leaves the total whole and names
  the session in neither `cost.unrecoverable_attempts[]` nor `cost.unpriced_plans[]` —
  asserted both where the shared attempt is the plan's only one (the whole-plan unpriced
  path) and where the live sidecar prices an attempt of its own beside it (the
  per-attempt path the escalation described); the same fixture with the prior's figure
  removed is still unpriced, so a merge rule cannot credit a copy that carries nothing;
  and where both copies carry a figure and disagree, the LIVE one is counted, once. The
  last two are green before the rework as well as after — they are what keeps the first
  from being satisfiable by a rule that simply prefers the prior. RED until
  the deterministic index landed — the pre-fix run dies inside
  `compute_plan_length_vs_loc` with a `FileNotFoundError` for the `failed/` `.md` the
  retry moved away. A missing `analysis/` script is tolerated rather than fatal, the
  `cost-recovery.sh` convention. Depends on `report.py`'s `build_usage_index` returning
  a live path plus prior attempts, on `prior_attempt_cost` returning the merged
  `attempts` list `compute_cost_rollup` classifies and on its `ATTEMPT_FIGURE_FIELDS`
  precedence, and on the sibling-`.md`
  readers (`compute_plan_length_vs_loc`, `compute_plan_drift`) warning instead of
  raising — none of which is visible from an import line.
- `stream-capture.sh` — copies the runner scripts into a `mktemp -d` checkout with a stub
  `claude` that **ignores SIGPIPE** and emits an init event, 1500 `assistant`/`tool_use`
  pairs and a priced `result` event (ending chosen by `CLAUDE_STUB_MODE`:
  `normal` | `no-result` | `usage-limit`), and drives it through a real `run-plans.sh
  --self`. The stub's SIGPIPE disposition is the fixture: one that dies with the pipeline
  cannot tell the fix from the defect it was written against — a `tee` in the *middle* of
  the capture pipeline, whose last stage wrote to the caller's stdout, so a consumer that
  stopped reading truncated the record while `claude` ran on to a clean exit (nine merged
  reviews filed as successes with a 689-byte `.stream.jsonl`, a 0-byte `.progress.md` and
  `total_cost_usd: null`). Asserts, for a healthy consumer and again for one that exits
  after two lines — before `claude` is started — and again for one that exits mid-stream:
  the plan is filed to `complete/`, the runner exits 0, `.stream.jsonl` holds all 3002
  lines and ends with the `result` event, the sidecar is priced, and `.progress.md`
  carries one `edit: <path>` line per mutating `tool_use`. Also: a stub emitting no
  `result` event and exiting 0 is still filed by its exit code but warns, naming the plan
  and the stream file, which survives; and the usage-limit routing is unchanged — plan
  left in `inprogress/`, exit 1, reason naming the limit — with the consumer present and
  with it gone. The pre-fix run failed 14 of 31: phase 3 captured 94 of 3002 stream lines
  and 39 of 1500 progress lines, ending on an `assistant` event.
  Four later phases came from the review. **6** feeds in a stream carrying one non-JSON
  line — `claude`'s stderr is merged into it, so a runtime warning lands there — and
  pins that the sidecar and the truncation warning agree about it (priced,
  `result_event: "seen"`, no warning); they used to disagree, one `jq` tolerating bad
  lines and the other not. **7** points `$TMPDIR` at a directory that does not exist so
  `mktemp -d` fails, and asserts the plan is filed to `failed/` naming that directory
  rather than the runner hanging on a marker it can never write — the assertion is the
  watchdog, so a hang is reported instead of stalling the gate. **8** sends SIGTERM to
  the runner alone and **9** to its whole process group (`set -m` gives it one of its
  own), asserting for both that the plan stays in `inprogress/`, the runner exits 130,
  the stream holds what was captured, no `claude`/follower/`tail` is left behind, and the
  capture directory is gone — the orphan check is deliberately budgeted well under the
  `slow` stub's remaining runtime, or an unkilled `claude` finishing by itself would
  satisfy it. Verified by mutation: dropping `stop_capture`'s `kill` fails 8f, dropping
  its `rm -rf` fails 9g, and dropping `follow_stream`'s pid stop condition fails 8f
  and 9f. No model, no network.
  Depends on `plan-runner-lib.sh`'s `run_plan` capturing the stream where nothing
  downstream can truncate it, on `finalize_plan` warning on `rc == 0` with no `result`
  event, on `run_all` leaving the runner alive when its own stdout is closed, and — for
  phases 7 to 9 — on `mktemp -d` being given an explicit template under `$TMPDIR` (a bare
  `mktemp -d` ignores it on macOS, which would make every capture-directory assertion
  here pass vacuously) — none of which is visible from an import line.
- `usage-limit-kill.sh` — the runner scripts in a `mktemp -d` checkout with a stub
  `claude` that `cat`s a canned `.stream.jsonl` (`CLAUDE_STUB_STREAM`) and exits with
  `CLAUDE_STUB_RC`, driven through the real `run-plans.sh --self`. The canned stream is
  the whole fixture, which is why this is not a mode of `stream-capture.sh`: that stub
  emits 3002 lines to test capture throughput and every phase here is three events.
  Asserts the hard-killed-session half of `stream_shows_usage_limit`: a stream with no
  `result` event whose last parsed event is an `error` naming HTTP 429 — or naming a
  limit in words — leaves the plan in `auto/inprogress/` and stops the runner with a
  reason naming the limit, while the boundary cases keep routing exactly as before. No
  result and no error event is still an ordinary failure to `auto/failed/`; so is an
  `error` event naming no limit; so is a 429 error followed by more events, since the
  signal is how the stream ENDED and not a scan of its body. A trailing non-JSON line —
  `claude`'s merged stderr — does not hide the error event, since both readers parse
  with `STREAM_EVENTS_JQ`. A stream that DID reach a result event is judged by that
  event alone: a success result after a 429 error is filed complete, and assistant text
  mentioning a rate limit is still not a limit. The original signal is asserted last,
  unchanged. No model, no network. Depends on `plan-runner-lib.sh`'s
  `STREAM_HARD_KILL_LIMIT_JQ` and the shared `STREAM_LIMIT_TEXT_RE`, and on
  `finalize_plan`'s `rc == 2` branch leaving the plan queued.
- `batch-sigpipe.sh` — `level-sentinel.sh`'s scaffolding (the runner scripts, a stub
  `claude` emitting one priced `result` event, a stub green `self/gate.sh`), with
  `run-batch.sh --self` driven into `head -2` so the pipe closes while the batch is
  still inside its build pass. `check-plans.sh` is deliberately NOT copied in, so that
  script's `-x` guard skips the lint and the batch's first stdout line is always its own
  `BATCH 1/3` banner — copying it in would move the "two lines" boundary. Asserts that
  the batch survives its own closed stdout: it exits with its own code rather than 141,
  the build AND verify passes both run and file their plans with sidecars (the verify
  pass is only reachable past the gate banner that used to kill it), and a failing build
  under the same closed stdout exits 1 rather than 141. A healthy-consumer control runs
  first, so a phase-2 failure can only be the closed stdout, and it also pins that the
  batch really does print more than two lines. `${PIPESTATUS[0]}` is read inside the
  subshell that ran the pipeline; the caller's `$?` is the substitution's. Depends on
  `run-batch.sh` installing `trap 'exec >/dev/null; printf "\n"' PIPE` above its first
  write — a handler, never `trap '' PIPE`, for the reason `../PROJECT_FACTS.md` records.
- `report-footnotes.sh` — `stale-failed-sidecars.sh`'s report-only scaffolding
  (`analysis/{pricing,roots,transcript,report}.py` in a throwaway checkout, a
  synthesized `self/features/` corpus of hand-written manifests, `planning.json` files,
  plan `.md` files and sidecars; no transcripts, every dollar a literal). Its own file
  rather than a phase of that one because the subject differs: that file is about which
  sidecar the index picks, this one about what the two tables say when a figure is
  missing. Asserts the `†` mark and its footnote on both: a review plan that RAN and
  carries no `total_cost_usd` makes the Cost table's review cell something other than a
  bare `$0.0000`, with a footnote directly under the table naming the bucket, the stem,
  the reason and what recovery made of it, and with the separate **Unpriced plans**
  paragraph gone rather than duplicated — while the build and verify rows, genuinely
  empty, stay unmarked, so the mark means "unpriced" and not "zero". A fully priced
  feature carries no mark and no footnote anywhere. A review plan with a null
  `duration_ms` gets the same treatment in the Time table, and
  `time.missing_duration_plans[]` carries the `{plan, queue, reason}` shape
  `cost.unpriced_plans[]` does — both reason branches pinned by exact text (`no result
  event` from `result_event: "missing"`, `no duration reported, cause not recorded` from
  a sidecar with no such field, the shape every sidecar committed before the field
  existed still has), so no single return value satisfies both. Depends on `report.py`'s
  `MISSING_FIGURE_MARK`, `group_by_bucket`/`bucket_mark`/`bucket_footnote_lines`,
  `missing_duration_reason`, and `compute_time_rollup` returning dicts rather than
  stems — none of which is visible from an import line.
