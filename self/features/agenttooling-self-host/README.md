# agenttooling-self-host

Make `agentTooling/` able to run the delegated-plan workflow **on itself**, and move the
`plan-analytics` feature — which was agentTooling work all along — out of this repo's
`plans/` and into agentTooling where it belongs.

## Goal

`agentTooling/` is vendored into each consuming repo by `git subtree`, and every feature
built *for the harness so far* has been planned and executed out of the host repo's
`plans/features/`. That misfiles the work: `plan-analytics` changed nothing in
`vinylCatalogue` — its entire diff was under `agentTooling/` — yet its manifest, plans,
logs and cost records live in `vinylCatalogue/plans/`, and would have to be re-created by
hand in the next repo that wanted them.

After this feature, agentTooling carries its own plan corpus and its own runner mode:

```
agentTooling/
  self/
    README.md  PROJECT_FACTS.md  gate.sh  gate-report.txt  interactive/
    features/<slug>/{README.md,auto/,verify/,interactive/}
```

```bash
./agentTooling/run-batch.sh --self <slug>       # build + verify agentTooling itself
python3 agentTooling/analysis/report.py --self <slug>
```

Three facts shape the design:

- **The runner is already parameterized; the scripts around it are not.**
  `plan-runner-lib.sh` reads `REPO_DIR` and `FEATURES_DIR` from whichever wrapper
  sourced it, so self-mode is a wrapper-level change. What is *not* parameterized is
  everything that spells the queue path out in prose — the resolver's error messages,
  the verify prompt's `plans/gate-report.txt` line, and eight
  `Path(repo_dir, "plans", "features")` constructions across the three analysis scripts.

- **Self-mode splits one root into two.** Today `REPO_DIR` means both "where artifacts
  are written" and "the cwd sessions ran from". Under `--self` those diverge: artifacts
  go to `agentTooling/`, but planning sessions ran from the enclosing repo, so
  `capture_planning.py` must look for transcripts under the *git toplevel*
  (`~/.claude/projects/-Users-…-vinylCatalogue`) while writing
  `agentTooling/self/features/<slug>/planning.json`. Resolving the session root as the
  nearest ancestor holding `.git` covers both the subtree case and a standalone
  `agentTooling` clone with one rule.

- **Everything in this directory ships to every consuming repo.** That is the whole
  point of the subtree, and it is also why `agentTooling/.gitignore` has to exist
  *before* anything moves: the host repo's `plans/**/*.stream.jsonl` pattern does not
  cover `agentTooling/self/features/**`, so moving `plan-analytics` without it would
  commit nine event streams of 0.2–1.5 MB each and push them upstream.

## Batches

**Before starting: commit `plan-analytics`'s outstanding output.** Its batch B results —
`agentTooling/analysis/`, the `usage.json` sidecars across every feature, `report.json`,
`planning.json` — are still uncommitted in the working tree. Landing them on their own
first keeps the two features' diffs separable; folded into this feature's commit they
corrupt exactly the per-feature attribution `plan-analytics` exists to produce, and plan
64 has to start from a clean tree regardless.

**Batch A — `./agentTooling/run-plans.sh agenttooling-self-host`** (59–62), then
`./agentTooling/run-verify.sh agenttooling-self-host` (63), then plan 64 by hand.

These plans run out of *this* repo's queue, not agentTooling's, because the runner cannot
read `agentTooling/self/features/` until plan 59 lands. This is the bootstrap and happens
exactly once; every subsequent agentTooling feature is authored under
`agentTooling/self/features/<slug>/` and run with `--self`.

Prefer the two runners separately over `run-batch.sh`: the batch script would run this
repo's `plans/gate.sh` (pytest, ruff, npm build) between the passes, and nothing in this
feature touches `src/vinylcat/` or `frontend/`.

Plan 64 is last and by hand because it is entirely `git mv`, `git subtree push`, and
smoke tests — no build executor has bash, and the moves must not happen until
`agentTooling/.gitignore` (plan 60) is on disk.

## Plans

| Plan | What it does |
|---|---|
| `59-runner-self-mode-sonnet` | `plan-runner-roots.sh` resolves both modes; the three runners take `--self`; the lib and the verify prompt stop hardcoding `plans/`. |
| `60-self-corpus-scaffold-haiku` | `agentTooling/.gitignore`, `CLAUDE.md`, and the `self/` tree's READMEs and `PROJECT_FACTS.md`. |
| `61-self-gate-sonnet` | `self/gate.sh` — agentTooling's mechanical gate (`bash -n`, `shellcheck` when present, `py_compile`). |
| `62-analysis-self-mode-sonnet` | `analysis/roots.py`; `--self` on all three analysis scripts; the artifact-root / session-root split. |
| `63-verify-sonnet` | Post-build verification. |
| `64-self-host-migrate` | *Interactive.* Commit, `git mv plan-analytics` into `self/features/`, smoke-test both modes, re-capture its cost, subtree push. |

## Deliberately excluded

- **Generating `self/`'s stubs from `templates/`.** `sync-plans.sh` writes the stubs a
  *consuming* repo needs, and every one of them points back up at `../agentTooling/…`.
  From inside agentTooling those relative paths are wrong and the "edit the template, not
  this file" banner is a lie — agentTooling *is* the source. `self/`'s READMEs are
  hand-written and stay that way; plan 60 adds a comment in `sync-plans.sh` saying so, so
  the gap reads as a decision rather than an oversight.

- **A `--self` flag on `sync-plans.sh`.** Same reason. It has nothing to generate.

- **Renumbering the plan sequence per-corpus.** `plan-analytics` keeps `48`–`58` after
  the move, and this feature continues at `59`. The global sequence is referenced from
  commit messages, progress logs and both `PROJECT_FACTS.md` files; a feature directory
  already makes plans addressable without the number being unique-per-tree.

- **Teaching `report.py --all` to span both corpora.** After the move, this repo's
  `report.py --all` loses `plan-analytics` and `report.py --self --all` gains it —
  both views stay reachable from the same checkout, just each scoped to its own corpus
  (5 features here, 2 under `--self`). That is the correct attribution — the feature's
  diff was entirely under `agentTooling/` — and what's excluded is only a *third*,
  merged view spanning both corpora at once. Building that would need a repo path
  argument, which `analysis/README.md` rules out on purpose (one repo's costs must not
  be writable into another's `plans/`).

- **Extracting agentTooling to a standalone clone.** `--self` is written to work from
  either a subtree or a standalone checkout (that is what the git-toplevel session root
  buys), but changing how the user actually works on it is not this feature's business.

- **A `CLAUDE.md` that avoids double-loading `CONVENTIONS.md`.** `agentTooling/CLAUDE.md`
  is required so a `--self` executor — whose cwd is `agentTooling/`, not the repo root —
  gets the conventions at all. In a consuming repo that means the file is loaded twice
  when someone edits inside `agentTooling/`, once via the root `CLAUDE.md`'s
  `@agentTooling/CONVENTIONS.md` import. Duplicated guidance is a smaller cost than a
  self-mode executor with none, and the alternatives (a conditional import, a
  sync-managed file) are machinery for a cosmetic problem.

## Machine-readable

```json
{
  "slug": "agenttooling-self-host",
  "branches": ["browseImages"],
  "session_window": { "from": "2026-07-30T19:03:00", "to": null },
  "plans": [
    "59-runner-self-mode-sonnet",
    "60-self-corpus-scaffold-haiku",
    "61-self-gate-sonnet",
    "62-analysis-self-mode-sonnet",
    "63-verify-sonnet"
  ],
  "exclude_sessions": []
}
```
