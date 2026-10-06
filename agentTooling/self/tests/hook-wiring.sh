#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/wire-settings.py, the merge that sync-plans.sh runs to put the
# PreToolUse hook entry, the Edit and Bash deny rules and the hooks/ ask rule into a
# consuming repo's .claude/settings.json (hooks/README.md). Run by self/gate.sh, or by
# hand: bash self/tests/hook-wiring.sh
#
# Builds thirty throwaway repos under mktemp -d, one per starting state of the settings
# file — absent, unrelated content only, hook only, deny rules only, a partial deny list
# with a repo's own rule in it, the hook and the Edit rules but no Bash rules, everything
# but the ask rule, everything but the sandbox block, complete, complete plus a RETIRED
# rule (`Bash(git stash:*)`, which the write removes and nothing else with it), a sandbox
# block carrying the repo's own domain, denyRead path and excludedCommands, a sandbox
# switched off by hand, the complete block with only `enabled` flipped against the
# generator's switch, a different hook, and twelve malformed shapes (three of them an
# explicit null, which a write would otherwise crash on) — and asserts,
# for each, that --check and --write report the documented status and exit code and agree
# with each other; that after a write every deny and ask rule is present and exactly one
# hook entry mentions the script; that nothing the repo already had is removed or changed,
# including its own deny and allow rules and a hand-customized hook path; and that a
# second write reports kept with the file byte-identical while --check reports in-sync.
# A file carrying the hook and the Edit rules and no Bash rules reports UNWIRED naming
# the count of missing Bash rules, and the write appends exactly those, in order.
#
# The SessionStart entry (self/DESIGN-2026-10-05-cloud-execution.md §7): every written
# consumer file carries exactly one SessionStart hook running plans/cloud-setup.sh — added
# once, never duplicated (the second write is byte-identical), a repo's customized
# spelling of it kept as the entry, a repo's own unrelated SessionStart hook kept first;
# a file complete but for it reports UNWIRED naming only it; a SessionStart that is not a
# list is INVALID; and --self writes none (no plans/cloud-setup.sh exists there).
# Malformed files are reported INVALID by both modes and left untouched.
#
# The sandbox block (self/features/runner-sandbox): every written file has
# sandbox.enabled equal to wire-settings.py's SANDBOX_ENABLED switch — OFF today
# (self/features/sandbox-consumer-reads) — failIfUnavailable and
# allowUnsandboxedCommands=false (the generator owns those three and overrides a repo's in
# either direction: a repo that switched the sandbox on by hand is switched back to the
# constant), no autoAllowBashIfSandboxed, the three secret denyRead paths and every
# generator domain; a repo's own domains, denyRead paths and unowned sandbox keys are kept
# where they stood and the generator's are unioned in after.
#
# The Bash deny list is NOT retyped here: it is rendered from hooks/policy.py, the one
# table the hook reads too, so a rule added to the table reaches this test with nobody
# editing it (self/tests/policy-table.sh asserts the rendering itself).
#
# Three more repos cover --self, where the one file, .claude/settings.json, is wholly
# GENERATED rather than merged, and tracked (self/features/self-cloud-bootstrap): it
# carries this checkout's hook path — guarded, a no-op where
# ${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh does not exist — and the ask rule
# Edit(**/hooks/**) + Edit(/hooks/**) in place of the vendored spelling, and no
# SessionStart entry; --self writes no settings.local.json. --check compares it BYTE FOR
# BYTE with a fresh write, so a hand-added allow rule, a repointed hook command or a
# missing file fails it where the merge check would have passed, and --write restores
# those bytes. The checkout's own tracked file is checked with it, the same call
# self/gate.sh records. No allow rule is ever added. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-wiring"
python3 - "$AT/hooks/wire-settings.py" "$TMP" "$AT" <<'PY'
import json, os, subprocess, sys

HELPER, TMP, AT = sys.argv[1], sys.argv[2], sys.argv[3]
# The prefix-rule twin of the hook's git deny comes from the table both scripts read
# (hooks/policy.py), never from a list retyped here — that duplication is the defect
# this feature closed.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(HELPER))
import policy

