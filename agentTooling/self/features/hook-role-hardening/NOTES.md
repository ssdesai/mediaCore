# hook-role-hardening — notes

Decisions and findings for the feature (`README.md`). The audit reproductions it started
from were the PR #138 auditor's `probe.py`; the cases are now tests
(`self/tests/hook-orchestrator-role.sh` H11/H12, `self/tests/orchestrator-role.sh` U1g/U1h,
`self/tests/coordinator-records.sh` K1/K6, `self/tests/security-audit.sh`).

## F1 — the role is a record its own session can edit

- **(b), the shape.** #138 shapes a coordinator record's `features[]` entries as
  `{repo, slug, session: null, branch: null, pr, report}` (`self/orchestrations/ablation-wave/`
  is the one real one); an orchestrator's `add-feature` records each implementer's
  `session` and `branch`. So `orchestrator_role.is_role` keeps a `coordinator` fence a role
  when any entry has a non-null `session` or `branch`, and `manifest.py --orchestration`
  refuses to write either into a coordinator record (null is allowed), so a real one cannot
  drift into the role by accident.
- **(b), every fence.** The role used to read the LAST fence only, which is why an appended
  `{}` or coordinator fence dropped it. It now reads every fence: any fence naming the
  session as a role makes the record a role. `self/tests/orchestrator-role.sh` U1e asserted
  the opposite ("an earlier fence naming S is not S's"); that contract is deliberately
  reversed, and the test now holds the new one (U1g, U1h). Readers of the record's DATA
  (`analysis/`) still take the last fence; only the role is stricter.
- **What (b) cannot see**: an in-place rewrite of the one fence — `session` changed, or
  `kind` added to a record with no features yet (the PR #138 probe's own baseline record
  has `features: []`, so its `kind=coordinator` case still passed after (b)). (a) covers it
  in a consuming repo only, so a third, beyond the brief: **the ledger**.
  `orchestration-start.sh` appends `<session> <slug>` to `<git common dir>/agenttooling-orchestrators`
  for every orchestrator record (never a coordinator one), and `record_for_session` falls
  back to it when no record names the session. The Edit tool cannot write under `.git/` in
  any mode (`Edit(**/.git/**)` deny), and a shell write there is handed to the human, so the
  role survives the record being rewritten or deleted. It is local to the clone — the
  record stays the shared copy — and costs one `git rev-parse` per lookup that found no
  record (only for a line that mentions a build script, or an implementer brief).
- **(a), the ask rule.** `wire-settings.py` adds `Edit(**/agentTooling/self/orchestrations/**)`
  to a consuming repo's ask rules (an Edit rule covers Write too); the records' sanctioned
  writers are subprocesses, which no Edit rule sees, so they are not prompted. The brief said
  records live in `plans/orchestrations/` in a consuming repo; they do not — they are always
  under the tooling directory (`agentTooling/self/orchestrations/`, `analysis/roots.py`'s
  `orchestrations_root`), so that is the path guarded.

### Dropped: the `--self` ask rule (F9)

**Dropped by the owner's decision during audit round 3.** The record as first committed,
read from git history, already holds the role on any machine once the record is committed,
and the ledger holds it on the starting machine before then; an ask rule over
`self/orchestrations/` would only put a prompt in front of an orchestrator's routine edits to
its own record, and in an unattended cloud session that prompt could stall it. The consumer
spelling (`Edit(**/agentTooling/self/orchestrations/**)`) stays as built. The history below
is how it got here.

The `--self` spelling (`Edit(**/self/orchestrations/**)`, `Edit(/self/orchestrations/**)`)
belongs in `SELF_POLICY_ASK_RULES`, but `--self`'s `.claude/settings.json` is tracked and
byte-checked against the generator, so adding it means regenerating that file
(`python3 -B hooks/wire-settings.py --self --repo <root> --write`). This feature was told
never to edit anything under `.claude/`, and the session's permission classifier refused
the regeneration as self-modification, so the self rule is not in this change. To finish
it: add the two strings to `SELF_POLICY_ASK_RULES` and to `SELF_ASK` in
`self/tests/hook-wiring.sh`, regenerate, and commit the settings file with them.

