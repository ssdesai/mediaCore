Verdict: clean

# Security audit: shared-hook-rules

I audited `git diff origin/main...HEAD` of the 13 files the plan names. I attacked throwaway
copies of HEAD and `origin/main` (`git archive` into this pass's scratch directory, each
`git init`ed). The only file I changed in this checkout is this report.

## Rules the diff touches

The diff adds no new allow, ask or deny rule. It moves shared literals into
`hooks/shared_rules.py` and binds every other file to them. These rules now read that module:

| # | Rule (what it denies or asks, and for whom) | What changed |
|---|---|---|
| R1 | Orchestrator role (`orchestrator_role.py`): denies build scripts, implementer `Agent` briefs and anything outside the allowlist to a session named by a record's `session` or by the ledger. A `kind: coordinator` record is not a role. | Record roots, key names, ledger name, slug pattern and git markers are bound from `shared_rules` |
| R2 | Allowlist slug check (`ORCHESTRATOR_SLUG_RE`, for `report.py --orchestration <slug>`) | Now `shared_rules.SLUG_RE`, or a never-matching pattern if the import fails |
| R3 | Import guards in `allow-repo-commands.sh` | `except Exception` replaces `except ImportError`, plus a new guarded `import shared_rules` |
| R4 | Settings ask rules (`wire-settings.py`) | Record roots are formatted from `shared_rules` |
| R5 | `orchestration-start.sh`: slug check, standalone and legacy refusals, coordinator `kind`, ledger write | Reads 9 values from `python3 -B hooks/shared_rules.py …` via `printf -v`, and refuses if fewer come back |
| R6 | `analysis/manifest.py` coordinator refusal and slug check | Bound from `shared_rules`, reached by `roots.py` appending `hooks/` to `sys.path` |

## Fixture

- A record `self/orchestrations/wave` naming session S.
- A coordinator record `coord` naming session K.
- A ledger line `SESS-L ledgerwave` in `.git/agenttooling-orchestrators`.
- T is an unrelated session.

The hook ran with `CLAUDE_PROJECT_DIR` set to the copy and profile `local`. "silent" means the
hook printed nothing, so Claude Code's ordinary permission flow decides.

## Probes A: payloads, HEAD vs origin/main (R1, R2)

Each row ran for S, L (ledger only), K (coordinator) and T.

| Input | S (HEAD / base) | L (HEAD / base) | K (HEAD / base) | T (HEAD / base) |
|---|---|---|---|---|
| `./run-plans.sh --self x` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `env env ./run-batch.sh --self x` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `bash -c './feature-start.sh x …'` | deny role / deny role | deny role / deny role | deny / deny | deny / deny |
| `echo ./run-plans.sh \| sh` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `find . -name run-plans.sh -exec {} \;` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `./ru"n-pl"ans.sh x` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `./run-{plans,x}.sh x` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| `python3 analysis/report.py --orchestration wave` | allow / allow | allow / allow | allow / allow | allow / allow |
| `… --orchestration 'wave⏎'` (quoted trailing newline: `$` in `re.match`) | silent / silent | silent / silent | silent / silent | silent / silent |
| `… --orchestration Wave` | deny role / deny role | deny role / deny role | allow / allow | allow / allow |
| `… --orchestration wave-` | deny role / deny role | deny role / deny role | allow / allow | allow / allow |
| `… --orchestration -wave` | deny role / deny role | deny role / deny role | allow / allow | allow / allow |
| `… --orchestration wave--x` | deny role / deny role | deny role / deny role | allow / allow | allow / allow |
| `… --orchestration ../wave` | deny role / deny role | deny role / deny role | deny / deny | deny / deny |
| `python3 analysis/report.py --self --orchestration wave --checkout .` | allow / allow | allow / allow | allow / allow | allow / allow |
| `python3 analysis/manifest.py --orchestration wave get session` | allow / allow | allow / allow | allow / allow | allow / allow |
| `./orchestration-start.sh --self w2 --session SESS-S` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| Agent `feature: agentTooling/x⏎build it` | deny role / deny role | deny role / deny role | silent / silent | silent / silent |
| Agent `feature: none — analysis⏎read` | silent / silent | silent / silent | silent / silent | silent / silent |