HOOK_ENTRY = {"matcher": "Bash", "hooks": [{"type": "command",
              "command": "/custom/path/allow-repo-commands.sh"}]}
HOOK_COMMAND = "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh"
# agentTooling's own command is guarded: the file is tracked and ships with the subtree,
# so where the script is absent (a consuming repo's root) it must be a silent exit 0.
SELF_HOOK_PATH = "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"
SELF_HOOK_COMMAND = 'test ! -f "%s" || "%s"' % (SELF_HOOK_PATH, SELF_HOOK_PATH)
# The SessionStart entry (self/DESIGN-2026-10-05-cloud-execution.md §7): the repo's seeded
# plans/cloud-setup.sh, once per container. The guard is the script's own — it asks
# env-profile.sh and is a no-op outside the cloud profile — so the entry names nothing but
# the script, and every session start runs it. Recognised by the script's name, so a
# repo's customized entry (a matcher, another spelling) is kept and never doubled.
SESSION_MARKER = "cloud-setup.sh"
SESSION_COMMAND = "${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh"
SESSION_ENTRY = {"hooks": [{"type": "command", "command": SESSION_COMMAND}]}
SESSION_CUSTOM = {"matcher": "startup", "hooks": [{"type": "command",
                  "command": "bash /custom/plans/cloud-setup.sh"}]}
OTHER_SESSION = {"hooks": [{"type": "command", "command": "/x/warm-cache.sh"}]}
# Both hook entries, as a complete file carries them
WIRED_HOOKS = {"PreToolUse": [HOOK_ENTRY], "SessionStart": [SESSION_ENTRY]}
# The Edit deny rules, then the Bash rules rendered from the table. The policy's own
# rule is no longer among them: hooks/ is an ASK rule now, so an attended session is
# prompted and a headless executor, which cannot answer, is refused.
EDIT_DENY = ["Edit(/.git/**)", "Edit(**/.git/**)", "Edit(**/.git)", "Edit(/.claude/**)",
             "Edit(**/.claude/**)", "Edit(**/.venv/**)", "Edit(**/venv/**)",
             "Edit(**/node_modules/**)"]
BASH_DENY = list(policy.bash_deny_rules())
ALL_DENY = EDIT_DENY + BASH_DENY
# Rules this helper once wrote and the table no longer renders. A merge removes exactly
# these — `Bash(git stash:*)` denied `git stash list` too, and a deny rule beats the
# hook's allow — and nothing else the repo carries.
RETIRED = list(policy.retired_bash_deny_rules())
ASK = ["Edit(**/agentTooling/hooks/**)"]
SELF_ASK = ["Edit(**/hooks/**)", "Edit(/hooks/**)"]
OK_WRITE = ("created", "wired", "kept")
SETTINGS_FILE = "settings.json"
# Claude Code's own per-user file; --self never generates it (self-cloud-bootstrap)
LOCAL_FILE = "settings.local.json"

# The OS sandbox block (self/features/runner-sandbox). The generator OWNS three scalars
# and the secrets-only denyRead; allowedDomains starts from at least these and grows with
# what a real run needed. `enabled` is wire-settings.py's SANDBOX_ENABLED switch, OFF
# since sandbox-consumer-reads: under the user's blockReadsOutsideWorkingDirectories a
# sandboxed verify pass cannot read the Playwright cache, and a repo's allowRead cannot
# re-open it. Flip SANDBOX_ENABLED_EXPECTED here together with that constant.
# failIfUnavailable and allowUnsandboxedCommands=false stay written: inert while off,
# correct once on. autoAllowBashIfSandboxed is never written: Bash approval stays the
# runner's --allowedTools. The write-deny of .git/hooks, .git/config and .claude/settings*
# is Claude Code's built-in list, on whenever enabled=true, so it is not in the block.
SANDBOX_ENABLED_EXPECTED = False
SANDBOX_OWNED = {"enabled": SANDBOX_ENABLED_EXPECTED, "failIfUnavailable": True,
                 "allowUnsandboxedCommands": False}
