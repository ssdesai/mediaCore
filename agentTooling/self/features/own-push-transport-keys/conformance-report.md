## Conformance

| Item | Evidence | Result |
|---|---|---|
| 1 | `hooks/allow-repo-commands.sh:697` adds `remote\..*\.proxy` to `OWN_PUSH_PRESENT_KEY_RES`. `hooks/allow-repo-commands.sh:699-709` adds `OWN_PUSH_HTTP_SAFE_VARS`. `hooks/allow-repo-commands.sh:4723-4726` refuses any `http.<var>` / `http.<url>.<var>` outside that set. This covers every listed key in bare and url form. | done |
| 2 | Deny-by-default is chosen, with the rationale in comments at `hooks/allow-repo-commands.sh:699-704` and in `hooks/README.md:923-930`. It covers `proxySSL*`, `sslBackend`, `extraHeader`, `emptyAuth` and future variables, and keeps `proxyAuthMethod` safe. The docstring at `hooks/allow-repo-commands.sh:4693-4700` covers pushurl / `pushInsteadOf` (pre-existing). NOTES is outside the diff, so I could not inspect the written reasoning on `credential.*`, `core.sshCommand` and `ssh.variant`. | done |
| 3 | `self/tests/hook-cloud-profile.sh` Q10 has `TRANSPORT_KEYS` rows: one per family, mixed case, bare and `http.<url>.`, plus a global-config-only `sslVerify` row. Approve controls are "Q10. config http.proxyAuthMethod is approved" and the others, plus "Q10. the fixture is restored: the plain push is approved again". `self/tests/README.md:1954-1961` documents Q10. | done |
| 4 | `hooks/README.md:923-930` is updated. `CONVENTIONS.md` is unchanged; its "Shell commands" text does not enumerate the config keys checked, so no change is needed there. | done |

## Out of scope

- `self/tests/hook-orchestrator-role.sh`: the orchestrator addendum (`git mv` allowlist denial tests); ties to no listed item.
- `self/BACKLOG.md`: the orchestrator addendum's `RUNNER_CONFIG_NAMES` backlog entry; ties to no listed item.
