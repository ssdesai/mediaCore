Verdict: clean

# Review — hook-role-hardening, round 4

## What the batch was supposed to do

Fix C1 from round 3's security audit: GNU `date`'s `-I` takes the rest of its word as an
optional attached argument, so in `date -Id 010100002020` the `d` belongs to `-I`
(`--iso-8601=date`). The old scan in `orchestrator_date_reads_only` read the `d` as `-d`,
skipped the next word, and let a clock-setting operand through. Round 4 stops the
short-cluster scan at `I` (`ORCHESTRATOR_DATE_OPTIONAL_ATTACHED`), so the next word is
checked as an operand.

## Does it do it

Yes. Round 4's diff (`8bdabcf..HEAD`) is small. Reading it against date's getopt string
`d:f:I::r:Rs:u`:

- `-Id X`, `-uId X`, `-uuId X`, `-I X`: the scan breaks at `I` with `takes_value = False`,
  so `X` is checked as an operand and refused unless it is `+FORMAT`. This matches GNU
  getopt, where an optional argument is never taken from the next word.
- `-dI X`: `d` comes first, so it takes `I` as its attached value and `X` is checked as an
  operand. That is still correct.
- `--iso-8601 X`: this is not a value-taking long option, so `X` is checked as an operand
  and denied.
- `-s` / `--set` are still refused separately, by the forbidden-option table
  (`"date": (("--set",), "s")`).
- The H24 cases listed in the plan are in the test and pass in `self/gate-report.txt`. H20
  is unchanged, and the gate shows no failures or skips.
- NOTES.md records the fix under "Lifecycle round 3", and the feature README's plan table
  and manifest list `03-audit-opus` and `04-review-opus`.

The round-1 contracts are untouched; this round changes only the date scan, its test and
the docs.

## Fixed in this pass

- `self/tests/hook-orchestrator-role.sh` H24: added a denial case for `date -I 010100002020`
  (bare `-I` followed by a clock-setting operand). The fix relies on `-I` never consuming
  the next word, but until now that was only tested with an attached argument. I traced the
  case through the code but did not run the test; the next gate run will run it.

## Escalated to the next round

None.
