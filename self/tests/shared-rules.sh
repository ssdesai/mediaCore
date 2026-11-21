#!/usr/bin/env bash
set -uo pipefail

# Self-test for the shared rules (self/features/shared-hook-rules): every rule the PreToolUse
# hook shares with analysis/ or a top-level *.sh entry point has ONE definition, the
# stdlib-only hooks/shared_rules.py, and nothing restates it. Run by self/gate.sh, or by
# hand: bash self/tests/shared-rules.sh
#
# It replaces the two equality-of-copies checks the mirrors needed (orchestrator-role.sh U3,
# orchestration-records-in-repo.sh R10): a copy that cannot exist needs no test that two
# copies agree. The behavioural tests of those files — the refusal text a user reads, the
# record a start writes, the role a session holds — stay where they are.
#
# Asserts:
#   S1. the module: its CLI prints the values it is asked for, one per line, and exits 2 with
#       nothing on stdout for an unknown name or no name; its values are the ones the rules
#       have always had (record roots, record name, ledger name, kind, slug pattern, both
#       refusal texts, roots.py's CLI go-ahead token); it imports only re and sys and does no I/O at import;
#   S2. every name `roots.py`, `orchestrator_role.py`, `manifest.py`, `routing.py`,
#       `coordinator_check.py`, `orchestration_capture.py` and the hook bind to a shared rule
#       IS the shared_rules object (a reference, never an equal copy); roots.py's *_PARTS are
#       the roots split; `wire-settings.py` spells the record ask rules from the roots, and
#       they come out as they always have;
#   S3. no tracked hooks/*.py, hooks/allow-repo-commands.sh, analysis/*.py or top-level *.sh
#       other than shared_rules.py assigns any of the module's literal values at module level
#       (a renamed copy included). The pairs that share a value and not a meaning are listed
#       below with why, and each is a deliberate exception;
#   S4. `grep -rn 'MIRRORS\|MIRRORED'` over hooks/, analysis/ and the top-level *.sh is empty;
#   S5. fail-safe, by caller (NOTES.md ruling 5): a hooks/ without shared_rules.py still
#       approves a plain `ls`, and answers exactly as a hooks/ without orchestrator_role.py
#       does for a session that holds a record (the role rule silent, nothing crashing);
#       orchestration-start.sh refuses (exit 1, naming shared_rules.py, nothing written) when
#       the module is missing or broken, and never falls back to a literal;
#   S6. the shell reads the module, it does not restate it: orchestration-start.sh runs the
#       CLI and carries no `eval` of its output.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/shared-rules.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
unset CLAUDE_CODE_SESSION_ID GATE_RESUME CLAUDE_CODE_REMOTE
export HOME="$TMP/home"
mkdir -p "$HOME"

SHARED="$HERE/hooks/shared_rules.py"
MODULE_NAME="shared_rules.py"
USAGE_RC=2
REFUSED_RC=1
SESSION_S="5e5e5e5e-0000-0000-0000-000000000001"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "== S1 the module =="
check "S1 hooks/shared_rules.py exists" '[[ -f "$SHARED" ]]'
roots_out="$(python3 -B "$SHARED" ORCHESTRATIONS_SELF_REL ORCHESTRATIONS_CONSUMER_REL 2>/dev/null)"
roots_want="$(printf 'self/orchestrations\nplans/orchestrations')"
check "S1 the CLI prints the two record roots, one per line" '[[ "$roots_out" == "$roots_want" ]]'
check "S1 the CLI prints one value for one name" \
  '[[ "$(python3 -B "$SHARED" LEDGER_NAME 2>/dev/null)" == "agenttooling-orchestrators" ]]'
out="$(python3 -B "$SHARED" NO_SUCH_NAME 2>/dev/null)"; rc=$?
check "S1 an unknown name exits $USAGE_RC with nothing on stdout (got $rc)" '[[ $rc -eq $USAGE_RC && -z "$out" ]]'
out="$(python3 -B "$SHARED" ORCHESTRATIONS_SELF_REL NO_SUCH_NAME 2>/dev/null)"; rc=$?
check "S1 one unknown name among known ones prints nothing at all (got $rc)" '[[ $rc -eq $USAGE_RC && -z "$out" ]]'
out="$(python3 -B "$SHARED" 2>/dev/null)"; rc=$?
check "S1 no name exits $USAGE_RC with nothing on stdout (got $rc)" '[[ $rc -eq $USAGE_RC && -z "$out" ]]'
python3 -B - "$HERE" <<'PY'
import importlib.util, os, re, subprocess, sys

