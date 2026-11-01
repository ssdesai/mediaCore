# 01 — review: orchestration-records

Review the diff against the spec below — never against the builder's account of it — and
say "no findings" when there are none: that is a legitimate verdict (AGENT_PLANS.md →
"Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/orchestration-records/README.md`: its opening
paragraph and its "Deliberately excluded" list. In short:

1. `orchestration-start.sh <slug>` writes `self/orchestrations/<slug>/README.md` (prose +
   JSON fence `{slug, session, agent_tooling, session_window{from,to}, features[]}`), refuses
   a bad slug, an existing folder and a run with no session id; the prose says the
   orchestrator commits nothing but its record, pushed as a records-only PR.
2. `analysis/manifest.py --orchestration <slug>` has `get`, `add-feature` (replacing the
   same repo+slug), `set-feature`, `set-window-to <instant|now>`; the existing subcommands
   are untouched (in particular `init … --orchestration <slug>` is a feature-manifest flag,
   not the scope).
3. `orchestration-capture.sh <slug>` prices the record's session across every project
   directory (the latest-instant file), inside the window (`to` null = now), subagents
   included, into `planning.json`, through one function in `capture_planning.py` — no second
   pricing path.
4. A feature manifest fence has the optional `orchestration` key; `feature-start.sh
   --orchestration <slug>` writes it in both profiles, checking only the slug shape;
   `manifest.py get orchestration` reads it; the template documents it as optional.
5. `report.py --orchestration <slug>` writes `report.md` and `report.json`: header, a row per
   feature (total from its `report.json`, else `unpriced` with one of three reasons), the
   overhead line, the group total = priced features + overhead, overhead %, and the count of
   unpriced features stated as not in the total; the arithmetic is one function returning a
   dict.
6. Docs: `analysis/README.md`, `self/README.md`, `self/orchestrations/README.md`, root
   `README.md`, `self/tests/README.md`, and ONE paragraph appended at the very end of
   `LIFECYCLE.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it (`self/tests/
  orchestration-records.sh`), and the gate (`self/gate.sh`) is green on this tree: its
  report says so, and the review does not re-run it. The new scripts and test are in the
  gate's syntax-check list and the test is `record`ed.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); README Rule 1 field lists exist for the record fence,
  the orchestration `planning.json` and `report.json`.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name; bash 3.2
  compatible, no `set -e`.
- `routing.py`'s `START_VALUE_FLAGS` knows `--orchestration`, so a start command carrying it
  still yields the feature's slug.
- NOTES.md's claims hold.

## Verdict
