# 01 — review: orchestration-start-branch-v2

Review the diff against the spec below — written before the build, from the orchestrator's
brief and `self/BACKLOG.md`, not from the builder's report. "No findings" is a legitimate
verdict. A finding blocks only when an item below is not closed or the diff introduces a
regression; anything else is filed in `self/BACKLOG.md` as non-blocking.

## What the feature was supposed to do

Two gaps the orchestrator role hits at the start of every wave.

1. **`orchestration-start.sh --branch claude/<slug>`.** A branchless cloud session (a
   detached HEAD, or `main`) has no sanctioned way onto a branch of its own unless it starts
   a feature. Under the cloud profile, for an orchestrator record (not `--coordinator`):
   - on a detached HEAD or on `main` with no `--branch`, the start is refused, and the
     refusal names `--branch claude/<slug>`; nothing is written;
   - with `--branch <name>`, the start cuts `<name>` off `origin/main` BEFORE it writes the
     record, then writes the record (and the ledger line) and commits the record on that
     branch;
   - whether `<name>` already exists is asked of ORIGIN, not the local remote-tracking
     cache: with an `origin` remote, `git ls-remote --exit-code --heads origin
     refs/heads/<name>` — exit 0 refuses (it exists), exit 2 goes on, any other exit refuses
     ("cannot ask origin"). A local branch of that name refuses too;
   - a branch some tracked feature manifest already names as its `branches[0]` is refused;
   - manifests are enumerated NUL-separated (`ls-files -z` / `ls-tree -z`, `read -r -d ''`),
     and the existing reverse guard `held_feature` is fixed the same way, so a manifest
     directory whose name git would C-quote is not silently skipped;
   - the decision on unmerged features' branches (manifests on origin's `claude/*`
     branches) is recorded in the feature's `NOTES.md`, whether or not they are read;
   - the orchestrator brief template (`templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`,
     with its template version bumped per `templates/README.md`) and `ORCHESTRATION.md`
     use the new flag.

   Excluded: the harness experiment driver's same gap stays in the backlog. The local
   profile's behaviour is not asked to change.

2. **The orchestrator may `git mv` its own stranded record.** `orchestration-start.sh`
   refuses a record stranded at the legacy vendored path with
   `shared_rules.LEGACY_RECORD_REFUSAL`, naming `git mv agentTooling/self/orchestrations/<slug>
   plans/orchestrations/<slug>`, but the orchestrator's Bash allowlist denied that remedy.
   Now an orchestrator session's `git mv agentTooling/self/orchestrations/<slug>
   plans/orchestrations/<slug>`, naming its OWN record and nothing else, is approved; a move
   of any other path — another record, any other file, a different destination, extra
   arguments or options, a standalone (non-vendored) checkout — is still denied.

   Excluded: parts 2–4 of the backlog entry "The orchestrator role has four gaps" stay in
   the backlog; the entry is rewritten without part 1.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `orchestration-start.sh`: usage line and header document `--branch <name>`; the refusal
  on a detached HEAD / `main` contains `--branch claude/<slug>`; every refusal happens
  before any write (record, ledger, branch); exit codes stay 2 usage, 1 refusal; a
  `--coordinator` record and the local profile are unaffected; the ls-remote exit-code
  mapping is exactly 0 refuse / 2 go on / other refuse.
- `held_feature` and the new manifest scan read NUL-separated output.
- `hooks/allow-repo-commands.sh`: the orchestrator allowlist (`orchestrator_command_allowed`,
  `orchestrator_git_allowed`) admits `git mv` only as the exact record move; the
  `ORCHESTRATOR_ALLOWLIST_TEXT` names it; no other orchestrator shape widens; every new
  literal is a named constant.
- Tests: `self/tests/orchestrator-role.sh` (or a new self test registered in
  `self/tests/README.md` and run by the gate) covers: detached-HEAD refusal naming the
  flag; the record committed on the cut branch; refusal when the branch exists on origin
  in a clone that fetches only `main`; refusal with an unreachable origin URL; a C-quoted
  manifest directory found by `held_feature`; `--branch` against a vendored
  `plans/features` corpus. `self/tests/hook-orchestrator-role.sh` covers the approved move
  and the denied variants.
- Docs: `hooks/README.md` → "The orchestrator role" table, `ORCHESTRATION.md` → "Cloud
  sessions" (the Bash allowlist bullet and the start), the brief template and its version,
  `self/BACKLOG.md` entries rewritten/removed, the folder READMEs of touched folders.
- `./self/gate.sh` green.

## Verdict