All 76 cells match between HEAD and base.

## Probes B: S and L reaching `hooks/shared_rules.py` itself (R1, R3)

The module is now a single point of failure for R1, so I tried every route an orchestrator
has to remove, empty or replace it. Each command ran for S and for L, and both gave the same
answers.

| Input | HEAD | base |
|---|---|---|
| `git rm hooks/shared_rules.py` | deny role | deny role |
| `git rm -q --cached hooks/shared_rules.py` | deny role | deny role |
| `git mv hooks/shared_rules.py hooks/x.py` | deny role | deny role |
| `git checkout origin/main -- hooks/shared_rules.py` | deny role | deny role |
| `git restore --source=HEAD~1 hooks/shared_rules.py` | deny role | deny role |
| `git stash` | deny role | deny role |
| `rm …`, `mv … /tmp/x`, `truncate -s0 …`, `cp /dev/null …`, `: > …` | deny role (each) | deny role (each) |
| `git show HEAD:README.md > …`, `git log > …`, `git diff --output=…` | deny role (each) | deny role (each) |
| `ln -sf /dev/null …`, `chmod 000 …`, `mkdir hooks/shared_rules` | deny role (each) | deny role (each) |
| `touch hooks/__pycache__/shared_rules.cpython-311.pyc` | deny role | deny role |
| `python3 -B hooks/shared_rules.py SLUG_PATTERN` | deny role | deny role |
| `python3 hooks/shared_rules.py SLUG_PATTERN > hooks/shared_rules.py` | deny role | deny role |
| `rg -l x > …`, `sed -n 1p … > …` | deny role (each) | deny role (each) |
| `git commit -m x hooks/shared_rules.py` | deny role | deny role |
| `./orchestration-start.sh --self w2 --session SESS-T` | deny role | deny role |
| `git add hooks/shared_rules.py` | silent | deny role |
| Write/Edit on `hooks/shared_rules.py`, `analysis/shared_rules.py`, `shared_rules.py`, `hooks/orchestrator_role.py`, the record | silent (each) | silent (each) |

The `git add` difference only reflects the file's existence. `git add hooks/policy.py` and
`git add analysis/roots.py` are silent on both copies, and `git add hooks/no_such_file.py` is
denied on both. It stages a file and does not change what the hook reads.

The hook does not decide Write/Edit on either copy. The settings ask rules cover them:
`Edit(**/hooks/**)` under `--self`, and `Edit(**/agentTooling/**)` in a consuming repo.

## Probes C: edits to files the rules trust (R1, R3)

These ran on a fresh HEAD copy per row. The probes were S `./run-plans.sh --self x`,
S Agent `feature: agentTooling/x`, L and L2 `./run-plans.sh`, and S `report.py
--orchestration wave` / `'a b'`.

| Edit in the copy | Result |
|---|---|
| A malicious `shared_rules.py` in the project root (the cwd) | role still denies (S, L), allowlist unchanged: not imported |
| A malicious `analysis/shared_rules.py` | role still denies: not imported by the hook |
| A malicious `self/orchestrations/shared_rules.py`, run with that directory as cwd | role still denies |
| A junk `hooks/__pycache__/shared_rules.cpython-311.pyc` | role still denies (`dont_write_bytecode`, the source is newer) |
| `re.py` in the project root | role still denies |
| Ledger `SESS-L Bad_Slug!` and `SESS-L2 ok-slug` with no trailing newline | L and L2 both denied (a bad slug is still the role, as "unknown") |
| Record given `kind: coordinator` while a features entry carries `session` (uncommitted) | S still denied |
| Record `kind: "Coordinator"` (other case) | S still denied |
| Record `README.md` renamed to `readme.md` (uncommitted) | S still denied (history and ledger sources) |
| `plans/orchestrations/` created beside `self/` | S still denied |
| `hooks/shared_rules.py` removed, raising, or rewritten with other key names | all probes are no longer the role (silent or ordinary allow) |

