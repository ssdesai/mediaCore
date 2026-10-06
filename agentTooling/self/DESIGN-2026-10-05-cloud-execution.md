# Design 2026-10-05 — one lifecycle, local and cloud, behind adapters

Status: **decided**, ready to build as the features in §10. Input:

- a field report of twelve problems from a hNM feature (`graph-view-controls`) run end
  to end in a Claude Code cloud session;
- this checkout's own gate, run in a cloud container on 2026-10-05;
- probes of that container's `gh` and proxy.

Each defect is located in the code. Where something was inferred and not reproduced, it
says so. The decisions taken in review are recorded in §11.

## §0 The problem

The lifecycle hard-codes four facts that are true on a laptop and false in a cloud
container:

1. The forge branch is the slug.
2. A feature gets a worktree inside a primary that stays on `main`.
3. `gh` is authenticated and speaks GraphQL.
4. The machine-local state (`~/.claude/projects/`, the claims ledger, a Terminal.app)
   holds everything this machine has ever done.

A cloud session differs in five ways:

1. It may push only to its assigned `claude/…` branch.
2. It starts on that branch.
3. It is one session from first message to PR.
4. Its `~/.claude` is new with each container.
5. Its `gh` reaches GitHub only through a proxy that injects credentials and refuses
   GraphQL.

Nothing in the harness detects which world it is in: no script reads
`CLAUDE_CODE_REMOTE`, `uname` or any CI variable.

## §1 The principle: the lifecycle never asks where it is running

The high-level logic stays identical in both places: the same steps, the same order, the
same refusals, the same records. Every difference between a laptop and a container lives
in a **detector** and a few **adapters** with fixed interfaces. `feature-start.sh`,
`feature-close.sh`, `feature-capture.sh`, the runners and `pr.sh` call the adapters and
never test the environment themselves.

A `self/gate.sh` check enforces this. It fails when `CLAUDE_CODE_REMOTE` or
`AGENTTOOLING_PROFILE` appears in any tracked file other than:

- the detector;
- the adapters;
- their tests.

Two adapters exist already in this shape: `plans/open-session.sh` and
`plans/worktree-setup.sh`. The rest of this design extends the pattern.

### The detector

`env-profile.sh`, a new sourced file at the root beside `plan-runner-roots.sh`, sets
`AGENTTOOLING_PROFILE` to `local` or `cloud`:

- an explicit `AGENTTOOLING_PROFILE` already in the environment wins (tests, and
  forcing);
- otherwise `CLAUDE_CODE_REMOTE=true` → `cloud`;
- otherwise `local`.

`feature-start.sh` prints one `profile` line naming the profile and the variable that
decided it. The manifest's fence gains `profile`, which `check-plans.sh` accepts and
`report.py` shows, so a cost record says where it was made.

### The adapters

| Adapter | Interface | Local | Cloud | Owned by |
|---|---|---|---|---|
| checkout layout (functions in `env-profile.sh`) | `feature_checkout <slug>`, `feature_branch <slug>`, `create_checkout <slug> <base>` | `<primary>/.worktrees/<slug>`, branch `<slug>` | the primary itself, on the assigned branch (§2) | agentTooling, new |
| `forge.sh` | `pr-find <head>`, `pr-open <head> <base> <title> <body-file>`, `auto-merge <pr-url>` | `gh api` REST; auto-merge by `gh pr merge --auto --merge` | `gh api` REST; auto-merge by the proxy's `ccr/auto_merge` route (§5) | agentTooling, new |
| `plans/open-session.sh` | `open-session.sh <checkout>` | Terminal.app | prints that the session is already in the feature's checkout | repo, exists (template-version 4) |
| `plans/worktree-setup.sh` | run inside a new checkout | venv, `npm install`, a port | the same, run in place | repo, exists |
| `plans/environment.sh` | sourced by the gate, the setup hook and the repo's own scripts | profile facts: DB connection, browser path | the same keys, the container's values | repo, new (seeded) |
| `plans/cloud-setup.sh` | once per container, as a `SessionStart` hook | not wired | start Postgres, create the role, write what `environment.sh` reads | repo, new (seeded) |

## §2 The checkout and the branch (items 1, 2, 4, 6, 8)

**Rule.** Every script reads the feature's branch from the manifest (`branches[0]`) and
its checkout from `feature_checkout`. None of them derives either from the slug. The
start is the only writer:

