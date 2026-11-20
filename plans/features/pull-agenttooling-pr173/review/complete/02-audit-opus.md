# 02 — security audit: pull-agenttooling-pr173

Queued by `run-review.sh` beside this round's review, because the feature's diff against
`origin/main` changes the hook — the PreToolUse policy or the settings that wire it
(`LIFECYCLE.md` → "The security audit"):

- `agentTooling/analysis/README.md`
- `agentTooling/analysis/roots.py`
- `agentTooling/hooks/README.md`
- `agentTooling/hooks/allow-repo-commands.sh`
- `agentTooling/orchestration-start.sh`

This is NOT the review. The review reads the diff for defects that stay green; this audit
tries to get PAST each rule the diff adds or changes, with concrete inputs, and reports
what it found. Read the diff of those files first (`git diff origin/main...HEAD -- <file>`),
then, for every rule the diff adds or changes:

1. Name the rule in one line: what it denies or asks, and for whom.
2. Build a throwaway copy to attack, never this checkout: `git archive HEAD` into a
   directory under your scratch space, and run the hook there with crafted payloads on its
   stdin — the PreToolUse JSON (`tool_name`, `session_id`, `agent_id`, `cwd`,
   `tool_input`) with `CLAUDE_PROJECT_DIR` pointing at the copy. A rule that reads files
   (records, manifests, settings) is attacked by editing those files in the copy.
3. Try at least the obvious families against it: wrappers and indirection in front of a
   program (`env`, `env env`, `/usr/bin/env`, `command`, `exec -a`, `nohup`, `xargs`,
   `sudo`, `find -exec`, `bash -c`, a pipe into a shell, a heredoc), quoting and
   splitting (`"…"`, `pa""th`, backslashes), globs and brace groups, variables and
   substitutions, inputs just inside and just outside every pattern or regex the diff
   adds, malformed and missing payload fields, and edits to any file the rule trusts.
4. Record every input you tried and its result — allowed (no output or `allow`), asked,
   or denied — in a table. A bypass is an input the rule exists to deny that it does not.
5. Class every finding — every input whose result you would report as wrong — as
   `blocking` or `non-blocking`, by the repository owner's ruling (2026-11-16, amended by
   `audit-blocks-only-new`):
   - **blocking** is only a REGRESSION: the result on this head is more permissive than
     on the base for the same input — a deny or an ask that becomes an allow, or a deny
     that becomes an ask. That includes a silent allow the head introduces (the base
     denies or asks, the head allows).
   - **non-blocking** is every other finding: pre-existing (the base's result for the same
     input is the same), prompt-only (the head asks where it should deny, and the base
     does not deny it either), and a pre-existing silent allow (the base allows the same
     input too). List a pre-existing silent allow under `## Non-blocking findings`,
     flagged as a pre-existing silent allow, with what the rule should do instead; the
     feature that sees it files it in its BACKLOG (`self/BACKLOG.md`, or
     `plans/BACKLOG.md` in a consuming repo) before it closes, as a `<slug>: backlog`
     commit after the clean verdict — no new round.
   For a rule that is not the hook's — a refusal in a lifecycle script — "allowed" means
   the script goes on where it should have refused, and the REGRESSION rule applies the same way.
   The evidence for `non-blocking` is the base's result for the same input: build a
   second throwaway copy from `git archive origin/main` and run the base's hook (or
   script) there with the same payload. A finding you cannot class with that evidence —
   the base would not run, the input has no base counterpart, you did not try it on the
   base — is `blocking`. This applies to a propagation too: a consuming repo's
   `pull-agenttooling-*` feature, whose base is the vendored agentTooling it replaces.

Do not edit any file in the repository: the review that runs after you judges this same
tree, and the close requires your verdict and its verdict to name one head. Your only
write in the repository is your report.

## Verdict

Write the report to the path the prompt names. Its first line is exactly
`Verdict: clean` (no blocking finding) or `Verdict: escalated` (at least one blocking
finding). Non-blocking findings never escalate the round, and are never left out of the
report. Then, in this order:

- the table of every input you tried and its result;
- a section headed exactly `## Findings`, holding one Markdown table and nothing else —
  or the single line `None.` when there are no findings. Its header row's first cell is
  exactly `class`, and every other row's FIRST cell is the class,
  exactly `blocking` or `non-blocking`, then the input, this head's result, the base's
  result, and the evidence (the command you ran on each copy). `feature-close.sh` reads
  this section: under `Verdict: clean` it refuses a row classed `blocking`, a row with any
  other first cell, any other line in the section, and a report with no such section;
- a section headed exactly `## Non-blocking findings`, listing each non-blocking finding as
  a follow-up to file — the input, both results, and what the rule should do instead — or
  `None.`; a pre-existing silent allow is listed here, flagged as a pre-existing silent
  allow;
- for each blocking finding, the input that reproduces it and what the rule should do
  instead.

"No findings" is a legitimate verdict when the table shows the attempts.
