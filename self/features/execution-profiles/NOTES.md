# Notes: execution-profiles

Rulings made during the direct build, one line of rationale each. The design
(`self/DESIGN-2026-10-05-cloud-execution.md` §1–§3, §5, §7–§9) and the manifest's "Rulings
taken before the build" are not reopened here; only how they were built is. Slice A is the
detector, the layout, the start, `forge.sh auto-merge`/`reachable` and `pr.sh` v6; slice B
(rulings 23 onwards) is §7, §8, §9 and the `gate` key.

## Slice A — §1 the detector

1. **`env-profile.sh` runs the detection when sourced** and EXPORTS `AGENTTOOLING_PROFILE`,
   so a child an adapter runs (the seeded `open-session.sh`) reads the decided value
   without deciding again. `PROFILE_DECIDED_BY` names the variable that decided it:
   `AGENTTOOLING_PROFILE`, `CLAUDE_CODE_REMOTE`, or `default` when neither did.
2. **An explicit value that is neither `local` nor `cloud` is an error, not a fallback.**
   `profile_check` fails naming it, and `feature-start.sh` and `forge.sh` refuse on it
   before doing anything: a typo in a forcing variable must not silently mean `local`.
3. **`CLAUDE_CODE_REMOTE` counts only when exactly `true`** (the design's wording); any
   other value is the default `local`.
4. **The layout functions take a hidden `layout_init <primary> <worktrees-dir> <base>
   [<branch>]`** before `feature_checkout`/`feature_branch`/`create_checkout`, keeping the
   design's one-argument interface. `create_checkout <slug> <start-point>` takes the
   resolved start point (`origin/<base>` or the local base), not the bare base name, since
   the start already resolves it for its message — recorded as a deviation from the
   table's `<base>`. Local: `git worktree add -q <primary>/.worktrees/<slug> -b <slug>
   <start-point>`, byte for byte the call the start made before. Cloud: nothing when the
   primary is already on the feature's branch, else `git checkout -q -b <branch>
   <start-point>`.
5. **`WORKTREES_DIR_NAME` stays in `feature-start.sh`** (capture_planning.py mirrors it)
   and is passed to `layout_init`, rather than moving a constant two files share.

## Slice A — §1 the confinement check

6. **`self/profile-confinement.sh [<dir>]`** is the check, a script so a test can run it
   on a planted repo; `self/gate.sh` records it as a blocking check. It greps tracked
   files (`git ls-files`, so an untracked scratch file never fails a gate) for the two
   names as **whole words** (`grep -w`): `CLAUDE_CODE_REMOTE_SESSION_ID`, which
   `plan-runner-lib.sh` scrubs, is a different variable and not a hit.
7. **Prose is exempt: every `*.md` file.** The design, the READMEs and the doctrine must be
   able to name the variables to describe the rule; what the rule is about is code that
   READS them. Everything else tracked — shell, Python, JSON, the templates — is checked.
8. **The allowlist** (`CONFINEMENT_ALLOWED` in the script): `env-profile.sh` (the
   detector), `forge.sh`, `self/open-session.sh` and `templates/plans/open-session.sh`
   (the adapters that branch on the profile), the check itself, and everything under
   `self/tests/` (the tests force the profile). Slice B's `cloud-setup.sh` template and
   SessionStart guard will need adding there.

## Slice A — `profile` in the fence

9. **`manifest.py init --profile local|cloud`**, optional, written after `base` in the
   fence's key order; absent in every manifest written before it, and every reader
   (`manifest_field`, `get`, `report.py`) treats absence as "not recorded", never as
   `local`. An unknown value is refused by `init`.
10. **`check-plans.sh` gains no check.** It already ignores keys it does not know, so a
    `profile` passes; a 15th check (validating the value) would change the pinned count
    of 14 in `self/tests/check-plans.sh` and slice B's `gate` key would add a 16th, for a
    field that moves no money. `init` validates on write instead; `check-plans.sh`'s test
    gains a case showing a fence with `profile` still passes all 14.
11. **`report.py` prints `Profile: <value> — where the feature was started (env-profile.sh).`** under the Generated
    line, and `report.json` carries `profile`, both only when the manifest has one, so a
    report of a feature started before this is byte-identical.

## Slice A — §2 the cloud start

12. **`--branch` under the local profile is refused** naming the rule (locally the branch
    is the slug): accepting and ignoring it would make a local start quietly differ from
    what was typed.
13. **The cloud checks, in order, before anything is written:** a second feature (a
    `<x>: start` commit in `origin/<base>..HEAD`, or a tracked manifest whose
    `branches[0]` is this branch — refused naming `<x>`); commits not on `origin/<base>`
    (refused naming the count and the newest subject); a dirty tree (refused naming the
    first paths); then the "contains `origin/<base>`" check — a checkout strictly behind
    with no commits of its own is fast-forwarded and the run exits 3 with the rerun
    command, exactly the local rule. The local stale-primary block is unchanged and runs
    only under `local`: under `cloud` the primary is on the assigned branch, which the
    local block would refuse as "not on main".
14. **An existing `--branch` that is not checked out is refused**: the start creates the
    feature's branch or uses the one the session is on; switching to some other existing
    branch is a checkout a human should choose.
15. **The cloud start lock lives in the primary's own admin dir** (`.git/feature-start.lock`,
    the same file name), written right after `create_checkout`, with `slug=`, `branch=` and
    `launched_on=` added to the local lock's `pid=`/`started=`. The local lock is
    byte-identical to before; the local prune never reads this one (it reads only worktree
    admin dirs).
16. **Resume = a lock for THIS slug on THIS branch whose PID is dead.** Then the dirty and
    foreign-commit refusals are skipped (the hand fix is exactly such a change, and the
    start commit only ever `git add`s the feature directory, so a fix is never swept into
    it), `create_checkout` is skipped, an existing uncommitted manifest and review stub are
    kept rather than rewritten, and the launch branch comes from the lock's
    `launched_on`, so a resumed start that began on `main` is still a router. A live PID is
    refused as a concurrent start; a lock for ANOTHER slug is refused naming it (a
    container holds one feature). A start killed between `checkout -b` and the lock write
    leaves no lock; its re-run is a fresh start on that branch, and is then the
    coordinator — accepted, since that window is one command long.

## Slice A — §3 the router is derived, and the start instant

17. **"Launched on" is `git branch --show-current` of the primary when the start begins**
    (the manifest's ruling), or the lock's `launched_on` on a resume. The session is the
    coordinator exactly when that equals the feature's branch; then no routing record is
    written and nothing is pinned (unless `--pin` was asked, which is honoured as before).
    Locally the launch branch is `main` and the feature's branch the slug, so the local
    start always writes the routing record as before.
18. **The start instant: `manifest.py [--self] <slug> session-start <id>`**, a new
    read-only subcommand printing that session's first transcript instant, floored to the
    second with a `Z` (the floor keeps `from <= start`, so the branch route's
    start-in-window test selects it). The start calls it only for a coordinator with a
    session id; when it prints nothing (no transcript, or no session id at all) `from` is
    the clock and the start prints ONE `warn` line naming `set-window-from` as the remedy.
    Consequence, accepted by the manifest: the coordinator's spend before the start is
    billed to the feature.

## Slice A — §5 the forge

19. **`forge.sh auto-merge <pr-url>`.** The number is the url's last path segment and must
    be digits, else it fails before any forge call. Local: `gh pr merge <url> --auto
    --merge --delete-branch` (the flags `pr.sh` passed before). Cloud: `gh api -X PUT
    repos/<o>/<r>/pulls/<n>/ccr/auto_merge -f merge_method=merge`. **Field name
    `merge_method`, value `merge`:** the REST spelling GitHub's own merge endpoint
    (`PUT /pulls/{n}/merge`) uses, and the route is a REST route; the proxy's refusal text
    names the route but not its body, and the GitHub MCP tool's GraphQL-style `mergeMethod:
    MERGE` is the other half of the same idea. **Unverified against the live route** —
    `self/pr.sh` never requests a merge, so the first cloud close with `PR_AUTO_MERGE=1`
    in a consuming repo is the first real call. A refusal is advisory: `pr.sh` warns and
    the PR waits for a human. Recorded in `self/BACKLOG.md`.
20. **`forge.sh reachable`**: local `gh auth status`; cloud `gh api repos/<o>/<r>` (never
    `auth status`); prints `reachable <o>/<r>`. Nothing in the lifecycle calls it yet —
    `pr.sh` deliberately has no probe, a refusing forge says so on the real call.
21. **`pr.sh` v6**: `auto_merge` finds the open PR with `"$FORGE" pr-find <branch>` and
    asks `"$FORGE" auto-merge <url>`; no PR found, no adapter, or a refusal is a warning,
    exit 0 (advisory, as before). `AUTO_MERGE_ARGS` moved into `forge.sh`.
22. **`open-session.sh` v4** (both copies): under the cloud profile it prints that the
    session is already in the feature's checkout and exits 0 without `osascript`. It reads
    `AGENTTOOLING_PROFILE`, which the start's sourcing of the detector exported — the
    adapter's contract, stated in its header.

## Slice B — §7 the environment adapters

23. **Both are repo-owned scripts in `REPO_OWNED_SCRIPTS`**, so they are seeded once, carry
    `# template-version: 1`, are hashed in `TEMPLATE_VERSIONS`, report `DRIFT` when behind
    and `missing` when deleted. **"MISSING, like BACKLOG.md"** is read as BACKLOG.md's
    actual status word, lowercase `missing` — the design capitalised it as a status name,
    and a second spelling for the same state would be two words for one thing.
24. **`environment.sh` is seeded without the executable bit** (`SOURCED_SCRIPTS` in
    `sync-plans.sh`) and refuses with exit 2, naming `.`, when run as a program: an
    `export` in a child process reaches nobody, so running it by mistake must fail loudly.
    It sources `agentTooling/env-profile.sh` when present and branches through
    `profile_is_cloud` (guarded by `declare -F` in the example, for a repo without the
    detector); its whole body is commented examples otherwise. It must be safe under
    `set -u` and `set -e`, since both callers use them.
25. **`cloud-setup.sh` is its own guard.** It sources the detector and exits 0 at once
    unless `profile_is_cloud`; with no `agentTooling/env-profile.sh` beside it it exits 0
    having done nothing (nothing can be decided). Under cloud the skeleton prints one
    "nothing configured" line. Every step must be idempotent: SessionStart fires on start,
    resume and compaction, and the entry carries no matcher so a restarted container's
    resumed session runs it too.
26. **The SessionStart guard's shape: the hook runs the detector-aware script; the
    settings entry carries no guard** (`{"hooks": [{"type": "command", "command":
    "${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh"}]}`). No file outside the detector and the
    adapters spells a profile variable — `hooks/wire-settings.py` names only the script —
    and no run-if entry point was added to `env-profile.sh`. Cost, accepted: a laptop
    session start runs one short bash process.
27. **The entry is recognised by `cloud-setup.sh` in any SessionStart hook command**, like
    the PreToolUse entry's marker: a repo's customised spelling (a matcher, `bash …`) is
    kept and never doubled; a repo's own other SessionStart hooks stay first, ours is
    appended after; a non-list `hooks.SessionStart` is `INVALID`. "Nothing the repo had
    removed" is read as the merge's existing rule — it removes nothing; an absent entry
    is re-added, as an absent PreToolUse entry is, since a deletion and a never-wired file
    look the same. The opt-out is the script's body, which is the repo's.
28. **`--check` reports the missing entry** like the rest of the wiring: `UNWIRED` (or
    `missing` for an absent file), naming `cloud-setup.sh SessionStart hook` in the gap,
    so `sync-plans.sh --check` counts it as one item. The in-sync message names it too.
29. **`--self` carries no SessionStart entry, and gains nothing for the cloud.** A
    `--self` checkout has no `plans/cloud-setup.sh`, and design §10's `cloud-self-gate`
    finding ("a cloud checkout should be born with its settings file") cannot be met by a
    hook: the generated settings file is untracked, so a fresh clone has none and no hook
    inside it can ever run to write it. The honest place is the cloud environment's own
    setup script (`python3 -B hooks/wire-settings.py --self --repo <root> --write`), a
    claude.ai settings change, not code — `templates/README.md` says so, and
    `self/BACKLOG.md` carries it. (`feature-start.sh --self` still regenerates the file in a
    primary that lacks it, as before.)
30. **The cloud environment's setup script vs `cloud-setup.sh`** (`templates/README.md`):
    the environment's for machine work — packages, toolchains, slow steps, anything that
    must exist before `.claude/settings.json` is read or must write it; `cloud-setup.sh`
    for what belongs with the repo's history — services its tests need, values
    `environment.sh` reads.
31. **The confinement allowlist names both new templates** although neither spells a
    variable today (they are adapters by definition, design §1); `hooks/wire-settings.py`
    is not listed, since it spells nothing.

## Slice B — §8 the resumable gate

32. **Only a recorded PASS is reused; a recorded failure always re-runs.** The design
    says "a check already recorded for the same tree is skipped"; read literally, a
    failure would be replayed too, and since the start now runs its base gate under
    `GATE_RESUME=1`, fixing the *environment* (starting Postgres) and re-running the start
    on the same tree would replay the red check forever — the sha cannot see the fix.
    Re-running a failure costs only that check. Recorded as a narrowing of the design's
    wording, not a reversal: a gate killed after check k still re-runs from k+1 when
    1..k passed (gate-resume K2, K7).
33. **A check is reused only when its recorded command line equals this run's** (`cmd=`
    line). A level gate passes `GATE_EXPECTED_RED` globs as `--ignore-glob` flags, so the
    same label on the same tree can mean a different command; the final gate must not
    reuse a level gate's result that ignored tests (gate-resume K8). A deferred check is
    never recorded.
