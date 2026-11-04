# 03 — scorecard: base arms and reading metrics

**Feature `harness-arm-base`, plan 3 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics (files and bytes read before the first edit, README bytes read)
beside the cost figures.

Summary: teach `harness/scorecard.py` to label a base arm by its commit, list the base
arms in the header, and render a reading table beside the Runs table.

Independent of other plans: it reads row fields by name (below) and needs no other file.

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts:
- New row fields (written by `run.sh`): `arm_kind` — `"agent_tooling"`, `"base"` or `""`
  (absent on rows written before it: read absent as the old behaviour); `base` — for a
  base arm, the arm's full commit; `read_files_before_edit`, `read_bytes_before_edit`,
  `readme_bytes_read` — integers or `null` (not measured), absent on older rows.
- `experiment.json` may carry `base_arms: {<label>: <full sha>}` instead of
  `agent_tooling` (never both).
- **Byte identity.** `harness/tests/scorecard-programs.sh` renders two hand-built cell rows
  (no `arm_kind`, no reading fields, no `base_arms`) and requires the output to equal
  `harness/tests/scorecard-programs.cells.md` byte for byte. Every change here must leave
  such a ledger's rendering unchanged: the new section appears only when some row
  carries a reading field key, and the label/header changes only for `arm_kind == "base"`
  / `base_arms`.
- `harness/tests/scorecard-arms.sh` asserts the existing comparison lines; the arm
  comparisons group by `arm` label and need no change for base arms.
- Every literal is a named constant in the block at lines 23–64. Never name a model.

## Files

- `harness/scorecard.py` — modify

## Changes

1. Constants, appended to the block at lines 23–64:
   ```python
   # Arms that vary the measured repository's commit (experiment.json `base_arms`)
   ARM_KIND_BASE = "base"
   BASE_ARMS_KEY = "base_arms"
   BASE_ARM_LABEL_FMT = "{arm} (base {sha})"

   # Reading metrics (harness/reading_metrics.py), rendered beside the cost figures
   READING_HEADING = "## Reading before the first edit"
   READING_FIELDS = ("read_files_before_edit", "read_bytes_before_edit", "readme_bytes_read")
   READING_COLUMNS = ("Fixture", "Method", "Arm", "Branch", "To PR-open",
                      "Files read before 1st edit", "Bytes read before 1st edit",
                      "README bytes read")
   BYTES_FMT = "{:,}"
   ```
2. `arm_label` (lines 128–135): when `row.get("arm_kind") == ARM_KIND_BASE`, return
   `BASE_ARM_LABEL_FMT.format(arm=arm, sha=(row.get("base") or "")[:SHORT_SHA_LEN])`
   (just `arm` when `base` is empty). Every other row is labelled exactly as now; update
   the docstring.
3. `render`'s header (lines 315–322): beside `arms_text`, build `base_arms_text` from
   `experiment.get(BASE_ARMS_KEY) or {}` the same way, worded `"  ·  base arms: "` +
   `label=sha7` joined by `", "`, and append it after `arms_text` in the same f-string.
   Empty when the key is absent.
4. A helper:
   ```python
   def reading_cell(value) -> str:
       """A reading figure: grouped digits, or NA when it was not measured."""
       return NA if value is None else BYTES_FMT.format(int(value))
   ```
   and a function `render_reading(rows: list[dict]) -> list[str]` returning `[]` when no
   row has any key in `READING_FIELDS`; otherwise `READING_HEADING`, a blank line,
   `table_header(READING_COLUMNS)`, one `table_row(...)` per such row — fixture,
   `cell_label(row)`, `arm_label(row)`, `` `branch` `` in backticks, `money(row.get("cost_method_usd"))`,
   then `reading_cell(row.get(field))` for each field — and a trailing blank line.
5. In `render`, inside `if rows:` right after the Runs table's closing `out.append("")`
   (line 349), add `out.extend(render_reading(rows))`.
