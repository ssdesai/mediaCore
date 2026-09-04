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
  plan with no sidecar and no `skipped:` line still is. Builds its fixtures with the shell helpers in
  `fixtures/`. No model, no network. Depends on `analysis/pricing.py`'s
  `get_rates`/`compute_cost`, `analysis/report.py`'s `compute_cost_rollup` and
  `analysis/transcript.py` and `analysis/recover_attempts.py` — a missing copy of the
  latter two is tolerated rather than fatal (the script was authored RED against
  `pricing.py` alone), so every recovery assertion fails loudly instead of the run
  aborting; the `report.py`-level assertions (13-14) were likewise authored RED against
  `self/features/recovered-totals-stay-honest`'s plan 02, which has since landed.
  `record`ed by `../gate.sh` alongside the other two.
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
  `PROJECT_FACTS.md` unfilled, exit 1, `needs attention: 1 item(s)`; filling
  `PROJECT_FACTS.md` brings it to exit 0 `is in sync`; a stale generated stub is
  reported `STALE` with `--check` writing nothing, and the plain sync repairs it; a
  repo-owned script stripped of its `template-version` line is reported `DRIFT` by both
  `--check` and the plain sync (which still keeps the file); a body-only edit below a
  script's `REPO-SPECIFIC` marker is not drift; a deleted repo-owned script is reported
  `missing` and the plain sync recreates it; and an unknown flag is a usage error, exit
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
