# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **The silent own-branch push rests on the `.git` Edit-deny rules, and nothing checks
  that a consuming repo kept them.** `own_push_allowed` trusts the root checkout's `.git`
  because `Edit(**/.git)` and `Edit(**/.git/**)` (`hooks/wire-settings.py`'s
  `EDIT_DENY_RULES`) stop an agent from writing a `.git` file that points at a planted
  gitdir. `wire-settings.py --check` runs only in agentTooling's own gate, so a consuming
  repo that drops those rules from `.claude/settings.json` silently reopens the hole
  `own-push-real-gitdir` closed. Proposal: `own_push_allowed` reads the project's
  `.claude/settings.json` and prompts unless both rules are present; failing that, a
  consumer-side check in `update.sh`. Assertion: with either rule removed from a fixture's
  settings, a plain `git push origin <started-branch>` prompts. Raised by
  `own-push-real-gitdir`'s round-2 audit.

- **A nested settings file with a discovered name is accepted by `--config`.** `ruff check
  --config sub/ruff.toml src`, with `sub/ruff.toml` holding `fix = true`, is approved: item 5
  of `hook-silent-allow-sweep` checks only the basename, and ruff applies a nested
  `ruff.toml` by itself only to files under its own directory, so `--config` extends it to
  files it never governed. Pre-existing (head and base both allow it); needs a planted file.
  Assertion: a `--config`/`--config-file` value is approved only at the project root (or the
  cwd inside the root); a nested one prompts. Raised by `hook-silent-allow-sweep`'s round-1
  audit (N1), and again by humanNetworkMap's pull audit 04 on #172: `--config
  plans/ruff.toml` with a planted `fix = true` is accepted, because `RUNNER_CONFIG_NAMES`
  is checked against the basename only (non-blocking, pre-existing; filed by
  `own-push-transport-keys` at the orchestrator's request).

- **The gate and check-plans spellings are shared by both layouts.** A planted `self/gate.sh`
  or root `./check-plans.sh` in a consuming repo, and a planted `plans/gate.sh` in
  agentTooling's own checkout, are approved. Pre-existing (the base approved any path).
  Assertion: the spellings are pinned by the hook's layout, as `hook_analysis_pins` pins
  `report.py` — `<root>/hooks/`: `self/gate.sh`, `check-plans.sh`; `<root>/agentTooling/
  hooks/`: `plans/gate.sh`, `agentTooling/check-plans.sh` — and every other spelling prompts.
  Raised by `hook-silent-allow-sweep`'s round-1 audit (N2).

- **The role rule reads "no record" without proving it ran.** A `shared_rules.py` that raises
  `SystemExit(0)` at import, or an `orchestrator_role.py` replaced by `sys.exit(0)`, exits 0
  with no output, which `orchestrator_record_for_session` reads as no record. Pre-existing;
  needs an edit to the tooling itself. Assertion: the module prints a positive sentinel on a
  clean no-match (for example `none`), and the shell refuses on anything that is neither the
  sentinel nor a record path. Raised by `hook-silent-allow-sweep`'s round-1 audit (N3).

- **A git trace variable in the hook's environment does not stop the own-push approval.**
  With `GIT_TRACE`, `GIT_TRACE_PACKET` or `GIT_TRACE2_EVENT` already set in the session's
  environment, the own-branch push is approved and git writes to the file it names.
  Pre-existing. Assertion: any `GIT_TRACE*` set to a path prompts, beside
  `OWN_PUSH_HELPER_ENVS`. Raised by `hook-silent-allow-sweep`'s round-2 audit.

- **The git deny does not read a pattern location.** `git -C se?f switch main`, `git -C se?f
  push origin other` and `git -C @(self) reset --hard` prompt where the literal path is
  denied: the deny side, like the read approval before `hook-silent-allow-sweep`, judges the
  location word as written. Prompt-only, no silent allow. Assertion: a ref-moving git command
  behind a pattern location is denied with the same reason as behind the literal path.
  Raised by `hook-silent-allow-sweep`'s round-2 audit.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §3 (closed by its third build feature).

- **Two narrowings of `hook-silent-allow-sweep` may be wider than needed.** A quoted
  location (`git -C 'plans/e?il' status`) prompts though bash does not expand it, and in a
  vendored copy `./agentTooling/self/gate.sh` prompts where the base approved it. Neither is
  a security problem. Assertion, if the owner wants them back: a single-quoted location
  value is read literally, and the vendored copy's own `self/gate.sh` is a known spelling.
  Raised by `hook-silent-allow-sweep`'s round-2 audit.

- **A writable git config defeats the hook's approvals generally.** The hook reads the
  effective config and trusts it: a `.git/config` an attacker can write, or a global or
  included config outside the root, can add a key the hook does not list (a `!` alias, a
  `core.pager`, `diff.external`, `http.proxy`, ...) and the read-only or own-push approval
  then runs it silently. `own-push-credential-keys` closed one slice (credential programs on
  the own-branch push) by listing keys, which cannot be complete. The real `.git/config` is
  Edit-denied, so the threat needs a prior approved write or a file outside the root.
  Assertion: the approvals are made against a config the hook controls (for example
  `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL=/dev/null` and an allowlist of repo keys) rather
  than a denylist of keys. Raised by humanNetworkMap's `pull-agenttooling-pr141` round 4,
  F2-F4.

- **`analysis/report.py` does no containment check on a record's `report` path.** A
  manifest's `report` field is read as a path and opened as given, so a record naming a file
  outside the repo makes the report read it. Assertion: `report.py` refuses (or ignores,
  with a note) a `report` path that resolves outside the checkout, and a test feeds it
  `../x`. Older than #139, not urgent. Raised by the independent audit of
  `orchestration-record-fixes`, carried by `hook-audit-gaps`.

- **The git deny reads git only at command position.** `X=1 git push --force origin x`,
  `env git …`, `command git …`, `time git …`, `sudo git …`, `xargs git …`, `! git …` and
  `{ git …; }` are prompts: `git_subcommand_args` wants `git` as the command's first word.
  Assertion: each is denied in both profiles (`self/tests/hook-cloud-profile.sh` T), with the
  env-prefix and keyword handling the build-script judge already has
  (`ENV_ASSIGNMENT_RE`, `BUILD_SCRIPT_LEAD_KEYWORDS`). Never an allow; older than this
  feature. Found by the phase-3 self-audit of `hook-audit-gaps`, not fixed there (a class of
  its own).
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §3 (closed by its third build feature).

- **The git deny matches flags as written, not as git reads them.** A long option
  abbreviated as git accepts it (`git push --force-w origin x` is `--force-with-lease`;
  `git reset --har`), and a short-flag cluster on a subcommand other than `push`
  (`git checkout -qb x`, and `git switch -qc x` locally), are prompts. Assertion: each is
  denied; `bundles_push_force` is the model for the clusters, `orchestrator_option_hits` for
  the prefixes. A `+<refspec>` push naming no protected branch (`git push origin +x`) is a
  prompt by decision — `hook-cloud-profile.sh` pins `git push origin +<current>` as one — and
  wants an owner ruling before it changes. Found by the phase-3 self-audit of
  `hook-audit-gaps`.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §3 (two spellings built, the rest best-effort by design).

- **A line the hook cannot tokenize: three leftovers.** `hook-audit-gaps` closed the git
  half: a line that names git, that no reading judges and that bash refuses (`bash_refuses`,
  `bash -n` over the line) is a git command that cannot be read, denied without decay
  (`UNLEXED_GIT_DENY` and `BASH_REFUSED_GIT_DENY` in `self/tests/allow-repo-commands.sh`). A
  line bash PARSES and no reader judges (`git push -f origin y⏎echo $'\''`, still a prompt,
  `BASH_PARSED_PROMPT`), this entry's old (a), is the next entry's class. What is left, each a prompt and never an
  allow: (b) a line that names NO git, does not tokenize and holds a `<<` or a `#` in its
  raw text (`cd /tmp && ls⏎echo '#`) is a prompt, where the same line without them is the
  does-not-tokenize deny — a rewrite lost; assertion: `does_not_tokenize` excuses a line
  only for a `<<` or a `#` OUTSIDE its quotes. (c) A line that names git of which one
  reading tokenizes, though not bash's — a comment in doubt kept as text, its apostrophe
  pairing with a later odd quote, beside a body no reading places (`(ls) # it's⏎git push -f
  origin y⏎cat <<EOF⏎echo '`) — is a prompt; assertion: the reading that keeps a doubtful
  comment as text does not count toward "some reading tokenizes". (d) The bash asked is the
  system's (`BASH_SYNTAX_ENV`, `/usr/bin:/bin`) with no option set, not the shell the
  session runs: a line that shell refuses and the system bash parses keeps the verdict it
  had, and one that parses only there (`git add !(x) $'it\'s'` under extglob) is denied;
  assertion: the check is made by the shell, and under the options, the command will run
  with — which the hook is not told. Found by `hook-audit-gaps`'s phase-3 self-audit, its
  round-5 and round-6 audits and round 7's build.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §§2–3 ((b), (c) closed by its build; (d) by design).

