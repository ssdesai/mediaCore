# 79 — capture: an evidenced zero is not a refusal

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 7 of 8 build plans.

`analysis/capture_planning.py` refuses to write a `$0.00` `planning.json` when no session
and no subagent matched, because a zero reads as "planning was free" when the usual
cause is a wrong branch name. But a feature whose only sessions on its branch are
*excluded* ones — runner sessions, whose cost `usage.json` already holds, or ids the
manifest's `exclude_sessions` names — has been seen on its branch: the name is right,
and the zero is evidenced. Today that feature cannot close. Lift the refusal for exactly
that case and test it.

Independent of other plans.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- Python 3 stdlib only; the analysis scripts import each other bare from their own
  directory. Run nothing; the verify pass runs the tests.
- In `capture_feature` (`analysis/capture_planning.py`, around line 1592) the refusal is
  `if not sessions and not subagents and not force:`. The set
  `excluded_ids_encountered` — every excluded session id the scan actually met on the
  feature's branches, runner sessions and manifest exclusions alike — is already
  computed above it and written as `data["excluded_session_ids"]`. `warnings` is the
  list `data["warnings"]` refers to, so appending to it after `data` is built still
  lands in the file.
- `self/tests/capture-guard.sh` is a bash test over a synthesized corpus; its phases 15
  and 16 (find them with `grep -n 'phase 15\|phase 16'`) build the fixture for the zero
  refusal — a manifest naming a branch, a redirected `$HOME`, a transcript or none — and
  assert `rc=1 file=no`. Phase 17 reuses that fixture builder. How a session becomes a
  runner session: `collect_excluded_session_ids` (line 197) gathers `attempts[].session_id`
  from every `*.usage.json` under the features tree, plus the manifest's
  `exclude_sessions`; either route counts.

## Files

- modify `analysis/capture_planning.py`
- modify `self/tests/capture-guard.sh`
- modify `analysis/README.md`
- modify `self/tests/README.md`

## `analysis/capture_planning.py`

Change the condition to
`if not sessions and not subagents and not excluded_ids_encountered and not force:` and
leave the three-cause message as it is. Directly before the `claims = load_claims()`
line that follows, add the evidenced case:

```python
    if not sessions and not subagents and excluded_ids_encountered:
        note = (
            f"no planning session matched, but {len(excluded_ids_encountered)} excluded "
            f"session(s) on {branches} were met — the branch name is right and the zero is "
            "evidenced; their cost is in usage.json or belongs to the feature that excluded them"
        )
        warnings.append(note)
        print(f"{slug}: {note}; writing planning.json with cost $0.00")
```

Update the docstring or comment above the refusal that describes the three causes so
it names the fourth outcome: excluded sessions met on the branch write the honest zero
without `--force`.

## `self/tests/capture-guard.sh`

Phase 17, after 16, two cases on the phase-15 fixture:

- 17a. the manifest's `exclude_sessions` names the one session that carries the branch
  → capture exits 0, `planning.json` exists, its `sessions` is `[]`, its
  `excluded_session_ids` holds that id, `cost_usd.total` is `0`, and stdout contains
  `evidenced`.
- 17b. the manifest excludes nothing; the feature holds
  `auto/complete/01-x-haiku.usage.json` whose `attempts[0].session_id` is that session's
  id → the same five assertions.
- 17c. a manifest naming a branch no transcript carries still gets `rc=1 file=no`
  (phase 15 unchanged — assert it once more here so the two outcomes sit side by side).

Update the phase list in the file's header comment.

## `analysis/README.md`

Where the zero refusal is described (search for `--force writes the honest zero` or
`REFUSING to write`), add the evidenced case in one sentence: excluded sessions met on
the branch — runner sessions or `exclude_sessions` — prove the branch name and lift the
refusal; the record then carries them in `excluded_session_ids` and a warning saying so.

## `self/tests/README.md`

In the `capture-guard.sh` bullet, add phase 17 to whatever list of phases it keeps.
