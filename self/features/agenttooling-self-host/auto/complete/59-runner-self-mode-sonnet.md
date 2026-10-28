# 59 — Runner self-mode

Feature: `agenttooling-self-host`, plan 1 of 5. Makes `agentTooling/` able to run the
delegated-plan workflow on itself (`--self`), so harness features are planned, executed
and costed inside agentTooling instead of inside whichever repo vendors it.

Teach the three runners a `--self` flag that drains `agentTooling/self/features/<slug>/`
instead of the consuming repo's `plans/features/<slug>/`.

Independent of other plans.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- `plan-runner-lib.sh` is sourced by a wrapper that has already set `REPO_DIR`,
  `FEATURES_DIR`, `QUEUE`, `PLAN_KIND`, `SUMMARY_TITLE`, `CLAUDE_TOOL_ARGS` and
  `build_prompt`. It never derives a path itself. That is why self-mode is a
  wrapper-level change.
- `run_all` does `cd "$REPO_DIR"` before anything else, so every user-facing path in a
  message is read *relative to `REPO_DIR`*. Under `--self` that cwd is `agentTooling/`,
  which is why the messages need a label variable rather than the literal `plans/`.
- Target of `--self`: `agentTooling/self/features/<slug>/{auto,verify,interactive}/`,
  with `self/PROJECT_FACTS.md` and `self/gate.sh` alongside. Plans 60 and 61 create that
  tree; this plan only points at it.
- Scripts here run under bash 3.2 (the system bash on macOS). Expanding a possibly-empty
  array under `set -u` needs the `${a[@]+"${a[@]}"}` form — `plan-runner-lib.sh:269`
  already does this for `CLAUDE_BUDGET_ARGS` and the same applies to the new
  `SELF_FLAG` array in `run-batch.sh`.
- `${BASH_SOURCE[0]}` inside a function resolves to the file the function was *defined*
  in, not the file that called it — so `resolve_roots` can locate `agentTooling/` even
  though every caller sources it from a different script.

## Files

- Create `agentTooling/plan-runner-roots.sh`
- Modify `agentTooling/run-plans.sh`
- Modify `agentTooling/run-verify.sh`
- Modify `agentTooling/run-batch.sh`
- Modify `agentTooling/plan-runner-lib.sh`
- Modify `agentTooling/RUNNER.md`
- Modify `agentTooling/README.md`

## `agentTooling/plan-runner-roots.sh` (create)

```bash
#!/usr/bin/env bash
# Root resolution shared by run-plans.sh, run-verify.sh and run-batch.sh. Sourced
# (never executed) before plan-runner-lib.sh, which needs REPO_DIR and FEATURES_DIR
# already set.
#
# Two modes, differing only in which repo's queue a run drains:
#
#   normal   REPO_DIR = the consuming repo root (this checkout's parent)
#            queue    = plans/features/<slug>/
#   --self   REPO_DIR = this agentTooling checkout
#            queue    = self/features/<slug>/
#
# Self-mode is how agentTooling builds its own features with its own harness. It lives
# here rather than in each wrapper for the same reason plan-runner-lib.sh exists: three
# copies of a two-branch path rule is three chances for the modes to drift apart, and a
# run that resolves the wrong root files its cost records under the wrong repo.

# resolve_roots <first-arg>
#
# Inspects only whether the first argument is --self; the caller does the shift, so
# nothing here mutates the caller's positional parameters.
#
# Sets, for the caller:
#   SELF_MODE          1 when --self was passed, else 0
#   REPO_DIR           the root the runner cd's to, so claude runs from there
#   FEATURES_DIR       absolute path to the per-feature tree
#   FEATURES_LABEL     that same path as a human would type it FROM REPO_DIR — used in
#                      messages, which are all printed after run_all's cd
#   SELF_ARG           "--self " or "", so a message can echo back a command line that
#                      actually reproduces this run
#   GATE_SCRIPT        the mechanical gate run-batch.sh runs between the two passes
#   GATE_REPORT_LABEL  where that gate leaves its report, relative to REPO_DIR
resolve_roots() {
  local first_arg="${1:-}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "$first_arg" == "--self" ]]; then
    SELF_MODE=1
    REPO_DIR="$script_dir"
    FEATURES_DIR="$script_dir/self/features"
    FEATURES_LABEL="self/features"
    SELF_ARG="--self "
    GATE_SCRIPT="$script_dir/self/gate.sh"
    GATE_REPORT_LABEL="self/gate-report.txt"
  else
    SELF_MODE=0
    REPO_DIR="$(cd "$script_dir/.." && pwd)"
    FEATURES_DIR="$REPO_DIR/plans/features"
    FEATURES_LABEL="plans/features"
    SELF_ARG=""
    GATE_SCRIPT="$REPO_DIR/plans/gate.sh"
    GATE_REPORT_LABEL="plans/gate-report.txt"
  fi
}
```

