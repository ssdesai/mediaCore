# Propagation pull `pull-agenttooling-pr169` — child brief (one per consuming repo)

Ordered by the owner on 2026-11-19 ("make a pull for each agentTools consumer to update the
version now"). agentTooling main at a130257f (#169, the newest merged PR; it carries #166–#169:
`feature-sync.sh`, the brief-conformance checks, the hook sweep, `--branch claude/<slug>`).
One cloud child per repo, model `claude-sonnet-5-5` per `LIFECYCLE.md` → "Propagate" step 4.
Repos: humanNetworkMap, mediaCore, vinylCatalogue, musicMap, and musicTools if it vendors
agentTooling (the child checks and stops if it does not). The text below is sent with `<REPO>`
replaced.

---

feature: <REPO>/pull-agenttooling-pr169

<REPO> propagation pull `pull-agenttooling-pr169` — implementer brief

## Role

You are the session for ONE feature in `ssdesai/<REPO>`: the propagation pull of agentTooling PR #169 (agentTooling `main` at `a130257f`, which also carries #166–#168). An orchestrator session created you (orchestration `tooling-wave-2026-11-18`). It reads your final report; if you are blocked, say exactly what you need and stop. Never merge your PR: the orchestrator merges it with a **merge commit** (never squash).

## Steps

0. If `<REPO>` has no `agentTooling/` directory at its root, it is not a consumer: report "not a consumer" and stop, changing nothing.
1. Attach agentTooling first: call the `add_repo` tool (claude-code-remote MCP) with owner `ssdesai`, repo `agentTooling`, access `read`. Without it the subtree fetch fails to authenticate.
2. Read `agentTooling/LIFECYCLE.md` → "Propagate" and `agentTooling/README.md` → "Updating" in THIS repo's vendored copy, and follow them; where they and this brief differ on a step, follow them and say so in your report.
3. Start, in the background with output to a scratchpad file, waiting for its exit notification (no `sleep`, no polling): `./agentTooling/feature-start.sh pull-agenttooling-pr169 --method hand --branch claude/pull-agenttooling-pr169`. If the vendored start refuses `--branch` or the cloud layout, follow the docs' fallback for a copy that predates it and say so. Your branch is `claude/pull-agenttooling-pr169`; create or push no other.
4. Pull: `agentTooling/update.sh` (or, for a copy with no cloud path, `git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling main --squash` then `agentTooling/sync-plans.sh`). Read its `chain` line. On a conflict with no local edits under `agentTooling/`, take upstream's whole tree exactly as the docs say (`git rm -r -q -- agentTooling`, `git read-tree --prefix=agentTooling/ -u MERGE_HEAD`, `git commit`), never `git merge --abort`. If there ARE local edits under `agentTooling/`, stop and report them.
5. Commit what `sync-plans.sh` wrote, and any hand-merge its `DRIFT` lines ask for. Read any `EDITED` / `OVERWROTE` line and move hand edits into `plans/PROJECT_FACTS.md` as the docs say.
6. Gate: the repo's gate (`./plans/gate.sh` if present, else what `plans/PROJECT_FACTS.md` names), in the background, output to a scratchpad file; wait for its exit notification. Fix failures caused by the pull in the repo's own files, never by editing `agentTooling/` and never by weakening a check; if a failure needs a judgment call, stop and report it.
7. Review and close per the docs (`run-review.sh pull-agenttooling-pr169`, then on `Verdict: clean` `feature-close.sh pull-agenttooling-pr169` straight away). A pull that changes an audit path gets the security audit too. After 2 escalated rounds stop and report.

Commit subjects are prefixed `pull-agenttooling-pr169:`; every commit message ends with the two trailer lines your session instructions give you. Never put a model identifier in a committed file. Never edit `.claude/`.

## Report, terse

The PR URL; the `chain` line before the pull and the `split` sha pulled; whether it conflicted and how it was resolved; `sync-plans.sh` lines other than OK (DRIFT / EDITED / OVERWROTE) and what you did; gate result; review verdict; cost. Last line: the PR link, "not a consumer", or the exact blocker.