- **The deny side does not follow a substitution's scope.** `cat <<EOF⏎$(git push --force
  origin x)⏎EOF` (an unquoted delimiter: bash runs the body's `$(…)`), a command INSIDE a
  quoted substitution (`echo "$(git push --force origin x)"`, and the same on a heredoc's
  run-on line there: `git commit -m "$(cat <<'EOF'⏎x⏎EOF git push --force origin x)"`, which
  bash 5.2 runs), a body line holding a `"` inside quoted backticks (``echo "`cat
  <<EOF⏎a " b⏎EOF⏎`" ; git push --force origin x``), and `echo $'it\'s' ; git push --force
  origin x` (an ANSI-C quote escaping a quote: `never_judged`; `$$$'a\''` the same) are
  prompts, as they were on `main`. Assertion: each is denied, by a reader that follows `$(…)`
  scope and decodes `$'…'`; rounds 4–8 of `orchestration-record-fixes` tried a scoped
  reading and took it out, so this wants a design, not a patch. Found by the phase-3
  self-audit of `hook-audit-gaps`; round 2 closed the `"$(echo " #")"` spelling (a comment
  past an opener is read both ways) and `$$'…'`, and its differential check counted the rest.
  Round 3 closed the whole-argument spelling — a `"$(cat <<…` head that is not stood in is
  also read opened, so the run-on line above and a command after the body inside the quotes
  are denied — and left every other `"$(…)"` (`echo "$(true; cat <<EOF⏎x⏎EOF⏎git push
  --force origin x⏎)"`, `echo "\\⏎$(cat <<EOF …)"`) where it was. Round 4 widened that head
  to the spellings bash reads as the same one (`"$( cat <<`, tabs, a line break after the
  `$(`, `cat<<`, a continuation inside: `HEREDOC_OPENED_HEAD_RE`); text before the `$(`
  (`echo "x$(cat <<EOF⏎x⏎EOF⏎git push -f origin y⏎EOF⏎)"`) and a command word other than a
  bare `cat` are still the one quoted word, and still this entry. Round 5 refused that head
  outright when its delimiter is no bare or fully quoted identifier (`unread_head`); the
  same odd delimiter behind text before the `$(`, a command word other than a bare `cat`, or
  a command on the head's own line (`"$(cat <<'EOF' -A`, `"$(cat <<EOF | tr a b`) is still
  the one quoted word.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §3 (a line naming git: closed by its build; any other: best-effort by design).

