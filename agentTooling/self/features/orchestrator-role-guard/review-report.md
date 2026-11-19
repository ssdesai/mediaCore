Verdict: clean

# Review: orchestrator-role-guard

## What the batch was supposed to do

Make the orchestration record the orchestrator's **role**. A session whose id is the
`session` in the fence of a `self/orchestrations/<slug>/README.md` must not build anything:
- `feature-start.sh`, the four runners and `feature-close.sh` refuse before any write.
- The PreToolUse hook denies those commands early, and also denies an `Agent` delegate whose
  prompt opens with `feature: `.
- `orchestration-start.sh` refuses in a checkout that already holds a feature (the reverse
  guard).
- A new generated `ORCHESTRATOR_SESSION_BRIEF.md` template briefs the orchestrator session.
- The doctrine docs say all of this.

## Does it do it

Yes. Checked against each contract in the brief:

- **One reader.** The rule lives once, in `hooks/orchestrator_role.py`: the last ```json
  fence, an exact match on `session`, and an unreadable or unparseable fence or a missing
  folder counts as no record. The CLI always exits 0. The shell reader
  (`orchestrator_record_for_session` / `refuse_orchestrator_session` in
  `plan-runner-roots.sh`) and the hook both call it. NOTES R1/R2 record that the reader sits
  in `plan-runner-roots.sh` rather than a separate `orchestrator-role.sh`, which the plan
  allowed as a ruling.
- **Before anything is written.**
  - `feature-start.sh` refuses right after `ROUTER_SESSION`, so `--session` counts. Nothing
    before that point writes: argument checks, profile check, `layout_init` (reads only).
  - The runners refuse right after `resolve_roots`.
  - `run-batch.sh` refuses before its first `mktemp`.
  - `feature-close.sh` refuses after its argument loop.
  - Test G1–G6 checks that each script writes nothing.
- **Refusal shape.** Matches the scripts' own refusals: `  refused  <reason>` on stderr,
  exit 1, and the reason names the slug, the record and
  `templates/plans/ORCHESTRATOR_BRIEF.md`.
- **Allowed stays allowed.** The capture, `manifest.py --orchestration` and reads are
  unguarded (tests G8 and H3). The hook does its cheap command parse first and looks up the
  record only for a build script.
- **Reverse guard.**
  - Uses `git ls-files`, so only tracked manifests count.
  - Matches on `branches[0]` or on the fence's `sessions`. I checked that `sessions` is a
    list of strings in real manifests, which is what the `jq index` check assumes.
  - Refuses before the record is written (tests V1–V3).
- **Agent matcher.**
  - `HOOK_MATCHERS = ("Bash", "Agent")`, and both entries use the same guarded command.
    `.claude/settings.json` was regenerated.
  - The deny needs the prompt to *start* with `feature: ` and the session to have a record.
    Otherwise the hook prints nothing, never an `allow`.
  - Non-dict payloads are handled quietly (tests H4–H7).
- **Gate.**
  - `self/gate-report.txt` is green with nothing SKIPPED. That covers the readme index,
    settings `--check`, profile confinement and both new tests.
  - Each new test has its `bash -n` line and its `record` line.
  - Both new tests pin the profile and clear `CLAUDE_CODE_REMOTE`.
- **Docs.** `LIFECYCLE.md`, `ORCHESTRATION.md`, `self/PROJECT_FACTS.md`, `hooks/README.md`
  and the template READMEs now describe the guard as enforced. No sentence still says it is
  unenforced.

## Fixed in this pass

1. **`templates/plans/ORCHESTRATOR_SESSION_BRIEF.md` pointed children at a path that doesn't
   exist.** It said to brief each child from `<tooling>/plans/ORCHESTRATOR_BRIEF.md`.
   - In a consuming repo that resolves to `./agentTooling/plans/ORCHESTRATOR_BRIEF.md`, which
     does not exist: `sync-plans.sh` writes the stub at the repo root's
     `plans/ORCHESTRATOR_BRIEF.md`.
   - In agentTooling it resolves to `./plans/…`, which also does not exist.
   - It is now `plans/ORCHESTRATOR_BRIEF.md`, with the existing agentTooling note
     (`templates/plans/ORCHESTRATOR_BRIEF.md`) kept. This is a repo-root path, not an
     agentTooling-root one, so it takes no `<tooling>/` prefix. `LIFECYCLE.md` already names
     it this way.
   - `self/tests/sync-check.sh` passes after the edit.
2. **`README.md`'s `sync-plans.sh` row left out both briefs.** This batch edited the row, but
   its list of generated stubs still omitted `ORCHESTRATOR_BRIEF.md` (an older omission) and
   the new `ORCHESTRATOR_SESSION_BRIEF.md`, while `sync-plans.sh`'s `GENERATED` list includes
   both. Both are added now.
3. **No test held the record path to `analysis/roots.py`.** The module's `ORCHESTRATIONS_REL`
   copies `analysis/roots.py`'s `orchestrations_root` by hand: the module's own comment says
   "the three must move together". The G cases already hold the module and
   `orchestration-start.sh` together, because the real start script writes the record the
   reader finds. Nothing held the module to `roots.py`.
   - Added check **U3** to `self/tests/orchestrator-role.sh`: it compares
     `roots.orchestrations_root()` relative to `AGENT_TOOLING_DIR` with the module's
     constant.
   - Added U3 to the test's header and to its `self/tests/README.md` entry.
   - I ran the test after the change: it prints "all checks passed", and U3 shows as `ok`.

## Escalated to the next round

None.

## Notes for the approver (not defects)

- `self/orchestrations/README.md` gained one paragraph about the role. The brief said nothing
  under `self/orchestrations/` should change, but ruling R9 in `NOTES.md` named this file,
  and no record was touched.
- `wire-settings.py`'s `hook_wired` now checks each matcher separately. A consuming repo
  that wired the hook under a wildcard or combined matcher (`*`, `Bash|Agent`) would get
  separate `Bash` and `Agent` entries added beside it, so the hook would run twice per call.
  Both runs give the same answer, and repos wired by this script use exactly `Bash`.
  Recorded only in case such a repo turns up.
