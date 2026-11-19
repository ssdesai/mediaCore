#!/usr/bin/env bash
set -uo pipefail

# Self-test for the hook half of the brief-header rule (self/features/delegate-cost-claims):
# hooks/allow-repo-commands.sh sends back an `Agent` call whose prompt's first non-empty
# line is not a brief header (hooks/brief_header.py) with a deny naming the line to put
# first, and lets every headed brief through without a word. Run by self/gate.sh, or by
# hand: bash self/tests/hook-brief-header.sh
#
# Fixtures, under mktemp -d, each with the hook's files copied in (brief_header.py beside
# orchestrator_role.py, policy.py and env_profile.py) and an orchestration record whose
# fence `session` is S:
#   C  a consuming repo — the hook under agentTooling/hooks/;
#   S  agentTooling's own shape — the hook under hooks/.
# Every case is fed the PreToolUse payload under BOTH profiles, local and cloud.
#
# Asserts:
#   G1. an Agent whose prompt has no header — plain text, the header below the first line,
#       `feature: x` with no slash, a header with a trailing remark — is denied, from any
#       session (the orchestrator's included: none of them is a feature header, so none is
#       the role's), with a reason naming `feature: <repo>/<slug>`, `feature: none — <reason>`
#       and why (cost attribution);
#   G2. a prompt opening `feature: <repo>/<slug>` (blank lines and indentation before it
#       allowed) or `feature: none — <reason>` from a session that is no orchestrator
#       prints nothing — never an allow;
#   G3. the orchestrator rule is untouched: from S a `feature: <repo>/<slug>` prompt is
#       still denied with the ROLE reason, not the header one;
#   G4. an Agent with no prompt, or a non-string one, prints nothing and exits 0;
#   G5. a copy of hooks/ without brief_header.py leaves the rule silent (the guarded
#       import), so a headerless prompt prints nothing there;
#   G6. agentTooling's own settings wire the hook for the Agent matcher, so the rule
#       reaches a session (the consuming repo's wiring is hook-wiring.sh's).
# Every invocation pins the profile and clears CLAUDE_CODE_REMOTE. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-brief-header.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-brief-header"
python3 - "$AT" "$TMP" <<'PY'
import json, os, shutil, subprocess, sys

AT, TMP = sys.argv[1], sys.argv[2]
HOOK_FILES = ("allow-repo-commands.sh", "policy.py", "env_profile.py", "orchestrator_role.py",
              "shared_rules.py", "brief_header.py")
HOOK_NAME = "allow-repo-commands.sh"
RECORD_REL = "self/orchestrations/wave/README.md"
SESSION_S = "5e5e5e5e-0000-0000-0000-000000000001"
SESSION_T = "7a7a7a7a-0000-0000-0000-000000000002"
ROLE_MARK = "is the orchestrator of"
HEADER_MARKS = ("feature: <repo>/<slug>", "feature: none", "cost")
PROFILE_ENV = "AGENTTOOLING_PROFILE"
REMOTE_ENV = "CLAUDE_CODE_REMOTE"
PROFILES = ("local", "cloud")
DENY, ALLOW, ASK, SILENT, ERR = "DENY", "ALLOW", "ASK", "silent", "ERR"
HEADLESS = (
    ("plain text", "Build four fixes in agentTooling."),
    ("the header below the first line", "Build it.\nfeature: agentTooling/x"),
    ("`feature: x` with no slash", "feature: x\nbuild"),
    ("a header with a trailing remark", "feature: agentTooling/x (setup)\nbuild"),
    ("an empty prompt", "   \n"),
)
HEADED = (
    ("`feature: <repo>/<slug>`", "feature: agentTooling/x\nbuild"),
    ("blank lines and indentation before the header", "\n\n   feature: musicMap/y  \nbuild"),
    ("`feature: none — <reason>`", "feature: none — read-only analysis\nread it"),
    ("`feature: none - <reason>`", "feature: none - audit\nread it"),
)