- **On the unreadable-ledger path, a build script's name built at run time is not seen.**
  awk's string concatenation (`awk 'BEGIN{system("./run-pl" "ans.sh")}'`), a quote glued
  inside a sed `e` script (`sed -n '1e ./run-pl""ans.sh' README.md`), `printf
  './run-pl%sns.sh' a | sh`, `echo ./run-plbns.sh | tr b a | sh` and a filter that selects
  the name (`ls | grep plans | xargs sh`) each run a build script and are prompts (or the
  opaque rewrite, which decays to an ask): no line reader can see a name that is not on the
  line. Assertion: with the ledger unreadable, a pipe INTO a shell or `xargs <shell>` and an
  awk `system(` or sed `e` are refused whatever they name. Each was a prompt on `main` too.
  Listed by round 1's audit of `hook-audit-gaps` (escalations/01-audit-opus.md, "not
  regressions") and counted by round 2's differential check.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §3 (closed as best-effort by design).

- **`hooks/README.md` promises more than "never silently approved".** Each
  `hook-audit-gaps` round wrote a stronger guarantee there ("both readings judged",
  "denied wherever bash runs it"), and each became the next audit's target. Proposal: the
  README guarantees only that nothing outside the approved shapes is approved silently,
  and documents the stronger denies as best-effort. Assertion: every guarantee the README
  states has a gate test row. Raised by `hook-audit-gaps`.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §5 (closed by its third build feature).

