# self/tests

Behavioural checks for the harness, run by `../gate.sh`. Each is a plain bash script that
exits non-zero on a failed assertion and prints one `ok`/`FAIL` line per check; none
calls a model or the network. `../PROJECT_FACTS.md` → Tests says there is no test
*runner* here — that is still true; these are scripts the gate `record`s directly.

**No test reads or writes the real `~/.claude`.** The seam is `$HOME`: every script here
that touches a transcript or the claims ledger exports `HOME` to its own `mktemp -d`
before calling a script under `analysis/`, and `Path.home()` — which resolves the
`~/.claude/projects/` glob and `claims_ledger_path()` alike — follows it. There is no
narrower override, deliberately: one that moved the ledger alone would let a test write
the ledger under `mktemp -d` while still reading the machine's own transcripts.

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
  slug `S` and primary checkout `R`, branch `S`, worktree `R/.worktrees/S` inside the
  primary, and every session a feature costs is either launched in that worktree or
  pinned by id. Its `project_dir` helper mangles `.` as well as `/`, as Claude Code does,
  which is what files a nested worktree's transcripts under `…-R--worktrees-S`. Asserts
  that `feature-start.sh` creates the branch and worktree off `origin/main` at
  `R/.worktrees/S` (nothing at the legacy `R-S`), leaving the primary on `main` and
  clean — `git status --porcelain` empty with the worktree nested in it, because the
  common git dir's `info/exclude` now carries `/.worktrees/` exactly once, still exactly
  once after seven more starts, every entry it already held (an unterminated last line
  included) intact, and nothing tracked touched — writes the manifest (`branches [S]`, `base main`, a `Z`
  `from`, `to` null, the running session pinned from `$CLAUDE_CODE_SESSION_ID`) and a
  `@@TODO@@` review stub numbered next in the global sequence, commits `S: start`, and
  refuses a bad slug, an existing branch, a worktree path already taken and a worktree's
  copy while creating nothing;
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
  exactly the cost files as `S: cost records`, prints one
  `pinned    N delegate(s) already pinned in the manifest` line instead of telling the
  human to pin a delegate the manifest already pins, removes the
  worktree and branch (keeping both under `--keep-worktree --no-push`), and writes and
  stamps nothing when the capture matches nothing — rolling that carry back, so a refused
  close leaves the primary byte-identical and clean rather than dirty and refusing its own
  re-run. No model, no network. A missing
  script fails its own assertions loudly rather than aborting the run, the convention
  `cost-recovery.sh` uses.
  Its **W** phase is where `session_window.to` comes from
  (`self/features/claim-window-precision/README.md`, item 1). Its fixture moves the
  feature's `from` back to a fixed instant with `set_bound` — a local helper that rewrites
  one bound inside the manifest's last fence, by hand because two of the shapes it needs
  are exactly what `manifest.py` refuses to write — and plants a branch session running
  `12:00:00.700` to `12:45` at a fixed date hours earlier plus, under it, a delegate that
  ran on to `13:00:00.700`. That fixture is what lets **W1** assert one exact `to`
  (`13:00:01Z`) carrying three separate facts: it is the DELEGATE's last instant +1s, not
  the parent's, so the subagent walk in `last_branch_instant` cannot be deleted silently;
  it is at second resolution though the evidence carried milliseconds, so the
  `replace(microsecond=0)` truncation cannot be dropped silently (an untruncated
  `13:00:01.700000Z` parses everywhere and would fail nothing else); and it carries a date
  a bound stamped at close time could never equal. W1 also asserts that both the session
  and the delegate are still captured under the now-exclusive bound. **W2** gives a feature
  nothing but a pinned session off the branch and in another checkout: no branch-selected
  session, so the close falls back to its own clock and prints the `no branch session`
  line. **W3** moves that bound later by hand — the shape every `to` in both corpora
  already had — and pins that `--recapture` tightens it back onto the evidence, printing
  `old -> new`. **W4** is the refusals, and their exit codes: `set-window-to --tighten`
  with a LATER instant must leave the fence byte-identical, name both bounds, and exit
  **3**, the widen refusal's own code — the exit code matters because the close continues
  past that one and only that one, and asserting merely "non-zero" would pass vacuously
  under an unimplemented `--tighten`, where argparse exits 2; the bound it already carries
  is asserted to be a no-op rather than a refusal, which is what `recover-at-close.sh` C12
  needs from every repair run; and a bound at or before the fence's `from` — an empty
  window, which every other feature's split would then drop — is refused as a plain exit
  1, naming both, with the primary left clean by all four. **W5** is the other side of
  that exit code: a close over a fence with no `to` key at all (so `set-window-to` fails
  for a reason that is not a refused widen) must refuse, name what `set-window-to` printed
  rather than the widen it never attempted, capture nothing, and roll its timing carry back
  so the primary is clean and byte-identical. Its feature is given a real branch session on
  purpose — without one the close would refuse at the capture anyway and the assertion
  would pass whatever the stamp did. **W6** is W5's complement and the reason the exit code
  is asserted at all: the tolerated code is written down twice, `WIDEN_REFUSED_EXIT` in
  `manifest.py` and `WIDEN_REFUSED_RC` in `feature-close.sh`, since bash cannot import it,
  so a drift between them would turn every declined widen into a refused close. It moves
  the bound to `12:30` by hand — between the session's first line and its last, the one
  shape from which the evidence widens rather than tightens, which is why the W1 fixture
  carries that middle `12:45` line — and asserts the close warns, captures anyway and
  leaves the published bound where it found it.
  Its **L** phase is the legacy layout (`self/features/in-repo-worktrees/README.md`): a
  feature started normally has its worktree moved by `git worktree move` to the sibling
  `R-S` every feature started before worktrees moved inside the primary still has, and
  the close must claim the session launched there by branch, carry that worktree's
  trailing timing stamp home, and remove it and the branch, leaving the primary clean;
  a `--recapture` afterwards, with the worktree gone, must still claim the session.
  Depends on `plan-runner-lib.sh` refusing the `@@TODO@@`
  marker, on `feature-start.sh` writing the `info/exclude` entry and `feature-close.sh`
  finding the worktree through `git worktree list --porcelain`, on
  `capture_planning.py`'s `--list-subagents`/`--list-sessions --unclaimed`,
  its zero refusal and its `--last-branch-instant` (including the subagent walk and the
  whole-second truncation), on `feature-close.sh` stamping from that evidence before the
  capture, rolling the stamp back with `rollback_stamp` and tolerating exactly
  `manifest.py`'s widen exit code at the stamp, and on `analysis/manifest.py`'s `init`,
  `get`, `claimed` and `set-window-to [--tighten]`.
