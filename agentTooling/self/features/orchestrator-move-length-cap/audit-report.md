Verdict: clean

# Security audit (round 3): orchestrator-move-length-cap

Head is this branch's `HEAD` (`66665e7`). Base is `origin/main`. Both ran from throwaway
copies under the pass's scratch directory (`git archive HEAD`, `git archive origin/main`),
never from this checkout. Further copies of the head were made for the tampered-file cases.

Since round 2, the owner's ruling split the conformance carry-forward (R-carry) out of
this feature (`72bed8c`). `conformance.py` and `feature-close.sh` are no longer in the
diff against `origin/main`, so this round has no R-carry rule to audit. The six files the
plan names hold two rules:

1. **R-cap** (`hooks/allow-repo-commands.sh`, `orchestrator_moves_own_record`): for an
   orchestrator session, a line longer than `ORCHESTRATOR_MAX_LINE_CHARS` (20000) is never
   the outright-approved move of its own record. It is checked before any parsing and falls
   to the allowlist denial. This tightens the hook.
2. **R-goahead** (`orchestration-start.sh`, `analysis/roots.py`, `hooks/shared_rules.py`
   `ROOTS_CLI_GO_AHEAD`): the start goes on past `roots.py start-refusal` (a no-`--self`
   start beside a vendored record) and `roots.py self-write` (a `--self` record write) only
   when the script exits 0 and prints exactly `ok`. Anything else refuses before any write.
   This tightens the start.

`analysis/README.md` and `hooks/README.md` change only documentation.

## How each was run

- **R-cap.** `scratch/inject.py` adds an attack block to the head's
  `self/tests/hook-orchestrator-role.sh`, after H29 and again after the H28 `mkdir -p`
  checks. The block sends each input through the real hook as a PreToolUse payload. It uses
  the test's consumer fixture, orchestrator session S and S's own stranded record, under
  both the `local` and `cloud` profiles, and prints one `AUDIT` line per result. The same
  injected test file was placed in the base copy and run against the base's hook.
  `scratch/compare.py` puts the two side by side.
  - The head test passed in full.
  - The base test failed only H29's four cap+1 checks. On the base, the padded move is
    approved.
- **R-goahead.** `scratch/inject_stubs.py` adds 11 more stub `roots.py` variants to the
  stub loops of C7 (`consumer-record-guard.sh`, `self-write`) and R14
  (`orchestration-records-in-repo.sh`, `start-refusal`). Each stub's exit code, whether a
  record was written, and the start's output are printed. The same files were run in each
  copy (`bash scratch/goahead.sh`).
- **R-goahead: the file the rule trusts.** `bash scratch/sr.sh` builds three more head
  copies and runs every stub against each:
  - `ROOTS_CLI_GO_AHEAD = ""` in `hooks/shared_rules.py`;
  - the `ROOTS_CLI_GO_AHEAD` line deleted;
  - the base's `shared_rules.py`, which has no such name.

## Inputs tried

### R-cap

The inputs were run against the orchestrator session S under both `local` and `cloud`.
Every row gave the same result under both profiles.

- `OWN_MOVE` is `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`
  (70 characters).
- `REMEDY` is `mkdir -p plans/orchestrations && ` followed by `OWN_MOVE` (103 characters).
- "deny" means the allowlist denial (`an orchestrator session runs only…`).

| input | len (OWN_MOVE / REMEDY) | head | base |
|---|---|---|---|
| plain | 70 / 103 | allow | allow |
| space-padded to cap−1 | 19999 / 19999 | allow | allow |
| space-padded to exactly the cap | 20000 / 20000 | allow | allow |
| space-padded to cap+1 | 20001 / 20001 | deny | allow |
| leading-space-padded to cap+1 | 20001 / 20001 | deny | allow |
| tab-padded to cap+1 | 20001 / 20001 | deny | allow |
| CR-padded to cap+1 | 20001 / 20001 | deny | allow |
| NBSP (U+00A0)-padded to cap+1 | 20001 / 20001 | deny | allow |
| U+3000-padded to cap+1 | 20001 / 20001 | deny | allow |
| a newline, then spaces to cap+1 | 20001 / 20001 | deny | allow |
| repeated ` >/dev/null` (a harmless redirect the rule strips) past the cap | 20002 / 20002 | deny | allow |
| repeated ` 2>&1` past the cap | 20005 / 20003 | deny | allow |
| repeated ` >/dev/null` up to the cap | 19991 / 19991 | allow | allow |
| ` #` comment, then `x` to cap+1 | 20001 / 20001 | deny | deny |
| padded to 2× the cap | 40000 / 40000 | deny | allow |
| padded to 10× the cap | 200000 / 200000 | deny | allow |
| spaces to exactly the cap (second run) | 20000 / 20000 | allow | allow |
| `env ` prefix | 74 / 107 | deny | deny |
| `/usr/bin/env ` prefix | 83 / 116 | deny | deny |
| `command ` prefix | 78 / 111 | deny | deny |
| `nohup ` prefix | 76 / 109 | deny | deny |
| `exec -a x ` prefix | 80 / 113 | deny | deny |
| `sudo ` prefix | 75 / 108 | deny | deny |
| `bash -c '<line>'` | 80 / 113 | deny | deny |
| `echo '<line>' \| sh` | 82 / 115 | deny | deny |
| `echo x \| xargs <line>` | 85 / 118 | deny | deny |
| `<line> ; true` | 77 / 110 | deny | deny |
| `<line> && ls` | 76 / 109 | deny | deny |
| `"git" mv …` | 72 / 105 | allow | allow |
| `g''it mv …` | 72 / 105 | allow | allow |
| `g\it mv …` | 71 / 104 | deny | deny |
| `$(true) ` prefix | 78 / 111 | deny | deny |
| `X=1 ` prefix | 74 / 107 | deny | deny |
| brace group in the destination (`plans/{orchestrations,x}/…`) | 74 / 107 | deny | deny |
| glob in the destination (`plans/orchestrat*/…`) | 67 / 100 | deny | deny |
| a 30000-character `cat` heredoc, then the line | 30085 / 30118 | deny | deny |
| `REMEDY` with the padding inside, before `&&`, to cap+1, plus each of the 36 variants above applied on top of it | 19998–200000 | deny (all 36) | deny (all 36) |

