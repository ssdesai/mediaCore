Verdict: escalated

# Review: propagate-agenttooling-access

## What the batch was supposed to do

On 2026-10-26, three of four cloud-session propagation pulls of agentTooling PR 90 failed
at `git subtree pull` from `https://github.com/ssdesai/agentTooling`. A cloud session's git
proxy serves only the repos attached to that session, and the pulls worked only after
`ssdesai/agentTooling` was attached with `add_repo` (read access). The feature was to:

1. document that step wherever a propagating session reads it;
2. optionally make `update.sh` print a one-line remedy for an auth failure under the cloud
   profile, tested offline;
3. keep the READMEs current and the gate green.

## Does it do it

Yes. I read the code and found no defects in it.

- **Docs.** The step is in `LIFECYCLE.md` → "Propagate" step 2, `README.md` → "Updating"
  and the `update.sh` entry, `ORCHESTRATION.md`'s propagation-round note, and the cloud
  design's list of how a session differs. Each names `add_repo`, read access and
  `ssdesai/agentTooling` correctly. None contradicts what `update.sh` does.
- **Cloud-only and auth-only.** `cloud_auth_remedy` runs only when the pull's exit is
  non-zero and its stderr matches `AUTH_FAILURE_RE`. It sources `env-profile.sh` only at
  that point and returns quietly when the file is absent or the profile is not `cloud`.
  The exit code is still `REFUSED_RC`, and git's error is still shown, because it goes
  through `tee` to stderr.
- **Pull path.** The pipeline `{ git … 2>&1 1>&3 3>&- | tee "$errlog" >&2; pull_rc=${PIPESTATUS[0]}; } 3>&1`
  sends git's stdout to the caller's stdout and its stderr to the caller's stderr.
  `PIPESTATUS[0]` is git's exit status, not `tee`'s. The temp file is removed on both the
  success and the failure path.
- **Survives overwriting itself.** Everything new is in `main()` or in a function defined
  before it. Nothing follows `main "$@"`.
- **Profile confinement.** `update.sh` does not spell either profile variable; it calls
  `profile_is_cloud`. The test spells them, which is allowed under `tests/`.
- **Tests are not vacuous, and none need the network.** U6 fails if the remedy is
  removed. U7 (local profile) and U8 (cloud, missing remote) fail if the remedy is printed
  every time. The failing fetch is a `git-remote-testauth` helper on `PATH`. U1–U5 are
  unchanged, and all pass in `self/gate-report.txt`.
- **`NOTES.md`** says why the code change was taken instead of a docs-only fix
  (ruling 1).

## Fixed in this pass

- `env-profile.sh` header: it still said the file was sourced only by `feature-start.sh`
  and `forge.sh`. It now also names `update.sh`, which sources it only after a failed pull.
- `README.md` `env-profile.sh` entry: the same correction to its "sourced by" list
  (CONVENTIONS.md Rule 2).

Both are comment or prose changes. `bash -n env-profile.sh` passes.

## Escalated to the next round

Two contracts in the review brief are true when I read the code, but no test checks them.
A later edit to the `tee` pipeline could break either one without turning the gate red.
Both fixes are new checks in `self/tests/update-cloud-branch.sh`; no code change is needed.

1. **A successful pull's stdout and stderr stay separate.** U5 runs `update.sh` with
   `2>&1`, so it would still pass if the redirection swapped them, for example if
   `1>&3`/`2>&1` were reordered. Add a check (e.g. U5h) that runs the successful pull with
   stdout and stderr captured to separate files. The `pull` / `split` lines and the stub
   sync's line must be in stdout. Git's own error text must not be in stdout.
2. **No temp file is left behind.** Nothing checks for a leftover `update-pull.*` file.
   Run U5 and U6 with `TMPDIR` set to a fresh empty directory under `$TMP`. After each,
   check that the directory holds no `update-pull.*` entry. Without this, deleting either
   `rm -f "$errlog"` (success path or failure path) goes unnoticed.

Update `self/tests/README.md`'s `update-cloud-branch.sh` entry to describe the new checks.

Not escalated, noted for the record: there is no `trap`, so a pull interrupted with
Ctrl-C leaves its temp file in `TMPDIR`. The script never left anything behind before, but
this costs only one small file in a temp directory.
