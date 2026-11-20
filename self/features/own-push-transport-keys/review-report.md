Verdict: clean

# Review: own-push-transport-keys

## What the batch was supposed to do

The cloud own-branch push (`git push [-u] origin <own branch>`) was approved silently even
when the effective git config redirected or weakened the transport: a proxy, `sslVerify=false`,
`curloptResolve`, or a planted CA, certificate, key or cookie file. The owner asked for those
keys (bare and `http.<url>.`) to turn the approval into a prompt, for more keys to be decided
from git's documentation (deny-by-default preferred), for mixed-case tests with a clean-config
control, and for docs to change only where they describe the check. The orchestrator's addendum
asked for every `git mv` that `orchestrator_moves_own_record` did not approve to be the
allowlist denial again, with tests, and for the `--config plans/ruff.toml` basename gap to be
filed in the backlog.

## Does it do it

Yes.

- `hooks/allow-repo-commands.sh:697-709`, `:4723-4726`: `remote\..*\.proxy` joins
  `OWN_PUSH_PRESENT_KEY_RES`. `http.*` is now deny-by-default: the section is split off with
  `partition(".")` and the variable taken with `rpartition(".")[2]`. On git's listed form that
  is correct: the section and variable are lower-case, the url subsection is kept as written
  and may contain dots, and a variable name never contains a dot. So `http.https://x.com/.proxy`
  yields `proxy`. Every check that existed before still runs unchanged ahead of the new one.
  The safe set (`proxyauthmethod`, `postbuffer`, `lowspeedlimit`, `lowspeedtime`,
  `maxrequests`, `minsessions`, `version`) holds only transfer tuning. It keeps the cloud
  container's own `http.proxyauthmethod=basic` approved.
- `orchestrator_git_allowed` returns `False` for `mv` (`:5724-5728`). The one approval path is
  unchanged. `main` calls `orchestrator_moves_own_record` on the whole line (`:5959`) and
  emits `ORCHESTRATOR_MOVE_REASON`. `orchestrator_command_allowed` still short-circuits on that
  same whole-line match (`:5808`). So the move alone and the `mkdir -p plans/orchestrations &&`
  remedy still approve, and any other line that holds a `git mv` falls to the allowlist denial.
- NOTES.md records the item-2 reasoning: why deny-by-default, and a ruling on each key the
  brief names (`credential.*`, `core.sshCommand`, `ssh.variant`, `pushurl` / `pushInsteadOf`).
- `CONVENTIONS.md` is unchanged, and correctly so: its "Shell commands" paragraph names the
  branch and manifest conditions of the push approval and lists no config keys.
- The gate report reads `all checks passed`, with no SKIPPED checks.

## Fixed in this pass

None.

## Escalated to the next round

None.

## Acceptance

| Item | Evidence | Result |
|---|---|---|
| 1 — transport keys (`http.proxy`, `http.<url>.proxy`, `remote.<name>.proxy`, `sslVerify`, `curloptResolve`, `sslCAInfo`, `sslCAPath`, `sslCert`, `sslKey`, `cookieFile`, `saveCookies`, bare and url-scoped) prompt | `hooks/allow-repo-commands.sh:697-709,4723-4726`; `self/tests/hook-cloud-profile.sh` Q10 `TRANSPORT_KEYS` rows and the global-config-only `sslVerify` row | done |
| 2 — more keys decided from git's docs, reasoning in NOTES, shape chosen and why | `self/features/own-push-transport-keys/NOTES.md` rulings 1-4 (deny-by-default chosen); Q10 rows for `proxySSL*`, `sslBackend`, `extraHeader`, `emptyAuth`, `followRedirects`, `pinnedPubkey`, an unknown variable | done |
| 3 — tests in the own-push test file: one case per family, mixed case, a clean-config control | `self/tests/hook-cloud-profile.sh` Q10: mixed-case prompt rows, approve rows for the kept variables, "the fixture is restored" row | done |
| 4 — `hooks/README.md` / `CONVENTIONS.md` updated only where they describe the push check | `hooks/README.md:923-930` (effective-config bullet); `CONVENTIONS.md` correctly unchanged (it lists no config keys) | done |
| orchestrator addendum — every `git mv` not approved whole is the allowlist denial; pipe and doubled-`&&` tests plus the approved shapes as controls | `hooks/allow-repo-commands.sh:5724-5728`; `self/tests/hook-orchestrator-role.sh` H28 rows (`| cat`, doubled `&&`, `&& ls`, `ls &&`, move alone approved); the `mkdir -p` remedy is approved by the existing H28 rows; `hooks/README.md` orchestrator table `mv` cell | done |
| orchestrator addendum — backlog entry for the `--config plans/ruff.toml` basename gap | `self/BACKLOG.md:26-30` | done |
| plan contract — `own_push_config_allows` keeps every earlier refusal; new `OWN_PUSH_HTTP_SECTION` / `OWN_PUSH_HTTP_SAFE_VARS` / `remote\..*\.proxy`; works on git's listed form | diff of `own_push_config_allows`; Q7-Q9 rows unchanged and green | done |
| plan contract — `orchestrator_moves_own_record` and the `main` emit path unchanged | the diff touches only `orchestrator_git_allowed` | done |
| plan contract — `hooks/README.md` and `self/tests/README.md` describe the new rows | `self/tests/README.md` Q10 and H28 entries | done |
| plan contract — `./self/gate.sh` green | `self/gate-report.txt` "all checks passed" | done |

## Deviations from the brief

None