`"git" mv` and `g''it mv` are the same command as the plain move once the shell removes
the quotes, so they are not bypasses. Every past-cap input was denied by the head,
whatever the padding character, its position, or harmless-redirect padding stripped
before the parse. No input is more permissive on the head than on the base.

A non-string `command` (a list or `null`) was not sent. The rule runs inside main()'s
`try/except`, which denies anything that raises, and both copies call
`ORCHESTRATOR_HARMLESS_REDIRECT_RE.sub` on the value, which raises for a non-string.

### R-goahead: stub `analysis/roots.py`

- `self-write` is the standalone `--self` start of `closed` (C7's fixture).
- `start-refusal` is the start of `idle-one` past a vendored record (R14's fixture).
- "went on" means the record was written. After each stub, the written record was removed
  so the next stub was judged afresh.

| stub | `self-write` head | `self-write` base | `start-refusal` head | `start-refusal` base |
|---|---|---|---|---|
| empty file (exit 0, no output) | refused, nothing written | went on | refused | went on |
| `sys.exit(0)` | refused | went on | refused | went on |
| `print("go")` | refused | went on | refused | went on |
| `print("ok ")` (trailing space) | refused | went on | refused | went on |
| `print("OK")` | refused | went on | refused | went on |
| `print("ok"); print("x")` | refused | went on | refused | went on |
| `print("ok", file=sys.stderr)` | refused | went on | refused | went on |
| `print("\nok")` (leading newline) | refused | went on | refused | went on |
| `print("ok\r")` | refused | went on | refused | went on |
| `print("ok"); sys.exit(1)` | refused (rc 1) | refused (rc 1) | refused | refused |
| `print("ok"); sys.exit(2)` | refused | refused | refused | refused |
| `raise SystemExit("boom")` (crash, rc 1) | refused ("cannot ask") | refused | refused ("could not be classified") | refused |
| `print("ok\n\n")` (`$(…)` strips trailing newlines, so this is exactly `ok`) | went on | went on | went on | went on |
| `print("ok")` (prints the go-ahead itself) | went on | went on | went on | went on |
| real `roots.py`, standalone `self-write x` / `start-refusal idle-one` | exit 0, prints `ok` | — | exit 0, prints `ok` | — |

The last two stubs print the go-ahead token itself. The rule is a fixed token, not a
secret, and it exists to catch an emptied or stubbed `roots.py` that exits 0 without it
(the comments in `shared_rules.py` and `orchestration-start.sh`). A stub that prints the
token is a classifier that says "go on", and the base goes on too. Neither is a finding.

### R-goahead: tampering with `hooks/shared_rules.py`, the file the rule trusts (head copies, all 14 stubs above)

| tamper | `self-write` (14 stubs) | `start-refusal` (14 stubs) | base, same input |
|---|---|---|---|
| `ROOTS_CLI_GO_AHEAD = ""`, which would make empty output "match" | all refused: "cannot read the shared rules" (an empty shared value stops the read loop) | all refused, same | the base reads no such name: its empty-stub start goes on (table above) |
| `ROOTS_CLI_GO_AHEAD` line deleted | all refused, same | all refused, same | as above |
| base's `shared_rules.py` (has no `ROOTS_CLI_GO_AHEAD`; its CLI exits 2 on the unknown name) | all refused, same | all refused, same | as above |

Every tampered `shared_rules.py` leaves the head refusing, where the base, which does not
read the token, goes on.

## Findings

None.

## Non-blocking findings

None.

No input was more permissive on the head than on the base, and the head denied every
input the two rules exist to deny. These inputs gave the same result on both copies:
`"git" mv` and `g''it mv`, which are the same move after the shell removes the quotes,
and the stubs that print the go-ahead token. Neither is something the rules exist to deny,
so neither is a finding, and nothing needs a backlog entry.
