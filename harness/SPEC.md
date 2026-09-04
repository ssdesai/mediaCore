# Experiment harness — build spec

Build spec for `agentTooling/harness/`: a method-agnostic harness that builds one
feature several ways from a frozen fixture, reviews and reworks every tree the same
way, scores each run, and appends the numbers to a ledger. It replaces the session
that ran the WP7 experiment by hand (`humanNetworkMap/plans/experiments/wp7-bundle-store/`,
`EXPERIMENTS.md` → Round 3), which cost $238 across five features — as much as both
arms it was measuring — and broke isolation twice: it reused one arm's review plan on
the other tree, and it cross-checked the two trees to write each other's rework list.
Both are ruled out here structurally, not by policy.

This file stays in the repo as the design record. Everything below is the contract;
where it pins a fact it was verified on 2026-08-29 in the sessions that ran WP7.

## 1. Nouns

### Fixture — a feature frozen so it can be built again

Lives in the **consuming repo** at `plans/experiments/fixtures/<name>/` (a fixture names
another repo's commit, which is a project fact, not tooling):

```
fixtures/<name>/
  fixture.json        machine-readable, below
  facts.md            toolchain facts and scope boundary handed to every method verbatim
                      (WP7's `spec-common.md`)
  review-brief.md     the scorer's review, written from the spec BEFORE any method runs;
                      the harness runs it on every tree (§3 stage 4)
  accept/             acceptance probe, run against a tree at checklist-green (§3 stage 6)
    accept.py         `accept.py <tree>` → exit 0 pass / 1 fail; prints one line per check
  README.md
```

`fixture.json`:

```json
{
  "name": "importedWhere",
  "repo": {"path": "/Users/sahildesai/dev/vinylCatalogue", "remote": "origin"},
  "base": "6b078d2",
  "spec": {"repo": "/Users/sahildesai/dev/mediaCore", "commit": "edc0c47",
           "path": "INTEGRATION.md", "sections": ["10.6", "10.1", "10.4", "10.5", "12"]},
  "setup": ["python3.13 -m venv .venv",
            ".venv/bin/python -m pip install -q -e \".[dev]\""],
  "gate": {"command": "./plans/gate.sh", "green": "all checks passed", "minutes": 2},
  "branch_stem": "importedWhere",
  "diff_lines": 1753
}
```

- `base` is the commit every run branches from. `spec` is a commit in the spec's repo;
  the harness checks out a **detached, read-only worktree** of that repo at that commit
  (`<repo>-fx-<name>`) and the brief points delegates at it, so a fixture stays valid
  after the spec's branch merges or moves. `sections` are what the brief tells the
  delegate to read.
- `setup` runs inside the fresh worktree before the gate rehearsal. `gate.green` is the
  substring the harness greps the gate's last lines for.
- `branch_stem` + method name + repeat index is the branch (§4).
- `diff_lines` is informational (the recorded size of the feature, for the ledger).

### Method — how a worktree at `base` becomes an open PR

Lives in **agentTooling** at `harness/methods/<name>/`:

```
methods/<name>/
  template.md     delegate brief with placeholders (§5); the harness fills it
  run.sh          `run.sh <tree> <brief> <slug>`; see the contract below
  README.md
```

Contract — the only thing the harness knows about a method:

- **Input:** a worktree on its branch at `base`, gate rehearsed green, venv installed,
  the manifest skeleton at `plans/features/<slug>/README.md` with `session_window.from`
  set, and the generated brief file.
- **Output:** a PR open from the branch to `main` (body's first line: *one arm of an
  experiment — do not merge until it picks a winner*), and the manifest's `plans`
  array populated (or left `[]` for a method with no plans). `run.sh` exits 0 on
  PR-open, 2 on a usage-limit stop (resumable), 1 on a work failure (do not retry).
- **Never:** read any other worktree, read `plans/experiments/`, edit
  `agentTooling/`, or run git/pip/npm outside `<tree>`. The harness passes these rules
  into the brief; `run.sh` does not need to repeat them.
- A method has **no review of its own that the harness relies on** — every tree goes
  through the harness's review stage (§3 stage 4), including `direct`. A method may
  include a self-review in its brief (a method variant), but that is a method choice
  and the harness review still runs after it.

Two methods ship with the harness; both are the WP7 arms, restated:

- `plans` — architect (`claude -p --model opus` with the brief) writes plans, NOTES.md
  and the manifest `plans[]`; `run.sh` asserts `auto/incomplete/`, `verify/incomplete/`,
  `review/incomplete/` non-empty and `NOTES.md` present, then runs
  `./agentTooling/run-batch.sh <slug>` from `<tree>` with output **appended** to
  `plans/batch.log` (`>>` — WP7 lost a run's log to `>`). The batch's own review plan
  and `pr.sh` are part of the method. On a non-zero batch exit: if
  `plans/features/<slug>/escalations/` is non-empty or a plan sits in `failed/`, exit
  1; otherwise re-run the batch once (it resumes from `inprogress/`), then exit 2.
- `direct` — one implementer (`claude -p --model opus` with the brief): builds, runs
  the gate to green, commits, pushes, opens the PR. One shot, no resume. Then the
  harness review (stage 4) — **direct is not "one `claude -p`"; it is one `claude -p`
  plus the same review and rework as every other method.**

Adding a method is a directory. Expected next: `direct-selfreview` (brief adds a
self-review pass against the spec plus the assertion checklist in §8),
`direct-sonnet` (same brief, `--model sonnet`), `spec-opus-build-sonnet`.

### Experiment — which cells to run

Lives in the consuming repo at `plans/experiments/<experiment>/`:

```
<experiment>/
  experiment.json
  results.jsonl       appended by the harness, one row per run (§6)
  SCORECARD.md        rendered from results.jsonl by harness/scorecard.py
  README.md
```

```json
{
  "name": "replayF2Direct",
  "fixtures": ["exportStore"],
  "methods": ["direct"],
  "repeats": 1,
  "stages": {"review": true, "rework": true, "accept": true},
  "noise_band_pct": 15,
  "prediction": "direct reaches PR-open within ±15% of the recorded $14.01 (WP7 F2)",
  "compare_to": "plans/experiments/wp7-bundle-store/SCORECARD.md"
}
```

`prediction` is required and is copied into the scorecard before any run — the
checklist-first rule from `EXPERIMENTS.md`.

## 2. Command surface

All under `agentTooling/harness/`, run from the consuming repo root (they derive the
consumer root as `parents[1]` of the harness dir, like the runners; `--consumer <path>`
overrides for development):

```
harness/run.sh <experiment-dir> [--only <fixture>:<method>[:<n>]] [--from <stage>]
               [--dry-run] [--no-cleanup]
harness/scorecard.py <experiment-dir>            # results.jsonl → SCORECARD.md
harness/lib.sh                                    # sourced by run.sh and methods
harness/tests/smoke.sh                            # §7
harness/new-fixture.sh <name> --repo … --base … --spec-repo … --spec-ref … --spec-path …   # §11
harness/check-fixture.sh <name>                   # §11
harness/new-experiment.sh <name> --fixtures … --methods … --prediction …               # §11
harness/publish.sh <experiment-dir> [--branch …]  # §11
```

`--dry-run` prints every command it would run, with the resolved branch names,
worktree paths and stage list, and runs nothing. `--from <stage>` resumes a run at a
stage (setup | method | review | rework | accept | capture | record) using the state
file (§6). Every `claude` invocation goes through one function `harness_claude` in
`lib.sh` that honours `HARNESS_CLAUDE_BIN` (default `claude`) — the seam the smoke test
uses.

## 3. Stages, per (fixture, method, repeat)

Sequential; each stage's start/end UTC and outcome are written to the state file.

1. **setup** — `git -C <fixture.repo.path> fetch -q <remote>`; `git worktree add -b
   <branch> <fixture.repo.path>-<branch> <base>`; run `fixture.setup` inside; run the
   gate and require `gate.green`; record the test counts the gate prints; add the
   spec worktree (detached, at `spec.commit`) if absent; write the manifest skeleton
   (`slug`, `branches: [<branch>]`, `session_window.from = now`, empty `plans`,
   `subagents`, `exclude_*`). If the gate is red, stop the run: the fixture is broken,
   not the method.
2. **brief** — fill `methods/<m>/template.md` (§5) and write it to
   `<tree>/plans/features/<slug>/BRIEF.md`. Generated from fixture + method only.
3. **method** — `methods/<m>/run.sh <tree> <brief> <slug>`. Exit 2 → wait for the
   usage-limit reset (reuse `stream_shows_usage_limit` / the reset-time parse in
   `plan-runner-lib.sh` — do not write a second detector) and re-invoke once; exit 1 →
   record `method_failed` and skip to capture/record. On exit 0: verify the PR exists
   (`gh pr view --json url`), set `session_window.to`, commit that one edit
   (`<slug>: close the manifest session window at PR-open`), push.
4. **review** — a fresh `claude -p --model opus --max-budget-usd $REVIEW_BUDGET_USD`
   in `<tree>` with `harness/templates/review-preamble.md` + the fixture's
   `review-brief.md`. The preamble says: read the diff against `base`, judge it
   against the spec and the brief, **fix** what is local (a missing assertion, an
   unenforced invariant, a README field list), **escalate** the rest, and write
   `plans/features/<slug>/review/findings.md` in the fixed shape (§5); run the gate;
   commit `review: <fixture>`; push. Its own manifest `<slug>-review` with its window.
   Same brief, same model, same preamble on every tree of the experiment.
5. **rework** — only if `findings.md` has ≥1 escalated item. One `claude -p --model
   opus` with `harness/templates/rework-preamble.md` + the findings file (nothing else:
   no other tree is ever read). Gate to green, one commit `rework: <fixture>`, push.
   Manifest `<slug>-rework`.
6. **accept** — `fixture/accept/accept.py <tree>`; exit code and its lines go in the row.
   Then the gate once more; counts recorded as the checklist-green counts.
7. **capture** — from `<tree>` (its own vendored copy):
   `agentTooling/analysis/capture_planning.py <slug>`, `<slug>-review`, `<slug>-rework`;
   then `analysis/report.py` for each; read the dollars; delete `report.{json,md}`.
8. **record** — append the ledger row (§6); re-render `SCORECARD.md`; unless
   `--no-cleanup`, remove the feature worktree (keep the branch and the PR; the branch
   is the cost record). The spec worktree stays until the experiment ends.

Isolation, enforced by construction: a run's inputs are fixture + method + nothing
else; the review brief exists before any method runs; the rework reads only its own
tree's findings; no stage reads across worktrees. There is no cross-check stage.

## 4. Naming

- Branch: `<branch_stem><Method><n>` in bare camelCase, method capitalised, `n`
  omitted when `repeats` is 1 — `exportStoreDirect`, `exportStorePlans2`. Never a
  `user/` prefix: `capture_planning.py` matches the manifest's `branches` entry
  literally against each session's `gitBranch`, and a mismatch silently reports `$0.00`.
- Slug (manifest dir under `plans/features/`): the branch in kebab-case —
  `export-store-direct`, `export-store-plans-2`; review/rework manifests append
  `-review` / `-rework`.
- Worktree: `<fixture.repo.path>-<branch>`.

## 5. Templates and file shapes

`methods/<m>/template.md` placeholders, all filled by the harness:
`@@TREE@@`, `@@BRANCH@@`, `@@BASE@@`, `@@SLUG@@`, `@@SPEC_TREE@@` (the spec worktree
path), `@@SPEC_PATH@@`, `@@SPEC_SECTIONS@@`, `@@FACTS@@` (contents of `facts.md`),
`@@GATE_COMMAND@@`, `@@GATE_MINUTES@@`, `@@ISOLATION@@` (the standard isolation
paragraph from `harness/templates/isolation.md`, listing the paths the delegate must
not touch — every sibling worktree of the fixture repo, `plans/experiments/`,
`agentTooling/`). The WP7 briefs are the seed: `plans` from
`f5/delegate-plans.md`, `direct` from `f5/delegate-direct.md` (paths in §9),
generalised so nothing feature-specific remains in the template.

`review/findings.md` — the interface between review and rework:

```markdown
# Review findings — <slug>

fixed: <n>      escalated: <n>

## Escalated
- id: R1
  file: src/vinylcat/peers.py
  gap: response body from a peer is read unbounded
  fix: cap at PEER_MAX_BODY_BYTES; test in tests/test_peers.py that a larger body → unknown
- id: R2
  ...

## Fixed
- id: F1
  file: tests/test_peers.py
  gap: InvalidURL branch untested
  commit: <sha>
```

The rework preamble says: fix every item under *Escalated*, nothing else; one commit;
gate green; report per item.

## 6. Ledger row and state

`results.jsonl`, one JSON object per run:

```
experiment, fixture, method, repeat, branch, slug, pr_url,
base, spec_commit, model,
t_setup_start, t_method_start, t_pr_open, t_review_end, t_rework_end, t_green,
cost_method_usd, cost_review_usd, cost_rework_usd, cost_green_usd (sum),
cost_lost_usd (spend from killed attempts' orphaned windows; never in cost_green_usd),
review_fixed, review_escalated, rework_ran,
gate_counts_pr_open, gate_counts_green   (whatever the gate prints, as a string),
accept_pass (bool), accept_lines (list),
method_failed (bool), interventions (list of {t, what}),
harness_version (git sha of agentTooling)
```

State file: `<experiment-dir>/state/<branch>.json`, the same fields filled as stages
complete; `--from` reads it. A finished run's state file stays. `record` prefers the
state file's value for any field a `--from` resume's fresh process never set.
When a stage re-runs over a manifest whose `session_window` is still open — a
killed attempt — the harness closes and prices that window first and banks the
figure in `cost_lost_usd`: real spend the method figures must not absorb. A
closed window is never re-priced. A freeze stamped before its slug's current
manifest window opened is stale — an earlier attempt's — and capture rebuilds it.

`scorecard.py` renders: the prediction; one table row per run with cost to PR-open,
review fixed/escalated, rework cost, cost to green, wall time to PR-open, accept
pass/fail; per (fixture, method) mean and spread when `repeats > 1`; the noise band
applied to each fixture's method pairs.

## 7. Smoke test — `harness/tests/smoke.sh`

Must pass with no network and no money:

- Builds a throwaway git repo under `mktemp -d` with a `plans/gate.sh` that prints
  `all checks passed`, a `plans/pr.sh` that records a fake PR URL in a file instead of
  calling `gh`, `agentTooling/` symlinked to this checkout, and one commit as `base`.
- A fixture `smoke` pointing at it (no `setup`; spec = the same repo, a `SPEC.md`
  committed there), `review-brief.md` of one line, `accept.py` that checks a marker
  file exists.
- A method `null` (`harness/methods/null/`, kept — it is the harness's own test
  double): `run.sh` writes the marker file, commits, "opens" the PR through the fake
  `pr.sh`, exits 0.
- `HARNESS_CLAUDE_BIN` set to a fake `claude` in the test dir that parses `-p`, writes
  a canned `findings.md` (one escalated item) when its prompt contains the review
  preamble's title, touches a rework marker when it contains the rework preamble's
  title, and prints `{"session_id": "smoke-…", "total_cost_usd": 0}`.
- Asserts: state file has every stage; `results.jsonl` has one row with
  `review_escalated == 1`, `rework_ran == true`, `accept_pass == true`; SCORECARD.md
  rendered; worktree removed; branch exists; `--dry-run` on the same experiment runs
  nothing (no worktree created) and prints the branch name.
- `--from rework` re-entry works from the saved state.

`capture_planning.py` against the fake session will price nothing — the smoke asserts
the capture stage runs and records `0`, not a dollar figure.

## 8. Pinned facts (verified 2026-08-29)

- **Cost capture.** `analysis/capture_planning.py <slug>` must run **from the
  worktree** (its session root is `parents[2]` of the script — the cwd the sessions ran
  from; a `claude -p` launched in `~/dev/vinylCatalogue-x` writes its transcript under
  the project dir for that path, not for `~/dev/vinylCatalogue`). The batch's per-plan
  runs are already captured this way. `branches` is matched literally on `gitBranch`;
  `session_window` is UTC ISO; subagents spawned by the Agent tool are pinned by id in
  `subagents` — `claude -p` sessions need no pin. Run `analysis/report.py <slug>` for
  dollars and delete `report.{json,md}` afterwards (they are not committed).
- **`claude -p`** flags present in this install: `-p/--print`, `--model`,
  `--output-format json` (the result object carries `session_id` and
  `total_cost_usd`), `--max-budget-usd`, `--dangerously-skip-permissions`,
  `--permission-mode`, `--append-system-prompt`, `--allowedTools`. Copy the invocation
  pattern from `plan-runner-lib.sh` (how it runs a verify/review plan with Bash
  enabled, the stream handling, `stream_shows_usage_limit`, and the exit-code
  convention `2 = usage limit`). Verify `--resume <session_id>` with `claude --help`
  before relying on it for the plans architect.
- **The gate.** `plans/gate.sh` is repo-owned; vinylCatalogue's runs pytest, ruff,
  vitest, Playwright layout + real on bind-probed ports (~2 min; two worktrees may
  gate at once) and ends with `# VERDICT` / `all checks passed`. No `uv` on this
  machine: vinylCatalogue's gate resolves `<tree>/.venv/bin/python`, hence
  `fixture.setup`. The pytest run rewrites `frontend/test-fixtures/contracts/*.json`;
  a diff there belongs in the commit.
- **`pr.sh` runs even when the review queue is empty** (`run-review.sh` treats an
  empty queue as a clean pass) and commits with `git add -A` — never leave scratch
  files in a tree before it runs; redirect logs outside the tree or into a
  `.gitignore`d path.
- **`run-batch.sh <slug>` resumes** from `inprogress/` on re-run; a tier-3 stop leaves
  `escalations/NN.md`; a failed plan sits in `failed/`.
- **Worktrees:** never branch or run git/pip/npm in a repo's main checkout
  (`~/dev/vinylCatalogue` sits on an old branch; `~/dev/humanNetworkMap` and
  `~/dev/agentTooling` may have live sessions). `git worktree add` is the one
  allowed command against a main checkout.
- **Never test against the hNM production database `humannetworkmap`.** Not relevant
  to the vinylCatalogue fixtures (no DB), relevant to any future hNM fixture.
- **Model prices** come from `analysis/pricing.py`; the harness never hard-codes a rate.

## 9. Fixtures and experiments to create (in the humanNetworkMap worktree)

Source material — session scratchpad, readable, copy what you need into the fixture
dirs (it is not durable):
`/private/tmp/claude-501/-Users-sahildesai-dev-humanNetworkMap/3f2c9afd-9417-463f-b1e1-655f31c56ce0/scratchpad/f5/`
(`spec-common.md`, `delegate-plans.md`, `delegate-direct.md`, `rework-common.md`,
`rework-direct.md`, `rework-plans.md`) and `…/scratchpad/f2/` (same names). The
per-feature acceptance code is `plans/experiments/wp7-bundle-store/score_b.py` at
`origin/wp7F5Bookkeeping` (hNM PR #79, unmerged — take the file from that ref, not
from `main`): its F2 section (B5/B6, `--vinylcat`, `--collection`) and F5 section
(B13: `StubPeer`, `write_scorer_config`, `start_gui`) become
`fixtures/exportStore/accept/accept.py` and `fixtures/importedWhere/accept/accept.py`,
each taking `<tree>` and building its own collection under a temp dir the way
`score_b.py` does. Leave `wp7-bundle-store/` itself untouched — it is the record.

- `fixtures/exportStore/` — F2. `base` = `git -C ~/dev/vinylCatalogue merge-base
  origin/exportStorePlans origin/exportStoreDirect`; spec = mediaCore `INTEGRATION.md`
  §5.1 at tag `v0.2.0`, sections `["5.1", "12"]`; `facts.md` from `f2/spec-common.md`;
  `review-brief.md` written by you **from §5.1 and `f2/rework-common.md`'s contract
  paragraph**, not from either arm's tree — what to check: the sign-off gate before any
  write on every entry point, `--dry-run` refused with `--store`, store bundle
  round-trips, folder wording absent on store exports and vice versa, spec §11 vs
  `Config` agreement, `StoreError` surfaced without a traceback, README field lists.
- `fixtures/importedWhere/` — F5. `base` `6b078d2` (assert it equals the merge-base of
  `origin/importedWherePlans` and `origin/importedWhereDirect`); spec = mediaCore
  `INTEGRATION.md` at `edc0c47` (branch `importedWhere`, PR #10), sections
  `["10.6", "10.1", "10.4", "10.5", "12"]`; `facts.md` from `f5/spec-common.md`;
  `review-brief.md` from §10.6 — three verdicts and the unconfigured case at every
  tier, `InvalidURL`/timeout/non-200/wrong-shape each triggered by a test, bounded
  response body and deadline, nothing written under the collection root, one
  vocabulary shared by route/CLI/pane, URL present in every `unknown` detail, README
  field lists for `RecordImportsOut`/`PeerImportOut`/`Config`.
- `experiments/replayF2Direct/` — the acceptance test for the harness itself:
  `exportStore` × `direct` × 1, all stages, prediction as in §1. **Do not run it** —
  it spends real money (~$15–25) and opens a real PR on vinylCatalogue; the owner runs
  it after reviewing this build. `--dry-run` it and put the output in your report.

## 10. Deliverables and done

In `~/dev/agentTooling-experimentHarness` (branch `experimentHarness`, off `origin/main`;
this file is already there):

- `harness/run.sh`, `harness/lib.sh`, `harness/scorecard.py` (stdlib only, like
  `analysis/`), `harness/templates/{isolation,review-preamble,rework-preamble}.md`,
  `harness/methods/{plans,direct,null}/{template.md,run.sh,README.md}`,
  `harness/tests/smoke.sh`, `harness/README.md` (contents table in the style of the
  root README; the field list of `fixture.json`, `experiment.json` and the ledger row
  per CONVENTIONS Rule 1; the method contract), root `README.md` row for `harness/`,
  `EXPERIMENTS.md` gains a short section pointing at `harness/` as the way to run an
  experiment from now on (do not rewrite the rounds).
- `harness/tests/smoke.sh` passes; `bash -n` on every script; `shellcheck` if
  installed (informational).
- Commit(s) on `experimentHarness`, pushed, PR to `main` titled `Experiment harness`
  whose body says it is unreviewed and names the F2 replay as the acceptance test.

In `~/dev/humanNetworkMap-experimentHarness` (create it: `git -C ~/dev/humanNetworkMap
worktree add -b experimentHarness ~/dev/humanNetworkMap-experimentHarness origin/main`):

- `plans/experiments/fixtures/{exportStore,importedWhere}/`, `plans/experiments/
  replayF2Direct/`, READMEs (`plans/experiments/README.md` gains the two dirs),
  `plans/experiments/fixtures/README.md`. The hNM worktree's vendored `agentTooling/`
  does **not** have `harness/` yet (it arrives by `subtree pull` after the agentTooling
  PR merges) — for the `--dry-run` use `--consumer ~/dev/humanNetworkMap-experimentHarness`
  from the agentTooling worktree.
- Commit, push, PR titled `Experiment fixtures: exportStore, importedWhere; replayF2Direct`,
  body noting it depends on the agentTooling harness PR.

Out of scope: running any paid stage; changing the runners, `capture_planning.py` or
`pricing.py` (if something there blocks you, name it in the report and work around it);
new methods beyond `plans`, `direct`, `null`; touching `plans/experiments/wp7-bundle-store/`.

Report, terse: both PR URLs; smoke output's last lines; the `--dry-run` output for
`replayF2Direct`; every fact above you found untrue and what you did instead; anything
in scope you did not finish and why.

## 11. Scaffolding (added 2026-08-31, after the first paid run)

The first replay (`replayF2Direct`) showed that everything around `run.sh` was still
done by hand: choosing and pinning the commits, writing the fixture skeleton, checking
it before paying, choosing branch names that do not collide with an earlier arm's, and
committing and PR-ing the results. Four scripts take those over; the three files that
carry judgement — `facts.md`, `review-brief.md`, `accept/accept.py` — stay hand-written,
and the scaffolding makes their absence impossible to miss rather than filling them in.

- `new-fixture.sh` resolves `--base` and `--spec-ref` to full commit ids (a ref moves;
  a fixture must not), refuses a ref that does not resolve, a spec path absent at the
  spec commit, or a base without the gate script, warns when the base is on no remote
  branch or a section heading is not found, and writes `fixture.json` plus stubs. The
  stubs carry `@@TODO@@`, which `harness_fill_template` treats as an unfilled placeholder
  — so a run over an unfinished fixture aborts at the brief stage, before any model call.
  The stub `accept.py` exits 1 and names itself.
- `check-fixture.sh` is the gate on a fixture: fields, commits, spec path, gate script,
  the three files present and not stubs, only the four placeholders the harness fills
  (`TREE`, `SPEC_TREE`, `GATE_COMMAND`, `GATE_MINUTES`), `accept.py` compiles. Exit code
  is the failure count. `new-experiment.sh` calls it on every fixture it names.
- `new-experiment.sh` computes every cell's branch with `harness_branch_name` and refuses
  if any exists locally or on the fixture repo's remote — the same collision `run.sh`
  refuses at setup, caught before the experiment directory exists. `--override
  <fixture>=<stem>` writes `branch_stem_override`. The prediction is a required argument,
  which is where the checklist-first rule now lives for a scripted run.
- `publish.sh` commits only the experiment directory, as `<experiment>: run <n> results`,
  on `<experiment>Results` when the consumer is on its default branch or on the current
  branch otherwise; pushes; opens the PR through `HARNESS_GH_BIN` with `SCORECARD.md` as
  the body. It is the one place the harness *writes* through the forge seam; the smoke
  test's fake `gh` records `pr create` per branch for it.

None of them changes `run.sh`'s behaviour. `tests/smoke.sh` §7 gained a fourth section
covering all four against the same throwaway repo, which now has a bare remote so the
push and PR paths are exercised.
