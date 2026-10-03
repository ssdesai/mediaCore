# 58 — Install the analysis tooling (run by hand)

Feature: plan-analytics. The build plans (52–56) can only write file contents — they
have no bash. These are the steps that need a shell, run after the batch and its verify
pass complete.

## 1. Confirm the layout survived the batch

`sync-plans.sh` already ran in plan 51; batch B changes no templates, so there is nothing
to re-sync. What is worth checking is that the batch filed itself where it should have:

```bash
ls plans/features/plan-analytics/auto/complete/     # 52–56 and their sidecars
ls plans/features/plan-analytics/verify/complete/   # 57
find plans -maxdepth 1 -type d                      # no plans/auto, no plans/verify
```

Anything in `plans/auto/` means a runner was invoked before the migration landed, and the
work needs moving by hand before the analysis will see it.

## 2. Make the analysis scripts executable

```bash
chmod +x agentTooling/analysis/*.py
```

**NOT RUN — obsolete (2026-07-31).** No script here has a shebang, and `roots.py` and
`pricing.py` are imported modules that should never carry the bit. Setting it would only
enable `./analysis/report.py`, which the shell hands to `sh` and which fails on the
opening docstring. Every documented invocation — this file, `analysis/README.md`,
`RUNNER.md`, `self/gate.sh` — is `python3 agentTooling/analysis/<name>.py`, and the bare
imports (`from roots import …`) depend on that form putting the script's own directory on
`sys.path`. Left non-executable deliberately.

## 3. Backfill the archived batches

The verify plan already runs this, so it should be a no-op. Confirm coverage rather than
assuming it:

```bash
find plans -name '*.stream.jsonl' | wc -l
find plans -name '*.usage.json' | wc -l
```

The second count should be ≥ the first. If it is lower, some streams weren't picked up —
the recursion under `plans/features/*/{auto,verify}/complete/` is the thing to check, and
a per-feature breakdown (`for d in plans/features/*/; do echo "$d $(find "$d" -name '*.stream.jsonl' | wc -l)"; done`)
will say which feature is short.

**This step has an expiry.** `.stream.jsonl` is gitignored and exists only on this
machine; the five completed features' cost history is unreproducible once those files are
gone. Do this before any cleanup that touches `plans/`.

## 4. Capture planning cost while the transcripts still exist

Do all six features, not just this one — the historical manifests exist precisely so the
trend view has something to compare against:

```bash
for s in core-library-and-gui collection-selection extractor-backends \
         manual-readings-and-browse image-versions-and-copies plan-analytics; do
  python3 agentTooling/analysis/capture_planning.py "$s"
  python3 agentTooling/analysis/report.py "$s"
done
python3 agentTooling/analysis/report.py --all
```

Session transcripts under `~/.claude/projects/` are on a retention clock. At a weekly
cadence this never binds, but the *first* run is catching up on history — so run it now
rather than next week. Expect the oldest features to come back with little or no planning
cost: their transcripts are likely already gone. That is a gap in the data, not a bug, and
the capture should say so rather than reporting `$0.00`.

Read the reports before trusting them. The numbers are new and unvalidated; a roll-up that
looks implausible is more likely a bug in the tooling than a surprise about the work. The
one number to sanity-check by hand is `manual-readings-and-browse` vs
`image-versions-and-copies` — both ran on the `browseImages` branch, and if their planning
costs look near-identical, `session_window` is not being applied and both are claiming the
same sessions.

## 5. Commit, then push the subtree upstream

Everything under `agentTooling/` is shared across repos and must go back to the
subtree remote, or the next repo to pull will not have it:

```bash
git add -A && git commit -m "..."
git subtree push --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main
git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

The pull after the push is not redundant — `subtree push` writes nothing locally, so the
recorded split stays stale and the *next* push fails with a misleading
"tip is behind its remote counterpart". All three subtree commands require a clean
working tree. See `agentTooling/README.md` → Updating.

## 6. The one question this leaves open

Where the code and the data live is now settled: repo-agnostic analysis in the subtree at
`agentTooling/analysis/`, per-feature manifests and reports beside the plans they describe
in `plans/features/<slug>/`.

What is not settled is **cross-repo** aggregation. `report.py --all` compares features
within one repo; once agentTooling is pulled into a second repo there is no view that spans
both, and no obvious place to put one that doesn't couple the subtree to a particular
machine's directory layout. Leave it until there is a second repo with real reports in it —
the answer depends on whether the interesting comparison turns out to be across features or
across repos, and one run of `--all` will not tell you.
