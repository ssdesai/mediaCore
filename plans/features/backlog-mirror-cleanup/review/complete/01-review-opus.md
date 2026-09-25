# 01 — review: backlog-mirror-cleanup

feature: mediaCore/backlog-mirror-cleanup

## What the feature was supposed to do

A by-hand, documentation-only change to `plans/BACKLOG.md`, per
`plans/features/backlog-mirror-cleanup/README.md` → "Decisions": delete the entry
"vinylCatalogue's export does not fill `Release.original_year`", and narrow the entry
"humanNetworkMap, musicMap and vinylCatalogue still pin `mediacore` `v0.3.0`…" to
humanNetworkMap alone, recording that musicMap and vinylCatalogue re-pinned.

## The diff

Base is `main`. `git diff main...HEAD --stat` must show only `plans/BACKLOG.md` and files
under `plans/features/backlog-mirror-cleanup/`. Then the full diff of `plans/BACKLOG.md`.

## Contracts to hold it to

1. **The evidence is real.** Check with `gh pr view 43 --repo ssdesai/musicMap --json state,mergedAt`
   and `gh pr view 158 --repo ssdesai/vinylCatalogue --json state,mergedAt` that both are
   `MERGED`. Check that vinylCatalogue's `main` holds
   `tests/test_acceptance_bundle_original_year.py` (`gh api repos/ssdesai/vinylCatalogue/contents/tests/test_acceptance_bundle_original_year.py --jq .name`)
   and that its `pyproject.toml` on `main` pins `mediacore` at `v0.4.0`
   (`gh api repos/ssdesai/vinylCatalogue/contents/pyproject.toml --jq .content | base64 -d | grep -n mediacore`).
   Likewise musicMap's dependency pin on its `main`.
2. **The remaining entry is truthful and still has a closing assertion** for humanNetworkMap,
   and says who re-pinned and when.
3. **Nothing else changed**: no code, no spec, no other README. `gate.sh` is green.

"No findings" is a legitimate verdict. Fix local defects in place; escalate only what needs a
design decision.

## Verdict

Write `plans/review-report.md` with first line `Verdict: clean` or `Verdict: escalated`, then
the findings.