SANDBOX_DENY_READ = ["~/.ssh", "~/.aws", "~/.config/gh"]
SANDBOX_MIN_DOMAINS = ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org",
                       "api.anthropic.com", "github.com", "api.github.com",
                       "objects.githubusercontent.com"]
# A consuming repo's own additions, which a merge keeps where they stand
OWN_DOMAIN = "internal.example.invalid"
OWN_DENY_READ = "~/.netrc"
OWN_EXCLUDED = ["docker"]


def generated_sandbox():
    """The block a write into an empty repo produces: the generator's full domain list,
    read from its output rather than retyped, so a domain added after a validation run
    reaches this test with nobody editing it."""
    repo = os.path.join(TMP, "sandbox-reference")
    os.makedirs(repo)
    subprocess.run(["python3", HELPER, "--repo", repo, "--write"], capture_output=True)
    with open(os.path.join(repo, ".claude", "settings.json")) as f:
        return json.load(f).get("sandbox", {})


GEN_SANDBOX = generated_sandbox()
GEN_DOMAINS = list(((GEN_SANDBOX.get("network") or {}).get("allowedDomains")) or [])


def sandbox_with(**overrides):
    block = json.loads(json.dumps(GEN_SANDBOX))
    block.update(overrides)
    return block


CONSUMER_SANDBOX = {
    "enabled": True, "failIfUnavailable": True, "allowUnsandboxedCommands": False,
    "excludedCommands": list(OWN_EXCLUDED),
    "filesystem": {"denyRead": [OWN_DENY_READ, SANDBOX_DENY_READ[0]]},
    "network": {"allowedDomains": [OWN_DOMAIN] + GEN_DOMAINS[:2]},
}
DISABLED_SANDBOX = sandbox_with(enabled=False, allowUnsandboxedCommands=True,
                                failIfUnavailable=False)

