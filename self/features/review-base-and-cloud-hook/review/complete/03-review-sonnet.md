# 03 — review: review-base-and-cloud-hook, round 3

A re-review scoped to round 2's escalation. "No findings" is a legitimate verdict.

## What round 3 was supposed to do

Fix the one finding in `self/features/review-base-and-cloud-hook/escalations/02-review-opus.md`:
`hooks/README.md`'s paragraph on the constants the hook binds and owns (around lines
1292-1310) must name round 2's additions — the bindings `PUSH_TO_PROTECTED`,
`GIT_PROTECTED_BRANCH` and `GIT_HOOK_ONLY_RULE` (bound to `policy.hook_only_rule`), the
hook's own `GIT_PUSH_PROTECTED_DENY_REASON`, and the reading constant `GIT_PUSH_REPO_FLAG`.
No code was to change.

## The diff

`git log --oneline -4` to find `review-base-and-cloud-hook: review round 2`, then
`git diff <that sha>..HEAD`. Expect `hooks/README.md` and this feature's own records only.

## Contracts to hold it to

- Every name the escalation lists appears in that paragraph, attributed correctly: the
  three bindings as `policy.py`'s objects, the deny reason as the hook's own, the
  `--repo` flag among the reading constants. Check each name against
  `hooks/allow-repo-commands.sh` (around lines 335-360) and `hooks/policy.py` — spelled
  exactly as the code spells it.
- Nothing else in the paragraph or the file changed meaning; no code, test or settings file
  changed in this round (`git diff --stat`).
- `./self/gate.sh` is not required for a doc-only round; `bash -n` and the profile
  confinement check are unaffected by a `.md` edit.

## Verdict

Write `self/review-report.md`. Its FIRST line is exactly `Verdict: clean` or
`Verdict: escalated`. A wording fix you can make in a file you are allowed to edit, make
and say so; a fix in `hooks/` you cannot make headless is an escalation naming the exact
words, as round 2 did.
