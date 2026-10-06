# 01 — review: ledger-and-routing

Written before the build, from the manifest (`self/features/ledger-and-routing/README.md`)
and the design (`self/DESIGN-2026-09-18-ledger-and-routing.md`), never from the
implementers' reports. "No findings" is a legitimate verdict. Fix local drift in this
pass; anything structural is an escalation, and an escalated report is round 2's brief.
Begin your report with the `Verdict:` line the prompt asks for.

## What the feature was supposed to do

Four ledger defects closed by two implementers on non-overlapping files. The base is
`main`; the diff to read is `git diff main...HEAD`.

1. **The routing record per feature** (A1, §1). `feature-start.sh` writes
   `<features>/<slug>/routing.json` through `routing.py --session --slug`, inside the
   directory the start commit adds. `routers_of(features_dir, slug)` reads that one file;
   `load_records(features_dir)` globs `*/routing.json` and keeps one record per
   `session_id`, the latest `captured_at`. `feature-capture.sh --refresh-for <slug>`
   rewrites only its own slug's file. `routing.py [--self] --migrate` moves legacy
   `<corpus>/routing/<id>.json` records into every slug their `features_started` name and
   deletes the legacy file, idempotently; `sync-plans.sh` runs it after a pull;
   `self/routing/` is migrated away in this feature. The stray reader lists
   `routing.json` in `COST_FILES` and has no `ROUTING_*` labels.
2. **The open co-claimant** (A2, §2). In `build_claimant_index` a co-claimant with
   `to: null` is bounded provisionally by `last_branch_instant` — the function its own
   close will call; no evidence → empty window → dropped with a warning naming it open.
   `share_basis[]` entries carry `open: true` and `provisional_to`; `planning.json` has
   top-level `open_claimants[]`; `annotate_corpus` warns naming the record and
   `--recapture` when the stamped `to` differs from the recorded `provisional_to`.
3. **The zero-cost pin** (A2, §3). Every `subagents[]` entry reaches the ledger with its
   `cost_usd`, 0 when unpriced; `--list-subagents --unclaimed` omits it.
