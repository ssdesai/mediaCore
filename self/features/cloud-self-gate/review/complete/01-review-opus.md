# 01 — review: cloud-self-gate

Written from the design (`self/DESIGN-2026-10-05-cloud-execution.md` §10) and the
manifest (`self/features/cloud-self-gate/README.md`). **Written after the build, not
before:** a stand-in review ran first and this brief replaces it (§10 "Bootstrapping"
says why). Do not take the manifest's account of causes on trust; check each against the
code. "No findings" is a legitimate verdict. Fix local drift in this pass; anything
structural is an escalation, and an escalated report is round 2's brief. Begin your
report with the `Verdict:` line the prompt asks for.

## What the feature was supposed to do

`self/gate.sh` returned a red verdict in a Claude Code cloud container. The feature makes
it green there by fixing each red check's dependence on the machine, **without changing
an assertion and without excusing a failure**. The design's rule is §7: the gate stays
strict, and the test or the environment is fixed.

1. **`feature-lifecycle` S4h–S4n.** Claimed cause: a bare origin made by a plain `git init
   --bare` takes HEAD from `init.defaultBranch`, unset in the container, so `master`, and
   the forge clone checks out an empty head. Claimed fix: `symbolic-ref HEAD
   refs/heads/main` on that origin, and on the same unpinned bare origin in
   `recover-at-close.sh`, `plan-numbering.sh` and `start-takeover.sh`.
2. **`allow-repo-commands`.** Claimed cause: `link-home` linked the real `$HOME`, and
   `/root` holds only dotfiles, so `cat link-home/*` names nothing, which
   `hooks/allow-repo-commands.sh`'s `value_confined` approves by design (`hooks/README.md`,
   "a file that does not exist cannot be read"). Claimed fix: `link-home` points at a home
   directory the test builds under its own temp directory, holding `.zshrc` and a visible
   file. The hook is unchanged.
3. **`hook-wiring`.** Claimed cause: the checkout had no generated `.claude/settings.json`.
   Fix: generated in the checkout. It is git-ignored, so it is not in the diff; making a
   cloud checkout start with it belongs to `execution-profiles` (§7).

Also on this branch, because a cloud session runs on its one assigned branch: the design
record itself (`self/DESIGN-2026-10-05-cloud-execution.md`), its `self/README.md` row and
a `self/BACKLOG.md` entry. Read them for accuracy against the code they cite, not for the
design's merits, which the user decided in review.

Not in this feature: wiring `.claude/settings.json` at container start; isolating
fixtures' global git config wholesale; the cost-capture sole-claimant cut
(`cost-capture-collisions`); closing through `feature-close.sh` (`cloud-close`).

## The diff

The base is `main`; the diff to read is `git diff main...HEAD`. Expect:
`self/DESIGN-2026-10-05-cloud-execution.md`, `self/README.md`, `self/BACKLOG.md`,
`self/tests/feature-lifecycle.sh`, `self/tests/recover-at-close.sh`,
`self/tests/plan-numbering.sh`, `self/tests/start-takeover.sh`,
`self/tests/allow-repo-commands.sh`, and `self/features/cloud-self-gate/` (manifest,
`planning.json`, `report.json`, `report.md`, this brief). Anything else that moved is a
finding.

## What to hold it to

- **No assertion changed.** Every `check` line and every expected-verdict list in the
  touched tests is byte-identical to `main`, apart from fixture setup. Show it from the
  diff.
- **The causes are real.** Reproduce each one: a bare repo with `init.defaultBranch` unset
  (`GIT_CONFIG_GLOBAL=/dev/null`) cloned after a push of `main` yields an empty head
  without the pin and a checkout with it; `value_confined` on a relative glob through a
  link to a directory with only dotfiles returns True. If a claimed cause does not
  reproduce, that is an escalation.
- **The fixture still tests the escape.** For every `link-home` case in
  `allow-repo-commands.sh`, say whether it still exercises a read out of the tree, and that
  `TMP/linked-home` is outside the fixture root and created once.
- **No other machine dependence of the same kind.** Search `self/tests/` for bare origins
  that are cloned with no pinned HEAD, and for relative reads through a link to the real
  home directory.
- **The tests pass.** Run `bash self/tests/feature-lifecycle.sh`,
  `bash self/tests/allow-repo-commands.sh`, `bash self/tests/recover-at-close.sh`,
  `bash self/tests/plan-numbering.sh`, `bash self/tests/start-takeover.sh`, then
  `./self/gate.sh`, and report each verdict.
- **The record is honest.** `planning.json` bills the whole pinned design session (about
  $7.89) as build; the manifest's "The cost record carries the design session" section
  says so and design §10 hands the cut to `cost-capture-collisions`. Check that the figures
  quoted match `report.md`.
- **Docs.** The design doc's §10 findings match the code; `self/README.md`'s row for the
  design names the four features in §10's order; `self/tests/README.md` needs an update
  only if it describes a fixture this feature changed.
- **Style.** Bash 3.2 in tests; no chained `cd`; named constants where the file uses them.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
