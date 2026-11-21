# hooks

Claude Code hook scripts, vendored with the rest of `agentTooling/`. A hook does nothing
until a settings file names it; `sync-plans.sh` does that wiring, so a repo gets it at
install and after every `subtree pull`. All six files are Python 3, standard library
only.

- `allow-repo-commands.sh` — `PreToolUse` hook for the `Bash` tool, and for the `Agent`
  tool: the orchestrator role ("The orchestrator role") and the brief header ("The brief
  header") — it denies or prints nothing there, never an allow. Reads the hook payload
  `{ tool_name, cwd, tool_input{command} }` on stdin and prints
  `{ hookSpecificOutput: { hookEventName, permissionDecision, permissionDecisionReason } }`
  with `permissionDecision: "allow"` when the whole command is confined to the project
  root and built only from allowlisted read/test programs and the harness's own read-only
  entry points. Its analysis answers one of three verdicts — ALLOW, **REWRITE** (it could
  not read the command and can name the rewrite) or **ASK** (it read the command and
  cannot vouch for it) — and prints nothing for the last, so the normal permission flow
  runs over a command it has read. It emits `permissionDecision: "deny"` for three shapes
  it reads and refuses outright — a command chaining `cd` or `pushd` with any other
  command, with a reason naming the rewrite; a git command that moves a ref or rewrites
  history, with a reason naming `LIFECYCLE.md` rule 2, `feature-start.sh` and
  `feature-close.sh` — `GIT_DENY_REASON` locally, the cloud reason in a cloud container,
  where the table's two cloud-only shapes are denied too, and a push to `main` in both
  profiles (`GIT_PUSH_PROTECTED_DENY_REASON` locally) ("The git shape, by profile") — and
  where a plain `git push [-u] origin <branch>` of the started feature's own branch, run
  from the project root with no global option and nothing else on the line, is the one
  write it approves (`own_push_allowed`);
  an assignment at command position whose own `$NAME` is used later on
  the same line, with a reason saying to inline the literal — and for every REWRITE, whose
  reason is the rewrite: a heredoc into an interpreter, code as a string, a pipe into one,
  a program or a path decided at run time, a one-line compound, a line that does not
  tokenize (which names the quote instead), a `$NAME` the shell expands, a `~`, a brace
  group the expansion refuses, a `..` path component, a bare or relative `cd`, a line
  break outside a quote or a heredoc, a sequence mixing approved reads with a command
  only the human can judge, a `sleep` anywhere on the line (nobody polls: run the
  command in the background and wait for its notification — `ORCHESTRATION.md`; the
  member's program is `SLEEP_PROGRAM`, the reason `SLEEP_REWRITE_REASON`), and a file
  authored through the shell — `echo`/`printf`
  redirected to a path, `cat`/`tee` fed literally with output to a path, `sed -i` — whose
  reason names the Write and Edit tools and is judged ahead of the opaque shapes. Its git
  deny reads `policy.py`'s constants and nothing of its own, and the profile from
  `env_profile.py`, imported in-process (guarded: a missing module reads as local); it
  spells neither profile variable itself, and `self/profile-confinement.sh` keeps it that
  way. Depends on `git` on `PATH` only for the cloud path (a missing or failing `git`
  there leaves today's answer), and on the manifest fence's `branches[0]` under
  `<features dir>/<slug>/README.md` to name a started feature.
  After `OPAQUE_REWRITE_ATTEMPTS` opaque commands in one session it emits
  `permissionDecision: "ask"` instead, keyed on the payload's `session_id` and `agent_id`
  through a state file under `$TMPDIR`; under `AGENTTOOLING_HEADLESS` it prints nothing
  there. `AGENTTOOLING_SCRATCH` names the one directory outside the root it approves a
  script from. Every approval rule is a refusal and the default is to
  refuse: a token it does not understand makes the whole command fall through to the prompt.
- `policy.py` — the git policy as **data**, and the one file both scripts above and below
  read it from. Constants: `GIT_PROGRAM`; `READ_ONLY` / `MUTATING` (how an entry is
  marked); `GIT_ALWAYS_MUTATING` (`clean`, `rebase`); `GIT_STASH` with
  `GIT_STASH_SUBCOMMANDS` (`list`, `show` READ_ONLY; `push`, `save`, `pop`, `apply`,
  `drop`, `clear`, `branch`, `create`, `store` MUTATING); `GIT_PUSH` with
  `GIT_PUSH_FORCE_FLAGS` and `GIT_PUSH_FORCE_LEASE_FLAG`; `GIT_RESET` with
  `GIT_RESET_MUTATING_FLAG`; `GIT_WORKTREE` with `GIT_WORKTREE_SUBCOMMANDS`
  (`list` READ_ONLY; `add`, `remove`, `prune`, `move`, `lock`, `unlock`, `repair`
  MUTATING); `GIT_CHECKOUT` / `GIT_CHECKOUT_BRANCH_FLAGS`; `GIT_SWITCH` /
  `GIT_SWITCH_BRANCH_FLAGS`; `GIT_BRANCH` / `GIT_BRANCH_MUTATING_FLAGS` /
  `GIT_BRANCH_LIST_FLAGS`; the **cloud-only entries** — `GIT_CLOUD_ONLY`
  (`{switch: CLOUD_SWITCH_AWAY, checkout: CLOUD_SWITCH_AWAY, push: CLOUD_PUSH_ELSEWHERE}`),
  `GIT_SWITCH_DETACH_FLAGS` (`--detach`, `-d`), `GIT_CHECKOUT_DETACH_FLAGS` (`--detach`),
  `GIT_ORPHAN_FLAG`, `GIT_PREVIOUS_BRANCH` (`-`), `GIT_PUSH_EVERY_REF_FLAGS` (`--all`,
  `--branches`, `--mirror`, `--tags`) and `GIT_PUSH_DELETE_FLAGS` (`--delete`, `-d`,
  `--prune`), **hook-only**: none of them reaches `denied_git_commands()` or
  `bash_deny_rules()`, since no command prefix can say "a branch other than the current
  one"; the **both-profile hook-only entry** — `GIT_PROTECTED_BRANCH` (`main`, one literal:
  not `master`, not a manifest's `base`), `PUSH_TO_PROTECTED` and `GIT_HOOK_ONLY`
  (`{push: PUSH_TO_PROTECTED}`), likewise never rendered as a rule, since a prefix cannot
  tell `main` from `main-x`; `BASH_RULE_TEMPLATE` (a prefix rule) and
  `BASH_EXACT_RULE_TEMPLATE` (an exact one); `GIT_BARE_DENIED` (`stash`, denied bare by
  an exact rule); and `RETIRED_DENIED_GIT_COMMANDS` (`git stash`, whose old prefix rule
  denied `git stash list` too). Functions: `cloud_only_rule(subcommand)` (the
  cloud-only entry a subcommand falls under, or None), `hook_only_rule(subcommand)` (the
  both-profile entry, or None), `worktree_read_only()`, `worktree_mutating()`,
  `stash_read_only()`, `stash_mutating()`, `denied_git_commands()`, `bash_deny_rules()`,
  which renders the `permissions.deny` twin in the fixed order below, and
  `retired_bash_deny_rules()`, what a merge removes. Every constant a rule is
  rendered from is an **ordered tuple**, not a frozenset: the rendering is compared byte
  for byte with the committed settings file, and a set has no order to compare.
  Both scripts import it by **sibling path**
  (`sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))`) with
  `sys.dont_write_bytecode = True`, because neither runs from a fixed directory — the
  hook is invoked by Claude Code from wherever the session sits, the writer with a
  `--repo` that is somebody else's checkout — and because that directory is inside the
  repo being guarded, where a `__pycache__` has no business. It is on the gate's
  `py_compile hooks` line and asserted by `self/tests/policy-table.sh`.
- `env_profile.py` — the **profile detector**: where agentTooling is running, `local` or
  `cloud` (`self/DESIGN-2026-10-05-cloud-execution.md` §1,
  `self/features/review-base-and-cloud-hook/`). The one place the rule lives and the only
  code that spells `AGENTTOOLING_PROFILE` or `CLAUDE_CODE_REMOTE` besides `../env-profile.sh`
  (which exports the answer), the adapters and the tests — `self/profile-confinement.sh`
  allowlists it, and deliberately not the hook. The rule: an explicit
  `AGENTTOOLING_PROFILE` wins (neither `local` nor `cloud` is an error); else
  `CLAUDE_CODE_REMOTE=true` → `cloud`; else `local`. `detect(environ=None)` returns
  `Detection { profile, decided_by }` — `decided_by` one of `AGENTTOOLING_PROFILE`,
  `CLAUDE_CODE_REMOTE`, `default` — over the mapping given or the process environment,
  and raises `InvalidProfile` (a `ValueError`, `.value` the bad value) for an invalid
  override; `is_cloud(environ=None)` is the yes/no, an invalid override reading as not
  cloud. Constants: `PROFILE_ENV`, `REMOTE_ENV`, `PROFILE_LOCAL`, `PROFILE_CLOUD`,
  `PROFILES`, `REMOTE_ON`, `DECIDED_BY_OVERRIDE` / `_REMOTE` / `_DEFAULT`,
  `INVALID_PROFILE_RC` (2). Two ways in: the hook **imports** it as a sibling, like
  `policy.py` — no process per Bash call; `../env-profile.sh` **runs** it once when
  sourced, `python3 -B <agentTooling>/hooks/env_profile.py`, reading two stdout lines,
  the profile then the decider (for an invalid override: the raw value and
  `AGENTTOOLING_PROFILE`, exit 2, the reason on stderr). Not `profile.py`: that would
  shadow the standard library's module. No I/O beyond the environment and, run as a
  script, those two lines. On the gate's `py_compile hooks` line; driven by
  `self/tests/env-profile.sh` (M1–M8) and, through the hook, `self/tests/hook-cloud-profile.sh`.
- `orchestrator_role.py` — the **orchestrator-role rule**, written once
  (`self/features/orchestrator-role-guard/`). `record_for_session(tooling_dir, session_id)`
  returns the path of the `<tooling_dir>/self/orchestrations/<slug>/README.md` or the
  consuming repo's `plans/orchestrations/<slug>/README.md` (`record_roots(tooling_dir)`, built
  from `record_bases(tooling_dir)`'s `(base, rel)` pairs: self first, then
  `os.path.dirname(tooling_dir)` + `plans/orchestrations` — the parent's only from a vendored
  copy: a `tooling_dir` holding `.git` (`GIT_ENTRY`) is agentTooling's standalone checkout,
  whose parent is no repository, and its role never comes from there; sorted within a root,
  so a legacy record a consumer still has under its vendored `self/orchestrations/` keeps its
  role until it is moved) ANY of whose
  ```` ```json ```` fences has `"session"` equal to the id (exact string compare) and is a
  role (`names_role`; `is_role(fence)`: anything but `"kind": "coordinator"`, or a
  coordinator fence whose `features[]` carries a non-null `session`/`branch` —
  `orchestrator_shaped`, constants `FEATURES_KEY` / `ORCHESTRATOR_FEATURE_KEYS`, which are
  `shared_rules`' and `analysis/manifest.py`'s `COORDINATOR_REFUSED_FEATURE_KEYS` too;
  `../self/features/hook-role-hardening/`), else — when no record names the session — the
  record a line of the checkout's LEDGER points at (`<git common dir>/agenttooling-orchestrators`,
  `<session> <slug>` per line, appended by `../orchestration-start.sh` for every
  orchestrator record and never a coordinator one; `LEDGER_NAME`, `ledger_lookup`,
  `git_common_dirs`, which finds the common dirs as git does but without running git; the
  ledger names a slug, not a root, so `ledger_record_path` names the first root holding that
  folder, else the last root; the Edit
  tool cannot write under `.git/`, so a record rewritten in place or deleted keeps the role;
  read line by line with bad bytes replaced; a `.git` that cannot be resolved, or a ledger
  that cannot be read, FAILS CLOSED as `LEDGER_UNREADABLE` with `LEDGER_UNREADABLE_REASON`;
  also read when a records root cannot be listed; the ledgers of EVERY enclosing
  checkout are read, and a `.git` directory without `HEAD` is unresolvable, round 2 N12) —
  and between the two, each record AS FIRST COMMITTED (`committed_role_record` /
  `added_records(base, rel)`: ONE `git -C <base> log -m --relative --diff-filter=A -p -- <rel>`
  per root — `self/orchestrations/` from the tooling directory and, from a vendored copy,
  `plans/orchestrations/` from the consuming repo's — each under `HISTORY_DEADLINE_SECONDS`,
  merges included, a shallow clone's boundary commit never read as an add — round 3, R5/R6),
  so the role reaches every clone and a working-tree edit or deletion does not drop it; git
  unavailable or past the deadline is unreadable history, a checkout with no commit yet has
  none; every source is asked and one that names the session wins, `LEDGER_UNREADABLE` only
  when none does (R4) — else `None` — a
  **coordinator record** (`../self/features/coordinator-cost-records/`) names its session
  for cost only, because a coordinator's Agent delegates send its `session_id` in their
  payloads and inherit its `$CLAUDE_CODE_SESSION_ID`, so a role there would refuse every
  feature they build; a missing directory, an unreadable file and an unparseable fence are skipped,
  never an exception; `refusal_reason(record_path)` renders the one reason from
  `REASON_TEMPLATE` (the slug, the record path and `IMPLEMENTER_BRIEF`,
  `templates/plans/ORCHESTRATOR_BRIEF.md`). CLI: `python3 -B hooks/orchestrator_role.py
  [--reason] -- <tooling-dir> <session-id>` (after `--` every word is positional, so an id
  starting with a dash is never the flag; the old `<dir> <id> [--reason]` form still works)
  prints the path (with `--reason`, the reason) or
  nothing and exits 0 always; an empty id prints nothing. Constants: `ORCHESTRATIONS_SELF_REL`
  (`self/orchestrations`), `ORCHESTRATIONS_CONSUMER_REL` (`plans/orchestrations`),
  `RECORD_NAME`, `GIT_ENTRY` (and `GIT_MARKER`), `GITDIR_PREFIX`, `COMMONDIR_NAME`,
  `SESSION_KEY`, `KIND_KEY` / `KIND_COORDINATOR`, `FEATURES_KEY`,
  `ORCHESTRATOR_FEATURE_KEYS`, `LEDGER_NAME` and `LEDGER_SLUG_RE` — every one **bound to
  `shared_rules.py`** (below), the one definition `analysis/roots.py` and
  `../orchestration-start.sh` read too, so none is restated here — and, its own, `FENCE_OPEN_RE` /
  `FENCE_CLOSE_RE` (line by line, not the data readers' regexes: the two accept different
  inputs, `self/features/shared-hook-rules/NOTES.md` ruling 17), `IMPLEMENTER_BRIEF`,
  `REASON_TEMPLATE`. It imports `shared_rules` **unguarded** (the two ship as one directory).
  Two readers: the hook **imports** it as a sibling, guarded like `env_profile.py` (a missing
  module — or a missing or broken `shared_rules.py`, whose import fails inside it — leaves the
  rule silent); `../plan-runner-roots.sh` **runs** it (`orchestrator_record_for_session`,
  `refuse_orchestrator_session`), which every lifecycle script that builds calls before its
  first write, and which **refuses the build, naming the module**, when either file is
  missing or the module exits non-zero (a failed import, or `RULE_FAILED` from a rule that
  raised): a broken install is never "no record" (`self/features/hook-silent-allow-sweep/`,
  item 7). Stdlib only; on the gate's `py_compile hooks` line; driven by
  `self/tests/orchestrator-role.sh` (U1) and `self/tests/hook-orchestrator-role.sh`.
- `shared_rules.py` — the **rules the hook shares with `analysis/` and the lifecycle
  scripts**, each written once (`self/features/shared-hook-rules/`; the hook may import only
  siblings in `hooks/`, so a rule it shared used to be written twice or three times and held
  equal by a mirror test). Constants: `ORCHESTRATIONS_SELF_REL` / `ORCHESTRATIONS_CONSUMER_REL`
  (the two record roots), `RECORD_NAME`, `GIT_ENTRY`, `GITDIR_PREFIX`, `COMMONDIR_NAME`, the
  record fence's keys (`SESSION_KEY`, `KIND_KEY`, `KIND_COORDINATOR`, `FEATURES_KEY`,
  `FEATURE_REPO_KEY`, `FEATURE_BRANCH_KEY`, `ORCHESTRATOR_FEATURE_KEYS` =
  `(session, branch)`, `ORCH_FEATURE_KEYS` = the six of a `features[]` entry), `LEDGER_NAME`,
  `SLUG_PATTERN` / `SLUG_RE`, and the refusal texts `LEGACY_RECORD_MOVE`,
  `LEGACY_RECORD_REFUSAL` and `STANDALONE_REFUSAL` (with `{slug}` placeholders), and
  `ROOTS_CLI_GO_AHEAD` (`ok`: the one line `../analysis/roots.py start-refusal` and
  `self-write` print on the go-ahead, bound there as `CLI_GO_AHEAD`; `../orchestration-start.sh`
  goes on only on exit 0 with exactly that line, so an emptied or stubbed `roots.py` refuses,
  `self/features/orchestrator-move-length-cap/`). Readers:
  `orchestrator_role.py` (imports it, unguarded; so a hooks/ without it leaves the role rule
  silent through the hook's own guarded import, exactly as one without `orchestrator_role.py`
  does, and every other answer is unchanged); `../analysis/roots.py` (appends this directory
  to `sys.path` and imports it, **unguarded** — a missing module is a broken install and an
  analysis tool that errors writes nothing; `manifest.py`, `routing.py`,
  `coordinator_check.py` and `orchestration_capture.py` take it from `roots`);
  `wire-settings.py` (imports it unguarded: it spells the records `ask` rule from the consumer
  root and the retired legacy-records ask it removes from the self root, and a copy that
  cannot read them must stop, not write a settings file that asks for less); `allow-repo-commands.sh` (guarded, for `ORCHESTRATOR_SLUG_RE` only: with no module the
  pattern matches nothing, so an orchestrator's record tool is handed to the human);
  `../orchestration-start.sh` runs the CLI `python3 -B hooks/shared_rules.py NAME [NAME ...]`
  — one value per line in the order asked, a tuple space-joined; exit 0, or exit 2 with nothing
  on stdout for an unknown name or none — and **refuses, naming the module, when it cannot
  read them; it never falls back to a literal**. Stdlib only (`re`, `sys`); nothing runs at
  import, so the hook's one extra import costs a parse. A value is here when two files other
  than this one hold it with the same meaning; the pairs left on purpose are listed in
  `self/features/shared-hook-rules/NOTES.md`. On the gate's `py_compile hooks` line; driven by
  `self/tests/shared-rules.sh`.
- `brief_header.py` — the **brief header**, written once (`../self/features/delegate-cost-claims/`;
  the format is specified in `../analysis/README.md` → "The brief header"): the first
  non-empty line of every delegate brief is `feature: <repo>/<slug>` or `feature: none —
  <reason>`. `parse(text)` returns `("feature", repo, slug)`, `("none", reason)` or `None`;
  `feature_of(text)` the `(repo, slug)` pair or `None`; `feature_lines(text)` every pair a
  stripped line of the text names, for the ambiguity check; `first_line(text)`. Constants:
  `HEADER_PREFIX`, `FEATURE_HEADER_RE`, `NONE_HEADER_RE`, `REQUIRED_FEATURE_HEADER`,
  `REQUIRED_NONE_HEADER`, `KIND_FEATURE`, `KIND_NONE`. Two readers: the hook **imports** it
  as a sibling, guarded like `orchestrator_role.py` (a missing module leaves the
  header rule silent); `../analysis/capture_planning.py` **imports it by path**
  (`<its dir>/../hooks`, appended to `sys.path`, unguarded — every copy of agentTooling
  ships both directories), for the unclaimed listing's "brief names" column, the
  auto-claim and the close's claim check. Stdlib only; no I/O; on the gate's `py_compile
  hooks` line; driven by `self/tests/delegate-cost-claims.sh` (B1) and, through the hook,
  `self/tests/hook-brief-header.sh`.
- `wire-settings.py` — `wire-settings.py [--self] --repo <dir> (--check | --write)`.
  Maintains the `PreToolUse` entries for `allow-repo-commands.sh` — one per matcher in
  `HOOK_MATCHERS` (`Bash`, `Agent`; an ordered tuple, since `--self` is compared byte for
  byte), added when no entry with that matcher references the script, so a repo wired
  before the `Agent` entry gets that one appended (`no Agent hook entry`) and keeps its own
  `Bash` entry — the **`SessionStart`
  entry** running agentTooling's own `../session-start.sh` —
  `${CLAUDE_PROJECT_DIR}/agentTooling/session-start.sh` (`SESSION_MARKER`,
  `SESSION_COMMAND`, `SESSION_EVENT`; no matcher, so it runs on every start, resume and
  compaction; **no profile guard in the entry**: the script asks `env-profile.sh` itself —
  the orientation in every profile, the repo's `plans/cloud-setup.sh` in the cloud only —
  so this file spells no profile variable; recognised by the script's name in any
  SessionStart command, so a repo's customised entry is kept and never doubled, and a
  repo's own other SessionStart hooks stay first; a SessionStart that is not a list is
  `INVALID`; under `--self` the guarded `SELF_SESSION_COMMAND`, `test ! -f
  "${CLAUDE_PROJECT_DIR}/session-start.sh" || "${CLAUDE_PROJECT_DIR}/session-start.sh"
  --self`), the `Edit` and `Bash`
  deny rules, the `hooks/` **ask** rule (and, for a consuming repo, the
  orchestration-records one) and the OS **`sandbox` block** (below, "The
  sandbox block": `SANDBOX_ENABLED` — off today — `SANDBOX_OWNED_SETTINGS`,
  `SANDBOX_DENY_READ`, `SANDBOX_ALLOWED_DOMAINS`) in `<dir>/.claude/settings.json`, and removes
  any `policy.retired_bash_deny_rules()` it finds there, and any SessionStart hook whose
  command is one of `RETIRED_SESSION_COMMANDS` — exactly
  `${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh`, the entry it wrote before
  `session-start.sh` existed, which would now run that step twice — dropping the entry
  once it holds no hook (a repo's own spelling of a `cloud-setup.sh` hook is not touched). The Bash
  rules are `policy.bash_deny_rules()`, never a list of its own. Prints one
  `status<TAB>message` line for the
  caller to format and exits 0 when nothing needs attention, 1 otherwise. Statuses:
  `in-sync`, `missing`, `UNWIRED`, `INVALID` for `--check`; `created`, `wired`, `kept`,
  `INVALID` for `--write`. `--self` works on agentTooling's own checkout instead of a
  consuming repo's, and differs in more than the spelling: its one file,
  `<dir>/.claude/settings.json`, is wholly **generated** and **tracked**
  (`self/features/self-cloud-bootstrap/`), its `PreToolUse` command the guarded
  `SELF_HOOK_COMMAND`, `test ! -f "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh" ||
  "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"` — a silent exit 0 where the
  script is absent, the script itself (reading the payload the shell hands on) where it
  is not — its `SessionStart` command the guarded `--self` one above, and no
  `settings.local.json` written. `--check` is
  a byte comparison against a fresh write (`INVALID` is a merge status and never reached
  there): `in-sync`, `missing` on an absent file, `UNWIRED` on a drifted one, the message
  naming where it first differs and the exact command that regenerates, `python3 -B
  <abs>/hooks/wire-settings.py --self --repo <abs root> --write`. `--write` restores the
  bytes and reports `created`, `wired` or `kept`. Under `--self` a **vendored** `--repo` —
  no `.git` of its own and one in an ancestor — is compared the same way, the shipped
  copy against the generator's bytes, but `--write` writes nothing there, so a mismatch
  is reported in both modes with the fix **upstream** (`VENDORED_FIX_HINT`: regenerate in
  a standalone checkout, commit, pull) and no local command. Called by `sync-plans.sh`
  (without `--self`); with `--self`, by hand (`--write`, then commit) and by
  `self/gate.sh` (`--check`); tested by `self/tests/hook-wiring.sh` and
  `self/tests/self-settings.sh` (which also runs the guarded command as Claude Code does,
  in each layout). Depends on Claude Code setting `${CLAUDE_PROJECT_DIR}` to the launch
  directory for hook processes, and on a hook inheriting the payload on stdin through
  `sh -c`.

## Why `allow-repo-commands.sh` exists

`permissions.blockReadsOutsideWorkingDirectories` refuses any command whose paths resolve
at run time. That is every `cd X && cmd` chain — including `cd X && ls`, and including
commands an allow rule already covers, since the block is checked before rule matching.
`CONVENTIONS.md` § Shell commands tells agents not to write that shape, but nothing else
enforces the rule, and every miss costs the human a prompt while teaching the model
nothing. So the hook answers a `cd X && cmd` chain with a deny whose reason is the fix,
not with an approval, and approves the rewritten, unchained commands without turning the
fence off.

## The three outcomes

The approval analysis answers a **verdict**, not a bool
(`../self/DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1). Before that, "I could not read
this" and "I read it and it writes" both collapsed into the same silence: the human paid
an approval for each and the model learned from neither.

| Verdict | What it means | What the hook prints |
|---|---|---|
| **ALLOW** | every subcommand read-only and confined to the project root | `permissionDecision: "allow"` |
| **REWRITE** | the analysis could not read the command, and a rewrite exists | `permissionDecision: "deny"`, the reason being the rewrite — and `"ask"` after `OPAQUE_REWRITE_ATTEMPTS` of them in one session |
| **ASK** | the analysis read it and cannot vouch for it: a write (a captured output, a copy, a move — a file authored in the command is a REWRITE), an unknown program, a path outside the root, an environment prefix, a whole-argument `$(…)` | nothing, so the settings' own rules and then the human decide |

Precedence on a line: any REWRITE member makes the line REWRITE — the human is never
handed a line no reader here could split — else any ASK member makes it ASK, else ALLOW.
The three shape denies below run first and are unchanged.

**ALLOW is `command_allowed`'s answer and nothing else.** The verdict layer sits on top
of that oracle rather than replacing it, and is reached only once it has declined, so it
can turn a silent prompt into a deny that names the fix and can never turn a prompt into
an approval. Re-deriving approval from per-member verdicts would widen it — `ls ;; ls`
has two approved members and a separator nothing here recognises — and so would dropping
the `UNANALYSABLE` refusal in favour of the per-shape tests: `ls\nls`, `cat ../absent` and
`git diff main...HEAD` would all be approved. That tuple therefore stays exactly where it
was, and what the design replaced is its *judgement*, not its refusal.

**No `ask` decision is ever emitted for the ASK class**, only for the escalation. An
explicit `ask` would override the `permissions.allow` rules a human wrote, and the prompt
already shows a command this hook has read.

### The chained `cd`

A `cd` or `pushd` at command position alongside any other command, where commands are
separated by `&&`, `||`, `;`, `|`, `&`, a line break, or a `(` subshell. The reason tells
the model to run `cd <absolute path>` as its own call, or to name every path absolutely.

A `$(…)` command substitution is its own scope, quoted or not: nothing inside it counts
as a command of the outer line, and the word after its `)` is read where the `$(` left
off. A `cd` in there moves no path the outer command resolves — `x=$(cd dir && pwd)` is
the usual way to make a path absolute — so `x=$(cd dir && pwd)` and
`x="$(cd dir && pwd)"` are both left alone, while `x=$(pwd) && cd dir` is still a chain.

The check runs before, and independently of, the approval analysis, and it needs neither
`CLAUDE_PROJECT_DIR` nor `cwd`: the shape is wrong wherever it runs. It deliberately does
not deny a standalone `cd`; `cd` as an argument (`echo cd`, `find . -name cd`) or inside
quotes; a redirect target; a comment or a heredoc body (neither is a command and neither is
read — but what FOLLOWS a body is, `ls;<<EOF cat⏎x⏎EOF⏎cd /tmp && ls` being a chain; see
"Where a heredoc's body ends" below); a heredoc whose body cannot be placed; any command
`never_judged` holds back; or a command that does not tokenize (an unbalanced quote). Those
fall through to the approval analysis.

**Where a heredoc's body ends (`heredoc_body_span`).** One function says where a body
ends, and every reader asks it (hook-audit-gaps, B1 and F1). Bash ends a heredoc at the
first line holding the delimiter and nothing else (`<<-` strips leading tabs from that line
first); `EOF)` is body text to the main parser. With an **unquoted** delimiter it first
joins each body line that ends in a line continuation — an odd run of backslashes — to the
next one, and only then looks for that line: `EO\⏎F`, `E\⏎O\⏎F`, `EOF\⏎` and an empty line,
and `⇥EO\⏎F` under `<<-` each END the body, and `x\⏎EOF` does not; with a quoted delimiter
it joins nothing. Until round 3 the span compared the lines as written, and each of those
hid the commands after it (`self/features/hook-audit-gaps/escalations/02-audit-opus.md`,
R2-1); the caller now says which runs of backslashes join (`joins`: `HEREDOC_JOIN_NEVER`
for a quoted delimiter, `HEREDOC_JOIN_ODD` for an unquoted one, `HEREDOC_JOIN_BACKTICK`
below). Inside a `$(…)`, moreover, bash 5.2 ends a heredoc
at a **run-on line** — a body line that begins with the delimiter and goes on — whenever a
`)` follows on that line, and runs the rest of it: `EOF)` and `EOF;…)`, and just as much
`EOF )`, `EOF⇥)`, `EOFS)`, `EOF x)`, `EOFxyz ; true)` and `EOF'q')` (round 1 took only an
operator character after the delimiter for a run-on, and each of the others hid a command:
`self/features/hook-audit-gaps/escalations/01-audit-opus.md`, E1). Inside a backtick
substitution the body ends at the closing backtick, whatever its line holds. With no
terminator line at all bash runs to the end of the input. So the span is
placed only at a line that is the delimiter alone; a line that begins with the delimiter
and goes on — what follows it is not asked — or, after a backtick, a line holding a
backtick, or no terminator, leaves the body **unplaced** for a caller that
says nothing more: the whole-argument readers (`heredoc_argument_at`, used by the
orchestrator allowlist and the build-script judge) then do not take the text as a message at
all, so the orchestrator allowlist denies it with the role reason and the build-script
judge reads it as text. Such a line is the plain body line it looks like only to the main
parser — a heredoc with no substitution before it.

**What the deny side reads (`judged_texts`).** `comment_and_heredoc_free` walks the line
once and returns it with its comments and placed bodies removed — the operator and its
delimiter word stay — so a command after a body is read whichever way the operator is
spelled (`true;<<EOF cat`, `&<<`, `|<<`, `&&<<`, `(<<`, a plain `cat <<EOF`, which was a
prompt before hook-audit-gaps). `command_words` — the git, assignment and build-script
denies — reads every text `judged_texts` returns, and a deny is owed when ANY of them holds
one; `chains_chdir` reads the first walk alone and judges nothing it cannot place.

**One rule decides what the walk may hide** (round 2;
`self/features/hook-audit-gaps/NOTES.md`, coordinator ruling 7):
wherever a stretch of text would be hidden from the deny side — a comment, a heredoc body,
a deleted continuation — and bash could read it differently, BOTH readings are judged and
the line is denied if either holds a deny. Text is hidden only where the reading is
certain. Round 1 emulated bash more finely at each such place instead, and each emulation
had an edge (E1, E2, E3 of its audit); this rule has costs, listed below, and no edges of
that kind. The walk reads a heredoc, a comment and a continuation so:

- **Outside a substitution, `EOF)` is body.** A heredoc with no substitution opener (`$(`,
  `<(`, `>(`, a backtick) anywhere before its operator is the main parser's, and is placed
  at its terminator line. After one, a run-on line is read EVERY way — not placed; as body
  text (an older bash); and as the end of the body, the rest of the line a command (bash
  5.2), at the first run-on line and at each later one in turn, since the body ends at the
  first one a `)` follows on (`EOFS⏎EOF git push …)` ends at the second); and, after a
  backtick, at the line's backtick — so
  `echo $(cat <<EOF⏎it's⏎EOF) ; git push --force origin x⏎EOF` is denied whatever the body
  holds, and so is the audit's B1 shape with a `"` in its message. A body with more than
  `MAX_RUN_ON_LINES` run-on lines is not read finely (below).
- **No body is placed where bash may not read one there.** A `<<` after an arithmetic opener
  (`((`, `$[`), inside a subscript (`a[1<<2]=5`) or inside `${…}` may be a shift; a
  delimiter holding a backtick, `$(`, `$"`, `$'` or a carriage return is one bash reads
  differently (`<<EOF\r` ends at a line `EOF\r`); and a substitution that opens between the
  operator and the end of its line is read through before any body (`cat <<EOF $(echo
  a⏎cmd⏎EOF⏎)` runs `cmd`). When no reading places a body, the line is read with only its
  comments removed, its body lines as commands: a deny may then fire on text bash would have
  taken for a body, which is the cost of never hiding one (`cat <<EOF | tee "$(mktemp)"` has
  its body read that way).
- **A whole-argument `"$(cat <<'EOF' … EOF⏎)"`** with a quoted delimiter and nothing
  substituted before it is one word whatever quotes its body holds (it stands as `""`), so
  the command after a commit message holding an odd `"` is read. An unquoted delimiter is
  not stood in: its body expands. A head that is NOT stood in — an unquoted delimiter, a
  `)"` that does not follow the terminator, a substitution before it — is read twice
  (round 3): as the one quoted word the plain reading takes it for, and **opened**, its `"`
  and the next `"` dropped, so that its heredoc is placed like any other and what follows
  the body is read as commands. `echo "$(cat <<EOF⏎EO\⏎F⏎git push --force origin y⏎EOF⏎)"`
  is denied that way (`escalations/02-review-opus.md`, the third reproduction: its twin
  without the continuation was a prompt too), and so are the run-on line inside `"$(cat
  <<'EOF'⏎x⏎EOF git push --force origin x)"` and the command after an unquoted delimiter's
  body holding an odd `"`. Any other `"$(…)"` is still one quoted word.
- **A line continuation is deleted where bash deletes it, BEFORE the walk tests what it is
  looking at** — from the line itself, outside single and ANSI-C quotes, and never inside a
  comment, which the walk has left behind by then. So `git pu\⏎sh --force origin x` is the
  push it is, the line after `ls # x \⏎` is a command, `a \⏎#b` holds a comment and `a\⏎#b`
  none — and no test reads as two pieces a construct bash has already joined. Round 2
  deleted a continuation as the walk passed it, and every test that looked ahead or behind
  still read the raw line (`escalations/02-audit-opus.md`, R2-2: `cat <\⏎(cat <<EOF⏎x⏎EOF )
  ; git push -f origin y⏎EOF⏎)` reached no deny). Now a split operator (`<\⏎<EOF`, `<<\⏎<`),
  delimiter (`<<\⏎EOF`, `<<E\⏎OF`, `<<"E\⏎OF"`, `<<'EOF'\⏎`: `heredoc_delimiter` reads it
  joined, and says whether it was quoted), substitution opener (`<\⏎(`, `$\⏎(`, `>\⏎(`),
  arithmetic opener or subscript before a `<<` (`(\⏎(`, `$\⏎[`, `a[1\⏎<<2]`), `$\⏎{`, `$\⏎'`
  and whole-argument head or tail (`"$\⏎(cat <<'EOF'⏎`, `⏎\⏎)"`) is the one bash reads. The
  raw-text tests beside the walk follow: the heredoc operator and the git word past a cap
  are looked for with every continuation deleted, and so are the unreadable-ledger
  refusal's markers (`unreadable_ledger_refuses`: `$\⏎(` and `<\⏎<` are `$(` and `<<`).
  Inside backticks bash deletes a continuation from the substitution's text before it
  reads the quotes there, and halves each run of backslashes as it does: there one is
  deleted inside single quotes too, and `\\⏎` is one for the substitution's own parser
  (`BACKTICK_ESCAPE_CYCLE`). A last backslash that escapes nothing is dropped: bash runs
  the command without it, and the lexer would refuse the line with it.
- **A body's own continuations are read every way that is in doubt** (`joins`). Bash's
  reading comes first (`HEREDOC_JOINS_PARSER`): an unquoted delimiter's body joined, a
  quoted one's as written. On a line that holds a heredoc and a continuation two more
  follow: `HEREDOC_JOINS_BACKTICK` — after a backtick the walk cannot tell whether the
  heredoc is inside the substitution, where a quoted delimiter's body is joined too and
  `\\⏎` joins an unquoted one's — and `HEREDOC_JOINS_AS_WRITTEN`, which joins nothing: how
  every body was read before round 3, kept so that a line denied that way is still denied.
- **A `#` is dropped for certain only where bash is certain to start a comment**: after an
  unescaped blank or operator (`a\ #b` and `a\r#b` are one word), outside `${…}` — where
  only a `${` nests, so `${x:-{}` ends at its first `}` — and with none of `(`, `[`, `{` or a
  backtick in the text kept before it. Past one of those the walk cannot tell: `a=(x)#b` and
  `$(x)#b` are one word though `(ls)#b` holds a comment, a `#` after a blank is text inside
  `$((…))` and a subscript, and a quote nested in `"$(…)"` or in quoted backticks turns the
  walk's quote state over. So each such `#` is **in doubt** and is read both ways, on its
  own — dropped, and kept as the commands it may be — in every combination. A line with
  more than `MAX_COMMENT_DOUBTS` of them is not read finely (below). Inside backticks a
  comment runs only to the closing backtick. `$'…'` is walked as the ANSI-C quote it is, so
  a `$'` in a comment opens nothing — after an odd run of `$` only: `$$` is the PID, so
  `$$'a\'` is a plain quote, and the git deny's readings leave that PID out, so that
  `never_judged` (below) does not hold back a line bash runs
  (`echo $$'a\' ; git push --force origin y #'`).
- **Past a cap the line is not read finely.** With more comments in doubt than
  `MAX_COMMENT_DOUBTS`, or more run-on lines in a body than `MAX_RUN_ON_LINES`, a line that
  names git anywhere is judged as a git command that cannot be read (`GIT_UNREADABLE_ARGS`:
  denied, never passed on); any other line is not read at all, which is a run to the
  build-script judge (the unreadable-ledger path) and no deny to the rest.
- **A built reading that does not tokenize is never dropped** (round 4;
  `self/features/hook-audit-gaps/escalations/03-audit-opus.md`, R3-1). When the walk has
  BUILT a reading — a comment dropped, a body placed, a whole-argument heredoc stood in or
  opened, a continuation deleted — and that reading's quotes then never close, no reader
  can lex it, and until round 4 it was dropped without a word: in `echo "$(cat
  <<'EOF'⏎x⏎EOF )" ; git push -f origin y⏎EOF⏎)"` bash ends the body at the run-on line,
  closes the quote, runs the push and only then meets the odd `"`. The walk now hands such
  a line back as a `TornReading`, `torn_reading` is the one test of it, and `judged_texts`
  asks it of every reading: a line that names git anywhere is judged as a git command that
  cannot be read, as past a cap, and any other takes the does-not-tokenize deny
  (`does_not_tokenize` asks `tears_a_reading`) — a chained `cd` or an own assignment bash
  runs there sits in a reading nothing here can lex. This is the one exception to "a line
  that does not tokenize is not judged" wherever this file says it — of the git deny
  ("The git shape" below) and of the seventh opaque shape ("The rewritable shapes"), whose
  heredoc and `#` guards do not excuse a torn reading. Not a built reading: a line the walk
  changed nothing on (a plain open quote, the opaque check's as before); a comment in doubt
  kept as TEXT (the reading that drops it is the one asked); bodies read as commands
  because none could be placed; and a dropped `$$` with nothing else (`grep $$'\'#' f`
  stays `never_judged`'s).
- **The opened head is matched as bash reads it** (round 4; R3-2). `"$( cat <<EOF`,
  `"$(⇥cat⇥<<EOF`, a line break after the `$(`, `"$(cat<<EOF` and a line continuation
  between any two of its characters are the head `"$(cat <<EOF` is
  (`HEREDOC_OPENED_HEAD_RE`, over `CONTINUATIONS_PATTERN`): `judged_texts` respells each
  one that way for the opened reading. Text before the `$(` (`"x$(cat <<EOF`) and a
  command that is not a bare `cat` are not this head, and stay one quoted word.
- **A head with any other delimiter is not read for a message at all** (round 5;
  `self/features/hook-audit-gaps/escalations/04-audit-opus.md`, R4-1). The stand-in and the
  opened reading both take the delimiter `HEREDOC_ARGUMENT_HEAD_RE` reads: a bare or fully
  quoted identifier. Bash takes more — a partly quoted word (`E'O'F`, `E"O"F`, `''EOF`), a
  backslash-quoted one (`\EOF`, `E\OF`), an empty one (`''`, `""`: the body ends at the
  first empty line) and one that is no identifier (`E-F`, `123`, `'E O F'`, `'E)F'`) — and
  with any of those the head was neither stood in nor opened: one quoted word, whatever
  bash ran after its `)"` (`echo "$(cat <<E'O'F⏎x"⏎EOF⏎)" ; git push -f origin y` was a
  prompt, as was its run-on twin). The delimiter word is not parsed. `unread_head` takes
  what follows the `<<` crudely (`HEREDOC_HEAD_WORD_RE`: the `-` and blanks, then everything
  up to the next blank or operator character) and asks whether that is the plain word; when
  it is not — in any spelling of the head, in any reading `judged_texts` takes — the reading
  is noted as torn, which is the git deny for a line that names git and the
  does-not-tokenize deny for any other. A commit message or PR body is never written under
  such a delimiter, and one under `'EOF'`, `"EOF"`, `EOF`, `-EOF` or `-'EOF'` is read
  exactly as before. Not this head: a herestring (`"$(cat <<<x)"`); a head a reading has
  dropped — in a comment, in a placed or stood-in body, so a message that NAMES such a
  head is a body like any other; and what the opened reading leaves as well — text before
  the `$(`, a command word other than a bare `cat`. A plain delimiter with a command
  after it on the head's own line (`"$(cat <<EOF | tr a b`) is read as it was.

**What the both-readings rule over-denies.** Each of these is a deny for a line on which
bash runs no denied command; the rule never errs the other way:

- A comment bash does start, past an opener, that holds a separator and then a denied
  command: `(ls) # then; git push --force origin y`, `(ls)#b; git push --force origin y`.
  With no opener before it the comment is certain and hides its text as before
  (`ls src # then; git push --force origin y` is a prompt).
- Inside a substitution, a body line that begins with the delimiter and does NOT go on to a
  `)`: bash keeps reading the body, and the hook also reads what follows as commands
  (`echo "$(cat <<'EOF'⏎x⏎EOF notes⏎)" ; git push --force origin x ; echo "⏎EOF⏎)"`). For
  an orchestrator, a commit message or PR body with a line that begins with its own
  delimiter word is refused with the role reason: pick another delimiter.
- A line past one of the two caps that names git, whatever it would have run — and, on the
  unreadable-ledger path, any line past one.
- A quoted brace sequence past `MAX_BRACE_WORDS` in an ordinary git argument — `git commit
  -m "ids {1..1000}"` — is denied as a git command that cannot be read: the deny's
  `brace_words` expands a quoted word too, by design (more words to judge, never fewer). A
  heredoc commit message is not affected, since its body is stood in before that.
- On the unreadable-ledger path, a comment in doubt that names a build script after a
  command word (`(cd x) # then ./run-plans.sh`) is a run.
- Round 3's. A body line bash joins to the one before it, then a line that is the
  delimiter alone, then a denied command: `cat <<EOF⏎x\⏎EOF⏎git push -f origin y⏎EOF`
  (bash's body runs to the last line; the reading that joins nothing ends it at the first
  `EOF`, as round 2 did). After a backtick anywhere earlier on the line, a quoted
  delimiter's body with a terminator joined across a continuation (``echo `date` ; cat
  <<'EOF'⏎EO\⏎F⏎git push -f origin y⏎EOF``), read as a backtick substitution's text is.
  And a whole-argument heredoc that is not stood in, read opened: what follows its body
  up to the next `"` is read as commands, so text bash keeps inside the quotes is too
  (`echo "$(cat <<EOF⏎x⏎EOF⏎) ; git push -f origin y"`), and so is the rest of a body
  after a line that begins with its own delimiter word (`"$(cat <<EOF⏎x⏎EOF notes⏎git
  push -f origin y⏎EOF⏎)"`). NOT one: the quoted-delimiter twin of a joined terminator,
  `cat <<'EOF'⏎EO\⏎F⏎git push -f origin y⏎EOF` — bash joins nothing there, the hook reads
  it so, and it stays a prompt, as does an escaped backslash before the line break
  (`EO\\⏎F`).
- Round 4's: a built reading whose quotes the WALK cannot pair, on a line bash reads
  whole — denied as a git command that cannot be read when the line names git, with the
  does-not-tokenize deny (which decays to an ask) when it does not. After a heredoc, a
  quote nested in a later `"$(…)"` with an odd quote of the other kind inside it (`cat
  <<EOF⏎x⏎EOF⏎echo "$(grep "don't" f)"`: the plain reading ends the outer `"` at the
  inner one). A message or PR body holding a line that begins with its own delimiter word
  and an odd quote anywhere after it (`git commit -m "$(cat <<'EOF'⏎EOF notes⏎it's
  fine⏎EOF⏎)"`: the reading that ends the body at that line reads `it's fine` as
  commands) — pick another delimiter, as an orchestrator already must. Round 3's
  as-written and backtick readings of a body, when what they read as commands holds an
  odd quote (`cat <<EOF⏎a \⏎EOF⏎it's⏎EOF`). And the opened head's new spellings, which
  cost what round 3's opened reading costs. A line that is broken for bash as well — a
  quote really left open after a comment, a body or a continuation — moved from a prompt
  to a deny too, at no cost. NOT one: the usual `"$(cat <<'EOF'⏎…⏎EOF⏎)"` message or body,
  whatever apostrophes, quotes and backticks it holds, an unquoted delimiter's body
  holding an odd `"`, and a comment after a `)` holding an apostrophe (`(ls) # it's`).
- Round 5's: every line that holds a whole-argument head whose delimiter is no bare or
  fully quoted identifier, whatever follows it. `echo "$(cat <<E-F⏎x⏎E-F⏎)"` runs nothing
  denied and takes the does-not-tokenize deny (which decays to an ask, and whose reason
  names an open quote this line does not have); a line that names git takes the git deny —
  so a message under a backslash-quoted delimiter, `git commit -m "$(cat <<\EOF⏎msg⏎EOF⏎)"`,
  a prompt before, is refused: write `'EOF'`. `unread_head` looks at each reading's text
  and not at its quotes, so the head's TEXT inside single quotes on a line that names git
  is refused too (`git log --grep '"$(cat <<' -1`, `git commit -m 'about "$(cat <<123'`;
  a `grep` for it is still approved, as the read it is), and so is a message under an
  UNQUOTED delimiter whose body names such a head in a reading that leaves the body in
  (`git commit -m "$(cat <<EOF⏎the head "$(cat <<E'O'F⏎EOF⏎)"`). NOT one: the
  same message under `'EOF'`, a herestring, and a plain delimiter with a pipe after it.
- Round 6's, as round 7 narrowed it: every line that names git, that no reading judges
  and that bash itself refuses (`bash -n`), whatever bash ran of it. A read before the open
  quote (`git status⏎echo '#`: bash runs the read, then stops at the quote). A commit
  message or PR body whose terminator and closing quote were both dropped (`git commit -m
  "$(cat <<'EOF'⏎msg`: bash runs nothing; a prompt before) — close it. A heredoc that is
  never terminated, with an odd quote in what follows it, on a line that names git (`git
  status ; cat <<EOF⏎it's`: bash reads the rest as the body, and warns — a warning is a
  refusal). A git word that is only text inside the open quote (`echo 'git push`), or
  inside what zsh reads as one ANSI-C quote and bash as an open one (`echo $$'a\' ; git
  push -f origin y '`). One line with a quote left open after an ANSI-C one (`git push -f
  origin y; echo $'\'' "`: bash runs nothing of it; a prompt before). Each is broken or
  unfinished for bash too, and each is told about the lifecycle rather than about the quote
  it needs to close; the ones with neither a `<<` nor a `#` were the does-not-tokenize deny
  before, which decays, and are this one now, which does not. One kind is NOT broken where
  it runs: a line no reading judges that parses only under an option or a shell the check
  does not have — an extglob pattern beside an ANSI-C quote (`git add !(x) $'it\'s'`,
  after `shopt -s extglob` on the line or in the session), zsh-only syntax. NOT one:
  anything bash parses — the usual message and PR body, an apostrophe in a comment or in a
  placed body, a `$'…'` that escapes a quote (`git commit -m $'it\'s'`), a quoted
  substitution whose inner quotes hold an odd quote (`git commit -m "$(echo "it's")"`:
  the does-not-tokenize deny it was before round 6, or the prompt when its text holds a
  `#`) — and any line that names no git.

**A line that names git and that no reading tokenizes is a git command that cannot be
read — when bash refuses it too** (rounds 6 and 7;
`self/features/hook-audit-gaps/escalations/05-audit-opus.md`, B1, and `06-audit-opus.md`,
B1). Bash runs every complete line before the one it cannot parse, so in `git push -f
origin y⏎echo '#` — and with `echo "$(cat <<EOF`, `echo '<<`, or a PR body whose terminator
was dropped as the last line — it ran the push and then met the parse error. The walk had
built nothing, so this was no torn reading; the git deny does not judge a line it cannot
lex; and the opaque check excused the line for the `<<` or the `#` in its raw text, inside
the open quote or not: a plain prompt. `judged_texts` now asks, once every reading is
taken, whether any of them is JUDGED — `chain_tokens` lexes it and `never_judged` does not
hold it back for an ANSI-C quote, the test `command_words` makes of each. When none is and
the line names git, bash is asked whether the line parses (`bash_refuses`, below), and
when it does not the answer is the one a torn reading and a line past a cap get
(`GIT_UNREADABLE_ARGS`: the git deny, which does not decay), whatever `<<` or `#` the line
holds. That covers the body no reading places whose text holds an odd quote (`git push -f
origin y⏎cat <<EOF⏎echo '`) as well. It widens round 4's exception ("A built reading that
does not tokenize is never dropped", above) from a built reading to any reading, and it is
what holds wherever this file says that a line that does not tokenize is not judged, is
refused whole, or is the opaque check's: under "The git shape", and for the seventh opaque
shape. Those sentences describe a line that names NO git, or one bash parses, which keeps
the verdict it had — the does-not-tokenize deny, or the prompt its heredoc and `#` guards
leave (`ls⏎echo '#`).

Round 6 decided what bash parses by guessing, and was wrong both ways. It excused every
reading `never_judged` holds back, so one `$'\''` anywhere switched the deny off on a line
bash cannot parse either (`git push -f origin y⏎echo $'\'' "`, and with `echo $'\'' '`,
which shlex even lexes: its audit, B1); and it denied what shlex refuses and bash runs (`git
commit -m "$(echo "it's")"`: its review). Round 7 asks bash. **`bash_refuses`** runs `bash
--norc --noprofile -n` with the line on stdin and counts anything but exit 0 with no
output as a refusal:

- **Nothing in the line is executed.** `-n` reads commands and runs none — no command, no
  `$(…)`, backtick or `<(…)` in a word, a heredoc body or an expansion, no redirect, trap,
  alias or function, and a `set +n` on the line is itself not run (tried on bash 5.2;
  `self/tests/hook-cloud-profile.sh` H20 keeps a canary). The line is never an argument
  (`-c`) or a file it names, stdin closes after it, no startup file is read, and the
  environment is `PATH=/usr/bin:/bin` alone, so no `BASH_ENV`, `ENV`, `SHELLOPTS` or
  exported function of the session reaches it and the bash found is the system's.
- **It fails closed.** No bash there, a timeout (`BASH_SYNTAX_TIMEOUT_SECONDS`), a NUL, a
  non-zero exit and ANY output count as refused: a heredoc that is never terminated exits
  0 with a warning, and bash ran what stood before it.
- **Its answer only adds this deny.** Bash is asked last, about a line that names git and
  that no reading judges — a line the hook reads costs no subprocess — and "refused" turns
  that line's verdict into the git deny; "parsed" leaves the verdict the line had before
  anything was asked. No approval and no other deny reads the answer.
- **It is not the shell the command runs in.** Claude Code hands the line to `eval` in the
  session's shell, which parses and runs it a command at a time, as bash reads stdin — but
  with the session's aliases and `shopt`s, in whatever bash or zsh that is. A line that
  parses only there is denied (the over-deny above); a line that fails part-way only there
  keeps its prompt, as does everything bash parses and no reader here follows.

What still reaches a prompt rather than a deny, as before this feature: a line that names
git, that no reader here judges and that bash PARSES — valid bash behind a quoted
substitution with an odd inner quote, or behind an ANSI-C quote that escapes one (`git
push -f origin y⏎echo "$(echo "it's #")"`, `git push -f origin y⏎echo $'\''`; without a
`#` or a `<<` in its text the first kind is the does-not-tokenize deny, which decays); a
line that names no git, does not tokenize and holds a `<<` or a `#` anywhere in its raw
text (`cd /tmp && ls⏎echo '#`: `does_not_tokenize`'s two guards excuse it, so the
chained-`cd` rewrite it would have been told about is lost — never a git deny); a line
that names git of which ONE reading tokenizes, though not the one bash makes — a comment
in doubt kept as text, whose apostrophe pairs with a later odd quote, beside a body no
reading places (`(ls) # it's⏎git push -f origin y⏎cat <<EOF⏎echo '`: bash is not asked
about a line a reading judges);
a `$(…)` in the
body of a heredoc with an unquoted delimiter, which bash runs and no reader here follows;
a command INSIDE a quoted substitution that is no whole-argument heredoc's, which the plain
reading takes for one quoted word (`echo "$(true; cat <<EOF⏎x⏎EOF⏎git push --force origin
x⏎)"`); and a `$'…'` that escapes a quote (`never_judged`, below)
(`self/BACKLOG.md`, hook-audit-gaps).

`never_judged` is the one guard every deny and rewrite below keeps, for the two places
the readers here would not read a line as the shell does:

- **An unquoted `#`** in text no walk has read: a comment, or a literal inside a word
  (`cat a#<<EOF`). The rewrites keep this guard whole, and so does the chained-`cd` deny for
  a `#` inside a word (`cd x && ls a#b` gets no rewrite; a comment it judges around).
  `command_words` — the git, assignment and build-script denies — reads the walk's text, so
  an apostrophe in a comment hides nothing: `git push origin main # '` is the push it is
  (hook-audit-gaps, A — the audit's two options were to strip the comment or to never let an
  unlexable line lose a deny; stripping reads the line as bash does and costs no extra
  denies). A `#` still in that text is the literal bash reads (`a#b`, `$#`, `${x#y}`), and
  the line is judged with it: `git push --force origin x a#b` is denied (phase 3; before it
  any `#` inside a word left the whole line unjudged, a prompt). A `#` inside
  single or double quotes or behind a backslash is a literal and is
  no guard, so `cd <root>; grep -n '^#' f` is denied like `grep -n '^x' f` — before
  `hook-hash-chained-cd` any `#` at all skipped the check. A line whose quotes never close
  outside its comments is read raw.
- **A `$'…'` that escapes a quote** (`$'it\'s'`), `#` or no `#`. That is ANSI-C quoting:
  the backslash makes the quote a character, and shlex — which every reader here lexes
  with — ends the quote at it. Judged anyway, `ls $'\'' # '; cd x` had its comment read
  as quoted and a `cd` the shell never runs denied, and `echo $'\''` was told to close a
  quote that is closed. Any `$` before the quote counts, because the shells disagree:
  bash reads `$$'…'` as the PID and a plain quote, zsh as a `$` and an ANSI-C one. A
  `$'…'` with no escaped quote ends where a plain quote does and is judged as one.

The cost is a real chain that carries such a quote: `cd x && grep $'it\'s' f` gets no
rewrite and reaches the ordinary flow, like a chain with a `#` inside a word. (A chain with
a trailing comment is denied since hook-audit-gaps, A: `cd x && ls # note` was unjudged
before it.) It is never approved (below). The guard is a model of shell quoting, so it is checked against the
shells: `self/tests/hook-quote-oracle.sh` puts every short string over `' " \ $ # space a`
to bash, and to zsh where installed, and fails if the guard lets through a line either
reads a comment or an unquoted `#` in, or holds one back without one of the two reasons
above.

**The approval analysis never approves a chained `cd` either.** `command_allowed`
approves a `cd` only as the whole command; one sharing the line with anything else is
refused, so a chain the deny cannot judge reaches the ordinary flow rather than an
`allow`. An `allow` there bought nothing: Claude Code re-checks every path a
hook-approved command reads against the reads fence, which cannot follow a `cd`, and
stopped for the human anyway — with no rewrite told to the model. The analysis
therefore threads no directory from one member to the next.

In a consuming repo the deny also reaches the runners' Bash-enabled executors (verify,
review). That is intended: they are held to the same convention.

### The git shape

A git command that moves a ref, rewrites history or throws work away, **wherever it sits
on the line** — after a `&&`, `;`, `|` or `&`, inside a `(…)` subshell or a `$(…)`
substitution, behind `-C <path>`, `--git-dir=…` or `-c k=v`. The reason names
`LIFECYCLE.md` → "The three rules", rule 2, and **both ends of the sanctioned route**:
`feature-start.sh` is the way in — it makes the branch and the worktree, is run from the
primary checkout by the human or by the session itself (with the command spelled out, and
the instruction to start the feature *before* editing and then edit only inside the
worktree), and its next run prunes away the ones whose work has merged — and `feature-close.sh` is the way out, run from the feature's worktree, on its
branch, after a clean review and *before* the merge. Merging the PR is the last step and
nothing runs after it (`self/DESIGN-2026-09-17-close-and-review-rounds.md`;
`LIFECYCLE.md` → step 6). `self/tests/allow-repo-commands.sh` asserts both names are in
the reason, and nothing in this directory says the close runs after the merge.

The constants behind all of this are `policy.py`'s, not this script's: the same table
`wire-settings.py` renders the `permissions.deny` prefix rules from.

Denied: `push` with `--force`, `-f`, `--force-with-lease[=…]` or a bundle of short flags
holding `f` — `-fu`, `-uf`, `-vfq` (`bundles_push_force`: the letters are read left to right
and stop at `-o`, which takes the rest of the word as its value, so `-ofoo` and `-uq` are no
force), in both profiles; `reset --hard`; `clean`;
`rebase`; `stash` unless its first argument is `list` or `show` — bare `git stash`, a
leading flag or pathspec (`git stash -u`, `git stash -- src`, each a push), `push`,
`save`, `pop`, `apply`, `drop`, `clear`, `branch`, `create`, `store` and an unknown
subcommand; `worktree` with any subcommand but `list` — `add`, `remove`, `prune`,
`move`, `lock`, `unlock`, `repair`, and an unknown one, since a subcommand the table has
not heard of is not one it can vouch for; `checkout -b`/`-B`;
`switch -c`/`-C`; `branch` with a positional argument or `-d`/`-D`/`--delete`/`-m`/`-M`/
`--move`. `clean` and `rebase` are denied whatever follows.

**`git stash list` and `git stash show` are read-only git** (2026-09-26,
`self/features/hook-pipe-redirect/`), approved like `git worktree list`. `stash` used to be
denied whatever followed, on the grounds that `list` is one keystroke from `git stash`;
but `CONVENTIONS.md` tells a worktree session to find its own stash entry by tag, which
that deny made impossible. The first argument decides, not the first positional as for
`worktree`, because a stash's leading flag makes it a push.

Not denied: `git branch --show-current`, `git branch --merged main` (the value of a
listing flag is not a positional), `git branch --list 'feat*'` (after `--list` or `-l` a
positional is a pattern to filter by, not a name to create — the mutating flags are
judged first, so `git branch --list --delete old` is still denied),
`git worktree list`, `git stash list`, `git stash show`, a plain `git push`,
`git checkout -- <file>`, `git reset <file>`. Nor is anything the analysis cannot read,
for the same reason the `cd` deny leaves those alone: a heredoc body, a comment, a line
`never_judged` holds back (a `$'…'` escaping a quote — a `#` inside a word is no longer one
for this deny: "What the deny side reads" above), or a `git …` that is an argument rather
than a command (`echo 'git rebase'`). A line that does not tokenize is no longer one of
them: no reader can judge it, so it is refused whole, as a git command that cannot be read
(round 6: "A line that names git and that no reading tokenizes", above).
A word carrying a brace is expanded as bash expands it (`brace_words`, the deny's own
expansion: nested groups and `{a..c}` sequences, in bash's order — the approval analysis's
`expanded_argv` reads simple groups and refuses the rest, which a deny cannot afford) and the
expansion is judged, so `git branch -D old {a,b}`, `git branch {-a,new}`, `git worktree
{add,list} x` (the last two were prompts before F2), `git push --forc{e,{x,y}} origin z` and
`git reset --har{d..d}` are denied. The word comes from the lexer with its quoting gone, so
a quoted group is expanded too (more words to judge, never fewer), and a word that expands
to nothing is kept as written. A git command whose braces expand past `MAX_BRACE_WORDS`
cannot be read and is denied as one that mutates (`GIT_UNREADABLE_ARGS`) rather than passed
on (hook-audit-gaps, F2: the skip let a delete through to a prompt; phase 3: a nested group
or a sequence was "judged as written", which was the way round it, and past the cap only
the brace rewrite fired, which decays to an ask).

Known and not denied — each a prompt, never an allow, and recorded in `self/BACKLOG.md`
under hook-audit-gaps rather than closed there: a long option abbreviated as git accepts it
(`push --force-w`, `reset --har`); a short-flag cluster on a subcommand other than `push`
(`checkout -qb x`); a `+<refspec>` push that names no protected branch (pinned as a prompt
by `self/tests/hook-cloud-profile.sh`); and git behind an environment prefix, a wrapper or a
keyword (`X=1 git …`, `env git …`, `! git …`, `{ git …; }`).

The check runs after the `cd` deny and before the approval analysis, and like the `cd`
deny it needs neither `CLAUDE_PROJECT_DIR` nor `cwd`.

#### The git shape, by profile

`GIT_DENY_REASON` describes the **local** layout — run the start from the primary
checkout, edit inside `.worktrees/<slug>` — which is wrong advice in a Claude Code cloud
container, where the container IS the feature's checkout on its assigned branch. So the
reason is chosen by profile (`self/features/review-base-and-cloud-hook/`), the profile
coming from `env_profile.py`, imported in-process — this file spells neither profile
variable:

- **local** (and an invalid `AGENTTOOLING_PROFILE`, or a missing module, which read as
  local): `GIT_DENY_REASON`, unchanged, and no subprocess is run. The one local change is
  the push to `main` below, refused with `GIT_PUSH_PROTECTED_DENY_REASON` (when the line is
  also a ref-moving shape, `GIT_DENY_REASON` wins); every other case in
  `self/tests/allow-repo-commands.sh` answers as before.
- **cloud**: `GIT_CLOUD_DENY_REASON_TEMPLATE` — still `LIFECYCLE.md` rule 2, then: this
  container is the feature's checkout on `<branch>`, no worktree and no other branch to
  make, switch to or push; commit on `<branch>` and push only it. When a tracked manifest
  under `<features dir>/*/README.md` names the branch as its `branches[0]` (the reading
  `session-start.sh` makes: `git grep` narrows, the fence decides, a fence with no
  branches reads as its slug), it names that feature, its manifest and
  `<prefix>feature-close.sh [--self] <slug>` (`GIT_CLOUD_STARTED_TEMPLATE`); otherwise the
  start to run here, `<prefix>feature-start.sh [--self] <slug>`
  (`GIT_CLOUD_UNSTARTED_TEMPLATE`). `<prefix>` and `--self` come from where this file sits
  (`repo_shape`): at `<root>/hooks/` it is agentTooling's own checkout (`./`, `--self`,
  `self/features`), otherwise a consuming repo (`./agentTooling/`, `plans/features`). It
  never mentions `.worktrees/` or the primary checkout. When the branch cannot be read it
  says "this session's assigned branch" instead; the reason never fails to be emitted.
- **cloud, off the feature's branch**: `GIT_CLOUD_OFF_BRANCH_TEMPLATE`
  (`self/features/cloud-off-branch-remedy/`). A container the platform restarted comes back
  cloned on `main`, so the template above would offer "commit on `main`, push only `main`"
  — the forbidden action — as the remedy. When the checkout is on
  `policy.GIT_PROTECTED_BRANCH` or detached and a refused `git switch`/`git checkout`
  names (`switch_target_names`: positionals before `--`, and a `-b`/`-c` value) a branch
  that a manifest records as `branches[0]` (`off_branch_target`: the name as written, a
  remote-tracking `origin/<x>` as `<x>`, read with `started_feature` over the checkout's
  tracked manifests and then over the target commit's own tree, where feature-start.sh
  committed the manifest), the reason is this one instead: the container is off
  `<target>` (feature `<slug>`, its manifest), a cloud session cannot switch to it, and the
  remedy is a fresh session launched on `<target>` or the human checking it out here; it
  never says to commit or push the base. The refusal itself is unchanged — no carve-out
  allows that switch. The extra probes run only on that refused path.
- **cloud, detached at the branch's tip**: `GIT_CLOUD_ATTACH_TEMPLATE`
  (`self/features/detached-at-branch-tip-attach/`). A session launched to continue a
  feature's branch can come up with HEAD detached exactly at `origin/<branch>`, the local
  `<branch>` a stale ancestor left by a cached clone; a fresh session reproduces it, so
  the off-branch remedy does not cure it. When the checkout is detached and
  `attachable_branch` finds such a branch — `for-each-ref --points-at HEAD
  refs/remotes/origin`, a tracked manifest naming it as `branches[0]` (`started_feature`),
  and the local ref absent or an ancestor of HEAD (`merge-base --is-ancestor`), the
  reading `plan-runner-roots.sh`'s `attachable_branches` makes — **every** cloud refusal
  there (`checkout -B`, `switch -C`, `branch -f`, a plain switch to the stale branch, a
  push) gets this reason instead: the shape, that a fresh session will not cure it, and
  the one command, `<prefix>attach-branch.sh [--self] <branch>`, which checks the same
  conditions and points the branch at HEAD and checks it out, moving nothing. The ref
  movers stay refused — the settings file's prefix rules refuse them whatever this hook
  says — and the script itself is not on the read-only entry-point list: like
  `feature-start.sh` it moves a ref, so it prompts. The probe runs only on a refusal
  from a detached HEAD.

And in the cloud, **two more shapes** are denied with that reason — `policy.py`'s
cloud-only entries, which are hook-only (no prefix can express them, so the settings file
does not change):

- **switching away** (`CLOUD_SWITCH_AWAY`): `git switch <x>` for any `x` but the current
  branch, `git switch -`, `--detach`/`-d`, `--orphan`; `git checkout` with one positional
  that is `-` or that git resolves to a commit (`rev-parse --verify --quiet <x>^{commit}`)
  or that names a remote-tracking branch (`origin/<x>`, which `git checkout <x>` would
  turn into a local branch), unless it is the current branch, `HEAD` or `@`;
  `git checkout --detach`, `--orphan`. A **file checkout is never a switch**: anything
  after `--`, `-p`/`--patch`, `--pathspec-from-file`, two or more positionals, or one git
  cannot resolve (a path) keeps today's answer. On a **detached HEAD**, where there is no
  current branch to leave, the same shapes are refused only when they would move the
  working tree (`detached_switch_moves`): `-`, `--orphan`, or a target that resolves —
  as written, else as `origin/<target>` — to a commit other than HEAD's. A switch landing
  on HEAD's own commit (`git checkout <branch>` whose local ref already IS HEAD,
  `git switch --detach`, `git checkout origin/<branch>` at HEAD) is not refused.
