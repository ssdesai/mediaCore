# tests

| File | What it is |
|---|---|
| `smoke.sh` | The whole harness, end to end, against a throwaway git repo under `mktemp -d`: the cell pipeline, the scaffolding, the pins, and the program cell (a program of two fixtures with a dependent second; a failed-implementer program; `--only` and `--from record`; the version-floor refusal; the lib and cost unit checks). No network, no money, nothing touched outside the temp directory. The longest of the three. `--keep` leaves the work directory behind for inspection. |
| `scorecard-arms.sh` | `scorecard.py`'s arm-aware comparisons on a hand-built `results.jsonl` (fixture `f`, methods `a`/`b`, arms `before`/`after`, then one unpinned row). No repo, no network, nothing outside a `mktemp -d` directory. Reads `scorecard.py`'s `render()` / `compare()` wording, so a change to it is a change here. |
| `scorecard-time.sh` | `scorecard.py`'s time columns on a hand-built ledger (fixture `f`; method `a` three times, one `method_failed`; method `b` once with no `t_green`): the Runs table's `Wall to PR` / `Wall to green` / `Total` with known minutes, `—` for a missing instant, the Per cell `Mean wall to PR` / `Mean total` with the failed row left out, the footnote line, and no Per cell section for one run per cell. No repo, no network, nothing outside a `mktemp -d` directory. Reads `scorecard.py`'s `render()` / `mean_minutes()`. |
| `scorecard-accept.sh` | `scorecard.py`'s failed runs, Per cell outcomes and `## Acceptance` section on a hand-built ledger (fixture `f`; method `a` twice good — one with $5 `cost_lost_usd` — and once `method_failed` at $0, the `discogsPrefillStructure` shape; method `b` twice): the failed row out of the means and the band line (a tie, not a drag), `Failed` 1 and `Spend` with the lost dollars, `Mean wall to green`; the pass counts at PR-open (`null` not counted, `—` when no row measured it) and at green; the per-check table with `FAIL → pass` transitions and green-only cells; a PR-open failure under failures; and no section for a ledger with neither field, nor for one whose rows carry the PR-open fields as `null` (the accept stage off). No repo, no network, nothing outside a `mktemp -d` directory. Reads `scorecard.py`'s `render()` / `render_accept()`. |
| `scorecard-programs.sh` | `scorecard.py`'s program section on a hand-built ledger: two `kind: "program"` rows (program `pr1`, arms `before`/`after`, two features each) beside two ordinary cell rows. Also holds the byte-identity check against `scorecard-programs.cells.md`. No repo, no network, nothing outside a `mktemp -d` directory; needs `jq`. Reads `scorecard.py`'s `render_programs()` / `program_comparisons()` wording, so a change to it is a change here. `--write-expected` rewrites the fixture. |
| `scorecard-programs.cells.md` | The scorecard `scorecard.py` rendered for `scorecard-programs.sh`'s experiment and its two cell rows alone, with no program row in the ledger — the expected text of the byte-identity check. Not hand-edited; regenerated with `scorecard-programs.sh --write-expected` only when an ordinary cell's rendering is meant to change. |
| `arm-base.sh` | `lib.sh`'s arm-kind helpers (`harness_experiment_arm_kind`, `harness_experiment_arms`) on hand-written `experiment.json`s — none, `agent_tooling`, `base_arms`, both (refused), malformed — and `scorecard.py`'s base-arm rendering on a hand-built ledger: the header's `base arms:` list, the `<arm> (base <sha7>)` label and the arm and method comparison lines. No repo, no network, nothing outside a `mktemp -d` directory. |
| `arm-spec.sh` | Arm spec paths, offline: `harness_check_arm_spec_paths` on accepted and refused pairings (a label that is not a base arm, a base arm with no path, absolute or `..` paths); `harness_build_isolation` for each `HARNESS_SPEC_SOURCE` (`arm` fills the own-copy rule and provenance, a bogus value dies naming it); and the shared-spec fill of the method templates and isolation paragraph compared byte for byte with `arm-spec.shared.md`. `--write-expected [--from-ref <ref>]` rewrites that file from the templates at the ref; `--from-ref <ref>` compares against them. No repo, no network, nothing outside a `mktemp -d` directory. |
| `arm-spec.shared.md` | The prompts a shared-spec cell renders, as they were before arm spec paths existed — the expected text of `arm-spec.sh`'s byte-identity check. Not hand-edited; generated with `arm-spec.sh --write-expected --from-ref <ref>` from that ref's templates. |
| `reading-metrics.sh` | `reading_metrics.py` on fabricated transcripts under a `mktemp -d` projects root: the window (both ends inclusive), the first edit, a repeated file counted once, an errored read not counted, a subagent's reads counted, README bytes after the edit counted, a sibling `<tree>2` project directory ignored, the no-edit and no-transcript cases, usage errors; then `scorecard.py`'s `## Reading before the first edit` table (grouped digits, `—` for not measured, absent for a ledger without the fields). No repo, no network. |
| `plans-method.sh` | The `plans` method's batch half (`methods/plans/run.sh`) against a throwaway git tree with a finished corpus, a stub `agentTooling/run-batch.sh` and a fake `claude`: a successful batch exits 0 and leaves the tree clean, its log (appended across runs) under `HARNESS_LOG_DIR`; a non-zero batch with no usage-limit evidence exits 1 after exactly one `run-batch.sh` call, log tail in the warning; the runners' usage-limit and interrupt summaries exit 2 after one call; earlier runs' evidence in the appended log does not count; an escalation wins; a first call runs the architect, and a call with the batch already started (a plan in `inprogress/`) skips it and resumes the batch; and the two evidence strings are still in `plan-runner-lib.sh`. No model, no network, nothing outside a `mktemp -d` directory. |
| `long-runs.sh` | `run.sh`'s long-run behaviour, black-box, one throwaway consumer per case (method `null`, two repeats, so two cells; a stub `claude` that exits 1, since no case runs a model stage): repeated `--only` (and an unmatched spec refused before any cell starts), `--from` past `setup` on a cell with no worktree refused naming `--reset`, `--time-budget` (exit 75, a `resume: ` line with one `--only` per unstarted cell, the estimate taken from a finished cell's state file), the per-experiment lock under the git common dir (live pid refuses a run or a reset, dead pid is taken over, `--dry-run` ignores it) and `--reset` (worktree and branch renamed `…Killed<ts>`, state moved to `state/killed/`, a fresh state keeping only `cost_lost_usd`, `results.jsonl` untouched; refusals and usage errors). Offline, a few seconds. |
| `review-model.sh` | `HARNESS_REVIEW_MODEL`, black-box and offline: `lib.sh`'s resolution (unset and empty give `HARNESS_MODEL`, a value is kept whatever `HARNESS_MODEL` is) and `run.sh --dry-run` on a throwaway `direct` consumer under distinct build and review model names: unset, every stage line names the build model; set, only the review line names the review model and the method and rework lines keep the build model. The review call's argv and the ledger row are in `smoke.sh`. |
| `review-effort.sh` | `HARNESS_REVIEW_EFFORT`, black-box and offline: `lib.sh`'s resolution (unset and empty give `HARNESS_EFFORT`, a value is kept, a bad one is refused naming the variable), the `harness_claude` seam with a stub `claude` that logs its argv (a caller's `--effort` replaces the run-wide one, so exactly one `--effort` reaches the CLI; without one, `HARNESS_EFFORT` is added once; neither, none) and `run.sh --dry-run` on a throwaway `direct` consumer: neither set, no `--effort` anywhere; `HARNESS_EFFORT` alone, every stage line carries it; both set, only the review line carries the review effort and the method and rework lines keep the build effort. The review call's argv and the ledger row are in `smoke.sh`. |

