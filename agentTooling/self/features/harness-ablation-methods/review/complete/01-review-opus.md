# 01 — review: harness-ablation-methods

You are reviewing a finished change against its spec, with fresh eyes. Report what is
wrong; "no findings" is a legitimate verdict, and a finding must name the file, the line
and the failing scenario.

## What the feature was supposed to do

Prepare the harness for a tooling-ablation experiment (which layers of agentTooling earn
their cost). Arms form a ladder, each adjacent pair one layer apart:
`vanilla` → `vanilla-conv` → `direct-bare` → `direct` → `plans`.

- **`harness/methods/vanilla-conv/`** (new): a minimal brief — spec, facts, implement, gate
  green, commit, push, open the PR — with no agentTooling doctrine (no CLAUDE.md /
  CONVENTIONS / PROJECT_FACTS / README-rule / named-constant / checkpoint / tests-first
  instructions). The harness-mandated parts stay: `feature:` first line, `@@ISOLATION@@`,
  the PR banner first line and `<tree>/agentTooling/forge.sh pr-open`. Its `run.sh` is
  `direct/run.sh` with the name changed. The tree's CLAUDE.md and `.claude/settings.json`
  load as usual.
- **`harness/methods/vanilla/`** (new): the same brief byte for byte, but the build runs
  without the conventions and the command hook. For the length of the method only, every
  tracked `CLAUDE.md` loses its lines that import `CONVENTIONS.md`, and the tracked
  `.claude/settings.json` loses its `hooks` and `permissions` keys; every other byte stays
  (the project part of root CLAUDE.md is deliberately kept, identical to `vanilla-conv`).
  The neutralized files are skip-worktree so no commit the build makes can carry them; they
  are restored from HEAD when the method exits (trap); and a commit that changed one of them
  anyway fails the method (exit 1). The PR diff must contain only the feature.
- **Drift guard** `self/tests/vanilla-pair.sh`, wired into `self/gate.sh` like
  `direct-bare-pair.sh`: the two templates identical and doctrine-free; `vanilla-conv/run.sh`
  equal to `direct/run.sh` modulo comments and name; `vanilla/run.sh` equal to
  `vanilla-conv/run.sh` once its `# vanilla-only` lines are removed; neutralize / restore /
  verify behaviour on a throwaway repo, including an end-to-end `vanilla/run.sh` with a fake
  `claude` that commits with `git add -A`.
- **Accept at PR-open.** `accept` used to run only after review and rework. The probe now
  also runs on the tree the method handed over (end of the method's PR step, `settle_pr`),
  recorded as `accept_pr_open_pass` / `accept_pr_open_lines` beside `accept_pass` /
  `accept_lines` in the state file and the cell row (null when not measured). Program
  feature rows are unchanged.
- **Scorecard** (`harness/scorecard.py`, coordinator's additions):
  1. cell cost means, spreads and the band comparison lines leave out `method_failed` rows;
     the Per cell table counts them under **Failed** and shows **Spend** — every run's
     to-green cost plus its `cost_lost_usd`, failed runs included — so lost spend is charged
     to its arm;
  2. the Per cell table shows **Mean wall to green** beside the existing wall-clock means;
  3. an `## Acceptance` section: pass counts at PR-open and at green per cell (when rows carry
     the PR-open fields), and a per-check table (`A1…An` parsed from `PASS  A1 …` /
     `FAIL  A3 …` lines), each cell `PR-open → green` when both were measured.
  A ledger with neither new field nor check ids renders as before apart from the Per cell
  table's new columns.
- Docs: `harness/README.md`, `harness/SPEC.md`, `harness/methods/README.md`, both test
  READMEs, `harness/EXPERIMENTS.md`'s method list.

Excluded: running any real experiment; fixtures in consumer repos; program rows'
accept-at-PR-open; changing the review base for pinned arms.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- The method contract (`harness/methods/README.md`): `run.sh <tree> <brief> <slug>`, exit
  0/1/2, model call through `harness_claude` with the tree as cwd (the repo root).
- After `vanilla/run.sh` exits by any path, the tree's neutralized files equal HEAD, no
  skip-worktree bit is left, and nothing of the neutralization is in any commit; a killed
  earlier attempt is restored before a new neutralization.
- `vanilla` and `vanilla-conv` templates differ in nothing; every placeholder fills.
- `accept_pr_open_pass` is `true`/`false`/`null` in the row — a `false` must not be read back
  as `null` (jq's `//` drops `false`).
- Scorecard: the discogsPrefillStructure shape (one failed $0 row in an arm) no longer
  drags that arm's means; `harness/tests/scorecard-programs.cells.md` changes only if an
  ordinary cell's rendering is meant to (it has no repeats, so it should not).
- Every new file is named in its folder's README (`check-readme-index.py`); new tests run in
  `./self/gate.sh`, offline, no model spend; `bash -n` covers `harness/methods/*/*.sh`.
- Named constants for magic values in new code.

## Verdict

State `Verdict: clean` or list the findings.