- **pushing elsewhere** (`CLOUD_PUSH_ELSEWHERE`): `git push` with `--all`, `--branches`,
  `--mirror`, `--tags`, `--delete`/`-d` (also inside a short cluster) or `--prune`, or a
  refspec — `[+]<src>[:<dst>]`, after the first positional, which is the remote — whose
  destination (`dst`, else `src`; `HEAD`/`@` the current branch; `refs/heads/` stripped)
  is not the current branch, or whose `src` is empty (`:x`, a deletion). Plain `git push`,
  `git push origin`, `git push origin HEAD` and `git push origin HEAD:<current>` keep
  today's prompt (unless the current branch is `main`, below); `git push [-u] origin
  <current>` is approved in the cloud when the feature is started, next.

**The one cloud approval: the started feature's own push** (`own_push_allowed`,
`self/features/cloud-checkpoint-push/`, narrowed by `self/features/own-push-real-gitdir/`).
A cloud container is reclaimed with whatever it never pushed, so — approval side, after
every deny above has had its say — `git push [-u | --set-upstream] origin <B>` is approved
silently in the cloud when all of these hold, and approves nothing otherwise (the answer is
always the prompt, never a deny; the order below is the order the checks run, cheapest
first):

- the push is the **whole command**: in a sequence with anything, even an approved read
  (`git push origin <B> && cat README.md`, `ls; git push origin <B>`), it is sent back with
  "run the push alone" (`own_push_alone_reason`, `OWN_PUSH_ALONE_REWRITE_REASON`), and in a
  pipeline (`git push origin <B> 2>&1 | tail -3`) or beside a redirect to a file it prompts
  (one write per Bash call, `self/features/hook-silent-allow-sweep/`, item 4);
- the words are exactly that, with **nothing before `push`**: no `-C`, `--git-dir`,
  `--work-tree`, `-c` or any other global option, and no env assignment — each of them moves
  the git directory, and a literal shape is simpler to hold than judging where a location
  resolves. After `push`: at most one of `-u` / `--set-upstream`, the remote word exactly
  `origin` (`OWN_PUSH_REMOTE`), and one branch word `<B>` — a plain name
  (`OWN_PUSH_BRANCH_RE`), never `HEAD`/`@`, `refs/heads/…`, `+<B>`, `<src>:<dst>` or
  `main`. Any other flag (`--no-verify`, `-o`, `--repo`), a second refspec or another
  remote prompts as before; a force push is denied before this is reached. `git -C <root>
  push …` therefore prompts, as `hook-cloud-profile.sh` T pins;
- the profile is `cloud` (`profile_is_cloud()`); the profile is read after the words, so a
  non-push command, and any push locally, runs no git;
- the payload's `cwd`, realpath'd, **is the project root**: a push from a subdirectory of
  the root prompts (Q7);
- git uses **the root checkout's own git directory**. The hook finds that checkout by
  walking the filesystem (`own_checkout`), not by asking git: the nearest directory at or
  above the root holding a `.git` entry, whose git directory is that entry when it is a
  directory, or the path on the `gitdir:` line when it is a regular file (a linked
  worktree); a symlink, an unreadable file or no `.git` at all prompts. Then `git rev-parse
  --absolute-git-dir --show-toplevel`, run in the root with the hook's own environment,
  must report that git directory and that checkout, both compared by realpath. This is the
  audit's gap: a git directory written as plain files under the tree (`plans/evil2/`, with
  `core.worktree` naming the root and `remote.origin.push` aiming at `main`, or with an
  `ssh://` origin and `core.sshCommand`) contains no `.git` in any path, so no write rule
  covers it, and `git -C plans/evil2 push …` used to be approved. With no `-C` the plant is
  never reached; a bare-repo shape (`HEAD`, `objects/`, `refs/`) planted in the root
  itself, a `core.worktree` in the real config and a `GIT_DIR` in the hook's environment
  each give another pair and prompt. A root that is a subdirectory of its checkout (the
  vendored `agentTooling/`, or a `--self` run) and a linked worktree keep the approval
  (`hook-cloud-profile.sh` Q7);