def new_fixture(root, hook_dir, tooling_dir, files=HOOK_FILES):
    os.makedirs(root)
    hooks = os.path.join(root, hook_dir)
    os.makedirs(hooks)
    for name in files:
        shutil.copy2(os.path.join(AT, "hooks", name), os.path.join(hooks, name))
    record = os.path.normpath(os.path.join(root, tooling_dir, RECORD_REL))
    os.makedirs(os.path.dirname(record))
    with open(record, "w") as f:
        f.write("# Orchestration: wave\n\n```json\n%s\n```\n" % json.dumps(
            {"slug": "wave", "session": SESSION_S, "features": []}))
    subprocess.run(["git", "-C", root, "init", "-q"], check=True, capture_output=True)
    return os.path.join(hooks, HOOK_NAME)


FIXTURES = {
    "consumer": (os.path.join(TMP, "consumer"), os.path.join("agentTooling", "hooks"), "agentTooling"),
    "self": (os.path.join(TMP, "self-shape"), "hooks", "."),
}
HOOKS = {name: (root, new_fixture(root, hook_dir, tooling))
         for name, (root, hook_dir, tooling) in FIXTURES.items()}
BARE_ROOT = os.path.join(TMP, "bare")
BARE_HOOK = new_fixture(BARE_ROOT, "hooks", ".",
                        tuple(f for f in HOOK_FILES if f != "brief_header.py"))


def run_hook(hook, root, payload_text, profile):
    env = {k: v for k, v in os.environ.items()
           if k not in (PROFILE_ENV, REMOTE_ENV, "CLAUDE_PROJECT_DIR")}
    env.update({"CLAUDE_PROJECT_DIR": root, "TMPDIR": TMP, "HOME": TMP, PROFILE_ENV: profile})
    return subprocess.run([hook], input=payload_text, capture_output=True, text=True, env=env)


def decode(p):
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


def agent(hook, root, profile, tool_input, session):
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


def header_reason(reason):
    return all(mark in reason for mark in HEADER_MARKS) and ROLE_MARK not in reason


for name, (root, hook) in HOOKS.items():
    for profile in PROFILES:
        tag = "%s/%s" % (name, profile)
        for label, prompt in HEADLESS:
            # The role rule reads the same parse, so a headless prompt — even one opening
            # `feature: ` that is not a header — reaches the header rule from the
            # orchestrator too; only a real feature header is the role's (G3).
            sessions = [("another session", SESSION_T), ("no session_id", None),
                        ("the orchestrator", SESSION_S)]
            for who, session in sessions:
                decision, reason = agent(hook, root, profile, {"prompt": prompt}, session)
                check("G1 [%s] %s from %s is sent back naming the header" % (tag, label, who),
                      decision == DENY and header_reason(reason), "%s: %s" % (decision, reason))
        for label, prompt in HEADED:
            decision, reason = agent(hook, root, profile, {"prompt": prompt}, SESSION_T)
            check("G2 [%s] %s prints nothing" % (tag, label), decision == SILENT,
                  "%s: %s" % (decision, reason))
        decision, reason = agent(hook, root, profile, {"prompt": HEADED[0][1]}, SESSION_S)
        check("G3 [%s] from the orchestrator a feature brief is still the ROLE denial" % tag,
              decision == DENY and ROLE_MARK in reason, "%s: %s" % (decision, reason))
        for label, tool_input in (("no prompt", {"description": "x"}),
                                  ("a non-string prompt", {"prompt": 12})):
            decision, reason = agent(hook, root, profile, tool_input, SESSION_T)
            check("G4 [%s] an Agent with %s prints nothing" % (tag, label), decision == SILENT,
                  "%s: %s" % (decision, reason))

for profile in PROFILES:
    decision, reason = agent(BARE_HOOK, BARE_ROOT, profile, {"prompt": HEADLESS[0][1]}, SESSION_T)
    check("G5 [%s] without brief_header.py a headerless prompt prints nothing" % profile,
          decision == SILENT, "%s: %s" % (decision, reason))

with open(os.path.join(AT, ".claude", "settings.json")) as f:
    settings = json.load(f)
agent_entries = [e for e in settings.get("hooks", {}).get("PreToolUse", [])
                 if e.get("matcher") == "Agent"]
check("G6 agentTooling's settings wire allow-repo-commands.sh for the Agent matcher",
      any(HOOK_NAME in h.get("command", "") for e in agent_entries for h in e.get("hooks", [])),
      agent_entries)

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-brief-header: all checks passed"; else echo "hook-brief-header: FAILED"; fi
exit "$rc"
