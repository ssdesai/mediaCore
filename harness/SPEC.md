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

Lives in the **consuming repo** at `plans/experiments/fixtures/<name>/` (a fixture pins
that repo's own commit, which is a project fact, not tooling; since 2026-11-01 it can pin
no other repository's, §14):

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
  "base": "6b078d2",
  "spec": {"url": "https://github.com/ssdesai/mediaCore", "commit": "edc0c47",
           "path": "INTEGRATION.md", "sections": ["10.6", "10.1", "10.4", "10.5", "12"]},
  "setup": ["python3.13 -m venv .venv",
            ".venv/bin/python -m pip install -q -e \".[dev]\""],
  "gate": {"command": "./plans/gate.sh", "green": "all checks passed", "minutes": 2},
  "branch_stem": "importedWhere",
  "diff_lines": 1753
}
```

- `repo` is optional and normally absent: the fixture's repository is the consumer, never
  resolved or cloned (§14). `repo.remote` alone names another remote of the consumer; a
  `repo.url` / `repo.path` must identify the consumer itself, else the fixture is refused.
  `spec.url`, optional, names an external spec repository, a checkout of which is found or
  cloned on the machine running the fixture (§12 — until 2026-10-30 `repo.url`/`spec.url`
  were `repo.path` and `spec.repo`, absolute paths on one laptop, still read as hints for
  `spec.repo`). The example's `spec.url` is such an external spec (mediaCore's contract).
- `base` is the commit every run branches from, in the consumer. `spec` is a commit in the
  consumer, or in the external spec repo when `spec.url` is set; the harness checks out a
  **detached, read-only worktree** of that repo at that commit
  (`<checkout>-fx-<name>`) and the brief points delegates at it, so a fixture stays valid
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
remains as a development flag, refused unless that root's `agentTooling/` is the running
copy, §14):

```
harness/run.sh <experiment-dir> [--only <fixture>:<method>[:<n>]] [--from <stage>]
               [--only <program>[:orchestrator[:<arm>][:<n>]]]    # §13
               [--dry-run] [--no-cleanup]
harness/scorecard.py <experiment-dir>            # results.jsonl → SCORECARD.md
harness/lib.sh                                    # sourced by run.sh and methods
harness/tests/smoke.sh                            # §7
harness/new-fixture.sh <name> --base … --spec-ref … --spec-path … [--spec-repo …]   # §11, §14
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

1. **setup** — `git -C <repo checkout> fetch -q <remote>` (the consumer's own checkout,
   §14); `git worktree add -b <branch> <repo checkout>-<branch> <base>`; run `fixture.setup` inside; run the
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
   (`forge.sh pr-find`, §12), set `session_window.to`, commit that one edit
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
- Worktree: `<repo checkout>-<branch>`, the consumer's own checkout (§14).

## 5. Templates and file shapes

