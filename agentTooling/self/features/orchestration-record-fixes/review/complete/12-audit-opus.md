# 12 — security audit: orchestration-record-fixes

Queued by `run-review.sh` beside this round's review, because the feature's diff against
`origin/main` changes the hook — the PreToolUse policy or the settings that wire it
(`LIFECYCLE.md` → "The security audit"):

- `analysis/README.md`
- `analysis/report.py`
- `hooks/README.md`
- `hooks/allow-repo-commands.sh`

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

Do not edit any file in the repository: the review that runs after you judges this same
tree, and the close requires your verdict and its verdict to name one head. Your only
write in the repository is your report.

## Verdict

Write the report to the path the prompt names. Its first line is exactly
`Verdict: clean` (no bypass found) or `Verdict: escalated` (at least one bypass, each
listed with the input that reproduces it and what the rule should do instead). "No
bypass found" is a legitimate verdict when the table shows the attempts.
