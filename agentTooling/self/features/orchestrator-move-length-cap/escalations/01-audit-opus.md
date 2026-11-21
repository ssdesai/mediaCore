Verdict: escalated

# Security audit — orchestrator-move-length-cap

Head: this branch's `HEAD`; base: `origin/main`. Both run from throwaway copies
(`git archive HEAD` / `git archive origin/main`) under the pass's scratch directory, never
this checkout.

Rules the diff adds or changes:

1. **R-cap** (`hooks/allow-repo-commands.sh`, `orchestrator_moves_own_record`): for an
   orchestrator session, a line longer than `ORCHESTRATOR_MAX_LINE_CHARS` (20000) is never
   the outright-approved move of its own record. It now falls to the allowlist denial. A
   tightening.
2. **R-goahead** (`orchestration-start.sh` + `analysis/roots.py` + `hooks/shared_rules.py`
   `ROOTS_CLI_GO_AHEAD`): `roots.py start-refusal` and `roots.py self-write` let the start go
   on only on exit 0 printing exactly `ok`. Anything else refuses. A tightening.
3. **R-carry** (`conformance.py check-close --previous/--changed`, wired by
   `feature-close.sh`): a conformance downgrade is no longer a close refusal when the item
   was `done` last round, the review says `done`, and "no file either round's evidence
   names is among the changed paths". A loosening. Base refuses every such downgrade.

How each was run:

- R-cap: `self/tests/hook-orchestrator-role.sh` in each copy, with an attack block appended
  after H29 that sends each payload through the real hook. The consumer fixture, session S
  and its own stranded record `wave` were used, under both profiles. The same test file
  was copied into the base copy.
- R-goahead: `self/tests/consumer-record-guard.sh` (C7, `self-write`) and
  `self/tests/orchestration-records-in-repo.sh` (R14, `start-refusal`) in each copy, with
  extra stub `roots.py` variants added to the stub loop. The same files were copied into
  the base copy.
- R-carry: `python3 scratch/carry_attack.py`. It runs head `conformance.py check-close`
  with `--previous/--changed`, which is what head `feature-close.sh` passes from round 2
  on. It runs base `conformance.py check-close` on the same brief, review and current
  conformance report, which is what base `feature-close.sh` runs (base has no carry
  arguments). Brief: items 1, 2. Review: both `done`. Current conformance: item 1
  `partial`. Previous round: item 1 `done`. Rename behaviour of `feature-close.sh`'s
  `git diff --name-only` was checked in a scratch repo (`scratch/rename.sh`).

## Inputs tried

### R-cap: orchestrator session S, consumer fixture, `local` and `cloud` (same result in both)

`OWN_MOVE` = `git mv agentTooling/self/orchestrations/wave plans/orchestrations/wave`.
`REMEDY` = `mkdir -p plans/orchestrations && ` + `OWN_MOVE`.

| input | len | head | base |
|---|---|---|---|
| `OWN_MOVE` | 70 | allow (move) | allow (move) |
| `REMEDY` | 103 | allow | allow |
| `OWN_MOVE` space-padded to cap−1 | 19999 | allow | allow |
| `OWN_MOVE` space-padded to cap | 20000 | allow | allow |
| `OWN_MOVE` space-padded to cap+1 | 20001 | deny (allowlist) | allow |
| `OWN_MOVE` leading-space-padded to cap+1 | 20001 | deny | allow |
| `OWN_MOVE` tab-padded to cap+1 | 20001 | deny | allow |
| `OWN_MOVE` + repeated ` 2>/dev/null` past cap | 20074 | deny | deny |
| `OWN_MOVE` padded to 2×cap | 40000 | deny | allow |
| `OWN_MOVE` + U+3000 ideographic-space padding to cap+1 | 20001 | deny | allow |
| `REMEDY` padded to cap | 20000 | allow | allow |
| `REMEDY` padded to cap+1 | 20001 | deny | allow |
| `REMEDY` with the padding inside, before `&&`, to cap+1 | 20004 | deny | deny |
| `env ` + `OWN_MOVE` | 74 | deny | deny |
| `command ` + `OWN_MOVE` | 78 | deny | deny |
| `git 'mv' …` (quoted subcommand, same operands) | 72 | allow | allow |
| `OWN_MOVE ; true` | 77 | deny | deny |
| `OWN_MOVE` + newline + 20000 spaces | 20071 | deny | allow |

No input is more permissive on head. `git 'mv'` is the same command after shell quote
removal, the same move, so it is not a bypass.

### R-goahead: stub `analysis/roots.py`

`self-write` is the standalone `--self` start of `closed`. `start-refusal` is the start of
`idle-one` past a vendored record.

