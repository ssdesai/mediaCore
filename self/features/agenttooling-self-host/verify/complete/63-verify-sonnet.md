# 63 — Verify: self-hosted mode

Feature: `agenttooling-self-host`, plan 5 of 5. Makes `agentTooling/` able to run the
delegated-plan workflow on itself (`--self`), so harness features are planned, executed
and costed inside agentTooling instead of inside whichever repo vendors it.

Confirm `--self` resolves the right roots in both the shell and the Python layers, that
an ordinary run is unchanged, and that nothing an executor wrote can leak MBs of event
stream upstream.

## Read this first

**The gate report covers none of this batch.** These plans ran out of `vinylCatalogue`'s
queue, so `plans/gate.sh` ran *this repo's* checks — pytest, ruff, the frontend build —
and every file this batch touched is under `agentTooling/`. A green verdict in
`plans/gate-report.txt` says nothing about the work you are verifying. Read it only to
confirm the batch did not break `vinylcat` by accident, then do your own syntax pass
(below). This is the exception to the usual "the mechanical checks already ran" rule,
not a licence to re-run the suite.

There is no test suite in `agentTooling/` and no runner to add one to — see
`agentTooling/self/PROJECT_FACTS.md` → Tests. So unusually, hand-checking is the whole
job here rather than a supplement to reading assertions.

## Do not start a real run

`resolve_feature` exits before phase 1 when given a slug that does not exist, so
`run-plans.sh --self no-such-feature` is safe and is the intended way to exercise the
resolver. **Never invoke a runner without a slug** — it would infer a feature from
whatever happens to be queued anywhere in this repo and start executing plans.

## Checks

**1. Syntax.** `bash -n` every script under `agentTooling/`, including the new
`plan-runner-roots.sh` and `self/gate.sh`, and `python3 -m py_compile
agentTooling/analysis/*.py`. Then run `./agentTooling/self/gate.sh` itself and read its
report at `agentTooling/self/gate-report.txt` — that script is plan 61's deliverable and
this is the only thing that will ever exercise it. If it is not executable, `chmod +x`
it; that is a local fix and interactive plan 64 re-applies it idempotently.

**2. Root resolution, shell.** Source `agentTooling/plan-runner-roots.sh` in a subshell
and call `resolve_roots` with and without `--self`, printing all seven variables it
sets. Confirm the `--self` set points at the agentTooling checkout and `self/…`, the
default set at the repo root and `plans/…`, and that `FEATURES_LABEL` is what a human
would type *after* `run_all`'s `cd "$REPO_DIR"` rather than a repo-root-relative path.

**3. Root resolution, Python.** Import `roots` and print `artifact_root`,
`features_root` and `session_root` for both modes. The one worth thinking about is
`session_root(True)`: in this subtree checkout it must be the `vinylCatalogue` root, not
`agentTooling/`, because that is the cwd planning sessions ran from and therefore what
`~/.claude/projects/` directory names encode. Confirm the corresponding transcript
directory actually exists on disk — a `session_root` that resolves to a path with no
transcript directory is the failure this split exists to prevent, and it fails silently
(an empty capture, not an error).

**4. The two corpora cannot be confused.** `agenttooling-self-host` exists in
`plans/features/` and not in `self/features/`. Confirm `run-plans.sh --self
agenttooling-self-host` errors with a message naming `self/features/…` and listing the
self corpus's features — not that it silently finds the one in `plans/`. Check the
converse too, and check that the ambiguity hint `resolve_feature` prints on a tie echoes
back `--self` when it is in self-mode (read the code path; do not manufacture a tie).

**5. Analysis scripts, both modes.** `report.py --all` and `report.py --self --all`
should both run without traceback, the second over a features root that may not exist
yet — plan 64 has not moved `plan-analytics` in. An absent tree must read as "nothing to
report", never as a crash. Do the same for `backfill_usage.py --self` (it should report
no features directory and return cleanly) and confirm `capture_planning.py --self
some-slug` fails naming a path under `self/features/`.

**6. The gitignore, before anything moves.** This is the check with a consequence that
cannot be undone quietly: `agentTooling/self/features/**/*.stream.jsonl` files are
0.2–1.5 MB each and, once committed, get pushed to the shared subtree remote by plan 64.
Use `git check-ignore -v` on a representative path under
`agentTooling/self/features/<slug>/auto/complete/` to confirm `agentTooling/.gitignore`
matches it and to see which line did the matching. Do the same for `.logfifo`,
`self/gate-report.txt` and `analysis/__pycache__/`. `git check-ignore` works on paths
that do not exist, so do not create files to test this.

**7. Docs match the code.** Spot-check that `agentTooling/README.md`'s contents table
lists `plan-runner-roots.sh` and `self/`, that `RUNNER.md`'s self-hosted section names
the same paths the scripts actually resolve, and that `analysis/README.md` no longer
claims a standalone checkout fails with `FileNotFoundError`. Fix drift in these files
directly; it is exactly the local-edit case.

## Scope

Fix only what is local — a wrong path in a message, a drifted README line, a missing
`chmod`. Anything needing a new function, a changed signature, or a decision about
layout is a build plan for the next batch: report it with the failing command and its
verbatim output. In particular, do **not** move `plan-analytics`, do not run
`git subtree push`, and do not create feature directories under
`agentTooling/self/features/` — those are interactive plan 64's, run by a human with the
tree in front of them.
