# Notes: cost-capture-collisions

Rulings made during the direct build, one line of rationale each. The sole-claimant cut
itself was decided in the manifest and is not reopened here; only how it was built is.

## §4 — runner children and the parent's session id

1. **Scrub at the one launch site.** `plan-runner-lib.sh` `run_plan` is the only `claude -p`
   in the harness (`harness/` is the experiment rig, out of scope). It now runs
   `env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_REMOTE_SESSION_ID …` (names in
   `EXECUTOR_SCRUBBED_ENV_NAMES`, space-separated for bash 3.2) and passes
   `--session-id <uuid>` minted per launch. Every runner inherits it.
2. **uuid source: `uuidgen`, then `/proc/sys/kernel/random/uuid`, then python3's `uuid`**
   (`mint_session_id`), lowercased, each answer checked against
   `EXECUTOR_SESSION_ID_RE`. macOS always has `uuidgen`; Linux has the kernel file; python3
   is already a hard dependency of the analysis. If all three fail the runner warns on
   stderr and launches WITHOUT `--session-id` — never with an empty one — and the scrub
   alone still keeps the parent's id away. Not tested (hiding all three sources from a
   test is not possible without stubbing `/proc`); recorded in `self/BACKLOG.md`.
3. **`write_usage_sidecar` and resume need nothing.** Both read the id out of the stream,
   which now carries the minted id; a resume is a fresh launch and so a fresh mint, which
   is what RUNNER.md "How resume works" already said. The runner prints `session: <id>`
   beside `model:` so a log names it before the stream does.
4. **Recognising a headless tree: the opening prompt carries `HEADLESS_PROMPT_MARKER`**
   ("A progress log is maintained automatically by the harness"). Trees are
   `uuid → parentUuid` links; a `compact_boundary` line's `logicalParentUuid` continues its
   tree though its `parentUuid` is null. A tree's kind is decided by its *opening prompt* —
   the first `user` line in file order with prompt text (string content or `text` blocks,
   never a `tool_result`, which can quote this module) — not by its root line, because a
   root can be an attachment. Rejected: `entrypoint` (inherited — the reproduction shows
   it), `promptSource`/`turnOrigin` (`"sdk"` on this CLI version, corroborating but a field
   the CLI may rename; the marker is the one thing the harness itself writes). The marker
   is in all four runner prompts (run-plans, run-verify's verify and escalation,
   run-review); `self/tests/stream-capture.sh` 11i–11m pin it there, 11j against the
   prompt a runner really sent. `git log -S` reaches only 2026-09-09 (shallow clone): the
   sentence is in every runner prompt as far back as the history goes.
