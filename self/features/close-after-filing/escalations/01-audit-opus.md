Verdict: escalated

# Security audit — close-after-filing

Files in the audit scope: `feature-close.sh`, `hooks/README.md`, `plan-runner-roots.sh`,
`self/gate.sh`, `templates/SECURITY_AUDIT.md`. Only one of them changes a rule:

- **R1** (`feature-close.sh`, the post-judged-head loop, `"$FEATURE_SLUG$BACKLOG_COMMIT_SUFFIX"`
  case): before the close, it now accepts a commit after the judged head under the subject
  `<slug>: backlog` when the commit has one parent, its whole diff is `$BACKLOG_REL`, and that
  path is mode `100644`. On the base, every commit with that subject is refused as unreviewed.
  The rule is meant to refuse every other path under this subject.
- `plan-runner-roots.sh` only adds `BACKLOG_LABEL`, the data R1 reads (`self/BACKLOG.md`, or
  `plans/BACKLOG.md` outside self mode). `hooks/README.md` and `templates/SECURITY_AUDIT.md`
  change only prose. `self/gate.sh` adds `self/tests/close-backlog.sh` to its list. None of
  these four adds a rule of its own.

## Method

I built two throwaway copies under the scratch directory:
`git archive HEAD` gives `scratch/head`, and `git archive origin/main` gives `scratch/base`.
`scratch/attack.sh <copy>` builds two fixtures from the copy, using the shape of
`self/tests/close-backlog.sh`:

- **plain:** a feature that changes `docs-notes.txt`.
- **hook:** a feature that changes `hooks/allow-repo-commands.sh`, so a security audit is owed.

Each fixture is reviewed clean through the copy's own `run-review.sh` with a stub `claude`.
Each case then resets the fixture to the reviewed stamps commit, adds the crafted commit(s), and
runs the copy's own `./feature-close.sh --self feat`. A stray untracked file stops the close at
the stray check, which comes after the head check and the audit checks. So:

- **ALLOWED** means the close got past R1 and every audit check.
- **REFUSED(unreviewed)** means R1's loop refused the commit.

Commands:

- `bash /tmp/plan-capture.5H4E5u/scratch/attack.sh /tmp/plan-capture.5H4E5u/scratch/head`
- `bash /tmp/plan-capture.5H4E5u/scratch/attack.sh /tmp/plan-capture.5H4E5u/scratch/base`

`<LF>` below is a literal newline character inside a git path name.

## Inputs tried

| # | input (commit(s) after the judged head) | head: plain | head: hook | base: plain | base: hook |
|---|---|---|---|---|---|
| A01 | `feat: backlog`, `self/BACKLOG.md` alone appended (the intended case) | allowed | allowed | refused | refused |
| A02 | `feat: backlog`, new file `self/BACKLOG.md<LF>` alone, BACKLOG untouched | **allowed** | **allowed** | refused | refused |
| A03 | `feat: backlog`, new **executable** `self/BACKLOG.md<LF><LF>` (a shell script) alone | **allowed** | **allowed** | refused | refused |
| A04 | `feat: backlog`, BACKLOG + `self/BACKLOG.md<LF>` | refused | refused | refused | refused |
| A05 | subject `feat: backlog ` (trailing space) + BACKLOG | allowed | allowed | refused | refused |
| A06 | subject `Feat: backlog` + BACKLOG | refused | refused | refused | refused |
| A07 | subject `feat: backlog` + body line + BACKLOG | refused | refused | refused | refused |
| A08 | `--allow-empty` commit under `feat: backlog` | refused | refused | refused | refused |
| A09 | BACKLOG + `.gitattributes` | refused | refused | refused | refused |
| A10 | case-variant path `self/backlog.md` alone | refused | refused | refused | refused |
| A11 | BACKLOG replaced by a directory `self/BACKLOG.md/x` | refused | refused | refused | refused |
| A12 | BACKLOG + `hooks/policy.py` | refused | refused | refused | refused |
| A13 | a valid backlog commit, then `docs-notes.txt` under the same subject | refused | refused | refused | refused |
| A14 | an audit path (`hooks/allow-repo-commands.sh`) alone under the subject | refused | refused | refused | refused |
| A15 | new file `hooks/policy.py<LF>` alone under the subject | refused | refused | refused | refused |
| K6/K8 | delete, symlink, or `chmod +x` of the BACKLOG; a merge under the subject (the feature's own `self/tests/close-backlog.sh`) | refused | refused | n/a (base refuses the subject) | n/a |

Notes on these results:

- **A01** is the relaxation the feature intends, so it is not a finding.
- **A05** is not a finding. Git's default commit-message cleanup strips the trailing
  whitespace, so the stored subject is exactly `feat: backlog` and the commit is A01.
- **Considered, not run:** `git replace` and grafts. They rewrite what `rev-list` and `diff`
  see, but they are local refs that the branch push does not carry. Anyone who can write them
  can also edit the script, so they are outside what R1 can guard.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | A02: commit `feat: backlog` whose only change adds a file named `self/BACKLOG.md<LF>` (trailing newline in the path); `self/BACKLOG.md` is untouched | allowed: the close passes R1 and the audit checks and reaches the stray check (plain and hook fixtures) | refused: `landed after the review judged this feature` | `bash /tmp/plan-capture.5H4E5u/scratch/attack.sh /tmp/plan-capture.5H4E5u/scratch/head` vs the same with `/tmp/plan-capture.5H4E5u/scratch/base`, case A02 |
| blocking | A03: commit `feat: backlog` whose only change adds an executable shell script named `self/BACKLOG.md<LF><LF>` | allowed: as A02 (plain and hook fixtures) | refused: `landed after the review judged this feature` | the same two commands, case A03 |

## Non-blocking findings

None.

## Blocking findings: reproduction and remedy

**B1 (A02, A03): trailing-newline path names collapse into `$BACKLOG_REL`.**

The check reads the changed paths like this:

```bash
backlog_files="$(git diff --no-renames --name-only -z "$sha^" "$sha" | tr '\0' '\n')"
```

`$(…)` strips every trailing newline from its output. A path that is `self/BACKLOG.md`
followed by one or more newline characters prints as `self/BACKLOG.md\n…\0`, and after the
`tr` and the strip it reads as `self/BACKLOG.md`. The comparison
`"$backlog_files" == "$BACKLOG_REL"` then holds. The mode check reads the real
`self/BACKLOG.md`, which this commit leaves unchanged at `100644`, so it passes as well.

The result: a file that no review has read, under any name of that form, with any content and
any mode (A03 is an executable script), rides the `<slug>: backlog` subject into the PR. The
base refuses the same commit, so this is a regression and blocking.

To reproduce, on a feature reviewed clean:

```
printf 'payload\n' > "self/BACKLOG.md
"          # the path ends in a newline
git add -A && git commit -m "<slug>: backlog"
./feature-close.sh --self <slug>
```

The close passes the head check.

**What the rule should do instead:** compare the NUL-separated list as data, never through a
command substitution that strips trailing characters. For example, read it with
`mapfile -d '' -t names < <(git diff --no-renames --name-only -z "$sha^" "$sha")` and accept
only when `${#names[@]} == 1` and `${names[0]} == "$BACKLOG_REL"`. Another option is to keep
the trailing NUL in the comparison: append a sentinel inside the substitution, then compare
against `"$BACKLOG_REL"$'\n'<sentinel>`.

Add a test case beside K3–K8 in `self/tests/close-backlog.sh`: a file named
`self/BACKLOG.md<LF>` under the subject must be refused.
