#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/wire-settings.py, the merge that sync-plans.sh runs to put the
# PreToolUse hook entry and the Edit deny rules into a consuming repo's
# .claude/settings.json (hooks/README.md). Run by self/gate.sh, or by hand:
# bash self/tests/hook-wiring.sh
#
# Builds thirteen throwaway repos under mktemp -d, one per starting state of the
# settings file — absent, unrelated content only, hook only, deny rules only, a partial
# deny list with a repo's own rule in it, complete, a different hook, and six malformed
# shapes — and asserts, for each, that --check and --write report the documented
# status and exit code and agree with each other; that after a write every deny rule
# is present and exactly one hook entry mentions the script; that nothing the repo
# already had is removed or changed, including its own deny and allow rules and a
# hand-customized hook path; and that a second write reports kept with the file
# byte-identical while --check reports in-sync. Malformed files are reported INVALID
# by both modes and left untouched. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-wiring"
python3 - "$AT/hooks/wire-settings.py" "$TMP" <<'PY'
import json, os, subprocess, sys

HELPER, TMP = sys.argv[1], sys.argv[2]
HOOK_ENTRY = {"matcher": "Bash", "hooks": [{"type": "command",
              "command": "/custom/path/allow-repo-commands.sh"}]}
ALL_DENY = ["Edit(/.git/**)", "Edit(**/.git/**)", "Edit(**/.git)", "Edit(/.claude/**)",
            "Edit(**/.claude/**)", "Edit(**/.venv/**)", "Edit(**/venv/**)",
            "Edit(**/node_modules/**)", "Edit(**/agentTooling/hooks/**)"]
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
    "complete":     ({"hooks": {"PreToolUse": [HOOK_ENTRY]},
                      "permissions": {"deny": list(ALL_DENY)}}, "in-sync", "kept"),
    "other-hook":   ({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                        {"type": "command", "command": "/x/other.sh"}]}]}}, "UNWIRED", "wired"),
    "broken":       ("{not json", "INVALID", "INVALID"),
    "hooks-list":   ({"hooks": []}, "INVALID", "INVALID"),
    "event-dict":   ({"hooks": {"PreToolUse": {}}}, "INVALID", "INVALID"),
    "perms-list":   ({"permissions": []}, "INVALID", "INVALID"),
    "deny-dict":    ({"permissions": {"deny": {}}}, "INVALID", "INVALID"),
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


def run(repo, mode):
    p = subprocess.run(["python3", HELPER, "--repo", repo, mode], capture_output=True, text=True)
    status, _, message = p.stdout.strip().partition("\t")
    return status, message, p.returncode


def read(repo):
    with open(os.path.join(repo, ".claude", "settings.json")) as f:
        return json.load(f)


def raw(repo):
    with open(os.path.join(repo, ".claude", "settings.json"), "rb") as f:
        return f.read()


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
    status, _, rc = run(repo, "--check")
    check("%s: --check reports %s" % (name, want_check),
          status == want_check and rc == (0 if status == "in-sync" else 1),
          "got %s rc=%d" % (status, rc))
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
    check("%s: every deny rule present" % name, all(r in deny for r in ALL_DENY),
          "missing %s" % [r for r in ALL_DENY if r not in deny])
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

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-wiring: all checks passed"; else echo "hook-wiring: FAILED"; fi
exit "$rc"