4. **The head's remedy** (A2, §4). `manifest.py [--self] <slug> set-window-from <instant>
   --session <id>` echoes old→new, refuses an instant before the session's first
   instant, refuses moving `from` later, and says a `--recapture` is needed on a captured
   feature. The unclaimed-head warning names the command with the session id and the
   head's first instant, not "by hand".

Not in this feature: a merge driver; one shared routing file; bounding a co-claimant by
anything but its own close's derivation; the budget and `git stash list`; the
per-attempt minutes walk, `slug_of_start_command` and `open-session.sh` quoting (the
`minutes-slug-and-quoting` feature).

## The diff

`git diff main...HEAD --stat`, then the full diff. Expect A1: `analysis/routing.py`,
`feature-start.sh`, `feature-capture.sh`, `plan-runner-roots.sh`, `sync-plans.sh`,
`analysis/report.py` (the routing renderers and import only), `self/routing/*` deleted
and `self/features/*/routing.json` added for the slugs the two legacy records name,
`self/tests/routing-record.sh`, `self/tests/feature-lifecycle.sh`,
`self/tests/verdict-readers.sh`, `self/tests/sync-check.sh` if it listed `routing/`,
root `README.md`, `LIFECYCLE.md`, `self/README.md` (a row for the design doc, the
`routing/` row gone), `self/features/README.md`, `templates/plans/README.md`,
`analysis/README.md`'s `routing.py` entry, `self/tests/README.md`. Expect A2:
`analysis/capture_planning.py`, `analysis/manifest.py`, `self/tests/session-share.sh`,
`self/tests/session-claims.sh` or `claims-ledger.sh` or `subagent-capture.sh`, the
manifest test, `analysis/README.md`'s `capture_planning.py` and `manifest.py` entries,
`self/tests/README.md`. Both: `self/BACKLOG.md` (four entries gone), this feature's
`NOTES.md`/`CHECKPOINT.md`/`timing.jsonl`. Anything else that moved needs a ruling in
`NOTES.md` or is a finding.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **One location, one reader.** `grep -rn "routing/" *.sh analysis/*.py self/tests/*.sh`
  finds no reader of the legacy directory — only `--migrate`'s source path and prose.
  `routers_of` opens `<slug>/routing.json` and nothing else; `load_records` reads
  `*/routing.json` under the features root. The field set of the record is unchanged
  (`captured_at, cost_usd, duration_s, ended_at, features_started[{slug, at}],
  git_branch, launched_in, model, session_id, started_at`) and `analysis/README.md`
  lists it.
- **No path two features share.** `feature-lifecycle.sh` starts two features from one
  router session off the same `main`, closes and merges each in turn, and asserts no
  conflict, two `routing.json` files, and one Routing row for the router naming both
  slugs. If the test starts the second feature after the first merges, it is not testing
  the defect.
- **Latest wins, once.** Two copies of one router with different `captured_at` collapse
  to the later one in `load_records`; the rule is in `routing.py`, not in a renderer, and
  `render_routing_table` shows one row for it.
- **Refresh touches its own file.** `feature-capture.sh --refresh-for <slug>` on a
  corpus holding another feature's `routing.json` for the same router leaves that other
  file byte-identical.
- **Migration is idempotent.** `--migrate` on a legacy record naming two slugs writes
  both, deletes the legacy file, prints two moves; a second run prints nothing and
  changes nothing; a target already holding a later `captured_at` is skipped, not
  overwritten. `self/routing/` does not exist on this branch and the two records it held
  are under `self/features/<slug>/routing.json` for every slug they named.
- **The stray reader.** `plan-runner-roots.sh`: `COST_FILES` contains `routing.json`; no
  `ROUTING_REL`, `ROUTING_DIR_NAME`, `ROUTING_RECORD_SUFFIX`; `stray_paths`' guard names
  the labels that remain and no others. `verdict-readers.sh`'s stray phase passes.
- **The open co-claimant is bounded by its own evidence.** `session-share.sh`: a capture
  while a co-claimant is open records `open_claimants` with that `<repo>/<slug>` and
  `share_basis[]` entries with `open: true` and a `provisional_to`; a second capture after
  that co-claimant's close stamps the same bound reports the same share. The bound comes
  from `last_branch_instant` called with the co-claimant's own features dir — not from
  the capturing feature's, not from the transcript end. A co-claimant with no branch
  session is dropped with a warning that says it is open with no evidence.
- **Drift is announced.** `annotate_corpus` on a frozen record whose `provisional_to`
  differs from the claimant's manifest `to` prints one WARN naming the record and
  `--recapture`; equal bounds print nothing.
- **A pin is a claim.** A manifest pinning a delegate whose transcript has no
  `assistant` line: the capture lists it in `subagents[]`, the ledger names this feature
  for the id with `cost_usd` 0, and `--list-subagents --unclaimed` does not list it.
  The ledger writer iterates `subagents[]`, not the priced subset.
- **`set-window-from`.** Applied and echoed old→new for an instant that covers a
  disclosed head; refused for an instant before the session's first timestamped instant
  (the message says which instant); refused for an instant later than the current `from`
  (the message says narrowing is not this command and names the command that is, or says
  none is); on a captured feature the output says `--recapture`. `manifest.py` imports
  `routing` for the transcript lookup and not `capture_planning`; the notes record the
  direction checked. The unclaimed-head warning text contains `set-window-from`, the
  session id and the head's first instant, and no longer says "by hand".
- **Docs.** `analysis/README.md`: `routing.py` (the per-feature path replaces the
  add/add paragraph; `--migrate`; the latest-wins rule), `capture_planning.py`
  (`open_claimants`, `open`/`provisional_to` on `share_basis`, the ledger-records-claims
  rule), `manifest.py` (`set-window-from` and its three refusals). Root `README.md` rows
  for `feature-start.sh`, `feature-capture.sh`, `sync-plans.sh`. `LIFECYCLE.md` steps 2
  and 5 name the new path. `self/README.md`: `routing/` row gone, design row present.
  `self/features/README.md` lists `routing.json` per feature. `templates/plans/README.md`
  if it listed `routing/`. `self/tests/README.md` for every test touched. This manifest's
  trailer paragraph on `sessions` names `plans/routing/<session-id>.json` — it is
  template text copied by `feature-start.sh`; a fix belongs in the template it is copied
  from (`templates/plans/features/README.md` or wherever `feature-start.sh` reads it),
  and the copy here may follow or be left with a ruling.
- **Style.** Named constants; Python stdlib only; bash 3.2 in the tests; no chained `cd`;
  each slice's commits touch only its own paths per the design's §6 table, shared
  READMEs in their own entries.
- **Exclusions named.** Every deviation from the manifest or design has a ruling in
  `NOTES.md`; the four backlog entries (routing add/add, co-claimant, zero-cost pin,
  head's remedy) are gone from `self/BACKLOG.md` and the six others are still there.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
