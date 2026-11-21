# Propagation pull `pull-agenttooling-pr173` — catch-up brief (mediaCore, vinylCatalogue)

These two repos merged an earlier pull: mediaCore #42 at a130257f, and vinylCatalogue #310 at
4e20b19e. This catch-up brings both to agentTooling main 25b332c9, which carries #170–#173,
including the two hook security fixes. The steps are the same as `pull-agenttooling-pr169-brief.md`
with the slug `pull-agenttooling-pr173`, on sonnet. The text below is sent with `<REPO>` replaced.

---

feature: <REPO>/pull-agenttooling-pr173

<REPO> propagation pull `pull-agenttooling-pr173` — implementer brief

## Role

You are the session for ONE feature in `ssdesai/<REPO>`: the propagation pull of agentTooling main at `25b332c9` (PR #173; it also carries #170–#172). An orchestrator session (session_0175k4pGGZCBv63KaXaGDio4, orchestration `tooling-wave-2026-11-18`) created you and reads your report. Send it with the claude-code-remote send_message tool, session_id "@parent". If you are blocked, say exactly what you need and stop. Never merge your PR: it is merged with a **merge commit** (never squash).

## Steps

0. Check that `<REPO>`'s main already contains the previous pull. Its `agentTooling/` must not be older than split a130257f (mediaCore) or 4e20b19e (vinylCatalogue); `agentTooling/update.sh`'s chain line shows the split. If the previous pull PR is unmerged, stop and report.
1. Attach agentTooling first: call the `add_repo` tool (claude-code-remote MCP) with owner `ssdesai`, repo `agentTooling`, access `read`. If the permission check refuses it, stop and report; the owner approves it in your session.
2. Read `agentTooling/LIFECYCLE.md` → "Propagate" and `agentTooling/README.md` → "Updating" in this repo's vendored copy, and follow them. Where they differ from this brief, follow them and say so.
3. Start the feature in the background, with output to a scratchpad file, and wait for its exit notification (no `sleep`, no polling): `./agentTooling/feature-start.sh pull-agenttooling-pr173 --method hand --branch claude/pull-agenttooling-pr173`.
4. Pull with `agentTooling/update.sh` and read its `chain` line. On a conflict with no local edits under `agentTooling/`, take upstream's whole tree as the docs say; never run `git merge --abort`. If there ARE local edits under `agentTooling/`, stop and report them.
5. Commit what `sync-plans.sh` writes. That includes `.claude/settings.json` wiring when it only adds or widens ask/deny rules; quote its "wired" line in the report and the PR. Stop and report instead if it removes an ask or deny rule without a broader replacement, or adds an allow rule. Hand-merge any `DRIFT` lines. Move any `EDITED` / `OVERWROTE` hand edits into `plans/PROJECT_FACTS.md`.
6. Gate: run the repo's gate in the background, with output to a scratchpad file. Fix failures caused by the pull in the repo's own files, never under `agentTooling/` and never by weakening a check. If a failure needs a judgment call, stop and report it.
7. Review and close: `run-review.sh pull-agenttooling-pr173`, and on `Verdict: clean` run `feature-close.sh pull-agenttooling-pr173` straight away. The pull changes `hooks/`, so it gets the security audit. After 2 escalated rounds, stop and report.

Commit subjects are prefixed `pull-agenttooling-pr173:`; every commit message ends with the two trailer lines your session instructions give. Never put a model identifier in a committed file. Never edit `.claude/` by hand.

## Report, terse

The PR URL; the `chain` line before the pull and the split pulled; any conflict and how it was resolved; `sync-plans.sh` lines other than OK; gate result; review and audit verdicts; cost. Last line: the PR link, or the exact blocker.
