# 02 — reading metrics: extractor and row fields

**Feature `harness-arm-base`, plan 2 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics (files and bytes read before the first edit, README bytes read)
beside the cost figures.

Summary: add `harness/reading_metrics.py`, which reads a cell's method-window transcripts
and prints three reading figures, and wire it into `run.sh` so every ordinary cell row
carries them.

Depends on: `01-base-arms-driver-sonnet.md` (it also edits `run.sh`'s `build_ledger_row`
and `run_cell`; locate the anchors below by their text, not by line number).

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts:
- Mirror `harness/program_cost.py` for shape: module docstring as the usage text, a
  constants block, argparse, exit `0` printed / `2` usage error, and the driver's analysis
  modules imported **by path** (`program_cost.py:60-67`: check
  `<analysis-dir>/capture_planning.py` exists, `sys.path.insert(0, …)`, then import).
  Stdlib only.
- From `analysis/capture_planning.py`: `transcript_dir_name(repo_dir)` (cwd → project
  directory name, `/` and `.` become `-`), `load_transcript_lines(path)` (list of parsed
  JSON lines, unparseable ones skipped), `subagent_transcript_paths(transcript_dir,
  session_id)` (`<dir>/<session_id>/subagents/agent-*.jsonl`, sorted). From
  `analysis/transcript.py`: `to_utc(ts)` → aware UTC `datetime` or `None` (accepts `Z`
  and milliseconds).
- Transcript shapes (Claude Code session `.jsonl`, one JSON object per line, each with a
  `timestamp`): an assistant line is `{"type": "assistant", "timestamp": …, "message":
  {"content": [ … {"type": "tool_use", "id": "<id>", "name": "Read", "input":
  {"file_path": "<abs path>"}} … ]}}`; the result comes on a later user line `{"type":
  "user", "timestamp": …, "message": {"content": [ {"type": "tool_result", "tool_use_id":
  "<id>", "content": <string or list of {"type": "text", "text": …}>, "is_error"?: true}
  ]}}`. `message` or `content` may be absent or a string — skip such lines.
- The method's sessions all run with cwd = the cell's worktree `$TREE`, so their
  transcripts are under `<projects-root>/<transcript_dir_name($TREE)>/`. Match that
  directory **by exact name**: `<repo>-<Branch>2`'s directory contains `<repo>-<Branch>`'s
  name as a substring and must not be read. Default projects root `~/.claude/projects`.
- State file helpers (lib.sh): `harness_state_get <file> <key>` (`// empty`),
  `harness_state_set <file> <key> <json value>`. `t_method_start` / `t_pr_open` are state
  keys, UTC with `Z`. `$SCRIPT_DIR` is `harness/`, `$AGENT_TOOLING_DIR/analysis` the
  driver's analysis copy, `$LOG_DIR` the experiment's log directory.
- Program features call `do_capture` directly (`program-stages.sh:844`); they must not
  run the new step, which is why it is a separate function called only from `run_cell`.
- Named constants for every literal; never name a model in the file.

## Files

- `harness/reading_metrics.py` — create
- `harness/run.sh` — modify
- `self/gate.sh` — modify

## `harness/reading_metrics.py` (new)

Usage: `python3 harness/reading_metrics.py <analysis-dir> <tree> --from <ts> --to <ts>
[--projects-root <dir>]`. Prints ONE line, a JSON object with exactly these keys:

```python
# Output keys — the ledger row's field names (harness/README.md → "The ledger row")
FILES_BEFORE_EDIT_KEY = "read_files_before_edit"
BYTES_BEFORE_EDIT_KEY = "read_bytes_before_edit"
README_BYTES_KEY = "readme_bytes_read"
TRANSCRIPTS_KEY = "transcripts"

# What counts as reading and as editing
READ_TOOL = "Read"
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
README_NAME = "README.md"
TEXT_ENCODING = "utf-8"

# Exit codes
EXIT_OK = 0
EXIT_USAGE = 2
```

Rules, which the docstring states in these words:
- **The window.** Every `*.jsonl` directly in the tree's project directory, and each one's
  subagent transcripts, is read; a line counts when `to_utc(line["timestamp"])` is inside
  `[--from, --to]`, both inclusive. `transcripts` is how many files contributed at least
  one counted line. Counted lines are ordered by (instant, file order, line order), files
  in sorted path order with each session's subagents after it.
