Verdict: escalated

# Security audit — close-after-filing, round 4

Files in the audit scope: `feature-close.sh`, `hooks/README.md`, `plan-runner-roots.sh`,
`self/gate.sh`, `templates/SECURITY_AUDIT.md`. The diff changes no rule in the PreToolUse
hook. It changes the rules in one lifecycle script, `feature-close.sh`, in the loop over the
commits after the judged head:

- **R1** (the `"$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX"` case, new). The close accepts a commit
  with the subject `<slug>: backlog` when `commit_changes_only "$sha" "$BACKLOG_REL"` holds:
  - the commit has one parent;
  - `git diff --no-renames --ignore-submodules=none --name-only -z "$sha^" "$sha"` lists the
    BACKLOG alone;
  - the BACKLOG is left at mode `100644`.

  The base refuses every commit under this subject.
- **R2** (the `"$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX"` case, changed). It now uses
  `commit_changes_only` with timing.jsonl.
- **R3** (the harness-records case, changed). `git show` now passes `--ignore-submodules=none`.
- **R4** (new this round). `export GIT_NO_REPLACE_OBJECTS=1` at the top of
  `feature-close.sh`. This is the fix for round 3's B3.
- `plan-runner-roots.sh` adds `BACKLOG_LABEL`, which R1 reads, and `--ignore-submodules=none`
  in `audit_paths_in_range`. `hooks/README.md` and `templates/SECURITY_AUDIT.md` change only
  prose. `self/gate.sh` adds one test to its list.

## Method

I made three throwaway copies under the scratch directory:

- `scratch/head`, from `git archive HEAD`;
- `scratch/base`, from `git archive origin/main`;
- `scratch/headfix`: head plus one line, `export GIT_GRAFT_FILE=/dev/null`, after the
  `GIT_NO_REPLACE_OBJECTS` export in `feature-close.sh`.

`scratch/attack.sh <copy> <case>...` builds a fixture from the copy in the shape of
`self/tests/close-backlog.sh`. The fixture is a feature that changes `docs-notes.txt`, reviewed
clean by the copy's own `run-review.sh` with a stub `claude`. Each case resets to the reviewed
stamps commit, adds its crafted commit(s) and local repository state, and runs the copy's
`./feature-close.sh --self feat`. A stray `stray.txt` stops the close at the stray check, which
runs after the head and audit checks. So:

- **allowed** means the close got past R1/R2 (the head check) and the audit-path check;
- **refused** means the loop refused the commit as unreviewed.

`PAYLOAD=` names the unreviewed file a case smuggles in: `hooks/policy.py`, an audit path, or
`docs-notes.txt`, which is not one.

The head copy's own `self/tests/close-backlog.sh` passes in full, K15a/K15b (the round-3
replace-ref cases) included.

## Inputs tried