## `agentTooling/run-plans.sh`

Replace the four config lines that currently derive `REPO_DIR` and `FEATURES_DIR`
(`SCRIPT_DIR=…` through `FEATURES_DIR=…`, keeping `QUEUE`/`PLAN_KIND`/`SUMMARY_TITLE`)
with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi
```

`shift` inside an `if` rather than `(( SELF_MODE )) && shift`: this script runs under
`set -uo pipefail` without `set -e`, so the short-circuit form would leave a non-zero
status behind for the next command to be blamed for.

In the header comment, the paragraph beginning "This script lives in the shared
agentTooling checkout" currently states that `REPO_DIR` *is* the consuming repo root.
Rewrite it to say that as the default, and that `--self` as the first argument instead
points the run at agentTooling's own `self/features/` queue — see
`plan-runner-roots.sh`.

## `agentTooling/run-verify.sh`

Same replacement of the `SCRIPT_DIR`/`REPO_DIR`/`FEATURES_DIR` block as `run-plans.sh`
above (the `QUEUE="verify"` / `PLAN_KIND` / `SUMMARY_TITLE` lines stay), and the same
header-comment correction.

In `build_prompt`, process step 3 currently hardcodes the gate report path:

> `3. If plans/gate-report.txt exists, read it.`

The gate report moves with the mode, so interpolate the label instead. The heredoc is
already unquoted (`<<PROMPT`), so `$GATE_REPORT_LABEL` expands:

```
3. If $GATE_REPORT_LABEL exists, read it. Install, format, lint, tests, typecheck and build ALREADY RAN and their output is in that report. Do not re-run them. If it lists failures, triage those first and re-run only the specific check that failed.
```

## `agentTooling/run-batch.sh`

Replace the `SCRIPT_DIR`/`REPO_DIR`/`GATE_SCRIPT` block with root resolution plus a
forwardable flag array:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi

# Forwarded verbatim to both passes so they can never resolve to different roots — the
# same failure the FEATURE_SLUG_OUT handshake below prevents for the feature slug.
# ${a[@]+"${a[@]}"}: expanding an empty array the naive way aborts under `set -u` on
# bash 3.2, still the system bash on macOS.
SELF_FLAG=()
if (( SELF_MODE )); then SELF_FLAG=(--self); fi
```

`GATE_SCRIPT` is now set by `resolve_roots`; delete the line that derived it from
`$REPO_DIR/plans/gate.sh`.

Both pass invocations forward the flag:

```bash
"$SCRIPT_DIR/run-plans.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$@"
```

```bash
"$SCRIPT_DIR/run-verify.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$batch_feature"
```

The `batch_feature="${1:-}"` line still reads the slug correctly — `--self` was shifted
off before it.

The two gate `echo` lines name `plans/gate.sh` literally; change them to use
`$GATE_REPORT_LABEL`'s sibling, i.e. print `${GATE_SCRIPT#$REPO_DIR/}` so a `--self` run
reports `self/gate.sh`. In the header comment, note that the optional first argument may
be `--self`, which selects agentTooling's own queue and its own gate.

## `agentTooling/plan-runner-lib.sh`

Three user-facing strings hardcode `plans/features`, and one hardcodes the retry command
without its mode flag. All four are read *after* `run_all`'s `cd "$REPO_DIR"`, so under
`--self` they currently name a directory that isn't there.

In the "A wrapper sources this file after setting:" header block, add the two new
required variables alongside `REPO_DIR` and `FEATURES_DIR`:

