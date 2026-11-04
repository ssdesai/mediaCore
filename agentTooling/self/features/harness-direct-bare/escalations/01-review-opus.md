Verdict: escalated

# Review: harness-direct-bare

## What the batch was supposed to do

Add `harness/methods/direct-bare/`, the control arm for measuring what `direct`'s three
procedure steps cost (`CHECKPOINT.md`, `stamp-timing.sh`, tests-first commit): `direct`
with exactly those steps removed. It also asked for a gate test that keeps the two briefs
paired, and for every place that lists the methods to be updated.

## Does it do it

The content does what the spec asked:

- **Template.** `diff direct/template.md direct-bare/template.md` shows only two removals:
  the `## Procedure` section (lines 27–44) and the
  ``(`CHECKPOINT.md` at status `committed`)`` parenthetical. Every other byte matches,
  placeholders included.
- **`run.sh`.** It is executable and differs from `direct/run.sh` only in comments, the
  method name in its three log/warn lines, and its `mktemp` prefix. The exit codes 0/2/1
  and the absence of any self-review are unchanged.
- **The pair test.** `self/tests/direct-bare-pair.sh` is in `gate.sh`'s `bash -n` list
  and has a `record` line. It cannot pass vacuously:
  - 1a–1c fail if the markers vanish from `direct`.
  - The expected file is derived from `direct/template.md` with awk and compared byte for
    byte (2b), so any edit to `direct`'s template fails the gate.
  - The placeholder checks use the harness's own `harness_fill_template`.
- **Docs.** `harness/README.md`, `harness/methods/README.md`, `harness/EXPERIMENTS.md`,
  `direct/README.md` (a pointer only) and the tests README row are accurate. No other
  method listing was missed. `direct` itself is unchanged.

## Fixed in this pass

- `harness/methods/direct-bare/run.sh` header comment: it said only "the two log lines"
  differ from `direct`'s. In fact three log/warn lines and the `mktemp -t` prefix differ.
  The same claim in `harness/methods/direct-bare/README.md` is fixed too. The pair test
  still passes.

## Escalated to the next round

1. **A `direct-bare` cell's branch name is not bare camelCase, which breaks
   `harness/SPEC.md` §4.**
   - **Where:** `harness_branch_name` (`harness/lib.sh:215`) builds
     `<stem>$(harness_capitalise "$method")`, and `harness_capitalise` only uppercases the
     first character.
   - **What happens:** a cell on fixture `exportStore` gets the branch
     `exportStoreDirect-bare`. SPEC §4 and the comment at `lib.sh:207` both promise
     `<branch_stem><Method><n>` in bare camelCase, and the branch rules elsewhere in the
     repo use `^[a-z][A-Za-z0-9]*$` (`publish.sh:63`, `new-experiment.sh:80`/`107`).
   - **Why it stays green:** nothing refuses a cell branch at run time, and the slug
     (`export-store-direct-bare`) and claim roots still come out distinct. So this is a
     broken invariant rather than a crash, and it is the first method name with a hyphen.
   - **Decision needed — pick one:**
     - rename the method `directBare`, which means changing the directory, docs and test;
     - or make the branch builder camelCase a hyphenated method name (`direct-bare` →
       `DirectBare`) and say so in SPEC §4.
   - **Missing assertion:** a gate check that every directory under `harness/methods/`
     yields a branch from `harness_branch_name` matching `^[a-z][A-Za-z0-9]*$`. With it,
     the next method name like this fails the gate instead of shipping.

## Not verified

None. The gate report's verdict is "all checks passed".
