# `own-push-transport-keys` — child brief

Dispatched 2026-11-20 by the orchestrator. The finding comes from musicMap's propagation-pull
audit (`plans/features/pull-agenttooling-pr169/audit-report.md`, 01-audit-opus, the one
`blocking` row). The orchestrator confirmed the lists are unchanged on agentTooling main
4e20b19e. The text below is sent as the prompt.

---

feature: agentTooling/own-push-transport-keys

agentTooling self feature `own-push-transport-keys` — implementer brief

## Role

You are the session for ONE agentTooling self feature. Orchestration `tooling-wave-2026-11-18`; the orchestrator (session_0175k4pGGZCBv63KaXaGDio4) reads your report. Never merge your PR. If you are blocked, say exactly what you need and stop.

## The defect (from a consumer's security audit, verbatim)

> | blocking | `git push origin claude/pull-agenttooling-pr169` (cloud profile, cwd the root, own branch, manifest committed at HEAD) after the repo config gains a transport-redirecting key not in `OWN_PUSH_PRESENT_KEYS`: `http.proxy` / `http.<url>.proxy` / `remote.origin.proxy`, `http.sslVerify=false`, `http.curloptResolve`; also file-naming `http.sslCAInfo`, `http.sslCert`, `http.cookieFile` | allow | ask |

The cloud own-branch push approval in `hooks/allow-repo-commands.sh` refuses when the repo config holds a key in `OWN_PUSH_PRESENT_KEYS` / `OWN_PUSH_PRESENT_KEY_RES` (main 4e20b19e, lines 685–697; consulted near line 4708). Those lists omit transport-redirecting and TLS/credential-file keys. So after one human-approved `git config` write, every own-branch push is silently approved while traffic can go to another proxy, skip TLS verification, or present a planted client certificate or cookie file.

## What to build

1. Make the own-push approval refuse (fall through to ask) when the repo config, or any config the push reads that the check already reads, holds a key that redirects or weakens the transport, or names a file the transport reads. At least: `http.proxy`, `http.<url>.proxy`, `remote.<name>.proxy`, `http.sslVerify` / `http.<url>.sslVerify`, `http.curloptResolve`, `http.sslCAInfo`, `http.sslCAPath`, `http.sslCert`, `http.sslKey`, `http.cookieFile`, `http.saveCookies`, each also in its `http.<url>.` form.
2. Read git's config documentation for the `http.*` and `remote.*` keys and decide whether more belong: for example `http.proxyAuthMethod`, `http.proxySSL*`, `http.sslBackend`, `http.extraHeader`, `http.emptyAuth`, `credential.*`, `core.sshCommand`, `ssh.variant`, `remote.<name>.pushurl` / `url.*.pushInsteadOf` (check whether already covered). Write your reasoning in NOTES. Prefer a deny-by-default shape (refuse any `http.*` key, or anything outside a short known-safe set) if it is simpler and keeps the tests' ordinary pushes approved. Say which you chose and why.
3. Tests in `self/tests/` (the existing hook test file for the own-branch push): one case per key family that must ask, with key names in mixed case as git normalizes them, and a control showing a clean config still approves.
4. Update `hooks/README.md` and `CONVENTIONS.md` → "Shell commands" only where they describe what the push approval checks.

## Lifecycle

`./feature-start.sh --self own-push-transport-keys --method direct --branch claude/own-push-transport-keys --orchestration tooling-wave-2026-11-18`, run in the background with output to a scratchpad file; wait for its exit notification. Then build, `./self/gate.sh`, `./run-review.sh --self own-push-transport-keys` (the change is on an audit path, so the security audit runs too), and on `Verdict: clean` `./feature-close.sh --self own-push-transport-keys`. Include `OWNER_BRIEF.md` (this brief's "The defect" and "What to build" sections verbatim), an acceptance table and a "Deviations from the brief" section, per the conformance checks. 3 review rounds / 2 escalated audit rounds, then stop and report. Commit subjects prefixed `own-push-transport-keys:`; commit messages end with the trailer lines your session instructions give. No model identifiers in committed files. Never edit `.claude/`.

## Report, terse

PR URL, the key set chosen and why, gate result, review and audit verdicts, cost.
