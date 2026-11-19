Verdict: clean

# Review, round 2: audit-blocks-only-new

## What the batch was supposed to do

Change what a security-audit finding may block. In `templates/SECURITY_AUDIT.md` step 5,
the old clause (b) is removed. It made blocking "a SILENT ALLOW of a command that writes or
runs anything that is not read-only, even when the base allows it too". Now only a
REGRESSION blocks: the head is more permissive than the base for the same input, and that
includes a silent allow the head introduces. A pre-existing silent allow is
`non-blocking`. It is listed under `## Non-blocking findings`, flagged as one, and filed
in the BACKLOG of the feature that sees it before that feature closes. A finding that
cannot be classed with base evidence is still blocking. The restatements and the B4 test
follow the template, and the `self/BACKLOG.md` convergence entry is cut down to the part
still open.

## Does it do it

Yes. This round's diff against `origin/main` is the same as round 1's, plus round 1's
one-line fix: "(a) applies the same way" became "the REGRESSION rule applies the same way".
The plan's contracts:

- **No stale rule text.** `git grep` over tracked files outside `self/features/` finds no
  "even when the base allows it too", no "non-read-only" blocking clause, and no dangling
  (a)/(b) label. "Silent allow" appears only in the new wording, in the template,
  `LIFECYCLE.md`, `ORCHESTRATION.md`, `hooks/README.md`, the B4 test and its README line.
  The "silent approvals" at `hooks/README.md` lines 1666 and 1678 are history, not the rule.
- **Every restatement agrees with the template.** All say blocking = only a regression,
  including a silent allow the head introduces. All say a pre-existing silent allow is
  non-blocking and is filed in the BACKLOG before the close. All keep "cannot be classed →
  blocking", either in their own text or by pointing to the template.
- **Report shape unchanged.** The `## Findings` table contract and the verdict line are
  untouched. The `## Non-blocking findings` bullet only gains the flagging sentence.
  `feature-close.sh` and `plan-runner-roots.sh` are not in the diff.
- **B4 pins the new text.** It checks for `pre-existing silent allow`, `REGRESSION`, both
  headings, and the unclassifiable-is-blocking sentence. It also checks that the old
  "even when the base allows it too" phrase is gone. The `self/tests/README.md` line says
  the same.
- **Nothing outside the change.** The only other files touched are the BACKLOG
  shortening and this feature's own history.

## Gate note: `security-audit.sh` is syntax-checked, not run

`self/gate-report.txt` is green. But `self/gate.sh` only lists `self/tests/security-audit.sh`
in its `bash -n` syntax checks (line 302). It has no `record "…" bash
self/tests/security-audit.sh` line, so the gate never actually runs the suite. As far as
this round's gate is concerned, B4 was unverified. I ran the suite myself on this head:
`security-audit: all checks passed`, B4 included.

## Fixed in this pass

None.

## Escalated to the next round

None.

## Follow-up for the BACKLOG (pre-existing, outside this feature)

- **`self/gate.sh` never runs `self/tests/security-audit.sh`.** This dates from
  `hook-role-hardening` (commit `1f4c004`), which added it to the syntax-check list only.
  As a result, no gate enforces any of the suite's checks: R1–R5, C1–C5, F1–F7, N8–N11,
  B1–B5. That includes the audit-blocking rules this feature relies on (B2: the close
  refuses a `blocking` row under a clean verdict; B4: the template's rule text). The fix
  is one line in `self/gate.sh` next to line 430:
  `record "security audit self-test" bash self/tests/security-audit.sh`. Then check that
  the `self/tests/README.md` entry still matches. I did not escalate this because it
  predates this feature and the plan keeps the round to the one rule change. It should be
  filed in `self/BACKLOG.md` (or fixed as its own feature).