```
#   FEATURES_LABEL   — FEATURES_DIR as typed from REPO_DIR ("plans/features", or
#                      "self/features" under --self); messages print after the cd
#   SELF_ARG         — "--self " or "", so a retry hint reproduces this run's mode
```

Next to the existing `FEATURE_SLUG=""` / `PLAN_DIR=""` declarations, default both so a
wrapper that predates `plan-runner-roots.sh` still runs rather than aborting under
`set -u`:

```bash
FEATURES_LABEL="${FEATURES_LABEL:-plans/features}"
SELF_ARG="${SELF_ARG:-}"
```

Then substitute at the four sites:

- `resolve_feature`'s unknown-slug error — `no such feature: plans/features/$requested`
  becomes `no such feature: $FEATURES_LABEL/$requested`.
- `resolve_feature`'s ambiguity hint — `echo "    $(basename "$0") $slug"` becomes
  `echo "    $(basename "$0") $SELF_ARG$slug"`, so the suggested command reproduces the
  mode as well as the slug.
- `run_all`'s empty-queue message — `under plans/features/*/$QUEUE/incomplete` becomes
  `under $FEATURES_LABEL/*/$QUEUE/incomplete`.
- The `resolve_feature` doc comment's opening line, "Plans live under
  `plans/features/<slug>/…`", gains "— or `self/features/<slug>/…` under `--self`; the
  wrapper decides, this file only reads `FEATURES_DIR`."

## `agentTooling/RUNNER.md`

The opening sentence under the title says the runners operate on "the consuming repo's
`plans/features/<slug>/` directories". Qualify it: that is the default, and `--self`
switches the whole run to agentTooling's own corpus.

Add a `## Self-hosted mode` section after `## Choosing a feature`. It should state:

- What it is for — agentTooling builds its own features with its own harness, so a
  harness change is planned, executed and costed in the repo it belongs to instead of in
  whichever repo happens to vendor it.
- The invocation: `--self` as the **first** argument, before any slug —
  `./agentTooling/run-batch.sh --self <slug>`. `run-batch.sh` forwards it to both passes.
- The table of what moves:

  | | normal | `--self` |
  |---|---|---|
  | `REPO_DIR` (executor cwd) | consuming repo root | `agentTooling/` |
  | feature tree | `plans/features/<slug>/` | `agentTooling/self/features/<slug>/` |
  | gate | `plans/gate.sh` → `plans/gate-report.txt` | `self/gate.sh` → `self/gate-report.txt` |
  | facts | `plans/PROJECT_FACTS.md` | `agentTooling/self/PROJECT_FACTS.md` |

- That everything else — the state folders, resume phases, budget, progress and usage
  sidecars — is identical, because both modes drive the same `plan-runner-lib.sh`.
- That the executor's cwd being `agentTooling/` is why `agentTooling/CLAUDE.md` exists:
  a `--self` executor never sees the consuming repo's root `CLAUDE.md`.
- The one asymmetry worth naming: the analysis scripts take `--self` too, and their
  session root is *not* `REPO_DIR` — planning transcripts are recorded against the git
  toplevel, which is the consuming repo when agentTooling is a subtree. Point at
  `analysis/README.md` rather than restating it.

## `agentTooling/README.md`

In the Contents table, add a row for `plan-runner-roots.sh` between `plan-runner-lib.sh`
and `sync-plans.sh` — resolves normal vs `--self` roots for all three runners; sourced,
not run — and a row for `self/` after `analysis/`: agentTooling's own plan corpus
(features, `PROJECT_FACTS.md`, `gate.sh`), drained by `--self`, pointing at
`self/README.md`.

Under `## Running`, after the three existing commands, add the self-hosted form:

```bash
./agentTooling/run-batch.sh --self <slug>    # build + verify agentTooling itself
```

with one sentence that `--self` goes first, before the optional slug, and a pointer to
`RUNNER.md` → "Self-hosted mode".

Under `## What stays in the consuming repo`, add a sentence distinguishing the two
corpora: everything under the repo's `plans/` is the repo's, everything under
`agentTooling/self/` is the harness's own and ships with the subtree.