`methods/<m>/template.md` placeholders, all filled by the harness:
`@@TREE@@`, `@@BRANCH@@`, `@@BASE@@`, `@@SLUG@@`, `@@SPEC_TREE@@` (the spec worktree
path), `@@SPEC_PATH@@`, `@@SPEC_SECTIONS@@`, `@@FACTS@@` (contents of `facts.md`),
`@@GATE_COMMAND@@`, `@@GATE_MINUTES@@`, `@@ISOLATION@@` (the standard isolation
paragraph from `harness/templates/isolation.md`, listing the paths the delegate must
not touch — every sibling worktree of the consumer repo, `plans/experiments/`,
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
effort (HARNESS_EFFORT: low|medium|high|xhigh|max, or null when unset),
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
  `--permission-mode`, `--append-system-prompt`, `--allowedTools`, `--effort <level>`
  (`harness_claude` adds it from `HARNESS_EFFORT`). Copy the invocation
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
- **`pr.sh` is run by `feature-close.sh`, on a clean review verdict** (since
  `close-and-review-rounds`; `run-review.sh` itself opens nothing, and an empty review
  queue leaves no verdict to close on). The close refuses a dirty path outside the
  corpus's own directories, and `pr.sh`'s fallback commit still uses `git add -A` — never
  leave scratch files in a tree before either runs; redirect logs outside the tree or
  into a `.gitignore`d path.
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
  if any exists locally or on the consumer's remote — the same collision `run.sh`
  refuses at setup, caught before the experiment directory exists. `--override
  <fixture>=<stem>` writes `branch_stem_override`. The prediction is a required argument,
  which is where the checklist-first rule now lives for a scripted run.
- `publish.sh` commits only the experiment directory, as `<experiment>: run <n> results`,
  on `<experiment>Results` when the consumer is on its default branch or on the current
  branch otherwise; pushes; opens the PR through `forge.sh pr-open` (`HARNESS_FORGE_BIN`,
  §12) with `SCORECARD.md` as the body. It is the one place the harness *writes* through
  the forge seam; the smoke test's fake `forge.sh` records `pr-open` per branch for it.

None of them changes `run.sh`'s behaviour. `tests/smoke.sh` §7 gained a fourth section
covering all four against the same throwaway repo, which now has a bare remote so the
push and PR paths are exercised.

## 12. Repositories by URL, the forge seam, pinned arms (added 2026-10-30)

Three things kept the harness on one laptop, and the A/B it was built for
(`EXPERIMENTS.md` → "Setting up the arms") by hand. `self/features/harness-cloud-pins/`.

- **Repositories by URL.** `fixture.json` carried `/Users/<owner>/dev/…` paths, so no
  cloud container could run a fixture. A fixture then named `repo.url` and `spec.url`
  (since 2026-11-01 only the external ones still go through this, §14); `lib.sh`'s `harness_resolve_repo` turns a URL into a main checkout on this machine —
  an environment override, the URL as a local checkout, the fixture's old path as a hint,
  a search of `HARNESS_REPO_ROOTS` (default: the consuming repo's parent) by origin
  identity, else a clone into the first root. `new-fixture.sh` writes URLs (a checkout
  argument contributes its origin), `check-fixture.sh` resolves them, and a path-only
  fixture still runs where its path exists, with a warning naming the field to add. A
  dry run names the clone it would make and makes none.
- **The forge seam.** `harness_pr_url` ran `gh pr view` and `publish.sh` ran
  `gh pr create`; both are GraphQL, which a cloud container's proxy refuses. The seam is
  now `forge.sh` (`pr-find`, `pr-open` over `gh api` REST), the vendored copy inside the
  checkout being asked about — forge.sh reads its own checkout's origin — or
  `HARNESS_FORGE_BIN`. `HARNESS_GH_BIN` is gone; the smoke test fakes `forge.sh` instead
  of `gh`. The `direct` brief opens its PR through the same adapter.
- **Arms.** `experiment.json` may carry `agent_tooling: {<label>: <full sha>}`, a third
  cell axis. At setup, on a branch that does not yet carry its pin commit, `harness_pin_agent_tooling` replaces the
  tree's `agentTooling/` with that upstream commit's tree from a checkout of
  `HARNESS_AGENT_TOOLING_URL`, runs the pinned copy's `sync-plans.sh` (its drift report is
  logged, not fatal), and commits `EXPERIMENT ARM (revert before merge): pin agentTooling
  to upstream <sha7>` (an arm equal to the version the base already vendors changes nothing, and its
  pin commit is made `--allow-empty`, so the branch still records its version and the
  re-run guard still finds the subject) — §3 stage 1 gains that step, §4's branch becomes
  `<stem><Method><Arm><n>`, §6's row gains `arm` and `agent_tooling`, and the scorecard
  compares arms within each fixture × method to PR-open and to green. The driver stays one
  version; every stage that runs inside the tree reads the pinned copy, the review and
  rework passes included, which is why the row keeps the method's cost apart.

Pinned facts (verified 2026-10-30, in a cloud container): `gh auth status` fails there
while `gh api` works, as `forge.sh`'s header says; `python3.13`, `uv`, node 22 and the
Playwright browsers under `/opt/pw-browsers` are in the image; the clones sit at
`/home/user/<repo>` in lower case with `https://github.com/<owner>/<repo>` origins, which
the identity comparison folds; `git archive HEAD | tar` of agentTooling is ~9 MB.
`tests/smoke.sh` ran its throwaway repo at the filesystem root on Linux — `mktemp -d -t
<prefix>` is a macOS idiom that GNU mktemp refuses, leaving `WORK` empty — and now uses
an explicit template under `$TMPDIR`.

## 13. Program cells (added 2026-10-30)

`self/features/program-cells/`. The harness compared one feature at a time; the question
"which agentTooling version runs a *set* of features cheaper under an orchestrator" needs a
cell that is a list of features. The row contract and the scorecard were merged first
(`README.md` → "The program row", `tests/scorecard-programs.sh`); this section is the cell
that produces the row.

**Stages**, in `program-stages.sh` (`HARNESS_PROGRAM_STAGES` in `lib.sh`; `HARNESS_STAGES`
is unchanged): `setup brief loop collect review rework accept capture record`.

1. `setup` — the program tree: worktree, arm pin, symlink and version-floor refusals,
   `program.json` `setup[]`, gate rehearsal, `orchestration-start.sh <PSLUG> --session <S>`
   in the pinned copy, commit.
2. `brief` — `claude -p --session-id S` with `templates/program-brief.md`; the reply is `ready`.
3. `loop` — per feature: the feature's worktree (`setup_tree`, i.e. `do_setup` minus its
   manifest skeleton), the orchestrator's `--resume` turn that writes the brief, the
   manifest skeleton, the implementer, the PR check, the manifest window closed, push; then
   `tip`, `dependency_ok`, `feature_done`.
