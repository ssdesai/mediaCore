# 09 — review: harness-arm-base

## What the feature was supposed to do

Two things, both in the experiment harness (`harness/`).

**Arms that differ by a commit of the measured repository.** Until now an arm could only
vary the vendored agentTooling version (`new-experiment.sh --agent-tooling
before=<ref>,after=<ref>`). The feature adds a second kind: `--base-arms
old=<sha>,new=<sha>` (written to `experiment.json` as `base_arms`), e.g. `new` the tip of a
restructure branch cut from `old`. Each cell's worktree is set up at its arm's commit
instead of the fixture's `base`; everything else is the fixture's — spec pin, facts,
review brief, accept probe, setup, gate — and the method, review and rework run as
before. The scorecard compares the arms pairwise within fixture × method under the
existing `noise_band_pct`, exactly as for agentTooling arms. The commits must resolve in
the repository the experiment runs from and lives on (`harness/EXPERIMENTS.md` → "The
rule"), and are refused otherwise. One experiment varies one thing: `agent_tooling` and
`base_arms` together are refused, as are `base_arms` and `programs` together (a program
pins its own base). The row records the arm's label in `arm`, its commit in `base`, an
empty `agent_tooling`, and the kind in a new `arm_kind` field.

**Reading metrics.** For every ordinary cell, from the transcripts of the method's run:
the distinct files read and the bytes read before the first edit, and the bytes of every
`README.md` read over the method's run. They go in the results row
(`read_files_before_edit`, `read_bytes_before_edit`, `readme_bytes_read`, `null` when not
measured) and into a scorecard table beside the cost figures. Program rows are
deliberately unaffected, and say so.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Read `self/features/harness-arm-base/README.md` for the plan table
and the exclusions, and `escalations/` if it exists.

## Contracts to hold it to

- **agentTooling arms are unchanged.** An experiment with `agent_tooling` resolves, pins,
  names its branches, writes its row and renders its scorecard exactly as before (plus
  `arm_kind: "agent_tooling"`); the pin is still keyed on `ARM_SHA` alone, so a base arm
  can never trigger `harness_pin_agent_tooling` or its dry-run lines. The
  `agent_tooling in <file> must be an object …` message is byte-identical.
  `harness/tests/scorecard-arms.sh`, `scorecard-programs.sh` and
  `scorecard-programs.cells.md` must not have changed.
- **The base override is complete.** Every place `run.sh` uses `BASE` after
  `resolve_cell` — the setup fetch-by-sha, `worktree add`, the pin re-run guard's
  `$BASE..HEAD`, `harness_branch_has_commits`, `HARNESS_BASE` in the templates, the row —
  sees the arm's commit, and a `--from` resume recomputes the same commit. Nothing reads
  the fixture's `base` behind its back.
- **Refusals.** Both arm kinds, base arms with programs, a ref that does not resolve in
  the consumer's checkout, and a sha that neither resolves there nor arrives by one fetch
  from the consumer's `origin` are each refused in `new-experiment.sh`; the first two
  also in `run.sh` on a hand-edited `experiment.json`, before any cell resolves. The
  repository rule is honoured: refs resolve in `CONSUMER_ROOT`, never in another
  checkout.
- **Reading metric definitions** match `reading_metrics.py`'s docstring and
  `harness/README.md`: the project directory matched by exact name (a sibling
  `<tree>2` never read), the window `[t_method_start, t_pr_open]`, subagents included,
  errored reads excluded, UTF-8 bytes, `null` (not 0) with no transcript. Program
  features never run the extractor.
- **README Rule 1.** `harness/README.md`'s ledger-row field list names every field
  `build_ledger_row` writes — compare the jq object to the list field by field — and
  `experiment.json`'s shape names `base_arms`. The program row section says it is not
  affected. `SPEC.md` §6 agrees.
- **Folder READMEs current**: `harness/README.md` Contents lists `reading_metrics.py` and
  both new tests; `harness/tests/README.md` describes them and says five tests;
  `self/gate.sh` records both new tests and compiles `reading_metrics.py`.
- **House rules**: bash 3.2 (no associative arrays, empty arrays expanded
  `${a[@]+"${a[@]}"}`), `set -uo pipefail` without `set -e` and no unchecked `&&`
  short-circuits, every literal a named constant, no model named in any committed file
  other than plan filenames, `scorecard.py` and `reading_metrics.py` stdlib only.

A missing assertion is the most valuable finding: phrase it as the test line that would
catch it. "No findings" is a legitimate verdict; do not manufacture speculative ones.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`; then what the feature was supposed
to do and whether it does it, and two lists — fixed here, escalated to the next round.