5. **Collision = a headless tree AND an interactive line; unknown is neither.** A line
   with no `uuid`, a dangling chain, or a tree with no prompt is unknown: never evidence,
   never dropped. So a usage.json id whose transcript has no recognisable headless tree
   (a runner predating the marker, every pre-tree fixture) is runner-only and excluded
   exactly as before — the failure mode of the rule is the old behaviour, not a new double
   count. Kept lines are everything not positively headless (so the child's
   `queue-operation` lines, which carry no uuid, stay: unbilled, and inside the
   coordinator's span in practice).
6. **A collided session is an ordinary session made of its interactive lines** — selected,
   priced, timed (its span from those lines alone) and recorded like any other, not in
   `excluded_session_ids`. One warning names it and every sidecar that names it
   (`runner_session_sidecars`, corpus-relative paths). A collided id that is also in the
   manifest's `exclude_sessions` is a manual exclusion as before.
7. **Delegate attribution:** `agent-<id>.meta.json`'s `toolUseId` → the parent line whose
   `tool_use` (or `tool_result`) carries that id → that line's tree; failing that, a parent
   line whose `toolUseResult.agentId` is the delegate's. Headless-spawned: the runner's,
   never priced (a pin on it is warned about and ignored). **When it cannot be told** (no
   meta file, an older CLI): priced as the coordinator's through the ordinary routes, with
   a warning naming the id and saying its cost may also be in the runner's usage.json —
   a disclosed possible over-count rather than a silent loss, the corpus's standing
   preference.
8. **Rule 3: a pin the walk did not reach is looked for everywhere, this repo included**
   (`find_pinned_anywhere`), skipping only delegates whose parent is a runner-only session
   (judged from the parent's transcript since round 2 — see 21).
   This also recovers a pin under a parent the walk skipped for an unclaimable `cwd`
   (another feature's worktree) — a pin is claimed "regardless of branch, window or cwd".
   `cross_repo` keeps its meaning: true only when the hit is under another repo's
   project directory.
9. **`last_branch_instant` is unchanged.** It counts runner sessions deliberately, and a
   collided id is a session on the branch either way: its interactive lines are the
   coordinator's work and its headless tree a runner draining the feature, both evidence
   of when work on the branch stopped. The session's start (what selection keys on) is the
   coordinator's own first line in both readings.
10. **Left alone, recorded in `self/BACKLOG.md`:** `--list-sessions --unclaimed` still
    counts any usage.json id as claimed, so a collided coordinator no feature captured is
    not listed; `recover_attempts.py` prices a collided id's null-cost attempt from the
    WHOLE transcript, coordinator lines included. Both only touch transcripts written
    before the scrub.

## §6 — the ledger knows what it has seen

11. **`seen` shape:** `{<normalized repo identity>: {repo, repo_name, registered_at,
    features: {<slug>: <instant>}}}` — per repo AND per feature, because the review's rule
    is per claimant: a mention is removed only when the ledger has seen *that feature's*
    claims. Written by a capture (its own slug) and by `register_frozen_claims` (each
    frozen record it registers; `registered_at` only when it walked the whole corpus).
    First-seen instants, never refreshed, so a second run over an unchanged corpus writes
    nothing. An old ledger (no `seen`, or the legacy flat shape) loads as nothing seen.
12. **Matching a mention to `seen`:** a mention is a display name (`<repo_name>/<slug>`);
    the record never stored the identity. It is matched case-insensitively against each
    seen repo's `repo_name` and the display name of its identity, and the slug against
    that repo's features. Two repos with one display name both match — the cost is a stale
    mention removed, never a figure moved.
13. **An unseen mention is kept and named on stderr** (`note: <slug>: also_claimed_by …
    not re-checked`), once per (record, session, mention), from both `--annotate-frozen`
    and the `--all` frozen path — never stdout, which `feature-capture.sh` reads as slugs.
14. **`--annotate-frozen` registers this corpus first** (`annotate_corpus` calls
    `register_frozen_claims(…, whole_corpus=True)`), in-flight features skipped as `--all`
    skips them.
15. **Normalisation is for comparison only:** `normalize_repo_identity` (scheme, `user@`,
    port, scp-style `:`, trailing `/` and `.git` dropped, lowercased) behind `claim_key`,
    used at every `(repo, slug)` comparison — `check_claims`, `record_claims`,
    `other_session_claimants`, `record_session_claims`, `add_session_claims`,
    `other_feature_pins`, `session_claim_intervals`' dedupe, `pin_over_parent_advice`.
    Stored `repo` strings and every display name are untouched.
16. **Real-corpus acceptance:** with a scratch empty `HOME`, `--self --annotate-frozen
    --except cost-capture-collisions` over this corpus prints no slug, changes no file
    (run first on a scratch copy, then on the checkout; `git status --short self/features`
    empty), registers 55 frozen features as seen, and prints 31 `not re-checked` notes, all
    for features of humanNetworkMap, musicMap and vinylCatalogue. Registration added no
    mention anywhere.

## The sole-claimant cut

17. **Taken only when it removes something** (`pin_is_cut`): one claim's coverage (window
    plus bounded head) is contiguous, so a session wholly inside it is detected by its
    first and last instants. A pin wholly inside its window keeps the unshared record byte
    for byte — no `share_basis` — which is what kept `session-share.sh` 6/11, every
    `session-claims.sh` phase and every frozen-record test unchanged. The figure is the
    same either way; only whether the record carries split fields differs.
18. **Wording:** the boundary warning's cut path says `not counted here (the session is
    pinned and this feature is its only claimant, so it is cut to the window …)`; the
    unshared path's parenthetical now says the session was selected by branch (only a
    branch session can reach it); the "shared by N claimant(s)" line is replaced, for a
    cut, by "pinned and claimed by this feature alone, so it is cut to the window". The
    unclaimed warning (head / rest, `set-window-from`) is reused unchanged.
19. **`capture_feature`'s fields with one claim:** `share_basis` = `[self]`,
    `session_cost_usd`, apportioned `duration_s`, `unclaimed_usd`, `unclaimed_duration_s`
    — all right with one claim (asserted by `session-share.sh` 21a–21h). `report.py` needs
    nothing: `compute_shared_sessions` skips an entry whose `share_basis` names only
    `self`, so no shared-session entry or footnote appears (21l–21m).

## Round 2 — the fallbacks (round 1's review escalation)

21. **A pinned-delegate fallback hit's parent is judged from the parent's own transcript**
    (`fallback_parent_collision`: `<project dir>/<parent id>.jsonl` beside the delegate's
    directory, `runner_collision` then `spawning_tree`), not by running the session
    fallback first and carrying its flags forward. Reason: it also covers the collided
    parent in this repo's directories that the walk skipped for an unclaimable `cwd`,
    which the session fallback never visits, and it makes the two loops' order irrelevant.
    A runner id whose transcript is not on disk stays runner-only (the old exclusion); the
    runner tree's delegate is not priced and its pin warned ignored; an untold one is
    priced and warned — the main walk's wording, now shared (`runner_spawned_pin_warning`,
    `untold_spawner_warning`). Asserted by `subagent-capture.sh` C12–C14b.

## Assertions changed

20. **`session-share.sh` phases 12 and 14 now select their sessions by branch** (own
    branches, no pin). They pinned the unshared path's disclosure (`counted in full`; no
    figure for a quantity of nothing), and a pin that outruns its window no longer takes
    that path — the behaviour this feature changes. Their `check` lines are unchanged; the
    pinned twin is the new phase 21. Phase 6 and 11 still pin (inside the window).