4. `collect` — the last `--resume` turn with `templates/program-collect.md`; `t_method_end`;
   the harness completes the record, commits what is left and pushes the program branch.
5. `review`, `rework`, `accept`, `capture` — per feature through `do_review`, `do_rework`,
   `do_accept`, `do_capture` (`load_program_feature` sets the cell globals they read); the
   capture stage also prices the overhead and reads `record_report`.
6. `record` — the `kind: "program"` row, the scorecard, worktree cleanup.

`--from` accepts the union of the two stage lists. A program cell maps `--from method` to
`loop`; an ordinary cell run with `--from loop` or `--from collect` skips all of its stages.

**Shapes.** `program.json`, the `experiment.json` field `programs`, the state keys and the
row are listed in `README.md` → "File shapes" and "The program row" (the field lists there
are the contract; this section does not repeat them). In brief: `program.json` is `{ name,
repo?{remote?, url?, path?} (the consumer), base (full 40-hex), branch_stem, gate{command, green, minutes}?, setup[]?,
features[{fixture, depends_on_previous, method?}] }` with a hand-written `README.md` beside it,
under `plans/experiments/programs/<name>/`; `experiment.json` gains `programs: [names]` beside
`fixtures`; the state files are `<experiment-dir>/state/<programBranch>.json` and one
`<featureBranch>.json` per feature; the row is appended to `results.jsonl`. Keys this section
adds to the state files: program `orchestrator_first_call_started` (set before the first
`--session-id` call; see rule 4 below); feature `unpriced_reason` (string or `null`, written by
`capture` when the feature has no manifest directory or its captured cost is below 90% of what
`claude` reported for the implementer, naming both figures).

**Naming.** Program branch `P = harness_branch_name <programStem> orchestrator <n> <repeats>
<arm>` (`mediaProgramOrchestratorAfter2`); feature branch `harness_branch_name <fixtureStem>
<programStem> <n> <repeats> <arm>` (`exportStoreMediaProgramAfter2`) — the program stem sits
where a cell's method does. `branch_stem_override[<program>]` replaces the program stem,
`branch_stem_override[<fixture>]` the fixture's. `PSLUG` is `P`'s slug. Briefs are at
`<program tree>/plans/programs/<PSLUG>/briefs/<NN>-<fixture>.md` (`NN` the zero-padded
position), committed on `P`; harness-side figures live only in the state files. The
orchestrator's results are `<logs>/<P>-orchestrator-<kind>[-NN]-result.json`.

