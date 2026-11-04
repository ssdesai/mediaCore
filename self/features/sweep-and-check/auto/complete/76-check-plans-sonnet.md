# 76 — check-plans.sh, and run-batch.sh runs it first

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 4 of 8 build plans.

Write `check-plans.sh` to the contract below and make `run-batch.sh` run it before the
build pass. Plan 73's `self/tests/check-plans.sh` asserts every line of the contract.

Depends on: nothing at build time. `sweep-and-check/73` is the test.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- bash 3.2: no associative arrays, no `${var^^}`; a possibly-empty array expands as
  `${a[@]+"${a[@]}"}`. `set -uo pipefail`, deliberately no `set -e` — use
  `if …; then …; fi`, never `cond && cmd`, for anything whose status is not checked.
- `plan-runner-roots.sh` (same directory): `resolve_roots "${1:-}"` sets `SELF_MODE`,
  `REPO_DIR`, `FEATURES_DIR`, `FEATURES_LABEL` (`self/features` or `plans/features`);
  `manifest_field <readme> <key>` prints a scalar, or a JSON array as text, from the
  LAST ```json fence, and nothing when the key is absent. Source it as
  `source "$SCRIPT_DIR/plan-runner-roots.sh"` — mirror `feature-close.sh:60-66`.
- jq is a hard dependency of the runners already; use it for array length and
  membership (`jq -r 'length'`, `jq -r '.[]'`).
- Every magic value is a named constant at the top of the file (`USAGE_RC=2`,
  `FAIL_RC=1`, `MODEL_RE`, `TODO_MARKER="@@TODO@@"`, the queue and state lists).
- `run-batch.sh` line 92 is `stamp_timing batch_start`; `FEATURE_SLUG="${1:-}"` and
  `SELF_FLAG=()` / `SELF_FLAG=(--self)` are set above it.

## Files

- create `check-plans.sh` (executable)
- modify `run-batch.sh`
- modify `README.md` (one Contents row — see below)

## The contract (this block is repeated verbatim in plan 73)

```
usage: check-plans.sh [--self] <slug>            exit 2 on usage (no slug, extra or unknown args)
exit 0 when every check passes, 1 when any check FAILs
one line per check, in this order, exactly:
  ok    <label>
  FAIL  <label>: <detail>
then one last line:  check-plans: <N> checks, <M> failed
D = $FEATURES_DIR/<slug>. Labels are fixed strings:
 1  feature directory exists        D is a directory
 2  manifest present                D/README.md exists
 3  fence parses                    manifest_field D/README.md slug prints something
 4  fence slug matches directory    that value == <slug>
 5  method known                    method absent, or one of plans|direct|hand
 6  branches non-empty              manifest_field branches is a JSON array of length >= 1
 7  window bounds carry a zone      session_window.from and .to, when present and not null,
                                    end in Z or in +HH:MM / -HH:MM
 8  plan filenames well-formed      every *.md directly under D/{auto,verify,review}/{incomplete,
                                    inprogress,complete,failed}/, ignoring *.progress.md, matches
                                    ^[0-9]+-[a-z0-9-]+-(haiku|sonnet|opus)\.md$ — or ^[0-9]+-gate\.md$
                                    under auto/ only; detail lists the offenders (path from D)
 9  plan numbers padded alike       the leading digit runs of every file from 8 have one length
10  no @@TODO@@ stubs queued        no file under any D/*/incomplete/ whose first line starts @@TODO@@
11  every plan file listed in plans[]   every non-sentinel file from 8 has its stem (name minus .md)
                                    in plans[]; detail lists the missing stems
12  every plans[] entry has a file  every stem in plans[] has <stem>.md under some state dir of
                                    auto/, verify/ or review/; detail lists the stems without one
13  every queued plan names the feature   every non-sentinel *.md under any D/*/incomplete/
                                    contains <slug> literally (grep -F); detail lists the files
14  plans method has a queue        method plans (or absent): at least one *.md under D/auto/ in
                                    any state; method direct or hand: ok
A queue or state directory that does not exist is simply empty for 8–14.
```

## `check-plans.sh`

A header comment in the style of `feature-close.sh`'s: what it checks, that
`run-batch.sh` runs it before spending anything, exit codes. Then the constants, then
`resolve_roots`, argument parsing (`--self` first, then exactly one slug), then the
fourteen checks in order through two helpers:

```bash
pass()  { echo "  ok    $1"; checks=$((checks + 1)); }
failc() { echo "  FAIL  $1: $2"; checks=$((checks + 1)); failed=$((failed + 1)); }
```

Checks 1–2 failing do not stop the run: every later check still prints (against an
absent manifest, `manifest_field` prints nothing and 3 fails; 8–14 see empty
directories). Session-window bounds: read `session_window` as JSON with
`manifest_field`, then `jq -r '.from // empty'` and `.to`; a `null` `to` is fine.
Check 7's zone test is one extended regex: `(Z|[+-][0-9]{2}:[0-9]{2})$`. Check 8's
enumeration is a plain nested `for` over the queue and state constants with
`[[ -e "$f" ]] || continue` and `[[ "$f" == *.progress.md ]] && continue`; collect the
relative paths into an array and reuse it for 9, 11 and 13. The last line is printed
from `checks` and `failed`; exit `FAIL_RC` when `failed > 0`.

## `run-batch.sh`

Directly after line 92 (`stamp_timing batch_start`):

```bash
# The lint runs before anything is spent. A malformed corpus — a plan without a model
# suffix, a stem missing from plans[], a review stub still carrying its marker — is
# otherwise found by a runner mid-batch or by a cost report that omits a plan.
if [[ -n "$FEATURE_SLUG" && -x "$SCRIPT_DIR/check-plans.sh" ]]; then
  echo "########## BATCH: check-plans ##########"
  if ! "$SCRIPT_DIR/check-plans.sh" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$FEATURE_SLUG"; then
    echo "########## BATCH: check-plans failed — nothing run; fix the corpus and re-run ##########"
    exit 1
  fi
fi
```

Add one sentence to the header comment's description of the sequence: the lint runs
first and a failure stops the batch before the build pass.

## `README.md`

In the Contents table, in the same group as `run-batch.sh`, add a row for
`check-plans.sh`: "Lints one feature's manifest fence and plan files before a paid run —
fourteen `ok`/`FAIL` checks, exit 1 on any; `run-batch.sh` runs it first." Match the
neighbouring rows' form.
