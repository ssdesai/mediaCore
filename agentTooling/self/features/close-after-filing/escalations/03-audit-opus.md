Verdict: escalated

# Security audit — close-after-filing, round 3

Files in the audit scope: `feature-close.sh`, `hooks/README.md`, `plan-runner-roots.sh`,
`self/gate.sh`, `templates/SECURITY_AUDIT.md`. The diff changes no rule in the PreToolUse hook.
It changes the rules in one lifecycle script, `feature-close.sh`, in the loop over the commits
after the judged head:

- **R1** (the `"$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX"` case, new). The close accepts a commit with
  the subject `<slug>: backlog` when `commit_changes_only "$sha" "$BACKLOG_REL"` holds. That
  check requires one parent, a `git diff --no-renames --ignore-submodules=none --name-only -z`
  that lists the BACKLOG alone (compared past a sentinel), and mode `100644`. The base refuses
  every commit under this subject. R1 should refuse any change other than the BACKLOG file alone.
- **R2** (the `"$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX"` case, changed). The base compared
  `git show --name-only` with `timing.jsonl`. This head uses `commit_changes_only` instead.
- **R3** (the harness-records case, changed). `git show` now passes `--ignore-submodules=none`.
- `plan-runner-roots.sh` adds `BACKLOG_LABEL`, which R1 reads, and `--ignore-submodules=none` in
  `audit_paths_in_range`. `hooks/README.md` and `templates/SECURITY_AUDIT.md` change only prose.
  `self/gate.sh` adds one test to its list.

## Method

I made two throwaway copies under the scratch directory: `scratch/head` from `git archive HEAD`
and `scratch/base` from `git archive origin/main`. `scratch/attack.sh <copy>` builds a fixture
from the copy in the shape of `self/tests/close-backlog.sh`: a feature that changes
`docs-notes.txt`, reviewed clean by the copy's own `run-review.sh` with a stub `claude`. Each case
resets to the reviewed stamps commit, adds the crafted commit(s), and runs the copy's
`./feature-close.sh --self feat`. A stray `stray.txt` stops the close at the stray check, which
runs after the head check. So:

- **allowed** means the close got past R1/R2 (the head check).
- **refused** means the loop refused the commit as unreviewed.

`scratch/attack2.sh <copy> backlog|stamps` runs the replace-object case through a **full close**,
with no stray file, and then pushes the fixture branch to its bare origin to show what lands
there. `scratch/headfix` is head plus one line, `export GIT_NO_REPLACE_OBJECTS=1`, near the top of
`feature-close.sh`; I used it to test the remedy. The scratch directory is removed when this pass
ends; the reproduction below needs none of it.

The head copy's own `self/tests/close-backlog.sh` passes in full, K13 and K14 included.

## Inputs tried

| # | input (commit(s) after the judged head) | head | base |
|---|---|---|---|
| A01 | `feat: backlog`, BACKLOG appended alone (the intended case) | allowed | refused |
| A02 | `feat: backlog`, BACKLOG + gitlink `sub`; untracked, excluded `.gitmodules` with `ignore = all` (round-2 B2/S1) | refused | refused |
| A03 | `feat: backlog`, BACKLOG + gitlink `hooks/sub`; local `diff.ignoreSubmodules=all` (round-2 S2) | refused | refused |
| A04 | `feat: backlog`, BACKLOG + gitlink `sub`; `submodule.sub.ignore=all` in local config, not in `.gitmodules` | refused | refused |
| A05 | `feat: review stamps`, timing.jsonl + gitlink `sub`, hidden by the excluded `.gitmodules` (round-2 S4) | refused | allowed |
| A06 | `feat: review stamps`, timing.jsonl made executable (round-2 C24) | refused | allowed |
| A07 | `feat: backlog`, the BACKLOG path itself turned into a gitlink, under `diff.ignoreSubmodules=all` | refused | refused |
| A08 | `git replace <real> <fake>`. Real: `feat: backlog` changing `hooks/policy.py`. Fake: `feat: backlog` appending to the BACKLOG alone, same parent | **allowed**. The full close reports "closing the tree it judged", and the branch pushed to origin is the real commit carrying the `hooks/policy.py` change | refused (unreviewed) |
| A08f | A08 against `scratch/headfix` | refused | — |
| A09 | as A08, but the fake is a `feat: review stamps` timing.jsonl append, and the real commit is `feat: review stamps` | allowed (full close) | allowed (full close) |
| A09b | as A09, but the real commit is `feat: change hooks` | allowed | allowed |
| A09f | A09 against `scratch/headfix` | refused | — |
| A10 | first attempt at a graft case; the merge did not form, so this was A01 again | allowed (not a graft; ignore) | refused |
| A10b | real merge `feat: backlog` bringing in a `hooks/policy.py` change; `.git/info/grafts` drops its second parent | refused. The graft applies, but the tree still differs in `hooks/policy.py` | refused |
| A11 | `feat: backlog ` (trailing space), BACKLOG alone | allowed: `read` trims the subject, and the content check holds | refused |
| A12 | `Feat: backlog`, BACKLOG alone | refused | refused |
| A13 | `feat: backlog`, a new `self/backlog.md` (wrong case) | refused | refused |
| A14 | `feat: backlog`, BACKLOG + `hooks/policy.py` | refused | refused |
| A15 | as A14, with `diff.relative=true` in local config | refused | refused |
| A16 | an empty commit under `feat: backlog` | refused | refused |
| A17 | `feat: backlog`, a new `SELF/BACKLOG.md` | refused | refused |
| A18 | `feat: backlog`, BACKLOG + a gitlink `sub` with nothing hiding it | refused | refused |