**Pinned rulings.** Settled by the repository owner:

1. *A harness-driven orchestrator loop.* One headless session, `--session-id` then
   `--resume` once per feature and once at the end; each implementer a separate top-level
   `claude -p` in its feature's own worktree with the orchestrator's brief as its prompt,
   free to use subagents (`Agent` and `Task` in `--allowedTools` beside `Bash`). A subagent
   cannot spawn subagents and its cost would land inside the orchestrator's transcript.
2. *The harness starts every feature* (worktree, branch, arm pin, `fixture.setup`, gate
   rehearsal, manifest skeleton): an arm's `feature-start.sh` refuses a copy inside a
   worktree. The arms' own start and close scripts are outside the comparison.
3. *Version floor.* An arm whose pinned agentTooling lacks `orchestration-start.sh` or
   `templates/plans/ORCHESTRATOR_BRIEF.md` is refused at `new-experiment.sh` and at setup.
4. *Cost.* A feature's method, review and rework cost come from the per-tree capture
   (`capture_one`); `cost_overhead_usd` is the orchestrator session(s) priced in
   `[t_method_start, t_method_end]` with the **driver's** `price_session_in_window`
   (`program_cost.py`); the arm's `report.py --orchestration` output goes into
   `record_report` as a cross-check, never as the figure.
5. *Dependencies.* A dependent feature's branch is cut at the previous feature's branch tip
   as it stood when that implementer finished (`tip`), its PR targets that branch
   (`pr_base`), and `dependency_ok` is `git merge-base --is-ancestor <previous tip>
   <branch>` — a boolean for a dependent feature, `null` otherwise. It runs after a failed
   predecessor; the row records `method_failed` on the predecessor.
6. *No PR for the program branch;* it is pushed. The record lives in the pinned copy in the
   program worktree — the one exception to "never edit `agentTooling/`".
7. *Review, rework, accept and capture run per feature branch after the loop,* reusing the
   cell stages. A feature is green when `!method_failed` and (the accept stage is off or
   `accept_pass`).
8. *Usage limit.* Exit 2 on the orchestrator: wait once (`harness_wait_for_usage_reset`),
   `--resume` the same session. On an implementer: wait once, run the same brief again.
   `PROGRAM_BUDGET_USD` (unset: none) goes to each orchestrator call as `--max-budget-usd`;
   the orchestrator's model is `HARNESS_MODEL`, and every call of the cell carries
   `--effort $HARNESS_EFFORT` when that is set; the program row records it as `effort`
   (a string, or `null`), beside `model`.
9. *`orchestrator` is a reserved method name:* no `methods/orchestrator/`, a program cell's
   `method` is the literal `"orchestrator"`, and the orchestrator chooses each implementer's
   method unless `program.json` pins it. (The brief counted ten owner rulings; these are the
   nine it listed.)

Further rulings, made while building:

1. Briefs live in the program tree, so the orchestrator (cwd the program tree, `acceptEdits`)
   can write them; they are committed on the program branch.
2. The implementer's method is the last line of the feature turn's reply,
   `METHOD: <direct|plans|hand>`; the harness takes the last such line. A method pinned in
   `program.json` wins and the prompt says so. Absent or invalid: `direct`, an intervention.
3. A feature's manifest skeleton is written after its brief is verified, immediately before
   its implementer starts (the method, in the title, is known by then).
4. Orchestrator session ids: the first call is `--session-id S` (a fresh UUID); each call
   records the `session_id` its result reports; the next `--resume` targets the most recent
   reported id (falling back to `S`); `orchestrator_sessions[]` holds every distinct id in
   order. Each id is priced from its **own first call's start** to `t_method_end`
   (`program_cost.py --session <id>@<from-ts>`), so a resume that forks and replays old
   history under old timestamps is not counted twice. Before the first call the harness
   persists `orchestrator_first_call_started`; on re-entry (`--from brief`) with
   `orchestrator_calls == 0` and the marker set, that call never completed and the real CLI
   would refuse the already-used id, so a fresh id is minted and stored as `session_id`, the
   old one joins `orchestrator_sessions[]` with the marker's instant as its start (a missing
   transcript prices 0), and an intervention names both.
