# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **`recover_attempts.py` prices a collided session's null-cost attempt from the whole
  transcript.** A usage.json attempt whose `session_id` is a coordinator's (a runner child
  that inherited the parent's id, design 2026-10-05 §4) and whose `total_cost_usd` is null
  is recovered by summing every line of `<id>.jsonl` — the coordinator's interactive lines
  included, which `capture_planning.py` now prices as the coordinator's. Assertion: an
  attempt whose transcript holds a headless tree and interactive lines recovers the
  headless tree's cost alone (`capture_planning.tree_flags`). Only transcripts written
  before the runner's scrub can collide. Raised by `cost-capture-collisions`.

- **`--list-sessions --unclaimed` hides a collided coordinator.** `claimed_session_ids`
  counts every id a usage.json names as claimed, so a coordinator a runner child collided
  with — priced by no feature yet — is never listed as cost nobody counts. Assertion: a
  session whose transcript holds interactive lines beside a headless tree, named by a
  usage.json and by no planning.json, is listed. Raised by `cost-capture-collisions`.

- **The runner's no-uuid fallback is untested.** `plan-runner-lib.sh` `mint_session_id`
  tries `uuidgen`, `/proc/sys/kernel/random/uuid` and python3's `uuid`, and when all three
  fail launches `claude -p` without `--session-id` and warns, rather than passing an empty
  one. No test hides all three sources. Assertion: with none available, the launch carries
  no `--session-id`, the WARN names the plan, and the child still sees neither
  `CLAUDE_CODE_SESSION_ID` nor `CLAUDE_CODE_REMOTE_SESSION_ID`. Raised by
  `cost-capture-collisions`.

- **The cloud auto-merge body is unverified against the live route.** `forge.sh
  auto-merge` under the cloud profile sends `PUT /repos/{o}/{r}/pulls/{n}/ccr/auto_merge`
  with `-f merge_method=merge` — the REST spelling of GitHub's own merge endpoint; the
  proxy's refusal text names the route but not its body, and `self/pr.sh` never requests a
  merge, so no cloud run has exercised it. A wrong field name is advisory (pr.sh warns and
  the PR waits for a human) but would silently never auto-merge, or merge with the
  repository's default method — a squash would strand the prune. Assertion, by hand at the
  first consuming repo's cloud close under `PR_AUTO_MERGE=1`: the PR shows auto-merge
  enabled with the merge-commit method; if the route wants another field, change
  `CLOUD_MERGE_METHOD_FIELD` and `self/tests/env-profile.sh` F2b together. Raised by
  `execution-profiles` (NOTES.md ruling 19).

- **A vendored `--self` build that changes the policy cannot regenerate the file it
  ships.** In a vendored agentTooling `wire-settings.py --self --write` writes nothing, and
  `--check` holds the shipped `agentTooling/.claude/settings.json` to the generator's bytes
  (`self-cloud-bootstrap` NOTES), so a vendored build that changes `hooks/policy.py` or the
  constants in `hooks/wire-settings.py` turns its own gate red, the fix named upstream:
  such a change can only be built in a standalone checkout today. Assertion, if a vendored
  policy build is ever wanted: a vendored `--self --write` regenerates the subtree's copy
  and nothing else, and the gate's settings check goes green again. Raised by
  `self-cloud-bootstrap`.

- **The SessionStart wiring is unexercised in a real cloud session.** `sync-plans.sh`
  wires `${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh` as a SessionStart hook with no
  matcher, and the seeded script is a no-op until a repo fills it; no consuming repo has
  yet run it in a container. Assertion, by hand at the first consuming repo's cloud setup
  feature: a new session's context shows the script's output line, a resumed session runs
  it again harmlessly, and its gate is green with no `--no-gate`. Raised by
  `execution-profiles` (design §7).

- **`AGENTTOOLING_SCRATCH` approves unread code for headless executors.** The hook
  approves `bash`/`python3` on any script under the runner's per-pass scratch directory,
  judging its path and arguments and never its contents. An executor can write any code
  there with an unprompted Write and run it unseen, which launders every command the hook
  denies for being unreadable. The OS sandbox that would contain it is off
  (`SANDBOX_ENABLED = False`). It was a deliberate trade, since a headless run has nobody
  to answer a prompt. Revisit it by making the approval conditional on the sandbox being
  enabled, or by refusing the scratch entry point when it is not. Assertion: with
  `SANDBOX_ENABLED` false, a headless `bash <scratch>/x.sh` is not approved by the hook.
  Raised by the 2026-10-05 cloud-execution design (§9), which declined to extend the same
  approval to interactive sessions.

