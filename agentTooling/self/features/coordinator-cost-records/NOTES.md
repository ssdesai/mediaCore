# coordinator-cost-records — notes

Rulings and facts the build rested on. Built by hand, by an Agent delegate of the
coordinator it records (session `4cba07a3-…`), in a clean clone on
`claude/coordinator-cost-records`.

## Rulings

- **A flag on the existing record, not a new record kind or a new folder.** The coordinator
  record is an orchestration record (`self/orchestrations/<slug>/README.md`, the same
  fence, the same `manifest.py --orchestration`, capture and report) with `"kind":
  "coordinator"` added after `slug`. Absent `kind` reads as `orchestrator`, so the four
  existing records and every reader of them are unchanged. One file shape, two readings of
  it: the role rule and the capture branch on `kind`, nothing else does.
- **It may be retroactive and is closed by the same `set-window-to`.** `--coordinator`
  defaults `from` to the session's first transcript instant, so registering a session
  after the fact covers it whole; `--from` overrides it (either kind). The window is closed
  with `set-window-to` as before; `ablation-wave`'s is closed at 2026-11-08T17:41:09Z and
  can be moved later and re-captured.
- **No role — checked, not assumed.** A subagent shares its parent's session id in both
  places the role is read: the hook payload (`allow-repo-commands.sh`'s `SESSION_FIELD`
  comment: a subagent's payload carries the PARENT's `session_id` and its own `agent_id`)
  and the shell — this delegate's `$CLAUDE_CODE_SESSION_ID` is `4cba07a3-…`, its parent's,
  and its own `feature-start.sh` stamped `from` at the parent's first instant. Keyed on
  `session`, a role would have refused this very feature's start, review and close. So
  `orchestrator_role.record_for_session` skips a coordinator record, and the reverse guard
  in `orchestration-start.sh` is skipped for one (it exists to stop a coordinator becoming
  an orchestrator, which a coordinator record never makes it). Asserted by
  `hook-orchestrator-role.sh` H10 (with and without `agent_id`) and `coordinator-records.sh`
  K2.
- **What the coordinator's line holds.** Its own transcript, plus its own delegates: brief
  `feature: none — …` and claimed by no feature (the machine's claims ledger, and the
  `subagents` pins of every manifest this checkout can read). Every other delegate — one
  briefed for a feature, or claimed — is left to the feature and listed in
  `subagents_not_priced`. This widens the brief's "own transcript only" by one class: a
  `feature: none` delegate is, by its own header, work no feature owns, so on the
  coordinator's line it is counted once and otherwise nowhere. For `ablation-wave` that is
  `ab83534d098ac10f0` ($4.99, "cost bookkeeping: pinning other sessions' delegates"), the
  pin-repair work itself. Without it the line is $39.32.
- **A coordinator's session pinned by a feature is warned about, not subtracted.** A
  manifest `sessions` pin, or the ledger's session section, naming the coordinator means
  that feature already counts the transcript; the capture says which and keeps its figure.
  None exists for `4cba07a3`.
- **Cross-repo features are priced, not left unpriced.** A feature's `report` may be
  relative to its own repository; `report.py --orchestration <slug> --checkout
  <repo>=<path>` resolves it there. Without the flag such an entry is unpriced with a reason
  naming the flag, so the report never silently mixes repos. The committed report was
  generated with `--checkout vinylCatalogue=/home/user/vinylCatalogue` (vinylCatalogue
  `main` at `e05de09c`).
- **(4) — where a coordinator starts.** Doctrine plus one advisory; nothing automatic.
  - `ORCHESTRATION.md` → "Coordinator shapes": launch a coordinator inside a repository
    checkout, on its default branch; how to record a wave coordinator.
  - The advisory is in `feature-start.sh` (cloud profile, on the coordinator path only),
    via `analysis/coordinator_check.py`: the start already assumes its session is the
    feature's coordinator, and when that session's first `cwd` is outside the start's
    checkout and no record names it, it is in fact someone else's coordinator. It names
    `orchestration-start.sh <slug> --coordinator --session <id>`, and adds that the
    directory is in no checkout (so no hooks ran there) when that is so. This feature's own
    start printed the misleading "it is the feature's coordinator" line that motivated it.
  - **Not a SessionStart check**: `session-start.sh` is wired by a repository's
    `.claude/settings.json`, which a session launched above the checkouts never loads
    (`/home/user` has no `.claude/`, and there is no user-level `settings.json` in this
    container) — the one case to catch is the one where it cannot run.
  - **Not an automatic record**: a session cannot be known to coordinate several features
    when it starts, and a record for a single-feature coordinator, already claimed by its
    branch, would double count it.

## Facts

- `ablation-wave` figures (window 2026-11-05T16:39:00.566Z → 2026-11-08T17:41:09Z):
  coordination overhead **$44.31** ($39.32 own transcript, all main-thread, no sidechain;
  $4.99 own `feature: none` delegate); 14 delegates left to features; eight priced
  features **$137.88**; group **$182.19**, overhead 24.3%. `coordinator-cost-records` is
  unpriced until its own `report.json` exists.
- `harness-ablation-methods` (#130) is in the record though the brief did not list it: its
  manifest pins `a37c317fcba738986`, a delegate of this session, and it was built on
  2026-11-05 inside the window.
- `agent_tooling` in `ablation-wave` is the commit the record was written at
  (`8f9e0b4`, this feature's start), not one the session ran under; the record's prose says
  so.

## Open

- Whether the Claude Code app lets the user choose a multi-repo cloud session's starting
  directory was not verifiable from inside the container (the environment docs do not
  cover it). The doctrine says "unless its starting directory is chosen in the app"; if it
  cannot be chosen, a wave coordinator in the cloud will keep starting at `/home/user`, and
  the record plus the start's advisory are the remedy.

## Commands

    ./orchestration-capture.sh ablation-wave
    python3 analysis/report.py --orchestration ablation-wave --checkout vinylCatalogue=/home/user/vinylCatalogue
    python3 analysis/manifest.py --orchestration ablation-wave set-window-to now
    bash self/tests/coordinator-records.sh
