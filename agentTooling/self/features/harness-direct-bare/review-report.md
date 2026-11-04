Verdict: clean

# Review — harness-direct-bare, round 2

## What the batch was supposed to do

Add `direct-bare`, the control arm for measuring what `direct`'s procedure steps cost: a
brief identical to `direct`'s minus the `## Procedure` section and the
``(`CHECKPOINT.md` at status `committed`)`` parenthetical, guarded by a gate test. Round 1
judged that content correct, but escalated one finding: the hyphenated method name produced
the cell branch `exportStoreDirect-bare`, which breaks SPEC §4's bare-camelCase rule (and
`publish.sh:63` would refuse it). The orchestrator's decision was to keep the method name
`direct-bare` and make the branch builder camelCase hyphenated names, minimally.

## Does it do it

Yes. Commit `23bf2d0` changes only `harness_capitalise` (`harness/lib.sh:216`), adds
section 5 to `self/tests/direct-bare-pair.sh`, and updates SPEC §4, the harness README
"Naming" entry and the tests README row.

- **The builder.** Each hyphen-separated part is capitalised and the hyphens dropped:
  `direct-bare` → `DirectBare`, `spec-opus-build` → `SpecOpusBuild`. A name with no hyphen
  takes the same final `printf` as before, so it comes out byte-identical. A leading or
  trailing hyphen yields an empty part and does not crash (`-x` → `X`, `x-` → `X`). It uses
  only `${x%%-*}`, `${x#*-}`, `${x:0:1}`, `+=` and `tr`, all of which work in bash 3.2, and
  no `${x^}` or associative arrays.
- **Arm labels.** These also go through `harness_capitalise`. `new-experiment.sh:145`
  validates them against `HARNESS_ARM_LABEL_RE` ("bare lower-case letters"), so a label can
  never contain a hyphen and labels behave exactly as before.
- **Callers.** `run.sh:152`, `new-experiment.sh:191/218/222` and
  `program-stages.sh:177/193` only build branches. Nothing in `harness/` or `analysis/`
  parses a branch back into a method. The row's `method` is still `$METHOD`, the directory
  name. The kebab-case slug derived from the branch (`lib.sh:529`) becomes
  `export-store-direct-bare2`, which is fine.
- **The test.** Section 5 pins `direct-bare` at one and several repeats, with an arm label,
  a non-hyphenated method and a three-part name. It also checks every directory under
  `harness/methods/` against `^[a-z][A-Za-z0-9]*$`. The old builder fails 5a–5c, 5e and the
  `direct-bare` case of 5f, so the round-1 defect cannot come back unnoticed, and the next
  hyphenated method is covered automatically.
- **Docs.** SPEC §4, the harness README and the tests README row all describe the rule
  correctly, and each says the row's `method` stays the directory name.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.

(Not a finding, only cosmetic: the round-2 edit to SPEC §4 left one line well over the
file's usual wrap width. It is also worth knowing that SPEC §4 gives the branch shape as
`<Method><n>` while the harness README gives `<Method><Arm><n>`. That difference was there
before this feature and this diff did not touch it.)