CASES = {
    "fresh":        (None, "missing", "created"),
    "other-only":   ({"permissions": {"allow": ["Bash(git status)"]}, "env": {"X": "1"}},
                     "UNWIRED", "wired"),
    "hook-only":    ({"hooks": {"PreToolUse": [HOOK_ENTRY]}}, "UNWIRED", "wired"),
    "deny-only":    ({"permissions": {"deny": list(ALL_DENY)}}, "UNWIRED", "wired"),
    "partial-deny": ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": ALL_DENY[:3] + ["Edit(/secrets/**)"]}},
                     "UNWIRED", "wired"),
    "edit-only":    ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(EDIT_DENY), "ask": list(ASK)}},
                     "UNWIRED", "wired"),
    "no-ask":       ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY)}}, "UNWIRED", "wired"),
    "no-sandbox":   ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)}},
                     "UNWIRED", "wired"),
    "complete":     ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": sandbox_with()},
                     "in-sync", "kept"),
    "retired":      ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": ["Edit(/secrets/**)"] + RETIRED
                                      + list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": sandbox_with()},
                     "UNWIRED", "wired"),
    "sandbox-own":  ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": CONSUMER_SANDBOX},
                     "UNWIRED", "wired"),
    "sandbox-off":  ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": DISABLED_SANDBOX},
                     "UNWIRED", "wired"),
    # The complete block with ONLY `enabled` flipped away from the switch — a repo that
    # turned the sandbox on by hand while the generator has it off (or the reverse, once
    # the switch is flipped). The generator owns `enabled`, so it is set back.
    "enabled-flip": ({"hooks": dict(WIRED_HOOKS),
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": sandbox_with(enabled=not SANDBOX_ENABLED_EXPECTED)},
                     "UNWIRED", "wired"),
    # The SessionStart entry (design §7): complete but for it, a repo's own customized
    # spelling of it (kept, never doubled), and a repo's own unrelated SessionStart hook
    # (kept where it stood, ours appended after it).
    "no-session":   ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                      "sandbox": sandbox_with()},
                     "UNWIRED", "wired"),
    "session-custom": ({"hooks": {"PreToolUse": [HOOK_ENTRY], "SessionStart": [SESSION_CUSTOM]},
                        "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                        "sandbox": sandbox_with()},
                       "in-sync", "kept"),
    "session-other": ({"hooks": {"PreToolUse": [HOOK_ENTRY], "SessionStart": [OTHER_SESSION]},
                       "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)},
                       "sandbox": sandbox_with()},
                      "UNWIRED", "wired"),
    "other-hook":   ({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                        {"type": "command", "command": "/x/other.sh"}]}]}}, "UNWIRED", "wired"),
    "broken":       ("{not json", "INVALID", "INVALID"),
    "hooks-list":   ({"hooks": []}, "INVALID", "INVALID"),
    "event-dict":   ({"hooks": {"PreToolUse": {}}}, "INVALID", "INVALID"),
    "session-dict": ({"hooks": {"SessionStart": {}}}, "INVALID", "INVALID"),
    "perms-list":   ({"permissions": []}, "INVALID", "INVALID"),
    "deny-dict":    ({"permissions": {"deny": {}}}, "INVALID", "INVALID"),
    "ask-dict":     ({"permissions": {"ask": {}}}, "INVALID", "INVALID"),
    "top-list":     ([], "INVALID", "INVALID"),
    "sandbox-list": ({"sandbox": []}, "INVALID", "INVALID"),
    "domains-dict": ({"sandbox": {"network": {"allowedDomains": {}}}}, "INVALID", "INVALID"),
    # An explicit null is not an absence: a write would setdefault() into it and crash
    "sandbox-null": ({"sandbox": None}, "INVALID", "INVALID"),
    "domains-null": ({"sandbox": {"network": {"allowedDomains": None}}}, "INVALID", "INVALID"),
    "deny-null":    ({"permissions": {"deny": None}}, "INVALID", "INVALID"),
}


def setup(name, content):
    repo = os.path.join(TMP, name)
    os.makedirs(repo)
    if content is not None:
        os.makedirs(os.path.join(repo, ".claude"))
        with open(os.path.join(repo, ".claude", "settings.json"), "w") as f:
            f.write(content if isinstance(content, str) else json.dumps(content))
    return repo


def run(repo, mode, self_mode=False):
    argv = ["python3", HELPER] + (["--self"] if self_mode else []) + ["--repo", repo, mode]
    p = subprocess.run(argv, capture_output=True, text=True)
    status, _, message = p.stdout.strip().partition("\t")
    return status, message, p.returncode


def read(repo, name=SETTINGS_FILE):
    with open(os.path.join(repo, ".claude", name)) as f:
        return json.load(f)


def raw(repo, name=SETTINGS_FILE):
    with open(os.path.join(repo, ".claude", name), "rb") as f:
        return f.read()


def write_raw(repo, settings, name=SETTINGS_FILE):
    with open(os.path.join(repo, ".claude", name), "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")


fails = 0


def check(name, cond, detail=""):
    global fails
    if cond:
        print("  ok    %s" % name)
    else:
        fails += 1
        print("  FAIL  %s%s" % (name, (" — " + detail) if detail else ""))


for name, (content, want_check, want_write) in CASES.items():
    repo = setup(name, content)
    before_raw = raw(repo) if content is not None else None
    status, message, rc = run(repo, "--check")
    check("%s: --check reports %s" % (name, want_check),
          status == want_check and rc == (0 if status == "in-sync" else 1),
          "got %s rc=%d" % (status, rc))
    if name == "edit-only":
        # The one gap is the Bash rules, and the message says how many and which kind
        check("edit-only: --check names the %d missing Bash rules" % len(BASH_DENY),
              ("%d Bash deny rule(s)" % len(BASH_DENY)) in message
              and "Edit deny rule" not in message and "ask rule" not in message
              and "hook" not in message, message)
    if name == "no-ask":
        # The ask rule is maintained with the same merge rules as a deny rule, and is
        # named in the gap message as its own kind
        check("no-ask: --check names the missing ask rule and nothing else",
              ("%d Edit ask rule(s)" % len(ASK)) in message
              and "deny rule" not in message and "hook" not in message, message)
    if name == "no-sandbox":
        check("no-sandbox: --check names the missing sandbox block and nothing else",
              "sandbox" in message and "rule(s)" not in message and "hook" not in message,
              message)
    if name == "no-session":
        check("no-session: --check names the missing SessionStart entry and nothing else",
              SESSION_MARKER in message and "SessionStart" in message
              and "rule(s)" not in message and "sandbox" not in message
              and "allow-repo-commands" not in message, message)
    if name == "retired":
        check("retired: --check names the retired rule to remove and nothing else",
              ("%d retired Bash deny rule(s)" % len(RETIRED)) in message
              and "missing" not in message and "ask rule" not in message
              and "hook" not in message, message)
    check("%s: --check writes nothing" % name,
          (raw(repo) if content is not None else None) == before_raw)
    status, message, rc = run(repo, "--write")
    check("%s: --write reports %s" % (name, want_write),
          status == want_write and rc == (0 if status in OK_WRITE else 1),
          "got %s rc=%d %s" % (status, rc, message))
    if want_write == "INVALID":
        check("%s: INVALID file left untouched" % name, raw(repo) == before_raw)
        continue
    after = read(repo)
    deny = after["permissions"]["deny"]
    ask = after["permissions"].get("ask", [])
    check("%s: every deny rule present" % name, all(r in deny for r in ALL_DENY),
          "missing %s" % [r for r in ALL_DENY if r not in deny])
    check("%s: the hooks/ ask rule is present, and is not a deny rule" % name,
          all(r in ask for r in ASK) and not any(r in deny for r in ASK),
          "ask=%s" % ask)
    # An allow rule is the one thing this helper must never write: whatever the repo had
    # under `allow` — including nothing at all — is what it still has.
    had_allow = (((content or {}).get("permissions") or {}).get("allow")
                 if isinstance(content, dict) else None)
    check("%s: no allow rule was added" % name,
          after["permissions"].get("allow") == had_allow,
          "got %r" % after["permissions"].get("allow"))
    if name == "edit-only":
        check("edit-only: --write appended exactly the Bash rules, in order",
              deny == EDIT_DENY + BASH_DENY, "got %s" % deny)
    # The sandbox block: the negative half of the backlog assertion. Once SANDBOX_ENABLED
    # is on, with unsandboxed commands refused, Claude Code's built-in write deny
    # (.git/hooks, .git/config, .claude/settings*) binds every Bash subprocess — no path of
    # ours needed. While it is off, the owned values are still written and asserted here.
    sandbox = after.get("sandbox") or {}
    check("%s: enabled is the switch's value (%s), fail-closed and no unsandboxed retry "
          "still written" % (name, SANDBOX_ENABLED_EXPECTED),
          all(sandbox.get(k) is v for k, v in SANDBOX_OWNED.items()),
          "got %s" % {k: sandbox.get(k) for k in SANDBOX_OWNED})
    check("%s: Bash is never auto-allowed by the sandbox" % name,
          "autoAllowBashIfSandboxed" not in sandbox, "got %r" % sandbox)
    deny_read = (sandbox.get("filesystem") or {}).get("denyRead") or []
    domains = (sandbox.get("network") or {}).get("allowedDomains") or []
    check("%s: the three secret paths are denied to reads" % name,
          all(p in deny_read for p in SANDBOX_DENY_READ), "got %s" % deny_read)
    check("%s: never the home directory or ~/.claude" % name,
          not any(p.rstrip("/") in ("~", "~/.claude") for p in deny_read), "got %s" % deny_read)
    check("%s: every generator domain is allowed, the minimum among them" % name,
          all(d in domains for d in GEN_DOMAINS + SANDBOX_MIN_DOMAINS), "got %s" % domains)
    check("%s: no domain or path is listed twice" % name,
          len(set(domains)) == len(domains) and len(set(deny_read)) == len(deny_read),
          "got %s / %s" % (domains, deny_read))
    if name == "sandbox-own":
        # A consumer's own additions stay where they stood; the generator's are unioned in
        check("sandbox-own: the repo's own domain and denyRead path are kept, first",
              domains[0] == OWN_DOMAIN and deny_read[0] == OWN_DENY_READ,
              "got %s / %s" % (domains, deny_read))
        check("sandbox-own: a sandbox key the generator does not own is untouched",
              sandbox.get("excludedCommands") == OWN_EXCLUDED, "got %r" % sandbox)
        check("sandbox-own: the union appended exactly the generator's missing entries",
              domains == [OWN_DOMAIN] + GEN_DOMAINS[:2] + GEN_DOMAINS[2:]
              and deny_read == [OWN_DENY_READ] + SANDBOX_DENY_READ, "got %s" % domains)
    if name == "sandbox-off":
        check("sandbox-off: the generator's owned settings override the repo's",
              after["sandbox"] == GEN_SANDBOX, "got %r" % after["sandbox"])
    if name == "enabled-flip":
        check("enabled-flip: --write names exactly one owned setting",
              "1 owned setting(s)" in message, message)
        check("enabled-flip: a hand-flipped enabled is set back to the switch, the rest "
              "of the block unchanged",
              sandbox.get("enabled") is SANDBOX_ENABLED_EXPECTED
              and after["sandbox"] == GEN_SANDBOX, "got %r" % after["sandbox"])
    check("%s: no retired rule is left" % name, not any(r in deny for r in RETIRED),
          "got %s" % [r for r in RETIRED if r in deny])
    if name == "retired":
        check("retired: --write removed exactly the retired rules, in place",
              deny == ["Edit(/secrets/**)"] + ALL_DENY, "got %s" % deny)
    marked = [h for e in after["hooks"]["PreToolUse"] for h in e["hooks"]
              if "allow-repo-commands.sh" in h["command"]]
    check("%s: exactly one hook entry names the script" % name, len(marked) == 1,
          "%d entries" % len(marked))
    session = after["hooks"].get("SessionStart") or []
    session_marked = [h for e in session for h in e["hooks"]
                      if SESSION_MARKER in h["command"]]
    check("%s: exactly one SessionStart entry runs plans/cloud-setup.sh" % name,
          len(session_marked) == 1, "%d entries" % len(session_marked))
    if name in ("fresh", "no-session"):
        check("%s: the SessionStart entry the write added is the generator's, unguarded "
              "in the settings (the script guards itself)" % name,
              session == [SESSION_ENTRY], "got %r" % session)
    if name == "session-custom":
        check("session-custom: the repo's own spelling is kept and not doubled",
              session == [SESSION_CUSTOM], "got %r" % session)
    if name == "session-other":
        check("session-other: the repo's own SessionStart hook stays first, ours after it",
              session == [OTHER_SESSION, SESSION_ENTRY], "got %r" % session)
    if isinstance(content, dict):
        kept_keys = all(after.get(k) == v for k, v in content.items()
                        if k not in ("hooks", "permissions", "sandbox"))
        kept_deny = all(r in deny for r in (content.get("permissions") or {}).get("deny") or []
                        if r not in RETIRED)
        kept_allow = all(r in after["permissions"].get("allow", [])
                         for r in (content.get("permissions") or {}).get("allow") or [])
        kept_hooks = all(e in after["hooks"].get(event, [])
                         for event in ("PreToolUse", "SessionStart")
                         for e in (content.get("hooks") or {}).get(event) or [])
        check("%s: nothing the repo had was removed or changed" % name,
              kept_keys and kept_deny and kept_allow and kept_hooks)
        if content.get("hooks", {}).get("PreToolUse") == [HOOK_ENTRY]:
            check("%s: hand-customized hook path kept" % name,
                  marked[0]["command"] == HOOK_ENTRY["hooks"][0]["command"])
    settled = raw(repo)
    status, _, _ = run(repo, "--write")
    check("%s: second write reports kept, file byte-identical" % name,
          status == "kept" and raw(repo) == settled, "got %s" % status)
    status, _, _ = run(repo, "--check")
    check("%s: --check after write reports in-sync" % name, status == "in-sync", "got %s" % status)

# ── --self: agentTooling's own checkout ───────────────────────────────────────
# The same rules with this checkout's hook path and ask spelling — but the file is
# GENERATED here rather than merged, so --check is a byte comparison.
vendored, selfrepo = setup("mode-vendored", None), setup("mode-self", None)
run(vendored, "--write")
status, _, rc = run(selfrepo, "--write", self_mode=True)
check("--self --write creates the file", status == "created" and rc == 0, "got %s" % status)
v, s = read(vendored), read(selfrepo)
check("--self writes settings.json and nothing else — no settings.local.json",
      sorted(os.listdir(os.path.join(selfrepo, ".claude"))) == [SETTINGS_FILE],
      "got %s" % sorted(os.listdir(os.path.join(selfrepo, ".claude"))))


def hook_commands(settings):
    return [h["command"] for e in settings["hooks"]["PreToolUse"] for h in e["hooks"]]


check("--self writes the self hook command, guarded", hook_commands(s) == [SELF_HOOK_COMMAND],
      "got %s" % hook_commands(s))
check("an ordinary run still writes the vendored hook command",
      hook_commands(v) == [HOOK_COMMAND], "got %s" % hook_commands(v))
check("--self writes the any-depth and root-anchored ask rules",
      s["permissions"]["ask"] == SELF_ASK, "got %s" % s["permissions"].get("ask"))
check("an ordinary run writes the vendored ask rule",
      v["permissions"]["ask"] == ASK, "got %s" % v["permissions"].get("ask"))
check("neither mode denies hooks/ any more — the prompt is the point",
      not any("hooks/**" in r for r in v["permissions"]["deny"] + s["permissions"]["deny"]))
check("the deny rules are the same in both modes",
      v["permissions"]["deny"] == s["permissions"]["deny"] == ALL_DENY,
      "got %s" % s["permissions"]["deny"])
check("an ordinary run writes the SessionStart entry for plans/cloud-setup.sh",
      v["hooks"].get("SessionStart") == [SESSION_ENTRY], "got %r" % v["hooks"].get("SessionStart"))
# A --self checkout has no plans/cloud-setup.sh (its corpus is self/, never seeded), and
# the round-1 SessionStart bootstrap is gone (self-cloud-bootstrap NOTES.md: a policy
# written during startup raced the first tool call) — so it carries no SessionStart entry.
check("--self writes no SessionStart entry — there is no plans/cloud-setup.sh to run",
      "SessionStart" not in s["hooks"], "got %r" % s["hooks"].get("SessionStart"))
swapped = json.loads(json.dumps(v))
swapped["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = SELF_HOOK_COMMAND
swapped["permissions"]["ask"] = SELF_ASK
swapped["hooks"].pop("SessionStart", None)
check("--self differs in the hook command, the ask rules and the SessionStart entry and "
      "nothing else", swapped == s)
check("--self on its own file reports in-sync",
      run(selfrepo, "--check", self_mode=True)[0] == "in-sync")
check("--self on a vendored file reports UNWIRED — the two are not interchangeable",
      run(vendored, "--check", self_mode=True)[0] == "UNWIRED")
check("neither mode added an allow rule",
      "allow" not in v["permissions"] and "allow" not in s["permissions"])

# ── --self --check is byte-for-byte ──────────────────────────────────────────
# agentTooling's own settings file is wholly generated, so anything a hand edit can do
# to it is drift — including the two the merge check could never see: an ADDED rule, and
# a repointed hook command. Each must fail the check that self/gate.sh records.
generated = raw(selfrepo)
drifted = json.loads(generated.decode())
drifted["permissions"]["allow"] = ["Bash(rm -rf /:*)"]
write_raw(selfrepo, drifted)
status, message, rc = run(selfrepo, "--check", self_mode=True)
check("a hand-added allow rule fails --self --check",
      status == "UNWIRED" and rc == 1, "got %s rc=%s" % (status, rc))
check("and the message names the file and says where it first differs",
      ".claude/settings.json" in message and "line" in message and "allow" in message,
      message)
status, _, _ = run(selfrepo, "--write", self_mode=True)
check("--self --write restores the generated bytes exactly",
      status == "wired" and raw(selfrepo) == generated, "got %s" % status)
repointed = json.loads(generated.decode())
repointed["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = SELF_HOOK_PATH
write_raw(selfrepo, repointed)
check("an unguarded hook command fails --self --check too — the marker is not enough",
      run(selfrepo, "--check", self_mode=True)[0] == "UNWIRED")
run(selfrepo, "--write", self_mode=True)
reordered = json.loads(generated.decode())
reordered["permissions"]["deny"] = list(reversed(reordered["permissions"]["deny"]))
write_raw(selfrepo, reordered)
check("so does a reordered deny list, which the merge check reads as complete",
      run(selfrepo, "--check", self_mode=True)[0] == "UNWIRED")
run(selfrepo, "--write", self_mode=True)
os.remove(os.path.join(selfrepo, ".claude", SETTINGS_FILE))
status, message, rc = run(selfrepo, "--check", self_mode=True)
check("a missing file fails --self --check as missing, naming the regenerate command",
      status == "missing" and rc == 1 and "--self --repo %s --write" % selfrepo in message,
      "got %s: %s" % (status, message))
status, _, _ = run(selfrepo, "--write", self_mode=True)
check("--self --write puts it back as created, and still writes no settings.local.json",
      status == "created" and raw(selfrepo) == generated
      and not os.path.exists(os.path.join(selfrepo, ".claude", LOCAL_FILE)),
      "got %s" % status)
# The sandbox block is generated too, so here a hand-added domain is drift rather than a
# consumer's addition to keep — the opposite of the merge's rule, and on purpose.
check("--self writes the same sandbox block an ordinary run does, enabled per the switch",
      s.get("sandbox") == v.get("sandbox") == GEN_SANDBOX
      and GEN_SANDBOX.get("enabled") is SANDBOX_ENABLED_EXPECTED,
      "got %r" % s.get("sandbox"))
widened = json.loads(generated.decode())
widened.setdefault("sandbox", {}).setdefault("network", {}).setdefault(
    "allowedDomains", []).append(OWN_DOMAIN)
write_raw(selfrepo, widened)
status, message, _ = run(selfrepo, "--check", self_mode=True)
check("a hand-added allowed domain fails --self --check, naming it",
      status == "UNWIRED" and OWN_DOMAIN in message, "got %s: %s" % (status, message))
run(selfrepo, "--write", self_mode=True)
flipped = json.loads(generated.decode())
flipped.setdefault("sandbox", {})["enabled"] = not SANDBOX_ENABLED_EXPECTED
write_raw(selfrepo, flipped)
check("so does a sandbox switched %s by hand, against the switch"
      % ("on" if not SANDBOX_ENABLED_EXPECTED else "off"),
      run(selfrepo, "--check", self_mode=True)[0] == "UNWIRED")
run(selfrepo, "--write", self_mode=True)
check("and a write over an unchanged file reports kept",
      run(selfrepo, "--write", self_mode=True)[0] == "kept")

# This checkout's own tracked file, through the same call self/gate.sh records
status, message, rc = run(AT, "--check", self_mode=True)
check("this checkout's tracked .claude/settings.json passes --self --check",
      status == "in-sync" and rc == 0, "got %s: %s" % (status, message))

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-wiring: all checks passed"; else echo "hook-wiring: FAILED"; fi
exit "$rc"
