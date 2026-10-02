# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **`feature-start.sh --self` regenerating the primary's settings "only when missing" is
  untested.** S1v covers the missing file; nothing asserts that a present but drifted
  primary `.claude/settings.json` is left byte for byte as it was (the start must never
  rewrite a human's experiment — the gate reports drift instead), or that a failing
  generator costs a `warn` line and never the start. Assertion: a second `--self` start
  over a primary whose file was hand-edited leaves those bytes alone and exits 0. Rider:
  `hooks/policy.py`'s docstring still calls that file "committed" — it is generated and
  untracked (the review could not edit it: `hooks/` is behind the `Edit` ask rule).
  Raised by `self-settings-untracked`.

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