- the **effective config**, read once with `git config --list -z` in the root (every scope:
  system, global, the repo's `.git/config`, `config.worktree`, includes, and the command-line
  scope the environment's `GIT_CONFIG_*` build), holds none of these keys
  (`OWN_PUSH_PRESENT_KEYS`, `OWN_PUSH_PRESENT_KEY_RES`; present at all means a prompt):
  `remote.origin.push`, `.pushurl`, `.receivepack`, `.vcs`, `.mirror`, `remote.pushdefault`,
  `branch.<any>.pushremote`, `core.sshcommand`, `core.hookspath`, `core.fsmonitor`,
  `push.recursesubmodules`, `push.gpgsign`, `pager.push` (git runs the pager it names),
  `submodule.recurse` (git reads it as `push.recurseSubmodules=on-demand` when that is
  unset, so the push would run in a submodule's own git directory), `push.followtags` (it
  pushes annotated tags beside `<B>`, and the approval is for one ref), `hook.<any>.event`
  and `hook.<any>.command` (config-based hooks: git 2.43 ignores them, a newer git runs a
  `pre-push` command with no file in `hooks/`), `include.path` and `includeif.<any>.path` (the included file could change between the
  probe and the push), and `credential.helper`, `credential.<any>.helper` and `core.askpass`
  (git runs the program they name when the server asks for credentials, and a `!`-prefixed
  helper is a shell command; `own-push-credential-keys`). Every `<any>` above includes the
  empty subsection: `[credential ""]` lists as `credential..helper`, git honours it for
  every url, and so `branch..pushremote`, `includeif..path` and `hook..command` prompt too
  (`.*` in the regexes, not `.+`; Q8 has the raw-text rows). The **transport** is checked
  too (`own-push-transport-keys`, Q10): `remote.<any>.proxy` prompts, and `http.*` is
  deny-by-default — any `http.<var>` or `http.<url>.<var>` whose variable is outside
  `OWN_PUSH_HTTP_SAFE_VARS` (`proxyauthmethod`, which the cloud's `~/.gitconfig` sets,
  `postbuffer`, `lowspeedlimit`, `lowspeedtime`, `maxrequests`, `minsessions`, `version`)
  prompts, so a proxy, `sslverify`, `curloptresolve`, a CA, certificate, key or cookie file,
  `extraheader`, `emptyauth`, `followredirects`, the `proxyssl*` keys and any variable a newer
  git adds each prompt. The approval also prompts when
  `GIT_ASKPASS` or `SSH_ASKPASS` is **non-empty** in the hook's environment (git runs it the
  same way; an empty one runs nothing, and the cloud container sets `GIT_ASKPASS=` empty, so
  an empty value approves), and when any of `GIT_EXEC_PATH`, `GIT_SSH`, `GIT_SSH_COMMAND` or
  `GIT_PROXY_COMMAND` is **set** at all (`OWN_PUSH_HELPER_ENVS`: git runs `git-remote-https`
  and its other helpers from `GIT_EXEC_PATH`). The probes run with `GIT_CONFIG` removed from
  their environment (`GIT_PROBE_DROPPED_ENVS`): it replaces the file `git config` reads and no
  other git command's, so a url-only `GIT_CONFIG` once hid every key above from the probe
  while the push still read them (`self/features/hook-silent-allow-sweep/`, items 2-3). The
  environment checks read the HOOK's environment: the Bash tool's shell is initialised from
  the user's profile, so a `GIT_ASKPASS` exported only from a shell rc file reaches the push
  but not the hook. `push.default` is absent, `simple` or `current`. `remote.origin.url`
  has exactly one value, an `https://` or `http://` url, and `git remote get-url --push --all
  origin` prints exactly that one line: a `url.*.insteadOf` or `pushInsteadOf` that applies
  to the url changes the line and prompts, one that does not (every cloud container injects
  `url.https://github.com/.insteadof=git@github.com:` and the `ssh://` twin in the
  command-line scope) does not, so the check is not "any `insteadOf`". A non-zero exit, a
  timeout or a record that does not parse prompts. The rest of `credential.*`
  (`credential.interactive`, `credential.username`, ...), `http.proxy*`, `gpg.*`, `user.*`,
  `push.negotiate` and `remote.origin.proxy` are deliberately not read: none names a program
  git runs on a push, the cloud sets some of them itself (`credential.interactive=false`),
  and the proxy keys reroute the transport under TLS and run nothing. Q7 has one row per key
  and per url shape; Q8 has the credential keys, the global-config helper and the askpass
  environment rows;
