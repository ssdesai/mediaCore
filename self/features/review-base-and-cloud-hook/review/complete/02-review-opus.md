# 02 — review: review-base-and-cloud-hook, round 2

Written before the rework, from the spec. Never from the implementer's report. "No
findings" is a legitimate verdict.

## What round 2 was supposed to do

Round 1 was reviewed clean (`self/features/review-base-and-cloud-hook/escalations/` is
empty; round 1's report is in the PR body). After it the human decided one change, now in
`self/features/review-base-and-cloud-hook/SPEC.md` → "Round 2: a push to `main` is refused
in BOTH profiles". Read that section first: it is the whole spec for this round, and it
overrides round 1's "locally nothing changes" for that one shape only.

## The diff

`git fetch origin main`, then the round's own diff: `git log --oneline` to find the
`review-base-and-cloud-hook: review round 1` commit, and `git diff <that sha>..HEAD`. Read
the whole-feature diff (`git diff origin/main...HEAD --stat`) only to check the round did
not disturb what round 1 judged.

## Contracts to hold it to

- **Every spelling the spec lists is denied, in both profiles**, with the right reason for
  each profile: `origin main`, `-u origin main`, `HEAD:main`, `x:main`, `+main`,
  `refs/heads/main`, `--repo origin main`, `--repo=origin main`, `:main`,
  `--delete origin main`, `git -C <root> push origin main`. Probe a few more yourself:
  `git push origin main --dry-run`, `git push origin 'main'` (quoted), `git push origin
  main:main`, `git push origin HEAD:refs/heads/main`, `git push upstream main`, a push to
  `main` inside a chain (`git status && git push origin main`) — run the hook on each, under
  both profiles, pinned (`AGENTTOOLING_PROFILE` set, `CLAUDE_CODE_REMOTE` cleared).
- **No false refusals**: `git push origin mainline`, `feature/main`, `main-x`, a source of
  `main` pushed to another destination (`git push origin main:x` — locally that is not a
  push TO main; decide whether the implementer's ruling is sound and recorded), `git log
  main`, `git checkout main -- f`, `echo 'git push origin main'`, a commit message
  containing it.
- **Locally there is no git probe**: no subprocess on any path the local judge takes
  (check the X-series logging-git tests cover a push to `main` under `local`). The bare
  `git push` on `main` locally staying a prompt is recorded as a ruling in `NOTES.md`.
- **In the cloud** a push whose resolved target is `main` is refused even when `main` is
  the current branch; plain `git push` and `-u origin <current>` still prompt when current
  is not `main`.
- **The protected name is one constant in `hooks/policy.py`'s table**, hook-only:
  `bash_deny_rules()` is unchanged, `.claude/settings.json` unchanged, `policy-table.sh`
  asserts the entry renders no prefix rule.
- **The local reason** is accurate: it says agents never push `main`, push the feature's
  branch, and that work reaches `main` through the PR `feature-close.sh` opens and a human
  merges. It must not tell a local session anything cloud-specific, nor vice versa.
- **The `--repo` fix** also applies to the cloud push-elsewhere judge
  (`git push --repo origin x` with `x` not current is refused in the cloud).
- **Nothing else moved**: every case that existed after round 1 keeps its answer in both
  profiles except `("git push origin main", …)`, which moved to denied. Diff the test
  tables to confirm no expectation was quietly changed to make a test pass.
- **Failure modes**: a malformed push line (unterminated `--repo`, `--repo` with no value)
  does not crash the hook; exceptions do not escape.
- **Docs**: `hooks/README.md`, `LIFECYCLE.md` rule 2, `README.md`'s `hooks/` row,
  `self/tests/README.md` rows if a test file's coverage changed, `NOTES.md` rulings.
  Named constants for every new literal.
- `./self/gate.sh` green.

## Verdict

Write `self/review-report.md`. Its FIRST line is exactly `Verdict: clean` or
`Verdict: escalated`. Fix local findings in this pass and say what you fixed; escalate only
structural ones. Then the findings with file:line, then what you probed and found sound.
