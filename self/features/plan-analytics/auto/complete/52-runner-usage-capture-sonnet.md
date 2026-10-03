# 52 — Per-plan usage sidecar in the runner

Feature: plan-analytics (plan 4 of 9) — tooling to price a feature end-to-end (planning
plus execution) and surface where delegated fanout wasted effort. This plan adds the
per-run cost record everything else reads: `finalize_plan()` writes a committed
`<plan>.usage.json` sidecar extracted from the run's final `result` event, so per-plan
cost survives the gitignored `.stream.jsonl`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Independent of other plans.

## Pinned facts

- `finalize_plan()` starts at line 244 of `agentTooling/plan-runner-lib.sh`. It takes
  `plan_path` and `rc`, derives `log_path` and `stream_path`, and has four branches:
  `rc==2` (usage limit — exits immediately, leaving plan/log/stream in `inprogress/`,
  no `mv` at all), `rc==3` (budget cap — `mv`s plan/log/stream to `$FAILED_DIR`),
  `rc!=0` (failure — same three `mv`s to `$FAILED_DIR`), and the fallthrough success
  path (same three `mv`s to `$COMPLETE_DIR`).
- `extract_model()` (lines 73–85) already derives the model name from a plan filename
  stem (`NN-description-MODEL.md`, trailing `-`-segment, falls back to `sonnet` with a
  `WARN` on stderr for an unrecognized suffix). Reuse it — don't re-derive the parse.
- `require_tools()` (line 292) already fails the run at startup if `jq` is missing, so
  both runners can rely on `jq` being present.
- `$REPO_DIR` is in scope throughout `plan-runner-lib.sh`; both wrappers set it via
  `REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"` — **no trailing slash**. When passed to
  `jq` for path-stripping, append one: `--arg repo "$REPO_DIR/"`.
- `run-plans.sh:2` and `run-verify.sh:2` set `set -uo pipefail` — **no `-e`**. A
  standalone failing command does not abort the runner on its own; suppress `jq`'s
  stderr anyway (matching the existing convention at the two other call sites,
  `stream_shows_usage_limit` and `stream_shows_budget_exhausted`) so a malformed
  stream doesn't spam the terminal, and clean up any truncated output file rather
  than leave a zero-byte `.usage.json` behind.
- `agentTooling/.gitignore` (repo-root `.gitignore` via the subtree) ignores only
  `plans/**/*.stream.jsonl` and `plans/**/*.logfifo`. `.progress.md` and the new
  `.usage.json` are committed.
- Plan filenames are `NN-description-MODEL.md`.

## Files

- Modify `agentTooling/plan-runner-lib.sh`
- Modify `agentTooling/RUNNER.md`

## `agentTooling/plan-runner-lib.sh`