- **Local:** `create_checkout` is today's `git worktree add .worktrees/S -b S
  origin/<base>`, and the branch is the slug. Nothing changes.
- **Cloud:** the container is the worktree. A worktree inside a container adds a second
  checkout to set up (item 4), a cwd for delegates to get wrong (item 8: `npm install` in
  the primary's root), and a branch the session cannot push (item 1). So
  `create_checkout` uses the primary itself, on the assigned branch:
  - `--branch <name>` names the branch. By default it is the current branch, when that
    is not the base. On the base with no `--branch`, the start refuses and names the
    flag. The script does any `git checkout -b`, so LIFECYCLE rule 2 holds: agents never
    create a branch, the start does.
  - It refuses a branch carrying commits not on `origin/<base>` (somebody's work) and a
    dirty tree.
  - A container pushes one branch, so it holds one feature. A second start in a container
    whose branch already carries a started feature is refused, naming that feature.

**What follows from the rule:**

- **The "primary on `main`" requirement** (item 2) becomes "the feature's checkout
  contains `origin/<base>`". It is checked the same way in both places. A checkout
  strictly behind with no commits of its own is fast-forwarded, and the run exits 3 with
  the command to run again (LIFECYCLE step 2's rule, unchanged).
- **The prune** of merged worktrees runs in both places. In a container it finds no
  worktrees and does nothing, with no special case.
- **A refused start is re-runnable without loss** (item 4). Locally, takeover is
  unchanged. In the cloud, a re-run finds the checkout already there and resumes at the
  setup hook. Nothing is deleted, so a fix made by hand survives.
- **`feature-close.sh`** refuses "not on the manifest's branch" in place of "not on branch
  `S`". **`feature-capture.sh`** pushes that branch. **`pr.sh`** already pushes
  `current_branch`.
- **Cost attribution** (item 1). The session's transcripts carry `gitBranch: claude/…`
  and the fence says `claude/…`, so the existing literal match in `capture_planning.py`
  (`branches_seen & set(branches)`) claims them. No alias, no glob.

## §3 Who is the router is derived, not configured (item 6)

**Rule.** The start writes a routing record only when the session running it was
launched on a branch other than the feature's:

- **Locally**, a start run from the primary is launched on `main`, not `S`. That session
  is a router, exactly as today: `routing.json` is written, and `--pin` remains the
  opt-in.
- **In the cloud**, the session was launched on `claude/x`, which is the feature's
  branch. It is the feature's coordinator, claimed by branch under LIFECYCLE rule 1 with
  no pin and no routing record. The window `from` the start stamps cuts off the part of
  the session spent before the feature existed. That spend lands in the capture's
  unclaimed residue, which is honest: it was routing.
- **The close's unpinned-builder check** needs no special case. With no routing record
  it has nothing to refuse.
- **`--open`** calls `open-session.sh`. In the cloud that adapter says the session is
  already in the feature's checkout.

`ORCHESTRATION.md` gains one paragraph. It says a session launched on the feature's
branch is its coordinator wherever it runs, and that in the cloud that is every session.

## §4 Runner children must not inherit the parent's session id (item 9)

**Defect, located.**

- `plan-runner-lib.sh` launches `claude -p` with the parent's environment. It adds only
  `AGENTTOOLING_HEADLESS` and `AGENTTOOLING_SCRATCH` (lib ≈ 783–785), so
  `CLAUDE_CODE_SESSION_ID` is inherited.
- The field report says the child then reported the parent's id. **Inferred from the
  report; reproduce first.**
- That id is written to the pass's `*.usage.json` (lib ≈ 912).
- `collect_excluded_session_ids` (`capture_planning.py` ≈ 258–287) then marks it a
  runner session.
- The scan `continue`s past it, pin or no pin (≈ 2795–2801), and does so before the
  subagent walk (≈ 2838).
- `find_pinned_elsewhere` skips the directories the main walk "already" walked (≈ 2878;
  402–417), so the coordinator's subagents are lost too.
- Result: $2.06 recorded instead of $29.23.

This is a bug wherever it runs, not a profile difference.

**Rules.**

1. **Scrub.** The runner launches every `claude -p` with `CLAUDE_CODE_SESSION_ID` and
   `CLAUDE_CODE_REMOTE_SESSION_ID` unset (`env -u`). It also passes an explicit
   `--session-id <uuid>` where the CLI supports it, so the child's id is the runner's
   choice and not an inheritance.
2. **Exclude by transcript, not by id alone.** An id is runner-only when every transcript
   line for it is headless. One that also has interactive lines is a collision: the
   capture warns, naming both, and keeps the interactive lines as the coordinator's. The
   runner's usage figure stays the runner's.
3. **Walk subagents even for a skipped parent.** `find_pinned_elsewhere` searches every
   directory, this repo's included, for a pinned id the main walk did not reach.

**Assertions** (`subagent-capture.sh`, `session-claims.sh`):

- a fixture whose runner usage names the coordinator's id still captures the coordinator
  and its pinned subagent;
- `run-review.sh` with a stubbed `claude` that echoes `CLAUDE_CODE_SESSION_ID` records a
  different id from the parent's.

## §5 The forge is an adapter (item 11)

**Defect, located.**

- `templates/plans/pr.sh` and `self/pr.sh` check `gh auth status`. On failure they print
  `skip` and **exit 0 before any push**.
- `feature-close.sh` then stamps `pr_opened rc=0 url=""`, recorded as a success.

**Probed in this container on 2026-10-05:**

- `gh auth status` reports the `GH_TOKEN` as invalid. It is a placeholder.
- `gh api repos/ssdesai/agentTooling` succeeds: the proxy injects credentials.
- `gh pr list` is refused with a 403: "GitHub GraphQL is not available from Claude Code
  sessions; use the REST API". The message names the cloud-only routes, among them
  `PUT /repos/{o}/{r}/pulls/{n}/ccr/auto_merge`.
- `gh pr create` and `gh pr merge` are GraphQL, so they fail in the cloud.

**Rule.** `forge.sh` (agentTooling, beside the runners) is the only code that talks to
the forge:

| Verb | Local | Cloud |
|---|---|---|
| reachability | `gh auth status` | `gh api /repos/{o}/{r}` (never `auth status`) |
| `pr-find <head>` | `gh api` `GET /repos/{o}/{r}/pulls?head={o}:{head}&state=open` | same |
| `pr-open <head> <base> <title> <body-file>` | `gh api` `POST /repos/{o}/{r}/pulls` | same |
| `auto-merge <pr-url>` | `gh pr merge --auto --merge --delete-branch` | `gh api -X PUT …/pulls/{n}/ccr/auto_merge` (merge method `merge`, never squash) |

- **Find and open share one REST path in both places.** Only reachability and auto-merge
  differ.
- **`{o}/{r}` comes from the origin URL**, normalised as in §6.
- **Exit codes.** Every verb exits non-zero on failure, and only `pr-find` may print
  nothing on success.
- **`pr.sh`** keeps its repo-owned shell and its two entry points. It calls `forge.sh`
  for the GitHub part: push with git, `pr-find`, otherwise `pr-open`, and print the
  url. A forge failure is a non-zero exit, so **no path stamps `pr_opened` without a
  url**. `pr.sh` goes to `template-version: 5`, and `README.md` gains an "Adopting the
  forge adapter" hand-merge section. A non-GitHub repo keeps its own forge code in
  `pr.sh` and never calls `forge.sh`.
- **`feature-close.sh` keeps its order** in one run: PR → `pr_opened` → capture → merge
  request.

**Verified 2026-10-05:** a write (`gh api POST /repos/{o}/{r}/pulls`) through the cloud
proxy works. `cloud-close`'s own `feature-close.sh` opened PR #79 with `forge.sh
pr-open`, and `pr-find` (`GET`) answered through the same proxy.

**Assertions** (`feature-lifecycle.sh`, `gh` stubbed):

- under `cloud`, the close opens the PR through `gh api` and never calls `gh pr` or
  `gh auth status`;
- under `local`, the same close calls `gh pr merge --auto` for the merge request;
- a stubbed REST failure exits non-zero and stamps the rc with no url;
- `pr-find` returning a url skips `pr-open`.

## §6 The ledger knows what it has seen (item 10)

**Defect, located.**

- The claims ledger is `~/.claude/subagent-claims.json`, local to the machine, with no
  provenance (`capture_planning.py` ≈ 473–553).
- `--annotate-frozen` runs `annotate_corpus` without first registering this corpus's
  frozen records (≈ 3572–3580).
- `annotate_frozen_record` treats absence from the ledger as "no longer a claimant" and
  deletes `also_claimed_by` (≈ 873–923).
- On a fresh container that deleted the mention from 20 merged features and re-rendered
  their reports.
- Repo identity is the origin URL as written (`repo_identity`, ≈ 557–575). The cloud's
  `https://github.com/o/r` and a laptop's `git@github.com:o/r.git` are two identities for
  one repo (inferred).