- neither `pre-push` nor `reference-transaction` exists (as any file type) in
  `<git rev-parse --git-common-dir>/hooks/`: the two hooks a push runs locally
  (`core.hookspath` already prompts, so the default directory is the only one to look in);
- git reads the current branch as `<B>` (`checkout_state`), run from the root;
- a **tracked** manifest names `<B>` as its fence's `branches[0]` (`started_feature`, the
  same reading `session-start.sh` makes): a manifest that lists it second, or only mentions
  it in prose, does not count. The manifest is read **as committed at `HEAD`**
  (`started_feature(..., tree=GIT_HEAD)`), never from the working tree: a commit is a write
  that goes to the human, an uncommitted edit is not, and `HEAD` is what the push sends, so
  editing `branches[0]` to name the current branch approves nothing until it is committed
  (`self/features/hook-audit-gaps/`, B3; `hook-cloud-profile.sh` Q5). The commit is read as
  git stored it, **replace refs ignored**: `own_push_allowed` sets
  `GIT_NO_REPLACE_OBJECTS=1` (`GIT_NO_REPLACE_ENV`/`GIT_NO_REPLACE_ON`) in the hook's own
  environment before its `HEAD` probes, so a `refs/replace/` entry laid over the committed
  manifest's blob — a ref no commit records and no human approved — approves no push
  either (round 2's hardening; Q6, which proves the ref live first).

Every probe that fails (no repo, a detached HEAD, git missing, a timeout) approves nothing:
the answer is today's prompt. It is the hook's alone — `policy.py` and the rendered
`permissions.deny` do not change, so `.claude/settings.json` is unchanged — and it is the
only write the approval side ever vouches for. A line chaining it with a command the
hook does not approve is still the "mixes reads with one write" rewrite
(`self/tests/hook-cloud-profile.sh` T and Q).

A redirect's file descriptor is never read as a refspec: the deny side's tokens
(`chain_tokens`, which `command_words` and `chains_chdir` both read) drop a word of digits
that ends directly on a `<` or `>` (`2>&1`, `2>/dev/null`; `2 >&1`, spaced, keeps its `2`
as bash does). Before, `git push -u origin <current> 2>&1 | tail -3` read as a push of
`<current>` and of a branch named `2`, and the cloud refused a feature branch's first push
while the same push without the redirect prompted (`self/features/ablation-harness-fixes/`).
Every other redirect word is out of the push's words too, for the same reason: `command_words`
takes a redirect operator and its target out of the words of every command (`>out`, `> out`,
`>>log`, `&>x`, `<in`, `2>/dev/null`, `2>&1`, in any position), so `push_reading` — and
`push_goes_elsewhere`, `push_reaches_protected` and every other git rule — reads only the
real arguments, and `git push origin main 2>&1` and `git push origin other > log` are still
refused. A digit is that descriptor only as a whole unquoted ASCII word no bigger than a C int
(`is_bare_descriptor`, `MAX_DESCRIPTOR`): `'1'>x`, `\1>x`, `١>x` and `99999999999>x` are
arguments, so `git -C '1'>/dev/null push origin main` is read as the push it is; `{fd}>x` is
a descriptor too. A quoted or escaped operator character is masked before the lexer sees it
(`mask_quoted_punctuation`), and a word of nothing but such characters (`';'`, `"|"`, `\;`)
comes back from `chain_tokens` as a `QuotedWord`, an argument on both sides: the deny side
reads `git push -o ';' origin HEAD:main` as the push it is, and `command_allowed` refuses a
line holding one (`quoted_separator_word`) rather than judge what follows as a command of its
own; `'\(' ` as a grep pattern is no operator and stays approved. A punctuation run is read
as bash reads it (`punctuation_pieces`: `;>x` is a separator and a redirect)
(`self/features/orchestration-record-fixes/NOTES.md` → round 3, F1, F2, F4–F6).

**The fail-closed rule.** `command_words` has one plain reading: every operator ends a command,
a paren included, and a quoted word is one word (`"$(…)"` among them). It does not follow shell
grammar into substitutions, `case` arms or heredoc bodies. Instead, a line holding a git word
and a `$(…)`, a backtick, a `<(`/`>(`, a `<<` (heredoc or herestring) or the word `case` —
anywhere, quoted or not — is never approved (`fails_closed`, in `command_allowed`), and the
deny side refuses what the plain reading finds: `echo $(git push origin main)` and
`echo $(case x in x) git push origin main;; esac)` are denied, while
`echo "$(git push origin main)"` and `git push -o >(cat) origin HEAD:main` prompt, as they did
before this feature. The outcome is a prompt, not a rewrite deny, so
`git commit -m "$(cat <<'EOF' … EOF)"` keeps working. (A push names its branch as a literal,
`git push -u origin <branch>`: `git push -u origin "$(git branch --show-current)"` is this
prompt locally and, in the cloud, the push deny, which reads the words and cannot check a
substitution against `branches[0]`.) A heredoc never switches the
deny off: only an unquoted `<<` operator is one (`'<<'`, `\<\<` and a `<<<` herestring are
not), its own line is read, and only its body is left out, as bash ends it
(`heredoc_body_span`, "Where a heredoc's body ends" above); the commands after the body are
read (`judged_texts`, "What the deny side reads"). On a checkout whose orchestrator ledger cannot be read, the
build-script deny — the one deny every session there gets — is coarser still: a raw command
holding a `$(`, a backtick, `<(`/`>(`, a `<<`, `$'…'`, `$"…"` or `${…}` is refused outright,
before any reading, with `UNREADABLE_LEDGER_REASON` (repair `.git` or the ledger, or drop the
substitution or heredoc; `unreadable_ledger_refuses` in `build_script_denial`). A finer reading
on that path is out of scope by design: each one met a new spelling
(`self/features/orchestration-record-fixes/NOTES.md`, rounds 12–13). The plain reading keeps a word with a substitution inside it whole
for `assigned_names` and `invokes_build_script` (`X="$(pwd)"; cat $X/f`,
`"./run-$(echo plans).sh"`). A redirect that writes a file is a write: that push prompts, it is
not denied (`self/tests/hook-cloud-profile.sh` T; `self/features/orchestration-record-fixes/NOTES.md`
→ round 9).

`--repo <r>` / `--repo=<r>` names the remote, so after it **every** positional is a
refspec: `git push --repo origin x` is judged like `git push origin x`, in both judges. A
`--repo` with no value consumes nothing and is never a crash.

And in **both profiles**, a **push to `main`** (`PUSH_TO_PROTECTED`, round 2): a `git
push` with a refspec whose destination, read as above, is `GIT_PROTECTED_BRANCH` —
`origin main`, `-u origin main`, `HEAD:main`, `x:main`, `+main`, `refs/heads/main`,
`--repo origin main`, a deletion (`:main`, `--delete origin main`), any remote, behind git's
global options or inside a chain. Locally it is read from the **words alone, no git
probe**, so `HEAD`/`@` and a push with no refspec are not resolved: a bare `git push` while
on `main` locally stays a prompt. Locally the reason is `GIT_PUSH_PROTECTED_DENY_REASON`
(agents never push `main`; push the feature's branch; work reaches `main` only through the
PR `feature-close.sh` opens and a human merges — `LIFECYCLE.md` rule 2, steps 6–7); in the
cloud it is the cloud reason, and there the current branch resolves `HEAD` and a bare
`git push`, so either on `main` is refused too. `main` as a source only (`main:x`), and
`mainline`, `feature/main`, `main-x`, are not a push to `main`
(`self/features/review-base-and-cloud-hook/NOTES.md` rulings 21–29).

What the hook needs from the repository — the checkout's root and branch (one
`git -C <dir> rev-parse --show-toplevel --symbolic-full-name HEAD`), whether a checkout
argument is a commit (up to two more), the started feature (a `git grep`) — is asked only
on the cloud path of a git command that could be denied: a switch, a checkout or a push,
or an already-denied shape whose reason needs the branch. Never locally, never for a read
(`self/tests/hook-cloud-profile.sh` X1–X3, under a logging `git`). `<dir>` is the payload's
`cwd` (else `CLAUDE_PROJECT_DIR`), moved by each `-C <path>` among git's global options.
Every probe is bounded (`GIT_PROBE_TIMEOUT_SECONDS`) and any failure — no repo, no git, a
timeout, a detached HEAD for a push — leaves the cloud-only shapes silent: today's answer,
never a crash and never an allow. (A detached HEAD's switch is read as above.) An env prefix (`AGENTTOOLING_PROFILE=local git push …`) is not
read as git by either deny, so it stays an ASK; it changes that command's environment, not
the hook's.

**Both sides read past git's global options now, but not the same ones**
(`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §5b). The deny side skips the whole
of `GIT_GLOBAL_VALUE_FLAGS` (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`,
`--exec-path`, `--config-env`) to find the subcommand, because finding a *mutating*
subcommand behind an option is never a risk. The approval side skips only
`GIT_GLOBAL_LOCATION_OPTIONS` — `-C`, `--git-dir`, `--work-tree` — each of which names a
location and nothing else, so confining its value to the project root is the whole of what
it can do. `git -C <a path inside the root> status`, the commonest read a coordinator
makes across its own worktrees, is therefore approved rather than prompting; before this
only the deny side skipped anything, so `-C` read as the subcommand and matched nothing.

The asymmetry is deliberate and the four left out are the reason: `-c` and `--config-env`
set arbitrary config, so `git -c core.pager='sh -c id' log` runs `sh`; `--exec-path` moves
where git looks for its own binaries; `--namespace` names a ref namespace rather than a
path, so nothing needs it and unlisted means prompt. **Nothing else in front of the
subcommand is skipped either**, and a bare flag is not exempt for taking no value —
`--paginate`/`-p` forces the pager config names even when stdout is not a tty, so `git
--paginate log` and `git -p -C <root> log` prompt (as does `git --no-pager -C <root> log`,
the accepted cost of a listing rule). A location option whose value is missing or is
itself a flag (`git -C`, `git -C --git-dir status`) names no location and is not approved.

Confinement is **not** repeated in `git_location_args`: `subcommand_allowed` has already
put every argument through `token_confined`, which covers the attached and separate
spellings and every repetition — `git -C <root> -C /tmp status` fails there on the second
value. Finding the subcommand is not approving it, either: `git -C <root> branch new` and
`git -C <root> worktree add x` are still denied by the deny side, and the forbidden-flag
list still applies to what follows the subcommand (`git -C <root> diff --ext-diff`
prompts).

**Confined is not enough: the read must use the root checkout's own git directory**
(`self/features/hook-planted-gitdir/`). A bare git directory written into the tree as plain
files (`HEAD`, `objects/`, `refs/`, a `config` naming `core.fsmonitor` or `diff.external`)
is a path inside the root, and git discovers it, so `git -C <root>/plans/evil status`,
`git -C … diff --no-index a b`, a `git status` whose cwd is the plant and `git
--git-dir=plans/evil log` used to be approved and ran what it named. Now
`read_uses_own_gitdir` finds the git directory the read would use — the `--git-dir` value,
resolved after every `-C`, or else a walk up from the cwd moved by every `-C`, stopping at
the first directory holding a `.git` entry or a `HEAD` (git stops at no other kind, so it
never stops earlier) — and approves only the root checkout's own (`own_checkout`, the
filesystem walk the cloud push uses), its common directory, or a direct child of
`<common>/worktrees/`, so a real linked worktree under `.worktrees/` stays approved. A
nested repository's `.git` is neither and prompts too. A walk that finds no repository at
all approves as before: git reads no repository config then. **No git runs for this
check** — asking git would read the planted config — so the "never for a read" above
holds. Any failure prompts. A location value (`-C`, `--git-dir`, `--work-tree`) that bash
would expand as a pattern — a `*`, `?` or `[`, or an extglob group, anywhere in it
(`location_is_pattern`) — prompts too: `git -C plans/e?il status` named no directory to the
walk while bash ran git in `plans/evil` (`self/features/hook-silent-allow-sweep/`, item 1). Out of scope, each in `self/BACKLOG.md`: a writable real
`.git/config` and git variables in the hook's own environment (`GIT_DIR` there moves every
read past this check).

### The run-time-value shape

An **assignment at command position** whose own `$NAME` or `${NAME}` appears later on the
same line: `X=/p; cat $X/f`, `export X=/p && ls $X`. This is the generalisation of the
chained `cd` — what blocks the reads fence is a path decided at run time, not several
commands on a line — narrowed to the one case where the literal is provably still in hand
two words earlier, so the correction is a substitution rather than a rewrite. The reason
says to inline it: every path a literal, one command per call.

A command whose words are *all* assignments is an assignment command; one with anything
else after them is an **environment prefix** (`X=1 make`), which decides nothing the shell
re-reads on the same line, and is not denied. Nor is an assignment nobody dereferences
(`X=/p`), a `$NAME` with no assignment on the line (`cat $HOME/f`), a `$` the shell will
not act on (`echo '$X'`, a backslash-escaped one), or a `$(…)` substitution, which is not
a variable use. The guards the git deny keeps hold here too, through the same
`command_words`: a comment and a heredoc's body are not read, and a line `never_judged`
holds back (a `$'…'` escaping a quote) or a line that will not tokenize is never judged.

**There is no prefix-rule twin for this one**, unlike the git deny. A
`permissions.deny` entry is a command *prefix*, and this is a relation between two tokens
anywhere on the line; no prefix rule can express it, so nothing of it is in `policy.py`
and the hook is the whole of the enforcement. `allow-repo-commands.sh` says so beside the
constants.

### The rewritable shapes

The rest of the rule — no `$(…)` in a path, no heredoc into an interpreter — used to stay
prose in `CONVENTIONS.md`, on the grounds that a deny must not demand a rewrite
(`self/DESIGN-2026-09-16-lifecycle-restructure.md` §3.7). That was the wrong trade: such a
command fell through to the human's prompt, which cost an approval and taught the model
nothing, and there is a rewrite that always works. **Decided 2026-09-17, superseding
§3.7**: a command the analysis cannot read is denied with the rewrite as its reason, and
the human is only asked once the model has tried.

Seven shapes. Six hide code from anyone reading the command line:

| Shape | Example |
|---|---|
| a heredoc feeding anything but `cat` | `python3 - <<'EOF'`, `bash <<EOF` |
| code as a string at a command position | `python3 -c`, `bash -c`, `node -e`, `perl -ne`, `eval`, and the same behind `xargs` or `find -exec`/`-execdir`/`-ok`/`-okdir`. The scan for the code flag stops at the first non-flag word, so a *script's* own `-c` is the script's business: `python3 tool.py -c config.yaml` is readable and is not denied. |
| a pipe into an interpreter with no script, a redirect after it or not | `… \| sh`, `… \| python3 > out`, `… \| sh 2>&1`. Read by `piped_into_interpreter` over `redirect_members`' members, whose words have every redirect taken out — `opaque_segments` kept `>` and its target as words, so `ls \| sh > out` read as `sh` running a script named `>` and prompted. An input redirect from a file is the script: `ls \| python3 < a.py` stays readable. A pipe whose right-hand side starts on the next line (`ls \|` then `sh`) is still a pipe. |
| a program decided at run time | `$CMD …`, `${CMD} …`, `$(which x) …` |
| a `$(…)` or backtick inside a word that is a path | `ls $(cd dir && pwd)/src`, ``cat `pwd`/README.md`` |
| a one-line compound | `for … do … done`, `while`, `until`, `if`, `case` |

The reason is the same for all six: write the script to the scratchpad with the Write
tool and run it by name; or use the Read/Grep tool instead of a one-liner; or inline the
literal you already have.

**The seventh is the plainest, and has a reason of its own.** A line that does not
tokenize at all — a quote left open (`cat 'x`, `ls 'src`), or a word shlex
refuses — is a line no reader here can even split into words, so none of the six checks
above, none of the three shape denies and no part of the approval analysis ever judged
it: it printed nothing and cost the human an approval. `does_not_tokenize` denies it with
`UNREADABLE_DENY_REASON`, which names the quote and says to close it, because "write the
script to the scratchpad" is not the fix for an apostrophe. It counts toward the
escalation like the other six. A line that names git is this shape only when bash parses
it (`git commit -m "$(echo "it's")"`, which shlex refuses); one bash refuses as well (`git
rebase 'main`) is a git command that cannot be read, the git deny, which does not decay
("A line that names git and that no reading tokenizes", above). The heredoc and `#` guards hold here too, looked for in
the raw text since a line that will not lex cannot be asked where its quotes are: a body
line and a comment are data, so `cat <<'EOF' … don't … EOF` and `ls src # don't` still
prompt. `opaque_deny_reason` is the tri-state the three answers meet in — the six shapes'
reason, the quote's, or `None` for a command the analysis can read.

**Exempt.** A heredoc feeding `cat` is a literal string, not code — `git commit -m
"$(cat <<'EOF' … EOF)"` is the shape Claude Code itself uses for a commit message (its body
ends only at a line holding the delimiter alone, with the `)"` after it: `heredoc_body_span`;
`EOF)` is body text, so a body whose line begins `EOF)` is not this shape), and
the operator's owner is read out of the substitution it sits in, so `git` is not mistaken
for the program being fed. A `$(…)` that is a *whole* argument decides a value rather
than a path or a program: `x=$(cd dir && pwd)`, `echo $(pwd)`, `ls $(cat f)` and
`AT="$(cd "$(dirname "$0")/.." && pwd)"` are all left alone. An interpreter named in a
flag's **value** (`rg --pre 'sh -c id'`, `git -c core.pager='sh -c id'`) is one token and
not a command position.

**And a `$`, a backtick or a `<` inside SINGLE QUOTES is a literal, not a substitution**
(`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §5a). The path check reads a word
through `path_body`, which strips a leading `NAME=` and one layer of surrounding *double*
quotes and leaves single quotes exactly where they are; `unquoted_index`, which reads what
is left, carries its own single-quote state, so a word quoted only in part (`cat
'$HOME'/x`) is judged character by character. Double quotes still come off, because `$`
and a backtick stay active inside them — `cat "$(pwd)/README.md"` really is a path decided
at run time, and `AT="$(cd … && pwd)"` is the whole-argument exemption above. Before this
the check used `word_body`, which strips either quote, so the backticks in `sed -n
'/```json/,/```/p' <file>` read as a command substitution: the line was **denied** as
unreadable when its file sat outside the root, while the same line with a file inside it
was approved by the read-only rule one branch earlier. A literal in single quotes is a
literal, and the human should have been asked. This is a narrowing only — it feeds
`is_opaque`, which runs only after the approval analysis has declined, so it can turn a
deny into a prompt and can never turn a prompt into an approval. The unquoted forms are
untouched: ``cat `pwd`/README.md`` and `` `which ls` src `` are still denied.

And a line carrying any heredoc is judged on the heredoc alone,
since its body lines read as commands to every scanner here — the same guard the other
three denies keep. **With one exception**: when every heredoc feeds `cat`, the segments
*before the first line break* are still checked for a pipe into an interpreter and for
code as a string, because that first line is a command line and not a body (the pipe on
`redirect_members(…, stop_at_line_break=True)`, so `cat <<'EOF' | python3 > out` is the
same deny). Otherwise `cat <<'EOF' | python3` and `bash -c "$(cat <<'EOF' … EOF)"` — the first two rewrites a
model reaches for once `python3 - <<EOF` is denied — would read as a plain `cat`, fall
through to the human's prompt, and reset the escalation counter on the way. The body
lines are after that break, so they stay unjudged and the `git commit -m "$(cat <<'EOF' …
EOF)"` exemption is untouched.

**The check runs last**, after the three shape denies and after the approval analysis has
declined to approve. A command this hook understands well enough to allow is readable by
construction, so `ls src # list it` keeps its approval instead of collecting a deny for
its comment; and a command it refuses for what it *does* — `rm -rf src`, `curl …`, `cat
/etc/passwd` — is *refused*, not *opaque*, and still prints nothing. That is the whole
distinction: opacity is about what the command hides, never about whether it was allowed.

**Seven more shapes joined them on 2026-09-18**, judged after the seven above and by the
same test for membership: the analysis could not read the command, and there is a rewrite
that always works. Each has a named reason constant, each names the member as written
(`MEMBER_TEXT_MAX_CHARS`), and a line carrying several gets one line per shape.

