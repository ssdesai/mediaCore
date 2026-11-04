# 05 — tests: reading metrics, offline

**Feature `harness-arm-base`, plan 5 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics (files and bytes read before the first edit, README bytes read)
beside the cost figures.

Summary: a new offline test, `harness/tests/reading-metrics.sh`, of
`harness/reading_metrics.py` on fabricated transcripts and of the scorecard's reading
table, registered in `self/gate.sh`.

Depends on: `02-reading-metrics-sonnet.md` and `03-scorecard-sonnet.md` (read
`harness/reading_metrics.py`'s docstring and `harness/scorecard.py`'s `render_reading`
first — they are the contract), and `04-tests-arm-base-sonnet.md` (the `self/gate.sh`
anchor below).

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts:
- Model the file on `harness/tests/scorecard-arms.sh` (header comment, constants block,
  `pass`/`fail`/`check`, `mktemp -d "${TMPDIR:-/tmp}/reading-metrics.XXXXXX"`, `trap
  cleanup EXIT`, summary and exit). Read it whole first.
- Invocation: `python3 harness/reading_metrics.py <repo>/analysis <tree> --from <ts> --to
  <ts> --projects-root <dir>`; prints one JSON line with `read_files_before_edit`,
  `read_bytes_before_edit`, `readme_bytes_read`, `transcripts`. The tree need not exist on
  disk: only its project-directory name is used, which is the tree path with every `/`
  and `.` replaced by `-` (write it with `tr '/.' '--'`, as `smoke.sh:484` does).
- Transcript lines (write each with `jq -c -n`): assistant
  `{"type":"assistant","timestamp":T,"message":{"content":[{"type":"tool_use","id":ID,"name":"Read","input":{"file_path":P}}]}}`;
  result
  `{"type":"user","timestamp":T,"message":{"content":[{"type":"tool_result","tool_use_id":ID,"content":TEXT}]}}`
  where `TEXT` is a string or a list of `{"type":"text","text":…}`. An edit is an
  assistant `tool_use` named `Edit` (input `{"file_path":P}`). Subagent transcripts live
  at `<project>/<session-id>/subagents/agent-<x>.jsonl`.
- Bytes are UTF-8: put one `é` (2 bytes) in a result and compute expected sizes with
  `printf '%s' "$TEXT" | wc -c` rather than by hand.
- bash 3.2, `set -uo pipefail`, no `set -e`; named constants; no model names; no network.

## Files

- `harness/tests/reading-metrics.sh` — create
- `self/gate.sh` — modify
- `harness/tests/README.md` — modify

## `harness/tests/reading-metrics.sh`

Fixed instants (constants): window `FROM=2026-01-01T10:00:00Z`, `TO=2026-01-01T11:00:00Z`;
events at `10:01`, `10:02`, `10:03`, `10:04`, `10:05`, `10:06` (with `.123Z`
milliseconds on some, to pin mixed precision), one at `09:59` and one at `11:01`.
`TREE="$WORK/repo-cellBranch"`.

World, under `$WORK/projects/<mangled TREE>/`:
- `s1.jsonl`: 09:59 Read `<tree>/README.md` + result (outside the window); 10:01 Read
  `<tree>/README.md` (result `R1`, a string with the `é`); 10:02 Read `<tree>/src/a.py`
  (result `R2` as a list of two text blocks); 10:04 Read `<tree>/src/a.py` again (`R3`);
  10:05 `Edit` of `<tree>/src/a.py`; 10:06 Read `<tree>/docs/README.md` (`R5`); and, at
  10:02, a Read of `<tree>/missing.py` whose result has `"is_error": true`.
- `s1/subagents/agent-x.jsonl`: 10:03 Read `<tree>/lib/b.py` (`R6`).
- `s2.jsonl`: 11:01 Read `<tree>/late.py` + result (after the window).
- A sibling directory `<mangled TREE>2/` with an in-window Read and result — must be
  ignored.

Cases (each one `check`):
1. exit 0 and one line of JSON;
2. `read_files_before_edit == 3` (README.md, a.py, b.py — the repeat of a.py counted once,
   the errored read and everything after the edit not at all);
3. `read_bytes_before_edit == bytes(R1)+bytes(R2)+bytes(R3)+bytes(R6)`;
4. `readme_bytes_read == bytes(R1)+bytes(R5)` (README reads after the edit count; the
   09:59 one does not);
5. `transcripts == 2` (s1 and its subagent; s2 has no in-window line; the sibling
   directory is not read);
6. **No edit:** a second projects root holding only the reads (no `Edit` line) counts
   every in-window read as before the first edit, including `R5`'s file;
7. **No transcripts:** a projects root with no directory for the tree prints the three
   figures as `null` and `transcripts == 0`;
8. **Usage:** an analysis directory without `capture_planning.py` exits 2; so does
   `--from not-a-time`.

Scorecard (`python3 harness/scorecard.py <dir>` over a hand-built `experiment.json` and
`results.jsonl`, as in `scorecard-arms.sh`):
9. one row carrying `read_files_before_edit: 12`, `read_bytes_before_edit: 123456`,
   `readme_bytes_read: 7890` renders the `## Reading before the first edit` heading and a
   table row containing `| 12 | 123,456 | 7,890 |`;
10. a row whose three fields are `null` renders `| — | — | — |` in that table;
11. a ledger whose rows carry none of the three keys renders no such heading.

## `self/gate.sh`

After the `record "harness arm base self-test" …` line plan 04 added, add:

```bash
# Reading metrics: harness/reading_metrics.py on fabricated transcripts, and the scorecard's table.
record "harness reading metrics self-test" bash harness/tests/reading-metrics.sh
```

and in the comment above the experiment-harness records (line ~519) change "its three
tests run here" to "its five tests run here".

## `harness/tests/README.md`

Add a table row after `arm-base.sh`:
`| \`reading-metrics.sh\` | \`reading_metrics.py\` on fabricated transcripts under a \`mktemp -d\` projects root: the window (both ends inclusive), the first edit, a repeated file counted once, an errored read not counted, a subagent's reads counted, README bytes after the edit counted, a sibling \`<tree>2\` project directory ignored, the no-edit and no-transcript cases, usage errors; then \`scorecard.py\`'s \`## Reading before the first edit\` table (grouped digits, \`—\` for not measured, absent for a ledger without the fields). No repo, no network. |`
