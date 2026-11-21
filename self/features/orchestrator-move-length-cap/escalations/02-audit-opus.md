Verdict: escalated

# Security audit (round 2): orchestrator-move-length-cap

Head is this branch's `HEAD` (`3c95525`). Base is `origin/main`. Both ran from throwaway
copies under the pass's scratch directory (`git archive HEAD`, `git archive origin/main`),
never from this checkout.

Rules the diff adds or changes:

1. **R-cap** (`hooks/allow-repo-commands.sh`, `orchestrator_moves_own_record`): for an
   orchestrator session, a line longer than `ORCHESTRATOR_MAX_LINE_CHARS` (20000) is never
   the outright-approved move of its own record. It tightens the hook.
2. **R-goahead** (`orchestration-start.sh`, `analysis/roots.py`, and `ROOTS_CLI_GO_AHEAD`
   in `hooks/shared_rules.py`): `roots.py start-refusal` and `roots.py self-write` let the
   start go on only when they exit 0 and print exactly `ok`. It tightens the start.
3. **R-carry** (`conformance.py check-close --tracked/--round`, wired by
   `feature-close.sh`): a conformance downgrade is no longer a close refusal when three
   things hold. The review says `done`. The newest earlier round that said `done` named a
   file tracked at head. No evidence for the item, from that round through this one, is
   "about" a path changed since that round. The docstring defines "about" as the path,
   its file name, its module stem, a folder holding it written `<folder>/`, or a glob
   matching it. This rule loosens the close: base refuses every downgrade.

`git diff --stat cd493a6 HEAD` shows that since round 1's audit, only `conformance.py`
and `feature-close.sh` changed among the audited files. Round 1 attacked R-cap and
R-goahead on byte-identical code. Its tables (in `escalations/01-audit-opus.md`) found
nothing, and this round did not repeat them. Both rules were confirmed again on the head
copy:

- `self/tests/hook-orchestrator-role.sh` passes. It includes the cap−1/cap/cap+1 move
  checks.
- `self/tests/consumer-record-guard.sh` passes. It includes C7, the stub `roots.py` that
  exits 0 with no go-ahead and is refused.
- `self/tests/orchestration-records-in-repo.sh` passes.

How R-carry was attacked:

- `python3 scratch/carry_attack.py` runs head `conformance.py check-close` with
  `--tracked <NUL list> --round <report> <NUL changed list> …`, which is what head
  `feature-close.sh` passes.
- On the same brief, review and current report, it runs base `conformance.py check-close`,
  which is what base `feature-close.sh` runs (base has no carry).
- The brief has items 1 and 2, and the review marks both `done`. The current report marks
  item 1 `partial`, unless a row says otherwise.
- The tracked list is `README.md hooks/x.sh hooks/a.py b.py Makefile docs/frob.1
  .gitignore "my dir/file.py" hooks/été.py docs/other.md new_name.py lib/util.py`.
- The wiring was checked separately with `bash scratch/wiring.sh`. It builds a scratch
  repo and runs `feature-close.sh`'s exact round lookup (`awk` on `%H %s`) and diff
  (`git diff -z --no-renames --name-only SHA^ HEAD -- . ":(exclude)<feature>/"`). The
  output lists both `old_name.py` and `new_name.py` for a `git mv`, lists `hooks/été.py`
  unquoted, and omits the feature directory.

## Inputs tried

### R-carry

"should" is what the rule's own documented contract requires.

