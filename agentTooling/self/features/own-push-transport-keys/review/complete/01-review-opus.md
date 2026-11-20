# 01 — review: own-push-transport-keys

Review the diff against the brief (`../../OWNER_BRIEF.md`), not against the builder's
account of it. "No findings" is a legitimate verdict: report one only for a behaviour the
brief asks for that the diff does not deliver, a regression, or a contract below that it
breaks.

## What the feature was supposed to do

- **The cloud own-branch push prompts on a transport key.** `git push [-u] origin <B>`
  (cloud profile, own branch, from the root) must not be approved silently when the
  effective config (every scope `git config --list -z` reads) holds a key that redirects or
  weakens the transport or names a file the transport reads: at least `http.proxy`,
  `remote.<name>.proxy`, `http.sslVerify`, `http.curloptResolve`, `http.sslCAInfo`,
  `http.sslCAPath`, `http.sslCert`, `http.sslKey`, `http.cookieFile`, `http.saveCookies`,
  each also as `http.<url>.<var>`. The result is a prompt (no decision), never a deny.
- **More keys decided from git's documentation**, with the reasoning in `NOTES.md`; a
  deny-by-default shape is preferred if it keeps ordinary pushes approved. The cloud
  container's own config (`http.proxyauthmethod=basic` in `~/.gitconfig`,
  `credential.interactive=false` and two non-applying `url.*.insteadOf` in the command-line
  scope) must still approve.
- **Orchestrator addendum.** In an orchestrator session, a `git mv` is approved only as the
  whole line `orchestrator_moves_own_record` matches (the move alone, or after exactly
  `mkdir -p plans/orchestrations && `). Any other line holding a `git mv` — piped into a
  reader, doubled with `&&`, chained with a read — is the allowlist denial, as on the base,
  never a prompt.
- **Backlog.** The `--config plans/ruff.toml` basename gap is filed in `self/BACKLOG.md`,
  not fixed.
- **Excluded:** git's environment overrides (`GIT_SSL_*`, `HTTPS_PROXY`), which the cloud
  platform sets itself; credential keys other than helpers; ssh-only and git://-only keys.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/allow-repo-commands.sh`: `own_push_config_allows` still returns False on every key
  and condition it did before (`OWN_PUSH_PRESENT_KEYS`, `OWN_PUSH_PRESENT_KEY_RES`,
  `push.default`, the origin url, the askpass and helper environments); adds
  `OWN_PUSH_HTTP_SECTION` / `OWN_PUSH_HTTP_SAFE_VARS` and a `remote\..*\.proxy` regex. The
  check must work on git's listed form: section and variable lower-case, the url
  subsection as written (it may hold dots).
- `orchestrator_git_allowed` returns False for `mv`; `orchestrator_moves_own_record` and
  the `main` path that emits `ORCHESTRATOR_MOVE_REASON` are unchanged.
- `self/tests/hook-cloud-profile.sh` Q10: one prompt row per key family in mixed case, bare
  and url-scoped, a global-config-only row, approve rows for the kept variables and a
  restore row; every Q7-Q9 row still passes.
- `self/tests/hook-orchestrator-role.sh` H28: the pipe, doubled `&&` and chained-read rows
  are the allowlist denial; the move alone and the `mkdir -p` remedy still approve.
- `hooks/README.md` ("the effective config" bullet and the orchestrator table's `mv`
  refusal cell) and `self/tests/README.md` describe the new rows; `CONVENTIONS.md` changes
  only if it describes what the push approval checks.
- `./self/gate.sh` is green.

## Verdict