| stub | `self-write` head | `self-write` base | `start-refusal` head | `start-refusal` base |
|---|---|---|---|---|
| empty file (exit 0, no output) | refused (1), nothing written | went on (0), record written | refused (1), nothing written | went on (0), record written |
| `sys.exit(0)` | refused | refused* | refused | refused* |
| `print("go")` | refused | refused* | refused | refused* |
| `print("ok ")` | refused | refused* | refused | refused* |
| `print("OK")` | refused | refused* | refused | refused* |
| `print("ok"); print("x")` | refused | refused* | refused | refused* |
| `print("ok"); exit 1` | refused (prints `ok`) | refused* | refused | refused* |
| real `roots.py` (standalone `self-write x` / `start-refusal idle-one`) | exit 0, prints `ok` (C7/R14 ok) | — | exit 0, prints `ok` | — |

\* In the base run, the first stub had already written the record, so the later base rows
refused with "already exists". That says nothing about the stub. By the base code they go
on on exit 0, as the empty stub shows. Head refuses each one with "without its go-ahead",
before any write. No input is more permissive on head.

### R-carry: `check-close`, item 1 downgraded `done` → `partial`, review `done`

"should" is what the rule's own contract ("no file either round's evidence names is among
the changed paths") requires.

| case | previous evidence (item 1) | current evidence (item 1) | changed paths | should | head | base |
|---|---|---|---|---|---|---|
| C0 control | `hooks/a.py:12` | not convinced | `docs/other.md` | carry | carried (rc 0) | refused (rc 1) |
| C1 control | `hooks/a.py:12` | not convinced | `hooks/a.py` | refuse | refused | refused |
| C2 absolute path, previous | `/home/user/agentTooling/hooks/x.sh:5`, `README.md` | not convinced | `hooks/x.sh` | refuse | **carried** (anchor = `README.md` only) | refused |
| C3 absolute path, current | `README.md` | `/home/user/agentTooling/hooks/x.sh:5` drops the flag | `hooks/x.sh` | refuse | **carried** | refused |
| C4 directory | `hooks/` and `README.md` | not convinced | `hooks/x.sh` | refuse | **carried** | refused |
| C5 extensionless file | `Makefile` target and `README.md` | not convinced | `Makefile` | refuse | **carried** | refused |
| C6 space in path | `my dir/file.py:3` | not convinced | `my dir/file.py` | refuse | **carried** (anchor = `dir/file.py`) | refused |
| C7 digit-led extension | `docs/frob.1` and `README.md` | not convinced | `docs/frob.1` | refuse | **carried** | refused |
| C8 dotfile | `.gitignore` and `README.md` | not convinced | `.gitignore` | refuse | **carried** | refused |
| C9 non-ASCII name | `hooks/été.py` and `README.md` | not convinced | `"hooks/\303\251t\303\251.py"` (git's quoted form) | refuse | **carried** | refused |
| C10 `~` path | `~/agentTooling/hooks/x.sh` and `README.md` | not convinced | `hooks/x.sh` | refuse | **carried** | refused |
| C11 `./` prefix | `./hooks/x.sh` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| C12 vendored prefix | `agentTooling/hooks/x.sh` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| C13 single-char basename | `x.sh` | not convinced | `hooks/x.sh` | refuse | refused (no anchor) | refused |
| C14 `::symbol` suffix | `hooks/x.sh::main` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| C15 Markdown link | `[x](hooks/x.sh#L4)` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| C16 backslash separator | `hooks\x.sh` | not convinced | `hooks/x.sh` | refuse | refused (no anchor) | refused |
| C17 glob | `hooks/*.sh` and `README.md` | not convinced | `hooks/x.sh` | refuse | **carried** | refused |
| C18 case differs | `Hooks/X.sh` | not convinced | `hooks/x.sh` | carry on Linux (different path) | carried | refused |
| C19 renamed file | `old_name.py:3` | not convinced | `new_name.py` (the only path `git diff --name-only` prints for the rename `old_name.py` → `new_name.py`, rename detection on by default; confirmed by `scratch/rename.sh`, which prints only `b.py` for `git mv a.py b.py`) | refuse | **carried** | refused |

C0 and C18 are what the feature intends, not findings. The bold rows are inputs where the
evidence does name a file that changed, yet head carries the downgrade and lets the close
go on where base refuses.

Not attempted as an input: a forged commit whose subject is `<slug>: review round <N-1>`.
`feature-close.sh` takes the most recent commit with that subject as the previous round.
Base already trusts the same subject match for round N's own report, so this audit did not
pursue it.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | C2/C3/C10: an evidence cell names the changed file by absolute or `~` path (`/home/user/agentTooling/hooks/x.sh:5`, `~/agentTooling/hooks/x.sh`), previous round `done`, current `partial`, review `done`, `hooks/x.sh` changed | carried, check-close rc 0, close goes on | refused, rc 1 | `python3 scratch/carry_attack.py` (head: `head/conformance.py check-close --owner-brief brief.md --review rev.md --conformance C2.cur.md --previous C2.prev.md --changed C2.changed.txt`; base: `base/conformance.py check-close --owner-brief brief.md --review rev.md --conformance C2.cur.md`) |
| blocking | C5/C7/C8: the named changed file has no letter-led extension of a 2+-char basename (`Makefile`, `docs/frob.1`, `.gitignore`) | carried, rc 0 | refused, rc 1 | same script, cases C5, C7, C8 on each copy |
| blocking | C4/C17: the evidence names a directory (`hooks/`) or a glob (`hooks/*.sh`) under which a file changed | carried, rc 0 | refused, rc 1 | same script, cases C4, C17 on each copy |
| blocking | C6/C9: the named changed path holds a space (`my dir/file.py`) or non-ASCII (`hooks/été.py`, which git lists quoted) | carried, rc 0 | refused, rc 1 | same script, cases C6, C9 on each copy |
| blocking | C19: the previous evidence names a file the feature has since renamed (`old_name.py` → `new_name.py`); `feature-close.sh`'s `git diff --name-only` lists only the new name | carried, rc 0 | refused, rc 1 | same script, case C19 on each copy; `bash scratch/rename.sh` (prints only `b.py`) |

## Non-blocking findings

None.

## Blocking findings: reproduction and fix

All five are the R-carry rule. Each makes `check-close` (and so `feature-close.sh`) carry
a downgrade, and open the PR, although a file that either round's evidence names changed.
The rule's contract says it must not. Base refuses every one of these closes. Reproduce
each with `scratch/carry_attack.py`, or by hand: brief `## 1. A\n\n## 2. B`, a review with
both rows `done`, a previous conformance table with item 1 `done` and the "previous
evidence" cell, a current table with item 1 `partial` and the "current evidence" cell, and
the changed list. Run head `conformance.py check-close … --previous … --changed …` and it
exits 0 with a `carried` line.

1. **Absolute and `~` paths are never extracted** (C2, C3, C10). `EVIDENCE_PATH_RE`'s
   lookbehind `(?<![\w./-])` rejects every start position inside `/abs/path/file.sh`,
   because each is preceded by a word character or `/`. The leading `/` and `~` are
   outside the first-character class. So a file named by absolute path is no anchor and
   is not checked against the changed list, even when the current round's own evidence
   cites it as the reason for the downgrade (C3). Fix: let a match start at `/` or `~/`
   and strip a leading `<checkout root>/` or `~/…/` before comparing. Simpler and fail
   closed: if an evidence cell contains any path-like token the regex did not turn into an
   anchor (an absolute path, a directory, a glob, an unextracted word with `/`), carry
   nothing for that item.
2. **Extensionless, digit-extension and dotfile names are not anchors** (C5, C7, C8).
   When another named file is an anchor, the change to these goes unseen. Fix: under the
   fail-closed rule above, treat any unrecognised file-like token as "cannot prove
   unchanged". Or match tokens against the changed list directly (`token in changed` or a
   suffix match) as well as the regex.
3. **Directories and globs are ignored** (C4, C17). Fix: a token ending in `/`, or holding
   `*`/`?`/`[`, should test as touched when any changed path lies under it or matches it
   (`fnmatch`). Or it should block the carry.
4. **Paths with spaces or non-ASCII are truncated or dropped** (C6, C9). Also,
   `feature-close.sh` writes `git diff --name-only` output with git's default
   `core.quotePath`, which quotes non-ASCII names. Fix: run the diff with `-z` (or
   `-c core.quotePath=false`) and parse NUL-separated names. Match evidence by substring
   against each changed path, not only by the regex extraction.
5. **Renames hide the old path** (C19). `git diff --name-only PREV^ HEAD` uses rename
   detection by default, so a file the previous evidence named and the feature then
   renamed (or rewrote under a new name) is absent from `--changed`. Fix: add
   `--no-renames` to the `feature-close.sh` diff (`feature-close.sh`, the `git diff
   --name-only "$PREV_ROUND_SHA^" "$JUDGED_HEAD"` line) so both the deleted old path and
   the added new path are listed.

R-cap and R-goahead had no findings. Every attempt on head was as strict as base or
stricter.
