# 75 — tests: sweep.sh

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 3 of 8 build plans.

Write `self/tests/sweep.sh`, the black-box test of the cadence script plan 78 writes.
RED until plan 78 lands.

Independent of other plans (78 implements what this asserts).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- Test shape and the transcript synthesizer: read `self/tests/feature-lifecycle.sh:53-140`
  and the `session_line` function it defines (find it with `grep -n 'session_line()'`),
  which writes one transcript line for a session with a given id, cwd, branch, model,
  timestamp and token counts, and `project_dir <cwd>` which maps a cwd to its directory
  under `$FAKE_HOME/.claude/projects/`. Copy both helpers into this test; do not source
  that file.
- Under `--self`, the analysis scripts take the artifact root from their own location
  (`<checkout>/self/features/`) and the session root as the nearest ancestor of that
  location holding `.git` — so the throwaway checkout `$AT_TMP=$TMP/agentTooling` must be
  a git repository (`git init`, one commit) and the synthesized session's `cwd` is
  `$AT_TMP`. `HOME` is redirected to `$FAKE_HOME` for every `sweep.sh` call.
- What to copy into `$AT_TMP`: `sweep.sh`, `plan-runner-roots.sh`, `analysis/*.py`, and
  an empty `self/features/`. The analysis scripts import each other bare from their own
  directory; nothing else is needed.
- A manifest the capture accepts is a README.md whose last ```json fence holds `slug`,
  `plans` (may be `[]`), `branches`, and `session_window` with a `Z` `from` earlier than
  the session's timestamp and `"to": null`.
- bash 3.2; never touch the real checkout; `python3 -B` everywhere so no `__pycache__`
  is left.

## Files

- create `self/tests/sweep.sh`
- modify `self/tests/README.md`

## The contract under test (this block is repeated verbatim in plan 78)

```
sweep.sh [--self]                       anything else: usage on stderr, exit 2
AT = the directory holding sweep.sh; every python call is `python3 -B`, --self forwarded first.
Banners, in this order, each on its own line:
  === sweep: rates ===       python3 -B -c "import sys; sys.path.insert(0, '<AT>/analysis'); import pricing; print(pricing.RATES_VERIFIED, pricing.is_rates_stale())"
                             prints "  rates  verified <RATES_VERIFIED>"; when stale, also
                             "  WARN   rate table is stale; update RATES and RATES_VERIFIED in analysis/pricing.py"; never stops
  === sweep: backfill ===    <AT>/analysis/backfill_usage.py [--self]
  === sweep: recover ===     <AT>/analysis/recover_attempts.py [--self]
  === sweep: capture ===     <AT>/analysis/capture_planning.py [--self] --all
  === sweep: report ===      for each slug with a modified or untracked planning.json or usage.json under
                             $FEATURES_DIR (git -C "$REPO_DIR" status --porcelain -- "$FEATURES_DIR"):
                             <AT>/analysis/report.py [--self] <slug>; then report.py [--self] --all
  === sweep: unclaimed ===   capture_planning.py [--self] --list-subagents --unclaimed --since <D>
                             capture_planning.py [--self] --list-sessions --unclaimed --since <D>
                             D = today minus SWEEP_LOOKBACK_DAYS (7) as YYYY-MM-DD, computed with python3
  === sweep: done ===        "  changed  <N> file(s) under <FEATURES_LABEL> — commit them" or "  changed  nothing"
                             then "  next     propagate: ./agentTooling/update.sh in each consuming repo"
exit 1 when any of backfill, recover, capture or report exited non-zero — every step still
runs and the done banner still prints — else 0.
```

## `self/tests/sweep.sh`

Scaffolding as pinned: `$AT_TMP` a git repo holding the copies, `$FAKE_HOME`, the two
helpers. `sweep() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT_TMP/sweep.sh" "$@" 2>&1 ); }`
capturing output and `rc`. Fixture: feature `feat-a` under `$AT_TMP/self/features/`
with branches `["feat-a"]`, `from` `2026-01-01T00:00:00Z`, `to` null, and one
synthesized session on branch `feat-a` with cwd `$AT_TMP`, timestamp
`2026-06-01T00:00:00.000Z`, some hundreds of output tokens so its cost is non-zero.

Assertions, each a `check` with its number in the label:

1. `sweep.sh --bogus` → rc 2; `sweep.sh --self --bogus` → rc 2.
2. `sweep.sh --self` → rc 0; the seven banners appear in the contract's order (assert
   with one `awk` or a loop over `grep -n` line numbers, strictly increasing);
   `self/features/feat-a/planning.json` exists and its `sessions` array has one entry;
   `self/features/feat-a/report.md` exists; output contains `  rates  verified `,
   a `  changed  ` line that is not `  changed  nothing`, and `  next     propagate`.
3. copy `planning.json` aside; `sweep.sh --self` again → rc 0 and `planning.json` is
   byte-identical (the capture skipped a frozen record).
4. add feature `feat-b` with branches `["nowhere"]` and no transcript → `sweep.sh --self`
   → rc 1; `self/features/feat-b/planning.json` does not exist; the output still ends
   with the done banner's two lines (the refusal did not stop the sweep); `feat-a`'s
   `planning.json` is still byte-identical to the copy.

## `self/tests/README.md`

Add one bullet for `sweep.sh` in the shape of the others: what it stands up (a git
checkout, a redirected `$HOME`, one synthesized transcript), the four assertions, and
that it depends on `analysis/capture_planning.py --all` skipping a captured feature and
exiting non-zero on a refusal.