This is a bug wherever it runs: any partial ledger triggers it.

**Rules.**

- **The ledger gains provenance.** `seen: {<repo identity>: <last registered instant>}`
  records each corpus whose frozen records it has registered.
- **Absence means no claim only for a repo it has seen.** `annotate_frozen_record`
  removes an `also_claimed_by` entry only when the ledger has `seen` that entry's repo.
  An unseen repo's mention is kept, and one line names it as not re-checked.
- **Register before annotating.** `--annotate-frozen` registers this corpus's frozen
  claims first.
- **Normalise repo identity** to `host/owner/repo`: drop the scheme, `git@`, `.git` and
  case. Stored records are read through the same normaliser, so nothing is migrated.

**Assertions** (`claims-ledger.sh`):

- an empty ledger leaves every frozen `also_claimed_by` untouched and the capture commits
  no sibling;
- a ledger that has seen repo X removes a stale X mention as today;
- the https and ssh spellings of one origin are one identity.

## §7 The gate stays strict; the environment is fixed (items 3, 5)

**Decision (§11 Q2): no exceptions mechanism.** Every cloud failure in the field report
has a fix at its source:

| Failure | Fix | Where |
|---|---|---|
| Chromium will not run sandboxed as root (18 tests) | launch with `--no-sandbox` when uid is 0 | the repo's Playwright config: a test-configuration fix |
| no Postgres, no passwordless role | start it and create the role; export the connection | `plans/cloud-setup.sh` → values read through `plans/environment.sh` |
| `cdn.playwright.dev` blocked | pin Playwright to the image's Chromium: `PLAYWRIGHT_BROWSERS_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` | `plans/environment.sh` |

