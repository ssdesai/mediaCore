Verdict: clean

# Review — consumer-record-guard, round 2

## What the batch was supposed to do

When agentTooling is vendored into a consuming repo, no orchestration-record tool may write
under the vendored `agentTooling/self/orchestrations/`, `--self` included. Each tool must
refuse before writing anything, with one shared text naming `plans/orchestrations/<slug>/`.
The tools are `orchestration-start.sh` (both kinds), the three writing subcommands of
`manifest.py --orchestration`, `orchestration-capture.sh` / `orchestration_capture.py`, and
`report.py --orchestration`. Three things must not change: reads of a shipped record, `--self`
in agentTooling's own checkout, and a consumer's runs without `--self`. Round 2 also had to fix
the two round-1 escalations: the advisory's wording and the missing C3 assertion.

## Does it?

Yes.

- **One classifier.** `roots.self_record_write_allowed()` returns `is_standalone_checkout()`.
  `record_write_refusal`, `coordinator_check.py` and the new `roots.py self-write <slug>`
  command all ask it. The shell start calls that command, so no second `.git` probe or path
  comparison was added. `--arm-root` cannot make a standalone checkout look vendored, because
  `apply_arm_root` rejects it together with `--self`.
- **Refusal before any write.**
  - Every writer checks `record_write_refusal` before its first write.
  - The start checks right after slug validation, before the session checks, the `mkdir`
    and the ledger append.
  - A refusal exits 1 and prints `VENDORED_SELF_WRITE_REFUSAL`.
  - The start treats any exit other than 0 as a refusal, so it fails closed.
  - `consumer-record-guard.sh` C1/C2 compare checksum snapshots of both record roots and the
    ledger.
- **Reads still work.** `manifest.py … get` keeps `write=False` and so calls `record_refusal`
  alone. C3 asserts the role hook still reads a shipped record. It also asserts the advisory
  counts that record as naming its session, with a control session that no record names
  (round-1 finding 2).
- **Advisory wording.** `flag = SELF_FLAG_WORDING if self_mode and self_record_write_allowed()`.
  R9 now runs the advisory three ways: standalone `--self` names the flag; vendored `--self`
  names no flag and contains no `--self`; plain names no flag (round-1 finding 1).
- **Standalone unchanged.** The `--self` assertions dropped from R1/R2 moved to R7, against the
  standalone checkout. C5 runs every writer there.
- **Fixtures.** `orchestrator-role.sh` G10 copies `analysis/roots.py`. The copy rule is written
  down in `self/PROJECT_FACTS.md` and `self/tests/README.md`.
- **Docs.** These all state the refusal and agree with the code: `LIFECYCLE.md`,
  `analysis/README.md`, the root `README.md`, `self/README.md`, `self/orchestrations/README.md`,
  `self/tests/README.md` and `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`.
- **Gate.** `self/gate-report.txt` ends with "all checks passed".
  - Its one non-zero line is the advisory "pricing rate history is current" check. That is
    about the date and not about this feature.
  - Nothing is listed as SKIPPED.

## Fixed in this pass

- **Untested contract: the start fails closed.** The plan states that the shell start refuses
  when `roots.py` cannot be asked. The code does this (`orchestration-start.sh:168-174`), but no
  test asserted it.
  - I added a C6 check to `self/tests/consumer-record-guard.sh`. It moves the standalone copy's
    `analysis/roots.py` aside, then runs `orchestration-start.sh --self closed`.
  - The check expects exit 1, output containing "cannot ask", no record folder, and an
    unchanged checksum snapshot of `self/` and the ledger.
  - The check can actually fail: with `roots.py` in place, the same start in that checkout is
    allowed and would write the record.
  - The test's header comment and its entry in `self/tests/README.md` now say so.
  - I ran the test file once to confirm the new check passes. All checks passed.

## Escalated to the next round

None.