Notes on these results:

- **Not findings:** A01 and A11 are the relaxation the feature intends. The subject is only a
  label; the content check is what guards, and it holds.
- **The round-2 fixes hold:** A02–A07 and A18. `--ignore-submodules=none` overrides
  `.gitmodules`, config `submodule.*.ignore` and `diff.ignoreSubmodules`. A05 and A06 are now
  refused where the base allowed them, so the round-2 non-blocking findings S4 and C24 are fixed
  too.
- **Grafts are not a bypass (A10b).** A graft changes only parents, never a tree. The diff against
  the grafted parent still lists every path the pushed tree changes.
- **Replace refs are a bypass (A08, A09).** Round 1 set them aside because "they are local refs
  the push does not carry". That reasoning is backwards. The close reads history *through* the
  local replacement, but the push sends the real objects. So the remote receives a commit that no
  check saw.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | A08: `git replace <real> <fake>`. `<real>` is `feat: backlog` (any subject works) changing `hooks/policy.py`. `<fake>` is `feat: backlog` appending to `self/BACKLOG.md` alone, on the same parent. Index and worktree are resynced with `git read-tree -u --reset HEAD` | allowed: the full close reports "closing the tree it judged", and `git push origin claude/feat` lands the real commit with the unreviewed `hooks/policy.py` change | refused: `'feat: backlog' landed after the review judged this feature` | `bash scratch/attack2.sh scratch/head backlog` vs `bash scratch/attack2.sh scratch/base backlog` |
| non-blocking | A09/A09b: the same replace attack with a fake `feat: review stamps` commit that appends to timing.jsonl alone (pre-existing silent allow) | allowed (full close) | allowed (full close) | `bash scratch/attack2.sh scratch/head stamps` vs `bash scratch/attack2.sh scratch/base stamps` |

## Non-blocking findings

- **A09/A09b, a pre-existing silent allow.** Any unreviewed commit after the judged head can be
  shadowed by a local `refs/replace/<sha>` that points at a fake `<slug>: review stamps` commit.
  The fake appends to timing.jsonl alone. Every `git log`, `git diff` and `git show` in
  `feature-close.sh` reads the fake, while `git push` sends the real commit. Both head and base
  run the close to the end.
  - **Should do instead:** read history with replace refs off. Export `GIT_NO_REPLACE_OBJECTS=1`
    at the top of `feature-close.sh`, ahead of every git call, or pass `--no-replace-objects` to
    each git call. I verified the export on `scratch/headfix` (A09f): refused.
  - **File in:** `self/BACKLOG.md`, if the blocking fix below does not land in this feature. The
    same line fixes both, so it should land here.

## Blocking findings: reproduction and remedy

**B3 (A08): a local replace ref makes an unreviewed commit look like a `<slug>: backlog`
commit.**

The base refuses every commit under the backlog subject, whatever its content. On this head, R1
judges the commit's content, but it reads that content through `refs/replace/`. So R1 checks a
stand-in commit that is never pushed. This is a regression for this input, which is what the
plan's rule asks about. The base still lets the same attack in under the stamps subject (A09,
non-blocking above), so this is not a new capability. But the plan's rule classes by the result
for the same input, and for this input the base refuses.

To reproduce, on a feature reviewed clean with judged head `R`:

```
echo '# payload' >> hooks/policy.py && git add hooks && git commit -m "<slug>: backlog"   # real
real=$(git rev-parse HEAD)
git checkout --detach R
echo '- finding' >> self/BACKLOG.md && git add self/BACKLOG.md && git commit -m "<slug>: backlog"   # fake
fake=$(git rev-parse HEAD)
git checkout claude/<slug>
git replace "$real" "$fake"
git read-tree -u --reset HEAD          # status now clean
./feature-close.sh --self <slug>       # "closing the tree it judged"; the push carries $real
```

**What the rule should do instead.** Never resolve history through replace refs in the close.
Put `export GIT_NO_REPLACE_OBJECTS=1` near the top of `feature-close.sh`, before its first git
call. Consider the same line for `plan-runner-roots.sh`'s `audit_paths_in_range` callers and
`run-review.sh`'s judged-head stamping. I verified the export on a patched copy: A08f and A09f
are both refused as unreviewed. Add a case beside K13 in `self/tests/close-backlog.sh`: an
unreviewed commit shadowed by a replace ref to a BACKLOG-only `feat: backlog` commit must be
refused, and so must one shadowed by a timing.jsonl-only `feat: review stamps` commit.