- **The hook judges by re-implementing bash's reader, which cannot converge.** It uses
  `shlex` plus a custom walk, and an auditor can always find another spelling where it and
  bash disagree. Proposal: make silent approval an allowlist (a single line, no
  `\`-continuation, no `$'…'`, the heredoc only in its canonical commit form) that
  prompts or denies everything else, and use bash itself (`bash -n`, which
  `hook-audit-gaps` round 7 introduces) as the parse oracle. Assertion: no silent-approval
  path depends on the hook's tokenizer agreeing with bash outside the allowlisted shapes.
  Raised by `hook-audit-gaps`.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §§1–2 (closed by its second build feature).

- **The bash-vs-hook differential harness is not committed.** `hook-audit-gaps` built one
  in a scratchpad; implementers should find divergences before audits do. Proposal: commit
  it as a `self/tests/` gate test. Assertion: the gate fails on any generated command that
  the hook approves silently while bash would run a command the hook denies. Raised by
  `hook-audit-gaps`.
  Superseded by `DESIGN-2026-11-19-hook-allowlist.md` §4 (closed by its first build feature).

- **The shell lifecycle scripts each carry their own `SLUG_PATTERN`.** `feature-start.sh`,
  `orchestration-capture.sh` and the other lifecycle scripts spell
  `^[a-z0-9]+(-[a-z0-9]+)*$` themselves, a shell-to-shell rule the hook does not share
  (`hooks/shared_rules.py`'s `SLUG_PATTERN` is the Python side's one definition, which
  `orchestration-start.sh` reads). Reading it from the module in each script would add a
  python process to every script start, so `shared-hook-rules` left it. Assertion: no
  lifecycle script restates the pattern, or one shell file defines it and the rest source
  it (`self/tests/shared-rules.sh`'s `SHELL_PAIRS_LEFT` loses its `SLUG_PATTERN` rows).
  Raised by `shared-hook-rules`.

- **Pairs the hook forms with `analysis/` or a shell file that still hold a literal each.**
  The hook may not depend on `shared_rules.py` for anything but the role rule (a missing
  module must leave every other answer unchanged), so these stayed: the FEATURE manifest's
  name `README.md` (`allow-repo-commands.sh`, `routing.MANIFEST_NAME`, the shells'), the
  feature corpus roots `self/features` / `plans/features` (`allow-repo-commands.sh`,
  `orchestration-start.sh`, `plan-runner-roots.sh`, `update.sh`, `roots.features_root`),
  the build-script names, and the profile words `env-profile.sh` restates from
  `env_profile.py`. Decide, per pair, a guarded read with a fail-safe answer or a rule that
  moves to the shell side; `NOTES.md` of `shared-hook-rules` lists them. Assertion: the
  exception tables in `self/tests/shared-rules.sh` hold only pairs with different meanings.
  Raised by `shared-hook-rules`.

- **A plans-method cell whose review escalates opens no PR, so the experiment harness
  records it `no-pr`.** The plans workflow stops after an escalated review (no close, no
  PR — `LIFECYCLE.md` step 5), which is right for a feature but leaves an experiment arm
  with no PR to measure at PR-open; the harness then opens one itself (`settle_pr`) or
  fails the cell. Decide whether an arm should run a rework round, or the harness should
  treat "escalated, pushed" as its own outcome. Assertion: a plans cell whose review
  escalates yields a row whose outcome names the escalation, not `no-pr`. Seen in
  vinylCatalogue's toolingAblation; raised by `ablation-harness-fixes`.

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

- **The SessionStart wiring is unexercised in a CONSUMING repo's cloud session.**
  `sync-plans.sh` wires `${CLAUDE_PROJECT_DIR}/agentTooling/session-start.sh` as a
  SessionStart hook with no matcher, which runs the repo's `plans/cloud-setup.sh` in the
  cloud; agentTooling's own `--self` entry has run in a real cloud session (a resume
  printed the orientation), but no consuming repo has yet run its `cloud-setup.sh` this way
  in a container. Assertion, by hand at the first consuming repo's cloud setup feature: a
  new session's context shows the orientation and the script's output line, a resumed
  session runs it again harmlessly, and its gate is green with no `--no-gate`. Raised by
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
  `Edit(**/agentTooling/**)` ask rule keeps from an unattended Edit, stay open to a
  `python3 <script>` a verify or review pass auto-approves; a prompt-injected executor
  could widen the policy every later session runs under. `hooks/README.md` → "Cross-layer
  dependencies" states the gap. A `filesystem.denyWrite` on that path in consumer mode is
  the obvious fix, but `update.sh`'s `git subtree pull` writes there through Bash too, and
  under `--self` the build legitimately edits `hooks/`, so it needs a ruling on which
  sessions may write it. Assertion: in a consuming repo, a sandboxed Bash subprocess that
  opens `agentTooling/hooks/allow-repo-commands.sh` for writing fails with `Operation not
  permitted`, and `update.sh` still pulls. Raised by `runner-sandbox`'s review.

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

- **A recapture re-prices a record from the table instead of from the rates it already
  recorded.** `planning.json` stores `rates_applied` (five rates, `from`, `source`) for
  every model of every session it prices, but `capture_planning.py --recapture` ignores
  them and prices again from `analysis/rates_history.json` (or the `litellm-live`
  fallback). So a frozen record's figure is reproducible only while the table and LiteLLM
  stay as they were: a refresh that appends a new entry, or a manual correction, can move
  the cost of a feature that already merged when somebody repairs it. Proposed: the
  record's own `rates_applied` win for a session it has already priced, and the table
  (then the live lookup) prices only sessions the record has not seen; re-pricing a record
  on purpose — to carry a correction — is an explicit flag. Keep the table: it still prices
  each session at its own date across a price change mid-feature, keeps the two halves of a
  session shared between features summing to the session, carries `manual` corrections to
  every record in one place, and prices with no network. Assertion: a captured feature,
  then a new dated entry for its model appended to the history, then `--recapture` — the
  figure is unchanged; the same with the explicit re-price flag moves it. Raised by the
  human during `review-base-and-cloud-hook` (round 5 recorded it).

- **A cloud capture names a repo in lowercase when nothing else spells it.** A Claude Code
  cloud container clones from a case-folded origin (`https://github.com/ssdesai/musicmap`),
  so `repo_display_name` — origin-derived, as it should be — says `musicmap`, and a
  feature only ever captured in the cloud is `musicmap/<slug>` in every mention. The
  collapse (`roots.collapse_feature_mentions`) merges it with a laptop's `musicMap/<slug>`
  wherever both appear, but cannot invent the capitals alone. A real fix needs the true
  name from somewhere local — e.g. a declared display name in the repo's own
  `plans/PROJECT_FACTS.md`, or the GitHub API's `full_name`, which the stdlib-only,
  no-network analysis must not call. Assertion: a capture in a checkout whose origin is
  `…/musicmap` in a repo that declares `musicMap` writes `musicMap/<slug>`. Raised by
  `cloud-pull-fixes`.

- **Five templates' headers still say to bump "when the body changes".** Since
  `cloud-pull-fixes`, `TEMPLATE_VERSIONS` hashes comments too and any edit needs a bump;
  only `cloud-setup.sh`'s header (bumped to 2 anyway) says so. Rewording the other five
  (`gate.sh`, `pr.sh`, `worktree-setup.sh`, `open-session.sh`, `environment.sh`) would
  itself be a bump and a DRIFT line in every consumer for no behaviour, so each is reworded
  at its next real bump. Assertion: every `templates/plans/*.sh` header says comments
  count. Raised by `cloud-pull-fixes`.

- **A consuming repo's `plans/worktree-setup.sh` printed ".venv created" on a resumed
  start although `uv` refused to recreate it.** Repo-owned, not agentTooling's: the seeded
  skeleton prints nothing of the kind. Noted so the next propagation round tells that repo.
  Raised during `cloud-pull-fixes`.

- **Program cells carry no reading metrics.** A program feature's capture does not run
  `reading_metrics.py`, so neither the program row nor its `features[]` has the reading
  fields. Assertion: a program row's `features[]` entries carry `read_files_before_edit`,
  `read_bytes_before_edit` and `readme_bytes_read`, measured over each implementer's window
  in its feature worktree. Raised by `harness-arm-base`.

- **Base arms do not combine with programs.** A program pins its own `base`, so
  `base_arms` with `programs` is refused. Assertion: an experiment with `base_arms` and
  `programs` cuts each program cell's program branch and non-dependent feature branches at
  the arm's commit instead of `program.json`'s `base`. Raised by `harness-arm-base`.

- **Program cells cannot be reset, and `--from` does not check their preconditions.**
  `run.sh --reset` refuses a program cell, and the `--from` check for missing state, setup start
  or worktree covers fixture cells only. Assertion: `--reset` on a killed program cell moves its
  program branch, feature branches, worktrees and state aside, and `--from loop` on one with
  those missing is refused naming `--reset`. Raised by `harness-long-runs`.

- **`run-plans.sh` has no time budget between plans.** A plan run killed at the 2-hour background
  limit resumes on re-run, and `run-batch.sh` has no between-plans loop (plan iteration is in
  `plan-runner-lib.sh`), so a budget would be a new mechanism there, not the harness's. Left out
  of `harness-long-runs` (`harness/SPEC.md` §17). Assertion: a run given a budget stops before a
  plan that would not fit, exits `HARNESS_BUDGET_STOP_RC`-style and prints the command that
  resumes it. Raised by `harness-long-runs`.

- **The orchestrator role has three gaps.** Each is one assertion. (A fourth, that it could not `git mv`
  its own stranded record, was closed by `orchestration-start-branch-v2`.)
  2. *The role hook reads only this checkout.* `hooks/orchestrator_role.py`'s
     `record_roots` looks under the hook's own `<tooling>/self/orchestrations/` and, from a
     vendored copy, its consuming repo's `plans/orchestrations/`, so an orchestrator whose
     record lives in another repository is not denied by the hook here; the scripts in the
     copy that holds the record still refuse. Assertion: a session whose record sits in
     checkout A, running `feature-start.sh` of checkout B, is refused.
  3. *The reverse guard needs git.* `orchestration-start.sh`'s `held_feature` finds
     manifests with `git ls-files`, and the whole guard is skipped when `git rev-parse
     --show-toplevel` finds no repository, with nothing printed. It reads the consuming
     repo's `plans/features/` too, but `self/tests/orchestrator-role.sh` V covers only
     `self/features/`. Assertion: a vendored copy whose consuming repo tracks a manifest
     naming the current branch refuses the start (`plans/features/<slug>/README.md`
     named), and a copy with no git above it says it could not check.
  4. *Edit isn't stopped by the role.* The hook judges only `Bash` and `Agent` calls
     (`MATCHED_TOOL`, `AGENT_TOOL`), so an orchestrator that builds by hand through the
     Edit or Write tool is not stopped at all; only the lifecycle scripts refuse.
     Assertion: an orchestrator session's Edit under a feature's checkout is denied or
     asked.

  Raised by `orchestrator-role-guard` (2–4); a delegate briefed without the `feature: ` first line was closed by `delegate-cost-claims`.

- **A delegate briefed with another repo's name in front of a `--self` slug is never
  auto-claimed.** A vendored coordinator that writes `feature: musicMap/<self-slug>` names a
  different `(repo, slug)` than the self corpus's `agentTooling/<self-slug>`, so the capture
  leaves it and the close's claim check does not list it (it names another feature).
  Assertion: a capture of `--self <slug>` pins a delegate briefed `<consumer>/<slug>` only
  when no consumer manifest holds that slug. Raised by `delegate-cost-claims`.

## Parked: README/spec structure

**Parked by the owner on 2026-11-07: do not start any of the next eight entries without the
owner's word.** They are the rest of the `readme-structure` orchestration
(`self/orchestrations/readme-structure/README.md`), whose vinylCatalogue A/B
(`discogsPrefillStructure`, #231) found the restructured READMEs and split spec cut bytes read
before the first edit by 30%, README bytes read by 77% and cost to green by 5.5% (n=2). Consumer
state below is the orchestration record's or the orchestrator's note as of 2026-11-07, not
checked from this tree.

- **The README/spec structure is rolled out only partly beyond vinylCatalogue.** The
  restructure merged in vinylCatalogue (#218); parts shipped in humanNetworkMap (#273, #275,
  #277) and musicMap (#73, #74). What is left (record items 1, 2, 8): README entries as an index
  line plus contracts, test READMEs one line per test file, and monolithic specs split one file
  per top-level section, wherever humanNetworkMap, musicMap and mediaCore do not yet have them.
  Assertion: in each of those repos a README entry is an index line plus its contracts, a test
  README has one line per test file, and no spec is a single file holding several top-level
  sections. Raised by `readme-structure`.

- **humanNetworkMap, musicMap and mediaCore do not run the README-index check.**
  `check-readme-index.py` shipped here (#119); consumers opt in per `agentTooling/README.md` →
  "Adopting the README-index check", once their agentTooling pull has landed. As of 2026-11-07
  none has. Assertion: each repo's gate runs it blocking, with a repo-owned ignore list for
  record and fixture directories only. Raised by `readme-structure`.

- **vinylCatalogue's root `CLAUDE.md` carries the CLI reference and the spec-amendment
  history.** It is long and loads into every session. Move both to files read on demand.
  Assertion: the root `CLAUDE.md` holds neither section and names where each now lives.
  Raised by `readme-structure`.

- **Repo facts are not scoped by path.** Facts that matter only under one folder load in every
  session. Scope them with `.claude/rules/` path-scoped rules, musicMap first (it already moved
  folder-scoped facts under #73). Assertion: a musicMap session that touches no file under a
  rule's path does not load that rule's text. Raised by `readme-structure`.

- **No mechanical check that a README still matches the code.** #119 checks that an entry
  exists, not that it is true. Wanted in the consumers' gates: a field list that no longer
  matches its schema, a named file that no longer exists. Assertion: a README that names a
  deleted file, or lists a field its schema lacks, turns the gate red. Raised by
  `readme-structure`.

- **humanNetworkMap's root README still carries the Data Model, Delegated plan execution and
  Notes for Claude Code sections.** Move them out of the root README (the split of that README
  started under #273). Assertion: the root README carries none of the three and points to
  where each lives. Raised by `readme-structure`.

- **Optional: humanNetworkMap's `scripts/check_test_spec_split.py` is not wired into its
  gate.** It shipped with the test-spec split (#277); as of 2026-11-07 the orchestrator's note
  is that the gate does not run it. Assertion: a test file the split spec does not name turns
  that repo's gate red. Raised by `readme-structure`.

- **The README traversal-rule A/B has not been run; decide whether it is still worth running.**
  It compares the old `CONVENTIONS.md` traversal ritual with the new one. The
  `discogsPrefillStructure` A/B may already have answered what it was for. Assertion: the
  entry is either removed with a line saying what answered it, or planned as a feature.
  Raised by `readme-structure`.

## Loose harness items

- **`self/tests/feature-sync.sh` never runs the script from outside the repo root.** Every
  case `cd`s to the clone's root first, which is how a cwd-relative `MERGE_HEAD` check
  passed every assertion until the review of `branch-sync-and-fanout-docs` found it (fixed
  there). Assertion: a conflict case run from a subdirectory exits 3 and names the file.
  Raised by `branch-sync-and-fanout-docs`.

- **No `feature-sync.sh` case is on a named branch other than the manifest's.** The
  off-branch refusal is reached only through a detached HEAD (R4) and `main` (R3, where the
  manifest is absent). Assertion: on another named branch carrying the manifest, the script
  exits 1 naming both branches, nothing moved. Raised by `branch-sync-and-fanout-docs`.

- **Arm-spec rows carry a `spec_commit` the cell did not read.** On a row whose `spec_source`
  is `"arm"`, `spec_commit` is still the fixture's `spec.commit`, while that cell's spec is at
  `base` (`harness/README.md`, spec-per-arm section). Assertion: such a row's `spec_commit` is
  the commit its spec was read at, or is absent, so no reader takes it for the cell's. Raised
  by `orchestrator notes 2026-11-07`.

- **`plans/experiments/README.md` lacks index lines for newer experiment folders.** As of
  2026-11-07 the orchestrator's note is that a consumer's experiments index is behind its
  folders; `harness/new-experiment.sh` writes the experiment's own `README.md` but no line in
  that index.
  Assertion: the README-index check (#119) run over `plans/experiments/` finds every
  experiment folder named. Raised by `orchestrator notes 2026-11-07`.

- **`publish.sh` with several experiments on one branch opens a PR whose body carries only the
  first experiment's scorecard.** It takes one experiment directory, uses its `SCORECARD.md`
  as the PR body, and does nothing when a PR is already open for the branch, so a second
  publish adds its commit and leaves the body alone. Assertion: after two experiments publish
  from one branch, the PR body carries both scorecards. Raised by
  `orchestrator notes 2026-11-07`.

- **`feature-start.sh` for an experiment run writes a full feature README and a review
  stub.** It has one manifest-and-review-stub step for every start, with no experiment case.
  An experiment run wants a manifest-only README that points at the experiment, and no review
  stub. Assertion: a start for an experiment run writes a README holding the manifest fence
  and a pointer, and no `review/` plan. Raised by `orchestrator notes 2026-11-07`.

- **Open question for the owner: should `run-plans.sh` push after each plan in a cloud
  container?** Neither `run-plans.sh` nor `run-verify.sh` commits (the executors may, under
  the plans method), and the cloud checkpoints stop at the start commit and the review
  round's, so a container reclaimed mid-build loses the executors' commits since the start.
  The default taken is no: the round's push carries them, and a plan run is not a
  checkpoint the lifecycle names. Assertion if decided yes: under the cloud profile a
  `run-plans.sh` pass that filed a plan to `complete/` leaves `origin/<branch>` at the local
  head, via `checkpoint_push`, and the local profile pushes nothing. Raised by
  `cloud-checkpoint-push`.

- **A harness experiment driver has no sanctioned path onto its own branch.** It ran
  `feature-start.sh --method hand` only to get a branch. `orchestration-start.sh --branch`
  now cuts an orchestrator's (`orchestration-start-branch-v2`); the experiment driver gets
  the same. Assertion: the driver on a detached HEAD is refused without a branch flag, and
  given one cuts that branch off `origin/main` without starting a feature. Raised by the
  2026-11-17 wave.

- **`orchestration-start.sh --branch` has five refusals no test exercises.** Five refusals have
  no assertion in `self/tests/orchestrator-role.sh` B: a local branch of that name,
  `--branch` while on another non-`main` branch, a record already on
  `origin/main`, commits on HEAD not on `origin/main`, and uncommitted changes. Each must
  exit 1 and leave no record, no ledger line and no new branch. (A name that is not
  `claude/<slug>`, `main` included, is B7 since round 4.) Raised by the
  `orchestration-start-branch-v2` review.

- **An assigned cloud branch that is not `claude/<slug>` cannot be named to
  `orchestration-start.sh --branch`.** Round 4 of `orchestration-start-branch-v2` narrowed
  `--branch` to `claude/<slug>` (owner ruling). A session already launched on an assigned branch
  of another shape (a mixed-case or suffixed name) still works by dropping `--branch`, and the
  "on another branch" refusal says so; but `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md` and
  `ORCHESTRATION.md` → "Cloud sessions" tell it to pass `--branch` always, and say only that the
  assigned name "must have that shape". Fix: one sentence in each — on a non-`main` assigned
  branch of another shape, run the start without `--branch`. Raised by the
  `orchestration-start-branch-v2` round-4 review.

- **`started_features_on` (`plan-runner-roots.sh`) enumerates with `git grep -l` without
  `-z`.** It has the C-quoting gap `orchestration-start-branch-v2` closed in `held_feature`:
  git C-quotes a manifest path holding a non-ASCII byte, a tab or a quote, and
  `session-start.sh` and `update.sh` then skip that feature silently. Fix: `git grep -z -l`
  with `read -r -d ''`. Assertion: a manifest under a non-ASCII directory naming the branch is
  found. Raised by the `orchestration-start-branch-v2` review.

- **No test asserts that `push_feature_branch` still sets the upstream.** Round 3 of
  `orchestration-start-branch-v2` changed the push to the explicit refspec
  `refs/heads/<b>:refs/heads/<b>` with `-u`; git sets `branch.<b>.remote`/`.merge` for it, but
  `orchestrator-role.sh` B2d and `cloud-checkpoint-push.sh` assert only that the branch
  reached origin. Assertion (beside B2d): `git -C "$AT" rev-parse --abbrev-ref
  '@{upstream}'` is `origin/<branch>`. Raised by the `orchestration-start-branch-v2` round-3
  review.

- **The other `-u origin <branch>` pushes still take a bare branch name.** Round 3 of
  `orchestration-start-branch-v2` wrote `push_feature_branch`'s refspec out in full because a
  name beginning `+` is read as a force refspec (`git check-ref-format --branch` accepts
  `+main`). `templates/plans/pr.sh` (and `self/pr.sh`, which ships from it) pushes
  `"$current_branch"`, and `harness/lib.sh` pushes `"$branch"`, both bare. A local branch
  named `+main` is unlikely but creatable, and pr.sh ships to every consuming repo. Fix: the
  same `refs/heads/<b>:refs/heads/<b>` form (pr.sh is a template: bump its version). Raised
  by the `orchestration-start-branch-v2` round-3 review.

- **`CONVENTIONS.md` → "Shell commands" no longer names every write the hook approves
  silently.** Its "Approved silently" paragraph lists reads and tests plus one write, the
  cloud `git push` of the started feature's branch. `orchestration-start-branch-v2` added a
  second write approved outright under both profiles: an orchestrator's
  `[mkdir -p plans/orchestrations && ] git mv <tooling>/self/orchestrations/<slug>
  plans/orchestrations/<slug>` of its own stranded record (`ORCHESTRATOR_MOVE_REASON` in
  `hooks/allow-repo-commands.sh`). `ORCHESTRATION.md` and `hooks/README.md` document it; the
  shipped conventions do not. Fix: one sentence in that paragraph naming it and pointing at
  `ORCHESTRATION.md` → "Cloud sessions". Raised by the `orchestration-start-branch-v2` round-2
  review.

- **An orchestration record cannot hold an experiment, nor a feature in a repo the
  orchestrator cannot clone.** `report.py`'s `compute_orchestration_report` prices each
  `features[]` entry from its `report` path's `report.json` (`cost.total`). A harness
  experiment writes no `report.json`, so on 2026-11-17 the humanNetworkMap
  `records-gate-models` experiment's scorecard total and its driver's cost were added to the
  group total by hand. A feature in another repo is priced with `--checkout <repo>=<path>`,
  but the orchestrator's Bash allowlist holds no `git clone`, so it has no path to name and
  the entry stays `UNPRICED_NEEDS_CHECKOUT`. Fix: an entry kind for an experiment that reads
  its scorecard's total and driver cost; and a way to price a foreign feature from its
  merged `report.json` without a checkout (or a sanctioned clone). Assertion: a record
  holding an experiment and a feature of another repo reports a group total that includes
  both, with no hand arithmetic. Raised by the 2026-11-17 wave.

- **When `harness/publish.sh` and `feature-close.sh` share a branch's PR, the PR keeps
  publish's title.** `publish.sh` opens the PR titled `<experiment>: results, run <N>`
  with `SCORECARD.md` as its body; the close's `pr.sh` finds it open and refreshes only its
  body (`forge.sh pr-edit` takes a body file and nothing else), so the merged PR is titled
  as the experiment's results run and carries the review's body. Fix: `pr-edit` takes the
  title too, and the close sets it. Assertion: after a publish and then a close on one
  branch, the PR's title is the close's. Raised by the 2026-11-17 wave.

- **Experiment names must be camelCase, and nothing says so.** `harness/new-experiment.sh`
  refuses any name not matching `^[a-z][A-Za-z0-9]*$` ("experiment name must be bare
  camelCase"), while feature slugs are kebab-case (`SLUG_PATTERN`). `harness/README.md`
  documents camelCase for program names and branch stems but not for the experiment name.
  Fix: state the rule and its reason in `new-experiment.sh`'s row in `harness/README.md`,
  or accept kebab-case if nothing the name feeds needs camelCase. Assertion: either `new-experiment.sh`
  accepts a kebab-case name, or the README states the rule. Raised by the 2026-11-17 wave.

- **Arm worktrees sit outside the project root.** `harness_worktree_path` (`harness/lib.sh`)
  puts a cell's worktree at `<repo path>-<branch>`, a sibling of the checkout, so the
  command hook treats every read there as outside the root and hands it to the human.
  Fix: put arm worktrees under the root (an ignored directory such as the `.worktrees/`
  `feature-start.sh` already excludes). Assertion: a driver's `ls` and `cat` inside an arm
  worktree are approved silently. Raised by the 2026-11-17 wave.

- **Rework runs on `HARNESS_MODEL`.** Only the review stage has its own model
  (`HARNESS_REVIEW_MODEL`); `harness/run.sh`'s `do_rework` and the program stages' rework
  pass `--model "$HARNESS_MODEL"`, so a rework round cannot use a different model from the
  build. Fix: `HARNESS_REWORK_MODEL`, defaulting to `HARNESS_MODEL`. Assertion: with it set,
  the rework's `claude -p` carries that model and the build's does not. Raised by the
  2026-11-17 wave.

- **The judge is not blind to the arm.** The harness's judging stage (`review`,
  `HARNESS_REVIEW_MODEL`) is given `@@TREE@@` and `@@BRANCH@@`
  (`harness/templates/review-preamble.md`), both built from `<stem><Method><Arm><n>`, so an
  arm labelled by model, or an experiment named for one, names the build's model to the
  judge; a blind judge a driver runs over that tree sees the same paths and branches. Fix:
  the judge gets a neutral alias per cell, and arm and experiment names are redacted from
  the paths, branches and diff it is shown. Assertion: no prompt the judge receives
  contains an arm label or the experiment name. Raised by the 2026-11-17 wave.

- **A `claude -p` check run before any start is priced by no feature.** On 2026-11-17 a
  session ran a pre-start `claude -p` check ($0.29) on a detached HEAD, before its feature
  existed, so no manifest's branch or window selects it and nothing pinned it. Fix: list it
  in `capture_planning.py --list-sessions --unclaimed` for the owner to pin, or record it
  as the orchestration's overhead. Assertion: after the wave's captures,
  `--list-sessions --unclaimed` lists no session of that wave. Raised by the 2026-11-17
  wave.

- **The owner brief is optional, so an orchestrated feature can still skip the yardstick.**
  `feature-start.sh --owner-brief` and the conformance check degrade to today's behaviour with
  one notice when a feature has no `OWNER_BRIEF.md`, which is the rollout that kept every
  consuming repo working on its next pull. Fix: once one wave has used it, make it mandatory
  for orchestrated features. Assertion: `feature-start.sh --orchestration <slug>` without
  `--owner-brief` is refused before anything is written, naming the flag, and
  `templates/plans/ORCHESTRATOR_BRIEF.md`'s start line already carries it. Raised by
  brief-conformance-checks.

- **A lazily numbered owner list collapses its items onto one id.** An `OWNER_BRIEF.md`
  written `1. **Add A.** …` / `1. **Add B.** …` (ordinary Markdown auto-numbering, rendered
  1, 2) gives `conformance.py items` two items sharing id `1`, so one acceptance row and one
  conformance row for `1` satisfy both and the close goes on. Fix: number list items by
  position as a renderer does (the first item's number, then +1 each), or at least exit
  non-zero on a duplicate id so the runner and the close refuse the brief. Assertion: `items`
  on the lazy brief prints ids `1` and `2`, or refuses. Raised by
  `self/features/brief-conformance-checks/audit-report.md` (rounds 2 and 3, non-blocking).

- **A clean audit is stamped stale, and counted toward the audit round cap as escalated,
  when a later review edits an audit path, even a whitespace-only change.** Assertion: an
  audit-path change that leaves the audited content's meaning unchanged, or any review fix
  after a clean audit, either re-runs the audit within the same round or does not count as
  an escalated audit round. Raised by brief-conformance-checks round 2.

- **Three pre-existing silent approvals behind a planted link.** `cat 'a >/dev/null b'`
  (`HARMLESS_REDIRECT_RE.sub` strips the redirect before any quote is read),
  `cat dir/[^i]*` (Python `glob` reads `[^i]` as the set of `^` and `i`; bash as every file
  not starting with `i`) and ``cat "dir/\`x"`` (shlex keeps the backslash bash drops) are
  each approved while bash opens a path the hook never judged. Each is confirmed against bash,
  and each needs a symlink already in the tree to read outside the root. No separate fix: the
  second build feature of `self/DESIGN-2026-11-19-hook-allowlist.md` (§8,
  `hook-allowlist-approval`) removes all three, owner ruling on that design's question 7
  (2026-11-19). Assertion: with a link planted at the path bash opens, none of the three is
  approved. Raised by the `hook-allowlist-design` (#170) prototype, "The defect"; filed by
  `pull-round-cleanups`.

- **The gate report drops a failing test's FAIL lines.** `self/gate.sh` keeps only the last
  `OUTPUT_TAIL_LINES` (40) lines of a section's output (`gate.sh`, the section writer), and a
  self-test prints its `FAIL` lines where they occur, then a summary. On 2026-11-19
  `orchestrator-role.sh` failed 21 checks inside a cloud `feature-start.sh` and the report kept
  only its last 37 `ok` lines and `21 check(s) FAILED`, so the start's refusal named no failing
  check and the cause took a separate reproduction to find. Fix: a section that exits non-zero
  keeps every line matching the test's failure marker (`FAIL`) ahead of the tail, or its whole
  output. Assertion: a stub check printing one `FAIL` line followed by 60 `ok` lines and
  exiting 1 leaves that `FAIL` line in `self/gate-report.txt`. Raised by
  `pull-round-cleanups`.

- **A vendored record whose last fence cannot be read counts as agentTooling's own.**
  `roots.legacy_record_claim` answers `CLAIM_OWN` for a `README.md` that exists but whose last
  fence does not parse, or whose `features` is not a list of dicts with string `repo`s. So a
  no-`--self` start of that slug goes on, writing a second record under the same slug, and the
  record tools call it agentTooling's own. This is pre-existing: the base's `is_stranded_record`
  answered no too. Fix: such a record is unclassifiable, and the start refuses naming the file, as
  it already does when `roots.py` cannot run. Assertion: a vendored record with an unparseable
  last fence, or `features` a dict, makes `orchestration-start.sh <slug>` exit 1 and write
  nothing. Raised by `pull-round-cleanups`'s audits (rounds 1–3, non-blocking).

- **`legacy_record_claim` compares raw `repo` strings, lower-cased only.** `features[].repo` of
  `" consumer"` or `"consumer.git"` is not matched to the consumer, so the record reads as
  agentTooling's own and its start goes on. A mixed wave whose agentTooling entry is spelled
  `agentTooling.git`, `"agentTooling "` or an origin URL is classed stranded, not ambiguous, and
  is prescribed the `git mv` that deletes an agentTooling wave from the consumer's
  `agentTooling/`. Both are pre-existing. Fix: normalize each `repo` the way the home names are
  derived (`capture_planning.repo_display_name`: last path segment, `.git` stripped), with
  whitespace stripped and `casefold()`, before comparing. Assertion: `" consumer"` and
  `"consumer.git"` read as the consumer's, and a fence listing `consumer` and `agentTooling.git`
  is ambiguous. Raised by `pull-round-cleanups`'s audits (rounds 2–3, non-blocking).

- **The record-move classifier can run three times for one denied line, and the comment says
  once.** In `hooks/allow-repo-commands.sh`, `main()` judges `orchestrator_moves_own_record` first,
  and the comment there says the move is "judged once here". That holds only for an approved
  move. A refused one (O18, ambiguous) is judged again by `orchestrator_command_allowed`, through
  `orchestrator_moves_own_record` and, for a bare `git mv`, `orchestrator_git_allowed`. That is up
  to three `roots.py stranded` subprocesses, so 3 × `ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS`
  (15 s) in the worst case. That is still under the 60 s hook timeout. Fix: pass `moves` into
  `orchestrator_command_allowed` so it skips the move judgment it already has, or cache the
  classifier's answer per call. Then make the comment true. Assertion: with a counting stub
  classifier, a refused own-record move runs it once. Raised by `orchestrator-record-move-guard`'s
  review (round 1, non-blocking).

- **No test pins the record-move classifier's fail-closed paths.** H28 has no row where the
  vendored `analysis/roots.py` is a symlink or is missing beside an otherwise approvable own
  stranded record. The code refuses both: `orchestrator_stranded_own_record` checks `islink` and
  `isfile`, and a missing script also exits non-zero. Fix: two rows in
  `self/tests/hook-orchestrator-role.sh` H28. Assertion: each is the allowlist denial, and
  restoring the file approves the move again. Raised by `orchestrator-record-move-guard`'s
  review (round 1, non-blocking).