**Rules.**

- **A red base gate in the cloud means the repo's cloud setup is unfinished.** Finishing
  it is a feature in that repo. `GATE_EXPECTED_RED` stays a level-sentinel mechanism
  only.
- **`--no-gate` stays the escape hatch.** The start records it in the manifest's fence
  as `gate: "skipped"` (otherwise `"green"`), so a feature started on an unverified base
  says so in its record. `check-plans.sh` accepts the key and `report.py` shows it.
- **`plans/environment.sh`** (new, seeded, repo-owned, template-versioned) holds facts,
  never exceptions:
  - the DB connection;
  - the browser path;
  - anything else that differs by profile.

  The gate, `worktree-setup.sh` and the repo's own scripts source it. The skeleton
  carries a commented example of each profile and no `brew`. The repo-owned scripts that
  told a cloud user to `brew services start` (item 5) read it instead.
- **`plans/cloud-setup.sh`** (new, seeded, repo-owned, template-versioned) is the
  once-per-container step. `sync-plans.sh` wires it as a `SessionStart` hook in the
  repo's `.claude/settings.json`, guarded to run only under the cloud profile, merged
  additively like the existing hook entry. `templates/README.md` names the cloud
  environment's own setup script as the alternative, and when to prefer it.
- **`sync-plans.sh --check`** reports a missing `environment.sh` or `cloud-setup.sh` as
  `MISSING`, like `BACKLOG.md`.

**Assertions** (`sync-check.sh`, `hook-wiring.sh`):

- the seeding and the versions;
- the `SessionStart` entry added once and never duplicated;
- the start's `gate` key is `skipped` under `--no-gate` and `green` otherwise.

## §8 Long work survives a container restart (item 7)

**Defect.** A 15-minute background gate and the implementer waiting on it both died
with the container. `AGENT_DIRECT`'s checkpoint resume worked, at the price of a second
implementer.

**Rules.**