5. A non-zero, non-usage-limit exit on any orchestrator call sets the program
   `method_failed` and is an intervention; the loop still tries every remaining feature (an
   unwritten brief: `brief_written: false`, no implementer, `method_failed: true`, no PR).
   The program's `method_failed` is any orchestrator call failed, any brief unwritten, or
   the collect turn failed.
6. A failed feature (implementer exit 1, or exit 0 with no PR open) skips review, rework and
   accept and is only captured; its `green` is false.
7. Setup refuses a program tree whose `agentTooling` is a symlink.
8. Program stage names are the nine above; `--from method` maps to `loop`.
9. Collect: the harness fills `program-collect.md` with the exact `manifest.py
   --orchestration` commands per feature that has a branch, then `set-window-to now`. After
   the turn it checks the record names every such feature (`manifest.py get features`) and
   that the window is closed (`get session_window.to`), does what is missing itself (each an
   intervention), commits what is left (`<PSLUG>: orchestration record (left over after the
   collect turn)`) and pushes. `t_method_end` is the instant the collect turn ended.
10. `record_report`: in `capture`, best effort and never fatal, the pinned copy's
    `orchestration-capture.sh <PSLUG>` and `analysis/report.py --orchestration <PSLUG>`; the
    `{group_total_usd, overhead_pct, unpriced_count}` of the record's `report.json`, `null`
    when absent; the record files committed on the program branch and pushed.

**Facts pinned from the code.**

- A finished feature (`feature_done`) is skipped on a `--from loop` re-entry (delete its
  state file to redo it); a feature with `brief_written` and its brief on disk reuses the
  brief and does not re-ask the orchestrator.
- If the first (program brief) orchestrator call fails, the loop and collect are skipped;
  capture and record still run, and `t_method_end` is the instant of the failure.
- A feature uses its own fixture's gate unless `program.json` names `gate.command`, which
  then governs the program tree and every feature. The program tree's own gate is
  `program.json`'s or, per field, the first feature's fixture's.
- Fixture `base`s are ignored in a program cell: every non-dependent branch is cut at the
  program's `base`; one warning names the fixtures whose differs.
- The record: `<program tree>/agentTooling/self/orchestrations/<PSLUG>/README.md`, written
  by `orchestration-start.sh` at setup and edited with `manifest.py --orchestration`;
  the row's `orchestration_record` is that path relative to the tree.
