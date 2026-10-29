# 02 — review: execution-profiles

Round 2: the re-review **scoped to round 1's escalation**
(`self/features/execution-profiles/escalations/01-review-opus.md`), written before the
rework, from that escalation and the coordinator's ruling below — never from the rework's
report. Read the code. "No findings" is a legitimate verdict. Fix local drift in this pass;
anything structural is an escalation. Begin your report with the `Verdict:` line the
prompt asks for.

## What the rework was supposed to do

Round 1 found that the resumable gate (design §8) never resumes when a runner runs it:
the tree sha (`gate_tree_sha` in `templates/plans/gate.sh` and `self/gate.sh`) covered the
feature corpus, and every runner writes there between gate runs (`stamp_timing`'s
`timing.jsonl` line before each gate, plan moves between `incomplete/`, `inprogress/` and
`complete/`, `*.progress.md`, `*.usage.json`), so a gate killed with its container and
re-run by `run-batch.sh` or `run-plans.sh` re-ran every check.

**The coordinator's ruling:** the whole features corpus — `plans/features/` in a
consuming repo, `self/features/` under `--self` — is left out of the tree sha, alongside
the gate's own outputs. It holds records, not gate inputs; `check-plans.sh` validates it
and is run by `run-batch.sh` itself, not by the gate. The accepted consequence: a gate
check that reads the corpus resumes across corpus edits. Recorded in `NOTES.md` and the
design's §8/§10.

## The diff

`git diff <round-1 head>...HEAD`, where the round-1 head is the `head=` on round 1's
`plan_end` in `self/features/execution-profiles/timing.jsonl`. Expect the two gate scripts
(and `TEMPLATE_VERSIONS` if the template's hash moved — a version bump is required only if
the template's version has already shipped on `main`; it has not, so a re-record at the
same version is correct), `self/tests/gate-resume.sh`, `self/tests/README.md`,
`NOTES.md`/`CHECKPOINT.md`, the design's §8/§10, and READMEs that describe the tree sha.
Nothing else.

## Contracts to hold it to

- **The assertion round 1 named exists and would fail on round 1's code:** a template gate
  run through a runner entry point (`run_level_gate`, or `run-batch.sh`'s final-gate path)
  with `stamp_timing` live and a feature directory present, killed during check 3, re-run
  through the same entry point, runs only c3 and c4. Likewise a corpus edit between runs
  does not reset the state, while a change outside the corpus still does.
- **The exclusion matches in both copies** of the gate, and the resolved corpus path is
  the right one in each (`plans/features` for the template, `self/features` for self).
- **The real index is still untouched**, and a non-git checkout still runs everything.
- **No existing assertion weakened.**
- Report the touched tests run individually; the coordinator runs the full gate.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then whether the escalation is resolved, what you fixed, what you escalated, and the
files this pass touched.