| case | earlier-round evidence (item 1, `done` unless noted) | current evidence | changed since that round | should | head | base |
|---|---|---|---|---|---|---|
| A0 control | `hooks/a.py:12` | not convinced | `docs/other.md` | carry | carried (0) | refused (1) |
| A1 control | `hooks/a.py:12` | not convinced | `hooks/a.py` | refuse | refused | refused |
| R1-C2 absolute, earlier | `/home/user/agentTooling/hooks/x.sh:5, README.md` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| R1-C3 absolute, current | `README.md` | `/home/user/agentTooling/hooks/x.sh:5 drops the flag` | `hooks/x.sh` | refuse | refused | refused |
| R1-C4 directory | `` `hooks/` `` and README.md | not convinced | `hooks/x.sh` | refuse | refused | refused |
| R1-C5 extensionless | `Makefile target, README.md` | not convinced | `Makefile` | refuse | refused | refused |
| R1-C6 space | `my dir/file.py:3` | not convinced | `my dir/file.py` | refuse | refused | refused |
| R1-C7 digit extension | `docs/frob.1 and README.md` | not convinced | `docs/frob.1` | refuse | refused | refused |
| R1-C8 dotfile | `.gitignore and README.md` | not convinced | `.gitignore` | refuse | refused | refused |
| R1-C9 non-ASCII | `hooks/été.py and README.md` | not convinced | `hooks/été.py` (NUL list) | refuse | refused | refused |
| R1-C10 `~` | `~/agentTooling/hooks/x.sh and README.md` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| R1-C16 backslash | `hooks\x.sh, README.md` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| R1-C17 glob | `hooks/*.sh and README.md` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| R1-C19 rename | `old_name.py:3, README.md` | not convinced | `old_name.py`, `new_name.py` (`--no-renames`) | refuse | refused | refused |
| N1 bare glob ending a sentence | `README.md; covers every *.sh.` | not convinced | `hooks/x.sh` | refuse (a glob matching it) | **carried (0)** | refused (1) |
| N2 bare glob before a colon | `README.md; *.sh: all checked` | not convinced | `hooks/x.sh` | refuse | **carried (0)** | refused (1) |
| N3 brace glob | `README.md; *.{sh,py}` | not convinced | `hooks/x.sh` | refuse | **carried (0)** | refused (1) |
| N4 folder, no slash | `README.md; every file in hooks` | not convinced | `hooks/x.sh` | carry (contract: `<folder>/`) | carried | refused |
| N5 symbol only | `README.md; orchestrator_moves_own_record` | not convinced | `hooks/x.sh` | carry (contract: text about a path) | carried | refused |
| N6 stem only | `README.md; module x` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| N7 NFD spelling of a changed name | `hooks/été.py and README.md` (NFD) | not convinced | `hooks/été.py` (NFC) | refuse | **carried (0)** | refused (1) |
| N8 later round partial cites changed file | newest: `hooks/x.sh broke it` (partial), changed `[]`; older: `README.md` (done) | not convinced | older's: `hooks/x.sh` | refuse | refused | refused |
| N9 newest done anchors | newest: `README.md` (done), changed `[]`; older: `hooks/x.sh` (done) | not convinced | older's: `hooks/x.sh` | carry | carried | refused |
| N10 anchor deleted | `gone.py:3` | not convinced | `gone.py` | refuse | refused | refused |
| N11 current cites changed file by basename | `README.md` | `see util.py` | `lib/util.py` | refuse | refused | refused |
| N12 current report has no row for item 1 | `README.md` | (no row) | `hooks/x.sh` | carry | carried | refused |
| N13 duplicate earlier rows (done + partial) | `README.md` done, `hooks/x.sh` partial | not convinced | `hooks/x.sh` | refuse | refused | refused |
| N14 Markdown link | `[here](hooks/x.sh#L4), README.md` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| N15 escaped pipe | `README.md \| hooks/x.sh` | not convinced | `hooks/x.sh` | refuse | refused | refused |
| N16 folder written `hooks/.` | `README.md; hooks/.` | not convinced | `hooks/x.sh` | refuse (a folder holding it) | **carried (0)** | refused (1) |
| N17 absolute folder, no slash | `README.md; /home/user/agentTooling/hooks` | not convinced | `hooks/x.sh` | carry (contract: `<folder>/`) | carried | refused |
| N18 review says partial | `README.md` | not convinced | `[]` | refuse | refused | refused |

Notes on the table:

- **Round 1's findings are fixed.** All 13 of round 1's bypass inputs (C2 to C10, C17,
  C19) now refuse.
- **Expected carries.** A0, N9 and N12 carry because the feature intends them.
- **Not findings, but open questions.** N4, N5 and N17 carry by the rule's stated
  contract, which counts a folder only when written `<folder>/` and does not count
  symbols. They are listed so the owner can decide whether that contract is wide enough.