- The implementer is run with `--allowedTools Bash Agent Task` and `--model $HARNESS_MODEL`,
  cwd the feature's worktree, prompt the feature's `plans/features/<slug>/BRIEF.md` (a copy
  of the orchestrator's brief). The method name is a label: no `methods/<name>/run.sh` runs.
- Orchestrator calls run in the program tree with `--permission-mode acceptEdits
  --allowedTools Bash`.
- `program_stage_wanted` and `stage_wanted` are separate functions over their own lists.

**Deviations and known limits.**

- *Unverified against a real `claude`:* that `--resume` keeps context headless and whether
  it keeps or forks the session id; that the consumer's hooks inside `-p` accept the
  orchestrator's git commands; that a real `claude` records the tree `<repo>-<Branch>` as
  the implementer's cwd (the smoke test proves `capture_one` claims that cwd through the
  manifest's `branches`); and the tool names `Agent` and `Task`
  (`EXPERIMENTS.md` → "Program cells": rehearse once before trusting numbers), and that the
  real CLI refuses an already-used `--session-id` (the reason a killed first call is
  replaced by a fresh id, rule 4).
- After a killed first orchestrator call the orchestration record, written at setup with the
  first minted id (`orchestration-start.sh --session`), names that old id as its `session`;
  the sessions that actually ran are in the row's `orchestrator_sessions[]`.
- The `METHOD:` choice is a label. `plans` is not run as the `plans` method (no architect,
  no `run-batch.sh` under the harness); a "plans" implementer is whatever the orchestrator
  asked its single session to do.
- Every implementer runs at `HARNESS_MODEL`; the Sonnet-builds / Opus-reviews cost rule is
  in the brief the orchestrator writes, not enforced by the harness.
- A dependent feature's setup runs the gate at its start point. If a failed predecessor
  left that branch red, setup does not die: it logs a warning, records the intervention
  `<feature>: gate red at the previous feature's tip <sha7>; ran anyway`, ends the setup
  stage with outcome `gate-red-ran-anyway` and goes on (the feature is cut at whatever the
  predecessor's branch holds). A non-dependent feature and every ordinary cell still die
  on a red gate (`gate-red`).
- A feature whose worktree was never created is skipped by review, rework, accept and
  capture; its cost is `0`.
- The record is checked and completed only for features that have a local branch.
- Setup commits (pin, brief, record) are on the program branch, never merged; there is no
  PR for it.
- `templates/program-brief.md` names the brief template as `plans/ORCHESTRATOR_BRIEF.md`
  in a parenthesis; the file the harness passes (`@@BRIEF_TEMPLATE@@`) is the pinned
  copy's `templates/plans/ORCHESTRATOR_BRIEF.md`.

## 14. Same repository: an experiment runs from, and lives on, what it measures (added 2026-11-01)

`harness-same-repo`. Settled by the repository owner: **every experiment runs from, and
lives on, the repository it measures; cross-repo experiments are bad behaviour.** Before
it, a fixture named its repository by URL and the harness resolved or cloned whatever repo
that was, so one repository held fixtures, programs and ledgers for another's features, and
a cloud run needed push access to a second repository and a standalone agentTooling clone
as the driver (§12 records that shape; it is history, not the contract).

- **The measured repository is the consumer.** `fixture.json` and `program.json` `repo` are
  optional. Absent, the repository is the consumer (`CONSUMER_ROOT`, remote `origin`);
  `repo.remote` alone may name another remote of the consumer. A `repo.url` / `repo.path`
  present must identify the consumer itself (`owner/repo` compared case-insensitively, `.git`
  dropped, so a cloud proxy URL matches). `repo.url` and `repo.path` are each checked, so a
  fixture still carrying a `repo.path` that is not the consumer is refused even with a
  matching `repo.url`: drop the `repo.path`. Anything else is refused at the first point the
  harness reads the file (`check-fixture.sh`, `new-experiment.sh`, `run.sh` including
  `--dry-run`): this fixture measures `<owner/repo>`; an experiment runs from and lives on
  the repository it measures; move it into that repository's `plans/experiments/` and run
  it there. `harness_program_check` also requires every feature's fixture to be on the
  consumer. The repository is never resolved, searched for or cloned; cells are worktrees
  added from the consumer.
- **The driver is the consumer's own vendored copy.** `run.sh`, `new-experiment.sh`,
  `check-fixture.sh`, `new-fixture.sh` and `publish.sh` refuse when the running harness is
  not `<consumer>/agentTooling/` (physical paths compared): bring that copy up to date there
  (`agentTooling/update.sh`) rather than driving it from another checkout. `--consumer`
  stays a flag for development and is refused on the same test.
- **Two inputs stay outside, read-only.** An arm's pinned agentTooling (`--agent-tooling
  <label>=<ref>`, resolved from `HARNESS_AGENT_TOOLING_URL`) and a spec in another
  repository (`spec.url`, optional; the legacy `spec.repo` path hint likewise). Only these
  still go through `harness_resolve_repo`, its overrides, its search and its clone. Absent
  `spec.url`, the spec worktree is added from the consumer at `spec.commit` (the dry run says
  "from the consumer's own checkout").
- **`new-fixture.sh`** requires `<name> --base --spec-ref --spec-path`; `--repo` is optional
  and must be the consumer; the fixture it writes has no `repo` block (only `repo.remote`
  when `--remote` is not `origin`), and `spec.url` only when `--spec-repo` is given.
- **Cloud.** The runner session's primary repository is the measured repository, already
  carrying an up-to-date vendored agentTooling; nothing else needs push access, and the spec
  repository and agentTooling are attached read-only if the proxy does not serve them
  (`README.md` → "In a Claude Code cloud container").