- **The gate template becomes resumable at check granularity.** Each check's result is
  written to `gate-state/<tree-sha>/<label>` as it finishes. Under `GATE_RESUME=1`, which
  the runners and the start set, a check already recorded for the same tree is skipped,
  so a restarted gate re-runs only what had not finished. The tree sha is `git
  write-tree` over the checkout, untracked inputs included, **with the gate's own
  outputs and the features corpus left out** (`plans/features/`, or `self/features/`
  under `--self`): the runners write there between gate runs (`stamp_timing`'s
  `timing.jsonl` line, plan moves, progress and usage sidecars), so a corpus in the sha
  would make every runner-started gate see a new tree and never resume. A gate check that
  reads the corpus therefore resumes across corpus edits, which is accepted. This is the
  same in both profiles.
- **Doctrine, in `ORCHESTRATION.md` and `AGENT_DIRECT.md`:**
  - the coordinator, never the implementer, owns any run longer than a few minutes;
  - the implementer's brief ends at "commit and checkpoint, then stop", so a restart
    costs no implementer;
  - in a cloud session the coordinator arms one `send_later` check-in before such a run,
    so a restart wakes it. The harness cannot call that tool itself, so this is doctrine,
    not code.

**Assertion** (`tiered-gates.sh` or a new `gate-resume.sh`, against the template gate):
a gate killed after check k re-runs from k+1 on the same tree, and from the start on a
changed one.

## §9 Hook friction (item 12)

**Decision (§11 Q4): the scratchpad is not auto-approved.**

The rewrite reasons send the model to "write a script to the scratchpad and run it by
name", and in an interactive session that script then prompts. Approving it would be a
bypass:

- the hook judges a script's path and arguments, never its contents;
- a Write into the scratchpad is not normally prompted;
- "write any code, then run it unseen" would launder every command the hook denies for
  being unreadable.

The prompt is the human approving code they can see. It is the policy working, not
friction.

**What does change:** `sleep` gains a rewrite reason — "nobody polls: run it in the
background and wait for the notification" (`ORCHESTRATION.md`). Today it falls through
to a silent prompt; the change can only tighten the policy. It is one row in
`self/tests/allow-repo-commands.sh`, carried by whichever feature next edits the hook.

`~` paths and mixed read/write lines are unchanged: the rewrite is the lesson.

**Raised by this review:** the runners' `AGENTTOOLING_SCRATCH` is the same bypass,
accepted for headless executors with the OS sandbox off. Recorded in `BACKLOG.md`.

## §10 Build

Four `--self` features, in order:

| Feature | Covers | Method | Why this order |
|---|---|---|---|
| `cloud-self-gate` | the gate's own red checks in a container (below) | hand | Nothing else can be gated in the cloud until this is green. |
| `cloud-close` | the close-critical part of §2 and §5: `feature-close.sh`, `feature-capture.sh` and `run-review.sh` read the branch from the manifest's `branches[0]` instead of deriving it from the slug; `forge.sh` with `pr-find` and `pr-open`, which `feature-close.sh` calls | direct | Until close runs in the cloud, every cloud feature reaches its PR by hand, past every refusal close holds: no PR without a clean review of the exact tree, no unreviewed commit after it. That is how `cloud-self-gate` reached its PR without the harness review. This is the last feature bootstrapped by hand. |
| `cost-capture-collisions` | §4, §6, the sole-claimant cut (below) | direct | Bugs that bite locally too. Its own capture must be right before the larger feature's is taken. |
| `execution-profiles` | the rest of §1, §2, §3, §5, plus §7, §8, the `sleep` reason | plans, or two direct slices: A = detector, layout, start, `forge.sh` auto-merge, `pr.sh` v5; B = `environment.sh`, `cloud-setup.sh`, `sync-plans.sh`, resumable gate, doctrine | Depends on a green self gate, a close that runs in the cloud, and a correct capture. |

**`cloud-self-gate`'s findings.** Run on 2026-10-05, `self/gate.sh` exits 0 with a red
verdict:

- **`hook-wiring`**: the primary has no `.claude/settings.json`, which was untracked and
  generated, so a fresh clone had none. Running `wire-settings.py --self --write` belongs
  to the checkout's setup; `self-cloud-bootstrap` (below) instead tracks the generated
  file, so a cloud checkout is born wired.
- **`feature-lifecycle` S4h–S4n** (9 assertions): the primary-behind-`origin/main` and
  remote-merge prune fixtures. **Cause found while building:** the bare origin's HEAD came
  from `init.defaultBranch`. The container sets none, so HEAD was `master` and the forge
  clone checked out an empty head. The fix pins it to `main`.
