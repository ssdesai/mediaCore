# Tooling backlog, September 2026: resume, stacking, timing, gitignore

Nine small items that accumulated while the direct one-shot and the timing work
landed (PRs #24–#26) and while three vinylCatalogue batches ran on the runners. None
is large; together they are one direct one-shot (`../../../AGENT_DIRECT.md`), the first
run of that method on this repo, with its own checkpoint doctrine applied to itself.

## The items, with the decision each one is built to

1. **A resumed batch settles a crossed level even when nothing is left to build.**
   `run-batch.sh:193-197` settles a crossed-but-unsettled level only if
   `auto/incomplete/` is non-empty. A batch killed during its last level's level-verify
   (every build plan already complete) resumes past the tier ladder: the ordinary verify
   pass runs the queued level-verify plan, but a red gate there never escalates and the
   batch reports the failure only at the final gate. Drop the `auto/incomplete/`
   condition: settle whenever the last crossed sentinel is not settled (level-verify
   pending, or its gate not green). A finished batch re-run with its gate reports intact
   settles nothing; one re-run on a fresh clone (reports are gitignored) re-runs that
   level's mechanical gate once, which is the cheap and honest outcome. Assert it in
   `self/tests/tiered-gates.sh` as a phase beside phase 4: sentinel crossed, level-verify
   queued, `auto/incomplete/` empty → the resume message prints and the level-verify
   runs before the verify pass.
2. **The batch runner is told the paused level's number, not left to re-derive it.**
   `run-batch.sh` recovers `NN` with `last_sentinel_nn` (a sort over completed sentinels)
   where `run-plans.sh` knew it one process earlier. Add a `LEVEL_PAUSE_NN_OUT`
   handshake shaped exactly like `FEATURE_SLUG_OUT` (`plan-runner-lib.sh:763`,
   `run-batch.sh:84`): the runner writes the sentinel's `NN` to the file when it exits
   `LEVEL_PAUSE_RC`; the batch reads it and falls back to `last_sentinel_nn` only when
   the file is absent or empty. An empty `NN` after both is a build failure — print it
   and exit 1 — never a `run-verify.sh --up-to ""`. Assert in
   `self/tests/level-sentinel.sh`: the number the batch resolves equals the sentinel's,
   and the empty case exits 1 with the message rather than reaching `run-verify.sh`.
3. **The review prompt says a skipped check is not a pass.** `run-review.sh:71` tells the
   review executor "a green gate is your starting condition" and nothing about skips;
   `run-verify.sh:136` has the sentence. Add the same sentence, same wording, to the
   review prompt's item 4, ending "state in your verdict exactly what is consequently
   unverified".
4. **Stacked pull requests, in the template and in `self/pr.sh`.** vinylCatalogue's
   repo-owned `plans/pr.sh` (`/Users/sahildesai/dev/vinylCatalogue/plans/pr.sh`, the
   reference; diff it against `templates/plans/pr.sh`) branches `review/<slug>` off
   *whatever is checked out* and opens the PR against that branch, so batches stack
   without waiting for a merge; re-run already on the review branch, it reads
   `BASE_BRANCH` from the environment (default `main`) for a first-time `pr create`.
   Port that logic verbatim into `templates/plans/pr.sh` and `self/pr.sh`. `README.md`
   → "Updating" gets a numbered step for repos that seeded `pr.sh` before this (it is
   never overwritten): what to hand-merge, in one sentence each. `ORCHESTRATION.md`
   gets one line: stacked batches export `BASE_BRANCH=<previous review branch>` when
   re-running the review pass.
5. **Direct builds stamp their milestones into `timing.jsonl`.** A direct feature's
   build span comes only from the implementer's transcript; the Time table cannot show
   tests-first against build against gate the way it splits passes for a planned
   feature. Add a top-level `stamp-timing.sh` — `stamp-timing.sh [--self] <slug> <event>
   [key=value …]`, `--self` first like every other script — that sources
   `plan-runner-roots.sh`, sets `FEATURE_SLUG`, and calls `stamp_timing`. The
   implementer runs `./agentTooling/stamp-timing.sh <slug> checkpoint status=<status>`
   at every checkpoint milestone; `AGENT_DIRECT.md` → "Checkpoint and resume" says so
   next to the rewrite rule, and says the checkpoint's `updated:` line is `date -u
   '+%Y-%m-%dT%H:%M:%SZ'`, never guessed. `harness/methods/direct/template.md` gets the
   same one line. `analysis/report.py`: for `method: direct`, when `checkpoint` events
   exist, derive `tests_s` (`planned` → `tests-written`), `direct_build_s`
   (`tests-written` → `gating`) and `gate_s` (`gating` → `committed`) and render them
   as indented sub-rows under "build: implementer"; with no events, nothing changes.
   A planned feature's report is byte-identical before and after. `analysis/README.md`
   documents the event and the keys. The new script joins `shell_scripts` in
   `self/gate.sh` and gets a row in `README.md`'s table. Assert the report rows in the
   self test that already builds report-level fixtures (`cost-recovery.sh`), or a new
   `self/tests/direct-timing.sh` if that file is the wrong home — either way, a row in
   `self/tests/README.md`.
6. **`sync-plans.sh` manages `plans/.gitignore`.** Consuming repos have no detector for
   the hand-maintained gitignore step (`README.md` install step 2, Updating step 3); a
   missed one commits per-level gate reports. Decision: a generated stub, not a warning.
   `templates/plans/.gitignore` holds `gate-report*.txt`, `**/*.stream.jsonl`,
   `**/*.logfifo` with a two-line comment; `sync-plans.sh` adds it to `GENERATED` and
   writes it like the READMEs; `templates/README.md` lists it; the two README steps
   become "sync writes `plans/.gitignore`; root-level patterns from an earlier install
   are harmless and can go". agentTooling's own root `.gitignore` must cover the same
   three patterns under `self/` — check, and add what is missing.
7. **`--list-subagents` from outside the repo names the flag.** Run from a directory
   above the repo, `capture_planning.py --list-subagents` finds no transcripts and says
   only that. When the scan is empty and `--everywhere` was not given, the message
   ends: "scanned <root> only; run from the repo, or pass --everywhere". Scope
   unchanged.
8. **`updated:` comes from `date -u`.** Part of 5; listed so it is not lost.
9. **A skipped level-verify is not missing usage.** `analysis/report.py` lists a
   level-verify plan the runner filed as skipped — `verify/complete/NN-level-*-sonnet.md`
   whose `.progress.md` opens `skipped: level NN gate reported 'all checks passed'`
   (`AGENT_PLANS.md` → Levels, D3; no `.usage.json` by design, the same marker
   `self/tests/level-sentinel.sh` asserts) — under "Missing usage for", and marks the
   feature's total partial and a lower bound. It is neither: nothing ran. Recognise the
   skipped sidecar and keep it out of the missing-usage list and the partial flag; a
   separate one-line "skipped" note is fine. A plan with no sidecar and no `skipped:`
   line is still missing. Assert both in `cost-recovery.sh`'s report-level phase. Seen
   on vinylCatalogue's `shell-jobs-and-review-refresh`, plan `05-level-backend`.

## Deliberately excluded

- Separating the coordinator's briefing minutes out of a direct feature's build cost.
  Documented as a known gap in `AGENT_DIRECT.md`; needs a design, not a fix.
- Resuming a harness experiment cell (`harness/methods/direct/run.sh`). A resumed cell
  is a different measurement.
- `harness/publish.sh`'s own PR flow. Experiments do not stack.

## Plans

| Plan | Model | Does |
|---|---|---|
| `71-review-opus` | opus | Independent review of the diff against `main`, from this manifest, not from the implementer's report. |

Built directly: no `auto/`, no `verify/`. `CHECKPOINT.md` and `NOTES.md` are the
implementer's.

```json
{
  "slug": "tooling-backlog-2026-09",
  "method": "direct",
  "plans": ["71-review-opus"],
  "branches": ["review/tooling-backlog-2026-09"],
  "session_window": {"from": "2026-09-02T12:37:09Z", "to": "2026-09-02T13:16:05Z"},
  "exclude_sessions": [],
  "subagents": ["aacf0dc983e425041"]
}
```