Round 2: the owner approved the regeneration. The implementer added both strings and ran
`python3 -B hooks/wire-settings.py --self --repo /home/user/agentTooling-delegate-cost-claims
--write`; the session's permission classifier refused it again ("Permission for this action
was denied by the Claude Code auto mode classifier. Reason: [Self-Modification]."). Per the
coordinator's instruction the refusal was not routed around: the two edits were reverted.
Round 3: dropped (above), so nothing is left to run.

## F2 — the session id

`orchestration-start.sh` refuses a session id (from `--session` or
`$CLAUDE_CODE_SESSION_ID`) that does not match `^[A-Za-z0-9_][A-Za-z0-9_-]*$` or is longer
than 128 characters (round 1, F13), before anything is written. Every id Claude Code issues
fits (UUIDs, `session_…`).

## F4 — the build-script judge

Two designs were on the table: skip a list of wrappers before taking the program's
basename, or deny when any word names a build script. The wrapper list was rejected: it is
a blacklist the next audit extends by one (`xargs`, `sudo`, `flock`, `find -exec`,
`setsid`, `env -S`, …), and the scripts' own refusal is spoofable through
`CLAUDE_CODE_SESSION_ID=…`, so the hook is the only judge that sees the real session.
"Any word" alone broke a standing contract (H3: `cat …/feature-start.sh` is not denied for
an orchestrator). So the rule is: a line that MENTIONS a build script (the name inside any
word, or a glob / brace group / `$…` substitution that could expand to one) is a run unless
every command on the line is a reader in `BUILD_SCRIPT_READERS` — programs that print a file
and run nothing it names (`cat`, `head`, `grep`, `wc`, …; not `sed`, `awk`, `find`, `git`,
`less`, which can run commands). A line that does not tokenize, or a heredoc, is read as
text with its quoting removed. Security audit round 1 (F10) showed that reading refused the
orchestrator's own records PR; the rule was narrowed as recorded below.

## Item 4 — the security audit as a lifecycle rule

Fitted to how `run-review.sh` queues plans: one pass drains `review/incomplete/` in sorted
order, the LAST plan's `plan_end` is the one the pass stamps with the verdict, and the one
live report is shared. So the audit is a review plan named `NN-audit-<model>` with the
review's NN — it sorts before `NN-review-…`, runs first, and leaves the review's plan_end as
the held one; it writes its own report (`<feature>/audit-report.md`, committed with the
round); the runner stamps a separate `audit_end` event with the same `head` as the review's
plan_end; and `latest_review_plan` / `completed_review_count` skip audit stems, so it is no
round of its own. A queue with an audit and no review after it is refused, since the pass
would stamp the review's verdict onto the audit. `feature-close.sh` diffs the base (no
fetch: `origin/<base>` when it exists) for the hook paths and requires the latest audit to
be clean at the judged head. The audit paths (widened in round 1, F6) are the same files under
`agentTooling/` in a consumer — so a consumer's subtree pull that changes the hook is audited
too, which costs one audit per such pull and was judged the safer reading of "touches
hooks/".

## Security audit (owner-required, separate from the review)

Recorded per round below: findings, then what was done.