- **`allow-repo-commands`**: `cat link-home/*` is ALLOWed, where the fixture links `$HOME`
  (`/root` here) into the project root. **Cause found while building:** `/root` holds only
  dotfiles, so the glob names nothing, which the hook approves by design. This is not a
  confinement bug. The fix makes the fixture build the home directory it links.

  Both are recorded in `self/features/cloud-self-gate/README.md`.

- **Found at its capture, for `cost-capture-collisions`:** a pinned session with no other
  claimant is billed whole. `session_window` only splits a session between claimants and
  never cuts a sole claimant to its window. So `cloud-self-gate`'s record carries the
  9.7-hour design session, which was launched on `main` and pinned because of that. In
  the cloud, where §2 claims the session by branch, this goes away for the ordinary case,
  but a pin still needs the cut.

- **Found at `cloud-close`'s close, for `cost-capture-collisions`:**
  - `feature-close.sh` ran end to end in the cloud, and `gh api POST /pulls` worked
    through the proxy (§5, PR #79).
  - §4 reproduced: the review runner's child carried the coordinator's session id, so
    the capture excluded the coordinator, and the pinned implementer went unfound
    (`find_pinned_elsewhere` skips the excluded parent's directory).
  - §6 reproduced: the annotate step, run from this container's empty ledger, deleted
    `also_claimed_by` from 11 frozen sibling records, and the close committed and pushed
    them. They were restored by hand before merge.
  - **Running a full close before §6 lands is unsafe in any fresh container.** Until
    `cost-capture-collisions` merges, a cloud close must not let `--annotate-frozen`
    write sibling records. `cost-capture-collisions` makes the annotate step refuse to
    delete `also_claimed_by` entries for repos its ledger has never seen.

- **`cost-capture-collisions`' findings** (`self/features/cost-capture-collisions/`,
  rulings in its `NOTES.md`):
  - **§4 reproduced, and worse than inferred.** An inheriting `claude -p` child reports
    the parent's id **and appends its lines to the parent's own transcript file**, as a
    new root (`parentUuid: null`), with the parent's `entrypoint` — so no field a line
    carries says "headless". Under `env -u` with `--session-id <uuid>` the child writes
    its own file under that id. The runner now always launches that way.
  - **Collisions already on disk** are told apart by conversation tree: a tree whose
    opening prompt carries the sentence every runner prompt shares
    (`HEADLESS_PROMPT_MARKER`) is the runner's. A usage.json id whose transcript also
    holds other trees is a collision: those lines are priced as the coordinator's, the
    runner tree is dropped, and a warning names both. A delegate is attributed by the
    tree its spawn sits in. A pinned delegate the main walk did not reach is looked for
    in this repo's directories too.
  - **§6** as designed: the ledger's `seen` section records each registered claimant;
    an `also_claimed_by` mention of an unseen claimant is kept and named on stderr;
    `--annotate-frozen` registers this corpus first; identities are normalised for
    comparison only. Run with an empty ledger over this corpus it changes no record.
  - **The sole-claimant cut, decided:** a pinned session is cut to its window by the
    split rule even with no other claimant; a branch-selected sole claimant is billed
    whole. The reasoning is in the feature's README.
  - **Found, for `execution-profiles`:** the branch route selects a session by its
    *start*, so a cloud coordinator, launched on the assigned branch before the start
    stamps `from`, is not selected at all (§3 assumed it would be, and cut). Until the
    start handles it, the remedy is `manifest.py set-window-from`.
  - **Found at its own close** (`feature-close.sh --self cost-capture-collisions`, run in
    this fresh container, PR #80):
    - **§6 held.** No claims ledger existed. The annotate step registered this corpus,
      changed no other record ("no other record in this corpus changed"), and named 31
      `also_claimed_by` mentions of humanNetworkMap, musicMap and vinylCatalogue features
      as not re-checked, keeping each. `git diff main -- self/features` showed only this
      feature's directory.
    - **§4 held.** Both review runners ran under minted ids and were excluded as runner
      sessions ("2 excluded"). The coordinator was captured ($7.85), with both
      implementers claimed through it ($14.53, $1.45). Total recorded: $25.98, of which
      review was $2.13.
    - **The start-instant finding bit, as predicted.** The coordinator began before the
      `from` the start stamped. `set-window-from` moved `from` back to its first instant
      before the close.

- **`execution-profiles`' findings** (`self/features/execution-profiles/`, rulings in its
  `NOTES.md`). **Built by slice A** (direct, one implementer): the detector and the
  layout adapter in `env-profile.sh` (§1); the confinement check as
  `self/profile-confinement.sh`, blocking in `self/gate.sh`, prose (`*.md`) exempt and the
  match whole-word so `CLAUDE_CODE_REMOTE_SESSION_ID` is no hit; `profile` in the fence
  (`manifest.py init --profile`, shown by `report.py`, accepted by `check-plans.sh` with no
  new check); the cloud start (§2) — `--branch`, the base refusal, one feature per
  container, no foreign commits, no dirty tree, "contains `origin/<base>`" with the same
  fast-forward and exit 3, and a refused start resumed from a lock in `.git/` with nothing
  deleted; the router derived from the launch branch (§3); `forge.sh auto-merge` and
  `reachable` (§5), with `pr.sh` at template-version 6 and `open-session.sh` at 4. **Built
  by slice B** (direct, a second implementer): `plans/environment.sh` and
  `plans/cloud-setup.sh` seeded at template-version 1 (§7), `--check` reporting either
  `missing`; the `SessionStart` entry in a consuming repo's settings; the gate template at
  3 and `worktree-setup.sh` at 2, both sourcing `environment.sh`, the gate resumable (§8)
  with `GATE_RESUME=1` set by the runners and the start; the fence's `gate` key; §8's
  doctrine in `ORCHESTRATION.md` and `AGENT_DIRECT.md`; and the `sleep` rewrite (§9).
  - **The SessionStart guard is the script.** The entry names only
    `${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh`; the script sources the detector and exits
    0 outside the cloud profile, so no new file spells a profile variable.
  - **A recorded failure is never reused, only a pass**, and only for the same command
    line. Read literally, "a check already recorded is skipped" would replay a red check
    after an environment fix the tree sha cannot see — and the start now resumes its base
    gate. A level gate's expected-red flags change the command, so the final gate never
    reuses a level's ignore-filtered result.
  - **`git add` refuses an `:(exclude)` pathspec naming an ignored path**, which the gate's
    own outputs always are, so the sha's exclusion is a `git rm --cached` after the add.
  - **`self/gate.sh` resumes too.** §8's defect was this checkout's own gate, and
    `sync-check.sh` pins each self copy to its template's version.
  - **Round 2: the features corpus is out of the tree sha** (escalation 01, NOTES ruling
    42). Round 1's gate never resumed under a runner, because `stamp_timing` and the plan
    moves wrote into the hashed tree between gate runs. `GATE_FEATURES_DIR`
    (`plans/features` / `self/features`) joins the gate's outputs in
    `GATE_TREE_EXCLUDES`; `gate-resume.sh` drives `run-plans.sh` on a level sentinel to
    prove it.
  - **`cloud-self-gate`'s "born with the file" could not be a hook in that file.** The
    `--self` settings file was untracked and generated, so a fresh clone had none and no
    hook in it could run. The ruling then put the write in the cloud environment's own
    setup script; `self-cloud-bootstrap` superseded it by tracking the generated file
    itself (below). `--self` still writes no SessionStart entry (it has no
    `plans/cloud-setup.sh`).
  - **The start-instant finding, fixed in the start.** A coordinator's `from` is its own
    first transcript instant, floored to the second (`manifest.py session-start`), so the
    branch route selects it with no `set-window-from`; the clock and one warning naming
    that command when the transcript cannot be read. The cost consequence, accepted in the
    manifest: the coordinator's spend before the start — in a container, reading the
    design for the very feature it then starts — is billed to the feature, not left in
    the unclaimed residue as §3 first assumed.
  - **The cloud `ccr/auto_merge` body is chosen, not observed**: `merge_method=merge`, the
    REST spelling. The proxy names the route but not its body, and nothing here has made
    the call yet (`self/BACKLOG.md`).
  - **A cloud session that starts with `--branch` from the base is a router** by the §3
    rule, and in a container it is also the only session there is — so if it builds, it
    must pin itself; the start's "Next" lines say so. The ordinary cloud start, on the
    assigned branch, never meets this.

- **`self-cloud-bootstrap`'s findings** (`self/features/self-cloud-bootstrap/`, rulings in
  its `NOTES.md`). A fresh agentTooling session is wired by the repo alone, with nothing
  in the cloud environment's setup script: `.claude/settings.json` is **tracked**, the
  whole `--self` policy, generated by `wire-settings.py --self --write` and compared byte
  for byte by `--check` and the gate; its `PreToolUse` command is guarded to a silent
  no-op where `${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh` does not exist. This
  replaces the "settings change in the environment's setup script" above. Three findings,
  on Claude Code 2.1.289 (headless) and 2.1.290 (cloud), decided it:
  - **A policy written at session start races the first tool call.** Round 1 built a
    tracked bootstrap whose `SessionStart` hook generated the policy into an untracked
    `settings.local.json`. The settings watcher reloads it asynchronously after the hook
    returns: the first call, `python3 -c 'print(1)'`, missed the `PreToolUse` hook in 3 of
    15 fresh headless sessions (all three under `--permission-mode acceptEdits` with a
    two-step prompt, 3 of 6 there; 9 of 9 caught under the other launches; 1 of 1 in a
    cloud session), and in none of 4 whose file existed at startup. A miss reaches the
    ordinary permission flow with no hook and no deny rule. A tracked file is read at
    startup, before any call.
  - **A vendored file is loaded only by a session launched inside `agentTooling/`.** At a
    consuming repo's root only the root's own settings loaded and the nested one never
    ran; launched in `consumer/agentTooling/`, the vendored settings ran and the root's
    did not — the project is the launch directory, not the git root — with
    `${CLAUDE_PROJECT_DIR}` that directory, where every path the file names exists. So
    tracking the full policy ships nothing harmful (the `self-settings-untracked` premise
    did not hold), and such a session — a `--self` executor's — is better off with it.
  - **A fast-forward over the commit that tracks the file needs no migration.** Git
    overwrites an ignored untracked file when a fast-forward starts tracking that path,
    with identical or different bytes, so a primary holding the old generated file just
    takes the tracked one.

  Live evidence: see self/features/self-cloud-bootstrap/NOTES.md.