The last row is the same failure mode origin/main has for `hooks/orchestrator_role.py`: a
single file in `hooks/` whose loss silences the role. Probes B show that no orchestrator
command reaches it, and any Write/Edit of it is asked by the settings. I do not count this as
a bypass.

## Probes D: `orchestration-start.sh` (R5)

| Input | HEAD | base |
|---|---|---|
| `--self ok-slug` | record written, ledger `SESS-N ok-slug` | same |
| Slugs `Bad`, `a_b`, `a⏎`, `-a`, `../x`, `a--b`, `a-`, `x&y`, `a b`, `é` | refused, slug pattern (each) | refused (each) |
| `--self wave` (exists) | refused, already exists | same |
| `--self ''` | usage, rc 2 | same |
| No `--self` in a standalone checkout | refused, standalone text | same text |
| `--self coordx --coordinator` | `"kind": "coordinator"`, no ledger line | same |
| Consumer layout, stranded legacy record `strand` | refused, legacy text with `{slug}` filled 4× | (n/a: base not built in consumer layout) |
| Consumer layout, fresh slug | `plans/orchestrations/fresh`, ledger `SESS-N fresh` in the consumer's git dir | — |
| HEAD with `shared_rules.py` removed | refused: "cannot read the shared rules" | — |
| HEAD with `shared_rules.py` exiting 0 and printing nothing | refused | — |
| HEAD with `LEDGER_NAME = ""` (empty line) | refused | — |
| HEAD with `re.py` in `hooks/` (stdlib shadowed) | refused | — |
| HEAD with `re.py` in cwd | not imported, record written | — |
| HEAD with `SLUG_PATTERN` widened to `.*` | `Bad` accepted | — |

The widened `SLUG_PATTERN` row needs an asked Edit to `hooks/`, the same as editing the
script's literal on base. The script uses `printf -v` without `eval`, and slug validation runs
before the `${…//\{slug\}/$SLUG}` substitution, so `&` or `/` cannot reach it.

## Probes E: settings and existing suites (R4, R6)

- `wire-settings.py` constants are identical on HEAD and base:
  - `POLICY_ASK_RULES` = `('Edit(**/agentTooling/**)', 'Edit(**/plans/orchestrations/**)')`
  - `RETIRED_EDIT_ASK_RULES` = `('Edit(**/agentTooling/hooks/**)', 'Edit(**/agentTooling/self/orchestrations/**)')`
  - `SELF_POLICY_ASK_RULES` = `('Edit(**/hooks/**)', 'Edit(/hooks/**)')`
- Run inside the HEAD copy, every suite passed: `shared-rules.sh`, `orchestrator-role.sh`,
  `hook-orchestrator-role.sh` (wrappers, quoting, globs, `bash -c`, pipes into a shell,
  heredocs, ledger, coordinator and hand-edited records), `orchestration-records-in-repo.sh`,
  `coordinator-records.sh`, `hook-wiring.sh` and `self-settings.sh`.
- R6: `roots.py` appends `hooks/` to `sys.path`, so an `analysis/shared_rules.py` would shadow
  it for the analysis tools. Writing that file is equivalent to editing `analysis/manifest.py`
  directly, which was always possible. The hook never imports it (Probes C), and the role's
  ledger and history sources hold regardless. This is no new capability.

## Bypasses

None. Every input the rules exist to deny is denied on HEAD exactly as on `origin/main`. The
only behaviour the diff adds is a single module whose loss silences R1, and getting there
requires an Edit to `hooks/` that the settings ask about and no orchestrator command reaches.
