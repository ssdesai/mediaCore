# 04 — tests: base arms, offline

**Feature `harness-arm-base`, plan 4 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics beside the cost figures.

Summary: a new offline test, `harness/tests/arm-base.sh`, of `lib.sh`'s arm-kind helpers
and `scorecard.py`'s base-arm rendering, registered in `self/gate.sh`.

Depends on: `01-base-arms-driver-sonnet.md` (the lib helpers and constants named below)
and `03-scorecard-sonnet.md` (the label and header wording). Read `harness/lib.sh`'s
`harness_experiment_arm_kind` / `harness_experiment_arms` and `harness/scorecard.py`'s
`arm_label` / `render` header before writing the assertions — they are the contract.

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts:
- Model the file on `harness/tests/scorecard-arms.sh`: its header comment, the named
  constants block (lines 20–52), `pass`/`fail`/`check` (lines 54–57), the `mktemp -d` with
  an explicit template under `${TMPDIR:-/tmp}` and the `trap cleanup EXIT` (lines 59–63),
  the hand-built `experiment.json` / `results.jsonl`, and the closing summary/exit. Read
  that file whole first.
- Source `lib.sh` only in a subshell, as `harness/tests/smoke.sh:1784` does:
  `lib_call() { ( source "$HARNESS_DIR/lib.sh"; "$@" ) 2>&1; }`. `harness_die` prints
  `ERROR: <msg>` and exits 1.
- Wording to assert, from plan 01's constants: the both-kinds refusal contains
  `never both`; a malformed `base_arms` dies with `base_arms in <file> must be an object of
  <label>: <full sha>`. From plan 03: a base-arm row is labelled `<arm> (base <sha7>)`;
  the header carries `base arms: <label>=<sha7>, …`; arm comparison lines read
  `- **<fixture> · <method>**: arm <left> vs arm <right>` with the arms in sorted order.
- bash 3.2, `set -uo pipefail`, no `set -e`; every literal a named constant; no model
  names. No network, no repo: everything in the `mktemp -d` directory.

## Files

- `harness/tests/arm-base.sh` — create (executable bit is set by the verify pass; the gate
  runs it with `bash`)
- `self/gate.sh` — modify
- `harness/tests/README.md` — modify

## `harness/tests/arm-base.sh`

Constants: experiment `scorecardBaseArms`, fixture `f`, methods `a`/`b`, arms `old`/`new`,
`SHA_OLD="3333333333333333333333333333333333333333"`,
`SHA_NEW="4444444444444444444444444444444444444444"`, noise band 15, and the four rows'
prices copied from `scorecard-arms.sh:34-37` (so two comparisons land inside the band and
two outside).

Cases (each one `check`):

**lib.sh** — write five small `experiment.json` files with `jq -n`:
1. no arm key → `harness_experiment_arm_kind` prints nothing and `harness_experiment_arms`
   prints `- -`;
2. `agent_tooling: {before: <SHA_OLD>}` → kind `agent_tooling`, arms line `before <SHA_OLD>`;
3. `base_arms: {old: SHA_OLD, new: SHA_NEW}` → kind `base`, arms lines exactly
   `old <SHA_OLD>` then `new <SHA_NEW>`;
4. both keys → `harness_experiment_arm_kind` and `harness_experiment_arms` each exit
   non-zero with output containing `never both`;
5. `base_arms: "abc"` → `harness_experiment_arms` exits non-zero with
   `base_arms in .* must be an object of <label>: <full sha>` (grep -E).

**scorecard.py** — an `experiment.json` carrying `base_arms` (no `agent_tooling`) and four
rows (fixture f × methods a,b × arms old,new), each with `arm_kind: "base"`, `base` the
arm's sha, `agent_tooling: ""`, the cost fields, `accept_pass: true`, `repeat: 1`, and a
`branch`; render with `python3 harness/scorecard.py <dir>`:
6. it exits 0;
7. the header line contains `base arms: old=3333333, new=4444444` and no `agentTooling arms:`;
8. the Runs table carries `new (base 4444444)` and `old (base 3333333)`;
9. the lines `**f · a**: arm new vs arm old`, `**f · b**: arm new vs arm old`,
   `**f · arm old**: a vs b` and `**f · arm new**: a vs b` are present, each showing
   `to PR-open` and `to green`;
10. exactly four comparison lines start with `- **f · `, two reading `tie inside the band`
    on both figures and two `outside the band`;
11. no `## Reading before the first edit` heading (the rows carry no reading fields).

## `self/gate.sh`

After line 525 (`record "harness scorecard programs self-test" …`), add:

```bash
# Base arms (experiment.json base_arms): the arm-kind helpers and the scorecard's labels.
record "harness arm base self-test" bash harness/tests/arm-base.sh
```

## `harness/tests/README.md`

Add a table row after `scorecard-programs.cells.md`:
`| \`arm-base.sh\` | \`lib.sh\`'s arm-kind helpers (\`harness_experiment_arm_kind\`, \`harness_experiment_arms\`) on hand-written \`experiment.json\`s — none, \`agent_tooling\`, \`base_arms\`, both (refused), malformed — and \`scorecard.py\`'s base-arm rendering on a hand-built ledger: the header's \`base arms:\` list, the \`<arm> (base <sha7>)\` label and the arm and method comparison lines. No repo, no network, nothing outside a \`mktemp -d\` directory. |`