**Bootstrapping.** `cloud-self-gate` and `cloud-close` are built before close runs in the
cloud, so they follow the field report's workaround. Its steps are the ones close would
enforce, and none is optional:

- a hand start on the assigned branch;
- **`run-review.sh --self <slug>`, the harness review, never a stand-in.** If the runner
  refuses on the branch, the review is done by hand and recorded in `review/` with its
  verdict and the head it judged;
- no PR until that verdict is clean for the head being pushed, and no commit after it
  other than the cost records;
- the capture (`feature-capture.sh --no-push`, or its steps by hand while it cannot find
  the branch), then a push;
- the PR opened through the GitHub tools.

`cloud-self-gate` broke the second rule: an ad-hoc subagent read the diff in place of the
harness review, and the PR opened with no review record. The checklist could be skipped
because it was a checklist. From `cost-capture-collisions` on, every feature goes through
`feature-close.sh`, in the cloud as locally.

## §11 Decisions taken in review (2026-10-05)

- **Adapters, not modes.** The lifecycle stays identical. Differences live in the
  detector and the adapters (§1). This removed a capability table, a "solo session"
  mode, a forge handoff file and a `--pr-url` re-run from the first draft.
- **The forge through `gh` in both places, not MCP.** A bash script cannot reach MCP
  tools, and the proxy makes `gh api` work in the cloud (§5).
- **In the cloud, the container is the worktree** (§2).
- **Q2: fix tests and environments; never declare exceptions** (§7).
- **Q4: no scratchpad auto-approval**; the existing headless one goes to the backlog
  (§9).

## §12 Deliberately excluded

- **Persisting transcripts beyond the container.** The close captures and freezes the
  figures onto the branch before the container goes. A session that never closes is
  lost, as it is in the unclaimed residue today.
- **The harness calling MCP.** It cannot, and `forge.sh` makes it unnecessary.
- **Several features per cloud session.** Ruled out by the push rule. Use one session
  per feature.
- **Fixing consuming repos' own scripts and tests.** Each repo's cloud setup is its own
  feature, using the seeded files.
- **A per-feature budget.** Unchanged ruling.
