# tests

| File | What it is |
|---|---|
| `smoke.sh` | The whole harness, end to end, against a throwaway git repo under `mktemp -d`. No network, no money, nothing touched outside the temp directory. `--keep` leaves the work directory behind for inspection. |

Run it after any change under `harness/`:

```bash
./agentTooling/harness/tests/smoke.sh
```

## What it builds

A repo with a `plans/gate.sh` that is always green and writes a report with counts in
it, a `plans/pr.sh` that records a URL in a file instead of calling a forge CLI,
`agentTooling/` symlinked to this checkout, a `SPEC.md` to pin as the fixture's spec, and
one commit as `base`, pushed to a bare remote beside it. Then a `smoke` fixture pointing
at that repo, a `smokeNull` experiment of `smoke × null × 1`, a fake `claude` behind
`HARNESS_CLAUDE_BIN` and a fake `gh` behind `HARNESS_GH_BIN` that answers `pr view` from
a per-branch file and records `pr create` into one.

The fake `claude` reads the last argument as the prompt, writes a canned `findings.md`
with exactly one escalated item when the prompt carries the review preamble's title,
touches a rework marker when it carries the rework preamble's title, and prints the
result object (`session_id`, `total_cost_usd: 0`) the harness reads its cost from.

## What it asserts

`--dry-run` creates no worktree, no branch and no ledger, and names the branch it would
create. A full run walks every one of the eight stages (each recorded in the state file),
writes one ledger row with `review_escalated == 1`, `rework_ran == true`,
`accept_pass == true` and the PR URL, renders `SCORECARD.md`, leaves no `report.json`
behind, and fills every placeholder in the brief. `--from capture` honours a
seeded freeze postdating its window (only the base repo's committed 2000-01-01 seed —
never replaced, since capture prices nothing against fake sessions — recaptures) and
its row hydrates from the state file.
`--from rework` re-enters off the saved state and appends a row that carries the gate counts and review counts from the
state file, prices a deliberately re-opened (orphaned) rework window into
`cost_lost_usd`, and notes the orphan as an intervention; run again over the now-completed stage, its
old freeze predates the rewritten window and is recaptured instead of reported, while
the review stage, which did not re-run, keeps its freeze. The worktree is removed at the end and the branch — the
cost record — stays.

After the run it exercises the scaffolding against the same repo: `new-fixture.sh`
pins full commit ids, records setup and sections, warns on a section heading it cannot
find, writes stubs that carry `@@TODO@@` and a probe that exits 1, and refuses an
existing fixture, an unresolvable ref and an absent spec path; `check-fixture.sh` rejects
that stub and passes the real `smoke` fixture; `new-experiment.sh` refuses the branch the
full run created, a stubbed fixture, an unknown method and a missing prediction, then
accepts `--override` and writes an `experiment.json` that `run.sh --dry-run` resolves to
the overridden branch; `publish.sh` creates the results branch, commits
`smokeNull: run 4 results` with the ledger and state but not `logs/`, opens the fake PR,
and is a no-op the second time.

**Capture is asserted as a recorded `0`, not as a dollar figure.** The sessions are fake,
so `capture_planning.py` can price nothing; what the test proves is that the stage runs
and that its number reaches the row.
