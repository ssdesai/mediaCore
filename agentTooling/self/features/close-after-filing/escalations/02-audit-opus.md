Verdict: escalated

# Security audit — close-after-filing, round 2

Files in the audit scope: `feature-close.sh`, `hooks/README.md`, `plan-runner-roots.sh`,
`self/gate.sh`, `templates/SECURITY_AUDIT.md`. The diff changes no rule in the PreToolUse hook.
It changes the rules in one lifecycle script:

- **R1** (`feature-close.sh`, the post-judged-head loop, `"$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX"`
  case). A commit after the judged head is accepted under the subject `<slug>: backlog` when
  `commit_changes_only "$sha" "$BACKLOG_REL"` holds and `ls-tree` shows the BACKLOG as `100644`.
  `commit_changes_only` holds when the commit has one parent and
  `git diff --no-renames --name-only -z` lists that one path, compared past a sentinel. The base
  refuses every commit under this subject. R1 is meant to refuse any change other than the
  BACKLOG file alone.
- **R2** (`feature-close.sh`, the `"$FEATURE_SLUG$STAMPS_COMMIT_SUFFIX"` case). The base compared
  `git show --name-only` with `timing.jsonl`. This head uses `commit_changes_only` instead, which
  adds the one-parent check, turns off renames, and compares past the sentinel.
- `plan-runner-roots.sh` only adds `BACKLOG_LABEL`, the data R1 reads. `hooks/README.md` and
  `templates/SECURITY_AUDIT.md` change only prose. `self/gate.sh` adds one test to its list.
  None of these four adds a rule of its own.

## Method

I made two throwaway copies under the scratch directory, `scratch/head` (from `git archive HEAD`)
and `scratch/base` (from `git archive origin/main`). `scratch/attack.sh <copy> [sub]` builds
fixtures from a copy, in the shape of `self/tests/close-backlog.sh`:

- **plain:** a feature that changes `docs-notes.txt`.
- **hook:** a feature that changes `hooks/allow-repo-commands.sh`.

Each fixture is reviewed clean by the copy's own `run-review.sh`, using a stub `claude`. Each case
then resets to the reviewed stamps commit, adds the crafted commit(s), and runs the copy's
`./feature-close.sh --self feat`. Unless a case says otherwise, a stray `stray.txt` stops the close
at the stray check, which runs after the head check and the audit checks. So:

- **allowed** means the close got past R1/R2 and every audit check.
- **refused** means the loop refused the commit as unreviewed.

Commands:

- `bash /tmp/plan-capture.10p3zO/scratch/attack.sh /tmp/plan-capture.10p3zO/scratch/head`
- `bash /tmp/plan-capture.10p3zO/scratch/attack.sh /tmp/plan-capture.10p3zO/scratch/base`
- the same two commands with a second argument `sub`, for cases S1–S4

`<LF>` below is a literal newline character inside a path name.

## Inputs tried