| Shape | Example | Reason names |
|---|---|---|
| a `$NAME`/`${NAME}` the shell will expand, anywhere in a word — the special and positional parameters (`$?`, `$$`, `$1`) included | `grep x $FILE`, `ls "$HOME/f"`, `cat $1` | inline the literal |
| a word starting with `~` | `ls ~/x` | write the absolute path |
| a brace group the expansion refuses — a quote or backslash mixed into an unquoted brace group, nesting, past `MAX_BRACE_WORDS` | `cat {a,{b,c}}` | expand it yourself, or write a script |
| a `..` **component** of a path token | `cat ../x`, `ls a/../b`, `--out=../x` | write the path from the project root |
| a bare or relative `cd`/`pushd` | `cd src`, `cd` | `cd <absolute path>` as its own call |
| a line break outside a quote or a heredoc, or a `\` continuation | two commands on two lines | one call per line |
| a sequence (`&&`, `\|\|`, `;`) mixing approved members with members only the human can judge | `grep x f && git commit -m m` | which members to run on their own (approved) and which to run alone |
| a member whose program is `sleep`, bare or by path (`SLEEP_PROGRAM`) — added 2026-10-05 by `self/features/execution-profiles` (`self/DESIGN-2026-10-05-cloud-execution.md` §9) | `sleep 60`, `ls && sleep 5` | nobody polls: run it in the background and wait for the notification (`ORCHESTRATION.md`) |

The `sleep` row only tightens: every such line used to fall through to a silent prompt, and
it is judged in the per-member loop beside the others, so on a sequence it is named ahead
of the mixed-sequence rewrite (`ls && sleep 60` is told about the sleep, not about which
member is approved).

**One write per Bash call** is what the mixed-sequence row is for (design §2). A sequence whose
members are **all** ASK (`git add x && git commit -m m`) is one ASK — one prompt, not two;
the rule takes noise out of the prompt, it does not multiply prompts. A **pipeline** is
one command, judged by its members and never split: `./run-review.sh --self x 2>&1 | tail
-25` is ASK for the runner it starts with, and a pipe into an interpreter is still the
deny it always was. A `&` is a job, not a sequence, and is not eligible either.

**Not rewritable, and therefore ASK.** A `..` in a token that is not a path
(`git diff main...HEAD` carries no `..` component); a CR or a NUL; an environment prefix
(`X=1 make`); a command's output captured to a file (`pytest > out.log`, `cat a > b`,
`cmd | tee log`); a path outside the root; a whole-argument `$(…)`, the documented
exemption above — there is no literal to inline, so the human judges it. Each prints
nothing, exactly as before.

### A file authored through the shell

**Added 2026-09-21** (`../self/features/shell-write-rewrite/`). `CONVENTIONS.md` →
"Shell commands" (its last table row and the "Handed to the human" paragraph) says to author files with the Write and Edit tools and never by shelling
out, because a write made by a subprocess gets past the repo's `Edit` allow and deny rules
and leaves the generic Bash approval as the only check. Nothing enforced it:
`cat >> tests/test_x.py <<'EOF' … EOF` was read as a write and returned ASK, which printed
nothing, and the model learned nothing. The shape always has a rewrite, so by the
membership test above it is a REWRITE. A member **authors a file through the shell** when
content written in the command itself lands in a file:

| Spelling | Example | Not this |
|---|---|---|
| `echo` or `printf` with its output redirected to a path — `>`, `>>`, `>\|`, `N>`, `&>`, `&>>`, attached or separate, anywhere among the words | `echo x > f`, `echo a>f`, `> f echo x` | `echo x 2>&1`, `echo x >&2`, `echo "a > b"`, `echo x > /dev/null` |
| `cat` or `tee` fed literally — a heredoc or herestring on the member, or for `tee` a pipe from `echo`/`printf` or a heredoc-fed `cat` — with output to a path (a redirect, or a file operand of `tee`) | `cat > f <<'EOF'`, `tee f <<'EOF'`, `cat <<< x > f`, `echo x \| tee f` | `cat a > b`, `cmd \| tee log`, `git commit -m "$(cat <<'EOF' … EOF)"` |
| `sed` editing in place — `-i` in any single-dash spelling (`-i`, `-i.bak`, `-Ei`, `-ni`, `-i ''`) or `--in-place[=…]` | `sed -i 's/a/b/' f` | `sed -n 5p f`, `sed 's/a/b/' f` |

A path is any redirect target except `NON_FILE_TARGETS` (`/dev/null`, `/dev/stdout`,
`/dev/stderr`, `/dev/tty`); an fd duplication and a process substitution (`>(…)`) are not
targets at all. **Where the file is does not matter**: the scratchpad, the root and `/tmp`
are all denied, because the Write tool reaches all three and is checked against the rules
the shell write bypasses. `cp`, `mv`, `touch`, `mkdir`, `rm` and `ln` stay ASK — none has
a Write/Edit rewrite that always works — and so does an interpreter script that writes
files (`python3 gen.py`), which is readable and runs by name.

**The reason** (`SHELL_AUTHORING_REWRITE_REASON`) names the member as written and gives
the rewrite: the Write tool for a new file or a whole rewrite, the Edit tool for a change
to an existing one — an append is an Edit anchored on the file's last lines — with the
*why* in one clause, since the session that prompted this knew the rule and broke it for
speed.

**Its own reader.** `opaque_segments` breaks at every `&` and `|`, so `2>&1`, `&> f` and
`>| f` come apart there; `redirect_members` reads the operators the way bash does, with
the same quote, backslash, backtick and `$(…)` tracking — a `>` inside quotes is text, and
a write inside a substitution is not judged. It hands back each member's words with the
redirects taken out, so `tee`'s file operand is never a heredoc delimiter or a redirect
target.

**Where it is judged.** In `command_verdict`, after `command_allowed` has declined and
**before** `opaque_deny_reason`, so `tee f <<'EOF'` — a heredoc into something other than
`cat`, and so the opaque deny before this — gets the Write reason rather than "write a
script to the scratchpad"; a heredoc into an interpreter (`python3 - <<EOF > f`) is still
the opaque deny. When a line carries a heredoc only the text before its first line break
is judged, the cut `segments_before_line_break` makes for the `cat` exemption: the body is
data, so a Markdown body full of `> quote` lines is never read as redirects. A `#` on the
judged text means the line is not judged, the guard every rewrite keeps, and a line whose
quotes are still open at the end is left to the unreadable shape. Only the members that
author a file are named: whatever else the line carries is judged when the model sends
what is left. It is a narrowing of ASK and never touches ALLOW — every case it fires on
printed nothing, or was the opaque deny, before it — and like every REWRITE it counts
toward `OPAQUE_REWRITE_ATTEMPTS`.

**The same two guards the three shape denies keep hold over all seven**: a line carrying a
heredoc, or one `never_judged` holds back — a `#` outside quotes anywhere (any `#` on a
line whose quotes never close), a `$'…'` escaping a quote —
is judged on the shapes above alone. A heredoc's body lines
and the text after a `#` are data, not a command line, so `cat <<'EOF' … cd x … EOF` is a
file being written and not a relative `cd`, and `ls src # X=/p; cat $X` is a comment and
not a variable the shell will expand. A deny must not fire on a guess about a body.

**And the reader every one of them depends on tracks both quotes.** `unquoted_index`
carried single-quote state only, so a `'` inside `"…"` opened a span it thought was
single-quoted and everything after it read as literal: `cat "'"$(pwd)/x` is a `$(…)` in a
path that fell through to a prompt instead of being denied. Both quotes are tracked now,
and only one of them hides anything — a `$`, a backtick and a `<<` stay **active** inside
double quotes, so the needle is still reported there; what the double-quote state is for
is knowing that the `'` inside it is an ordinary character.

### Escalation after N rewrites

A deny must not demand the same rewrite forever. The hook counts opaque commands per
caller: the first `OPAQUE_REWRITE_ATTEMPTS` (2) are denied with the rewrite reason, and
the next returns `permissionDecision: "ask"` with a reason saying the command is still
unreadable after two rewrites and is the human's call. **Any command the analysis can
read resets the count** — approved, merely refused, or denied for one of the three older
shapes alike — because each of those is the model demonstrating it can write something
this hook reads.

The counter is keyed on the payload's `session_id` **and** its `agent_id`. `agent_id` is
present only when the hook fires inside a subagent call (Claude Code hooks reference), and
a subagent's payload carries its *parent's* `session_id` — so without the pair a
delegate's rewrites would escalate its coordinator. A payload with no `session_id` has no
counter at all and is denied every time rather than ever reaching `ask`.

State is one file per key under `$TMPDIR/agenttooling-hook-state/`, named by a digest of
the key so nothing from the payload reaches the filesystem. A missing, empty, corrupt or
unwritable file counts as **zero**: this state may turn into neither a crash nor a deny,
and the safe direction of every failure here is another deny rather than an `ask`.

### Headless runners and the scratch directory

`plan-runner-lib.sh` exports two variables into the `claude -p` it launches, at that one
site (`RUNNER.md` → "The executor's environment"):

- **`AGENTTOOLING_HEADLESS=1`** — the escalation step prints **nothing** instead of `ask`.
  An `ask` is a question for a human and there is none at a terminal in a batch; falling
  through lets the runner's own non-interactive policy decide. The counter still advances,
  so the state is the same as an interactive session's.
- **`AGENTTOOLING_SCRATCH=<dir>`** — a per-pass directory (inside the run's capture
  directory, so the existing teardown removes it; the same launch passes `--add-dir` for
  it, without which `acceptEdits` would refuse the Write). `bash <scratch>/x.sh` and `python3
  [-B] <scratch>/x.py` are approved from it, like the harness's own entry points and for
  the same reason: it is the place the opaque deny tells the model to write a script.
  Resolved through symlinks, so a link out of the directory is not a script in it; the
  file must exist; and the same basename anywhere else, or any of it with
  the variable unset, is not approved. The script **may take arguments**, and each is
  checked like any other path — `token_confined` against the project root, or inside the
  scratch directory lexically *and* through its symlinks. Existence never decides that
  check, though: a relative, non-flag argument (including the value after `=` in
  `--out=../x`) is judged LEXICALLY first, against the project root or the scratch
  directory, whether or not anything is there yet — an argument may well be the script's
  own OUTPUT path, so "names nothing on disk" cannot be the reason it passes. A bare flag
  (`--flag`, `-v`) carries no path and needs no such check. So `bash <scratch>/x.sh
  src/a.py`, `… <scratch>/helper.sh`, `… new-output.txt` and `… --flag` are approved, and
  `… /etc/passwd`, `… ../x` (whether or not `../x` exists) and `… --out=../x` prompt. A
  flag BEFORE the script is not a script: `bash -x <scratch>/x.sh` prompts, since it
  changes how bash runs the file. This is the only rule in the file that reaches outside
  the project root.

### What is approved silently

A command is approved only when **every** subcommand (split on `&&`, `||`, `;`, `|`, `&`)
passes, against a cwd that starts at the payload's `cwd` and moves with each `cd` (a
chained `cd` only reaches this analysis when § What it denies declined to judge it):

- `cd` — one argument, absolute, resolving inside the root through symlinks.
- Every argument that is a path must resolve inside the root: absolute ones through
  symlinks; relative ones against the effective cwd, expanded as globs first, so
  `dir/*` is judged by what it will actually name. `--flag=value` and `key=value`
  carry their path in the value. A value that names nothing on disk is not a path.
- The program: a read-only program (`READ_ONLY_PROGRAMS`) with none of its writing,
  executing or symlink-following flags (`FORBIDDEN_FLAGS`, whole token or the part
  before `=`; `FORBIDDEN_SHORT_LETTERS`, any letter of a single-dash token, which also
  catches `-ni` and `-i.bak`); `sed` with only `-n`/`-E`/`-r` and a script matching
  *optional address or range, then `p`*, because `w` inside a script writes a file;
  `git` with a read-only subcommand and no `--output`, where `branch` takes only listing
  flags and `worktree` only `list` — and where the subcommand may sit behind the global
  LOCATION options `-C`, `--git-dir` and `--work-tree` (`git_location_args`; their values
  are path-checked by the rule above like any other argument, and no other flag in front
  of the subcommand is read past — see § The git shape), and only when the git directory
  it would use is the root checkout's own or a linked worktree's, never one planted in the
  tree (`read_uses_own_gitdir`, no git probe — § The git shape); a runner prefix
  (`RUNNER_PREFIXES`) — pytest, ruff and mypy **in their read-only forms**, which are
  exact-word allowlists (below), `npx playwright test`, and `npm run` for the named
  scripts only, since `npm run` executes whatever `package.json` says; or one of the
  harness's own entry points below.

#### The runners' allowlists

ruff, mypy and pytest — bare, as a path (`.venv/bin/ruff`) or as `python[3] -m <runner>` —
are approved only in the words `RUNNER_BARE_FLAGS`, `RUNNER_VALUE_FLAGS`,
`RUNNER_CONFIG_FLAGS` and `RUNNER_SHORT_BUNDLES` name (`runner_words`), matched **exactly,
word by word** (`../self/features/runner-write-allows/`). The first version was a denylist of
the flags known to write, and each of three audits found another: a flag that is not
listed is a flag this hook has not read, so it prompts.

- **Exact match.** No prefix is read as its flag, so an abbreviation prompts. mypy takes
  them (`--inst` runs as `--install-types`); pytest 9.1.1 does not, and an older one did.
- **Value flags** are listed as such: the value is the next word, or the `=` of a long
  flag, and starts with neither `-` nor `@`. An attached short value (`-kfoo`, `-n4`) is
  not a listed word and prompts.
- **Positionals** are files and node ids, already path-checked like every argument.
- **`@`.** Any word that starts with `@` is no approval, positional or value: mypy and
  pytest both read `@file` as a file of further arguments, which hides any flag.
- **A bare `--`, an unknown flag, `-`** prompt.
- **ruff** approves `check [flags] [paths]`, `format --check|--diff [flags] [paths]`,
  `version`, `rule <code>` and `--version`/`-h`; `clean` (deletes the cache), `server`,
  `analyze` and every other word prompt. Global flags come before or after the subcommand.
  `--config <value>` is approved only when the value names an **existing regular file inside
  the root** whose name, as written and as resolved, is one the tool **finds by itself**
  (`runner_config_file_ok`, `RUNNER_CONFIG_NAMES`: `pyproject.toml`, `ruff.toml`,
  `.ruff.toml` for ruff; `mypy.ini`, `.mypy.ini`, `pyproject.toml`, `setup.cfg` for mypy): an
  inline `--config 'fix = true'` is a TOML override that turns `fix` on, and `--config
  fix.toml` holding `fix = true` rewrote the file. mypy's `--config-file` is judged the same
  way (`cfg.ini` with `junit_xml` wrote XML, with `plugins` imported a module)
  (`self/features/hook-silent-allow-sweep/`, item 5).
- **Never listed, and so never approved:** `--fix`, `--fix-only`, `--unsafe-fixes`,
  `--add-noqa`, `--output-file`/`-o`, `--cache-dir`, `--watch` (ruff); `--python-executable`,
  `--junit-xml`, every `--*-report`, `--install-types`, `--cache-dir`, `--sqlite-cache`,
  `-c`/`--command` (mypy); `--basetemp`, `--junitxml`/`--junit-xml`, `--log-file*`,
  `--debug` (it writes a debug log to the next word, overwriting a test file given
  after it), `--resultlog`, `--pastebin`, `-o`/`--override-ini`, `-p`, `-c`, `--rootdir`,
  `--confcutdir`, `--pdb`, `--trace`, `-W`/`--pythonwarnings` (it imports the module named in
  the value's category field, so `-W ignore::antigravity.X` runs that module's import-time
  code) (pytest).
- **pytest's short letters bundle** (`-qx`, `-vv`) and `-r<chars>` over its report set
  are matched by `RUNNER_SHORT_BUNDLES`; the rest of its flags are in the two sets.

`npm run` and `npx playwright test` are as before: named scripts, no flag reading.

#### The harness's own entry points

The commands an executor runs to read the state of its own work. `gate.sh` and
`check-plans.sh` are matched by their **known spellings** relative to the root
(`ENTRY_GATE_SPELLINGS`: `self/gate.sh`, `plans/gate.sh`; `ENTRY_CHECK_PLANS_SPELLINGS`:
`check-plans.sh`, `agentTooling/check-plans.sh`), and only when the script path exists,
resolves inside the root and has **no symlink component below it** (`symlink_free_below`:
`inside` follows links, so a link to another in-root file would otherwise be the script).
A planted `x/gate.sh`, `./gate.sh` at the root or `x/check-plans.sh` carries the basename
and prompts (`self/features/hook-silent-allow-sweep/`, item 6). The
three Python scripts are **pinned** (`pinned_entry_dir`): the lexical path must be exactly
`<root>/<pin>/<script>`, an existing regular file, with no symlink component below the root
and a `realpath` equal to itself, where `<pin>` is the ONE analysis directory beside the
running hook (`hook_analysis_pins`, compared by realpath as `orchestrator_tooling_file`
pins): `analysis/` for a hook at `<root>/hooks/` (agentTooling's own checkout),
`agentTooling/analysis/` for one at `<root>/agentTooling/hooks/` (a consuming repo), and none
for a hook anywhere else. A basename on its own vouches for nothing: `python3
/tmp/report.py`, `python3 ../report.py`, a planted `x/report.py` or `dir/analysis/report.py`
inside the root, a planted copy at the *other* pinned directory (`agentTooling/analysis/` in
the standalone checkout, `analysis/` in a consuming repo), a symlinked `report.py` or one
reached through a symlinked `analysis/` all refuse, and so does one reached through a
symlink that leaves the tree.

**The token must carry a directory component.** `./check-plans.sh` and `self/gate.sh` are
approved; a bare `check-plans.sh` prompts, because bash resolves a word with no `/` along
`$PATH` rather than from the cwd — so the file this analysis found in the repo and the
program bash would run are two different things, and the one bash runs is whichever copy
`$PATH` names first.

| Approved | Held to |
|---|---|
| `gate.sh` | no arguments, or one level label |
| `check-plans.sh` | any arguments (they are `--self` and a slug), no symlink component below the root |
| `bash -n <files>` | only `-n`, at least one file |
| `shellcheck <files>` | no flags, at least one file |
| `python3 [-B] -m py_compile <files>` | at least one file |
| `python3 [-B] <…>/report.py` | at the pinned path, exactly `[--self] <slug>`, `[--self] --all`, `[--self] --rounds-md <slug>` or `[--self] --orchestration <slug>` (`report_shape`); `--arm-root` and `--checkout` prompt. `<root>/analysis/report.py` **requires `--self`**: without it the script writes `<root>/../plans/features/`, outside the root. `<root>/agentTooling/analysis/report.py` writes `<root>/plans/features/` either way |
| `python3 [-B] <…>/capture_planning.py` | at the pinned path, exactly `[--self] --list-sessions [--unclaimed] [--since <date>]` or `[--self] --list-subagents [--unclaimed] [--everywhere] [--since <date>] [--for <repo>/<slug>]` — options in any order, each at most once, a value no word starting `-` (`capture_listing_shape`) |
| `python3 [-B] <…>/manifest.py` | at the pinned path, exactly `[--self] [--orchestration] <slug> get <key>` — a slug matching the lifecycle's pattern, a key no word starting `-` (`manifest_get_shape`) |

Nothing else. `feature-start.sh`, `feature-close.sh`, `stamp-timing.sh`,
`capture_planning.py` in a capturing form, `manifest.py init` and `set-*`, `python3 -c`,
`bash <script>` without `-n` and every other script still prompt: each either freezes a
cost record, rewrites a manifest, moves a ref, or runs whatever it is handed.

**The two flag-reading rows are exact shapes, word by word, not searches**
(`../self/features/python-entry-exact/`). Searching the words for a `--list-` or a `get`
let argparse read something else: the last of a repeated option
(`manifest.py --orchestration A --orchestration get --orchestration=x set-window-to …` ran
`set-window-to`), a unique-prefix abbreviation (`--forc` is `--force`), a decoy value that
looks like a flag (`--since '--list- x'`). So any word the shape does not name, a repeat, a
`--x=y` spelling or a misplaced `--self` is no approval — it prompts — and the hook does not
try to emulate argparse. The three scripts' parsers also set `allow_abbrev=False`, as
defence in depth. `manifest.py get init` is a feature named `get` being initialized, and
fails the shape for its missing key.

This does **not** widen `python3`. The interpreter is approved only in front of
`-m py_compile` or one of those scripts, and every file argument is checked against the
root like any other path.

Refused outright, before any of that: `..` anywhere; a line break or NUL; a token
beginning with `~`; and, outside single quotes or a backslash, any of `< > $ \`` —
(each of these refusals is a REWRITE or an ASK above, never an approval; the refusal
itself is untouched, and only what is said about it changed) —
redirection, substitution. The harmless `2>&1`, `>/dev/null`, `2>/dev/null` and
`&>/dev/null` are stripped first. Unbalanced quotes refuse. A leftover punctuation token
that is not a recognised separator (`|&`, `;;`, `(`, `>&`) refuses.

Brace lists (`ls {src,tests}`, `cat src/{a,b}.py`) are expanded, not refused, when they
are simple. Every raw word of the command — split as bash splits it, quotes and
backslashes kept — that contains a brace must either be wholly single-quoted (bash reads
the brace literally) or carry no quote or backslash at all and consist only of simple
groups: `{` + comma-separated alternatives, at least one comma, no brace, whitespace,
quote, `$` or backtick inside, + `}`. The groups are removed in one pass and any brace
left over refuses, which is what refuses nesting (`{a,{b,c}}`), a comma-less `{a}`, and
`{}`. `..` is already refused, which covers sequence expressions (`{a..c}`). Each
subcommand is then checked twice with the same cwd: as its **literal** tokens, which keeps
a single-quoted `'{-a,-v}'` from approving `git branch`, and as its **expanded** words
(left to right, cartesian, as bash does), which checks every path and flag bash will
really see — so `cat {src/a.py,/etc/passwd}` and `sort -{r,o}x` refuse, and `cd {a,b}`
refuses for having two arguments. A token expanding to more than `MAX_BRACE_WORDS` (256)
words refuses, and an expanded word beginning with `~` refuses, since bash expands the
tilde after the braces.

### The orchestrator role

An orchestrator session spawns one implementer session per feature and builds nothing
itself (`../LIFECYCLE.md` → "Orchestrator and implementer sessions"), and its orchestration
record is the role: a session whose id is some record's fence `session` is an orchestrator
(`orchestrator_role.py`, above) — unless the record is a coordinator record (`"kind":
"coordinator"`), which is no role: a subagent's payload carries its parent's `session_id`
(with its own `agent_id`), so a coordinator whose delegates build features would otherwise
have every one of them denied (`self/tests/hook-orchestrator-role.sh` H10). That exemption
is earned by shape (`../self/features/hook-role-hardening/`, F1): a `coordinator` record whose
`features[]` carries a non-null `session` or `branch` — the orchestrator's `add-feature`
shape — is still a role, and every fence of the file is read, so an appended `{}` or
coordinator fence cannot shadow the real one (H11). An in-place rewrite of the one fence
(or deleting the record) is caught by the ledger `orchestration-start.sh` keeps in the git
directory, out of the Edit tool's reach (H13), and in a consuming repo put before a human
first by `wire-settings.py`'s ask rules on `plans/orchestrations/**` and the whole
vendored tree `agentTooling/**` (which covers the legacy `agentTooling/self/orchestrations/`). The scripts that build refuse in it themselves; the hook
is the early feedback, with the **same reason** (`refusal_reason`), and two denies that are
not about the shape of a command:

- **`Bash` — the orchestrator allowlist** (`../self/features/hook-role-hardening/`, security
  audit round 3; owner-approved). For an orchestrator session every Bash command is DENIED
  unless every command on the line — a pipeline, or a `&&` / `||` / `;` list — matches one
  of these shapes (`orchestrator_command_allowed`; the table is the `ORCHESTRATOR_*`
  constants in one block of `allow-repo-commands.sh`):

  | Shape | Allowed | Not allowed |
  |---|---|---|
  | readers | `ls`, `cat`, `head`, `tail`, `wc`, `grep`, `rg`, `find`, `sed -n '<N>p'` / `'<N>,<M>p'`, `stat`, `du`, `jq`, `diff`, `sort`, `uniq`, `cut`, `tr`, `date`, `pwd`, `echo`, `printf` over literal paths | `rg --pre`/`--hostname-bin`/`-z`/`--search-zip`; `find -exec`/`-execdir`/`-ok`/`-okdir`/`-delete`/`-fprint*`/`-fls`; `jq -f`/`--from-file`; `sort -o`/`--output`/`--compress-program`; `printf -v` in any spelling (a subscripted name is evaluated arithmetically, which runs a substitution; round 4); `uniq` with more than one operand (words after `--` counted, and the bare `-` is one); `date -s`/`--set`, or any `date` operand that is not a `+FORMAT` (`MMDDhhmm` sets the clock); `tail -f`/`-F`/`--follow`/`--pid`; `diff -l`/`--paginate` |
  | git reads | `status`, `log`, `diff`, `show`, `rev-parse`, `ls-files`; exactly `branch --show-current`, `remote -v`, `worktree list`, `fetch origin <branch>` | any global option before the subcommand (`-c`, `-C`, `--git-dir`, …) or `NAME=` prefix; `--ext-diff`, `--textconv`, `--output`, `--open-files-in-pager`, `--upload-pack`, `--receive-pack`, `--exec`, `--run`, `--show-signature` by any unique prefix, `-O` in a short cluster, a `%G` format; every other subcommand (`git grep` included) |
  | git writes | `add <files>` — each an existing regular file, no symlink, no leading `:`, no glob character, no `.git` component; `commit -m "<literal>"` or `-m "$(cat <<'EOF' … EOF)"`; `push -u origin <branch>`, the branch's name written out — the push rules below still apply; `mv <tooling>/self/orchestrations/<slug> plans/orchestrations/<slug>` — the move `shared_rules.LEGACY_RECORD_REFUSAL` names, of the session's OWN record (`orchestrator_record_move`): a vendored copy, run from the consuming repo's root, the source the directory holding the record that names the session (the record's path as the role lookup returned it, no symlink on it), the destination not yet there and its parents no symlink; and, read at judgment time (`orchestrator_stranded_own_record`, `../self/features/orchestrator-record-move-guard/`: the role lookup's slug can come from the ledger alone, which reads no record), the source's `README.md` a regular file, no symlink, naming this session as an orchestrator (`orchestrator_role.names_role`, the payload's `session_id` threaded through), and the record stranded — the consuming repo's own, not agentTooling's shipped one nor an ambiguous one — by `analysis/roots.py`'s `legacy_record_claim`, asked through `<python> -B -E -s <tooling>/analysis/roots.py stranded <slug>` (exit 0; the hook imports nothing from `analysis/`; a missing or symlinked classifier, another exit, a timeout of `ORCHESTRATOR_MOVE_CLASSIFIER_TIMEOUT_SECONDS` or any failure is no approval); alone on the line, or after exactly `mkdir -p plans/orchestrations && ` (`shared_rules.LEGACY_RECORD_MKDIR`: the printed remedy, since git tracks no empty directory), it is APPROVED outright (`ORCHESTRATOR_MOVE_REASON`, `../self/features/orchestration-start-branch-v2/`) | options on `add`/`commit`/`push`/`mv`; any other `mv` — another record, another file or destination, a third word, another cwd, a standalone checkout's records, a symlinked `plans` or `plans/orchestrations`, a record README that is a symlink, a folder whose README is missing or names another session, a record that is not stranded; the move itself on any line that is not it alone or behind that one lead (piped, doubled, chained with a read: `orchestrator_git_allowed` denies every `git mv` it is handed, `own-push-transport-keys`'s orchestrator addendum); any other `mkdir`, or that one joined by anything but `&&`; a `<branch>` (push or fetch) outside `^[A-Za-z0-9][A-Za-z0-9._/-]*$` or holding `..` — no `+`, `:`, glob or refspec; an unquoted heredoc delimiter, text after its terminator, a delimiter line inside its body |
  | gh | `pr create --title … --body …` (literal or the quoted heredoc), `pr view`, `pr list`, `pr checks` | every other `gh` command; `--web`, `--watch`, `-R`/`--repo` |
  | entry points | THIS checkout's own `orchestration-start.sh` and `orchestration-capture.sh` (spelled `./…` relative to the cwd), `python3 [-B] <its analysis/manifest.py> [--self] --orchestration <slug> get|set-window-to <one operand>` or `add-feature|set-feature <operands…>`, `<its analysis/report.py> [--self] --orchestration <slug> [--checkout <value>]…` (`--self` only as the first argument, `ORCHESTRATOR_SELF_FLAG`: agentTooling's own records, `../self/features/orchestration-records-in-repo/`), `<its analysis/capture_planning.py>` in the plain session's exact listing shape (`capture_listing_shape`, above) | a word that is itself a symlink, or a script that does not resolve (`realpath` against the cwd) to the hook's own tooling directory — a planted `analysis/report.py` at a consuming repo's root or in a records folder; `orchestration-start.sh --session`; a report slug that is not a slug, `--self` without `--orchestration` or anywhere but first, `--all`; any word starting `-` after the manifest scope's slug or as a `--checkout` value — a repeated `--orchestration`, `--orchestration=…` (`../self/features/python-entry-exact/`); a `--` word, a repeat, an abbreviation or any unlisted option to capture_planning.py |

  Every word must be a plain literal: single quotes are literal, double quotes may hold no
  `$`, backtick or backslash, and outside quotes a word holds no `$`, backtick, glob, brace,
  backslash, `<`, `>`, `(`, `)`, `&`, `#`, starts with no `~` or `!`, and no command starts
  with a `NAME=` assignment; the only redirects are `2>&1` and `> /dev/null`. The
  expansions the tokenizer reads — a quoted-delimiter heredoc substitution as the commit
  message or PR title/body, and `"$(git branch --show-current)"` in the pushed branch's
  place (admitted here, but no documented push: the push rules judge the words, so the
  cloud refuses that spelling as a push of another ref, and the push to write is `git push
  -u origin <branch>` with the name written out, `../CONVENTIONS.md` → "Approved silently")
  — are recognised by
  the tokenizer itself, only where an unquoted `"` begins a fresh word and the closing `)"`
  ends it (security audit round 3, R1: a search of the raw line was blind to quoting, so one
  could hide inside single quotes or be glued to a word) — and the heredoc's body ends only at
  a line holding the delimiter alone with the `)"` on the very next line
  (`heredoc_argument_at(…, strict=True)`; hook-audit-gaps, B1: `EOF)" ; ./feature-start.sh zz ;
  echo "⏎EOF⏎)"` is not a message but a command, and is denied with the role reason) —
  and stand as one per-call random
  token, valid only in those positions. A line past `ORCHESTRATOR_MAX_LINE_CHARS` is refused
  unread. A command that
  matches goes on to every judge below exactly like any command (the git push rules, the
  shape denies, the approval); anything else is denied with the role's reason
  (`refusal_reason`) and the list (`ORCHESTRATOR_ALLOWLIST_TEXT`): an orchestrator hands other
  work to a SEPARATE session (`create_session`, or `send_message` to an implementer) or to the
  human. An in-process subagent is no way out (round 3, R8): its payload carries this
  session's id, so it has the Read, Grep and Edit tools but this same Bash list — and exempting
  a subagent's `agent_id` would reopen a delegated build. This replaces the name matching that rounds 1–2
  hardened and that could not close indirection naming no build script (round 2's N2, N3,
  N5, N6, N7): an allowlist closes those by construction. **Other sessions are unchanged** —
  `self/tests/hook-orchestrator-role.sh` H20 runs round 2's 133-command regression set through
  this hook and `origin/main`'s and requires byte-identical answers.

  **What the name matching still does**: `invokes_build_script` and `build_script_denial`
  are kept for one case — a checkout whose role cannot be read (`LEDGER_UNREADABLE`: a
  `.git` that does not resolve, an unreadable ledger, git unavailable or past its deadline)
  and no source names the session (round 3, R4: every source is asked, and one that names
  the session wins over one that cannot be read). There no session
  can be shown not to be an orchestrator, and every session is refused BUILDING — a line that
  names, or may expand to, a build script — with the unreadable reason, and nothing else; the
  allowlist is not applied, so a broken `.git` never locks a session out of ordinary
  commands. Its reading (literal names in non-exempt commands, patterns where a program
  launches, the exempt readers/git/gh/`sed -n`/`bash -n`, the parked heredoc body) is as
  rounds 1–2 left it, with three closures from hook-audit-gaps (round 14's audit): a comment is
  not read, so an apostrophe in one hides nothing (A); the line is judged with every line
  continuation deleted AND as it was written, a run when either reading is one (round 2:
  bash deletes no continuation inside a comment, so `ls # x \⏎./run-plans.sh` runs the
  script, and deleting first hid it in the comment — the audit's E2; a comment in doubt,
  `a=(x)#b; ./run-plans.sh`, is read both ways as on the git deny — E3), a line that does not
  lex is scanned for patterns as well as names (unless
  it holds a heredoc), and an exempt reader piped into a launcher counts a pattern as a name
  (`ls run-p*.sh | sh`) (B); and, because the launcher denylist can never be complete
  (`unshare`, `setpriv`, `prlimit`, awk's `system()`, sed's `e`, `git -c alias.x=!…`), **a
  pattern for a build script in any blank-separated piece of any argument of a non-exempt
  command is a run** (`mentions_build_script_pattern`) (C). Phase 3 added a fourth and
  closed the neighbours its self-audit found. **A file an input redirect feeds a command**
  (`bash < run-plans.sh`, `<>`, `N<`, glued or quoted, before the program or after it;
  `fed_files`) is read like a name in an exempt reader: text to `cat < run-plans.sh`, and a
  run — with the deny the piped script gets, `cat run-plans.sh | bash` — once the line holds
  a command that may launch. Beside a reader that names a build script, **every command that
  is neither exempt nor a plain filter** counts as that launcher, since the list is no more
  complete after a pipe (`cat run-plans.sh | unshare sh`, `| ash`; the filters are
  `BUILD_SCRIPT_FILTERS` — `sort` without `--compress-program`, `uniq`, `cut`, `tr`, `tee`,
  named bare). A bracket expression is read as `?` (`./run-plans.s[^x]`, `[[:alpha:]]`:
  fnmatch knows neither); the words of a line that does not lex end at operators as well as
  blanks (`true;./run-p*.sh;true # '`); the value of an environment assignment is read for a
  pattern (`GIT_EDITOR='./run-p*.sh' git commit`: the shell git hands it to expands it); and
  git's exec flags are refused abbreviated or clustered too (`git grep --open=…`, `-nO…`,
  `git push --receive=…`). The cost, on this path only: a
  bare glob handed to a non-exempt command (`cp * dest`, `tar -cf x.tar *.sh`, `jq . *`) could
  expand to a build script's name and is refused with the role reason; a glob with a
  directory or a suffix that is no build script's (`*/report.json`, `tests/*.py`) is not; a
  line that names a build script in a reader and also runs any other non-filter command is
  refused (`wc -l run-plans.sh && pytest`: send the two separately); `bash -n <
  run-plans.sh` is refused (`bash -n run-plans.sh`, with the file named, is the exempt form);
  and `VAR=<glob> cmd` is refused when the glob could expand to a build script's name. Each
  of these was a prompt before. `bash -n` is approved only as exactly `-n` and paths for every
  session (`files_only` refuses any `-` or `+` word: `+n`, `+o noexec` run the file; N1).
