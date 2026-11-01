# 73 — tests: check-plans.sh

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 1 of 8 build plans.

Write `self/tests/check-plans.sh`, the black-box test of the script plan 76 writes, and
wire every file this batch adds into `self/gate.sh`. RED until plan 76 lands.

Independent of other plans (76 implements what this asserts; the gate lines below name
files plans 74, 75, 76, 77 and 78 create).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- bash 3.2: no associative arrays; a possibly-empty array expands as `${a[@]+"${a[@]}"}`.
- Test shape: read `self/tests/feature-lifecycle.sh:53-140` — `TMP="$(mktemp -d)"`, the
  scripts under test copied into `$TMP/agentTooling` from
  `AT="$(cd "$(dirname "$0")/../.." && pwd)"`, `ok`/`fail`/`check` helpers printing
  `  ok    <label>` / `  FAIL  <label>`, a `fails` counter, exit 1 at the end when any
  failed, a `trap` removing `$TMP`. Copy that shape. Never touch the real checkout.
- `plan-runner-roots.sh` → `resolve_roots "${1:-}"`: with `--self`,
  `FEATURES_DIR=<script dir>/self/features`; otherwise `<script dir>/../plans/features`.
  `check-plans.sh` sources it from its own directory, so copying both files into
  `$TMP/agentTooling/` makes `$TMP/plans/features/` the ordinary corpus and
  `$TMP/agentTooling/self/features/` the `--self` one.
- `manifest_field <readme> <key>` (same file) reads the LAST ```json fence with awk and
  jq. jq is on PATH.
- The gate: `self/gate.sh` lists scripts in `shell_scripts=( … )` under
  `=== gate: shell syntax ===` and records tests as
  `record "<label>" bash self/tests/<name>.sh` under `=== gate: level sentinels ===`.

## Files

- create `self/tests/check-plans.sh`
- modify `self/gate.sh`
- modify `self/tests/README.md`

## The contract under test (this block is repeated verbatim in plan 76)

```
usage: check-plans.sh [--self] <slug>            exit 2 on usage (no slug, extra or unknown args)
exit 0 when every check passes, 1 when any check FAILs
one line per check, in this order, exactly:
  ok    <label>
  FAIL  <label>: <detail>
then one last line:  check-plans: <N> checks, <M> failed
D = $FEATURES_DIR/<slug>. Labels are fixed strings:
 1  feature directory exists        D is a directory
 2  manifest present                D/README.md exists
 3  fence parses                    manifest_field D/README.md slug prints something
 4  fence slug matches directory    that value == <slug>
 5  method known                    method absent, or one of plans|direct|hand
 6  branches non-empty              manifest_field branches is a JSON array of length >= 1
 7  window bounds carry a zone      session_window.from and .to, when present and not null,
                                    end in Z or in +HH:MM / -HH:MM
 8  plan filenames well-formed      every *.md directly under D/{auto,verify,review}/{incomplete,
                                    inprogress,complete,failed}/, ignoring *.progress.md, matches
                                    ^[0-9]+-[a-z0-9-]+-(haiku|sonnet|opus)\.md$ — or ^[0-9]+-gate\.md$
                                    under auto/ only; detail lists the offenders (path from D)
 9  plan numbers padded alike       the leading digit runs of every file from 8 have one length
10  no @@TODO@@ stubs queued        no file under any D/*/incomplete/ whose first line starts @@TODO@@
11  every plan file listed in plans[]   every non-sentinel file from 8 has its stem (name minus .md)
                                    in plans[]; detail lists the missing stems
12  every plans[] entry has a file  every stem in plans[] has <stem>.md under some state dir of
                                    auto/, verify/ or review/; detail lists the stems without one
13  every queued plan names the feature   every non-sentinel *.md under any D/*/incomplete/
                                    contains <slug> literally (grep -F); detail lists the files
14  plans method has a queue        method plans (or absent): at least one *.md under D/auto/ in
                                    any state; method direct or hand: ok