34. **State file format:** `plans/gate-state/<tree-sha>/<label>`, the label with every
    character outside `A-Za-z0-9_-` turned into `_` (so `unit tests/fast` →
    `unit_tests_fast`, and no `..` or `/` can escape the directory); content `rc=<n>`,
    `cmd=<command line>`, then the report section verbatim — so a resumed run's report is
    complete. Written through `<file>.tmp` and `mv`, after the section is appended to the
    report, so a kill mid-write leaves no half record. Only the current tree's directory is
    kept: `gate_state_init` removes the others (a different tree's results are never
    reused).
35. **The tree sha:** a temporary index (`mktemp -d` under `$TMPDIR`) seeded by copying the
    real index (`git rev-parse --git-path index`, so a linked worktree's own index), then
    `git add -A -- ':/'`, then `git rm -r -q --cached --ignore-unmatch` of the gate's own
    outputs (`plans/gate-report*.txt`, `plans/gate-state`), then `git write-tree`. The
    exclusion is a removal after the add rather than an `:(exclude)` pathspec on it,
    because git fails an add whose pathspec names an ignored path — which those outputs
    always are. Ignored files (venvs, `node_modules`) are not inputs; untracked ones are.
    No git, or any failing step, means no sha: every check runs and nothing is recorded.
    Taken once, after the toolchain section and before the first check.
36. **`self/gate.sh` carries the mechanism too, and both self copies move with the
    templates** (gate 3, worktree-setup 2). `sync-check.sh` 8 pins each self copy to its
    template's version, and §8's defect was this checkout's own ~13-minute gate; the self
    copies source `self/environment.sh` when present, which agentTooling does not ship (its
    checks need no service), so the parity is honest and the line a no-op today.
    `.gitignore` ignores `self/gate-state/`. `gate-resume.sh` runs every scenario against
    both gates.
37. **`GATE_RESUME_ON="1"` lives in `plan-runner-roots.sh`**, the file every caller already
    sources; `run_level_gate`, `run-batch.sh`'s final gate and `regate`, and
    `feature-start.sh`'s base gate each prefix their gate call with it. A seeded gate older
    than version 3 ignores the variable.
42. **Round 2 — the features corpus is out of the tree sha** (the coordinator's ruling on
    escalation 01). `stamp_timing`'s `timing.jsonl` line, the sentinel and plan moves, and
    the `*.progress.md` / `*.usage.json` sidecars all write inside the hashed checkout
    between a runner's gate runs, so no runner-started gate ever resumed. The whole corpus
    (`plans/features/` in the template gate, `self/features/` in `self/gate.sh`) is added to
    `GATE_TREE_EXCLUDES` beside the gate's own outputs, as the named constant
    `GATE_FEATURES_DIR` in each. Option (b), tracked content plus untracked outside the
    corpus, was not taken: it would have made the sha depend on the index. Accepted
    consequence: a gate check that reads the corpus resumes across corpus edits
    (`check-plans.sh` validates it, and `run-batch.sh` runs that itself, not the gate). The
    template gate's body changed, so `TEMPLATE_VERSIONS` re-records its hash at version 3,
    which has not shipped on `main`. `gate-resume.sh` gained K11a-c (both gates) and R1-R4,
    which drive `run-plans.sh` on a level sentinel in a consuming-repo layout with
    `stamp_timing` live; R2/R3 and K11b failed before the fix with `c1 c2 c3 c4`. The
    scenario's `reset_runner_feature` clears `plans/gate-state` (a test fix made alongside
    the build, not an assertion change): otherwise the previous scenario's complete record
    for the same tree meant c3 never started.