- **`Agent`** — denied when the session is an orchestrator and `tool_input.prompt` is a
  string whose first non-empty line is a `feature: <repo>/<slug>` header, the first line of
  every implementer brief (`../ORCHESTRATION.md` → Rules). It is read by
  `brief_header.parse`, the same parse the brief-header rule below reads, so a header behind
  leading blank lines is caught and `feature: none — <reason>` — an orchestrator's own
  analysis delegate — is not a build and passes. When `brief_header.py` is missing the
  check falls back to a prompt that **starts with** `BUILD_BRIEF_MARKER` (`feature: `). A
  prompt that mentions it mid-text, has no prompt or has a non-string one is not this deny;
  nor is a session that is no orchestrator. On `Agent` the hook never prints an `allow`.

**What stays allowed in an orchestrator session**: in Bash, the allowlist above and nothing
else (its records commit, push and PR among it; H15); every tool that is not Bash; and a
delegate whose brief is not a feature brief. The record lookup runs once per Bash call — every
Bash call now, for every session, since the allowlist needs the role before anything else
(one `os.listdir` and ONE `git log -m --diff-filter=A -p` per records root, each under a
3 s deadline; round 3, R6) — and
for an `Agent` call only when the prompt carries the marker, and only when the payload has a
`session_id`; it reads THIS checkout's `self/orchestrations/` (the
hook's own grandparent directory) and, when that directory is a vendored copy (no `.git` of its
own), its consuming repo's `plans/orchestrations/` (that directory's parent) — working tree and
history alike — so an orchestrator whose record lives in another
repository's agentTooling copy is not refused here (`../self/BACKLOG.md`) — the scripts in
that copy still refuse. The hook never exits non-zero. **The one rule lives in
`orchestrator_role.py`**; `plan-runner-roots.sh` reads it through the CLI, and
`self/tests/hook-orchestrator-role.sh` holds the cases under both profiles and both shapes
(a consuming repo, agentTooling's own).

### The brief header

On `Agent`, after the orchestrator role's deny and only when it did not fire, the hook
judges the brief itself (`../self/features/delegate-cost-claims/`): a `tool_input.prompt`
string whose first non-empty line is not a brief header (`brief_header.parse` is `None`) is
**denied** — a REWRITE-style send-back whose reason, `BRIEF_HEADER_DENY_TEMPLATE`, names the
line to put first (`feature: <repo>/<slug>`, or `feature: none — <reason>`) and why: cost
attribution claims a delegate by that line (`../CONVENTIONS.md` → "Delegate briefs",
`../analysis/README.md` → "The brief header"). Any session, either profile; a call with no
prompt or a non-string one is not judged, a headed brief prints nothing, and the hook never
prints an `allow` on `Agent`. No escalation counter: the fix is always the one line. It
reaches a session because `wire-settings.py`'s `HOOK_MATCHERS` already wires the hook for
`Agent` (a consuming repo gets the entry on its next `sync-plans.sh`). The orchestrator's
deny goes first and reads the same single parse, so an orchestrator's `feature:
<repo>/<slug>` brief is refused with the role's reason and its `feature: none — <reason>`
brief prints nothing. `self/tests/hook-brief-header.sh` holds the cases under both profiles
and both shapes; `self/tests/hook-orchestrator-role.sh` H9 holds the two orchestrator ones.

## What the audit found and closed

Each of these approved something in the first version. All are now refused and asserted
in `self/tests/allow-repo-commands.sh`:

| Bypass | Was |
|---|---|
| `cat $HOME/.ssh/id_rsa` | `$` never rejected; a relative-looking token skipped the path check |
| `sort --output=~/.zshrc f`, `git log --output=…`, `pytest --junit-xml=/tmp/x` | `--flag=value` never split |
| `sed -i.bak`, `sed -ni`, `sort -o/tmp/x` | short flags matched as whole tokens only |
| `sed 's/a/b/w ~/.zshrc' f` | sed's `w` command writes from inside the script |
| `git branch -D main`, `git branch new` | `branch` allowlisted wholesale |
| `rg --pre 'sh -c …'`, `sort --compress-program=…` | exec-through flags not forbidden |
| `cat {/etc/passwd,}` | brace expansion produced a path the checker never saw; now expanded and each word checked |
| `ls \|& sh` | `\|&` is not a separator, so `sh` hid inside the `ls` group |
| `ls x#; rm -rf src` | shlex starts a comment at any `#`, bash only at a word's start, so the `rm` was never lexed; shlex comments are now off |
| `cat link-out/.zshrc`, `head dir/*` | relative paths and globs never resolved through symlinks |
| `grep -R`, `find -L`, `rg -L` | symlink-following recursion reads outside the tree |
| `tree -o f`, `uniq in out`, `npm run <any>`, `npx playwright install` | allowlist too wide |
| `ls > /dev/nullx` | redirect stripped by substring, not whole word |
| `ls <NUL>` | bash truncates at NUL; the analysis read past it |

### The second audit (2026-09-17)

Run against the analysis as it stood with the three denies in place. Each row was tried
against the real hook with a crafted payload before it was called a bypass; each is now
refused and asserted in `self/tests/allow-repo-commands.sh`, beside the near-miss that
must stay **approved**, so a closure that over-reached fails there.

| Bypass | Was | Guard beside it |
|---|---|---|
| `X=/tmp/e/pytest src/a.py` — an env prefix executes `src/a.py` | `program_name()` took the basename of the *assignment* word, so the hook read the next word as an argument to an allowlisted runner while bash read it as the program. An assignment at command position is now refused outright. | `X=1 make`, `FOO=1 ls` still prompt |
| `grep -f/etc/hosts src`, `file -m/etc/hosts README.md`, `rg -f/etc/hosts src` — a read outside the tree | `value_confined` returns True for any token starting with `-`, and where an attached option value begins is the program's business. A flag with no `=` that carries a `/` is now refused outright. | `ls -- src`, `git log --oneline -5`, `--flag=path` (still split and checked) |
| `ls -RL .`, `du -L .`, `du --dereference .` — lists or sizes every file under whatever an in-tree symlink points at | neither reader had a `FORBIDDEN_SHORT_LETTERS` entry; `find -L` and `grep -R` did | `ls -la src`, `du -sh .venv`, `grep -d recurse` (= `-r`, which does not follow) |
| `rg --hostname-bin=id x src`, `rg -z x src` | both run an external program — a hostname binary, a decompressor off `PATH` — like `--pre`, which was already forbidden | `rg -n pattern src` |
| `git show --textconv`, `git diff --ext-diff`, `git blame --textconv` | run whatever the repo's own config names for them | `git log --format=%x41`, `--pretty=format:%H` (formatting only) |
| `ruff check --fix src`, `ruff format src`, `mypy --install-types` — a write and an install | runner prefixes were matched and never inspected. "Repo code runs" covers a suite executing what the repo contains, not a linter rewriting it. A denylist and the `ruff format` report-flag rule closed it; the denylist was replaced by the runners' allowlists (the runner-write audit below). | `ruff format --check src`, `ruff format --diff src`, `ruff check src`, `python -m ruff check src` |
| `capture_planning.py --list-sessions --force` | not reachable to a write today (a listing mode exits first), but `--force` is what makes a capture overwrite a frozen record and a reader should not have to reason about argparse's ordering. Tightened into `CAPTURE_WRITING_FLAGS` — since replaced by the exact listing shape (below). | the other listing forms |

### The propagation audit (2026-11-16)

humanNetworkMap's audit of agentTooling `df98316` found two silent approvals of a write in
`python_entry_allowed`, both from reading flags by search rather than by shape. Closed by
`../self/features/python-entry-exact/`; asserted in `self/tests/allow-repo-commands.sh`
(both profiles) and `self/tests/hook-orchestrator-role.sh` H27 (the orchestrator role).

| Bypass | Was | Guard beside it |
|---|---|---|
| B1: `manifest.py --orchestration A --orchestration get --orchestration=orch-test set-window-to …` | the second positional was `get`, but argparse keeps the last `--orchestration` and ran `set-window-to` on another record's fence; the orchestrator's allowlist checked only the first word | `manifest.py [--self] [--orchestration] <slug> get <key>`, the record tool's four subcommands |
| B2: `capture_planning.py <slug> --forc --since '--list- x'`, `… --al --recapture --since '--list- x'` | a `--list-` prefix anywhere approved, and `CAPTURE_WRITING_FLAGS` matched whole words only, so an abbreviation of `--force`/`--all` passed beside a decoy value; `--force` overwrites `planning.json` with $0.00 | every documented listing form |

### The runner-write audit (2026-11-16)

An independent audit of #147 found silent approvals of writes in the runner allowlist and
in `python_entry_allowed`; main had the same holes. Each row was reproduced against the real
tool in a throwaway copy before it was called a bypass (ruff 0.16.9, mypy 2.3.1, pytest
9.1.1; the results are in `../self/features/runner-write-allows/NOTES.md` → Build log).
Closed by `../self/features/runner-write-allows/`; asserted in
`self/tests/allow-repo-commands.sh` (both profiles) beside the read forms that must stay
approved (`RUNNER_READ_ALLOW`, `RUNNER_WRITE_PROMPT`).

| Bypass | Was | Guard beside it |
|---|---|---|
| F1: `ruff check --config 'fix = true' f.py`, `--config fix=true`, `ruff --config 'fix = true' check f.py` — rewrites the file | an inline `--config` is a TOML override and `RUNNER_FORBIDDEN_FLAGS` did not list it; `--fix` was forbidden by name, `fix = true` by value was not | `--config`/`--config-file` approved only for an existing regular file inside the root (`runner_config_file_ok`); `ruff check --config pyproject.toml src` |
| F2: `ruff check --add-noqa f.py` — appends `# noqa` to the source | not in the denylist | `--add-noqa`, like `--fix`, is not in `RUNNER_BARE_FLAGS`; `ruff check src` |
| F3: `mypy --python-executable <file>` (space and `=`) — runs the file | not in the denylist | not in the mypy allowlist; `mypy src/a.py` |
| F4: ruff `--output-file X`/`-o X` (with `--show-settings` too); mypy `--junit-xml X` and every `--*-report DIR` — each creates the file | the denylist named three ruff flags and one mypy flag | none of them is an allowlisted word; `ruff check --output-format concise src`, `mypy --show-error-codes src` |
| F5: mypy `--install-type`, `--inst` — abbreviations of `--install-types`; `mypy @args.txt` with `--junit-xml` inside | the denylist matched whole words and `argparse` takes any unique prefix; an `@file` is a file of further arguments | exact words only (no prefix is a flag); any word starting `@` prompts. pytest reads `@file` too |
| F6: pytest `--basetemp`, `--junitxml`/`--junit-xml`, `--log-file`, `--debug` (writes to the **next word** — it overwrote the test file given after it), `--resultlog`, `--pastebin`, `-o`/`--override-ini` (`cache_dir`, `log_file`, `addopts=--junitxml=…`), `-p` and `-c` | pytest had no allowlist and no denylist | the pytest allowlist; `pytest -q tests/x.py`, `-k`, `-m`, `--tb`, `-rA`, `-n 4` |
| F7: `python3 analysis/report.py <slug>` in the standalone checkout — writes `report.md`/`report.json` into `<root>/../plans/features/<slug>/`, outside the root | any arguments were approved, and `--self` is what points the script at `<root>/self/features/` | `<root>/analysis/report.py` needs `--self`; `report_shape` is exact; `<root>/agentTooling/analysis/report.py` (which writes inside the root either way) does not |
| F9: a planted `x/report.py` or `dir/analysis/report.py`, a symlinked `report.py`, a `report.py` reached through a symlinked `analysis/` — approved by basename plus `inside()`, which follows links | `entry_script` matched the basename and resolved with `realpath` | `pinned_entry_dir`: the lexical path equals `<root>/analysis/<script>` or `<root>/agentTooling/analysis/<script>`, no symlink component below the root (`symlink_free_below`, which `gate.sh` and `check-plans.sh` get too). The orchestrator's `orchestrator_tooling_file` already pins to this hook's own tooling file and takes `report.py` only as `[--self] --orchestration <slug>`, so it approves nothing the main path now refuses |
| B1: `pytest -W 'ignore::antigravity.X' tests/x.py`, `python3 -m pytest -W ignore::this.X …` — pytest imports the module named in the category field, so its import-time code runs (`antigravity` starts a browser) | `-W` was in the pytest value-flag allowlist | `-W` (and `--pythonwarnings`) is not an allowlisted word and prompts; no parser for its value; `pytest -q tests/x.py`, `-k`, `-m` |
| F10: `-B` was documented as suppressing `py_compile`'s `.pyc` | a wrong description: the `.pyc` is written either way | the "Considered and not a bypass" row is corrected and the write is listed under "Tool caches" below |

F12 (`capture_planning.py --list-sessions … && make` went from a deny to a prompt) is a
prompt on a form the human must judge anyway, and was recorded only.

### Considered and not a bypass

Each was tried; none is. They are here so the next audit does not re-derive them.

| Candidate | Why it is safe |
|---|---|
| an env prefix that changes behaviour (`PAGER=… git log`, `GIT_DIR=`, `PYTHONPATH=`, `LD_PRELOAD=`, `IFS=`) | `subcommand_allowed` refuses any assignment at command position, whatever the name (asserted by `FOO=1 ls` and the `X=/tmp/e/pytest` cases) |
| `grep -d recurse`, `grep --directories=recurse` | the same as `-r`, which does not follow symlinks; `-R`/`--dereference-recursive` does and is forbidden. `grep -D recurse` is a *devices* action, not recursion. |
| `find -H`, `find -P` | `-H` follows only a **command-line** symlink, and every argument is path-checked through `realpath` already; `-L`/`-follow` are forbidden |
| `du --files0-from=…`, `wc --files0-from=…`, `sort --files0-from=…`, `find -newer …`, `grep --file=…`, `git blame --contents=…`, `git diff --no-index …` | the outside path is a token or a `--flag=value`, and the path check refuses it |
| `git grep --open-files-in-pager` | `grep` is not in `GIT_READ_ONLY_SUBCOMMANDS`, so the flag is unreachable |
| `git -c core.pager=…`, `--exec-path=…`, `--config-env=…`, `--namespace=…` | none names a location this analysis can confine, so none is in `GIT_GLOBAL_LOCATION_OPTIONS`; `git_location_args` stops at the first unlisted flag and `git_allowed` then reads it as the subcommand, which matches nothing. Every spelling prompts. (`--git-dir` and `-C` no longer do when their value is inside the root — see "The git shape".) |
| `sed`'s `e`, `w`, `W`, `r`, `s///w`, a newline in the script, `--expression`, `-s`, `--` | none can match `SED_PRINT_SCRIPT_RE`; a newline anywhere is already `UNANALYSABLE`; the flags are not in `SED_ALLOWED_FLAGS` |
| `python3 -m py_compile <symlink out>` | every file argument is path-checked through `realpath` like any other |
| `python3 [-B] -m py_compile <file>` leaves a `__pycache__` | a write, confined to the root, and the check's own output. `-B` does **not** suppress it (`py_compile` writes the `.pyc` itself, checked on 3.13); it is listed under "Tool caches" in the accepted limits |
| process substitution `<(…)` | `<` is a shell-active character outside single quotes |
| a `\` line continuation | the literal newline it leaves is in `UNANALYSABLE` |
| a token after `--` | `flag_forbidden` still fires on it, conservatively: `grep -- -R x src` prompts |
| a NUL byte, a unicode look-alike for `/` | NUL is `UNANALYSABLE`; a homoglyph is not `os.sep`, so it can only fail to resolve and name nothing |
| `cat {src,link-home}/a.py` | the expansion names nothing on disk, and a file that does not exist cannot be read |
| `cat -`, `tail -F`, `pytest --pdb`, `npx playwright test --ui` | these block rather than escape: the agent's own Bash call hangs, which is a cost to it and not a read, write or exec outside the tree |
| `rg --search-zip`'s decompressor, `git`'s configured `textconv` | both need a planted file or a planted `PATH` entry first, which is the accepted limit below — and both are forbidden anyway |

### The `wire-settings.py` gap

`bash_deny_rules()` renders command **prefixes**, and the hook reads relations and
shapes, so two things the hook denies have no prefix twin and cannot get one:

- **The run-time-value deny** — a relation between two tokens anywhere on the line.
- **The opaque deny** — a shape, not a prefix; `python3 -c` is a prefix but a heredoc,
  a pipe into an interpreter and a `$(…)` inside a path are not.

In each case the hook is the whole of the enforcement, and `permissions.deny` is the
visible half of only what a prefix can say.

What used to be a third entry here — `git worktree move|lock|unlock|repair` and
`git branch --delete|--move`, which a prefix rule *can* express and which
`permissions.deny` did not name — was the drift `policy.py` closed. There is no fixable
half left: the table renders one rule per mutating entry, and
`self/tests/policy-table.sh` fails if it ever stops.

## Accepted limits

- **Repo code runs.** pytest, ruff, playwright and the `npm run` scripts execute what the
  repo contains. That is what "run the tests" means; a change to that code is a write,
  which this hook never approves — the runners' allowlists (`RUNNER_BARE_FLAGS`,
  `RUNNER_VALUE_FLAGS`, `RUNNER_CONFIG_FLAGS`) and the `ruff format` rule are where that
  line is drawn. What the repo's own config asks a run to write (`addopts` with
  `--junitxml`, `[tool.mypy] junit_xml`) is the repo's, and editing that config is a write.
- **Tool caches.** The approved read forms write their own bookkeeping at the tool's
  default place: `.ruff_cache`, `.mypy_cache`, `.pytest_cache`, and `__pycache__/*.pyc`
  from `py_compile` (`-B` does not stop it). Each is confined to the root and is not
  something the command line chose. Every flag that moves a cache (`--cache-dir`,
  `-o cache_dir=`, `--cache-clear`, `ruff clean`) is outside the allowlists and prompts.
- **A command may hang.** `cat -`, `tail -F`, `pytest --pdb` and `npx playwright test
  --ui` are approved and block. The cost is the agent's own Bash call, not a read, a
  write or an exec outside the tree, so they are not the hook's problem.
- **A planted file needs a prior write.** An unquoted glob that expands to `-delete`, a
  look-alike `python` symlink inside the tree, a `.git/config` that points `diff.external`
  at a command — each requires a file to exist first, and creating it prompts.
- **Conservative false negatives.** A grep pattern that looks like an absolute path
  outside the tree (`grep '/usr/lib' src`) prompts. So does `~` anywhere a token starts,
  `..` anywhere at all, and any `$` outside single quotes even when escaped inside double
  quotes. The cost of each is one prompt.
- **`||` short-circuit.** The effective cwd after `cd A || cd B` is taken as `B`. Every
  `cd` target is inside the root regardless, so the approximation only affects which
  inside directory relative arguments are resolved against.

## The deny rules

`wire-settings.py` also maintains two sets of rules in `permissions.deny`, which binds in
every permission mode and cannot be overridden by a mode or an allow rule, and one rule
in `permissions.ask`, which is evaluated before any allow rule and forces a prompt.

### `Edit`

`--permission-mode acceptEdits` — which the batch runners use — accepts every Edit-tool
write under the working directory, unattended. So:

```
Edit(/.git/**)      Edit(**/.git/**)     Edit(**/.git)
Edit(/.claude/**)   Edit(**/.claude/**)
Edit(**/.venv/**)   Edit(**/venv/**)     Edit(**/node_modules/**)
```

`.git/hooks/*` is executable code; `.claude/` is the permission system itself; and the
dependency trees are code that runs on the next test. The `**/`
forms match at any depth, so a worktree's copies are covered; the two root-anchored forms
are insurance for the two that matter most. Deny rules reach the Edit and Write tools and
`> file` redirects,
not a subprocess that opens a file itself — which is also why `sync-plans.sh` can still
write `.claude/settings.json` through this helper. OS-level enforcement is the sandbox
block (below), which binds the subprocess too once its `SANDBOX_ENABLED` switch is on — it
is off today.

**The policy is an `ask` rule, not a deny**, and it is the one rule whose spelling depends
on the mode:

```
permissions.ask:
Edit(**/agentTooling/**)                             # consumer: the whole vendored tree
Edit(**/plans/orchestrations/**)                     # consumer: the repo's own records
Edit(**/hooks/**)   Edit(/hooks/**)                  # under --self
```

**Why the consumer rule covers the whole vendored tree**
(`../self/features/vendored-edit-ask/`, finding B1 of humanNetworkMap's audit of
agentTooling PR 141): the orchestrator allowlist above runs vendored entry points with no
prompt — `analysis/report.py`, `analysis/manifest.py`, `orchestration-start.sh`,
`orchestration-capture.sh` and the `plan-runner-roots.sh` / `plan-runner-lib.sh` they source
— so an Edit or Write to any of them (an Edit rule covers both tools) is code that then runs
silently, and an ask rule limited to `hooks/` left that hole open under `acceptEdits`. A
per-file rule would have to follow every entry point the allowlist ever gains; the tree-wide
one does not. Vendored code is never edited in a consuming repo: it changes only by
`git subtree pull` (`update.sh`), which writes through git, not the Edit tool, so the rule
never fires on the sanctioned path, and no lifecycle step writes under `agentTooling/` through
the Edit tool (records live in `plans/orchestrations/`, manifests, briefs and notes in
`plans/features/`, seeded files in `plans/`). A subprocess write to a vendored file is not
the Edit rule's business: the hook sends back a shell-authored file, and the sandbox is the
remaining layer. `--self` is unchanged — in agentTooling's own checkout agentTooling IS the repo
and is edited normally, so only `hooks/` is asked.

The orchestration records are asked about for the same reason
(`../self/features/hook-role-hardening/`, F1): a record whose fence names a session IS that
session's orchestrator role, so one Edit to it drops a rule the hook enforces. A consuming
repo's records live in its own `plans/orchestrations/` (`../self/features/
orchestration-records-in-repo/`), outside the vendored tree, so they keep a rule of their own;
one still at the legacy vendored place keeps its role until it is moved and is covered by the
tree-wide rule. Their writers
— `orchestration-start.sh` and `manifest.py --orchestration` — are subprocesses no Edit rule
sees, so they are not prompted. Consumer spelling only: the `--self` pair was dropped by the
owner — the record as first committed holds the role in every clone and the ledger before
that, and an ask would only stall an unattended orchestrator's edits to its own record (that
feature's NOTES.md, "Dropped: the `--self` ask rule (F9)").

This directory is the policy, and an unattended executor must not be able to widen what
the hook approves — but a human editing it should be *asked*, not refused. An ask rule is
evaluated before allow rules and fires even under `acceptEdits`, and in a headless
`claude -p` there is no terminal to answer it, so a matching ask is **denied** there.
That is exactly the split wanted: an attended session prompts, a runner's executor is
refused. **Known limit:** under `bypassPermissions` an ask does not fire at all — only
deny binds in that mode — and the runners launch with `acceptEdits`, never bypass
(`RUNNER.md` → "The executor's environment").

The `**/` spelling is what closed the hole the root-anchored deny left: `Edit(/hooks/**)`
is anchored at the *project root*, so for a session rooted at the primary checkout the
copy in `.worktrees/<slug>/hooks/` was neither denied nor asked about, and that is how
this feature's own predecessor edited the policy. At any depth it is covered from either
root. The cost, stated where a consuming repo will meet it: `Edit(**/hooks/**)` under
`--self` matches any directory named `hooks/` at any depth of *this* checkout, which is
the right trade here and is why the vendored spelling keeps its `agentTooling/` segment.

The two narrower vendored asks this helper wrote before `vendored-edit-ask` —
`Edit(**/agentTooling/hooks/**)` and `Edit(**/agentTooling/self/orchestrations/**)` — are
strictly subsumed by `Edit(**/agentTooling/**)` and are **retired**
(`RETIRED_EDIT_ASK_RULES`): the next `sync-plans.sh` removes both, by exact string, in the
same write that adds the broad rule, so there is no moment with neither and no stale rule
that reads as if it were the boundary. A repo's own spelling of a rule is the repo's and is
left alone. Consumer mode only: `--self` never carried them.

A consuming repo that had the old `Edit(**/agentTooling/hooks/**)` **deny** rule — the
spelling this helper wrote before the ask rule — got the ask rule added beside it, and
deny wins over ask, so editing `hooks/` there stayed refused: every consuming repo
carried both until `claude-md-chain`. That deny is now **retired**
(`RETIRED_EDIT_DENY_RULES`): the next `sync-plans.sh` removes it where it stands, exactly
as a retired `Bash` deny (below), and the ask rule is what remains. A deny a repo wrote
itself under another spelling is the repo's and is not touched.

### `Bash`

`LIFECYCLE.md` rule 2 — agents never create or destroy branches and worktrees, and never
rewrite history — written where `/permissions` will show it:

```
Bash(git push --force:*)   Bash(git push -f:*)   Bash(git push --force-with-lease:*)
Bash(git reset --hard:*)   Bash(git clean:*)     Bash(git rebase:*)
Bash(git stash push:*)     Bash(git stash save:*)     Bash(git stash pop:*)
Bash(git stash apply:*)    Bash(git stash drop:*)     Bash(git stash clear:*)
Bash(git stash branch:*)   Bash(git stash create:*)   Bash(git stash store:*)
Bash(git worktree add:*)   Bash(git worktree remove:*)   Bash(git worktree prune:*)
Bash(git worktree move:*)  Bash(git worktree lock:*)     Bash(git worktree unlock:*)
Bash(git worktree repair:*)
Bash(git checkout -b:*)    Bash(git checkout -B:*)
Bash(git switch -c:*)      Bash(git switch -C:*)
Bash(git branch -d:*)      Bash(git branch -D:*)      Bash(git branch --delete:*)
Bash(git branch -m:*)      Bash(git branch -M:*)      Bash(git branch --move:*)
Bash(git stash)
```

These are **prefix** rules but the last: each matches only a command that begins with the
text it names, so `git -C /repo worktree add x`, `x=$(git rebase main)` and `ls && git
stash` match none of them. `Bash(git stash)` is an **exact** rule, for the bare verb: its
prefix spelling `Bash(git stash:*)` matched `git stash list` too, and a deny rule beats
the hook's allow, so the prefix is retired (`policy.RETIRED_DENIED_GIT_COMMANDS`) and a
consuming repo's merge removes it. A leading-flag push (`git stash -u`) has no rule for
the same reason — any prefix that named it would name the listing — and is the hook's
alone. The enforcement is the hook's git deny above, which reads every
command on the line; these rules are the visible half of the same policy. They are not a
second list any more: `policy.bash_deny_rules()` renders them from the same table the
hook reads, in the order above — push force ×3, `reset --hard`, the always-mutating
verbs, stash ×9, worktree ×7, checkout, switch, branch, then the exact `git stash` — so an
entry added to the table reaches both halves and `self/tests/policy-table.sh` asserts
that it did. A rule here is never an allow rule; nothing this helper writes ever is.

## The sandbox block

**The block is generated, but OFF by default.** `wire-settings.py`'s one switch,
`SANDBOX_ENABLED = False`, writes `"enabled": false`
(`self/features/sandbox-consumer-reads`). The reason: where the user's
`permissions.blockReadsOutsideWorkingDirectories` is on, the sandbox refuses every read
under the home directory, so a consumer's verify pass cannot reach the Playwright browser
cache, and this repo-level file cannot re-open it (see `SANDBOX_DENY_READ` below). **To
turn it on:** first re-open the cache in the machine's *user* settings
(`~/.claude/settings.json` → `sandbox.filesystem.allowRead`), or turn the read block off.
Then set `SANDBOX_ENABLED = True` and run a propagation pull: `sync-plans.sh` sets every
consumer's `enabled` back to the constant, and `--self --write` regenerates this
checkout's file. That is the whole procedure. Everything else below is written either way,
and it binds nothing until the switch is on. Until then the runners execute without the OS
boundary, as they did before `runner-sandbox` (#72).

Every rule above binds a *tool call*. None of them binds what a Bash command does once it
runs: a subprocess that opens `~/.ssh/id_rsa` itself, writes `.git/hooks/pre-commit`, or
posts to an arbitrary host is outside them all — and the verify and review passes run
Bash unattended (`--permission-mode acceptEdits`, `--allowedTools Bash`), where the
realistic threat is prompt injection from something the executor reads. The boundary
under the subprocess is Claude Code's OS sandbox (Seatbelt on macOS), and
`wire-settings.py` writes it into the same file, in both layouts — today with the switch
off:

```json
"sandbox": {
  "enabled": false,
  "failIfUnavailable": true,
  "allowUnsandboxedCommands": false,
  "filesystem": { "denyRead": ["~/.ssh", "~/.aws", "~/.config/gh"] },
  "network": { "allowedDomains": ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org",
               "api.anthropic.com", "github.com", "api.github.com",
               "objects.githubusercontent.com"] }
}
```

- **`SANDBOX_ENABLED`** — the switch above, the source of the owned `enabled` value.
- **`SANDBOX_OWNED_SETTINGS`** — `enabled` (from `SANDBOX_ENABLED`), `failIfUnavailable`
  and `allowUnsandboxedCommands`. The last two are inert while the switch is off and
  correct once it is on: `failIfUnavailable` (a batch never runs unsandboxed without
  saying so: where the sandbox cannot start, the session refuses to) and
  `allowUnsandboxedCommands: false` (no retry outside the sandbox for a command that
  failed inside it). **`autoAllowBashIfSandboxed` is never written**: Bash approval stays
  where it was — the runner's `--allowedTools`, this hook's policy, the human.
- **`SANDBOX_DENY_READ`** — the sandbox's own read default is open, so only the
  credential stores are closed. This block never denies `~/` or `~/.claude`: the
  Playwright browser cache and `analysis/`'s reads of `~/.claude/projects` need them.
  **But another settings layer can close far more.** Where
  `permissions.blockReadsOutsideWorkingDirectories` is on (user settings, or the `dev/`
  folder's), the sandbox enforces that at the OS level too: in the validation run a Bash
  subprocess could not list `~/Library/Caches` (`Operation not permitted`), and the
  session's effective `denyRead` held the home directory with only the worktree and a few
  `~/.claude` subdirectories allowed back. A consumer's verify pass that runs Playwright
  (browsers under `~/Library/Caches/ms-playwright`) or a home-directory toolchain (pyenv,
  nvm, `~/.npm`) may therefore be refused a read this block never asked for — and it will
  look like broken code. **This block cannot re-open it.** While
  `permissions.blockReadsOutsideWorkingDirectories` is on, Claude Code drops
  `sandbox.filesystem.allowRead` (and `allowWrite`) entries that come from *repository*
  settings — "While the block is in force, `allowRead` and `allowWrite` entries from
  repository settings don't count" (Claude Code 2.1.286,
  <https://code.claude.com/docs/en/settings-reference.md> → "Sandboxed commands under the
  block", checked 2026-09-30). A probe confirmed it: with an `allowRead` for
  `~/Library/Caches/ms-playwright` in this generated file, a sandboxed `claude -p` still
  got `Operation not permitted` listing the cache
  (`self/features/sandbox-consumer-reads/NOTES.md`). So `wire-settings.py` writes no
  `allowRead`. The re-allow is a **per-machine user-settings entry**: `allowRead` in
  `~/.claude/settings.json` → `sandbox.filesystem`, naming the cache
  (`~/Library/Caches/ms-playwright` on macOS, `~/.cache/ms-playwright` on Linux) — the doc
  excludes only repository entries, so a user-settings one should count, though no run has
  shown it yet. Nothing in this harness writes it; `self/BACKLOG.md` tracks the consumer
  verify run that would prove it.
- **`SANDBOX_ALLOWED_DOMAINS`** — the package registries, the model API and GitHub,
  extended only by what a real run under the sandbox was refused
  (`self/features/runner-sandbox/NOTES.md` records the run that set this list).
- **No `denyWrite`.** Writes are confined to the working directory (and `--add-dir`
  directories) already, and with `enabled` on Claude Code applies its **built-in write
  denies** with no setting of ours and no exemption: `.git/hooks`, `.git/config`,
  `.git/HEAD`, `objects/`, `refs/`, every `.claude/settings*` file,
  `.claude/{skills,agents,commands,hooks,workflows}/`, `.mcp.json`, `.bashrc`, `.zshrc`,
  `.gitconfig`, `~/.claude/` and `~/.claude.json` (Claude Code 2.1.284,
  <https://code.claude.com/docs/en/sandboxing.md>, checked 2026-09-30). A narrow
  `denyWrite` of our own would only restate that list. A denied write sees `Operation not
  permitted`; a refused host sees a `host-not-allowed` error or a refused connection — and
  a run failing under the sandbox looks exactly like the code broke, so read the stream
  for those first.

**`strictAllowlist` is left off, on purpose.** Project settings govern the user's
*interactive* sessions in the repo too, and there a prompt for a new domain is useful —
the human approves it once and can add it here. In `claude -p` there is nobody to answer
that prompt, so the same setting refuses the domain for a headless executor: attended
sessions prompt, the runners' executors are denied. Turning it on would make interactive
sessions refuse silently for no gain in the runners.

**Once the switch is on, these reach every developer, not just the runners.** Project
settings govern interactive sessions too, so `failIfUnavailable: true` means a machine where the sandbox
cannot start (Linux without bubblewrap, WSL1) cannot run Claude Code in that repo at all,
and `allowUnsandboxedCommands: false` removes the human's own escape hatch for a command
the sandbox breaks. That is the ruling (`self/features/runner-sandbox/NOTES.md`): the
alternative is a batch that runs unsandboxed without saying so, and a repo that needs
the hatch overrides it in its gitignored `.claude/settings.local.json`, which wins over
the project file and which this helper never touches — and which then unsandboxes that
checkout's runners too, since `claude -p` reads it as well.

**Merge semantics** differ from the rules above in one way: the three owned keys are set
to the generator's value *wherever they stand* — a consuming repo that flipped its
`enabled` by hand is set back to `SANDBOX_ENABLED` by its next `sync-plans.sh` (switched
off today, on once the constant is), so the constant is the one place to flip it — while
`denyRead` and `allowedDomains` are **unions**: the repo's own entries stay first and in
place, and the generator's missing ones are appended after them. Every other sandbox key
(`excludedCommands`, `network.allowUnixSockets`, `credentials`, …) is the repo's and is
never touched. A `sandbox`, `sandbox.filesystem` or `sandbox.network` that is not an
object, or a `denyRead` / `allowedDomains` that is not a list, is `INVALID` and the file
is left untouched. Under `--self` the block is generated like the rest of the file, so a
domain hand-added there is drift the gate refuses; add it to `SANDBOX_ALLOWED_DOMAINS`
and regenerate.

**Not covered:** Linux/WSL (bubblewrap) specifics, `credentials` masking, and TLS
termination at the proxy — see `self/BACKLOG.md`.

## What `wire-settings.py` will and won't touch

**In a consuming repo**, `.claude/settings.json` is repo-owned and may hold anything, so
everything is **merged,
not copied**. The hook entry is appended when no hook command anywhere in the file
mentions `allow-repo-commands.sh`, and the `SessionStart` entry when no SessionStart hook
command mentions `session-start.sh` — after any SessionStart hooks the repo has of its own;
each deny and ask rule is appended when its exact string is absent. Otherwise the file is left byte-for-byte alone. It never reorders or
rewrites another entry, and it never adds an allow rule. It removes exactly four kinds of
entry, each one it once wrote itself and has since retired. A `Bash` deny rule the table
dropped (`policy.retired_bash_deny_rules()`, today only `Bash(git stash:*)`), because a
deny rule left behind would go on overriding the hook's approval of what the table now
calls read-only. An `Edit` deny rule its ask rule replaced (`RETIRED_EDIT_DENY_RULES`,
today only `Edit(**/agentTooling/hooks/**)`), because deny wins over ask and leaving it
refused the humans the ask was written to prompt. The two narrow vendored `Edit` ask rules
the tree-wide `Edit(**/agentTooling/**)` subsumes (`RETIRED_EDIT_ASK_RULES`:
`Edit(**/agentTooling/hooks/**)` and `Edit(**/agentTooling/self/orchestrations/**)`),
removed in the same write that adds the broad one. And the SessionStart hook running
`${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh` directly (`RETIRED_SESSION_COMMANDS`), because
`session-start.sh` now runs that script and leaving it would run it twice; its entry goes
once it holds no other hook, and a repo's own differently-spelled `cloud-setup.sh` hook
stays. `--check` reports such a file `UNWIRED` with "N retired … (…) to remove"; `--write`
takes them out where they stand and reports what it removed.
And it owns three values in the `sandbox` block, which it sets wherever they stand, while
unioning its `denyRead` paths and domains into the repo's own ("The sandbox block" above).

**Under `--self` the file is wholly generated**, because nothing else writes
agentTooling's own: there is no repo to own it but this one. So `--check` compares it
**byte for byte** with what a fresh `--write` into an empty directory produces, and names
where it first differs and which entry one side carries that the other does not; and
`--write` puts those bytes back, reporting `kept` when they were already there. That is
the whole point of the mode: the merge check could only ever see a *missing* entry, so a
hand-added allow rule, a hook command repointed at the vendored path where it would never
run, or a reordered deny list all left `self/gate.sh` green while this file said they
failed it. They fail it now. The corollary is that a hand edit to that file is **lost**
on the next write rather than merged — which is what "generated" means, and why the
`Edit(/.claude/**)` deny rule refuses to let one be made through the Edit tool at all.
Claude Code's own "don't ask again" approvals go to `.claude/settings.local.json`, which
is git-ignored and never generated, so they never touch the policy.

**And under `--self` the file is tracked** (`self/features/self-cloud-bootstrap/`), so a
fresh clone — every new cloud container, and a review, close or router session that never
ran a start — has the hook and the deny rules from its first tool call. Only a file
present at startup gives that: round 1 of that feature committed a `SessionStart` hook
that generated the policy into an untracked file, and the settings watcher's reload
missed the first tool call in 3 of 15 fresh sessions (its `NOTES.md`). A worktree has the
file from its checkout too, so nothing generates it there. `self/gate.sh` fails on a
missing file as on a drifted one, and the message names the command to run. It ships with
the subtree, which is harmless: a session launched at a consuming repo's root loads only
that root's own settings, and one launched inside the vendored `agentTooling/` loads this
file with `${CLAUDE_PROJECT_DIR}` that directory, where every path it names exists — the
self policy is what such a session should have. The guard in `SELF_HOOK_COMMAND` covers
anything left: no `hooks/allow-repo-commands.sh` under the project directory, a silent
exit 0. In a **vendored** agentTooling — `--repo` with no `.git` of its own and one above
it — `--check` holds the shipped copy to the same bytes, and since `--write` writes nothing
there, a failure names the fix upstream rather than a local command. The consuming repo's
own hook, wired at its root by `sync-plans.sh`, is untouched by any of it.

The hook marker is the script's basename, so a repo that hand-edits the entry — a
different path, a narrower `matcher`, an added `if:` — keeps its version and never gets a
duplicate. Deleting an entry or a rule is durable in one direction only: the next
write run re-adds it. To opt out of the hook for good, keep an entry that points it
somewhere harmless rather than deleting it; to opt out of a deny rule, remove it from
`EDIT_DENY_RULES` here or from `policy.py`'s table, which changes it for every consuming
repo.

`--self` changes the hook command (which loses the `agentTooling/` segment), the ask
rule's spelling (`Edit(**/hooks/**)` and `Edit(/hooks/**)`, since here `hooks/` is at the
root), and how the file is maintained (generated, not merged). The deny rules are the
same list in both modes. The two are not interchangeable: `--self --check` over a
vendored repo's file reports `UNWIRED`, and an ordinary `--check` over this checkout's
reports it too.

A consuming repo's file that does not parse, or whose `hooks`, `hooks.PreToolUse`,
`hooks.SessionStart`, `permissions`, `permissions.deny`, `permissions.ask`, `sandbox`, `sandbox.filesystem`,
`sandbox.filesystem.denyRead`, `sandbox.network` or `sandbox.network.allowedDomains`
values are the wrong type — an explicit `null` included, which is present, not absent —
is reported `INVALID` and left untouched. `--self` never reports `INVALID`: a generated file
that does not parse is drift like any other, and the write replaces it.

## Cross-layer dependencies

- **The approved forms of `../analysis/capture_planning.py`, `manifest.py` and `report.py`
  restate their parsers** — `CAPTURE_LISTING_OPTIONS` and `CAPTURE_VALUE_OPTIONS` name
  `capture_planning.py`'s listing options and which take a value, `MANIFEST_READ_SUBCOMMAND`
  and `ORCHESTRATOR_MANIFEST_*` `manifest.py`'s subcommands and their arity. Renaming an
  option there leaves the shape naming a word the parser no longer has: the hook still
  approves the old word, and the script refuses it with argparse's usage error (exit 2)
  before it reads or writes anything, while the new spelling prompts until it is named
  here — so a rename is a dead approval to remove, never a write let through. A new option
  that writes prompts until it is named here, and is never named. All three parsers set
  `allow_abbrev=False`, so the exact word is the only spelling
  (`../self/features/python-entry-exact/`; asserted at run time by
  `self/tests/manifest-window.sh` M9).
- **`CLAUDE_PROJECT_DIR`** — `allow-repo-commands.sh` reads this for the project root and
  approves nothing when it is unset. Claude Code sets it for hook processes. In a `git
  worktree` it is the worktree root, so a worktree session approves paths inside its own
  tree only — never the main checkout.
- **`cwd` in the hook payload** — must be present and inside the root, or a relative path
  in the command could resolve anywhere. The hook approves nothing without it. The opaque
  check still runs when it is missing: an unreadable command is unreadable wherever it
  runs, as the three shape denies already were.
- **`session_id` and `agent_id` in the hook payload** — the escalation counter's key.
  `agent_id` is present only inside a subagent call and a subagent carries its parent's
  `session_id`, so the pair is what keeps a delegate's rewrites off its coordinator's
  count. A payload with no `session_id` never escalates.
- **`$TMPDIR`** — where the escalation state lives
  (`$TMPDIR/agenttooling-hook-state/<digest>.count`, `/tmp` when unset). Nothing else in
  the hook touches the filesystem for state, and every read of it tolerates absence and
  corruption.
- **`AGENTTOOLING_HEADLESS` and `AGENTTOOLING_SCRATCH`** — set by
  `plan-runner-lib.sh`'s `claude -p` launch site and by nothing else (`RUNNER.md` → "The
  executor's environment"). The hook is their only reader. Neither is set in an ordinary
  interactive session, where the escalation asks and no scratch directory is approved.
  The scratch directory is only usable if that same launch also passes `--add-dir` for it:
  `--permission-mode acceptEdits` auto-accepts a Write under the working directory alone,
  and this directory is under `$TMPDIR`. Approving a script the executor could never have
  written is a dead end, so the two belong to one contract — asserted together in
  `self/tests/stream-capture.sh` phase 10.
- **`policy.py` beside both scripts** — neither imports it by package name or from the
  cwd: each inserts its own `os.path.dirname(os.path.realpath(__file__))` on `sys.path`
  first, because the hook is run from wherever the session sits and the writer from
  wherever `--repo` points. Moving either script out of this directory, or vendoring one
  without the other two, is an `ImportError` at the first Bash call rather than a silent
  fallback. Both set `sys.dont_write_bytecode` so the import leaves no `__pycache__` in
  the repo being guarded.
- **`env_profile.py` beside the hook, and `AGENTTOOLING_PROFILE` / `CLAUDE_CODE_REMOTE`
  in its environment** — the hook imports the module the same sibling way, guarded: a
  missing module, an invalid override or any detection failure reads as **local**, i.e.
  today's answers. It reads the two variables only through the module. `../env-profile.sh`
  depends on the module too, at `<its own dir>/hooks/env_profile.py`, so a test fixture
  that copies `env-profile.sh` copies the module beside it.
- **`git` on `PATH`, the session's checkout, and the manifest fence** — the cloud path only
  ("The git shape, by profile"): the current branch from `rev-parse`, the started feature
  from a tracked `<features dir>/<slug>/README.md` whose fence's `branches[0]` is that
  branch (`plan-runner-roots.sh`'s `manifest_branch` contract, written by
  `feature-start.sh`), and the repo's shape from this file's own location (`<root>/hooks/`
  for agentTooling's checkout, `<root>/agentTooling/hooks/` vendored). Any of them missing
  degrades to today's answer or a reason that names less, never a crash.
- **The orchestration record and the `feature: ` first line** — the orchestrator-role
  denies depend on two contracts the hook does not import: a record at
  `<tooling>/self/orchestrations/<slug>/README.md` or the consuming repo's
  `plans/orchestrations/<slug>/README.md` whose last fence carries `session`
  (written by `../orchestration-start.sh`, read by `analysis/manifest.py --orchestration`),
  and the `feature: <repo>/<slug>` first line of every implementer brief
  (`../ORCHESTRATION.md` → Rules, `../templates/plans/ORCHESTRATOR_BRIEF.md`'s header) —
  plus the payload's `session_id`, which a subagent's payload carries as its parent's. A
  changed record location is one edit, to `shared_rules.py`'s `ORCHESTRATIONS_SELF_REL` /
  `ORCHESTRATIONS_CONSUMER_REL`, which the role rule, `analysis/roots.py`,
  `orchestration-start.sh` and `wire-settings.py`'s ask rules all read. The guard is also two-tool:
  `Agent` must be a wired matcher (`wire-settings.py`'s `HOOK_MATCHERS`), or the delegate
  deny never fires.
- **`brief_header.py` beside the hook, and `analysis/capture_planning.py` reading it** —
  the brief-header deny and the capture's reading of a brief's `feature:` line are one
  definition; a change to the grammar there changes what the hook sends back and what the
  capture claims together, which is the point. `capture_planning.py` finds it at
  `<analysis>/../hooks/`, so vendoring `analysis/` without `hooks/` is an ImportError.
- **`shared_rules.py` beside `orchestrator_role.py`, `wire-settings.py` and `analysis/`** —
  the record roots, fence keys, ledger name, slug pattern and refusal texts are read from it
  by the role rule, the settings writer, every analysis tool (through `roots.py`, which finds
  it at `<analysis>/../hooks/`) and `orchestration-start.sh` (by running it). Vendoring
  `analysis/` or `wire-settings.py` without it is an ImportError, `orchestration-start.sh`
  refuses, and the hook alone degrades: the role rule goes silent.
- **`python3` on `PATH`** — `sync-plans.sh` skips the wiring with a `SKIPPED` line when it
  is absent. The hook itself is `#!/usr/bin/env python3`.
- **A consuming repo's `.claude/settings.json` must be committed** to reach worktrees. A
  `git worktree` gets no `.claude/` of its own, and `.claude/settings.local.json` is
  ignored globally by Claude Code's default `~/.config/git/ignore` entry. The shared file
  is the only copy a worktree or a fresh clone can inherit. `sync-plans.sh` says so when
  it writes one.
- **This checkout's own `.claude/settings.json` is generated and tracked.**
  `python3 -B hooks/wire-settings.py --self --repo <root> --write` writes it; run it after
  changing the constants here and commit the result. `self/gate.sh` records
  `wire-settings.py --self --repo <root> --check` as a blocking check, which fails on a
  missing file and compares a present one byte for byte, so a hand edit of any kind — an
  added rule as much as a missing one — fails the gate, and the failure names the command
  that regenerates. Do not edit that file directly — the `Edit(/.claude/**)` rule in it
  refuses anyway. Its hook command depends on `${CLAUDE_PROJECT_DIR}`, which Claude Code
  sets to the launch directory for hook processes, for both its guard and its path. It
  ships with the subtree and is loaded only by a session launched inside
  `agentTooling/`; a consuming repo's own wiring is the one at *its* root, written by
  `sync-plans.sh` without `--self`. Why it is tracked rather than generated at session
  start is recorded live in `self/features/self-cloud-bootstrap/NOTES.md`.
  `.claude/settings.local.json` is git-ignored: Claude Code's own per-user file.
- **The hook is trusted code that lives in the repo.** `update.sh` pulls it from the
  agentTooling upstream and re-runs the wiring, so that upstream is the trust root for
  the policy. The `Edit(**/agentTooling/**)` **ask** rule keeps an unattended
  executor from changing it, or any other vendored file, through the Edit tool — a headless session cannot answer an
  ask, so it is refused there, while an attended one is prompted; a subprocess write is
  the remaining path. The sandbox block, once switched on, binds subprocesses, but its
  built-in write denies
  do not name `hooks/` (it is inside the working directory, which the sandbox leaves
  writable), so that path stays open to a Bash command the runner auto-approves.
- **Hooks are read at session start.** A change to the wiring takes effect in the next
  session; `/hooks` shows what the current one loaded.
- **The `SessionStart` entry depends on `agentTooling/session-start.sh` with
  `env-profile.sh` and `plan-runner-roots.sh` beside it**, all three shipped with the
  subtree. In the cloud it then runs the repo's seeded `plans/cloud-setup.sh` with
  `bash`; with that script absent it prints one line saying to run `sync-plans.sh` (which
  re-seeds it, and whose `--check` reports it `missing`) and exits 0.

## Wiring

`sync-plans.sh` does this. By hand, the equivalent is:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh" }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/agentTooling/session-start.sh" }
        ]
      }
    ]
  }
}
```

The `SessionStart` entry runs agentTooling's `session-start.sh` on every session start
(`self/DESIGN-2026-10-05-cloud-execution.md` §7): a few read-only lines naming the profile,
the branch and the command that comes next — `feature-start.sh <slug>` run where the
session stands, or the feature already started on this branch and its close — and then, in
the cloud only, the repo's seeded `plans/cloud-setup.sh` for what THIS repo needs (its exit
code is the hook's). The universal part is agentTooling's, so it reaches every repo on its
next `subtree pull`; only the repo's part is seeded and repo-owned. The alternative for
the repo's part — the cloud environment's own setup script — is in `templates/README.md`.

In agentTooling's own checkout the commands are
`test ! -f "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh" ||
"${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"` and
`test ! -f "${CLAUDE_PROJECT_DIR}/session-start.sh" ||
"${CLAUDE_PROJECT_DIR}/session-start.sh" --self`, which is what
`wire-settings.py --self --write` writes into the tracked `.claude/settings.json`. The
session-start command only reads and prints (that checkout has no `plans/cloud-setup.sh`);
the policy itself is still committed rather than written at startup, so a fresh container
has it before its first tool call (`self/features/self-cloud-bootstrap/`).

## Editing the policy

The allowlists are named constants at the top of `allow-repo-commands.sh`:
`READ_ONLY_PROGRAMS`, `FORBIDDEN_FLAGS`, `FORBIDDEN_SHORT_LETTERS`, the `SED_*` grammar,
`GIT_READ_ONLY_SUBCOMMANDS` / `GIT_BRANCH_ALLOWED_FLAGS` / `GIT_WORKTREE_READ_ONLY`,
`RUNNER_PREFIXES`, `RUNNER_BASENAMES`, `RUNNER_ALIASES`, the runners' allowlists
(`RUNNER_BARE_FLAGS`, `RUNNER_VALUE_FLAGS`, `RUNNER_CONFIG_FLAGS`, `RUNNER_SHORT_BUNDLES`,
`RUNNER_RUFF*`, `RUNNER_INFO_FLAGS`) and `MAX_BRACE_WORDS`, the
`ENTRY_*`, `CAPTURE_*`, `MANIFEST_*`, `SYNTAX_*` and `PYTHON_*` constants for the
harness's own entry points, plus `CHDIR_PROGRAMS` and
`ASSIGNMENT_RE` / `ASSIGNMENT_BUILTINS` / `VAR_USE_RE` for the
three shape denies. **The `GIT_*` mutation constants are not there**: they are
`policy.py`'s, the table `wire-settings.py` renders its prefix rules from, and the hook
binds the same objects under the same names — the cloud-only entries (`GIT_CLOUD_ONLY` and
its flags) included, and the both-profile push-to-`main` entry (`PUSH_TO_PROTECTED`,
`GIT_PROTECTED_BRANCH`, `GIT_HOOK_ONLY_RULE` bound to `policy.hook_only_rule`), whose local
reason `GIT_PUSH_PROTECTED_DENY_REASON` is the hook's own. How the push and cloud paths READ
their arguments stays here, beside the reader:
`GIT_SWITCH_VALUE_FLAGS`, `GIT_CHECKOUT_VALUE_FLAGS`, `GIT_PUSH_REPO_FLAG`, `GIT_PUSH_VALUE_FLAGS`,
`GIT_PUSH_VALUE_LETTER`, `GIT_PUSH_DELETE_LETTER`, `GIT_PATHSPEC_SEPARATOR`,
`GIT_CHECKOUT_PATH_FLAGS`, `GIT_HEAD_NAMES`, `GIT_BRANCH_REF_PREFIX`, the `GIT_REFSPEC_*`
and `GIT_PROBE_*` constants, `GIT_LOCATION_FLAG`, `GIT_PROBE_TIMEOUT_SECONDS`, the
`MANIFEST_*` fence readers, the repo-shape constants (`SELF_TOOL_PREFIX`, `SELF_ARG`,
`SELF_FEATURES_DIR`, `CONSUMER_FEATURES_DIR`, `VENDORED_DIR_DEFAULT`,
`TOOL_PREFIX_TEMPLATE`), the orchestrator role (`AGENT_TOOL`, `BUILD_BRIEF_MARKER`,
`BUILD_SCRIPTS`, `AGENT_PROMPT_FIELD`, `BUILD_SCRIPT_READERS`,
`BUILD_SCRIPT_READER_EXEC_FLAGS`, `BUILD_SCRIPT_LAUNCHERS`, `FIND_LAUNCH_FLAGS`,
`FIND_EXEC_END`, `BUILD_SCRIPT_LEAD_KEYWORDS`, `BUILD_SCRIPT_GIT_EXEMPT`,
`BUILD_SCRIPT_GIT_EXEC_FLAGS`, `BUILD_SCRIPT_GH_EXEMPT`, `SED_PRINT_ONLY_RE`,
`SYNTAX_ONLY_FLAG`, `SYNTAX_ONLY_SHELLS`, `ENV_ASSIGNMENT_RE`, `BUILD_SCRIPT_GLOB_CHARS`,
`BUILD_SCRIPT_WILDCARD`, `BUILD_SCRIPT_EXPANSION_RE`, `ANSI_C_QUOTE_RE`, `EXTGLOB_RE`,
`HEREDOC_ARGUMENT_HEAD_RE`, `HEREDOC_ARGUMENT_TAIL_RE`, `COMMENT_PREDECESSORS`,
`COMMENT_DOUBT_OPENERS`, `MAX_COMMENT_DOUBTS`,
`HEREDOC_RUN_ON_IS_BODY`/`HEREDOC_RUN_ON_ENDS`/`HEREDOC_RUN_ON_BACKTICK`, `MAX_RUN_ON_LINES`,
`PID_PARAMETER`, `HERESTRING_OPERATOR`, `GIT_NO_REPLACE_ENV`/`GIT_NO_REPLACE_ON` (hook-audit-gaps
round 2, which also took `HEREDOC_RUN_ON_CHARS` out), `HEREDOC_ARGUMENT_FILL`, `HEREDOC_WORD_CHAR_RE`,
`HEREDOC_JOINS_PARSER`/`HEREDOC_JOINS_BACKTICK`/`HEREDOC_JOINS_AS_WRITTEN`, `ESCAPED_BACKSLASH`,
`BACKTICK_ESCAPE_CYCLE`, `BACKTICK_CONTINUATION`,
`HEREDOC_JOIN_NEVER`/`HEREDOC_JOIN_ODD`/`HEREDOC_JOIN_BACKTICK` (round 3: how a line continuation is read
in a body and inside backticks), `HEREDOC_DELIMITER_UNREAD_RE`, `HEREDOC_SHIFT_RE`,
`HEREDOC_ARGUMENT_STAND_IN`, `CARRIAGE_RETURN`, `BRACE_OPEN`/`BRACE_CLOSE`, `BRACE_SEQUENCE_RE`,
`BRACE_SEQUENCE_STEP`, `GIT_UNREADABLE_ARGS`, `REDIRECT_INPUT_FILE_OPS`, `BUILD_SCRIPT_BRACKET_RE`,
`BUILD_SCRIPT_ANY_CHARACTER`, `BUILD_SCRIPT_TEXT_SPLIT_RE`, `BUILD_SCRIPT_FILTERS`,
`BUILD_SCRIPT_FILTER_EXEC_FLAGS`, `BUILD_SCRIPT_GIT_EXEC_SHORT` (hook-audit-gaps phase 3),
`HEREDOC_PLACEHOLDER`, `HEREDOC_PLACEHOLDER_RE_TEMPLATE`,
`HEREDOC_TOKEN_BYTES` (a random token per call, round 2 N4), `BUILD_SCRIPT_QUOTING_RE`, `OPTION_PREFIXES`,
the orchestrator allowlist's `ORCHESTRATOR_*` block (readers and their forbidden options,
git's read/exact/forbidden sets, gh's, the entry points, the separators, the heredoc and
branch substitutions, the per-call token, the character sets, `ORCHESTRATOR_ALLOWLIST_TEXT`);
the reason text is `orchestrator_role.py`'s `REASON_TEMPLATE`, and the wired
matchers are `wire-settings.py`'s `HOOK_MATCHERS`, an ordered tuple — a new build script is
an entry in `BUILD_SCRIPTS` and a case in `self/tests/hook-orchestrator-role.sh`), and the
cloud reason (`GIT_CLOUD_DENY_REASON_TEMPLATE`,
`GIT_CLOUD_STARTED_TEMPLATE`, `GIT_CLOUD_UNSTARTED_TEMPLATE`, `BRANCH_QUOTE`,
`BRANCH_UNKNOWN`), and the off-branch reason (`GIT_CLOUD_OFF_BRANCH_TEMPLATE`,
`OFF_BRANCH_DETACHED`, `GIT_REMOTE_REF_PREFIX`, `GIT_REMOTE_SEPARATOR`,
`GIT_TREE_PATH_SEPARATOR`, `GIT_SHOW`, `GIT_PROBE_REMOTE_REFS`), and the attach reason
(`GIT_CLOUD_ATTACH_TEMPLATE`, `ATTACH_SCRIPT`, `GIT_HEAD`, `GIT_ATTACH_REMOTE_PREFIX`,
`GIT_PROBE_IS_ANCESTOR`, `GIT_PROBE_ATTACH_CANDIDATES`); a new cloud-only shape is an entry in `policy.GIT_CLOUD_ONLY`, a branch
in `cloud_refuses`, and a row in `self/tests/hook-cloud-profile.sh`'s table with its local
and its cloud answer. The opaque deny is `OPAQUE_REWRITE_ATTEMPTS`,
`HEREDOC_LITERAL_PROGRAMS`, `INTERPRETER_CODE_LETTER`, `EVAL_PROGRAM`,
`COMMAND_CARRIER_PROGRAMS`, `FIND_EXEC_FLAGS`, `COMPOUND_KEYWORDS`, `SEGMENT_BREAKS` and
`LINE_BREAK_CHARS` (the subset of `SEGMENT_BREAKS` that ends the command's first line,
which is where `segments_before_line_break` stops for a `cat` heredoc);
`UNREADABLE_DENY_REASON` for the seventh shape; the verdicts and the shapes added on
2026-09-18 are `VERDICT_ALLOW` / `VERDICT_REWRITE` / `VERDICT_ASK`, `MEMBER_TEXT_MAX_CHARS`
/ `MEMBER_TEXT_CUT` / `MEMBER_QUOTE`, `REASON_PREFIX` / `REASON_LINE_SEPARATOR`,
`LINE_BREAK_NEWLINE`, `SEQUENCE_SEPARATORS`, `PARENT_COMPONENT`, `BRACE_EMPTY_GROUP` and
one reason constant per shape (`VAR_USE_REWRITE_REASON`, `TILDE_REWRITE_REASON`,
`BRACE_REWRITE_REASON`, `PARENT_PATH_REWRITE_REASON`, `RELATIVE_CHDIR_REWRITE_REASON`,
`LINE_BREAK_REWRITE_REASON`, `MIXED_SEQUENCE_REWRITE_REASON`); the shell-authored file is
`AUTHORING_ECHO_PROGRAMS`, `AUTHORING_LITERAL_PROGRAMS`, `AUTHORING_TEE_PROGRAM`,
`AUTHORING_HEREDOC_FED_PROGRAM`, `AUTHORING_SED_PROGRAM`, `SED_IN_PLACE_LETTER`,
`SED_IN_PLACE_LONG`, `SED_VALUE_LETTERS`, the `REDIRECT_*` operator constants,
`PROCESS_SUBSTITUTION_PREFIXES`, `FD_DUP_TARGET_RE`, `NON_FILE_TARGETS`,
`AUTHORING_SEPARATOR_CHARS`, `PIPE_SEPARATORS` and `SHELL_AUTHORING_REWRITE_REASON` — a new shape is a constant,
a predicate in `rewrite_reason_lines`'s table, a case in `self/tests/allow-repo-commands.sh`
and the row above;
the escalation is `STATE_DIR_NAME` / `STATE_FILE_SUFFIX` / `STATE_KEY_SEPARATOR` under
`TMPDIR_ENV`, with `HEADLESS_ENV`, `SCRATCH_ENV`, `SCRATCH_BASH` and
`SCRATCH_SCRIPT_MIN_ARGS` for the runner-side pair. Every change to the approval
constants is a widening of
what runs without a prompt: add the command to `self/tests/allow-repo-commands.sh` with
the bypass you checked it does not open, and run `bash self/tests/allow-repo-commands.sh`.
A change to `CHDIR_PROGRAMS` adds a `DENY` case and a `NOT_DENIED` case there. A change
to any opaque constant adds an `OPAQUE_DENY` case *and* an `OPAQUE_NOT_DENIED` case, and
anything touching the counter, the `ask`, the headless fall-through or the scratch entry
point belongs in `self/tests/hook-escalation.sh`, which is the only place the state file
is exercised at all (`bash self/tests/hook-escalation.sh`).

**The git policy is one table.** `policy.py` holds `GIT_ALWAYS_MUTATING`, the flag sets
and `GIT_WORKTREE_SUBCOMMANDS`; the hook imports them for `git_mutates`, and
`bash_deny_rules()` renders the `permissions.deny` prefix twin from the same constants.
So a subcommand is added **once**, and what follows is: a `DENY` case and a `NOT_DENIED`
case in `self/tests/allow-repo-commands.sh`, and
`python3 -B hooks/wire-settings.py --self --repo <root> --write` to regenerate this
checkout's tracked `.claude/settings.json`, committed with the change — every other self
checkout takes it with the commit (the gate's byte-for-byte check fails until you do).
`self/tests/hook-wiring.sh` and `self/tests/policy-table.sh` render the list from the
table rather than repeating it, so neither needs editing. Consuming repos pick the new
rule up on their next `sync-plans.sh`.

This is what replaced "two constants move together", which is how the two lists drifted
for as long as they did: `permissions.deny` named neither
`git worktree move|lock|unlock|repair` nor `git branch --delete|--move`, and nothing
failed.

**A change here is closed only behind a security audit** (`../LIFECYCLE.md` → "The
security audit"; `../self/features/hook-role-hardening/`). A feature whose diff against its
base touches this folder, `.claude/`, or a file that enforces the role or the audit (the
list is `../plan-runner-roots.sh`'s `audit_paths` — the hook, `.claude/`, every script that
calls `refuse_orchestrator_session`, the runner library, the stamp writer, the gate, the
record writer, the audit's template, and every file the orchestrator allowlist executes with
what it imports (`orchestration-capture.sh`, `analysis/` whole) — diffed against the manifest's
base and the default branch's merge-base both; under `agentTooling/` in a consuming repo)
gets an `NN-audit-opus.md` rendered by `run-review.sh` beside its review from
`../templates/SECURITY_AUDIT.md` (a queued audit that is not exactly that is refused): a separate executor that attacks a
throwaway copy of the changed rules with concrete inputs and tables each as allowed, asked
or denied. `feature-close.sh` refuses the close until that audit's committed report is clean
on the head the review judged and nothing after that head touches an audit path. Findings are
classed `blocking` (only a regression against the base, a silent allow the head introduces
included) or `non-blocking` (everything else, a pre-existing silent allow too, filed in the
BACKLOG before the close, as a `<slug>: backlog` commit touching that file alone, which the
close accepts after the judged head); only a blocking finding escalates, and the close refuses a clean report whose `## Findings` holds anything not classed
non-blocking. The tests above are what the change claims; the audit is someone
trying to prove them incomplete.