HERE = sys.argv[1]
SHARED = os.path.join(HERE, "hooks", "shared_rules.py")
STDLIB_ALLOWED = {"re", "sys"}
FORBIDDEN_AT_IMPORT = r"\bsubprocess\b|\bopen\(|\bos\.|\bpathlib\b|\bglob\b|\bshutil\b"

# The values the rules have always had: what a user reads and what lands on disk
EXPECTED = {
    "ORCHESTRATIONS_SELF_REL": "self/orchestrations",
    "ORCHESTRATIONS_CONSUMER_REL": "plans/orchestrations",
    "RECORD_NAME": "README.md",
    "GIT_ENTRY": ".git",
    "KIND_KEY": "kind",
    "KIND_COORDINATOR": "coordinator",
    "SESSION_KEY": "session",
    "FEATURES_KEY": "features",
    "LEDGER_NAME": "agenttooling-orchestrators",
    "SLUG_PATTERN": "^[a-z0-9]+(-[a-z0-9]+)*$",
    "STANDALONE_REFUSAL": (
        "this is agentTooling's own checkout, not a consuming repo: without --self a record "
        "would land outside it — pass --self for agentTooling's own records (self/orchestrations/)"),
    "LEGACY_RECORD_REFUSAL": (
        "the record `{slug}` is at the old place, agentTooling/self/orchestrations/{slug} — "
        "a record lives in the repo that ran it now; move it: "
        "mkdir -p plans/orchestrations && "
        "git mv agentTooling/self/orchestrations/{slug} plans/orchestrations/{slug}"),
    "LEGACY_RECORD_MKDIR": "mkdir -p plans/orchestrations",
    # self/features/orchestrator-move-length-cap/: roots.py's CLI go-ahead to the start
    "ROOTS_CLI_GO_AHEAD": "ok",
}
EXPECTED_TUPLES = {
    "ORCHESTRATOR_FEATURE_KEYS": ("session", "branch"),
    "ORCH_FEATURE_KEYS": ("repo", "slug", "session", "branch", "pr", "report"),
}

failures = []
def check(label, cond):
    print(("  ok    " if cond else "  FAIL  ") + label)
    if not cond:
        failures.append(label)

spec = importlib.util.spec_from_file_location("shared_rules_under_test", SHARED)
before = set(sys.modules)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module  # the module looks its own namespace up by name
spec.loader.exec_module(module)
check("S1 shared_rules imports without a failure", True)
for name, value in EXPECTED.items():
    check("S1 %s is %r" % (name, value[:40]), getattr(module, name, None) == value)
for name, value in EXPECTED_TUPLES.items():
    check("S1 %s is %r" % (name, value), getattr(module, name, None) == value)
check("S1 SLUG_RE is SLUG_PATTERN compiled", module.SLUG_RE.pattern == module.SLUG_PATTERN)

source = open(SHARED, encoding="utf-8").read()
imports = set(re.findall(r"^(?:import|from)\s+(\w+)", source, re.M))
check("S1 it imports only re and sys (got %s)" % sorted(imports), imports <= STDLIB_ALLOWED)
code_lines = [l for l in source.splitlines() if not l.lstrip().startswith("#")]
body = "\n".join(code_lines)
check("S1 it opens no file and runs no subprocess", not re.search(FORBIDDEN_AT_IMPORT, body))

# S2 — every bound name IS the shared object. (module file, name, shared name)
HOOKS = os.path.join(HERE, "hooks")
ANALYSIS = os.path.join(HERE, "analysis")
sys.path.insert(0, HOOKS)
sys.path.append(ANALYSIS)
import shared_rules  # noqa: E402  the hooks/ copy: the one analysis/ and the hook import
import orchestrator_role, roots, manifest, routing, coordinator_check, orchestration_capture  # noqa: E402
import env_profile  # noqa: E402

