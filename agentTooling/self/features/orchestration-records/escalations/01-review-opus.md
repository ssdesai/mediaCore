Verdict: escalated

# Review: orchestration-records

## What the batch was supposed to do

Add the **orchestration record** (`self/orchestrations/<slug>/README.md`), the record an
orchestrator session keeps of the features it spawned. The batch was to add:

- `orchestration-start.sh`, which writes the record.
- `manifest.py --orchestration <slug>` with `get`, `add-feature`, `set-feature` and
  `set-window-to`.
- `orchestration-capture.sh`, which prices the orchestrator's session across every
  project directory, inside its window, through one new
  `capture_planning.price_session_in_window`.
- An optional `orchestration` key in a feature manifest, written by
  `feature-start.sh --orchestration`.
- `report.py --orchestration`, which writes the group report as `report.md` and
  `report.json`.
- The listed docs.

The spec is the manifest at `self/features/orchestration-records/README.md`.

## Does it do it

Yes. Every behaviour the spec names is in the diff, and nothing it excludes is:

- **Record location.** The record always lives in `self/orchestrations/` and has no
  `--self` split.
- **No feature re-capture.** The group report does not capture the features again; it
  only reads each feature's `report.json`.
- **Existing manifest subcommands unchanged.** The orchestration scope is selected only
  when `--orchestration` is the first word, so `init --orchestration` stays a flag of the
  feature manifest.
- **One pricing path.** The capture prices through the single new function.

Contracts checked:

- **Docs.** The README Rule 1 field lists exist for the record fence, the orchestration
  `planning.json` and the orchestration `report.json`, and they match the code.
- **Report arithmetic.** It all sits in one function that returns a dict:
  - group total = priced features + overhead;
  - unpriced features are counted and stated as not in the total;
  - the three unpriced reasons are as specified.
- **Gate.** The new scripts and the test are in the syntax-check list, the test is
  `record`ed, and the gate report is green with no SKIPs.
- **Shell rules.** No new script uses `set -e`.
- **`routing.py`.** `START_VALUE_FLAGS` includes `--orchestration`.
- **`NOTES.md`.** Its claims hold, including that `--branch` is still missing from
  `START_VALUE_FLAGS`, which it leaves to a sibling feature.

## Fixed in this pass

- `analysis/report.py`, `read_total_usd`: an existing `report.json` that was not valid
  JSON was reported as `report path does not exist: <path>`, which is false. A
  `JSONDecodeError` now returns `no total in <path>`. A missing or unreadable file still
  returns the path-missing reason, so the three documented reasons now mean what they say.
  This is a local change to one `except` clause; no test exercises a malformed file.

## Escalated to the next round

Each item below is a behaviour this batch added that no test asserts. The plan's contract
requires "a test that would fail without it". Both tests are small, cheap to write, and the
gate would run them from then on.

1. **`feature-start.sh --orchestration` is untested end to end** (`NOTES.md` says so
   itself).
   - What is missing: no test fails if the
     `${orchestration_args[@]+"${orchestration_args[@]}"}` pass-through at
     `feature-start.sh` (the `manifest.py … init` call) is deleted, or if the early
     slug-shape refusal (`refuse "--orchestration '…' must match …"`) is.
     `orchestration-records.sh` S4 covers only the `manifest.py init --orchestration` half.
   - What to add: in `self/tests/feature-lifecycle.sh`, which already drives real starts
     against stubs:
     - a start with `--orchestration grp-x` whose committed manifest's
       `manifest.py <slug> get orchestration` prints `grp-x`;
     - a start with `--orchestration Bad/Slug` that exits 1 and creates no branch or
       worktree;
     - a start without the flag whose fence has no `orchestration` key.
2. **`routing.py`'s `START_VALUE_FLAGS` gained `--orchestration` with no assertion.**
   - What is missing: nothing in `self/tests/routing-record.sh`, the only test calling
     `slug_of_start_line` / `slug_of_start_command`, uses the new flag. Removing it from
     the frozenset would leave the gate green, while a start line that puts the flag before
     the slug would record the orchestration slug as the feature.
   - What to add, to `routing-record.sh`:
     - `slug_of_start_line("agentTooling/feature-start.sh --orchestration grp-x feat-y")`
       returns `feat-y`;
     - the ordinary order, `feature-start.sh feat-y --orchestration grp-x`, also returns
       `feat-y`.

## Not escalated, noted for the reader

- `orchestration-start.sh` puts the session id into the JSON fence without escaping it.
  This is harmless for `$CLAUDE_CODE_SESSION_ID`, which is a UUID. A hand-typed
  `--session` containing a `"` would produce an unreadable fence, and `manifest.py
  --orchestration` would then refuse to touch it. That is a loud failure rather than a
  silent one.
- `report` paths resolve against the agentTooling root. A feature built in a consuming
  repository therefore reads `unpriced` unless its path is written relative to that root.
  The record's field list and `self/orchestrations/README.md` document this choice, so it
  is a stated design, not drift.