- **The first edit** is the instant of the earliest counted `tool_use` whose `name` is in
  `EDIT_TOOLS`. With none, every read in the window is "before the first edit".
- **A read** is a `Read` `tool_use` whose `tool_result` (matched by `tool_use_id`) is
  counted and not `is_error`. Its bytes are the UTF-8 length of the result's text: the
  string itself, or the concatenated `text` of its `text` blocks (other blocks add 0). A
  read is before the first edit when its `tool_use` instant is earlier than the first
  edit's.
- `read_files_before_edit` — distinct `input.file_path` values among reads before the
  first edit. `read_bytes_before_edit` — the sum of those reads' bytes, repeats included.
  `readme_bytes_read` — the bytes of every read in the window, before or after the first
  edit, whose `file_path` basename is exactly `README.md`.
- **No transcript** (no project directory, or no counted line): the three figures are
  `null` and `transcripts` is `0` — the row then says "not measured", never 0.
- Usage errors (no `capture_planning.py` in `<analysis-dir>`, unparseable `--from`/`--to`)
  print `usage error: …` on stderr and exit 2.

Structure: a pure function `reading_figures(events)` over the ordered counted lines
returning the three figures (so the test can reason about it), a loader that builds the
ordered list, and `main(argv=None)`. Print with `json.dumps(…, sort_keys=True)`.

## `harness/run.sh`

1. In the constants block at the top, add:
   ```bash
   # Reading metrics (harness/reading_metrics.py): its row fields, in the order they print
   READING_METRICS_SCRIPT="reading_metrics.py"
   READING_FIELDS="read_files_before_edit read_bytes_before_edit readme_bytes_read"
   ```
2. After `do_capture()` add:
   ```bash
   # What the method's sessions read before their first edit: the transcripts filed under
   # the worktree's own project directory, inside [t_method_start, t_pr_open] (now, when
   # no PR opened). Ordinary cells only: a program feature's capture never calls this.
   do_reading_metrics() {
     local from to out field
     from="$(harness_state_get "$STATE" t_method_start)"
     [[ -n "$from" ]] || return 0
     to="$(harness_state_get "$STATE" t_pr_open)"
     [[ -n "$to" ]] || to="$(harness_utc_now)"
     if ! out="$(python3 "$SCRIPT_DIR/$READING_METRICS_SCRIPT" "$AGENT_TOOLING_DIR/analysis" "$TREE" \
                 --from "$from" --to "$to" 2>>"$LOG_DIR/$BRANCH-reading.log")"; then
       harness_warn "reading metrics failed for $BRANCH — see $LOG_DIR/$BRANCH-reading.log"
       return 0
     fi
     for field in $READING_FIELDS; do
       harness_state_set "$STATE" "$field" "$(jq -c --arg f "$field" '.[$f]' <<<"$out")"
     done
   }
   ```
3. In `run_cell`, each of the three `stage_wanted capture && do_capture` lines becomes
   `stage_wanted capture && { do_capture; do_reading_metrics; }`.
4. Next to `state_or()` add:
   ```bash
   state_json_or_null() {  # $1 state key: its JSON value, or null when the state lacks it
     jq -c --arg k "$1" '.[$k] // null' "$STATE" 2>/dev/null || printf 'null'
   }
   ```
5. `build_ledger_row`: add one `--argjson <field> "$(state_json_or_null <field>)"` for each
   of the three fields, and in the object, directly after `cost_lost_usd: $cost_lost_usd,`:
   `read_files_before_edit: $read_files_before_edit, read_bytes_before_edit:
   $read_bytes_before_edit, readme_bytes_read: $readme_bytes_read,`.
6. `dry_run_cell`: after the `report.py` dry line, add
   `dry "python3 $SCRIPT_DIR/$READING_METRICS_SCRIPT $AGENT_TOOLING_DIR/analysis $TREE --from <t_method_start> --to <t_pr_open>   (reading before the first edit)"`.

## `self/gate.sh`

Line 541: `record "py_compile harness" python3 -m py_compile harness/scorecard.py harness/reading_metrics.py`.