## Slice B — the `gate` key

38. **`gate: "skipped"` also when the repo has no gate script** (not only `--no-gate`):
    no gate ran, and the key exists so "a feature started on an unverified base says so";
    `green` only when the gate ran here and was green. Two values, no third.
39. **`manifest.py init --gate green|skipped`**, written after `profile` in
    `FENCE_KEY_ORDER`, an unknown value refused (`KNOWN_GATE_RECORDS`); `report.py` prints
    `Gate: <value> — …` under the Profile line and `report.json` carries `gate`, both only
    when the fence has one. `check-plans.sh` gains no check (ruling 10 holds: 14 checks;
    `self/tests/check-plans.sh` 2f shows a fence with `gate` passes all 14).

## Slice B — §9 and the doctrine

40. **`sleep` is a member-level rewrite** (`sleeps()` in the per-member loop beside the
    `~` and `cd` shapes, `SLEEP_REWRITE_REASON`): bare or by path, anywhere on the line.
    It can only tighten — `command_allowed` never approved `sleep`, so every such line
    used to prompt — and it is named ahead of the mixed-sequence rewrite, since "run it in
    the background" is the lesson and "run `ls` alone" is not.
41. **AGENT_DIRECT.md's brief item 2 and procedure step 5 now agree**: the implementer runs
    the checks it touched; the whole gate is the coordinator's unless the brief names a
    short one; the brief ends at "commit and checkpoint, then stop". Item 2 names the cloud
    layout (the primary, on `branches[0]`). The new section "Long runs belong to the
    coordinator" and ORCHESTRATION.md's two new Rules carry §8's doctrine, `send_later`
    included as doctrine only.