`self/gate.sh` runs all twelve (steps `harness plans method self-test`, `harness scorecard arms self-test`,
`harness scorecard time self-test`, `harness scorecard accept self-test`,
`harness scorecard programs self-test`, `harness arm base self-test`,
`harness arm spec self-test`, `harness reading metrics self-test`, `harness long-runs self-test`, `harness review model self-test`, `harness review effort self-test` and `harness smoke test`, under "experiment
harness"), syntax-checks every `harness/*.sh`, `harness/methods/*/*.sh` and
`harness/tests/*.sh`, and compiles `scorecard.py`; a change under `harness/` is covered
by the gate. To run one alone, from the repo root:

```bash
./agentTooling/harness/tests/smoke.sh
./agentTooling/harness/tests/scorecard-arms.sh
./agentTooling/harness/tests/scorecard-programs.sh
./agentTooling/harness/tests/scorecard-time.sh
./agentTooling/harness/tests/scorecard-accept.sh
./agentTooling/harness/tests/arm-base.sh
./agentTooling/harness/tests/arm-spec.sh
./agentTooling/harness/tests/reading-metrics.sh
./agentTooling/harness/tests/long-runs.sh
./agentTooling/harness/tests/review-model.sh
./agentTooling/harness/tests/review-effort.sh
```

## What it builds

A repo with a `plans/gate.sh` that is always green and writes a report with counts in
it, a `plans/pr.sh` that records a URL in a file instead of calling a forge CLI,
`agentTooling/` symlinked to this checkout, a `SPEC.md` to pin as the fixture's spec, and
one commit as `base`, pushed to a bare remote beside it (the consumer's `origin`). Then a
`smoke` fixture with no `repo` block and no `spec.url` (it measures the consumer it lives
on, and its spec worktree is added from the consumer's own checkout), a `smokeNull`
experiment of `smoke × null × 1`, a fake `claude` behind `HARNESS_CLAUDE_BIN`, and a fake
`forge.sh` behind `HARNESS_FORGE_BIN` that answers `pr-find` from a per-branch file and
records `pr-open` into one. `HARNESS_AGENT_TOOLING_URL` is this checkout, so the pinned
run needs no network. The work directory is `mktemp -d` with an explicit template under
`$TMPDIR` — the `-t <prefix>` form is macOS-only and left `WORK` empty on Linux, where the
test then wrote at `/`.

**The driver seam.** The harness refuses to run unless the consumer's own `agentTooling/` is
the copy being run (`harness_require_own_driver` in `lib.sh`). `smoke.sh` drives throwaway
consumers from this checkout, so it exports `HARNESS_TEST_EXTERNAL_DRIVER=1` (a named constant
in `lib.sh`) for everything except the one section that asserts the refusal, which runs
under `env -u`. It is a test seam, not an operator option: nothing else sets it.

**The harness-opened PR.** Two `direct` cells run with `SMOKE_IMPL_NO_PR=1` (the fake
builds, commits and pushes but opens no PR: the harness must open it through the fake
forge, and the row carries `pr_opened_by_harness: true` and an intervention, `method_failed`
false) and `SMOKE_IMPL_NO_COMMIT=1` (it exits 0 having built nothing: still
`method_failed`, no PR opened). The scaffolding section also pushes a prep commit to a
branch the consumer never fetched and asserts `check-fixture.sh` fetches the base by sha
once, creates no ref, and still fails a base no remote has. A third cell
(`SMOKE_FORGE_OPEN_FAILS=1`, the fake forge refusing `pr-open`) ends `no-pr`/`method_failed`
with its worktree removed; `run.sh --from review` on it then must open the PR, record
`pr_opened_by_harness` and a "resumed from no-pr" intervention, make no model call (the
method is not re-run), log that it re-captures the method's slug — and only that slug —
at the driver's rates, and leave a non-failed row. Before the resume the test commits a
far-future frozen `planning.json` (`captured_at` 2099, `cost_usd.total` 5.0) onto the
cell's local branch, which no stale-freeze rule would rebuild: the capture log must then
carry no `<slug>: already captured` line, so dropping `--recapture` from `capture_one`
fails the suite. The row's `cost_method_usd` is not asserted: the fake sessions price
nothing, so the honoured `--recapture` refuses to write a $0 record and the freeze stays.
For the resume alone the `smoke` fixture's `setup[]` is swapped for one that logs its
`pwd` (restored after): the setup must run exactly once, in the re-added worktree, and
before the `accept at PR-open` line. A fourth cell (`SMOKE_IMPL_CLOSES_WINDOW=1`, the fake
stamping its manifest window's `to` as a plans arm's own close does) must exit 0 with no
`no open session_window` error, an informational line instead, and no "close the manifest
session window" commit, while the harness-opened-PR cell still carries that commit.
After the scaffolding's base checks, the **reference check** (`ablation-harness-fixes`):
the real fixture warns that it names no reference; a derived fixture whose
`reference.commit` is the `smokeNull` branch (the marker built) passes, having run its
`setup[]` once in a worktree that is not the consumer and removed it with no ref created
or moved; one whose reference is the base (no marker) fails quoting the probe's `FAIL`
line; `--no-reference` skips it; and `--reference <commit>` checks a fixture that names
none. Offline unit checks of the same seams are `self/tests/harness-driver-measures.sh`.

The fake `claude` reads the prompt on stdin, writes a canned `findings.md`
with exactly one escalated item when the prompt carries the review preamble's title,
touches a rework marker when it carries the rework preamble's title, builds the marker,
pushes and opens its PR when the prompt is the `direct` method's brief, and prints the
result object (`session_id`, `total_cost_usd`) the harness reads its cost from — 0, except
a `direct` implementer, which reports `SMOKE_IMPL_REPORTED_USD`. With
`SMOKE_PRICED_TRANSCRIPTS=1` (and `SMOKE_COST_MODEL`, `SMOKE_COST_INPUT_TOKENS`,
`SMOKE_COST_OUTPUT_TOKENS`) the implementer, review and rework calls also leave a billed
transcript under `$HOME/.claude/projects/<the cwd's project>/`, recording the real cwd and
branch; the program cell's fake does the same for its calls. With `SMOKE_ARGV_LOG` set it
appends each call's argv to that file and ignores every flag, which is how the effort
assertions see `--effort` reach the seam.

`HARNESS_EFFORT` is asserted in `smoke.sh`: an ordinary dry run shows no `--effort` and the
full run's row (ordinary and program) has `effort == null`; a dry run under
`HARNESS_EFFORT=max` shows `--effort max` on the method, review and rework lines (and the
program cell's orchestrator, implementer, review and rework lines); the second `--from
rework` run is made under it and its argv log and row both say `max`; `HARNESS_EFFORT=huge`
makes the dry run exit non-zero naming the levels.

`HARNESS_REVIEW_MODEL` is asserted in `smoke.sh` too: the full run is made under distinct
`HARNESS_MODEL` and `HARNESS_REVIEW_MODEL` values with `SMOKE_ARGV_LOG` set, and exactly one
logged call (the budget-capped review) carries the review model while the method and rework
calls carry the build model only; its row has `model` and `review_model` as set, and the
`--from capture` row, made with the review model unset, has `review_model == model`. The
program cell's dry run under both names puts the review model on the per-feature review line
only (rework keeps the build model), and its row, made with the review model unset, has
`review_model == model`.

`HARNESS_REVIEW_EFFORT` is asserted in `smoke.sh` as well: the full run is made with only the
review effort set (`high`), and exactly one logged call, the review call, carries any
`--effort`, the rework call none; its row has `review_effort == high` and `effort == null`. The
`--from capture` row, made with neither set, has both null; the second `--from rework` run,
made under `HARNESS_EFFORT=max` alone, has `review_effort == max`. The program cell's dry run
under both variables puts the review effort on the per-feature review line only, and its row,
made with neither set, has `review_effort == null`.

## What it asserts

`--dry-run` creates no worktree, no branch and no ledger, and names the branch it would
create. A full run walks every one of the eight stages (each recorded in the state file),
writes one ledger row with `review_escalated == 1`, `rework_ran == true`,
`accept_pass == true`, `accept_pr_open_pass == true` (the probe also ran on the PR-open
tree, into its own `-accept-pr-open.txt` log) and the PR URL, renders `SCORECARD.md`, leaves no `report.json`
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

Then the repository rule (an experiment runs from, and lives on, the repository it
measures), in two sections.

- **The repository a fixture measures.** `new-fixture.sh` with no `--repo`/`--spec-repo`
  writes no `repo` block and no `spec.url`, and refuses a `--repo` that is another
  repository. A fixture whose `repo.url` is the consumer's own origin (`smokeOwnUrl`) passes
  `check-fixture.sh`, `run.sh --dry-run` and `new-experiment.sh`; one whose `repo.url` names
  another repository (`smokeOther`, `acme/other`) is refused by all three, the message naming
  `acme/other` and ending "run it there". `repo.path` is checked on its own through
  `check-fixture.sh`: the consumer's own directory passes (`smokePathOwn`); a checkout of
  another repository (`smokePathOther`) is refused naming `acme/other` and "run it there"; a
  path that does not exist (`smokePathMissing`) is refused naming the path; and the
  consumer's own `repo.url` beside such a stale path (`smokePathStale`) is refused too. A program whose `repo.url` names another
  repository is refused by `harness_program_check` and by `new-experiment.sh --programs`
  (`this program measures acme/other`), and one naming the consumer's own URL passes. A
  fixture with no `spec.url` gets its spec worktree from the consumer: the dry-run line says
  "from the consumer's own checkout", and the full run's `<consumer>-fx-smoke` worktree
  exists, is detached at the spec commit and shares the consumer's git directory. A
  fixture whose spec lives elsewhere (`smokeExtSpec`, `spec.url` naming a second bare
  remote with its own checkout) is the only use of the resolver now: with the roots pointed
  at an empty directory, `HARNESS_REPO_DIR_SPECREMOTE` names the checkout and nothing is
  cloned; without it `spec.url` is cloned into that root under the repository's name and
  `check-fixture.sh` says so; a dry run names the external spec repository and the clone it
  would make without making it. A fixture in the pre-URL shape for its spec (`spec.repo`, no
  `spec.url`) passes with a warning naming `spec.url` and dry-runs from the path hint.
- **The external-driver refusal.** Without the seam, `run.sh`, `check-fixture.sh`,
  `new-experiment.sh`, `new-fixture.sh` and `publish.sh` given `--consumer` a repository
  whose `agentTooling/` is not this checkout exit non-zero saying "The harness runs from the
  measured repository's own agentTooling/" and naming `agentTooling/update.sh`; a consumer
  whose `agentTooling/` is this very checkout (the symlink the smoke repo carries) is
  accepted without the seam; and with the seam set the foreign consumer gets past the check.

Then a pinned arm: `new-experiment.sh --agent-tooling head=HEAD` writes
`agent_tooling.head` as this checkout's full commit id and lists `smokePinnedNullHead`,
refuses a label that is not bare letters and a ref that does not resolve; the dry run
names the pin; `--only` with another arm selects nothing; and the run itself leaves the
worktree's `agentTooling/` a real directory holding the pinned tree (not the symlink),
one commit titled `EXPERIMENT ARM (revert before merge): pin agentTooling to upstream
<sha7>`, the generated `plans/README.md` the pinned copy's sync wrote, and a ledger row
carrying `arm` and `agent_tooling`, with the arm in the scorecard; the unpinned run's
row carries an empty `arm`. The pinned row carries `arm_kind: "agent_tooling"` and the
unpinned row `arm_kind: ""` with its three reading fields `null` (no transcript, not
measured). An `experiment.json` whose `agent_tooling` is `"abc"` (not an
object of `<label>: <sha>`) makes `run.sh --dry-run` exit non-zero, print no `branch:` line
and name the expected shape, instead of running every cell unpinned.

Then a resume after a failed pin (`smokeResume`, branch `smokeResumedNullHead`): with
`HARNESS_AGENT_TOOLING_URL` naming a directory that is not a checkout and
`HARNESS_REPO_ROOTS` an empty directory, the run exits non-zero after `worktree add` —
worktree and branch exist, no pin commit, `agentTooling/` still the base's symlink, no
ledger row. Re-run with the real upstream, the same cell reuses that worktree and pins it:
the pin commit is on the branch exactly once, `agentTooling/` is a real directory holding
`harness/lib.sh`, and the row's `agent_tooling` is the arm's full sha. A further
`--from setup` adds no second pin commit.

Last, the control arm (`smokeControl` fixture, `smokeControlRun` experiment, branch
`smokeControlledNullHead`): a prep commit off the smoke base replaces the `agentTooling/`
symlink with a real directory — `git archive` of this checkout's HEAD, its pinned `sync-plans.sh`
already run — and becomes the fixture's `base`, so the arm's pin changes nothing. The run
exits 0 with exactly one pin commit on the branch, that commit lists no files under
`git show --stat` and has its parent's tree, `agentTooling/` is still the real directory, and
the row's `agent_tooling` is the arm's full sha. A further `--from setup` finds the empty
commit by its subject and adds no second one.

Then the base arms (section 8b, `smokeBaseArms` experiment, branches `smokeBasedNullOld` and
`smokeBasedNullNew`): a restructure commit is cut from the smoke base on `smokeRestructure`
(it adds a marker file) and pushed to `origin`. `new-experiment.sh --base-arms
old=<base>,new=smokeRestructure` writes `base_arms` with full shas (the branch resolved) and
no `agent_tooling`, and the README lists both branches. It refuses five shapes — a ref that
does not resolve, a sha `origin` does not have (both naming the repository rule), `--base-arms`
with `--agent-tooling` (never both), with `--programs` (does not combine with programs), and a
label that is not bare letters. Two hand-edited `experiment.json` files, one adding
`agent_tooling` and one adding `programs`, make `run.sh --dry-run` exit non-zero, print no
`branch:` line and name the same two reasons. The dry run of the real experiment names both
branches and a `base:  arm new at <sha>` line, with no `pinned to upstream` line. The full
`new` cell is cut at the restructure commit: the marker file is present, the branch descends
from that commit with no pin commit, `agentTooling/` is still the base's symlink, and the row
carries `arm: "new"`, `arm_kind: "base"`, `base` the restructure sha, an empty
`agent_tooling` and `fixture: "smoke"`; the scorecard shows `new (base <sha7>)` and a
`base arms:` line.

Then arm spec paths (section 8c, `smokeArmSpec` experiment, over the same two base arms):
`new-experiment.sh --base-arms … --arm-spec-path old=SPEC.md,new=<marker file>` writes
`arm_spec_paths` with each arm's path. It refuses eight shapes, each non-zero and naming the
reason — `--arm-spec-path` without `--base-arms`, with `--agent-tooling` alone, a label that
is not a base arm, a base arm left without a path, an absolute path, a `..` component, a path
absent at the arm's commit, and a file only the other arm's commit has. A hand-edited
`experiment.json` with `arm_spec_paths` and no `base_arms` makes `run.sh --dry-run` exit
non-zero, print no `branch:` line and name that it needs base arms. The dry run of the real
experiment names each arm's spec path "in its own tree" and adds no detached spec worktree. The
full `new` cell's brief names the marker file inside the cell's own tree, calls it this arm's
own copy and never mentions the shared spec worktree, and its row carries `spec_source: "arm"`,
`spec_path` the marker, `arm_kind: "base"`; the earlier ordinary ledger row carries
`spec_source: "shared"` and `spec_path: "SPEC.md"`.

Then the program cell, in `smoke.sh` too (its fake `claude` also answers the three program
prompts, matched by their titles `# Harness program brief`, `# Harness program feature` and
`# Harness program collect`; its `METHOD:` last line is what the driver parses). These
sections are described from the brief they were written to; read `smoke.sh` for what each
one finally asserts:

- **A program of two fixtures, the second dependent on the first.** `new-experiment.sh
  --programs` scaffolds it; `run.sh` walks `setup brief loop collect review rework accept
  capture record`; the ledger gains one `kind: "program"` row whose second feature has
  `dependency_ok == true`, a `pr_base` naming the first feature's branch, an implementer
  `session`, and whose `cost_overhead_usd` and `record_report` are present; the orchestration
  record names both features and has its window closed; the program branch is pushed and no
  PR is opened for it; the scorecard renders a `## Programs` section.
  The program's fake implementer leaves a priced transcript whose cwd is the real tree
  (`<repo>-<Branch>`, no fabricated legacy sibling), so the non-zero cost assertions prove
  `capture_planning.py` claims the harness's own tree end to end. A `smokeNoReview`
  experiment (`"stages": {"review": false}`) dry-runs and must print `review: false
  rework: true accept: true`, pinning `harness_stage_enabled` against the `// true` bug
  that read an explicit `false` as true.
- **The failed-implementer program.** A first implementer that exits 1 (or exits 0 with no
  PR) is `method_failed` with its `failure_reason`, skips review, rework and accept, and is
  still captured; the dependent second feature still runs, cut at whatever the first
  branch holds, and the program row records the first as not green.
- **`--only` and `--from record`.** `--only <program>[:orchestrator[:<arm>][:<n>]]` selects
  the program cell and nothing else; `--from record` re-enters a finished program cell off
  its state files and appends a row without calling the orchestrator again.
- **The floor refusal.** `new-experiment.sh --programs` refuses an arm whose pinned
  agentTooling lacks `orchestration-start.sh` or `templates/plans/ORCHESTRATOR_BRIEF.md`,
  naming the arm and the file; so does the program's setup stage.
- **The lib and cost unit checks.** `harness_program_check` (with `CONSUMER_ROOT` the smoke
  repo) on a program that breaks each rule (first feature dependent, duplicated fixture,
  base not 40-hex, a fixture on another repository, a program on another repository,
  reserved method), `harness_check_program_floor`, `harness_new_session_id` and
  `harness_fill_template`'s `@@PREV_OUTCOME@@` handling; and `program_cost.py` over a
  fabricated transcript (the figure, the `<id>@<from-ts>` form, an unknown id priced at 0
  with a warning).

Between the program's full run and its failing-implementer section sit two sections on
experiment directories of their own, both pinned to this checkout:

- **An ordinary cell, priced end to end** (`smokePricedCell`, method `direct`, run under
  the priced HOME with `SMOKE_PRICED_TRANSCRIPTS=1`). The row must carry `cost_method_usd`,
  `cost_review_usd` and `cost_rework_usd` all above 0, `cost_green_usd` equal to their sum
  within `ARITHMETIC_TOLERANCE`, `cost_method_reported_usd` equal to what the fake reported,
  no "claude reported" (unpriced) warning, and a capture log with no `cannot claim` /
  `launched_elsewhere` line, and the three reading fields all `0` (the fake implementer's
  transcript holds no tool calls). It fails if `capture_planning.py`'s `claim_roots` stops
  admitting the harness's own `<primary>-<branch>` tree; the ordinary full run above
  asserts only 0s.
- **`stages {review: false}` as a run** (`smokeNoReviewRun`, method `null`). A review that
  is not wanted begins no stage: the state file has no `stages.review` (nor `stages.rework`,
  which needs escalated findings), no `t_review_end`, `review_fixed` or `review_escalated`;
  the row has `cost_review_usd == 0`, `review_escalated == 0`, `review_fixed == 0`,
  `rework_ran == false`; no review prompt is written and the branch holds no review or
  rework manifest and no findings; setup, method, accept, capture and record still ran. It
  fails if `harness_stage_enabled` goes back to `jq '.stages.x // true'` (checked by
  breaking the helper locally: the dry-run flag check and these all fail).

`scorecard-arms.sh` is separate because smoke's experiment has one arm and one method, so
`scorecard.py`'s two comparison loops never produced a line there. It asserts, over four
rows, the lines `f · a: arm after vs arm before`, `f · b: arm after vs arm before`,
`f · arm before: a vs b` and `f · arm after: a vs b` (the arm pair prints its arms in sorted
order, `after` first), each showing both `to PR-open` and `to green`; the two deltas
within ±15% read `tie inside the band` on both figures and the two outside it name the
dearer side and `outside the band`; and that a fifth row with `arm: ""` adds no line and is
never paired with a pinned row.

`scorecard-programs.sh` asserts, over a ledger of two program rows and two cell rows: the
header's `programs: 2`; the `## Programs` table rows (group to PR-open, overhead, overhead
%, group to green, `PRs open x/n`, `Green x/n`, and the record's figure or `—`); a
`### pr1 · arm <arm> #<n>` table per program cell, with `—` for a feature that depends on
nothing, `✓` for a dependent one whose branch holds the previous tip and `✗` for one whose
does not; the single comparison line `pr1 · orchestrator: arm after vs arm before`, inside
the band on to-PR-open and outside it on to-green, ending in the counts suffix and `(n=1)`;
that program branches never reach the runs table and the program line never reaches a cell
line; the program's and the features' interventions, failures and gate counts; and, with a
second run of arm `before`, the `## Per program cell` means; then, over the two program
rows alone with `features_count`, `features_pr_open`, `features_green` and `overhead_pct`
nulled, that it renders with no `## Runs` section and falls back to counting `features[]`
and to `cost_overhead_usd` / `cost_group_usd`. **The byte-identity check**: the
same experiment with the two cell rows alone must render exactly `scorecard-programs.cells.md`,
the text `scorecard.py` produced before program rows existed (written once from that earlier
`scorecard.py`, and committed — not a run of `origin/main`'s copy, so no network and no
second checkout).

**The ordinary full run asserts capture as a recorded `0`, not as a dollar figure.** Its
sessions are fake and leave no transcript, so `capture_planning.py` prices nothing; what it
proves is that the stage runs and that its number reaches the row. The priced sections
(the program's full run and the priced ordinary cell) fabricate billed transcripts and
assert the figures.
