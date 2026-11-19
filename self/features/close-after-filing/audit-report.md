Verdict: clean

# Security audit — close-after-filing, round 6

Files in scope: `feature-close.sh`, `hooks/README.md`, `plan-runner-roots.sh`,
`self/gate.sh`, `templates/SECURITY_AUDIT.md`. Head `fe94075`, base `origin/main` `2b27dac`.

This round was queued by the merge of main (`8c34190`, consumer-record-guard). Since round 5's
judged head (`1877610`), the merge changes none of the feature's lines in these five files. It
adds lines to `self/gate.sh` that main carries too. `feature-close.sh` and
`plan-runner-roots.sh` are byte-identical to round 5's tree. The diff against the base still
changes no rule in the PreToolUse hook. It changes the refusals in one lifecycle script,
`feature-close.sh`, in its loop over the commits after the judged head:

- **R1** (new). Subject `<slug>: backlog`: accepted only when `commit_changes_only "$sha" "$BACKLOG_REL"` holds. That means:
  - one parent;
  - a name list read with renames off, submodules never ignored and NUL separators, which must be the BACKLOG alone;
  - mode `100644`.

  The base refuses every commit under this subject.
- **R2** (changed). Subject `<slug>: review stamps`: now goes through `commit_changes_only` with timing.jsonl.
- **R3** (changed). The harness-records case: `git show` passes `--ignore-submodules=none`.
- **R4**. `export GIT_NO_REPLACE_OBJECTS=1`.
- **R5**. `export GIT_GRAFT_FILE=/dev/null`.
- Supporting changes:
  - `plan-runner-roots.sh` adds `BACKLOG_LABEL` and passes `--ignore-submodules=none` in `audit_paths_in_range`.
  - `hooks/README.md` and `templates/SECURITY_AUDIT.md` change prose only.
  - `self/gate.sh` lists `self/tests/close-backlog.sh`.

## Method

I made two throwaway copies under the scratch directory: `scratch/head` from `git archive HEAD`,
and `scratch/base` from `git archive origin/main`.

The head's `self/tests/close-backlog.sh` builds its fixtures from the copy it sits in:

- a feature reviewed clean by that copy's own `run-review.sh`, with a stub `claude`;
- a bare origin;
- a stray file, so the close stops at the stray check, which runs after the head and audit checks.

I copied the test into the base copy as well, so each case runs against the base's
`feature-close.sh` and `plan-runner-roots.sh`.

`scratch/patch.py` wraps each check so that it prints how the close ended:

- **ALLOWED**: it reached the stray check;
- **REFUSED**: it printed "landed after the review judged this feature".

`scratch/patch2.py` adds the new probes X1–X5. Commands:

- `bash scratch/run.sh`: the plain suite on both copies. The head passes in full.
- `bash scratch/run2.sh`: classified K cases.
- `bash scratch/run3.sh`: classified X cases.

## Inputs tried

| # | input (commits and local state after the judged head) | head | base |
|---|---|---|---|
| K1 | `feat: backlog` touching `self/BACKLOG.md` alone (the intended case) | allowed | refused |
| K2 | two such commits | allowed | refused |
| K3 | `feat: backlog`: BACKLOG + `docs-notes.txt` | refused | refused |
| K4 | BACKLOG alone under `feat: file the findings` | refused | refused |
| K5a | `feat: backlog`: `hooks/policy.py` alone | refused | refused |
| K5b | `feat: backlog`: BACKLOG + `hooks/policy.py` | refused | refused |
| K6a | `feat: backlog` deleting the BACKLOG | refused | refused |
| K6b | `feat: backlog` turning the BACKLOG into a symlink to `hooks/policy.py` | refused | refused |
| K6c | `feat: backlog` making the BACKLOG executable | refused | refused |
| K7 | `feat: backlog` touching `plans/BACKLOG.md` in the self layout | refused | refused |
| K8 | a merge under `feat: backlog`, first-parent diff the BACKLOG alone | refused | refused |
| K11a | new file `self/BACKLOG.md<LF>` under `feat: backlog` | refused | refused |
| K11b | executable `self/BACKLOG.md<LF><LF>` under `feat: backlog` | refused | refused |
| K12 | `timing.jsonl<LF>` under `feat: review stamps` | refused | refused |
| K13a | gitlink beside the BACKLOG, hidden by an excluded `.gitmodules` with `ignore = all` | refused | refused |
| K13b | the same gitlink beside timing.jsonl under `feat: review stamps` | refused | **allowed** |
| K13c | gitlink at `hooks/sub` beside the BACKLOG under `diff.ignoreSubmodules=all` | refused | refused |
| K14 | `feat: review stamps` making timing.jsonl executable | refused | **allowed** |
| K15a | unreviewed `hooks/policy.py` commit shadowed by `git replace` with a BACKLOG-only `feat: backlog` stand-in | refused | refused |
| K15b | the same with a timing.jsonl-only `feat: review stamps` stand-in | refused | **allowed** |
| K16a | unreviewed `docs-notes.txt` change hidden by a cyclic `.git/info/grafts` under `feat: backlog` | refused | refused |
| K16b | the same under `feat: review stamps` | refused | **allowed** |
| K9 | hook-changing feature behind a clean audit, then a BACKLOG-only `feat: backlog` | allowed (audit line prints) | refused |
| K10 | hook-changing feature: `feat: backlog` with BACKLOG + `hooks/policy.py` | refused | refused |
| L2 | `audit_paths_in_range` with a gitlink at `hooks/sub` under `diff.ignoreSubmodules=all` | listed | not listed (refused at the subject loop in K13c anyway) |
| X1 | `diff.relative=true` + `diff.noprefix=true` config, `feat: backlog`: BACKLOG + `docs-notes.txt` | refused | refused |
| X2 | subject `feat: backlog ` (trailing space), BACKLOG alone | allowed | refused |
| X3 | message `feat: backlog<LF>x` (no blank line, so `%s` joins it), BACKLOG alone | refused | refused |
| X4 | a valid BACKLOG-only `feat: backlog`, then `docs-notes.txt` alone under the same subject | refused | refused |
| X5 | `feat: backlog` replacing the BACKLOG with a directory `self/BACKLOG.md/x` | refused | refused |

Notes on these results:

- **K1, K2, K9 and X2 are the relaxation the feature exists for.**
  - In X2, `git commit`'s default cleanup strips the trailing space, so the stored subject is
    exactly `feat: backlog` and the commit is K1.
  - The base refuses these by design, so they are not findings.
- **On head, the stamps-subject cases are stricter than on base.**
  - K13b, K14, K15b and K16b are pre-existing silent allows on the base. The base checks only
    `git show --name-only`.
  - The head refuses all four. A head stricter than its base is no finding.
- **Not re-run this round:** round 5's commit-graph forgery (its C06/C07) and the caller-set
  `GIT_GRAFT_FILE` cases (its C04/C05).
  - The code they exercise (`feature-close.sh`, `plan-runner-roots.sh`) is byte-identical to
    round 5's tree. On head, round 5 recorded them refused.

## Findings

None.

## Non-blocking findings

None.

The base's silent allows under `feat: review stamps` (K13b, K14, K15b, K16b) are fixed on this
head, so none needs a BACKLOG entry.
