# Notes: propagate-agenttooling-access

Rulings made during the hand build, each with its reason. The brief is the spec; these
are what it left open.

1. **`update.sh` recognises the failure — the code change was taken, not docs-only.** The
   spec allowed it only if reliable and testable offline. Both hold: the failure is read
   from git's own stderr after the pull fails, and the test drives it with a
   `git-remote-testauth` helper on `PATH` (git resolves `<scheme>://` to
   `git-remote-<scheme>`), which prints the proxy's line and exits 128 — no network.
2. **The line matched is the one observed.** In this container,
   `GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/ssdesai/vinylCatalogue.git` (a
   repo not attached to the session) answered `fatal: could not read Username for
   'https://github.com': terminal prompts disabled`, exit 128, while the attached
   `ssdesai/agentTooling` answered. `AUTH_FAILURE_RE` also takes git's other spellings of
   the same refusal (`Authentication failed`, `returned error: 401`/`403`, `Repository not
   found`), so a proxy that answers differently still gets the hint; a merge conflict or a
   missing remote does not match (U8).
3. **Only under the cloud profile, asked of `env-profile.sh`.** Locally the same text means
   the user's own credentials, and the hint would be wrong. `update.sh` spells no profile
   variable: it sources `env-profile.sh` and calls `profile_is_cloud`, so
   `self/profile-confinement.sh` holds. It sources it lazily, only after a failed pull
   whose stderr matched — the pull has not overwritten anything then, and a copy without
   `env-profile.sh` beside it (the pre-existing test fixtures) keeps its old behaviour.
4. **Advisory, not a new exit code.** The exit stays `REFUSED_RC`; the `remedy` line is
   added after git's error on stderr. A caller that checks the code sees nothing new.
5. **git's stderr is teed, not swallowed.** The pull's stderr goes through `tee` into a
   temporary file and on to stderr as it comes; stdout is kept on its own descriptor, so
   the `pull`/merge output reads as before. The temporary file is removed on both paths.
6. **The repo named is derived from the remote**, `owner/repo` out of a `github.com` URL
   with `.git` dropped (`ssdesai/agentTooling` for `DEFAULT_REMOTE`), and the whole URL
   for any other remote — so `--remote` to a fork names the fork.
7. **Docs placed where a propagating session reads them**: `LIFECYCLE.md` → "Propagate"
   step 2 (the cloud path, before the pull), `README.md` → "Updating" and the `update.sh`
   index entry, `ORCHESTRATION.md`'s propagation-round note, and the cloud design's §0
   list of how a cloud session differs (git as well as `gh` goes through a proxy).
8. **Round 2 (rework of the round-1 escalation): the two untested contracts get checks.**
   U5h runs the successful pull with stdout and stderr captured apart, so a reordered
   `2>&1 1>&3` is caught; U5i and U6e give the run its own `TMPDIR` and require no
   `update-pull.*` left on either path. Both were seen to fail with the redirection
   swapped and the success-path `rm -f` removed, and pass once restored. No `trap` was
   added for an interrupted pull (the review's note): one small temp file in `TMPDIR` on
   Ctrl-C is not worth a trap that would have to coexist with the self-overwriting
   `main()`.
9. **Round 3 (the merge of `origin/main` after PRs 91 and 93) exposed a harness gap, left
   for a self feature of its own.** The round ran in a second cloud container, where the
   round-2 coordinator's transcript (`1d50d2d4…`, pinned in `sessions`) no longer exists,
   so `feature-close.sh`'s capture refused on `check_frozen_cost`. The cost record was
   written by hand with `capture_planning.py --carry-lost`, the remedy the refusal names.
   Two things make that a gap and not a one-off: `feature-close.sh` and
   `feature-capture.sh` never pass `--carry-lost`, and `check_frozen_cost` does not skip
   `carried_from` entries — so a feature whose rounds span containers refuses on every
   later close, and each re-capture is a hand step.
