# Notes: own-push-transport-keys

Rulings, with a one-line reason each, then the acceptance table and the deviations.

## Source

A consumer's security audit (the row is verbatim in `OWNER_BRIEF.md`): in the cloud profile,
`git push origin <own-branch>` was approved silently after the repo config gained
`http.proxy`, `http.<url>.proxy`, `remote.origin.proxy`, `http.sslVerify=false`,
`http.curloptResolve`, or a file-naming `http.sslCAInfo`, `http.sslCert` or
`http.cookieFile`. The base asked.

## Rulings

1. **`http.*` is deny-by-default, with a short safe set.** Any `http.<var>` or
   `http.<url>.<var>` whose variable (the last dot-separated component, which git prints
   lower-case) is outside `OWN_PUSH_HTTP_SAFE_VARS` prompts. The safe set is
   `proxyauthmethod`, `postbuffer`, `lowspeedlimit`, `lowspeedtime`, `maxrequests`,
   `minsessions`, `version`.
   - *Why deny-by-default, not a longer list.* Of git's 34 documented `http.*` variables,
     most either redirect the transport (`proxy`, `curloptresolve`, `followredirects`),
     weaken TLS (`sslverify`, `sslversion`, `sslcipherlist`, `ssltry`, `sslbackend`,
     `schannel*`), name a file the transport reads (`sslcainfo`, `sslcapath`, `sslcert`,
     `sslkey`, `cookiefile`, `pinnedpubkey`, `proxysslcert`, `proxysslkey`,
     `proxysslcainfo`), write one (`savecookies`), or add credentials (`extraheader`,
     `emptyauth`, `delegation`). Listing every one would leave the next variable a git
     release adds silently approved; the seven kept ones only tune a transfer that already
     goes where and how the rest of the config says.
   - *Why a safe set at all, not "any `http.*`".* This container's `~/.gitconfig` sets
     `http.proxyauthmethod=basic`, so refusing every `http.*` key would prompt on every real
     cloud push — the approval the feature exists to keep. `proxyauthmethod` picks how git
     authenticates to the proxy the environment already names; it moves nothing.
     `postbuffer` is the common fix for a large push. The rest are timeouts, concurrency and
     the HTTP version.
   - *Left out of the safe set on purpose.* `useragent` and `noepsv` are harmless but nobody
     needs them on a push; `followredirects` can send the push to another host;
     `pinnedpubkey` strengthens TLS but names a file, and the brief counts a named file as a
     prompt.
   - *URL subsection.* The rule ignores the URL: `http.<url>.<var>` prompts for any URL,
     matching or not, rather than reimplementing git's URL matching.
2. **`remote.<any>.proxy` prompts** (a regex in `OWN_PUSH_PRESENT_KEY_RES`, `.*` like the
   others so an empty subsection counts). Only `origin`'s matters to this push, but any
   remote's is cheap to refuse and nothing in a feature's checkout sets one.
   `remote.<name>.proxyauthmethod` stays approved, for the reason `http.proxyauthmethod`
   does.
3. **The other families the brief named, checked against git's documentation**
   (`git help -c`, git 2.43):
   - `http.proxyAuthMethod`: kept (ruling 1). `http.proxySSL*`, `http.sslBackend`,
     `http.extraHeader`, `http.emptyAuth`: prompt, through ruling 1.
   - `credential.*`: `credential.helper` and `credential.<url>.helper` already prompt
     (`own-push-credential-keys`). The rest (`username`, `useHttpPath`, `interactive`,
     `protectProtocol`, `sanitizePrompt`) run nothing and move nothing; the cloud sets
     `credential.interactive=false` itself. Left approved.
   - `core.sshCommand`: already prompts. `ssh.variant`, `core.gitProxy`, `protocol.*`:
     apply to ssh and git:// transports only, and the approval already requires one
     http(s) origin url, so they cannot reach this push. Left approved.
   - `remote.<name>.pushurl`: already prompts for `origin`. `url.*.pushInsteadOf` /
     `insteadOf`: already covered — the approval requires `remote get-url --push --all` to
     print the configured url unchanged.
   - `trace2.*Target` writes trace events to a file or socket; it moves no traffic and the
     events carry no credential. Out of scope, as the brief is the transport.
4. **Environment overrides are not checked.** Git reads `GIT_SSL_NO_VERIFY`,
   `GIT_SSL_CAINFO`, `GIT_SSL_CERT`, `GIT_HTTP_PROXY_AUTHMETHOD`, `HTTPS_PROXY` and friends
   from the environment. The cloud platform sets `GIT_SSL_CAINFO` and `HTTPS_PROXY` itself
   (its agent proxy), so refusing them would prompt on every push; the hook's environment is
   the session's, which no Bash call changes (a `VAR=x git push` prefix already prompts).
5. **Orchestrator addendum: every `git mv` the allowlist's per-command loop reads is the
   denial.** `orchestrator_command_allowed` (and `main` before it) approves the record move
   through `orchestrator_moves_own_record`, which matches the WHOLE line. A `git mv` reached
   in the per-command loop is therefore on some other line, so `orchestrator_git_allowed`
   returns False for it, and the line gets the allowlist denial the base gave.
   `orchestrator_record_move` is now called only from `orchestrator_moves_own_record`.

## Acceptance

| # | Requirement | Where | Test |
|---|---|---|---|
| 1 | The approval prompts on `http.proxy`, `http.<url>.proxy`, `remote.<name>.proxy`, `http.sslVerify` (bare and url), `http.curloptResolve`, `http.sslCAInfo`, `sslCAPath`, `sslCert`, `sslKey`, `cookieFile`, `saveCookies`, each in its `http.<url>.` form too | `hooks/allow-repo-commands.sh`: `OWN_PUSH_HTTP_SAFE_VARS`, the `remote\..*\.proxy` regex, `own_push_config_allows` | `hook-cloud-profile.sh` Q10, one row per key, mixed case, bare and url-scoped |
| 2 | More keys decided from git's docs, reasoning in NOTES, the shape chosen and why | Rulings 1-4; deny-by-default chosen | Q10 rows for `proxySSLCert`, `proxySSLCAInfo`, `sslBackend`, `extraHeader`, `emptyAuth`, `followRedirects`, `pinnedPubkey`, an unknown variable |
| 3 | Mixed-case keys, a clean-config control, ordinary pushes still approved | — | Q10 rows (keys typed as `SSLVerify`, `Proxy`, `SslCert`; url `https://GitHub.COM/`), the global-config-only row, seven safe-variable approve rows, the restore row, and every existing Q7-Q9 approve row |
| 4 | `hooks/README.md` and `CONVENTIONS.md` updated where they describe the checks | `hooks/README.md` → "the effective config"; `CONVENTIONS.md` lists no config keys, so it is unchanged | — |
| 5 | Orchestrator addendum: a `git mv` on any line but the approved move is the allowlist denial | `orchestrator_git_allowed` | `hook-orchestrator-role.sh` H28: the move piped into `cat`, doubled with `&&`, chained with `ls` before and after, all DENY with the allowlist; the move alone and the `mkdir -p` remedy still approve |
| 6 | Orchestrator addendum: the `--config plans/ruff.toml` basename gap filed | `self/BACKLOG.md`, folded into the existing nested-`--config` entry (same cause) | — |

## Deviations from the brief

- **Built by this session, not a delegate.** The manifest says `method: direct` as the
  brief's start command set it; no implementer delegate was spawned, so the build cost is
  this session's.
- **The ruff backlog item extends an existing entry** rather than adding a new one: the
  entry "A nested settings file with a discovered name is accepted by `--config`" already
  holds the same cause and assertion.
