# Owner brief: own-push-transport-keys

The orchestrator's brief, verbatim ("The defect" and "What to build"), then the addendum the
orchestrator sent after the start.

## The defect (from a consumer's security audit, verbatim)

> | blocking | `git push origin claude/pull-agenttooling-pr169` (cloud profile, cwd the root, own branch, manifest committed at HEAD) after the repo config gains a transport-redirecting key not in `OWN_PUSH_PRESENT_KEYS`: `http.proxy` / `http.<url>.proxy` / `remote.origin.proxy`, `http.sslVerify=false`, `http.curloptResolve`; also file-naming `http.sslCAInfo`, `http.sslCert`, `http.cookieFile` | allow | ask |

The cloud own-branch push approval in `hooks/allow-repo-commands.sh` refuses when the repo config holds a key in `OWN_PUSH_PRESENT_KEYS` / `OWN_PUSH_PRESENT_KEY_RES` (main 4e20b19e, lines 685–697; consulted near line 4708). Those lists omit transport-redirecting and TLS/credential-file keys. So after one human-approved `git config` write, every own-branch push is silently approved while traffic can go to another proxy, skip TLS verification, or present a planted client certificate or cookie file.

## What to build

1. Make the own-push approval refuse (fall through to ask) when the repo config, or any config the push reads that the check already reads, holds a key that redirects or weakens the transport, or names a file the transport reads. At least: `http.proxy`, `http.<url>.proxy`, `remote.<name>.proxy`, `http.sslVerify` / `http.<url>.sslVerify`, `http.curloptResolve`, `http.sslCAInfo`, `http.sslCAPath`, `http.sslCert`, `http.sslKey`, `http.cookieFile`, `http.saveCookies`, each also in its `http.<url>.` form.
2. Read git's config documentation for the `http.*` and `remote.*` keys and decide whether more belong: for example `http.proxyAuthMethod`, `http.proxySSL*`, `http.sslBackend`, `http.extraHeader`, `http.emptyAuth`, `credential.*`, `core.sshCommand`, `ssh.variant`, `remote.<name>.pushurl` / `url.*.pushInsteadOf` (check whether already covered). Write your reasoning in NOTES. Prefer a deny-by-default shape (refuse any `http.*` key, or anything outside a short known-safe set) if it is simpler and keeps the tests' ordinary pushes approved. Say which you chose and why.
3. Tests in `self/tests/` (the existing hook test file for the own-branch push): one case per key family that must ask, with key names in mixed case as git normalizes them, and a control showing a clean config still approves.
4. Update `hooks/README.md` and `CONVENTIONS.md` → "Shell commands" only where they describe what the push approval checks.

## Orchestrator addendum (from the orchestrator, after the start)

> Orchestrator addendum to your brief: one more hook regression to fix in this same feature, since it's the same file. List it in the acceptance table as "orchestrator addendum", not as a deviation, and add it to OWNER_BRIEF.md under a heading saying it came from the orchestrator.
>
> Source: humanNetworkMap's pull audit 04, on #172 (orchestrator-record-move-guard), verbatim summary:
> `orchestrator_git_allowed` gained a `sub == "mv"` branch. It admits the record move inside ANY line the allowlist reads, but `main` emits the allow only when `orchestrator_moves_own_record` matched the WHOLE line. Every other line the allowlist passed falls through to the ordinary judges, which PROMPT on `git mv` where the base DENIED.
> Repro (orchestrator session, its own stranded record planted):
> - `git mv agentTooling/self/orchestrations/legacy-one plans/orchestrations/legacy-one | cat` (any allowlisted reader after the pipe);
> - the same git mv twice joined by `&&`.
> Head prompts, base denies. Fix: deny every `git mv` that orchestrator_moves_own_record did not approve. The one approved shape is the move alone, or after `mkdir -p plans/orchestrations &&`; any other git mv is the allowlist denial. Add tests for the pipe and the doubled `&&` cases, plus the approved shapes as controls.
>
> Also file in self/BACKLOG.md (non-blocking, pre-existing, from the same audit): `--config plans/ruff.toml` with a planted fix=true is accepted, because RUNNER_CONFIG_NAMES checks the basename only.