| # | input (commit(s) after the judged head) | head | base |
|---|---|---|---|
| C01 | `feat: backlog`, BACKLOG appended alone (the intended case) | allowed | refused |
| C02 | `feat: backlog`, new file `self/BACKLOG.md<LF>` alone (round-1 B1) | refused | refused |
| C03 | `feat: backlog`, executable `self/BACKLOG.md<LF><LF>` alone (round-1 B1) | refused | refused |
| C04 | `feat: backlog`, new file `self/BACKLOG.md<LF>.`, which spoofs the sentinel | refused | refused |
| C05 | `feat: backlog`, BACKLOG appended + new `self/BACKLOG.md<LF>` | refused | refused |
| C06 | `feat: backlog`, new file `self/BACKLOG.md<LF>.<LF>` | refused | refused |
| C07 | `feat: backlog`, `docs-notes.txt` renamed onto the BACKLOG | refused | refused |
| C08 | `feat: backlog`, BACKLOG + `hooks/policy.py` renamed to `self/new.md` | refused | refused |
| C09 | `feat: backlog`, BACKLOG turned into a gitlink (160000) | refused | refused |
| C10 | `feat: backlog`, BACKLOG replaced by a directory `self/BACKLOG.md/x` | refused | refused |
| C11 | `feat: backlog`, BACKLOG made executable | refused | refused |
| C12 | `feat: backlog`, BACKLOG turned into a symlink to `hooks/policy.py` | refused | refused |
| C13 | `feat: backlog`, BACKLOG deleted | refused | refused |
| C14 | merge under `feat: backlog`, whose first-parent diff is the BACKLOG alone | refused | refused |
| C15 | message `feat:\nbacklog` (`%s` reads `feat: backlog`), BACKLOG alone | allowed | refused |
| C16 | empty commit under `feat: backlog` | refused | refused |
| C17 | `feat: backlog`, BACKLOG + `hooks/policy.py` | refused | refused |
| C18 | `feat: backlog`, BACKLOG + a new gitlink `sub`; an untracked worktree `.gitmodules` says `ignore = all` | **allowed** | refused |
| C19 | as C18, but the gitlink replaces `hooks/policy.py` (a typechange) | refused | refused |
| C20 | a valid backlog commit, then `docs-notes.txt` under the same subject | refused | refused |
| C21 | `feat: backlog`, new `plans/BACKLOG.md` (the wrong layout's file) | refused | refused |
| C22 | `feat: review stamps`, new file `self/features/feat/timing.jsonl<LF>` | refused | refused |
| C23 | `feat: review stamps`, timing.jsonl removed and `hooks/policy.py` moved onto it | inconclusive: the close refused earlier, "recorded 'no verdict'", because the fixture's verdict lookup needs timing.jsonl | the same |
| C24 | `feat: review stamps`, timing.jsonl made executable | allowed | allowed |
| C25 | `feat: review stamps`, a merge that brings in a `docs-notes.txt` change | refused | refused |
| C26 | `feat: review stamps`, timing.jsonl appended (the intended case) | allowed | allowed |
| H01 | hook fixture: BACKLOG appended under `feat: backlog` (the intended case) | allowed, with the audit line printed | refused |
| H02 | hook fixture: BACKLOG + `hooks/allow-repo-commands.sh` | refused | refused |
| H03 | hook fixture: BACKLOG + `audit-report.md` rewritten | refused | refused |
| H04 | hook fixture: executable `self/BACKLOG.md<LF>` alone | refused | refused |
| S1 | C18 with `.gitmodules` listed in `.git/info/exclude`, and a **full close** with no stray file | **gets past the head check and the stray check**; stops only at the manifest check because the fixture has no `templates/plans/features/TEMPLATE.md` | refused (unreviewed) |
| S2 | `feat: backlog`, BACKLOG + a gitlink `hooks/sub`, local config `diff.ignoreSubmodules=all`, no `.gitmodules` | allowed | refused |
| S3 | `feat: backlog`, BACKLOG + a gitlink `sub`, no `.gitmodules`, no config | refused | refused |
| S4 | `feat: review stamps`, timing.jsonl appended + a gitlink `sub`, `.gitmodules` `ignore = all` hidden by exclude | allowed | allowed |
| T1 | S1–S3 against `scratch/headfix`: head plus `--ignore-submodules=none` on the diff in `commit_changes_only` | refused (all three) | — |

Notes on these results:

- **Not findings:** C01, C15 and H01 are the relaxation the feature intends. The subject is only a
  label, and the content check is what guards.
- **The round-1 blocker is fixed:** C02–C06, C22 and H04. The sentinel holds against names that
  contain a newline, including a name that spoofs the sentinel itself.
- **R2 is no looser than the base** on every stamps input I tried.
- **Considered, not run:** `git replace` and grafts. Round 1 gives the reasoning: they are local
  refs the push does not carry.
- **Local config is in scope.** S2 needs local git config, and anyone who can edit that can edit
  the script. S1 needs no config: only a worktree `.gitmodules` that `.git/info/exclude` hides.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | C18/S1: commit `feat: backlog` that appends to `self/BACKLOG.md` and adds a gitlink `sub` (`git update-index --add --cacheinfo 160000,<sha>,sub`). The worktree has an uncommitted `.gitmodules` with `ignore = all`, hidden from the stray check by `.git/info/exclude` | allowed: `commit_changes_only` sees only `self/BACKLOG.md`. The close gets past the head check and the stray check, and stopped only at the fixture's missing manifest template | refused: `landed after the review judged this feature` | `bash /tmp/plan-capture.10p3zO/scratch/attack.sh /tmp/plan-capture.10p3zO/scratch/head sub` vs the same with `/tmp/plan-capture.10p3zO/scratch/base`, case S1; C18 in the run without `sub` |
| blocking | S2: the same gitlink smuggled at `hooks/sub` with local `diff.ignoreSubmodules=all` | allowed (reached the stray check) | refused (unreviewed) | the same two commands, case S2 |
| non-blocking | S4: commit `feat: review stamps` that appends to timing.jsonl and adds a gitlink `sub`, hidden the same way (pre-existing silent allow) | allowed | allowed | the same two commands, case S4 |
| non-blocking | C24: commit `feat: review stamps` that makes timing.jsonl executable (pre-existing silent allow) | allowed | allowed | the runs without `sub`, case C24 |

## Non-blocking findings

- **S4, a pre-existing silent allow.** A `<slug>: review stamps` commit can carry an unreviewed
  gitlink when the submodule diff is suppressed, either by a worktree `.gitmodules` with
  `ignore = all` or by `diff.ignoreSubmodules`. The base's `git show --name-only` hides it too, so
  both head and base allow it.
  - **Should do instead:** read the stamps commit's names with `--ignore-submodules=none`. The fix
    for the blocking finding below covers this case too, because both cases call
    `commit_changes_only`.
  - **File in:** `self/BACKLOG.md`, if the fix does not land in this feature.
- **C24, a pre-existing silent allow.** A `<slug>: review stamps` commit can change timing.jsonl's
  mode to executable, and both head and base allow it.
  - **Should do instead:** require mode `100644` on timing.jsonl, as R1 does for the BACKLOG.
  - **File in:** `self/BACKLOG.md`.

## Blocking findings: reproduction and remedy

**B2 (C18/S1, S2): a submodule change hidden from `commit_changes_only` rides the
`<slug>: backlog` subject.**

`git diff` honours `submodule.<name>.ignore` from the worktree `.gitmodules`, and also
`diff.ignoreSubmodules` from config, even for a diff between two commits. Under `ignore = all`, a
gitlink added or changed in the commit is not listed at all. So the name list reads
`self/BACKLOG.md` alone, the mode check passes, and an unreviewed tree entry goes into the PR. The
base refuses every commit under this subject, so this is a regression.

To reproduce, on a feature reviewed clean:

```
printf '[submodule "sub"]\n\tpath = sub\n\turl = ./x\n\tignore = all\n' > .gitmodules
echo .gitmodules >> .git/info/exclude
echo '- finding' >> self/BACKLOG.md
git add self/BACKLOG.md
git update-index --add --cacheinfo 160000,<any commit sha>,sub
git commit -m "<slug>: backlog"
./feature-close.sh --self <slug>      # passes the head check and the stray check
```

**What the rule should do instead.** Make the name list independent of submodule ignore settings:
add `--ignore-submodules=none` to the `git diff` in `commit_changes_only`, or use plumbing that
does not read them. I verified the flag on a patched copy (T1): S1, S2 and S3 are all refused.
Add a case beside K11/K12 in `self/tests/close-backlog.sh`: a gitlink beside the BACKLOG under the
subject, with an excluded `.gitmodules` that sets `ignore = all`, must be refused.