- **A dead half-start cut from a stacked `--base` is never pruned.** Since
  `start-takeover`, the prune removes another slug's abandoned half-start (branch at its
  creation commit, clean, start lock naming a dead PID), but only among branches that are
  ancestors of `origin/main` — the prune's first test. A half-start made with
  `--base <unmerged branch>` sits on that branch's tip, which is not an ancestor of
  `origin/main`, so only a re-run of its own slug takes it over; a slug nobody re-runs
  keeps its worktree and branch until a human removes them. Closing it means the prune
  testing a half-start against its creation commit instead of against `origin/main`.
  Assertion: a start of slug A prunes a clean, dead-locked half-start of slug B that was
  started with `--base other`.
  Raised by `start-takeover`.

- **A start killed while its hook or gate is running leaves that child running.**
  `feature-start.sh` runs the setup hook and the gate as children; a `SIGKILL` of the start
  itself (not of its process group) leaves them running inside the worktree while the
  start lock's PID is already dead, so a takeover or a prune in that window removes the
  worktree under a live gate. A Ctrl-C signals the whole foreground group and does not
  hit this. Closing it means recording the child's PID (or the process group) in the lock
  and treating the half-start as live while any of them exists. Assertion: a start whose
  PID is killed while its stub gate sleeps is refused by a re-run of its slug until the
  gate exits.
  Raised by `start-takeover`.