- `worktree-claims.sh` — `capture-guard.sh`'s scaffolding (copies of
  `analysis/{pricing,roots,transcript,capture_planning}.py` in a throwaway checkout, a
  bare `mkdir .git`, transcripts under a redirected `$HOME`), asserting which launch
  directories feature `S` claims a session from now that worktrees are nested in the
  primary `R` (`self/features/in-repo-worktrees/README.md`). Its `mktemp -d` template is
  `wt.claims.XXXXXX` on purpose: the dots put a `.` in `R`'s own path, so every project
  dir is named with `/` and `.` both mangled to `-`, as Claude Code names them, and W0
  checks that premise and the `…-R--worktrees-S` name of the nested one. One manifest
  and six sessions on `S`'s branch, all in the window: launched in `R`, in
  `R/.worktrees/S` (with a delegate under it), in the legacy sibling `R-S`, and — later
  than those — in `R/.worktrees/<other>` and in the prefix-sharing `R/.worktrees/S-two`
  and `R-S-two`. Asserts that capture selects the first three by branch with their
  `cwd`s (W1) and none of the other three, although each sits under `R` or starts with
  one of `S`'s own worktree paths, naming the other worktree's directory in the warning
  (W2; W2d–e are the prefix cases, which a bare `startswith(root)` in
  `path_at_or_under` fails, verified by weakening it); that the delegate filed under the nested project dir
  is priced with its parent (W3); that `--last-branch-instant` is the delegate's last
  instant + 1s rather than the other worktree's later one (W4); and that
  `--list-sessions` and `--list-subagents` find what is filed under the nested and
  legacy project dirs (W5). W1c-d, W2 and W4 were RED until `capture_planning.py`
  fenced `R/.worktrees` (`claim_roots`, `cwd_claimable`); everything was RED until
  `transcript_dir_name` mangled `.`. Depends on `session_line`/`subagent_line`/
  `subagent_prompt_line` from `fixtures/transcripts/build-transcript.sh`. The legacy half
  of the rule is also `capture-guard.sh` phase 15. No model, no network.
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
- `recover-duration.sh` — `recover-at-close.sh`'s phase-B scaffolding on its own:
  `analysis/{pricing,roots,transcript,recover_attempts}.py` in a throwaway checkout, a
  synthesized `self/features/` corpus of `usage.json` sidecars, and
  `~/.claude/projects/*/<session_id>.jsonl` transcripts under a redirected `$HOME`.
  Asserts the lower bound `recover_attempts.py` derives beside the dollars
  (`self/features/recovered-duration-lower-bound/README.md`, item 1): an unpriced attempt
  whose transcript survives gains `recovered_duration_s`, the seconds between the
  transcript's **first and last timestamped lines** — the fixture's last line is a `user`
  line later than any assistant response, so a span taken over
  `iter_billable_messages`'s yields instead of over the transcript fails the assertion —
  while `total_cost_usd` and `duration_ms` both stay null; the sidecar's top-level
  `recovered_duration_s` is the sum over its recovered attempts, as the top-level
  `recovered_cost_usd` beside it already was; a transcript with fewer than two
  timestamped lines writes no duration at all rather than `0.0`, and no top-level key
  either; an attempt whose transcript is gone is left byte-identical and reported
  unrecoverable; an attempt carrying a recovered cost and no duration — every attempt
  recovered before this existed — is skipped by an ordinary run and backfilled by
  `--force`; and an attempt with a measured `duration_ms` is never visited. Depends on
  `recover_attempts.py`'s `recover_attempt` returning the span in its field dict and on
  its top-level merge writing the duration key only when some attempt carries one;
  RED until both landed.
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
- `claims-ledger.sh` — `subagent-capture.sh`'s scaffolding, asserting what the ledger at
  `$HOME/.claude/subagent-claims.json` counts as claimed
  (`self/features/recovered-duration-lower-bound/README.md`, items 2 and 3, plus that
  feature's two review escalations). Four parts.
  **A**: `--list-subagents --unclaimed --for <repo>/<slug>` drops a delegate whose id is
  already in that feature's manifest `subagents` — "unclaimed" used to mean "not claimed
  through a branch", so every close printed its own pinned delegates and told the human
  to pin them — while an unpinned sibling briefed for the same feature is still listed
  with the `Pin each in` advice beside it, and with every delegate pinned the list is
  empty and the advice is gone. A delegate already in the ledger is still dropped, read
  from a **legacy flat** ledger file (agent id → claim, no section keys — the shape on
  every machine today), which is how that half asserts an old ledger still loads. **B**:
  two manifests pinning one session id — the coordinator that spans features. The second
  capture is *not* refused the way a doubly-claimed subagent is, its `planning.json`
  session entry gains `also_claimed_by: ["<repo>/<slug>"]`, the ledger holds both claims
  under that session id as a **list** (a session may have many claimants, a subagent
  exactly one), and re-capturing the first feature annotates it symmetrically. Neither
  manifest declares a `session_window`, so both claims are unbounded and the money is
  split evenly between them: `report.py` renders
  `cost.shared_sessions[{session_id, cost_usd, session_cost_usd, also_claimed_by}]`,
  where `cost_usd` is this feature's own share and `session_cost_usd` the undivided
  session beside it, the two features' shares sum to `session_cost_usd`, and the one
  footnote under the Cost table names the session and the other feature without saying
  it is counted in full — the sentence that was the whole disclosure before the split
  existed. A `planning.json` frozen before the share rule carries `also_claimed_by` but
  none of `share_basis`/`session_cost_usd`/`session_duration_s`, and is still reported
  the old way: `shared_sessions[]` with no `session_cost_usd`, and a footnote that falls
  back to saying the session is counted in full there. Finally the **in-flight
  co-claimant**: `also_claimed_by` stripped while `share_basis` is left in place — the
  shape of a feature that captures while another feature pinning the same session has not
  captured yet, so the split found the co-claimant through its manifest but the ledger
  holds no claim from it. That record still produces a `shared_sessions[]` entry naming
  the co-claimant recovered from `share_basis`, and a footnote, because keying the
  disclosure off the ledger alone prints a halved figure with nothing saying what halved
  it — a silent under-count, worse than the disclosed over-count the split removed, and
  the corpus's normal case rather than a corner. The record is restored from a copy
  immediately afterwards, since part C asserts an exact `2 annotated` count over a sweep
  of the whole corpus.
  **C**: the annotate-only path over a record that is already **frozen** — two features
  each captured while the ledger held no claim on their shared coordinator, which is the
  shape the seven closes of 2026-09-07 left behind. One plain `capture_planning.py --all`
  (no `--recapture`, what `sweep.sh` runs) leaves each of them naming the other, and it
  does so in a single run because every frozen record is registered in the ledger before
  any is annotated — convergence must not depend on the order the corpus is walked in.
  Everything else in both files is byte-identical (asserted over the whole record with
  `also_claimed_by` stripped, not over a list of fields), the run reports them as
  `annotated`, `report.py` then renders the footnote, and a second `--all` writes
  nothing. The shared session's transcript is **deleted before the sweep**, which is what
  asserts the path opens none — the reason a frozen record can take it at all. **D**: the
  same-slug corpus preference — a `plans/features/<slug>` pinning a delegate and a
  `self/features/<slug>` of the same name that does not. Under `--self` the delegate is
  still listed as unclaimed (the self corpus owns the query), without `--self` it is not,
  and a slug the queried corpus does not hold at all falls back to the slug alone across
  both. Before it, the other corpus's pin silenced `feature-close.sh`'s stop-on-unpinned
  guard and the delegate was never priced.
  Depends on `capture_planning.py`'s `load_ledger`/`save_ledger` two-section shape,
  `manifest_pinned_subagents`, `register_frozen_claims`/`annotate_frozen_record`, and
  `report.py`'s `compute_shared_sessions`; RED until each landed. D writes into
  `$TMP/plans/features`, the host repo's corpus, which `all_features_roots()` resolves
  as the sibling of the throwaway agentTooling checkout.
- `session-share.sh` — `claims-ledger.sh`'s arithmetic counterpart: same scaffolding
  (copies of `analysis/{pricing,roots,transcript,capture_planning}.py` into a throwaway
  agentTooling checkout, `mkdir -p "$AT/.git"`, and, under a redirected `$HOME`, the
  `~/.claude/projects/*/<session_id>.jsonl` transcripts capture reads, built with
  `session_line` from `fixtures/transcripts/build-transcript.sh`). Asserts what a session
  claimed by more than one feature is priced and timed by — *concurrent share* rather
  than being counted in full by every claimant. One session
  (`11111111-0000-0000-0000-000000000001`) carries six responses, all input/cache-read/
  cache-creation `0` so cost is proportional to output tokens alone:

  | id | timestamp | output tokens |
  |---|---|---|
  | `r0` | `08:00` | 1000 |
  | `r1` | `10:30` | 2000 |
  | `r2` | `12:30` | 4000 |
  | `r3` | `14:30` | 6000 |
  | `r4` | `16:30` | 12000 |
  | `r5` | `20:30` | 800 |

  Four features (`share-a`..`share-d`) pin that session id in their manifest's
  `sessions`, with `branches` naming a branch no transcript carries — the pin is the only
  route in — and these windows: `share-a` `10:00`-`18:00`, `share-b` `12:00`-`18:00`,
  `share-c` `14:00`-`18:00`, `share-d` `16:00`-`18:00`. A fifth, `share-solo`, pins its own
  session and is claimed by nobody else. Ownership per response is every claimant whose
  window covers its timestamp, with the earliest claimant alone owning anything before
  every window opens and nobody owning anything after every window closes: owned output
  tokens are **a 10000, b 7000, c 5000, d 3000, unclaimed 800**, summing to the session's
  25800; duration, partitioned the same way over `[first line, last line]` = 45000s, is
  **a 22200, b 7800, c 4200, d 1800, unclaimed 9000**. Captures the four in order a, b, c,
  d, then re-captures `share-a` so its record sees the other three claims — a claimant not
  yet captured is still found through its manifest alone. Asserts, in order: (1) the four
  shares plus the unclaimed remainder equal the session's own `cost_usd.total`, to `1e-9`
  — the assertion the whole feature exists for; (2) each feature's `cost_usd.total`
  matches its predicted token-ratio share; (3) the earliest claimant's total strictly
  exceeds what its share would be without the head response, while the other three carry
  none of it; (4) `share_basis` on the earliest claimant's entry names all four claimants
  — itself first with `source: "self"`, the other three `"manifest"` with their own
  manifests' `from`/`to`, asserted as a set rather than an order; (5) `duration_s` is
  apportioned by the same rule (22200/7800/4200/1800), `session_duration_s` is the whole
  45000s span on every entry, the unclaimed span is **read from the record's own
  `unclaimed_duration_s`** and the four apportioned spans plus it sum to 45000 — an
  earlier cut asserted the unclaimed `9000` as a literal, which supplied the missing
  seconds itself instead of catching their absence and so could not see a session leaking
  time, and `started_at`/`ended_at` stay the session's own first and last instants
  throughout — only `duration_s` is apportioned; (6) `share-solo`'s single-claimant entry
  carries none of `share_basis`, `session_cost_usd`, `session_duration_s` or
  `unclaimed_usd`, no `priced[]` row carries `share` or `full_cost_usd`, `duration_s`
  equals `ended_at - started_at`, and `cost_usd.total` is the whole transcript's cost;
  (7) a second `r2` line appended at `11:59:59.500`, before `share-b`'s `from` of `12:00`,
  while `r2`'s first line — first in *file* order, which is what `iter_billable_messages_at`
  keys on — stays at `12:30` inside that window: the two lines of one response sit in
  *different* ownership stretches, `{share-a}` and `{share-a, share-b}`. It is still billed
  once and to its first line's owners: assertion (1)'s invariant still holds and `share-a`/
  `share-b`'s totals from (2) are unchanged. Both halves are load-bearing — a walk that
  buckets lines by window and dedups within each bucket bills `r2` once per bucket and
  breaks (1), and one that dates a response by its *last* line hands all 4000 tokens to
  `share-a` and breaks (2). An earlier cut of this phase appended the line at
  `12:00:00.001`, on the same side of every boundary as `12:30` and in the same ownership
  set, where no dedup strategy can differ and all three checks passed vacuously; (8) capture output names the session in an
  unclaimed-remainder warning, `unclaimed_usd` is exactly the `800/25800` share of the
  session cost, and — `8c`, added by `bounded-opening-stretch`'s rework — that warning is
  the pre-existing tail sentence with no head clause in it, this session having no head
  (`share-a`'s eight-hour window puts its bound four hours before `r0`); (9) a sixth feature `share-empty`, pinning the same session with a
  *backwards* window (`09:00`-`03:00`), owns nothing — not the head its early `from` would
  otherwise rank it first for, and not a second of duration — while a-d's totals and the
  sum invariant are unchanged; (10) the same defect from its other side, `share-empty-2`
  (`05:00`-`03:00`, opening before the session's own first response), must not strand the
  head in the unclaimed remainder; (11) its costliest shape — `share-solo-empty` pins
  `share-solo`'s single-claimant session with a backwards window, and `share-solo` must
  stay unshared (no `share_basis`, whole cost, untouched duration) with the offending
  claim named on stdout. An empty claim from another feature is dropped from the claim set
  outright rather than merely refused a share, because `select_parent` branches on
  `len(intervals) <= 1`: counted, it flips a solo session onto the share path and its one
  real owner loses everything past its own `to`. Phases 9 and 10 are the two ways an empty window
  reaches the split — pinning by id skips window matching entirely, so a backwards window
  arrives intact and the head-stretch ranking orders on `from` alone: one shape pays it,
  the other silently underpays the legitimate earliest claimant. Both were caught in the
  verify pass, not the build. Extracts the repeated JSON reads into `field` (a `python3 -c` over
  `json.load`) and `close_enough` (the `1e-9` float comparison) near the top rather than
  repeating a one-liner in every check. Phases 1-5 and 7-8 were RED until
  `capture_planning.py` learns to share a multiply-claimed session — a run against
  today's code is expected to FAIL them, not crash. Phase 6 is GREEN today and must stay
  green: it is the no-change half of the contract, pinning that a session with a single
  claimant is never touched by this feature. Phases 9-10 were RED against the build pass's
  own first cut of `share_owners`, which filtered empty windows out of `in_window` matching
  but not out of the opening-stretch ranking. No model, no network.
  Two later phases are `claim-window-precision`'s. **12** is the size of what phase 6
  leaves unsliced: `share-outside` pins a session of its own with 1000 output tokens
  inside its window and 3000 after it, so the dollars past `to` are exactly three quarters
  of the session's cost and a warning that named the whole session, or only the part
  inside, prints a different figure. The figure is read back out of the warning
  numerically (a 4-decimal string compare would fail on a last-place rounding difference)
  and `cost_usd.total` is asserted to exceed it, which is what pins the session as still
  priced whole; `12g` is the other branch of the same sentence, `not counted`, off
  share-a's own capture. **13** tightens `share-d`'s `to` to `16:15` — past its `from` but
  before its only response at `16:30` — through the real `manifest.py set-window-to
  --tighten`, which is why this file also copies `manifest.py` into the sandbox. share-d
  then owns nothing and the sum invariant from (1) still holds; `13c` asserts share-c's
  total ROSE, so a tighten that silently did nothing cannot pass. `16:00` was rejected as
  the tightened bound: it makes share-d's own window empty, and the assertion would then
  be satisfied by the pre-existing empty-claim drop rather than by the moved bound.
  **14** is phase 12's warning where there is nothing to quantify: `share-quiet` pins a
  session with one response well inside its window and, half a second past `to`, an
  unbilled `user_line`. The warning fires on the last LINE while the quantity counts
  billable RESPONSES at or after `to`, so the two are out of step and the quantified
  sentence would assert a measurement of nothing. The assertion is the absence of the
  figure — read back with the same `sed` phase 12 uses to read its presence, so a
  formatted `$0.0000` fails rather than passing as "zero is zero anyway" — plus the
  qualitative sentence saying no billable response falls past `to`, and `cost_usd.total`
  still non-zero, the warning being prose either way.
  **15** is `bounded-opening-stretch`'s, on a session and claimants of its own
  (`66666666-0000-0000-0000-000000000006`; `head-a` `10:00`-`11:00`, `head-b`
  `12:00`-`18:00`; responses `r0` `08:00`/1000, `r1` `09:30`/2000, `r2` `10:30`/4000,
  `r3` `13:00`/3000) so that nothing above is re-run or disturbed. The opening-stretch
  fallback pays the earliest claimant only as far back as that claimant's own window is
  long — `head-a`'s hour puts its bound at `09:00`, so `r1` is still its own and `r0`,
  two hours out, is owned by nobody. Asserts `head-a`'s total is `r1 + r2`; that
  `unclaimed_usd` is exactly `r0`'s `1000/10000` share and the two totals plus it equal
  `session_cost_usd`; that `head-b` is unchanged at `r3` alone; that `duration_s` splits
  the same way — `head-a` `09:00`-`11:00` = 7200s, `unclaimed_duration_s` the 3600s
  before the bound plus the 3600s gap between the two windows, the three summing to the
  18000s span; that the unclaimed warning names the head's dollars and seconds APART from
  the rest of the remainder (the figure read back numerically, as `12c` does) and names
  the remedies that reach a head — pin the session, or move the earliest claimant's
  `from` back by hand, `from` having no `set-window-to`; and that an earliest claimant
  whose `to` is still `null` keeps the UNBOUNDED head, a window with no end having no
  length to bound by, which is why `write_manifest` writes a bare JSON `null` for a `to`
  of the literal string `null`. `15a`, `15b` and `15b-sum`, `15d` and `15d-unclaimed`,
  and every `15e` check were RED against the unbounded fallback on `main`, which pays
  `head-a` the `08:00` response and `08:00`-`11:00` of the span; `15c`, `15d-sum`, `15f`
  and `15f-unclaimed` are green on both sides and are the guard, as is phase 3 — an
  eight-hour window still reaches a head response two hours out, which is what stops the
  bound being read as a fixed grace period. `15f-duration*` is that phase's rework
  addition, the seconds side of the in-flight exemption: with `head-a`'s `to` `null`,
  `head-a`'s `duration_s` is 16200 (`08:00`-`10:00` as the unbounded head, `10:00`-`12:00`
  as its own open-ended window, and half of the `12:00`-`13:00` overlap), `head-b`'s is
  1800, and there is no `unclaimed_duration_s` at all. It is the one path where
  `partition_seconds` gets `head_edge = None` and adds no cut point, so it is where the
  dollars and the seconds are least constrained to agree, and `15f` asserted only dollars.
  **16** and **17** are the same feature's rework. **16** is a remainder that is ALL head:
  a session of its own (`77777777-0000-0000-0000-000000000007`; `n0` `08:00`/1000, `n1`
  `10:30`/2000, `n2` `13:00`/3000) with `allhead-a` `10:00`-`11:00` and `allhead-b`
  `11:00`-`14:00` chaining end to end — `in_window` is half-open, so `to == from` leaves
  no gap — and running past the last response, so the only unowned instants are the
  `08:00`-`09:00` before `allhead-a`'s bound. The warning must then drop its "and $0.0000
  (0s) is the rest" clause and its "For the rest" sentence rather than hand the reader the
  `to`-widening remedy for nothing, which no `to` widened forwards could reach anyway.
  `16a`/`16a-usd` assert the fixture's own premise — `unclaimed_duration_s` is 3600 and
  `unclaimed_usd` is `n0`'s `1000/6000` share — without which the two negative greps would
  pass vacuously on any session that simply has no head. **17** pins the bound's INCLUSIVE
  edge (ruling 1 is `min_from - moment <= to - from`): a fresh session again
  (`88888888-0000-0000-0000-000000000008`; `e0` `09:00`/1000, `e1` `10:30`/2000, `e2`
  `13:00`/3000, `edge-a` `10:00`-`11:00`, `edge-b` `11:00`-`18:00`), since a fifth response
  on phase 15's session would re-base every token fraction in `15a`-`15f`. `edge-a`'s hour
  puts its bound at `09:00` exactly, where `e0` sits: its `cost_usd.total` is `e0 + e1`,
  its `duration_s` is 7200 (`[bound, from)` plus its own window), and nothing on the
  session is unclaimed in either currency. `16c` and `16d` were RED against the build
  pass's own warning, which always emitted both halves of the sentence pair; `17a`, `17b`
  and `17c` are red only under a mutation — flip `share_owners`' `moment < bound` to `<=`
  and all three move, while `15a` (the dollars) stays green, which is exactly the gap.
  `8c`, `15f-duration*`, `16a`, `16a-usd`, `16b` and `16e` are guards, green before and
  after. `8c` is the fourth escalation, on phase 1's output: with no head the warning is
  the pre-existing tail sentence and carries no head clause at all — the `elif` branch had
  no reader before it.
- `session-claims.sh` — `session-share.sh`'s counterpart on the claim-set side: same
  scaffolding, plus a `write_host_manifest` twin of `write_self_manifest` that writes into
  `$TMP/plans/features` (the enclosing repo's own corpus, per `claims-ledger.sh` part D)
  and direct writes/edits of `$FAKE_HOME/.claude/subagent-claims.json`. One session
  (`33333333-0000-0000-0000-000000000003`) with four responses two hours apart from
  `2026-06-02T10:00:00.000Z`, equal output tokens so cost is proportional to them alone;
  `claim-here`, in the self corpus, pins it with window `10:00`-`20:00`. Asserts the three
  sources a claimant is found from and their ranking: (1) a manifest in the OTHER corpus —
  `claim-there`, window `14:00`-`20:00` — is found live, `share_basis` naming
  `<enclosing repo>/claim-there` with source `"manifest"`, claim-here's total three
  quarters of the session cost (it owns the first two responses alone, half of the last
  two); (2) with that manifest gone, a claimant in a THIRD repo this checkout cannot read
  a manifest from at all — `otherRepo/claim-elsewhere` — is found from the ledger's
  `sessions` section instead, same three quarters, source `"ledger"`; (3) a *stale* ledger
  entry for `claim-there` under its own `(repo, slug)` does not duplicate its live,
  current manifest entry — one entry, source `"manifest"`, carrying the manifest's
  current `from` rather than the ledger's old one; (4) a claim with no `window` key at all
  (the shape recorded before this feature existed) is read as unbounded — `from`/`to` both
  null in `share_basis` — splits claim-here's cost exactly in half, and is warned about by
  name; the same claim seeded into a LEGACY FLAT ledger (no `subagents`/`sessions` keys)
  still loads but is never read as a session claim — claim-here's cost reverts to the
  full, unshared figure, no `share_basis` at all; (5) a fifth response appended as the
  parent transcript's OWN sidechain line (`session_line … true`, plan 89's addition),
  inside every claimant's window, is shared the same way: `cost_usd.sidechain` is halved
  on this feature and `cost_usd.total` still equals `main + sidechain`; (6) after a
  capture, the ledger's own `agentTooling/claim-here` entry carries a `window` of
  NORMALIZED instants (python `isoformat`, `+00:00`) rather than the manifest's raw
  strings, asserted by parsing rather than string equality — the shape a third repo's
  capture (assertion 2's scenario) reads; (7) a record frozen with no other claimant, then
  claimed by a manifest and a ledger entry that both appear only after the freeze, is
  ANNOTATED by a plain `--all` (no `--recapture`) rather than recomputed — every field
  byte-identical to the frozen copy but `also_claimed_by` (asserted with
  `same_but_annotation`, `claims-ledger.sh` part C's helper), and the run separately warns
  naming the slug and the session that the frozen figure predates the share rule and
  `--recapture` would rebuild it while the transcript still exists — and goes on warning on
  the SECOND consecutive `--all` (7d-7f), which writes nothing: the annotation converges on
  the first sweep and the stale full-count figure does not, so a warning keyed off "did
  this run write" asks for the repair once and then goes quiet for as long as the
  transcript has left, while the `skipping` line still means the run wrote nothing;
  (8) the subagent side
  of the ledger is untouched — a subagent claim-here already claims still refuses a second
  feature's (`claim-twin`'s) capture outright, one check, asserted by reference to
  `subagent-capture.sh`'s own fixture rather than re-derived here; (9) the claimant scan is
  indexed once per capture rather than repeated per selected session — a `python3 - <<'PY'`
  block (the `sys.path` insert of the copied `analysis/` the other tests use) wraps
  `parse_manifest` in a counter, calls `build_claimant_index`, then
  `session_claim_intervals` for three different session ids, and asserts the counter did
  not grow after the index was built. It refuses to pass on an empty corpus (`VACUOUS`
  below two manifests parsed), since a count of zero is trivially stable; what the index
  must not change is any *answer*, and that is asserted by every other check in this file
  and in `session-share.sh` rather than here; (10) the same claim set asked of the
  **vendored** layout, in a second sandbox — assertions 1-9 stand up the standalone shape
  (`$AT` holds the `.git`), where the self corpus's identity comes out right whichever
  rule derives it. Here a consuming repo `vendorHost` holds a real `git init` with a real
  `origin` (not the bare `mkdir .git` the rest of the file uses: an invalid `.git` makes
  the subprocess exit 128 and `repo_identity` fall back to the *vendored* directory's own
  name, `agentTooling`, which is accidentally the right answer — the wrong answer needs a
  `git` that succeeds), `agentTooling/` beneath it with no `.git`, and the transcripts
  filed under the enclosing directory's project path with `cwd` the enclosing directory,
  so `session_root(True)` is the consumer. Four equal responses, `claim-here` and
  `claim-self-twin` both in the self corpus with windows covering the whole transcript:
  the twin appears in `share_basis` as `agentTooling/claim-self-twin` with source
  `manifest` (10a) and nothing in `share_basis` is named for the enclosing repo, the
  capturing feature itself included (10b); a ledger claim on the same feature under the
  declared identity and a *different* window dedupes into that one entry rather than
  becoming a third claimant (10c), keeping the manifest's `from` (10d); `claim-here`'s
  total is therefore half the session, not the 5/12 three claims produce (10e); and the
  ledger row the capture writes for itself carries `repo`
  `https://github.com/ssdesai/agentTooling.git` and `repo_name` `agentTooling` (10f, 10g).
  The fixture's own precondition is checked rather than assumed — `git -C $VHOST remote
  get-url origin` really is `$VENDOR_ORIGIN` (10-pre) — because a `git` that failed there
  would hand the rule the *right* answer by accident and pass the whole phase vacuously.
  10h-10j then put assertion 7's shape into the same layout, which is the only route
  through `register_frozen_claims` and the `--all` loop's `annotate_frozen_record` call:
  the ledger is reseeded to the two rows a SHARED ledger really holds here — `claim-here`'s
  own and a second feature's, both under the declared identity, since the standalone
  checkout's `--self` runs wrote them — and a plain `--all` (no `--recapture`) annotates
  the frozen record rather than recomputing it (10-annotated, `same_but_annotation`
  again), naming `agentTooling/claim-self-twin` in `also_claimed_by` (10h) and nothing
  ending in `/claim-here` (10i), while the ledger keeps exactly ONE `claim-here` row and
  it carries the declared identity (10j). 10i is the defect in that path:
  `other_session_claimants` excludes a feature's own claim by `(repo, slug)`, so a frozen
  `--self` record annotated under the consumer's origin misses its own `agentTooling`
  ledger row and lists ITSELF among its co-claimants.
  1-7 were RED until `capture_planning.py` looked beyond its own corpus and its own
  manifest for a session's claimants, and 10a-10g, 10i and 10j until `corpus_identity`
  declared the self corpus's identity rather than deriving it (10-pre, 10-annotated and
  10h are green either way: they pin the fixture and the branch taken, not the identity); (8) was GREEN throughout — the subagent
  refusal it pins is pre-existing and must stay exactly as it is while the session side
  grows around it. No model, no network.
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
- `allow-repo-commands.sh` — builds a throwaway project root with a venv symlink, an
  in-repo worktree and two symlinks that escape the tree, then feeds the real
  `hooks/allow-repo-commands.sh` the payload Claude Code sends, one command at a time.
  Asserts the four `cd X && cmd` shapes that motivated the hook are approved along with
  ordinary reads and runs; that every bypass the audit found is refused (variable
  expansion, `--flag=value` paths, attached and combined short flags, sed's `w`,
  `git branch` mutation, exec-through flags, brace expansion, `|&`, relative paths and
  globs through symlinks, symlink-following recursion, redirects, a NUL byte); that
  single-quoted shell characters are literal while double-quoted ones are not; that a
  worktree session cannot reach the main repo; and that a payload without `cwd`, with
  `cwd` outside the root, for another tool, or without `CLAUDE_PROJECT_DIR` approves
  nothing. `~` and `/etc/hosts` are symlink targets and command text only — nothing is
  read from either. The list of bypasses is `hooks/README.md` → What the audit found.
- `hook-wiring.sh` — thirteen throwaway repos, one per starting state of
  `.claude/settings.json` (absent, unrelated content, hook only, deny rules only, a
  partial deny list with a repo's own rule in it, complete, a different hook, six
  malformed shapes). Asserts `hooks/wire-settings.py --check` and `--write` report the
  documented status and exit code and agree; that after a write every deny rule is
  present and exactly one hook entry names the script; that nothing the repo had is
  removed or changed, including a hand-customized hook path; that a second write is
  `kept` with the file byte-identical and `--check` then says `in-sync`; and that
  malformed files are `INVALID` in both modes and untouched.
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
  `self/` (8), and that the upstream URL is ONE string across the three places that
  mirror it by hand: `analysis/roots.py`'s `SELF_CORPUS_IDENTITY` (read by importing
  `roots`), `update.sh`'s `DEFAULT_REMOTE` (read by parsing the literal) and the root
  `README.md`'s `git subtree` commands (8b-8d). All three comments say they move
  together and nothing else enforces it; the failure mode is silent and is the one
  `self-corpus-identity` fixed — move the remote in one and not the others and every new
  `--self` ledger claim carries a `repo` matching none of the historical rows, so one
  feature deduplicates against nothing and is counted twice. Fixture B is a subtree cycle: a bare `$TMP/upstream.git`, a `$TMP/work` clone
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
  Two later phases pin the Time table's **second** mark
  (`self/features/recovered-duration-lower-bound/README.md`, item 1): a plan whose
  `duration_ms` is null but whose attempt carries a `recovered_duration_s` contributes
  that span to its bucket, is listed under `time.recovered_duration_plans[]` in the
  `{plan, queue, reason}` shape plus `recovered_s`, is **not** also listed under
  `missing_duration_plans[]`, and its row reads `7.5 ‡` rather than `0.0 †` — two marks
  because `†` says the bucket has no figure and `‡` says it has one and it is a lower
  bound — with a footnote naming the plan, the seconds and the transcript span, while
  `total_is_partial` and the lower-bound line both stay. The phase beside it re-reads the
  transcript-is-gone fixture and pins that nothing about it changed: still `†`, still a
  bare `0.0`, no `‡` anywhere. Both marks are asserted by glyph, so changing either is a
  visible change to the tests.