| # | input (commit(s) and local repository state after the judged head) | head | base |
|---|---|---|---|
| B01 | `feat: backlog`, BACKLOG appended alone (the intended case) | allowed | refused |
| B02 | round-3 A08: `git replace <real> <fake>`. The real commit is `feat: backlog` changing `docs-notes.txt`; the fake is a BACKLOG-only `feat: backlog` | refused (R4 holds) | refused |
| B03 | B02 plus `core.useReplaceRefs=true` in local config | refused | refused |
| B04 | B02 run with `GIT_NO_REPLACE_OBJECTS=0` in the caller's environment | refused (the script's export wins) | refused |
| B05 | round-3 A09: the same replace attack with a timing.jsonl-only `feat: review stamps` | refused | allowed |
| B06 | **cyclic `.git/info/grafts`**, `PAYLOAD=docs-notes.txt`. R is the real `feat: backlog` commit changing `docs-notes.txt` and the BACKLOG, on parent J (the stamps commit). F is a fabricated commit whose tree is R's tree without the BACKLOG change. Grafts: `R F`, `F JD`, `JD JD^ F`, where JD is the judged head. Results: `rev-list J..HEAD` lists R alone; `merge-base --is-ancestor JD HEAD` holds; `diff R^ R` lists the BACKLOG alone | **allowed** | refused |
| B06full | B06, with the full close (no stray file) | the close runs on past the head, audit and stray checks to the PR step ("the PR is open"). A `git push origin claude/feat` then lands `feat: backlog` carrying `docs-notes.txt` on origin | — |
| B06f | B06 against `scratch/headfix` (`GIT_GRAFT_FILE=/dev/null`) | refused | — |
| B07 | B06 with `PAYLOAD=hooks/policy.py` | refused, by the audit-path check (`hooks/policy.py changed after the review judged this feature`): that check diffs trees across the range, so a graft cannot hide an audit path | — |
| B08 | B06 under `feat: review stamps`, timing.jsonl in place of the BACKLOG, `PAYLOAD=docs-notes.txt` | allowed | allowed |
| B08f | B08 against `scratch/headfix` | refused | — |
| B09 | `.git/shallow` naming the commit under a `feat: backlog` commit | refused (the judged sha is not in the branch's history) | refused (same) |
| B10 | forged `objects/info/commit-graph`: R's root-tree oid patched to a BACKLOG-only tree, `feat: backlog`, `PAYLOAD=docs-notes.txt` | refused (the diff still lists `docs-notes.txt`) | refused |
| B11 | B10 under `feat: review stamps` | refused | allowed |
| B12 | B10 with `PAYLOAD=hooks/policy.py` | refused | — |
| B13 | a BACKLOG-only `feat: backlog`, then a `docs-notes.txt` commit also under `feat: backlog` | refused | refused |
| B14 | subject `feat: backlog` plus a body, BACKLOG alone | allowed | refused |
| B15 | subject `feat: backlog\r` (`--cleanup=verbatim`), BACKLOG alone | allowed | refused |
| B16 | subject ` feat: backlog` (leading space), BACKLOG alone | refused | refused |
| B17 | `feat: backlog` turning `self/BACKLOG.md` into a directory | refused | refused |
| B18 | `feat: backlog` adding `self/BACKLOG.md.x` | refused | refused |
| B19 | `feat: backlog`, BACKLOG alone, with `.git/info/attributes` naming a smudge filter on it | allowed | — |

Notes on these results:

- **Not findings:** B01, B14, B15 and B19. B01 is the relaxation the feature intends. In B14
  and B15 the subject is only a label: the content check is what guards, and it holds. In B19
  the close never checks the file out. A marker file the filter writes did appear, but my own
  harness made it with its `checkout -f` between cases, not the close.
- **R4 holds** (B02–B05). The round-3 fix also turns B05 and B11, which the base allowed, into
  refusals.
- **Grafts are not covered by R4.** On git 2.43, `GIT_NO_REPLACE_OBJECTS=1` leaves
  `.git/info/grafts` in force: the diff under that variable still lists the BACKLOG alone in
  B06.
- **Why B06 works when round 3's A10b did not.** A10b grafted away a merge parent, so the tree
  difference stayed visible. B06 needs a cycle instead. F is reachable from JD, so `log JD..HEAD`
  never lists it, and JD is reachable from R through F, so the ancestry check holds.
  `commit_changes_only` diffs R against its grafted parent F, which differs only in the BACKLOG.
- **The range-wide audit-path check still catches any audit path (B07).** So B06 smuggles only
  non-audit files: docs, scripts outside the audit list, a consuming repo's source. The close
  exists to refuse exactly that: "a change no review has read".

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | B06: a cyclic `.git/info/grafts` (`R F`, `F JD`, `JD JD^ F`). It makes an unreviewed `feat: backlog` commit R, changing `docs-notes.txt` and `self/BACKLOG.md`, look like a BACKLOG-only change against a fabricated parent F | allowed: the close passes the head, audit and stray checks, and the pushed branch carries R's `docs-notes.txt` change | refused: `'feat: backlog' landed after the review judged this feature` | `PAYLOAD=docs-notes.txt bash scratch/attack.sh scratch/head graft_backlog` vs `PAYLOAD=docs-notes.txt bash scratch/attack.sh scratch/base graft_backlog` |
| non-blocking | B08: the same graft attack under `feat: review stamps`, timing.jsonl in place of the BACKLOG (pre-existing silent allow) | allowed | allowed | `PAYLOAD=docs-notes.txt bash scratch/attack.sh scratch/head graft_stamps` vs `PAYLOAD=docs-notes.txt bash scratch/attack.sh scratch/base graft_stamps` |

## Non-blocking findings

- **B08, a pre-existing silent allow.**
  - **The attack.** Take an unreviewed commit that touches non-audit files and is committed
    under `<slug>: review stamps` with a timing.jsonl change. A cyclic `.git/info/grafts` can
    make it diff as timing.jsonl alone against a fabricated parent.
  - **Results.** Head and base both get past the head check.
  - **Should do instead.** Read history with grafts off, as with replace refs. Export
    `GIT_GRAFT_FILE=/dev/null` beside `GIT_NO_REPLACE_OBJECTS=1` at the top of
    `feature-close.sh`. A further option is to refuse when `$GIT_DIR/info/grafts` exists. I
    verified the export on `scratch/headfix`: B08f is refused.
  - **File in.** `self/BACKLOG.md`, if the blocking fix below does not land in this feature.
    The same line fixes both, so it should land here.

## Blocking findings: reproduction and remedy

**B06: a cyclic graft makes an unreviewed commit look like a `<slug>: backlog` commit.**

The base refuses every commit under the backlog subject, whatever its content. On this head,
R1 judges the commit's content against its parent. Round 3's fix turned replace refs off, but
the parent is still resolved through `.git/info/grafts`, which `GIT_NO_REPLACE_OBJECTS` does
not disable on git 2.43. The push sends the real commit. For this input the result is
"refused" on the base and "allowed" on the head: a regression under the plan's rule.

To reproduce, on a feature reviewed clean, with stamps commit `J`, judged head `JD = J^` and
`JDP = JD^`:

```
# fabricated parent: J's tree plus the payload, never pushed
git checkout --detach J && echo '# payload' >> docs-notes.txt && git commit -qam x
T=$(git rev-parse 'HEAD^{tree}'); git checkout -f claude/<slug>
F=$(git commit-tree "$T" -p "$JDP" -m x)
# the real commit: payload + BACKLOG
echo '# payload' >> docs-notes.txt; echo '- finding' >> self/BACKLOG.md
git commit -qam "<slug>: backlog"; R=$(git rev-parse HEAD)
printf '%s %s\n%s %s\n%s %s %s\n' "$R" "$F" "$F" "$JD" "$JD" "$JDP" "$F" > .git/info/grafts
./feature-close.sh --self <slug>     # passes the head check; the push carries R with docs-notes.txt
```

**What the rule should do instead.** Never resolve parents through grafts in the close. Export
`GIT_GRAFT_FILE=/dev/null` next to `GIT_NO_REPLACE_OBJECTS=1` at the top of
`feature-close.sh`, before its first git call. Alternatively, refuse the close outright when
`$(git rev-parse --git-path info/grafts)` exists, or when `.git/shallow` exists.

I verified the export on a patched copy: B06f and B08f are both refused, and B01 (the intended
case) is still allowed. Add a case beside K15 in `self/tests/close-backlog.sh`: an unreviewed
non-audit change hidden by a cyclic graft must be refused under `feat: backlog` and under
`feat: review stamps`.
