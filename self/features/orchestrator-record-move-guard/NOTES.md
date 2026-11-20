# Notes: orchestrator-record-move-guard

## 1. The start ran with `--no-gate`

The first `feature-start.sh` refused because the gate on `origin/main` (`a130257f`) was not
green. The orchestrator traced the cause: `self/tests/orchestrator-role.sh` unset
`CLAUDE_CODE_SESSION_ID GATE_RESUME CLAUDE_CODE_REMOTE` but not `AGENTTOOLING_PROFILE`. A cloud
feature-start exports that variable (`env-profile.sh`), so the test's sandbox ran as cloud and
21 checks failed. The gate passes standalone. The repro is
`AGENTTOOLING_PROFILE=cloud bash self/tests/orchestrator-role.sh`.

The repository owner approved a `--no-gate` start in this session, so the manifest says
`"gate": "skipped"`. This branch's first commit added the variable to the unset (orchestrator
addendum, owner's go). The sibling `pull-round-cleanups` merged the same fix as #171, with a
regression check. The sync with main took main's version, and the file is now identical to
main's.

## 2. Why the hook runs the classifier as a subprocess

The brief's condition 3 is `roots.is_stranded_record`. After #171 that is
`legacy_record_claim(slug) == CLAIM_STRANDED`. The hook may not import `analysis/`
(`shared_rules.py`'s header; `analysis/roots.py` reaches the hook's rules by path for the same
reason). Re-implementing the claim in `shared_rules.py` would make two classifiers, which is
what the claim exists to prevent, and would clash with the sibling's work on `roots.py`.

So the hook asks the CLI that `orchestration-start.sh` already asks:
`<python> -B -E -s <tooling>/analysis/roots.py stranded <slug>`. The details:
- `<tooling>` is the hook's own real path, the same base #169's checks use.
- The call refuses a missing or symlinked classifier.
- `-E -s` keep `PYTHON*` variables and the user site out of it, and `-B` writes no bytecode.
- `-I` is not used, because it drops the script's own directory from `sys.path`, which
  `roots.py` needs to import `routing`.
- The timeout is `ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS` (15). `roots.py` itself may run
  `git remote get-url` for up to 10 seconds.
- A non-zero exit, a timeout or any exception means no approval. The line then falls through
  to the allowlist denial, the base behaviour before #169.

The subprocess runs only for a line that already has the move's exact shape and passed every
#169 check. `main()` now judges the move first and asks the allowlist only when it is not the
move, so the classifier runs once per call instead of twice.

The README check runs before the subprocess. Condition 1 uses `os.path.islink` and
`os.path.isfile` on `<legacy>/README.md`. #169 already proved that `<legacy>` resolves to
itself, so no component above it is a symlink. Condition 2 is `orchestrator_role.names_role`
on that README with the payload's `session_id`. A missing or non-string id means no approval.

## 3. Differences from the brief

- The brief names `roots.is_stranded_record`. The orchestrator's later message asked that the
  guard be built on #171's `legacy_record_claim`. `roots.py stranded` is exactly
  `legacy_record_claim(slug) == CLAIM_STRANDED`, so an ambiguous record is not approved either.
  H28 has a row for that case.
- The test fixture's vendored copy now carries `analysis/`, so the approved case exercises the
  real classifier. The fixture's `wave` record lists no feature, which is agentTooling's
  shipped shape. H28 therefore checks O18 against it as it stands, then rewrites it with a
  consumer feature for every later row.
- The merge commit from `feature-sync.sh` used git's default message, with no session
  trailers. It was pushed before this was noticed and is left as it is, since rewriting a pushed
  commit needs a force push.