- **Before round 1 (implementer's own check).** The PR #138 auditor's `probe.py`, re-run
  against this tree's `hooks/`: every F1 and F4 case it listed is now denied except
  `kind=coordinator` on a record with `features: []` — which led to the ledger (F1 above).
  The probe's `T`-session rows (another session) stay silent, as they should.
- **Round 1 (Fable auditor, started by the coordinator on e0ff998): `Verdict: findings`.**
  The implementer could not start it itself (no Agent tool; a fresh `claude -p` was refused
  by the permission classifier), so the coordinator did. Thirteen findings; F9 is the
  `--self` ask rule above, deferred then and dropped in round 3. Each other
  one, and what was done (probes turned into `self/tests/security-audit.sh` F1–F7,
  `hook-orchestrator-role.sh` H14–H16, `orchestrator-role.sh` G10, `coordinator-records.sh`):
  - **F1** — `<slug>: cost records` / `<slug>: PR` hid a hook change after the judged head.
    Those subjects now pass only when every file they touch is under the features directory
    (the capture commits sibling features' records a shared session is split with),
    and `feature-close.sh` refuses any `<judged head>..HEAD` diff touching an audit path.
  - **F2** — rename detection hid `git mv hooks hooks2` + a symlink. Every audit-path diff is
    `--no-renames -z`, and a directory prefix also matches its bare name (`hooks`,
    `agentTooling/hooks`).
  - **F3** — the review ran after the audit and could change the hook. **Chosen: fingerprint,
    not reordering.** The runner fingerprints the audit paths' working tree (path + blob id,
    a symlink by its target) when the audit plan finishes (`on_plan_finished`, a new optional
    callback in `plan-runner-lib.sh`'s `hold_or_stamp_plan_end`) and again at the stamp; any
    difference stamps the audit `stale`. Why not run the audit after the review: the pass
    stamps the verdict on the LAST plan's held `plan_end`, so the review must stay last, and
    a fingerprint also catches a change by anything else in between, uncommitted included.
  - **F4** — a forged plan file plus one `audit_end` line passed. The close now also requires
    the judged head's committed `audit-report.md` to open `Verdict: clean`, last written by a
    `<slug>: review round N` commit (`git log -1 <judged head> -- <report>`, so it is that
    head or an ancestor), and the audit stem to be the pinned model.
  - **F5** — any hand-queued audit replaced the template. When the diff touches an audit
    path, `run-review.sh` always renders the template with the pinned model and refuses a
    queued audit of another stem or a different body.
  - **F6** — the audit paths now include `plan-runner-roots.sh`, `feature-close.sh`,
    `run-review.sh`, `orchestration-start.sh`, `session-start.sh`,
    `templates/SECURITY_AUDIT.md`, `analysis/manifest.py` and `.claude/` (a prefix), under
    `agentTooling/` in a consumer; names are read NUL-separated, never quoted.
  - **F7** — the close refuses a manifest `base` that differs from its value at the judged
    head, and an empty `base...HEAD` diff (every feature's diff carries its own directory).
  - **F8** — (a) from an orchestrator session, the repo-code runners (`REPO_CODE_RUNNERS`:
    pytest, `python -m pytest`, npm/npx/yarn/pnpm, make, `gate.sh`, `check-plans.sh`) fall
    through to the human instead of `allow`; (b) ANSI-C `$'…'` and locale `$"…"` quoting, and
    extended globs, are read as the wildcard before tokenizing, and names are matched
    case-folded; (c) name-free indirection is documented as the limit in `hooks/README.md`
    → "The orchestrator role" rather than claimed closed.
  - **F10** — the inversion refused the orchestrator's own records PR. A pattern now counts
    only at command position and as an argument of a known launcher (`find`'s `-exec`
    commands judged as their own); git `commit|push|log|diff|show|grep|status|add` (no
    global option, no program-running flag), `gh pr|issue|api|repo|release`, `sed -n
    <addr>p` and `bash -n` are exempt like the readers; a whole-argument `"$(cat <<'EOF' …
    EOF)"` is read as its body. A literal name still counts in every command that launches a
    program. Every false positive the audit listed is in H15.
  - **F11** — records that cannot be listed no longer skip the ledger.
  - **F12** — the ledger is found without running git (the nearest `.git`, a `gitdir:` file,
    a worktree's `commondir`), read line by line with bad bytes replaced, a line naming the
    session counts whatever follows its slug, and the writer adds a newline before appending
    when the last line lacks one. **No git dir:** the WRITER only warns — the record it just
    wrote is still the role, and refusing would leave an orchestrator with no record at all —
    while the READER fails closed when a `.git` is there but cannot be resolved, or the ledger
    exists but cannot be read: it answers `LEDGER_UNREADABLE` for every session, with its own
    reason. A checkout whose `.git` is broken cannot build or commit anyway, so failing closed
    costs nothing real; a checkout with no `.git` at all has no ledger to expect and reads as
    none. Not addressed (accepted): the ledger is per clone and never pruned, and
    `--session <other id>` can make another session an orchestrator with no undo — both
    already true of the record itself.
  - **F13** — the session id is `^[A-Za-z0-9_][A-Za-z0-9_-]*$`, at most 128 characters, and
    the shell reader passes it after `--` (the CLI takes `[--reason] -- <dir> <id>`).
- **Round 2 (Fable auditor, on 003d344): `Verdict: findings`.** F1–F3, F5–F8, F10, F11, F13
  closed; twelve new findings. **N2, N3, N5, N6, N7** (name-matching holes in the hook) are
  HELD by the coordinator pending the owner's decision on an allowlist for orchestrator
  sessions. Done this round (probes turned into `security-audit.sh` N8–N11,
  `hook-orchestrator-role.sh` H17, `orchestrator-role.sh` G10j/k and G11,
  `coordinator-records.sh` K2):
  - **N1** — `bash -n +n f` / `bash -n +o noexec f` were approved for every session and ran
    f. `files_only` (behind `syntax_check_allowed`) and the build judge's `bash -n` exemption
    now refuse any word starting `-` or `+` after the one `-n` (`OPTION_PREFIXES`).
  - **N4** — a literal placeholder crashed the judge into "no deny". The heredoc placeholder
    carries a random token per call, `body_of` leaves an out-of-range index alone, and
    `build_script_denial` treats any exception as a run (a deny for a session with a record).
  - **N8** — the forged-audit route. `run-review.sh` refuses a hook change's review resumed
    from `inprogress/` with no audit beside it (queueing one in `incomplete/` would run it
    after the review). The close reads the audit plan from the judged head's tree, the
    `audit_end` from the first `<slug>: review stamps` commit after it (`git show`), holds the
    plan's body to the template (`audit_plan_matches_template`: the template with NN, slug,
    base and a files block of only `- \`path\`` lines), and a `cost records`/`PR` commit
    that touches an audit plan, `audit-report.md` or adds an `audit_end` line is refused.
  - **N9** — the stem, model and body checks apply to `inprogress/` too, and a review there
    counts as queued.
  - **N10** — the fingerprint carries the executable bit; a symlink at an audit path is
    refused outright, at the queue (`audit_symlinks`) and in the judged tree at the close
    (`audit_symlinks_at`), rather than hashed through.
  - **N11** — audit paths add `feature-start.sh`, `run-plans.sh`, `run-verify.sh`,
    `run-batch.sh` (every `refuse_orchestrator_session` caller), `plan-runner-lib.sh`,
    `stamp-timing.sh` and `self/gate.sh`; touched paths are the union of the diff against the
    manifest's base and against the default branch (`origin/HEAD`, else `origin/main`, else
    `main`; `audit_default_base`).
  - **N12** — a `.git` directory counts only if it holds `HEAD` (else unresolvable: fail
    closed), and the ledgers of every enclosing checkout are read (a nested `.git` no longer
    hides the consumer's). A junk `.git` still fails closed, and that denies only what the
    role denies — build scripts and implementer briefs, with the unreadable reason — never an
    ordinary command, so it does not lock a session out.
  - **The record as first committed (owner-approved).** `record_for_session` unions three
    sources: the working tree's records, each record as it was in the commit that ADDED it
    (`git log --relative --diff-filter=A` + `git show <commit>:./<path>`), and the ledgers.
    A committed orchestrator record edited in the working tree, or deleted, keeps the role in
    every clone; a genuine coordinator record committed as one stays exempt; a record never
    committed answers from the working tree and the ledger. **Git unavailable** (off PATH,
    failing) in a checkout is unreadable history: fail closed with the same reason as the
    ledger, consistent with F12 — a checkout where git cannot run cannot build or commit
    anyway. A checkout with no commit yet has no history and reads as none.
  - **F9** — refused again by the permission classifier; later dropped by the owner (see
    "Dropped: the `--self` ask rule" above).
- **Round 3 design (owner-approved): an allowlist for orchestrator sessions.** It replaces
  name matching for those sessions and closes N2, N3, N5, N6 and N7 by construction.
  `hooks/allow-repo-commands.sh`: when `orchestrator_record` (the three-source lookup) names
  the session, every Bash line is denied unless every command on it matches the table
  (`orchestrator_command_allowed`, the `ORCHESTRATOR_*` block); a match goes on through every
  existing judge (push rules, shape denies, approval). The denial is the role's reason plus
  `ORCHESTRATOR_ALLOWLIST_TEXT`. Documented in `hooks/README.md` → "The orchestrator role"
  and `ORCHESTRATION.md` → "Cloud sessions".
  - **Retired:** `runs_repo_code` and `REPO_CODE_*` (round 1's F8a fall-through: the
    allowlist denies every runner outright), and the name-matching build-script judge FOR
    ORCHESTRATORS — main() no longer calls it for them.
  - **Kept:** `invokes_build_script` / `build_script_denial` and their constants, for one
    case: a checkout whose role cannot be read (`LEDGER_UNREADABLE`). There every session is
    refused building and nothing else; applying the allowlist instead would lock every
    session out of ordinary commands in a checkout with a broken `.git` (round 2, N12's
    requirement). Also kept: `files_only`'s `-`/`+` rule (N1), which binds every session.
  - **Dropped from round 1's sanctioned list:** `git grep` (not among the allowed git read
    subcommands, and it runs a pager program by flag), `bash -n` (no shell is on the list),
    `find -exec …` (forbidden), `echo $HOME`, `jq`/`ls`/`wc` over globs and a `for` loop (no
    expansion is a plain literal). Each is now the allowlist denial (H18): read with the
    Read/Grep/Glob tools, or hand it to a `feature: none` subagent.
  - **Not on the list, and not asked for:** `cd`. An orchestrator's commands run from its
    session's directory; one that needs another directory hands the work to a subagent.
  - **Cost:** the role is now looked up on every Bash call of every session (one
    `os.listdir`, one `git log` over `self/orchestrations/`, a `git show` per record —
    about 80 ms here), since the allowlist needs it before any other judge.
  - **Proof other sessions are unchanged:** H20 runs round 2's 133-command regression set
    (c6) through this hook and `origin/main`'s, both profiles, byte-identical.
- **Round 3 (on 717cc075): `Verdict: findings`.** Round 2's N1, N4, N8–N12 closed; round 1's
  F1–F7 hold; ordinary sessions byte-identical to main apart from the N1 fix. F9 dropped by
  the owner (above). Probes turned into `hook-orchestrator-role.sh` H21 (all 675 rows of
  a1–a4/a6: the 205 the allowlist admits are not its denial, every other row is denied) and
  H22, and `orchestrator-role.sh` G12.
  - **R1** — the heredoc and branch expansions were matched on the raw line, blind to
    quoting. `orchestrator_words` now recognises them itself, only where an unquoted `"`
    begins a fresh word and the closing `)"` is followed by the end, a blank or a separator;
    each is one placeholder word, nothing may be glued to it; the raw substitutions are gone.
    The heredoc's terminator must now be followed by a newline before `)"`. Lines past
    `ORCHESTRATOR_MAX_LINE_CHARS` (20 000) are refused unread.
  - **R2** — entry points are resolved: `realpath(join(cwd, word))` must equal the hook's own
    `<tooling>/orchestration-start.sh`, `…/analysis/report.py` and so on, so the unprefixed
    spelling in a consuming repo and a planted copy anywhere are not entry points. The
    residual route is editing the real tooling files — and those are audit paths, so a
    feature that edits them is audited. The general basename approval for ordinary sessions
    (`harness_entry_allowed`) is untouched: changing it would change every session's answers,
    which H20 holds byte-identical.
  - **R3** — push and fetch branches must match `^[A-Za-z0-9][A-Za-z0-9._/-]*$` with no `..`.
  - **R4** — `record_for_session` asks every source; a real record from any wins, and
    `LEDGER_UNREADABLE` is returned only when none names the session. **Chosen for the
    unreadable fallback: document the residual, keep the name matching.** Reaching it now
    takes every source failing to name the session: git unusable AND no ledger line AND the
    working-tree record edited away. In that state the old build-script deny still refuses
    the build scripts by name for every session, and N2/N3/N5/N6-style indirection would
    pass it; applying the allowlist instead would lock every session in a broken checkout
    out of ordinary commands, which N12 ruled out.
  - **R5** — `git log -m` (merges diffed against each parent) sees a record added only in a
    merge. A commit listed in `<common dir>/shallow` is never read as a record's add.
    **Deviation, stated:** such a record is SKIPPED by the history source rather than failing
    it closed — a shallow clone, a cloud session's default, would otherwise refuse building to
    every session — and the working tree and the ledger still answer for it; `git fetch
    --unshallow` restores the history source. **Limit, documented:** a record whose FIRST
    commit already says `kind: coordinator` (written that way before it was ever committed)
    is read as a coordinator by the history source; only the ledger, written by
    `orchestration-start.sh` without `--coordinator`, still names such a session, and only on
    the machine that ran the start.
  - **R6** — the history is one `git log -m --diff-filter=A -p` over `self/orchestrations/`,
    parsed in-process, under one 3 s deadline (`HISTORY_DEADLINE_SECONDS`); a timeout is
    unreadable history and falls back as R4 says. 300 records: ~50 ms (G12e). No cache.
  - **R7** — `uniq` counts operands after `--`; `capture_planning.py` needs exactly one
    `--list-sessions`/`--list-subagents` and no `--`; `report.py` takes only `--orchestration
    <slug>` (`SLUG_RE`) and `--checkout` pairs; `gh pr view|list|checks` refuse `--web`,
    `--watch`, `-R`, `--repo`; `tail` refuses `-f`/`-F`/`--follow`/`--pid`; `diff` refuses
    `-l`/`--paginate`; git reads refuse `--show-signature` and a `%G` format;
    `orchestration-start.sh --session` is refused; `git add` refuses a path holding a `.git`
    entry, or one that IS inside a `.git`.
  - **R8** — the deny text, `hooks/README.md` and `ORCHESTRATION.md` now send other work to a
    SEPARATE session (`create_session`, or `send_message` to an implementer) or the human, and
    say an in-process subagent shares the session id: the Read, Grep and Edit tools, the same
    Bash list. `agent_id` is not exempted (it would reopen delegated builds).
  - **F9 docs** — the four remaining "deferred" mentions now say "dropped" and point at the
    NOTES.md section (`hooks/wire-settings.py`, `hooks/README.md`, the feature README,
    `self/tests/hook-wiring.sh`).
- **Round 4 (on f8dcd335): `Verdict: findings`.** R1–R8 closed, no regression in F or N.
  - **HIGH — `printf -v` runs code.** `printf -v 'x[$(touch pwned)]' a` was admitted: bash
    evaluates an array subscript arithmetically, and arithmetic evaluation runs the command
    substitution. `ORCHESTRATOR_READER_FORBIDDEN` now holds `printf`: `v` in any short
    spelling (`-v`, `-vname`, a cluster) is refused (H23). **The other builtin readers,
    checked:** `echo` takes only `-n`/`-e`/`-E` and prints its arguments; `pwd` takes only
    `-L`/`-P`; printf's FORMAT and ARGUMENTS are not evaluated (`%d` takes a plain number, and
    a non-number is an error, never an expression); none of them assigns a variable once `-v`
    is gone. Every other reader on the list is an external program, which cannot reach the
    shell's arithmetic.
  - **Defence in depth — a symlinked entry point.** The hook refuses an entry-point word that
    is itself a symlink (`os.path.islink`, before the R2 realpath comparison), and
    `orchestration-start.sh` / `orchestration-capture.sh` resolve `SCRIPT_DIR` through every
    link (`readlink` loop, `pwd -P`) before sourcing anything, so a link beside a planted
    `plan-runner-roots.sh` sources the real library (`coordinator-records.sh` K1). The python
    entry points need nothing: python puts the script's resolved directory on `sys.path`.
- **Round 5 (on 2deec884): `Verdict: clean`, no findings.** Both round-4 fixes hold (`printf
  -v` in every spelling, the symlinked entry point). Structurally, the orchestrator path only
  ever ADDS denies — it never emits an allow of its own; an admitted line goes on to the same
  judges as any session's. On the round-3 corpus a non-orchestrator matches main on 676 of
  677 rows, the one difference being the intended N1 fix (`bash -n +n`). The role lookup, the
  fail-closed build deny and the shallow-clone handling held.

## Lifecycle round 1 (review + templated audit, both escalated)

The first `run-review.sh` pass queued `01-audit-opus` from the template beside
`01-review-opus`. The audit found two bypasses and the review escalated on them
(`escalations/01-audit-opus.md`, `escalations/01-review-opus.md`). The review could not apply
B1 itself: the `Edit(**/hooks/**)` ask rule held its edit for a human, as designed. Round 2's
fixes:
- **B1 — `uniq - OUT` wrote a file.** `orchestrator_operands` counted only words not starting
  with `-`, so the bare `-` (stdin) was dropped and `uniq - OUT` named one operand. A bare `-`
  is now an operand (`is_orchestrator_operand`, `ORCHESTRATOR_STDIN_OPERAND`). Tests: `uniq -
  out`, `echo x | uniq - out`, `uniq -c - out`, `uniq --skip-fields=1 - out` are denied (H21
  rows); `echo '#!/bin/sh' | uniq - -hook` stays admitted (one operand).
- **B2 — the audit trigger missed what the allowlist executes.** `orchestration-capture.sh`,
  `analysis/report.py`, `analysis/capture_planning.py`, `analysis/orchestration_capture.py`
  and the modules they import were no audit paths, so round 3's R2 note ("the residual route
  is editing the real tooling files, which are audit paths") was false for them. **Decided:
  `analysis/` whole, plus `orchestration-capture.sh`.** A list of imports would drift with
  every new import; the cost is that a feature touching only `analysis/` now gets a security
  audit too. `security-audit.sh` F6 adds `orchestration-capture.sh` and `analysis/roots.py`;
  R3's non-hook fixture moved from `analysis/notes.txt` to `docs-notes.txt`.

## Lifecycle round 2 (review clean, templated audit escalated)

`02-review-opus` came back clean; `02-audit-opus` escalated with two bypasses
(`escalations/02-audit-opus.md`). B1 and B2 held. Round 3's fixes:
- **A1 — `git add` staged a planted nested repository.** Through pathspec magic (`:/sub`,
  `':(glob)s*'`), a glob (`'s*'`, quoted globs being git pathspecs too), `:/`, or a parent
  directory (`git add self` over `self/deep/.git`), a gitlink was staged, and `git status` —
  admitted and approved — then ran the planted `core.fsmonitor`. **Chosen: explicit file
  paths only**, over walking each directory for a `.git`: every argument must be an existing
  regular file (`os.path.isfile`, no symlink), with no leading `:` or `-`, no glob character,
  and no `.git` component. It is the smaller rule and cannot miss a depth or a pathspec form;
  the orchestrator's only `git add` is its record's README, a file. Test: H24.
- **A2 — `date MMDDhhmm` set the clock.** GNU date's operand form sets the system time, past
  the `-s`/`--set` rule. `date` is admitted only when every operand is a `+FORMAT`; the values
  of `-d`/`--date`, `-f`/`--file`, `-r`/`--reference` are taken as theirs
  (`orchestrator_date_reads_only`). Test: H24 (`date 010100002020`, `date -u …`, `date
  --utc …`, `date 01010000.00`, `date -R …` denied; `date`, `date -u +%Y…`, `date -d … +%s`,
  `date -r <file>` admitted).

## Lifecycle round 3 (review clean, templated audit escalated)

`03-review-opus` came back clean; `03-audit-opus` escalated with one bypass
(`escalations/03-audit-opus.md`); the `git add` rule held.
- **C1 — `date -Id MMDDhhmm` set the clock.** GNU date's `-I` takes the rest of its word as an
  optional attached argument, so in `-Id` the `d` is `-I`'s, not the `-d` option; the scan read
  it as `-d` and skipped the next word, the clock-setting operand. The short-cluster scan now
  stops at `I` (`ORCHESTRATOR_DATE_OPTIONAL_ATTACHED`), the only such option in date's
  `d:f:I::r:Rs:u`. Test: H24 denies `date -Id 010100002020`, `-uId`, `-uuId`; admits `date
  -Id` and `date -uId +%s`.