## Existing assertions changed, and why

- `feature-lifecycle.sh` P2e and `self/tests/open-session.sh` O4: the version they pin moved
  (pr.sh 5 -> 6, open-session.sh 3 -> 4) because this feature changed those bodies.
- `sync-check.sh` 1d, 1f, 4b, 4d, 4g: the same pr.sh bump (`< 5` -> `< 6`).
- `feature-lifecycle.sh`'s stub `gh pr merge` recorded the origin head of `refs/heads/$3`;
  `forge.sh` passes the PR url there now, so the stub resolves a url to the branch checked
  out in its cwd (where pr.sh runs). X2e asserts the same fact as before.
- Every test that runs `feature-start.sh` or a `pr.sh --merge-request` now exports
  `AGENTTOOLING_PROFILE=local` and copies `env-profile.sh` into its fixture: without the
  first, this container's `CLAUDE_CODE_REMOTE=true` would send them down the cloud path.
  No assertion in them changed.
- `feature-lifecycle.sh` CB's first close now runs under `AGENTTOOLING_PROFILE=cloud`: the
  same assertions, now proving the cloud close (design §5's first bullet).
- Slice B: `sync-check.sh` 1c, 1e, 1f pin gate.sh 2 -> 3 and worktree-setup.sh 1 -> 2,
  because this feature changed those bodies (resume + environment.sh; environment.sh).
- Slice B: `hook-wiring.sh`'s complete-file fixtures (edit-only, no-ask, no-sandbox,
  complete, retired, sandbox-own, sandbox-off, enabled-flip) now carry the SessionStart
  entry too (`WIRED_HOOKS`): "complete" now includes it, and without it their
  "names X and nothing else" checks would see the new gap. "--self differs in the hook
  path and the ask rules and nothing else" now also drops the SessionStart entry before
  comparing, since `--self` deliberately writes none (ruling 29).
- Slice B: `cloud-start.sh`'s stub gate also writes the `GATE_RESUME` it was handed to
  `$GATE_RESUME_OUT` — a fixture change; no assertion moved.

## For slice B (done)

- Add the seeded `cloud-setup.sh` template (and `self/` copy, if any) to
  `CONFINEMENT_ALLOWED` in `self/profile-confinement.sh` if it reads the profile. — Done,
  with `environment.sh` (ruling 31); there is no self copy.
- `FENCE_KEY_ORDER` in `analysis/manifest.py` places `profile` after `base`; put `gate`
  beside it. `report.py`'s `Profile:` line is where a `Gate:` line would go. — Done
  (ruling 39).
