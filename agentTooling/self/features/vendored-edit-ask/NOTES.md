# vendored-edit-ask — notes

## The flaw

Found by humanNetworkMap's security audit after it pulled ssdesai/agentTooling#141
(`plans/features/pull-agenttooling-pr141/escalations/01-audit-opus.md` there, finding B1).
In a consuming repo the hook's orchestrator allowlist (`hooks/allow-repo-commands.sh`)
approves agentTooling entry points silently — `analysis/report.py`, `analysis/manifest.py`,
`orchestration-start.sh`, `orchestration-capture.sh`, and the `plan-runner-roots.sh` /
`plan-runner-lib.sh` they source. `hooks/wire-settings.py`'s consumer ask rules covered only
`agentTooling/hooks/**` and the records folders. So an Edit or Write to one of those
vendored files was not asked (silently accepted under `acceptEdits`), and the planted code
then ran with no prompt through the allowlisted command.

## Rulings (owner, 2026-11-13)

1. **Fix it upstream, broadly.** In a consuming repo `wire-settings.py` writes an ask rule
   for the whole vendored tree: `Edit(**/agentTooling/**)` (an Edit rule covers the Write
   tool too). Vendored code is never edited in a consumer; it changes only by
   `git subtree pull` (`update.sh`), which writes through git, not the Edit tool, and so is
   unaffected by the rule. Closing the hole per-file would have to track every entry point
   the allowlist ever gains; the tree-wide rule does not.
2. **The narrower vendored rules are retired.** `Edit(**/agentTooling/hooks/**)` and
   `Edit(**/agentTooling/self/orchestrations/**)` are strictly subsumed by the broad rule,
   so they are no longer needed. They leave `POLICY_ASK_RULES`, and their exact strings
   are removed from a consumer's settings wherever this helper writes (a retired-ask list,
   the twin of `RETIRED_EDIT_DENY_RULES`) — one rule per concern, and no stale rule that
   reads as if it were the boundary. The removal happens in the same write that adds the
   broad rule, so there is no moment with neither. A repo's own spelling of a rule is the
   repo's and is left alone.
3. **`Edit(**/plans/orchestrations/**)` stays**: the records are outside the vendored tree.
4. **agentTooling's own checkout (`--self`) is unchanged**: its rules
   (`SELF_POLICY_ASK_RULES`) and its tracked `.claude/settings.json` do not move. In the
   standalone checkout agentTooling IS the repo and is edited normally.
5. **No consumer-side lifecycle step edits under `agentTooling/`.** Records live in
   `plans/orchestrations/` (orchestration-records-in-repo); manifests, briefs and NOTES in
   `plans/features/`; seeded files in `plans/`. A legacy record a consumer still has under
   `agentTooling/self/orchestrations/` was already asked before this change, so nothing
   newly prompts there. The scripts that write records and manifests do so as
   subprocesses, which no Edit rule sees.

## Implementation notes

- **Retirement mirrors `RETIRED_EDIT_DENY_RULES`.** `RETIRED_EDIT_ASK_RULES` is a tuple of
  the two exact strings; `gaps_in` gains one element, `retired_ask` (after `retired_edit`),
  read from `permissions.ask` with `present_rules`; `apply_gaps` drops it from `ask` before
  appending the missing broad rule, in the same pass; `describe_changes` reports it as
  "N retired Edit ask rule(s) (...)" (`--check`: "... to remove"). No new mechanism.
- **Consumer mode only.** `gaps_in` returns `[]` for the retired asks under `--self`, so a
  `--self` generation never touches them (it generates from an empty file, where none are
  present anyway); `SELF_POLICY_ASK_RULES` and the tracked `.claude/settings.json` are
  unchanged, and `--self --check` on this checkout is `in-sync`.
- **Order after a write.** Retired asks leave where they stand; the broad rule is appended
  after whatever the repo kept, like any missing ask rule. A file that already carries the
  broad rule and nothing retired reports `in-sync`/`kept` and is not rewritten.
- **Verified read-only:** `update.sh` writes the vendored tree only through
  `git subtree pull --prefix=... --squash` (plus a `git commit-tree`-style re-anchor), never
  the Edit tool; `sync-plans.sh` writes `plans/` and `.claude/settings.json` as subprocesses.
  No template, lifecycle script or doc tells an agent to Edit/Write under `agentTooling/`
  (searched `templates/`, `*.sh`, LIFECYCLE/RUNNER/ORCHESTRATION/AGENT_* and CONVENTIONS);
  nothing needed fixing. `self/tests/security-audit.sh` does not list the ask rules.
- **Docs:** `hooks/README.md` (rules block, a new "why tree-wide" paragraph, retired-ask
  prose, the retired-kinds count three to four, records section, the cross-layer
  dependency bullet), `README.md` (`sync-plans.sh` and `hooks/` rows), `self/README.md`,
  `self/BACKLOG.md` (one spelling), `self/tests/README.md`. Historical records and
  `self/DESIGN-2026-09-17-policy-module.md` keep the old spelling.

## Excluded

- Narrowing the orchestrator allowlist itself: the owner's ruling closes the hole at the
  write, which also covers any entry point added to the allowlist later.
- Subprocess writes to vendored files (a Bash `>` or a script): those are the hook's
  business (it sends back shell-authored files) and the sandbox's, not an Edit rule's.
