# Checkpoint: recovered-duration-lower-bound

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-07T16:39:16Z
gate: all checks passed (63 checks, self/gate-report.txt)

## Slices
- [x] acceptance tests — recover-duration.sh (4 red), claims-ledger.sh (10 red),
      report-footnotes.sh phases 6-7 (6 red), feature-lifecycle.sh C3m/C3n (2 red);
      registered in self/gate.sh and self/tests/README.md
- [x] 1. recover_attempts.py: recovered_duration_s on the attempt + top-level sum
- [x] 2. report.py: time.recovered_duration_plans[], bucket figure, ‡ mark and footnote
- [x] 3. capture_planning.py: --list-subagents --unclaimed --for drops a manifest-pinned
      delegate; feature-close.sh step 3 prints the `pinned` line instead of the advice
- [x] 4. claims ledger gains a sessions section; planning.json also_claimed_by;
      report.py cost.shared_sessions[] and the Cost table footnote
- [x] 5. READMEs (analysis/, self/tests/), gate.sh rows, self/BACKLOG.md

## Learned
- Tests keep off `~/.claude` by exporting `HOME` to a temp dir — every relative does it
  (recover-at-close.sh:111, capture-guard.sh:120). `Path.home()` follows `$HOME`, so the
  ledger and the transcript globs move together. That is the override; no new env var.
- `self/gate.sh` lists every test script twice: once in `shell_scripts` for `bash -n`,
  once as a `record` line. A new test file needs both or it never runs.
- report.py's Time table reads only the LIVE sidecar (`duration_from_usage`); the dollars
  read priors too. Not widened here — see NOTES.md and the new BACKLOG entry.

## Resume
- Nothing to resume: every slice landed and the gate is green. The review pass is next
  (the coordinator runs `run-review.sh`; this build did not push and opened no PR).
- cd /Users/sahildesai/dev/agentTooling-recovered-duration-lower-bound
- bash self/tests/recover-duration.sh; bash self/tests/claims-ledger.sh;
  bash self/tests/report-footnotes.sh; bash self/tests/feature-lifecycle.sh
- ./self/gate.sh   (59 checks green before this feature; 63 after)
