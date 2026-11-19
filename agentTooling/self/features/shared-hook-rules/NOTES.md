# shared-hook-rules — rulings

Raised by the owner (`self/BACKLOG.md`, URGENT, during `orchestration-records-in-repo`):
the PreToolUse hook can import only siblings in `hooks/`, so every rule it shares with
`analysis/` is written twice — and the shell a third time — and held equal by mirror tests
(`self/tests/orchestrator-role.sh` U3, `self/tests/orchestration-records-in-repo.sh` R10).
`orchestration-records-in-repo` had to change each copy to move a consumer's records. This
feature gives each shared rule one definition and deletes the mirrors.

Already single, and left where they are: the brief header (`hooks/brief_header.py`, which
`analysis/capture_planning.py` reaches by path) and the env profile (`hooks/env_profile.py`,
which `env-profile.sh` runs and the hook imports). They are the precedent ruling 1 follows.

## Coordinator rulings (before the build)

1. **The shared rules live in ONE new stdlib-only module, `hooks/shared_rules.py`; there is
   no `lib/` folder.** `hooks/` is the constrained side: the hook imports siblings and nothing
   else, so the module the hook reads has to sit beside it, and `analysis/` already reaches
   `hooks/` by path (`capture_planning.py`'s `HOOKS_DIR`, appended to `sys.path`). Two reasons
   against `lib/`: every hook call would gain a computed `sys.path` entry outside its own
   directory, and the record locations the role rule depends on would move out from under
   `wire-settings.py`'s `Edit(**/agentTooling/hooks/**)` ask rule — a file that decides who is
   an orchestrator would become editable without a human seeing it. Following the precedent of
   `brief_header.py` and `env_profile.py` also means one convention, not two.
2. **What moves in.** Every constant `hooks/*.py` (`allow-repo-commands.sh` included — it is
   Python) shares in meaning and value with `analysis/*.py` or a top-level `*.sh`. At least:
   the two record roots (`ORCHESTRATIONS_SELF_REL` / `_CONSUMER_REL`; `roots.py`'s
   `ORCHESTRATIONS_*_PARTS` and `orchestration-start.sh`'s copies), `RECORD_NAME`, `GIT_ENTRY`
   (and `orchestrator_role.py`'s duplicate `GIT_MARKER`), the fence keys and values `kind` /
   `coordinator` (`roots.ORCH_KIND_*`, `orchestration-start.sh`'s `COORDINATOR_KIND`),
   `session`, `features` and the orchestrator feature keys (`manifest.py`'s
   `ORCH_FEATURE_KEYS`, `roots.ORCH_FEATURES_KEY`), the ledger name (`orchestration-start.sh`'s
   `LEDGER_NAME`), the slug pattern (`orchestrator_role.LEDGER_SLUG_RE`, `routing.SLUG_RE`,
   `manifest.SLUG_RE`), and the two refusal texts the shell restates (`roots.py`'s
   `STANDALONE_REFUSAL`, `LEGACY_RECORD_REFUSAL`). The implementer audits for more and records
   each pair it finds below.
3. **`analysis/` keeps its own names, bound to the one value.** `roots.py` imports
   `shared_rules` (appending `HOOKS_DIR` as `capture_planning.py` does, so nothing in `hooks/`
   can shadow an analysis module) and binds `ORCH_KIND_KEY = shared_rules.KIND_KEY` etc., so
   `report.py`, `manifest.py` and `orchestration_capture.py` change nothing. A binding is a
   reference, not a restatement: there is one literal. The same for `orchestrator_role.py`'s
   names.
4. **Fast.** `shared_rules.py` is constants plus a tiny CLI: it imports `re` and `sys` at most,
   does no I/O and runs no subprocess at import, and the hook reaches it through the
   `orchestrator_role` sibling import it already does — no new path entry, no new process per
   Bash call.
5. **Fails safe, by caller.**
   - **The hook**: `orchestrator_role.py` imports `shared_rules` unguarded (they ship as one
     directory); the hook's existing `try: import orchestrator_role / except ImportError`
     therefore catches a missing or broken `shared_rules.py` and leaves the role rule silent —
     exactly what a `hooks/` copy missing `orchestrator_role.py` does today. Every other answer
     the hook gives is unchanged; it never crashes a Bash call. If the hook (or `wire-settings.py`)
     needs `shared_rules` directly, the import is guarded the same way.
   - **`analysis/`**: imports it unguarded. A missing module is a broken install, and an
     analysis tool that errors writes nothing — fail-closed.
   - **The shell** (`orchestration-start.sh`): reads each value through the module's CLI and,
     if it cannot, refuses (exit 1, `REFUSED_RC`) naming the module — never falls back to a
     literal, which would be the mirror again.
   - **`plan-runner-roots.sh`'s role reader** is unchanged: a crashing `orchestrator_role.py`
     prints nothing, which reads as "no record", as a missing module does today. Owner to look
     at (not changed here — "behaviour unchanged" is this feature's contract): that reader
     fails open on a broken install.
6. **The shell reads, rather than restates, where it is the same rule.** `orchestration-start.sh`
   takes its record roots, record name, `.git` entry, coordinator kind, ledger name and the two
   refusal texts from `python3 -B hooks/shared_rules.py <NAME>` (or one call printing several —
   implementer's choice, no `eval`). The shell `SLUG_PATTERN`s in the other lifecycle scripts
   are out of scope: they are a shell-to-shell rule the hook does not share, and reading them
   would add a python process to every script start; a backlog entry records it.
7. **`wire-settings.py` builds its record ask rules from the constants**, so
   `POLICY_ASK_RULES` stops spelling the two roots. The generated `.claude/settings.json` must
   come out byte-identical (the gate's settings `--check`).
8. **The mirror tests go, a single-definition test replaces them.** U3 in
   `self/tests/orchestrator-role.sh` and R10 in `self/tests/orchestration-records-in-repo.sh`
   are deleted (R10's behavioural checks that the refusal TEXT reaches the user stay — they
   test output, not equality of copies). A new `self/tests/shared-rules.sh`, registered in
   `self/gate.sh` and `self/tests/README.md`, asserts: every bound name in `roots.py`,
   `orchestrator_role.py`, `manifest.py`, `routing.py` and `wire-settings.py` IS the
   `shared_rules` object; no tracked `hooks/*.py`, `hooks/allow-repo-commands.sh`,
   `analysis/*.py` or top-level `*.sh` other than `shared_rules.py` assigns any of its literal
   values; `grep -rn 'MIRRORS\|MIRRORED'` over those comes back empty; and the fail-safe paths
   of ruling 5 (a fixture `hooks/` without `shared_rules.py`: the hook still approves a plain
   `ls` and does not crash; `orchestration-start.sh` refuses naming the module).
9. **The harness's `PROGRAM_RECORD_ROOT` (`harness/program-stages.sh`) stays** unless the audit
   shows it restates the current rule: it reads arms that may run an older agentTooling, so it
   names both the old and the new location by design (`orchestration-records-in-repo` ruling 6).
   The implementer confirms and records the outcome here.
10. **The record-fence regexes are not unified unless the behaviour is identical.** The role
    reads every fence line by line (`FENCE_OPEN_RE`/`FENCE_CLOSE_RE`); the data readers take the
    last fence with one DOTALL regex. If the audit shows they accept different inputs, they are
    two rules and stay, justified here.

## Rulings made in the build

11. **The CLI serves any upper-case string (or string tuple) constant of the module**, not a
    registry: `python3 -B hooks/shared_rules.py NAME...` prints each value on a line (a tuple
    space-joined) and exits 0, or prints nothing and exits 2 for an unknown name or none, so a
    caller never holds half an answer. No registry means a new shared constant is readable by
    the shell the moment it exists, and a test cannot drift from a list.
12. **`orchestration-start.sh` reads its nine values in ONE `python3 -B` call** (record roots,
    record name, `.git` entry, coordinator kind, ledger name, slug pattern, both refusal
    texts) into variables of the same names with `printf -v` — no `eval`. The count of lines
    read is the check, so a missing, broken or empty-printing module refuses (exit 1, naming
    `hooks/shared_rules.py`) with nothing written. The legacy refusal's `{slug}` placeholder
    is filled by bash substitution, so the text a user reads is byte-identical to before.
    This script's own `SLUG_PATTERN` moved too (it is read in the same call); the OTHER lifecycle
    scripts' `SLUG_PATTERN`s did not (ruling 6; backlog).
13. **`analysis/` reaches the module through `roots.py`**: `roots` appends `hooks/` to
    `sys.path` and imports `shared_rules`, and `manifest.py`, `routing.py`, `coordinator_check.py`
    and `orchestration_capture.py` take it with `from roots import shared_rules`, so there is one
    `sys.path` edit in `analysis/` and every analysis tool that needs a rule already imports
    `roots`. `roots.ORCHESTRATIONS_*_PARTS` are the shared roots split (`tuple(REL.split("/"))`);
    `OWN_RECORD_NOTE` is built from them; `roots.py`'s legacy-record read uses `RECORD_NAME`.
14. **The hook's `ORCHESTRATOR_SLUG_RE` is the shared pattern, guarded.** `allow-repo-commands.sh`
    imports `shared_rules` the guarded way; with no module the pattern is `(?!)`, which matches
    nothing, so an orchestrator's record tool is handed to the human instead of approved — the
    safe side, and unreachable in practice (the allowlist runs only for a session the role
    already named, which needs `shared_rules` through `orchestrator_role`).
15. **`wire-settings.py` imports `shared_rules` unguarded.** A guarded fallback would be a
    literal root, i.e. the mirror again, and a copy that cannot read the roots must stop rather
    than write a settings file that quietly asks for less (ruling 5's "needs it directly" clause,
    decided the fail-closed way). `POLICY_ASK_RULES` is spelled from the two roots; the
    generated bytes are unchanged (`hooks/wire-settings.py --self --check`).
16. **Ruling 9 confirmed.** `harness/program-stages.sh` names `plans/orchestrations` and the
    legacy `agentTooling/self/orchestrations` on purpose: it reads arms that may be pinned to an
    older agentTooling than the driver's, and the arm's layout, not this checkout's, decides.
    It is not the current rule restated, and it is not a top-level `*.sh`; it stays.
17. **Ruling 10 confirmed: the fence readers are two rules and stay.** The role reads LINES
    (`^```json[ \t]*$` to `^```[ \t]*$`, every fence); the data readers take the last match of
    ```` ```json\n(.*?)\n``` ```` (`manifest.FENCE_RE`; the hook's manifest reader uses
    `^```json\s*$`). They accept different inputs: a fence opened with trailing blanks
    (```` ```json ````) is a fence to the role and none to `FENCE_RE`; `FENCE_RE` is not
    anchored to a line start and closes at the first `\n``` ` even before more text on that
    line; the hook's reader also takes `\s` (a `\r`). Unifying them would change which files
    count as a role or as data, which this feature may not.

18. **The hook's guarded imports of `orchestrator_role` and `shared_rules` catch `Exception`, not
    only `ImportError`.** Ruling 5 says a *broken* module leaves the role rule silent; a
    `shared_rules.py` with a syntax error raises `SyntaxError` inside `orchestrator_role`'s
    import, which `except ImportError` would let crash the Bash call. Wider, never narrower:
    a missing module behaves as before.
19. **Merge with vendored-edit-ask (PR #142).** Main replaced the narrow consumer asks with the
    tree-wide `Edit(**/agentTooling/**)` and moved the two narrow ones to
    `RETIRED_EDIT_ASK_RULES`, which the merge removes by exact string. Rulings 7 and 15 now read:
    `POLICY_ASK_RULES` spells only the consumer root from `ORCHESTRATIONS_CONSUMER_REL` (the
    legacy root is under the tree-wide rule), and the retired
    `Edit(**/agentTooling/self/orchestrations/**)` is built from `ORCHESTRATIONS_SELF_REL` —
    byte-equal to the string once written, which `self/tests/shared-rules.sh` S2 pins, so no
    exception-table entry. `--self` and its generated bytes are unchanged.

### The audit: every pair `hooks/*.py` and `allow-repo-commands.sh` form with `analysis/*.py` or a top-level `*.sh`

Found by a scan of every module-level constant in `hooks/` against `analysis/` and the top-level
`*.sh` for the same value, then read for the same meaning. **Moved** (one definition in
`shared_rules.py`; each other file binds): the two record roots, `RECORD_NAME` (also
`coordinator_check.RECORD_NAME`, `orchestration_capture.MANIFEST_NAME`), `GIT_ENTRY` (and the
duplicate `GIT_MARKER`; `roots.GIT_ENTRY`; the shell's), `GITDIR_PREFIX` / `COMMONDIR_NAME`
(`roots.COMMONDIR_FILE`), `SESSION_KEY` (also `coordinator_check`), `KIND_KEY`,
`KIND_COORDINATOR` (`roots.ORCH_KIND_*`, the shell's `COORDINATOR_KIND`), `FEATURES_KEY`,
`FEATURE_REPO_KEY` (`roots.ORCH_FEATURES_KEY` / `ORCH_FEATURE_REPO_KEY`),
`ORCHESTRATOR_FEATURE_KEYS` (`manifest.COORDINATOR_REFUSED_FEATURE_KEYS`), `ORCH_FEATURE_KEYS`
(`manifest`), `LEDGER_NAME`, `SLUG_PATTERN` / `SLUG_RE` (`orchestrator_role.LEDGER_SLUG_RE`,
`routing.SLUG_RE`, `manifest.SLUG_RE`, the hook's `ORCHESTRATOR_SLUG_RE`, this shell's
`SLUG_PATTERN`), `LEGACY_RECORD_MOVE`, `LEGACY_RECORD_REFUSAL`, `STANDALONE_REFUSAL`;
`manifest.KNOWN_PROFILES` binds to `env_profile.PROFILE_LOCAL` / `PROFILE_CLOUD` (the profile
detector was already single; `manifest.py` held a copy of its two words) and
`manifest.ORCH_KEY_ORDER` spells its fence keys from the shared names.

**Left, and why** (each is in `self/BACKLOG.md` where it is real work; the test's exception
tables name the same pairs):

- *Same meaning, but the other side is a shell file or the hook may not depend on the module for
  an answer other than the role's* (ruling 5): the FEATURE manifest's name `README.md`
  (`allow-repo-commands.sh` `MANIFEST_NAME`, `routing.MANIFEST_NAME`, the shells'
  `STARTED_MANIFEST_NAME` / `MANIFEST_NAME`); the feature corpus roots `self/features` /
  `plans/features` (`allow-repo-commands.sh` `SELF_FEATURES_DIR` / `CONSUMER_FEATURES_DIR`,
  `orchestration-start.sh`'s labels, `update.sh`, `roots.features_root`); the build-script names
  (`BUILD_SCRIPTS`, `routing.FEATURE_START_SCRIPT`, `CLOSE_SCRIPT_NAME`, `REVIEW_RUNNER_NAME`);
  `AGENTTOOLING_HEADLESS` / `AGENTTOOLING_SCRATCH` (`plan-runner-lib.sh`); the `agentTooling`
  directory name (`VENDORED_DIR_DEFAULT`, `SELF_REPO_DISPLAY_NAME`); the profile words in
  `env-profile.sh` (`PROFILE_LOCAL` and friends, which restate `env_profile.py`'s); `--self`
  (`ORCHESTRATOR_SELF_FLAG`, `coordinator_check.SELF_ARG`, `capture_planning.SELF_FLAG_WORD`).
- *Same spelling, different meaning, nothing to share*: `.git` as a remote URL suffix
  (`capture_planning`, `forge.sh`, `update.sh`, `plan-runner-roots.sh`) and as git's entry in
  `wire-settings.py`'s `GIT_MARKER` and the hook's `GIT_DIR_ENTRY` path reads (a fact of git);
  `Bash` (`MATCHED_TOOL`, `HOOK_MATCHERS`, `routing.BASH_TOOL_NAME`: Claude Code's tool name);
  `origin`, `main`, `HEAD`, `refs/remotes/` (git's names); `.claude` (`SETTINGS_REL` against
  `PROJECTS_REL`: different directories); `capture_planning.SEEN_FEATURES_KEY` and `SEEN_REPO_KEY`
  (the claims-seen ledger's keys); `branch` in `policy.GIT_BRANCH` and `START_LOCK_BRANCH_KEY`.
