# 01 — review: close-after-filing

Review the diff against the spec below — written before the build, from the brief, not from
the builder's report. "No findings" is a legitimate verdict: say `Verdict: clean` when the
diff does what is listed and holds the contracts, and do not invent findings to fill a
report.

## What the feature was supposed to do

Resolve a contradiction between doctrine and code. The doctrine (`ORCHESTRATION.md` →
"Rules", `LIFECYCLE.md` → "The security audit", `templates/SECURITY_AUDIT.md`,
`hooks/README.md`) says a clean round's non-blocking findings are filed in the repo's
BACKLOG by the coordinator before the close, but `feature-close.sh` refused every commit
after the head the review judged other than the harness's own subjects — a BACKLOG-only
commit included — as an unreviewed round. Following the doctrine therefore looped.

The feature chooses one of two resolutions and justifies the choice in
`self/features/close-after-filing/NOTES.md`:

- (a), preferred: `feature-close.sh` accepts, after the judged head, a commit under ONE
  fixed subject the script defines that touches ONLY the repo's BACKLOG file
  (`self/BACKLOG.md` under `--self`, `plans/BACKLOG.md` in a consuming repo; behind
  `agentTooling/` where the self layout is vendored), and still refuses everything else —
  that subject touching any other path, the BACKLOG file under any other subject, and any
  audit path whatever the subject (the existing F1 rule).
- (b): the doctrine changes so findings are filed within the round, before the stamped head.

Whichever is chosen: the close's refusal message for an unreviewed commit names the
allowed path, and every doc that states the rule agrees with the code.

Excluded: any change to how the audit classes findings, to which subjects other than the
new one are accepted, to `orchestration-start.sh`, `analysis/manifest.py`/`roots.py`, or to
`LIFECYCLE.md` → "Orchestration records" (a sibling feature's).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `feature-close.sh`'s post-review loop: the new subject is a named constant beside
  `COST_COMMIT_SUFFIX`/`PR_COMMIT_SUFFIX`/`STAMPS_COMMIT_SUFFIX`, and a commit under it
  passes only when its whole change (renames off, NUL-safe names) is the one BACKLOG path
  for this layout — not a deletion, not a symlink or mode change that turns it into
  something other than a regular file, not a merge with an empty diff. Any other commit
  still reaches the existing refusal, and that refusal now names the allowed path.
- The BACKLOG path comes from the layout (`resolve_roots` in `plan-runner-roots.sh` or an
  equivalent single definition), not a literal repeated in several places.
- F1 holds: `audit_paths_in_range "$JUDGED_HEAD..HEAD"` still runs over the whole range,
  whatever the subjects, and nothing the new subject admits can be an audit path or audit
  evidence (an audit plan, `audit-report.md`, an `audit_end` line). The STAMPS_SHA read
  (first `S: review stamps` commit after the judged head) is unaffected by a BACKLOG commit
  before or after it.
- A new test under `self/tests/`, recorded by `self/gate.sh`, in the shape of the existing
  close tests (throwaway checkout, stub `claude`, the close stopped at the stray check):
  a BACKLOG-only commit under the subject after a clean judged head passes the head check
  (also on a hook-changing feature, whose audit line still prints); the subject plus any
  other path, the BACKLOG under another subject, an audit path under the subject, and a
  deletion or symlink of the BACKLOG are each refused, naming the allowed path.
- Docs agree with the code: `ORCHESTRATION.md` → "Rules", `LIFECYCLE.md` → "The security
  audit" and "6. Close", `templates/SECURITY_AUDIT.md`, `hooks/README.md`, `README.md`'s
  `feature-close.sh` row, `self/PROJECT_FACTS.md`'s close command; no doc still says a
  BACKLOG-only commit is refused or a new round.
- READMEs: `self/tests/README.md` lists the new test; every touched folder's README still
  describes it (`check-readme-index.py` green).
- Shell rules (`self/PROJECT_FACTS.md` → "Conventions and gotchas"): bash 3.2, no `set -e`,
  magic values as named constants.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. Escalate only on a defect the diff
introduces or a listed contract it fails; list anything else as a non-blocking note.
