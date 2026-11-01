# 01 — review: minutes-slug-and-quoting

Written before the build, from the manifest
(`self/features/minutes-slug-and-quoting/README.md`) and the design
(`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md`), never from the implementer's
report. "No findings" is a legitimate verdict. Fix local drift in this pass; anything
structural is an escalation, and an escalated report is round 2's brief. Begin your
report with the `Verdict:` line the prompt asks for. This feature edits `hooks/`; if the
Edit rule refuses you there, say so in the report and escalate the fix instead of
shelling a write around it.

## What the feature was supposed to do

Five small defects, one implementer. The manifest's `base` says which branch to diff
against (`ledger-and-routing`, or `main` if the close has retargeted it); the diff to
read is `git diff <base>...HEAD`.

1. **The minutes walk** (S1). A plan's seconds are the sum over attempts, live sidecar
   before prior, measured before recovered before unmeasured; the bucket rule and the
   two counts on `recovered_duration_plans[]` entries.
2. **The start's slug** (S2). `slug_of_start_command` reads the start's own line after
   joining `\`-continuations; no slug on that line is no slug.
3. **The opener's quoting** (S3). Both `open-session.sh` copies escape through two named
   layers, both at `template-version: 3`, `TEMPLATE_VERSIONS` re-recorded.
4. **A report read does not rewrite** (S4). `report.py` leaves the record untouched when
   only `generated_at` would move.
5. **Two hook shapes** (S5). A single-quoted backtick is not an opaque shape; `git -C
   <in-root path> <read-only>` is approved by its subcommand.

Not in this feature: the vendored `.claude/settings.json`; approving `ps`, `cp` or the
harness entry points that write; anything `ledger-and-routing` owns.

## The diff

Expect: `analysis/report.py`, `analysis/routing.py`, `self/open-session.sh`,
`templates/plans/open-session.sh`, `templates/plans/TEMPLATE_VERSIONS`,
`hooks/allow-repo-commands.sh`, `hooks/README.md`, `self/tests/report-footnotes.sh`,
`self/tests/routing-record.sh`, `self/tests/feature-lifecycle.sh` or a new
`open-session` test, `self/tests/allow-repo-commands.sh`, `self/tests/README.md`,
`self/gate.sh` only if a test file is new, `analysis/README.md` (`report.py`,
`routing.py` entries), `self/README.md` (`open-session.sh` row, the design row),
`templates/plans/README.md` if it describes the opener, `self/BACKLOG.md` (three entries
gone), and this feature's `NOTES.md`/`CHECKPOINT.md`/`timing.jsonl`. Anything else that
moved needs a ruling in `NOTES.md` or is a finding.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **The walk mirrors the cost walk.** The time walk's attempt order and its live-before-
  prior rule are the same as `compute_cost_rollup`'s — ideally the same iterator. A plan
  with a measured attempt and a recovered attempt reports the sum, sits in
  `recovered_duration_plans` with `measured_attempts` and `recovered_attempts`, carries
  the lower-bound mark, and its footnote says which part is a lower bound. A plan with an
  attempt holding neither figure is in `missing_duration_plans` naming attempt k of n. A
  plan whose only figures are in a prior sidecar reads them. No new mark.
- **The slug is on the start's line.** `slug_of_start_command("./feature-start.sh
  --self\nls")` is `None`; the `\`-continued form yields its slug; `--base x <slug>`
  yields `<slug>`; the constants for the continuation and the value-taking flags are
  named. `is_router_lines`'s behaviour on a start with no slug is stated in the notes.
- **Every quote survives.** With `osascript` stubbed, each copy run with a path holding
  a space, `'`, `"` and `\` produces a `do script` string that, unescaped and run with
  `claude` stubbed to print `$PWD`, prints the path intact. Both copies say
  `template-version: 3`; `template-versions.sh` passes; `feature-lifecycle.sh` S5's text
  reads still pass.
- **A read does not write.** Two consecutive `report.py` runs over an unchanged corpus
  leave `report.md` and `report.json` byte-identical (a test that runs `git status` or
  compares checksums); a changed `planning.json` rewrites them; the mask is one named
  regex, and a record that does not exist is written.
- **The hook.** `sed -n '/```json/,/```/p' /outside/x.md` prompts rather than denies;
  `grep 'a`b' README.md` is approved; an unquoted backtick is still denied; a line that
  will not tokenize is still denied; `git -C <root> status` is approved; `git -C /tmp
  status` prompts; `git -C <root> branch new` is denied; `git --git-dir=<root>/.git log`
  is approved. Every existing ALLOW / DENY / NOT_DENIED case still passes.
  `hooks/README.md` says both.
- **Style.** Named constants; Python stdlib only; bash 3.2 in the tests; no chained
  `cd`; every file authored with Edit/Write.
- **Exclusions named.** Every deviation from the manifest or design has a ruling in
  `NOTES.md`; the three backlog entries (minutes walk, no-slug start, open-session
  quoting) are gone from `self/BACKLOG.md` and the others are still there.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