A queue or state directory that does not exist is simply empty for 8–14.
```

## `self/tests/check-plans.sh`

Scaffolding: `$TMP/agentTooling/{check-plans.sh,plan-runner-roots.sh}` copied from `$AT`;
`$TMP/plans/features/` for the ordinary cases; `$TMP/agentTooling/self/features/` for
the one `--self` case. Run the script as `"$TMP/agentTooling/check-plans.sh" <slug>`,
capturing stdout to a variable and the exit code to `rc`. Two helpers:

```bash
# mkfeature <features-root> <slug> <plans-json-array> [<branches-json-array>] [<from>] [<method>]
# writes <root>/<slug>/README.md: a title line, then a ```json fence holding slug, plans,
# branches (default ["<slug>"]), session_window {"from": <from default 2026-09-04T00:00:00Z>,
# "to": null}, and method when given.
# mkplan <features-root> <slug> <queue> <state> <name> [<first line>]
# writes <root>/<slug>/<queue>/<state>/<name>: <first line> (default "# plan"), then a line
# "feature: agentTooling/<slug>".
```

Assertions, each its own `check` with the number in the label; build a fresh feature
directory per assertion (a slug per case, e.g. `c04`) so cases never share state:

1. no slug → rc 2; `check-plans.sh --bogus x` → rc 2; `check-plans.sh x extra` → rc 2.
2. well-formed: plans `["01-build-haiku","02-verify-sonnet","03-review-opus"]`, files
   `auto/incomplete/01-build-haiku.md`, `auto/incomplete/02-gate.md`,
   `verify/incomplete/02-verify-sonnet.md`, `review/incomplete/03-review-opus.md` → rc 0;
   exactly 14 lines start with `  ok    `; no line starts with `  FAIL  `; the last line is
   `check-plans: 14 checks, 0 failed`. (The sentinel is absent from plans[] and passes 11.)
3. slug with no directory → rc 1; a `  FAIL  feature directory exists` line; the last
   line still starts with `check-plans: `.
4. fence slug `other` ≠ directory → a `  FAIL  fence slug matches directory` line.
5. method `bogus` → `  FAIL  method known`; method `direct` with no `auto/` at all →
   rc 0.
6. branches `[]` → `  FAIL  branches non-empty`.
7. from `2026-09-04T00:00:00` (no zone) → `  FAIL  window bounds carry a zone`; from
   `2026-09-04T00:00:00+05:30` → that line is `  ok    `.
8. an extra file `auto/incomplete/04-thing.md` → `  FAIL  plan filenames well-formed:`
   line whose detail contains `04-thing.md`; separately `verify/incomplete/05-gate.md` →
   FAIL 8; separately `auto/incomplete/01-build-haiku.progress.md` beside the plan → 8 ok.
9. `auto/incomplete/001-extra-haiku.md` (listed in plans[]) beside `01-build-haiku.md` →
   `  FAIL  plan numbers padded alike`.
10. a queued plan whose first line is `@@TODO@@ replace me` → `  FAIL  no @@TODO@@ stubs
    queued`; the same content under `review/complete/` instead → 10 ok.
11. a file `auto/incomplete/04-stray-haiku.md` not in plans[] → `  FAIL  every plan file
    listed in plans[]:` with `04-stray-haiku` in the detail.
12. plans[] naming `09-ghost-haiku` with no file → `  FAIL  every plans[] entry has a
    file:` with `09-ghost-haiku` in the detail; the same stem present as
    `auto/complete/09-ghost-haiku.md` → 12 ok.
13. a queued plan whose body never mentions the slug (`mkplan` with a first line and then
    overwrite the file with `# no feature line`) → `  FAIL  every queued plan names the
    feature`.
14. method plans, no `auto/` directory → `  FAIL  plans method has a queue`.
15. `--self`: the well-formed feature written under `$TMP/agentTooling/self/features/`
    → `check-plans.sh --self <slug>` rc 0.
16. the batch stop. Copy `run-batch.sh run-plans.sh run-verify.sh run-review.sh
    run-escalation-plan.sh plan-runner-lib.sh stamp-timing.sh` from `$AT` into
    `$TMP/agentTooling/` as well; write `$TMP/bin/claude` — a stub that appends its
    arguments to `$TMP/claude.log` and prints one line
    `{"type":"result","total_cost_usd":0,"session_id":"stub"}` (mirror
    `self/tests/level-sentinel.sh:39-45`) — and put `$TMP/bin` first on PATH; write
    `$TMP/plans/gate.sh` that exits 0. Then, with cwd `$TMP`:
    a. the feature from 8 (bad filename): `agentTooling/run-batch.sh <slug>` → rc non-zero
       and `$TMP/claude.log` does not exist (nothing was run);
    b. the well-formed feature: `agentTooling/run-batch.sh <slug>` → `$TMP/claude.log`
       exists (the build pass started). Do not assert its exit code.

## `self/gate.sh`

In `shell_scripts=( … )`, after `feature-close.sh` add three lines `check-plans.sh`,
`sweep.sh`, `update.sh`; after `self/tests/feature-lifecycle.sh` add
`self/tests/check-plans.sh`, `self/tests/sync-check.sh`, `self/tests/sweep.sh`. Under
`=== gate: level sentinels ===`, after the `feature lifecycle self-test` line, add:

```bash
record "check plans self-test" bash self/tests/check-plans.sh
record "sync check self-test" bash self/tests/sync-check.sh
record "sweep self-test" bash self/tests/sweep.sh
```

## `self/tests/README.md`

Add one bullet for `check-plans.sh` in the shape of the existing ones: what it stands
up, what it asserts (the fourteen labels, the usage exit, the batch stop), and that it
depends on `plan-runner-roots.sh`'s `resolve_roots` and `manifest_field`. Plans 74 and
75 add the bullets for their own tests.