def load_by_path(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

import importlib.machinery  # noqa: E402
wire = load_by_path("wire_settings_under_test", os.path.join(HOOKS, "wire-settings.py"))
hook = load_by_path("allow_repo_commands_under_test", os.path.join(HOOKS, "allow-repo-commands.sh"))

BOUND = [
    (roots, "GIT_ENTRY", "GIT_ENTRY"),
    (roots, "GITDIR_PREFIX", "GITDIR_PREFIX"),
    (roots, "COMMONDIR_FILE", "COMMONDIR_NAME"),
    (roots, "LEGACY_RECORD_MOVE", "LEGACY_RECORD_MOVE"),
    (roots, "LEGACY_RECORD_REFUSAL", "LEGACY_RECORD_REFUSAL"),
    (roots, "STANDALONE_REFUSAL", "STANDALONE_REFUSAL"),
    (roots, "CLI_GO_AHEAD", "ROOTS_CLI_GO_AHEAD"),
    (roots, "ORCH_FEATURES_KEY", "FEATURES_KEY"),
    (roots, "ORCH_FEATURE_REPO_KEY", "FEATURE_REPO_KEY"),
    (roots, "ORCH_KIND_KEY", "KIND_KEY"),
    (roots, "ORCH_KIND_COORDINATOR", "KIND_COORDINATOR"),
    (orchestrator_role, "ORCHESTRATIONS_SELF_REL", "ORCHESTRATIONS_SELF_REL"),
    (orchestrator_role, "ORCHESTRATIONS_CONSUMER_REL", "ORCHESTRATIONS_CONSUMER_REL"),
    (orchestrator_role, "RECORD_NAME", "RECORD_NAME"),
    (orchestrator_role, "GIT_ENTRY", "GIT_ENTRY"),
    (orchestrator_role, "GIT_MARKER", "GIT_ENTRY"),
    (orchestrator_role, "GITDIR_PREFIX", "GITDIR_PREFIX"),
    (orchestrator_role, "COMMONDIR_NAME", "COMMONDIR_NAME"),
    (orchestrator_role, "SESSION_KEY", "SESSION_KEY"),
    (orchestrator_role, "KIND_KEY", "KIND_KEY"),
    (orchestrator_role, "KIND_COORDINATOR", "KIND_COORDINATOR"),
    (orchestrator_role, "FEATURES_KEY", "FEATURES_KEY"),
    (orchestrator_role, "ORCHESTRATOR_FEATURE_KEYS", "ORCHESTRATOR_FEATURE_KEYS"),
    (orchestrator_role, "LEDGER_NAME", "LEDGER_NAME"),
    (orchestrator_role, "LEDGER_SLUG_RE", "SLUG_RE"),
    (manifest, "SLUG_RE", "SLUG_RE"),
    (manifest, "ORCH_FEATURE_KEYS", "ORCH_FEATURE_KEYS"),
    (manifest, "COORDINATOR_REFUSED_FEATURE_KEYS", "ORCHESTRATOR_FEATURE_KEYS"),
    (routing, "SLUG_RE", "SLUG_RE"),
    (coordinator_check, "SESSION_KEY", "SESSION_KEY"),
    (coordinator_check, "RECORD_NAME", "RECORD_NAME"),
    (orchestration_capture, "MANIFEST_NAME", "RECORD_NAME"),
    (hook, "ORCHESTRATOR_SLUG_RE", "SLUG_RE"),
]
for mod, name, shared_name in BOUND:
    label = "S2 %s.%s is shared_rules.%s" % (os.path.basename(mod.__file__), name, shared_name)
    check(label, hasattr(mod, name) and getattr(mod, name) is getattr(shared_rules, shared_name, object()))
check("S2 manifest.py reaches the hooks/ copy of the module, not another",
      os.path.realpath(manifest.shared_rules.__file__) == os.path.realpath(SHARED))
check("S2 roots.ORCHESTRATIONS_SELF_PARTS is the shared root split",
      roots.ORCHESTRATIONS_SELF_PARTS == tuple(shared_rules.ORCHESTRATIONS_SELF_REL.split("/")))
check("S2 roots.ORCHESTRATIONS_CONSUMER_PARTS is the shared root split",
      roots.ORCHESTRATIONS_CONSUMER_PARTS == tuple(shared_rules.ORCHESTRATIONS_CONSUMER_REL.split("/")))
check("S2 manifest.ORCH_KEY_ORDER carries the shared fence keys in place",
      manifest.ORCH_KEY_ORDER[1] == shared_rules.KIND_KEY and manifest.ORCH_KEY_ORDER[2] == shared_rules.SESSION_KEY
      and manifest.ORCH_KEY_ORDER[-1] == shared_rules.FEATURES_KEY)
check("S2 manifest.KNOWN_PROFILES is env_profile's two profiles, not a copy",
      manifest.KNOWN_PROFILES[0] is env_profile.PROFILE_LOCAL and manifest.KNOWN_PROFILES[1] is env_profile.PROFILE_CLOUD)
check("S2 wire-settings POLICY_ASK_RULES is the exact strings vendored-edit-ask set, spelled from the roots",
      wire.POLICY_ASK_RULES == ("Edit(**/agentTooling/**)",
                                "Edit(**/plans/orchestrations/**)"))
check("S2 ... and names no root the module does not",
      "Edit(**/%s/**)" % shared_rules.ORCHESTRATIONS_CONSUMER_REL in wire.POLICY_ASK_RULES)
check("S2 wire-settings RETIRED_EDIT_ASK_RULES is the strings it once wrote, spelled from the roots",
      wire.RETIRED_EDIT_ASK_RULES == ("Edit(**/agentTooling/hooks/**)",
                                      "Edit(**/agentTooling/self/orchestrations/**)")
      and "Edit(**/agentTooling/%s/**)" % shared_rules.ORCHESTRATIONS_SELF_REL in wire.RETIRED_EDIT_ASK_RULES)

# The module's own CLI plumbing: not a rule anyone else holds
CLI_MECHANICS = {"TUPLE_SEPARATOR", "USAGE_RC", "OK_RC"}

# S3 — nothing else assigns a shared literal at module level. Shared values: every string,
# string tuple and compiled pattern the module defines.
import ast  # noqa: E402

def shared_values():
    values = {}
    for name in dir(shared_rules):
        if not name.isupper() or name in CLI_MECHANICS:
            continue
        value = getattr(shared_rules, name)
        if isinstance(value, re.Pattern):
            value = value.pattern
        if isinstance(value, str) or (isinstance(value, tuple) and value and all(isinstance(v, str) for v in value)):
            values.setdefault(value, []).append(name)
    return values

def literal_of(node):
    """The string, string tuple or compiled-pattern source an assignment's value is, or None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Tuple) and node.elts and all(
            isinstance(e, ast.Constant) and isinstance(e.value, str) for e in node.elts):
        return tuple(e.value for e in node.elts)
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "compile"
            and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)):
        return node.args[0].value
    return None

# A pair that shares a VALUE but not a MEANING, or a one-sided pair the build left on purpose
# (NOTES.md "Rulings made in the build"): (file, constant name) -> why.
DIFFERENT_MEANING = {
    ("analysis/capture_planning.py", "SEEN_FEATURES_KEY"): "the claims-seen ledger's own `features` key",
    ("analysis/capture_planning.py", "SEEN_REPO_KEY"): "the claims-seen ledger's own `repo` key",
    ("analysis/capture_planning.py", "GIT_REMOTE_SUFFIX"): "a remote URL's `.git` suffix",
    ("analysis/routing.py", "MANIFEST_NAME"): "a FEATURE manifest's name, not an orchestration record's",
    ("hooks/allow-repo-commands.sh", "MANIFEST_NAME"): "a FEATURE manifest's name; the hook may not depend on shared_rules (NOTES.md)",
    ("hooks/allow-repo-commands.sh", "GIT_DIR_ENTRY"): "git's own entry name in the hook's path reads; the hook may not depend on shared_rules",
    ("hooks/wire-settings.py", "GIT_MARKER"): "git's own entry name in wire-settings' repo probe; not a rule",
    ("hooks/policy.py", "GIT_BRANCH"): "the `git branch` subcommand",
}
sources = []
for folder, pattern in (("hooks", ".py"), ("hooks", "allow-repo-commands.sh"), ("analysis", ".py")):
    for entry in sorted(os.listdir(os.path.join(HERE, folder))):
        if entry.endswith(pattern) and entry != "shared_rules.py":
            sources.append(os.path.join(folder, entry))
values = shared_values()
restated = []
for rel in sources:
    tree = ast.parse(open(os.path.join(HERE, rel), encoding="utf-8").read())
    for node in tree.body:
        targets = node.targets if isinstance(node, ast.Assign) else [node.target] if isinstance(node, ast.AnnAssign) and node.value else []
        if len(targets) != 1 or not isinstance(targets[0], ast.Name) or node.value is None:
            continue
        literal = literal_of(node.value)
        if literal in values and (rel, targets[0].id) not in DIFFERENT_MEANING:
            restated.append("%s:%s = %r (shared_rules.%s)" % (rel, targets[0].id, literal, "/".join(values[literal])))
for line in restated:
    print("        " + line)
check("S3 no hooks/ or analysis/ module restates a shared literal (%d found)" % len(restated), not restated)

# The shell: a top-level NAME="literal" holding a value the module's CLI serves
SHELL_PAIRS_LEFT = {
    ("feature-start.sh", "SLUG_PATTERN"): "the shell slug patterns are shell-to-shell (BACKLOG.md)",
    ("orchestration-capture.sh", "SLUG_PATTERN"): "the shell slug patterns are shell-to-shell (BACKLOG.md)",
    ("forge.sh", "GIT_SUFFIX"): "a remote URL's `.git` suffix",
    ("update.sh", "GIT_SUFFIX"): "a remote URL's `.git` suffix",
    ("plan-runner-roots.sh", "GIT_REMOTE_SUFFIX"): "a remote URL's `.git` suffix",
    ("plan-runner-roots.sh", "STARTED_MANIFEST_NAME"): "a FEATURE manifest's name",
    ("orchestration-start.sh", "MANIFEST_NAME"): "a FEATURE manifest's name (the reverse guard)",
    ("session-start.sh", "MANIFEST_NAME"): "a FEATURE manifest's name",
    ("update.sh", "MANIFEST_NAME"): "a FEATURE manifest's name",
    ("feature-start.sh", "START_LOCK_BRANCH_KEY"): "the feature manifest's `branch` field of the start lock",
}
shell_values = {v for v in values if isinstance(v, str)}
shell_restated = []
for entry in sorted(os.listdir(HERE)):
    if not entry.endswith(".sh"):
        continue
    for line in open(os.path.join(HERE, entry), encoding="utf-8", errors="replace"):
        m = re.match(r"""^([A-Z][A-Z0-9_]*)=(['"])(.*)\2\s*(?:#.*)?$""", line.rstrip("\n"))
        if m and m.group(3) in shell_values and (entry, m.group(1)) not in SHELL_PAIRS_LEFT:
            shell_restated.append("%s:%s=%r" % (entry, m.group(1), m.group(3)[:50]))
for line in shell_restated:
    print("        " + line)
check("S3 no top-level *.sh restates a value the module serves (%d found)" % len(shell_restated), not shell_restated)

sys.exit(1 if failures else 0)
PY
[[ $? -eq 0 ]] || fails=$((fails + 1))

echo "== S4 no mirror comment survives =="
mirrors="$(grep -rn --include='*.py' --include='*.sh' 'MIRRORS\|MIRRORED' "$HERE/hooks" "$HERE/analysis" 2>/dev/null; grep -n 'MIRRORS\|MIRRORED' "$HERE"/*.sh 2>/dev/null)"
check "S4 grep MIRRORS/MIRRORED over hooks/, analysis/ and the top-level *.sh is empty" '[[ -z "$mirrors" ]]'
[[ -z "$mirrors" ]] || printf '%s\n' "$mirrors"

echo "== S5 fail-safe: the hook =="
python3 -B - "$HERE" "$TMP" "$SESSION_S" <<'PY'
import json, os, shutil, subprocess, sys

HERE, TMP, SESSION_S = sys.argv[1:4]
HOOK_NAME = "allow-repo-commands.sh"
HOOK_FILES = ("allow-repo-commands.sh", "policy.py", "env_profile.py", "orchestrator_role.py",
              "brief_header.py", "shared_rules.py")
ROLE_MARK = "is the orchestrator of"
PROFILE_ENV = "AGENTTOOLING_PROFILE"
RECORD_SLUG = "wave"
PLAIN = "ls"
BUILD = "./run-plans.sh --self x"

failures = []
def check(label, cond):
    print(("  ok    " if cond else "  FAIL  ") + label)
    if not cond:
        failures.append(label)

def fixture(name, omit):
    root = os.path.join(TMP, name)
    hooks = os.path.join(root, "hooks")
    os.makedirs(hooks)
    for f in HOOK_FILES:
        src = os.path.join(HERE, "hooks", f)
        if f != omit and os.path.exists(src):
            shutil.copy2(src, hooks)
    record = os.path.join(root, "self", "orchestrations", RECORD_SLUG, "README.md")
    os.makedirs(os.path.dirname(record))
    with open(record, "w") as handle:
        handle.write("# w\n\n```json\n%s\n```\n" % json.dumps(
            {"slug": RECORD_SLUG, "session": SESSION_S, "features": []}))
    subprocess.run(["git", "-C", root, "init", "-q"], check=True, capture_output=True)
    return root

def ask(root, command, session):
    env = {k: v for k, v in os.environ.items() if k not in (PROFILE_ENV, "CLAUDE_CODE_REMOTE")}
    env.update({"CLAUDE_PROJECT_DIR": root, "TMPDIR": TMP, "HOME": TMP, PROFILE_ENV: "local"})
    payload = {"tool_name": "Bash", "cwd": root, "session_id": session, "tool_input": {"command": command}}
    return subprocess.run([os.path.join(root, "hooks", HOOK_NAME)], input=json.dumps(payload),
                          capture_output=True, text=True, env=env)

def decision(done):
    try:
        return json.loads(done.stdout)["hookSpecificOutput"].get("permissionDecision")
    except (ValueError, KeyError, TypeError):
        return None

whole = fixture("hook-whole", None)
no_shared = fixture("hook-no-shared", "shared_rules.py")
no_role = fixture("hook-no-role", "orchestrator_role.py")
done = ask(whole, BUILD, SESSION_S)
check("S5 control: with every file, the orchestrator's build is denied with the role reason",
      decision(done) == "deny" and ROLE_MARK in done.stdout)
done = ask(no_shared, PLAIN, SESSION_S)
check("S5 a hooks/ without shared_rules.py still approves a plain `ls` (rc %d)" % done.returncode,
      done.returncode == 0 and decision(done) == "allow")
for label, command in (("a plain read", PLAIN), ("the orchestrator's build script", BUILD)):
    a, b = ask(no_shared, command, SESSION_S), ask(no_role, command, SESSION_S)
    check("S5 %s: no shared_rules.py answers as no orchestrator_role.py does (the role rule silent)" % label,
          a.returncode == b.returncode == 0 and a.stdout == b.stdout and ROLE_MARK not in a.stdout)
sys.exit(1 if failures else 0)
PY
[[ $? -eq 0 ]] || fails=$((fails + 1))

echo "== S5 fail-safe: orchestration-start.sh =="
# A vendored copy with the start script and what it sources, and a hooks/ that holds no module
# (missing) or a module that does not run (broken).
vendor_start() {
  local at="$TMP/$1/agentTooling"
  mkdir -p "$at/hooks"
  cp "$HERE/orchestration-start.sh" "$HERE/plan-runner-roots.sh" "$at/"
  git -C "$TMP/$1" init -q -b main
  case "$2" in
    broken) printf 'raise SystemExit("broken")\n' > "$at/hooks/$MODULE_NAME" ;;
  esac
}
for mode in missing broken; do
  vendor_start "start-$mode" "$mode"
  at="$TMP/start-$mode/agentTooling"
  out="$("$at/orchestration-start.sh" --self wave --session "$SESSION_S" 2>&1)"; rc=$?
  check "S5 $mode module: orchestration-start.sh exits $REFUSED_RC (got $rc)" '[[ $rc -eq $REFUSED_RC ]]'
  check "S5 $mode module: the refusal names $MODULE_NAME" '[[ "$out" == *"refused"* && "$out" == *"$MODULE_NAME"* ]]'
  check "S5 $mode module: nothing is written (no record folder, no ledger)" \
    '[[ ! -e "$at/self/orchestrations" && ! -e "$TMP/start-$mode/.git/agenttooling-orchestrators" ]]'
  out="$("$at/orchestration-start.sh" wave --session "$SESSION_S" 2>&1)"; rc=$?
  check "S5 $mode module: without --self it refuses too, with no literal fallback (got $rc)" \
    '[[ $rc -eq $REFUSED_RC && "$out" == *"$MODULE_NAME"* && ! -e "$TMP/start-$mode/plans" ]]'
done

echo "== S6 the shell reads the module =="
check "S6 orchestration-start.sh runs the module's CLI" 'grep -q "hooks/$MODULE_NAME" "$HERE/orchestration-start.sh"'
check "S6 ... and evals nothing" '! grep -Eq "^[^#]*\beval\b" "$HERE/orchestration-start.sh"'

echo
if (( fails )); then echo "shared-rules: $fails FAILED"; exit 1; fi
echo "shared-rules: all checks passed"