- **Bold rows are the findings.** In each, the evidence is "about" a changed path in the
  contract's own terms (a glob matching it, or a folder holding it), or names the changed
  file in another Unicode normalisation. Head still carries the downgrade, and the close
  goes on where base refuses.

### R-cap and R-goahead

The code is unchanged since round 1's audit, which recorded 18 R-cap inputs and 7 stub
`roots.py` variants on each rule (see `escalations/01-audit-opus.md`). Head was as strict
as base on every one, or stricter. This round re-ran the head copy's
`hook-orchestrator-role.sh`, `consumer-record-guard.sh` and
`orchestration-records-in-repo.sh`, and all checks passed.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | N1/N2: earlier `done` evidence `README.md; covers every *.sh.` (or `*.sh: …`), current `partial`, review `done`, `hooks/x.sh` changed | carried, check-close rc 0, close goes on | refused, rc 1 | `python3 scratch/carry_attack.py` (head: `head/conformance.py check-close --owner-brief brief.md --review rev.md --conformance cur.md --tracked tracked.bin --round round.md changed.bin`; base: `base/conformance.py check-close --owner-brief brief.md --review rev.md --conformance cur.md`) |
| blocking | N3: earlier evidence `README.md; *.{sh,py}`, `hooks/x.sh` changed | carried, rc 0 | refused, rc 1 | same script, case N3 on each copy |
| blocking | N16: earlier evidence `README.md; hooks/.`, `hooks/x.sh` changed | carried, rc 0 | refused, rc 1 | same script, case N16 on each copy |
| blocking | N7: earlier evidence names `hooks/été.py` in NFD, the changed list holds it in NFC | carried, rc 0 | refused, rc 1 | same script, case N7 on each copy |

## Non-blocking findings

None.

## Blocking findings: reproduction and fix

All four are R-carry. Base refuses every one of these closes. To reproduce each with
`scratch/carry_attack.py`, or by hand:

- Brief: `## 1. A\n\n## 2. B`.
- Review: both rows `done`.
- Earlier round's conformance: item 1 `done`, with the evidence shown.
- Current conformance: item 1 `partial`.
- Tracked list: holds `README.md`. Changed list: `hooks/x.sh`.

Head `conformance.py check-close … --tracked … --round …` then exits 0 with a `carried`
line.

1. **A glob followed by punctuation is not matched** (N1, N2). `GLOB_TOKEN_RE`
   (`[^\s'"(),;]+`) keeps a trailing `.` or `:` in the token, so `*.sh.` and `*.sh:` never
   `fnmatch` `hooks/x.sh`. `hooks/*.sh.` is caught only by the folder test.
   - Fix: strip trailing `.:!?` (and a `:<digits>` line suffix) from each glob token
     before matching.
   - Fail-closed alternative: when a token holds a glob character and matches no tracked
     path at all, treat the item as touched.
2. **Brace patterns are not globs to `fnmatch`** (N3). `*.{sh,py}` is split at the comma,
   and neither half matches.
   - Fix: expand `{a,b}` groups in a token before matching. Or treat any token holding `{`
     together with a glob character as touched.
3. **A folder written `<folder>/.`** (N16). `FOLDER_AFTER` rejects a following `.`, so
   `hooks/.` (and `hooks/./`) is not seen as the folder.
   - Fix: accept `<folder>/` followed by `.` when that `.` is followed by a non-name
     character or `/`. Or normalise `/./` and a trailing `/.` out of the evidence text
     before matching.
4. **Unicode normalisation** (N7). The evidence and the git path are compared as raw code
   points.
   - Fix: apply `unicodedata.normalize("NFC", …)` to the evidence text, the tracked list
     and the changed list before any comparison.

Inputs N4, N5 and N17 (a folder named without a trailing slash, or only a symbol inside a
changed file) carry by the rule's stated contract, so they are not findings. If the owner
wants them to refuse, the contract has to widen. One option: count a bare folder name
standing alone when any changed path lies under it.