**1. Insert a new function immediately before the `# After run_plan returns, route the
plan + log to the right folder.` comment** (i.e. directly above `finalize_plan`). Match
on that comment text, **not** on a line number — plan 48 rewrote the top of this file and
shifted everything below it. This exact jq filter has been run against a real captured
stream (`40-ingest-real-copies-haiku.stream.jsonl`, now under
`plans/features/image-versions-and-copies/auto/complete/`) and verified to
produce `total_cost_usd: 0.1647174`, `num_turns: 14`, and 3 repo-relative
`files_edited`. Note `is_error` is read as `$r.is_error` directly, not `$r.is_error //
null` — jq's `//` treats `false` the same as `null`, so a successful run (`is_error:
false`) would otherwise get silently rewritten to `null`.

```bash
# Extract a small, committed cost/usage summary from the run's final `result` event, so
# per-plan cost survives after the (gitignored) .stream.jsonl is gone. Called from the
# top of finalize_plan, before any mv, while stream_path is still where run_plan left it.
# Non-fatal: guarded on the stream file existing, jq's stderr is suppressed the same way
# the other two call sites in this file suppress it, and a failed/partial jq run has its
# output file removed rather than left as a truncated .usage.json.
write_usage_sidecar() {
  local plan_path="$1"
  local rc="$2"
  local stream_path="$3"
  local usage_path="$4"

  [[ -f "$stream_path" ]] || return 0

  local model outcome
  # Suppress stderr here: extract_model's fallback WARN already printed once from
  # run_plan's own call; a second copy here would just be noise.
  model="$(extract_model "$plan_path" 2>/dev/null)"
  case "$rc" in
    0) outcome="complete" ;;
    2) outcome="inprogress" ;;
    3) outcome="budget_exceeded" ;;
    *) outcome="failed" ;;
  esac

  jq -s --arg plan "$(basename "$plan_path" .md)" --arg model "$model" \
    --arg outcome "$outcome" --arg repo "$REPO_DIR/" '
    (map(select(.type == "result")) | last) as $r
    | [ .[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") ] as $tools
    | ($tools | map(select(.name == "Edit" or .name == "Write" or .name == "MultiEdit" or .name == "NotebookEdit"))) as $edits
    | {
        plan: $plan, model: $model, outcome: $outcome,
        session_id: ($r.session_id // null),
        subtype: ($r.subtype // null),
        is_error: $r.is_error,
        num_turns: ($r.num_turns // null),
        duration_ms: ($r.duration_ms // null),
        total_cost_usd: ($r.total_cost_usd // null),
        usage: {
          input_tokens: ($r.usage.input_tokens // 0),
          cache_creation_input_tokens: ($r.usage.cache_creation_input_tokens // 0),
          cache_read_input_tokens: ($r.usage.cache_read_input_tokens // 0),
          output_tokens: ($r.usage.output_tokens // 0)
        },
        model_usage: ($r.modelUsage // {}),
        permission_denials: (($r.permission_denials // []) | length),
        tool_counts: ($tools | group_by(.name) | map({key: .[0].name, value: length}) | from_entries),
        files_edited: ($edits | map(.input.file_path // empty | ltrimstr($repo)) | unique),
        edit_count: ($edits | length)
      }
    ' "$stream_path" > "$usage_path" 2>/dev/null || rm -f "$usage_path"
}
```

**2. Edit `finalize_plan` itself** to compute `usage_path`, call the sidecar writer at
the top (before the `rc == 2` check — that branch never `mv`s anything, so nothing
else needs to change there), and `mv` the sidecar alongside the plan in every branch
that already `mv`s `stream_path`. Apply this diff (unchanged lines shown for context
only):

```diff
 finalize_plan() {
   local plan_path="$1"
   local rc="$2"
   local log_path="${plan_path%.md}.progress.md"
   local stream_path="${plan_path%.md}.stream.jsonl"
+  local usage_path="${plan_path%.md}.usage.json"
   local plan_name
   plan_name="$(basename "$plan_path")"

+  write_usage_sidecar "$plan_path" "$rc" "$stream_path" "$usage_path"
+
   if (( rc == 2 )); then
     exit_reason="stopped: Claude usage limit reached on $plan_name (left in inprogress for next run)"
     exit 1
   fi

   # Deliberately failed/, not inprogress/: a resume would just buy the same brief another
   # budget's worth of turns, which is the behaviour the cap exists to prevent. Hitting it
   # means the plan asked for more than a verify pass should do, and that is a question for
   # whoever wrote it — not something the runner should quietly pay to finish.
   if (( rc == 3 )); then
     mv "$plan_path" "$FAILED_DIR/"
     [[ -f "$log_path" ]] && mv "$log_path" "$FAILED_DIR/"
     [[ -f "$stream_path" ]] && mv "$stream_path" "$FAILED_DIR/"
+    [[ -f "$usage_path" ]] && mv "$usage_path" "$FAILED_DIR/"
     exit_reason="stopped: $plan_name exceeded its run budget (moved to failed; re-scope the brief)"
     exit 1
   fi

   if (( rc != 0 )); then
     mv "$plan_path" "$FAILED_DIR/"
     [[ -f "$log_path" ]] && mv "$log_path" "$FAILED_DIR/"
     # The raw stream is the only record of *why* it failed — keep it.
     [[ -f "$stream_path" ]] && mv "$stream_path" "$FAILED_DIR/"
+    [[ -f "$usage_path" ]] && mv "$usage_path" "$FAILED_DIR/"
     exit_reason="stopped: claude exited with code $rc on $plan_name (moved to failed)"
     exit "$rc"
   fi

   mv "$plan_path" "$COMPLETE_DIR/"
   [[ -f "$log_path" ]] && mv "$log_path" "$COMPLETE_DIR/"
   # Keep the full event stream even on success: it is the complete record of what
   # the model did — tool inputs and results the terminal summary omits. Gitignored.
   [[ -f "$stream_path" ]] && mv "$stream_path" "$COMPLETE_DIR/"
+  [[ -f "$usage_path" ]] && mv "$usage_path" "$COMPLETE_DIR/"
   echo "=== Finished: $plan_name ==="
   echo ""
 }
```

## `agentTooling/RUNNER.md`

In `## Layout and state`, the paragraph currently reads (~line 73):

```
Every finished plan — complete or failed — lands with three files, not two:

- `<plan>.md` and `<plan>.progress.md`. On a failure the log's last line is
  `failed (exit N): <reason>`, extracted from the run's final `result` event, so a plan
  that died before its first Edit still says why instead of leaving an empty log.
- `<plan>.stream.jsonl` — the raw stream-json event log: the full record of what the
  model did, including the tool inputs and results the terminal summary drops. Kept on
  both success and failure so any run can be analysed after the fact. Gitignore it —
  useful locally, too large and too machine-specific to commit.
```

Replace it with (four files now, and a third bullet for the new sidecar — match the
existing terse, imperative voice, reasons stated once):

```
Every finished plan — complete or failed — lands with four files, not two:

- `<plan>.md` and `<plan>.progress.md`. On a failure the log's last line is
  `failed (exit N): <reason>`, extracted from the run's final `result` event, so a plan
  that died before its first Edit still says why instead of leaving an empty log.
- `<plan>.stream.jsonl` — the raw stream-json event log: the full record of what the
  model did, including the tool inputs and results the terminal summary drops. Kept on
  both success and failure so any run can be analysed after the fact. Gitignore it —
  useful locally, too large and too machine-specific to commit.
- `<plan>.usage.json` — a small, committed extract of the final `result` event: cost,
  turns, duration, token counts, tool-call counts, and files edited. Exists because the
  stream it comes from is gitignored and too large to commit — this is what per-plan
  cost survives on. Written by `finalize_plan` before the stream is moved, so it lands
  alongside the plan in whichever directory it settles in.
```

Leave the rest of `## Layout and state` (the per-directory bullet list, the
usage-limit note) unchanged.
