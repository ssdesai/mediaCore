#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/wire-settings.py, the merge that sync-plans.sh runs to put the
# PreToolUse hook entry, the Edit and Bash deny rules and the hooks/ ask rule into a
# consuming repo's .claude/settings.json (hooks/README.md). Run by self/gate.sh, or by
# hand: bash self/tests/hook-wiring.sh
#
# Builds sixteen throwaway repos under mktemp -d, one per starting state of the settings
# file — absent, unrelated content only, hook only, deny rules only, a partial deny list
# with a repo's own rule in it, the hook and the Edit rules but no Bash rules, everything
# but the ask rule, complete, a different hook, and seven malformed shapes — and asserts,
# for each, that --check and --write report the documented status and exit code and agree
# with each other; that after a write every deny and ask rule is present and exactly one
# hook entry mentions the script; that nothing the repo already had is removed or changed,
# including its own deny and allow rules and a hand-customized hook path; and that a
# second write reports kept with the file byte-identical while --check reports in-sync.
# A file carrying the hook and the Edit rules and no Bash rules reports UNWIRED naming
# the count of missing Bash rules, and the write appends exactly those, in order.
# Malformed files are reported INVALID by both modes and left untouched.
#
# The Bash deny list is NOT retyped here: it is rendered from hooks/policy.py, the one
# table the hook reads too, so a rule added to the table reaches this test with nobody
# editing it (self/tests/policy-table.sh asserts the rendering itself).
#
# Three more repos cover --self, where the file is wholly GENERATED rather than merged:
# it carries this checkout's hook path and the ask rule Edit(**/hooks/**) +
# Edit(/hooks/**) in place of the vendored spelling, --check compares it BYTE FOR BYTE
# with a fresh write, so a hand-added allow rule or a repointed hook command fails it
# where the merge check would have passed, and --write restores those bytes. The
# checkout's own committed .claude/settings.json is checked with it, the same call
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
SELF_HOOK_COMMAND = "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"
# The Edit deny rules, then the Bash rules rendered from the table. The policy's own
# rule is no longer among them: hooks/ is an ASK rule now, so an attended session is
# prompted and a headless executor, which cannot answer, is refused.
EDIT_DENY = ["Edit(/.git/**)", "Edit(**/.git/**)", "Edit(**/.git)", "Edit(/.claude/**)",
             "Edit(**/.claude/**)", "Edit(**/.venv/**)", "Edit(**/venv/**)",
             "Edit(**/node_modules/**)"]
BASH_DENY = list(policy.bash_deny_rules())
ALL_DENY = EDIT_DENY + BASH_DENY
ASK = ["Edit(**/agentTooling/hooks/**)"]
SELF_ASK = ["Edit(**/hooks/**)", "Edit(/hooks/**)"]
OK_WRITE = ("created", "wired", "kept")

CASES = {
    "fresh":        (None, "missing", "created"),
    "other-only":   ({"permissions": {"allow": ["Bash(git status)"]}, "env": {"X": "1"}},
                     "UNWIRED", "wired"),
    "hook-only":    ({"hooks": {"PreToolUse": [HOOK_ENTRY]}}, "UNWIRED", "wired"),
    "deny-only":    ({"permissions": {"deny": list(ALL_DENY)}}, "UNWIRED", "wired"),
    "partial-deny": ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": ALL_DENY[:3] + ["Edit(/secrets/**)"]}},
                     "UNWIRED", "wired"),
    "edit-only":    ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": list(EDIT_DENY), "ask": list(ASK)}},
                     "UNWIRED", "wired"),
    "no-ask":       ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": list(ALL_DENY)}}, "UNWIRED", "wired"),
    "complete":     ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": list(ALL_DENY), "ask": list(ASK)}},
                     "in-sync", "kept"),
    "other-hook":   ({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                        {"type": "command", "command": "/x/other.sh"}]}]}}, "UNWIRED", "wired"),
    "broken":       ("{not json", "INVALID", "INVALID"),
    "hooks-list":   ({"hooks": []}, "INVALID", "INVALID"),
    "event-dict":   ({"hooks": {"PreToolUse": {}}}, "INVALID", "INVALID"),
    "perms-list":   ({"permissions": []}, "INVALID", "INVALID"),
    "deny-dict":    ({"permissions": {"deny": {}}}, "INVALID", "INVALID"),
    "ask-dict":     ({"permissions": {"ask": {}}}, "INVALID", "INVALID"),
    "top-list":     ([], "INVALID", "INVALID"),
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


def read(repo):
    with open(os.path.join(repo, ".claude", "settings.json")) as f:
        return json.load(f)


def raw(repo):
    with open(os.path.join(repo, ".claude", "settings.json"), "rb") as f:
        return f.read()


def write_raw(repo, settings):
    with open(os.path.join(repo, ".claude", "settings.json"), "w") as f:
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
    marked = [h for e in after["hooks"]["PreToolUse"] for h in e["hooks"]
              if "allow-repo-commands.sh" in h["command"]]
    check("%s: exactly one hook entry names the script" % name, len(marked) == 1,
          "%d entries" % len(marked))
    if isinstance(content, dict):
        kept_keys = all(after.get(k) == v for k, v in content.items()
                        if k not in ("hooks", "permissions"))
        kept_deny = all(r in deny for r in (content.get("permissions") or {}).get("deny") or [])
        kept_allow = all(r in after["permissions"].get("allow", [])
                         for r in (content.get("permissions") or {}).get("allow") or [])
        kept_hooks = all(e in after["hooks"]["PreToolUse"]
                         for e in (content.get("hooks") or {}).get("PreToolUse") or [])
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


def hook_commands(settings):
    return [h["command"] for e in settings["hooks"]["PreToolUse"] for h in e["hooks"]]


check("--self writes the self hook command", hook_commands(s) == [SELF_HOOK_COMMAND],
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
swapped = json.loads(json.dumps(v).replace(HOOK_COMMAND, SELF_HOOK_COMMAND))
swapped["permissions"]["ask"] = SELF_ASK
check("--self differs in the hook path and the ask rules and nothing else", swapped == s)
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
check("and the message says where the file first differs",
      "line" in message and "allow" in message, message)
status, _, _ = run(selfrepo, "--write", self_mode=True)
check("--self --write restores the generated bytes exactly",
      status == "wired" and raw(selfrepo) == generated, "got %s" % status)
repointed = json.loads(generated.decode())
repointed["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = HOOK_COMMAND
write_raw(selfrepo, repointed)
check("a repointed hook command fails --self --check too — the marker is not enough",
      run(selfrepo, "--check", self_mode=True)[0] == "UNWIRED")
run(selfrepo, "--write", self_mode=True)
reordered = json.loads(generated.decode())
reordered["permissions"]["deny"] = list(reversed(reordered["permissions"]["deny"]))
write_raw(selfrepo, reordered)
check("so does a reordered deny list, which the merge check reads as complete",
      run(selfrepo, "--check", self_mode=True)[0] == "UNWIRED")
run(selfrepo, "--write", self_mode=True)
check("and a write over an unchanged file reports kept",
      run(selfrepo, "--write", self_mode=True)[0] == "kept")

# The committed file, through the same call self/gate.sh records
status, message, rc = run(AT, "--check", self_mode=True)
check("this checkout's committed .claude/settings.json passes --self --check",
      status == "in-sync" and rc == 0, "got %s: %s" % (status, message))

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-wiring: all checks passed"; else echo "hook-wiring: FAILED"; fi
exit "$rc"
