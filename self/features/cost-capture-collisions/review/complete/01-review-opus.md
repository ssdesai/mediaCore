# 01 — review: cost-capture-collisions

Written from the design (`self/DESIGN-2026-10-05-cloud-execution.md` §4, §6 and §10's
`cost-capture-collisions` row) and the feature manifest's "The sole-claimant cut:
decided" section **before** the build, never from the implementer's report. Read the
code; do not take the manifest's or `NOTES.md`'s account on trust. "No findings" is a
legitimate verdict. Fix local drift in this pass; anything structural is an escalation,
and an escalated report is round 2's brief. Begin your report with the `Verdict:` line
the prompt asks for.

## What the feature was supposed to do

Three capture defects, each a bug wherever it runs:

1. **§4 — runner children inherit the parent's session id.** Reproduced in the cloud
   container (manifest, "§4 reproduced"): a `claude -p` child launched with the parent's
   environment reports the parent's `session_id` and **appends its lines to the parent's
   own transcript file** as a new root (`parentUuid: null`), with the parent's
   `entrypoint`. The runner then writes that id into the plan's `*.usage.json`; the
   capture's `collect_excluded_session_ids` marks it a runner session; the main walk
   `continue`s past it before its subagent walk; and `find_pinned_elsewhere` skips this
   repo's transcript directories, so the coordinator's pinned delegate is lost too.
   - **Fix at the source.** `plan-runner-lib.sh` launches every `claude -p` with
     `CLAUDE_CODE_SESSION_ID` and `CLAUDE_CODE_REMOTE_SESSION_ID` unset and with an
     explicit `--session-id <uuid>` the runner chose (the installed CLI accepts it).
     Every runner that goes through the lib inherits the fix — `run-plans.sh`,
     `run-verify.sh`, `run-review.sh`, escalations.
   - **Robust to records already written that way.** An id a `usage.json` names is
     runner-only when none of its transcript lines lies outside a headless (runner)
     conversation tree; one whose transcript also holds interactive lines is a
     **collision**: the capture warns, naming the session and the sidecar(s), keeps the
     interactive lines as the coordinator's (priced and selected as any session would
     be), and drops the headless tree's lines, whose cost the `usage.json` already holds.
     How a tree is recognised as headless is the implementer's ruling (the reproduction
     shows `entrypoint` cannot do it) and must be recorded in `NOTES.md`.
   - **Subagents of a skipped parent are still reachable by pin.** A pinned delegate
     whose parent the main walk did not price is looked for in every directory, this
     repo's included — but a delegate of a genuine runner session is still never priced
     here (its sidecar's `total_cost_usd` includes it).
2. **§6 — a fresh ledger lets annotate delete sibling claims.** `--annotate-frozen` must
   never remove an `also_claimed_by` entry for a repo or a claimant its ledger has never
   seen: a missing claim reads as **unknown**, not absent. The design's shape: the
   ledger gains provenance of what it has registered; `--annotate-frozen` registers this
   corpus's frozen claims before annotating; repo identity is normalised to
   `host/owner/repo` (scheme, `git@`, `.git`, case dropped) **for comparison**, and
   stored records are read through the same normaliser, so nothing is migrated. An old
   ledger with no provenance must load and behave safely.
3. **The sole-claimant cut**, as decided in the manifest: a pinned session is cut to its
   window by the existing split rule (`share_owners`, `partition_seconds`, `head_bound`)
   even when this feature is its only claimant; a branch-selected sole claimant is still
   billed whole; the cut part is the disclosed unclaimed remainder.

## The diff

Base `main`; read `git diff origin/main...HEAD` (this cloud checkout may have no local
`main` ref). Expect: `plan-runner-lib.sh`, `analysis/capture_planning.py`, possibly
`analysis/report.py` and `RUNNER.md`, `self/tests/*.sh` (at least `subagent-capture.sh`
or `session-claims.sh` for §4, `claims-ledger.sh` for §6, `session-share.sh` or
`session-claims.sh` for the cut), `self/tests/README.md`, `analysis/README.md`,
`self/README.md`, `self/BACKLOG.md` if anything is left, the design doc's §10, and
`self/features/cost-capture-collisions/` (manifest prose, `NOTES.md`, `CHECKPOINT.md`,
this brief). **No other feature's directory under `self/features/` may change** — a
sibling's `planning.json`, `report.json` or `report.md` in the diff is a finding of the
first order, since it is exactly what §6 exists to stop. Anything else that moved is a
finding.

## Contracts to hold it to

- **Tests came first and test the promise.** The branch should show
  `cost-capture-collisions: acceptance tests` before the implementation. In the existing
  self-test files there must be, black-box through the CLI and disk:
  - **§4 reproduction:** a fixture whose runner `usage.json` names the coordinator's id,
    with that id's transcript holding both the coordinator's interactive lines and a
    runner tree, still captures the coordinator (its interactive cost only) **and** its
    pinned subagent, and warns about the collision; a usage.json id whose transcript is
    runner-only is still excluded exactly as before.
  - **§4 at the source:** a runner (`run-review.sh` is the design's choice) driven with a
    stubbed `claude` that records `CLAUDE_CODE_SESSION_ID` / `CLAUDE_CODE_REMOTE_SESSION_ID`
    and its `--session-id`: the child sees neither variable, receives a valid uuid that
    differs from the parent's, and the resulting `usage.json` records that uuid.
  - **§6 reproduction:** an empty ledger (scratch `HOME`), a corpus whose frozen records
    carry `also_claimed_by` naming both a feature of this corpus and one of another repo
    the ledger has never seen; `--annotate-frozen` changes no record and the capture
    commits no sibling. A ledger that has seen repo X and claimant X/s still removes a
    stale `X/s` mention as before. The https and ssh spellings of one origin are one
    identity.
  - **The cut:** a pinned sole-claimant session that outruns its window is billed only
    for its window (plus the bounded head), with the rest in `unclaimed_usd` /
    `unclaimed_duration_s` and the sums still exact; a branch-selected sole claimant is
    billed exactly as on `main`.
  Check each exists and would fail on `main`'s code. Mutate one site mentally — e.g.
  restore the `continue` for a usage.json id, or let annotate delete an unseen mention —
  and say which assertion catches it.
- **No assertion weakened.** Existing `check` lines in the touched tests are unchanged
  unless the behaviour they pinned is what this feature changes (a pinned sole claimant
  billed whole is the obvious candidate); each such change must be justified in
  `NOTES.md`.
- **No frozen figure moves without a recapture.** Normalising repo identity must not
  change any `feature` string written into `share_basis` or `also_claimed_by` (they carry
  the display name, e.g. `agentTooling/<slug>`), so the annotation pass over this
  corpus's real records changes nothing. Run, with a scratch empty `HOME`,
  `python3 analysis/capture_planning.py --self --annotate-frozen` against a copy of the
  corpus if you need to, or read the code closely enough to say why it is a no-op.
- **The runner change is safe on both platforms**: bash 3.2, a uuid source available on
  macOS and Linux, `env -u` used the way the existing `env` call is, named constants
  (CONVENTIONS "Named constants"), and a failure to mint a uuid handled rather than
  passing an empty `--session-id`.
- **The gate passes.** Run `./self/gate.sh` and report its verdict line, and each touched
  test on its own.
- **READMEs** (CONVENTIONS "Keeping READMEs up to date"): `analysis/README.md`'s
  `capture_planning.py` entry describes the collision rule, the ledger's new section with
  its full field list (Rule 1 — it is an on-disk JSON shape read across repos), and the
  sole-claimant cut in place of "a session with one claimant is priced whole";
  `RUNNER.md` or the lib's comments state the scrub; `self/tests/README.md` rows describe
  the new cases; the design's §10 records what was built and what the close found.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
