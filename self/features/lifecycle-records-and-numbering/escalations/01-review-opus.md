Verdict: escalated

# Review — `lifecycle-records-and-numbering`, round 1

Read as `git diff main...HEAD` (11 commits, 24 files). The gate report at
`self/gate-report.txt` is green and every check it lists ran; nothing below re-runs it.

## What the batch was supposed to do, and whether it does it

| Manifest item | Verdict |
| --- | --- |
| **One numbering rule** (B) — `feature-start.sh` writes `01-review-opus` in both modes, the `SELF_MODE` `find \| sed \| sort -n` gone, `PROJECT_FACTS.md`/`self/features/README.md` reworded, `plan-numbering.sh` asserting `01` | Done. The branch is deleted outright (`NN="01"`); `plan-numbering.sh` now stands up a `--self` checkout *and* a vendored consumer checkout and asserts `01` in four corpus states, including one holding `104-build-sonnet.md`. `feature-lifecycle.sh` keeps the `old` fixture's `07` as the control. This feature's own stub is `01-review-opus`. |
| **One stray reader** (A) — `is_cost_usage_path`, `stray_paths` and their constants in `plan-runner-roots.sh` and nowhere else; admitted siblings as an argument; the close calling it with none | Done. Grep over the three files finds each definition once, in the roots file, and calls elsewhere. `stray_labels <slug> <checkout>` replaces the two hand-derived label blocks, and the capture's `git add` now takes `ROUTING_REL` from the same place the check does. `A2` asserts the strict-before case, `X4` the close's. |
| **The close's round** (A1) — from the review's `plan_end`, count as fallback | Done, with the non-numeric `case` guard keeping `(( ROUND < 1 ))` off a garbage detail. `RC` drives a genuinely capped round-2 review into `review/failed/` and asserts banner and `pr_opened` both say 2 where the count says 1; `RF` strips `round` and asserts the fallback. |
| **Verdict readers, directly** (A2) — new `self/tests/verdict-readers.sh`, wired into `self/gate.sh` | Done. Sixteen assertions, no runner, no git. `report_verdict` now folds and trims the first line *before* matching the prefix — a real behaviour change (`NOTES.md` ruling 4), stated in `RUNNER.md` and the root `README.md`, and failing in the safe direction. |
| **Pre-4 `pr.sh`** (A3) | Done. `X5` builds the fixture from the real template with one line rewritten, asserts the skip names `3` and `4`, one `pr create`, no `pr merge`, records still committed, exit 0. |
| **`report.py` on an uncaptured feature** (B1) | Done. `run_single_feature` checks `planning.json` before `parse_manifest`, prints one line naming the file and `feature-close.sh`, exits 1. `report-rounds.sh` phase 7 asserts the exit, both names, *no* `Traceback`, and no `report.json`. Unreachable from the harness: both of `feature-capture.sh`'s `report.py <slug>` calls run after a `planning.json` exists, and `--all` only visits features that glob one. |
| **Docs and backlog** | Accurate. No sentence anywhere still says the corpus numbers as one sequence, that the close's check is "looser", or that the review opens the PR. All seven backlog entries the manifest names are gone. `AGENT_PLANS.md`'s "passes 99" and "qualify any cross-feature reference with the slug" bullets both exist, so the new cross-references in `plan-runner-roots.sh` and `PROJECT_FACTS.md` resolve. |
| **Exclusions** | Honoured. `hooks/` untouched; every deviation has a ruling in `NOTES.md`, including the `RUNNER.md` edit the manifest marked "if needed". |

## Fixed in this pass

- `self/tests/verdict-readers.sh` — the file set `FEATURES_DIR` *before* sourcing
  `plan-runner-roots.sh`, while its own header and `self/tests/README.md` both describe the
  opposite order. Today the two are equivalent (the roots file assigns its roots only inside
  `resolve_roots`), but if a later edit ever set one at source time the fixture would be
  silently overwritten with this checkout's real corpus — where the slug `verdict-readers`
  holds no review at all, so every assertion would keep passing and assert nothing. Moved the
  `source` and its `declare -f` guard above the fixture, and said why in a comment. The test
  still passes, all 16.
- `plan-runner-roots.sh:128` and `LIFECYCLE.md:173` — two comment/prose lines left unwrapped
  at ~125 columns against the surrounding ~90. Rewrapped; no wording changed.

## Escalated to round 2

One finding.

**`stray_paths` fails open when `stray_labels` has not run** — `plan-runner-roots.sh:290`
(the reader), `feature-capture.sh:137` and `feature-close.sh:162` (the two callers).

Moving the reader out of `feature-capture.sh` introduced an invariant that did not exist
before: the capture used to derive `FEATURE_REL`/`FEATURES_REL`/`ROUTING_REL` unconditionally
at the top of the script, and now the reader depends on four globals a *separate* call sets.
Both current callers do call it — that is not the defect. The defect is what happens if one
ever does not, or calls it after the first `stray_paths`: under `set -uo pipefail`, an unset
`FEATURE_REL` inside `STRAY="$(stray_paths …)"` kills only the command substitution's
subshell. The error goes to stderr, `STRAY` comes back **empty**, and both call sites read
empty as "every dirty path is a cost record". The close then opens the PR over a dirty tree
and the capture commits and pushes it — the exact failure the reader exists to prevent, and
the one the whole slice moved it here to make impossible. A guard is missing on the one path
where the check silently disappears rather than refusing.

Not fixed here because it is a contract decision, not a patch: `stray_paths` returns its
findings on stdout and its callers branch on `-n "$STRAY"`, so "refuse" has to be expressed
either as a sentinel line on stdout or as a new return-code convention both callers learn.
Pick one deliberately.

- *What it should be*: `stray_paths` checks `${FEATURE_REL:-}`, `${FEATURES_REL:-}`,
  `${ROUTING_REL:-}` and `${STRAY_SLUG:-}` before its loop and, if any is unset, emits a
  line naming the programming error on stdout (so the caller's existing `-n` branch refuses
  with it) as well as stderr — rather than letting `set -u` end the subshell quietly.
- *The assertion that would catch it*: a phase in `self/tests/verdict-readers.sh` — which
  already sources the roots file with no runner — that calls
  `stray_paths "?? self/features/x/NOTES.md.tmp" ""` **without** calling `stray_labels`
  first, and asserts the result is non-empty. It fails today, and it is the only assertion
  in the corpus that would notice a caller dropping the `stray_labels` line.

## Files this pass touched

- `self/tests/verdict-readers.sh`
- `plan-runner-roots.sh`
- `LIFECYCLE.md`
- `self/review-report.md`