- **`feature-lifecycle.sh` T5 writes its brief into a directory that does not exist.**
  Line ~1450 prints `No such file or directory` for
  `$AT/self/features/lifecycle-one/review/incomplete/99-review-opus.md` — the primary's
  `main` does not carry `lifecycle-one`'s feature directory at that point — on `main` as
  well as on `start-takeover`. The run still reports all assertions passed, so T5 ("a
  review run from the primary on main commits nothing") may be passing without the brief
  it meant to run. Assertion: T5's brief exists before its review runs, and the test
  prints nothing on stderr.
  Raised by `start-takeover` (seen while gating it).

- **Long-context (above 200k input tokens) and other tiered pricing is not priced —
  parked until the tier report flips.** `analysis/rates_history.json` holds one flat rate
  per field, and the refresh reads only LiteLLM's five flat per-token fields. Since
  `rates-tier-check`, `refresh_rates.py --tiers` reports, for every model the corpus's
  cost records name, whether its LiteLLM entry carries a tiered rate (`TIER_SUFFIXES`,
  `*_above_200k_tokens` among them), and `feature-capture.sh`'s residue prints its summary
  on every capture. **Finding, 2026-09-27:** the five corpora on this machine (agentTooling
  self, vinylCatalogue, musicMap, mediaCore, humanNetworkMap) use Fable 5, Fable 5.1,
  Haiku 4.5, Opus 4.8, Opus 5, Opus 5.5 and Sonnet 5, and **none carries a tier** in
  LiteLLM — the only Anthropic entry with one is Sonnet 4.5, which no corpus uses. Prompts
  past 200k are common (about a third of Opus 5 responses in the transcripts), so this is
  not moot, only flat-priced upstream today. Nothing to build until the residue's `tiers`
  line reads "N model(s) carry an above-200k tier"; then tiered pricing is due, to this
  assertion: a transcript message with more than 200k input tokens on a model whose
  LiteLLM entry carries `input_cost_per_token_above_200k_tokens` prices at that rate, and
  one below the threshold at the flat rate (per message — a per-request tier is invisible
  in an aggregate, so `transcript.py` would have to price per message).
  Raised by `litellm-pricing`. **Ruled 2026-09-26:** first have `refresh_rates.py` report
  whether any model the corpus uses carries an above-200k tier; build tiered pricing only if
  one does. Planned as `rates-tier-check`, which built the report and found none
  (`self/features/rates-tier-check/NOTES.md`).

- **No end-to-end test of a propagation pull's cost record.** `LIFECYCLE.md` →
  "Propagate" makes each pull a `pull-agenttooling-pr<N>` hand feature, and
  `self/tests/propagation-pull.sh` asserts `update.sh`'s half (it pulls only inside a
  started feature's worktree, on its branch). That the round's delegates then leave the
  residue is argued from parts tested elsewhere — a worktree session claimed by branch, a
  pinned delegate claimed as `pinned` (`feature-lifecycle.sh` C1–C2) — not asserted
  through one fixture: `feature-lifecycle.sh` drives a standalone `--self` checkout, where
  `update.sh` refuses as the source checkout, and a consumer-shaped lifecycle (vendored
  prefix, `plans/gate.sh`, `pr.sh`, `worktree-setup.sh` stubs, an upstream to pull from)
  does not exist yet. Assertion: in a consumer fixture, a coordinator on `main` starts
  `pull-agenttooling-pr1 --method hand`, a delegate briefed `feature: consumer/
  pull-agenttooling-pr1` runs the worktree's `update.sh` and is pinned with
  `pin-subagent`, the review is clean, and `feature-close.sh`'s capture claims the
  delegate, lists no delegate of that round in its `=== residue ===`, and
  `report.py pull-agenttooling-pr1` shows its cost.
  Raised by `propagation-as-feature`.

- **Unclaimed delegates that belong to a feature in another repo.**
  `abdc44b0d582d0b92` (2026-09-22, $8.74) is the direct implementer for
  `vinylCatalogue/audio-checked-mark`: its brief opens with that `feature:` line, but
  its parent session was on `main`, so no route claims it. Pin it in that feature's
  manifest `subagents` in the vinylCatalogue repo, and re-capture there. Do it together
  with the pending vinylCatalogue repair, which needs a clean `main` there anyway.
  Two "very thorough exploration" delegates, `a64bd100d13188cc7` ($0.73) and
  `aed24720a93f38a51` ($0.95), belong to parent session `a60214fa`, and their briefs name
  no feature. Pin them to whatever feature that session went on to build, or record them
  as that session's routing overhead. Assertion: `capture_planning.py --list-subagents
  --unclaimed --everywhere` lists none of these three ids.
  Raised by `litellm-pricing`. **Ruled 2026-09-26:** pin `abdc44b0d582d0b92` with
  `manifest.py audio-checked-mark pin-subagent abdc44b0d582d0b92` in vinylCatalogue once
  `manifest-pin-subagent` has been propagated there; the two exploration
  delegates are recorded as `a60214fa`'s routing overhead.

- **No consumer verify pass has run under the sandbox, and the read surface there is
  narrower than the block asks for.** `runner-sandbox` validated the block with one
  agentTooling review pass (no network used, `.git/hooks` write refused). On this
  machine `permissions.blockReadsOutsideWorkingDirectories` is on, and the sandbox
  enforces it at the OS level: `ls ~/Library/Caches` from a sandboxed Bash subprocess is
  `Operation not permitted`. A consumer verify pass that runs `npx playwright test`
  (browsers under `~/Library/Caches/ms-playwright`) or a home-directory toolchain (pyenv,
  nvm, `~/.npm`), or that installs a package from a registry not yet listed, will
  probably fail in a way that looks like broken code. **The fix is not in
  `wire-settings.py`:** under that block Claude Code 2.1.286 drops `allowRead` entries
  from repository settings (`sandbox-consumer-reads` proved it live and cites the doc
  sentence in its `NOTES.md`), so the re-allow is a per-machine user-settings entry,
  `sandbox.filesystem.allowRead` in `~/.claude/settings.json`, naming
  `~/Library/Caches/ms-playwright` (and any home-directory toolchain path a run shows
  refused). Until then the block ships **switched off** (`SANDBOX_ENABLED = False` in
  `hooks/wire-settings.py`, since `sandbox-consumer-reads`), so the runners execute
  without the OS boundary. Assertion: with the user-settings `allowRead` present,
  `SANDBOX_ENABLED` is set to `True`, a propagation pull carries `"enabled": true` into
  vinylCatalogue, and `run-verify.sh` on a known-green vinylCatalogue feature with
  Playwright is green under those synced settings;
  every path it needed is named in `hooks/README.md` → "The sandbox block" as a
  user-settings prerequisite, and any host a `SANDBOX_ALLOWED_DOMAINS` entry, each with
  the run that needed it. Raised by `runner-sandbox` (its review found the read limit);
  narrowed by `sandbox-consumer-reads`.

- **The runner's gate executes agent-authored code outside the sandbox.**
  `run_level_gate` and the batch re-gate run `plans/gate.sh` / `self/gate.sh` from the
  runner's own shell, not from `claude -p`, so pytest conftests, `package.json` scripts,
  Playwright configs and every test a build pass wrote run with no sandbox around them;
  the sandbox block bounds the executor's Bash only. Locking `gate.sh` itself (an Edit ask
  rule plus a write deny) would not close it, because the code the gate runs is the
  agent's. Assertion: a test file that writes `.git/hooks/pre-commit` fails with
  `Operation not permitted` when the runner's gate executes it, and the gate is otherwise
  green. Raised by the router session on 2026-09-30 while deciding whether Playwright
  belongs in the sandboxed verify pass.

- **The sandbox block is unvalidated on Linux/WSL.** `hooks/wire-settings.py`'s block is
  platform-neutral settings, but it was run only under macOS Seatbelt. On Linux the
  sandbox needs bubblewrap and socat, and with `failIfUnavailable: true` a machine
  without them cannot run Claude Code in a consuming repo at all; WSL1 is unsupported.
  Assertion: on a Linux checkout with bubblewrap, `self/gate.sh` and one review pass are
  green under the generated settings, and `hooks/README.md` → "The sandbox block" names
  the Linux prerequisites. Raised by `runner-sandbox` (deliberately excluded there).

- **A sandboxed Bash subprocess can still rewrite the permission hook itself.** The
  sandbox block writes no `denyWrite` and relies on Claude Code's built-in write denies
  (`.git/hooks`, `.git/config`, `.claude/settings*`, …), none of which names
  `agentTooling/hooks/` — it is inside the working directory, which the sandbox leaves
  writable. So `allow-repo-commands.sh` and `policy.py`, which the
  `Edit(**/agentTooling/hooks/**)` ask rule keeps from an unattended Edit, stay open to a
  `python3 <script>` a verify or review pass auto-approves; a prompt-injected executor
  could widen the policy every later session runs under. `hooks/README.md` → "Cross-layer
  dependencies" states the gap. A `filesystem.denyWrite` on that path in consumer mode is
  the obvious fix, but `update.sh`'s `git subtree pull` writes there through Bash too, and
  under `--self` the build legitimately edits `hooks/`, so it needs a ruling on which
  sessions may write it. Assertion: in a consuming repo, a sandboxed Bash subprocess that
  opens `agentTooling/hooks/allow-repo-commands.sh` for writing fails with `Operation not
  permitted`, and `update.sh` still pulls. Raised by `runner-sandbox`'s review.

- **Consuming repos' records short on `claude-sonnet-5-5` / `claude-mythos-preview` are
  not repaired.** live-model-rates refreshed the history and recaptured this corpus's one
  short record (`sandbox-consumer-reads`); records in a consuming repo's `plans/features/`
  captured before that refresh reached it still say `total_is_partial: true` with a "no
  rate for model" warning for either model, and only that repo can recapture them, after
  its next `subtree pull` and while their transcripts survive (about four weeks).
  Deliberately excluded from live-model-rates ("Consuming repos' own corpora"). Known
  case: humanNetworkMap `access-views-write` ($29.03 partial, four sonnet-5-5 helpers).
  Assertion: in each consuming repo, no `planning.json` carries a "no rate for model
  'claude-sonnet-5-5'" warning. Raised by `live-model-rates`.

- **Cross-repo pin over a parent claim.** A delegate yields to the feature that pins it
  when the parent-selecting capture can see the pin — a manifest in its own corpus copies,
  or a `"pinned"` ledger claim. Within a repo that always holds. Across repos it holds only
  if the pinning feature captured FIRST: when the parent-selecting feature (repo A)
  captured before the pin (repo B) existed, B's capture is refused by `check_claims`, writes
  no ledger claim, and A's advised recapture cannot see B's pin, so it claims the delegate
  again. The only way out today is a hand-written `exclude_subagents` entry in A, which no
  command writes. The refusal says this rather than hiding it. Closing it: a pin-intent
  record the refused capture may write to the ledger without touching A's claim (a separate
  section, read by `other_feature_pins`). Assertion: repo B pins a delegate repo A already
  claimed by parent; B's capture is refused; A's recapture then yields it; B's capture
  succeeds. Raised by `unpin-and-yield`.

- **The three humanNetworkMap manifests still carry the wave router's pin and hand-written
  `exclude_subagents`.** `access-page`, `article-render-sandbox` and
  `article-render-javascript` pin router `756102ea-…` (about $4.33) and exclude each other's
  delegates. Once this agentTooling is pulled there (`pull-agenttooling-pr<N>`), on each
  feature's own branch: `manifest.py <slug> unpin-session 756102ea-…`, `unexclude-subagent`
  per id, then `feature-capture.sh <slug>` in its worktree. Not done from here: that work
  is in that repo, and another session is active on those branches. Assertion: none of the
  three manifests pins `756102ea-…` or carries an `exclude_subagents` entry, and each
  `planning.json`'s `yielded_agent_ids` names the delegates the others pin. Raised by
  `unpin-and-yield`.

- **The template gate has no `record_fresh`.** `self/gate.sh` runs its settings check —
  made fresh while its input was an ignored file the resume's tree sha left out (it is
  tracked since `self-cloud-bootstrap`, and the check stays fresh) — on every gate and
  never records it; `templates/plans/gate.sh` has no such mode, so a consuming repo that
  adds a check reading an ignored or generated file (a `.env`, a local config) gets a
  recorded pass that survives that file changing under `GATE_RESUME=1`. Not built: no
  seeded check reads one today, and the function is a template version bump every
  consuming repo hand-merges. Assertion: a check `record_fresh`ed in the template gate,
  run twice under `GATE_RESUME=1` on the same tree with its ignored input broken between
  the runs, fails the second run and writes no `plans/gate-state/` record. Raised by
  `session-start-precision`.
