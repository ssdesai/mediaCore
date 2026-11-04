# Checkpoint: shell-write-rewrite

status: committed
updated: 2026-09-21T23:08:02Z
gate: all checks passed (shellcheck skipped: not installed, as on main)

## Slices
- [x] acceptance tests — self/tests/allow-repo-commands.sh (AUTHORING_REWRITE,
      AUTHORING_NOT_DENIED, member cases, precedence; moved cases; replay record),
      self/tests/hook-escalation.sh (§9h–9i, resetter), self/tests/routing-record.sh (R11),
      self/tests/feature-lifecycle.sh (S3a3–S3a4) — committed red on their own
- [x] 1. hooks/allow-repo-commands.sh — redirect_members, authoring_reason_lines, judged in
      command_verdict after ALLOW and before opaque_deny_reason
- [x] 2. analysis/routing.py — parse_manifest (moved from report.py), pinned_sessions,
      split_pinned; report.py table/fraction/routed-by call it, --all names skips
- [x] 3. feature-start.sh — --pin writes no routing record; header comment
- [x] 4. docs — hooks/README.md, CONVENTIONS.md, analysis/README.md, LIFECYCLE.md step 2,
      self/PROJECT_FACTS.md, self/tests/README.md rows, self/BACKLOG.md (two entries)
- [x] gate green, NOTES.md, commit

## Learned
- opaque_segments splits `2>&1`, `&>`, `>|` at the `&`/`|`, so the shape needs its own
  redirect-aware scanner; shlex drops quotes so a quoted `>` is indistinguishable.
- routing.py cannot import report/capture_planning/manifest (all import it).
- feature-lifecycle.sh prints a harmless "No such file" at its T5 phase on main too.

## Resume
- Nothing to resume: the build commit is on the branch; the review pass is next
  (`./run-review.sh --self shell-write-rewrite`).
