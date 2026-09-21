#!/usr/bin/env python3
"""Wire the hook and its permission rules into a repo's `.claude/settings.json`.

Called by `sync-plans.sh` at install and after every `subtree pull`, and by
`self/gate.sh --self` for agentTooling's own checkout.

**In a consuming repo the file is repo-owned and may hold anything, so this merges
rather than copies**: it appends the `PreToolUse` entry for `allow-repo-commands.sh`
when no hook already references the script, and appends each `Edit` deny, `Bash` deny
and `Edit` ask rule that is absent. It never removes, reorders or rewrites another
entry. Everything it adds is a restriction or a prompt-remover for reads; it never adds
an allow rule.

**Under `--self` the file is wholly GENERATED**, because nothing else writes
agentTooling's own: `--check` compares it BYTE FOR BYTE with what a fresh write would
produce and names the first line that differs, and `--write` puts those bytes back. That
is the difference a merge check could not see — a hand-added allow rule, a hook command
repointed at a path that would never run, a reordered list — each of which left the gate
green while `hooks/README.md` said it failed. The hook path also loses its
`agentTooling/` segment there, and the policy ask rule is spelled for a checkout whose
`hooks/` is at the root.

The `Edit` deny rules exist because `--permission-mode acceptEdits` — which the batch
runners use — accepts every Edit-tool write under the working directory, including into
`.git/` (hooks are executable), `.claude/` (permissions), and the dependency trees (code
that runs on the next test). Deny rules bind in every permission mode and cannot be
overridden by a mode or an allow rule. They cover the Edit and Write tools and `> file`
redirects, not a subprocess that opens a file itself.

The `hooks/` directory is an **ask** rule rather than a deny: an ask is evaluated before
allow rules and forces a prompt even under `acceptEdits`, and in a headless `claude -p`
there is no terminal to answer it, so it is refused. That is exactly the policy wanted —
a human may edit the policy, an unattended executor may not — where a deny refused
everyone and a silence let the runners through. Under `bypassPermissions` an ask does not
fire at all; the runners launch with `acceptEdits`, never bypass (`hooks/README.md`).

The `Bash` rules are the visible half of `LIFECYCLE.md` rule 2 — agents never create or
destroy branches and worktrees, and never rewrite history. They are prefix rules, so they
match only the spelling they name: `git -C /repo worktree add x` and
`x=$(git rebase main)` slip past every one of them. The *enforcement* is
`allow-repo-commands.sh`'s git deny, which reads the whole line. Both are rendered from
one table, `policy.py` beside this file, so they cannot drift apart:
`policy.bash_deny_rules()` writes these rules and the hook imports the same constants.

Emits one `status<TAB>message` line for the caller to format, and exits 0 when nothing
needs attention, 1 otherwise.
"""

import argparse
import json
import os
import sys

# The policy table, imported as a sibling: this script is run with a `--repo` that is
# somebody else's checkout, so the directory has to come from this file's own path. No
# bytecode, so a run against a repo never leaves a __pycache__ in the vendored tree.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import policy                                                        # noqa: E402

# Where the wiring lives in the consuming repo
SETTINGS_REL = os.path.join(".claude", "settings.json")

# The hook entry. The marker identifies it across hand-edits to the path, the matcher
# or an added `if:` — a repo that customized the entry keeps its version, and a second
# one is never appended alongside it. (Under `--self` a customized entry is drift, not a
# customization: that file is generated.)
HOOK_MARKER = "allow-repo-commands.sh"
HOOK_COMMAND = "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh"
# agentTooling's own checkout: `hooks/` is at the root, not under `agentTooling/`
SELF_HOOK_COMMAND = "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"
HOOK_EVENT = "PreToolUse"
HOOK_MATCHER = "Bash"

# Edit-tool deny rules, matched by exact string. `**/x/**` matches at any depth; the
# root-anchored `/x/**` forms are insurance for the two that matter most, since `/`
# in project settings resolves against the primary working directory (the worktree
# itself in a worktree session).
EDIT_DENY_RULES = (
    "Edit(/.git/**)",
    "Edit(**/.git/**)",
    "Edit(**/.git)",
    "Edit(/.claude/**)",
    "Edit(**/.claude/**)",
    "Edit(**/.venv/**)",
    "Edit(**/venv/**)",
    "Edit(**/node_modules/**)",
)
# The policy itself, as an ASK rule: an unattended executor must not be able to widen
# what the hook approves, and a human editing it should be asked rather than refused.
# Spelled at any depth so a worktree's copy is covered from a session rooted at the
# primary checkout — the hole the root-anchored deny left open — with the root form
# beside it under `--self`, the insurance the deny pairs have.
POLICY_ASK_RULES = ("Edit(**/agentTooling/hooks/**)",)
SELF_POLICY_ASK_RULES = ("Edit(**/hooks/**)", "Edit(/hooks/**)")

PERMISSIONS_KEY = "permissions"
DENY_KEY = "deny"
ASK_KEY = "ask"
EDIT_RULE_LABEL = "Edit"
BASH_RULE_LABEL = "Bash"
DENY_RULE_KIND = "deny"
ASK_RULE_KIND = "ask"

# Status words, aligned with the vocabulary sync-plans.sh already prints
STATUS_IN_SYNC = "in-sync"
STATUS_MISSING = "missing"
STATUS_UNWIRED = "UNWIRED"
STATUS_INVALID = "INVALID"
STATUS_CREATED = "created"
STATUS_WIRED = "wired"
STATUS_KEPT = "kept"
OK_STATUSES = frozenset([STATUS_IN_SYNC, STATUS_CREATED, STATUS_WIRED, STATUS_KEPT])

JSON_INDENT = 2
REGENERATE_HINT = "regenerate it with wire-settings.py --self --repo <dir> --write"
NEEDS_ATTENTION = 1
OK = 0


def hook_command(self_mode):
    return SELF_HOOK_COMMAND if self_mode else HOOK_COMMAND


def edit_ask_rules(self_mode):
    """The `hooks/` rule, in this mode's spelling."""
    return SELF_POLICY_ASK_RULES if self_mode else POLICY_ASK_RULES


def entry_for_hook(self_mode):
    return {
        "matcher": HOOK_MATCHER,
        "hooks": [{"type": "command", "command": hook_command(self_mode)}],
    }


def structure_error(settings):
    """The reason this file cannot be merged into, or None. Checked in both modes so
    `--check` never promises a write that `--write` would refuse."""
    hooks = settings.get("hooks")
    if hooks is not None and not isinstance(hooks, dict):
        return '"hooks" is not an object'
    event = (hooks or {}).get(HOOK_EVENT)
    if event is not None and not isinstance(event, list):
        return '"hooks.%s" is not a list' % HOOK_EVENT
    permissions = settings.get(PERMISSIONS_KEY)
    if permissions is not None and not isinstance(permissions, dict):
        return '"%s" is not an object' % PERMISSIONS_KEY
    for key in (DENY_KEY, ASK_KEY):
        value = (permissions or {}).get(key)
        if value is not None and not isinstance(value, list):
            return '"%s.%s" is not a list' % (PERMISSIONS_KEY, key)
    return None


def hook_wired(settings):
    """True when any PreToolUse hook command mentions the script, however spelled."""
    for entry in (settings.get("hooks") or {}).get(HOOK_EVENT) or []:
        for hook in (entry or {}).get("hooks") or []:
            if HOOK_MARKER in str((hook or {}).get("command", "")):
                return True
    return False


def missing_rules(settings, key, rules):
    present = (settings.get(PERMISSIONS_KEY) or {}).get(key) or []
    return [rule for rule in rules if rule not in present]


def gaps_in(settings, self_mode):
    """(need_hook, missing Edit denies, missing Bash denies, missing ask rules). Only
    the hook command and the ask spelling differ between the modes; the deny rules are
    the same list in both, since the policy's own rule left it for `permissions.ask`."""
    return (
        not hook_wired(settings),
        missing_rules(settings, DENY_KEY, EDIT_DENY_RULES),
        missing_rules(settings, DENY_KEY, policy.bash_deny_rules()),
        missing_rules(settings, ASK_KEY, edit_ask_rules(self_mode)),
    )


def apply_gaps(settings, self_mode, need_hook, missing_edit, missing_bash, missing_ask):
    """Append what is absent, in the documented order, and change nothing else."""
    if need_hook:
        settings.setdefault("hooks", {}).setdefault(HOOK_EVENT, []).append(
            entry_for_hook(self_mode))
    if missing_edit or missing_bash:
        settings.setdefault(PERMISSIONS_KEY, {}).setdefault(DENY_KEY, []).extend(
            missing_edit + missing_bash)
    if missing_ask:
        settings.setdefault(PERMISSIONS_KEY, {}).setdefault(ASK_KEY, []).extend(
            missing_ask)


def settings_text(settings):
    return json.dumps(settings, indent=JSON_INDENT) + "\n"


def generated_text(self_mode):
    """The whole file, as a write into an EMPTY repo would leave it. Under `--self` this
    is not one possible result but THE file: nothing else writes that one."""
    settings = {}
    apply_gaps(settings, self_mode, *gaps_in(settings, self_mode))
    return settings_text(settings)


def describe_drift(actual, expected):
    """How a generated file that should be `expected` differs, in one clause.

    A line number alone is a poor answer when the drift is an appended section: the
    first line that differs is then the `]` that used to close the file, which names
    nothing. So the line number comes with the first ENTRY each side has and the other
    does not — which is what a reader is looking for — and a difference that is neither
    (the same entries in another order) says so rather than pointing at a bracket.
    """
    actual_lines, expected_lines = actual.splitlines(), expected.splitlines()
    line = 0
    for index in range(max(len(actual_lines), len(expected_lines))):
        got = actual_lines[index] if index < len(actual_lines) else None
        want = expected_lines[index] if index < len(expected_lines) else None
        if got != want:
            line = index + 1
            break
    extra = [ln for ln in actual_lines if ln not in expected_lines]
    absent = [ln for ln in expected_lines if ln not in actual_lines]
    clauses = []
    if extra:
        clauses.append("carries %s" % extra[0].strip())
    if absent:
        clauses.append("is missing %s" % absent[0].strip())
    if not clauses:
        clauses.append("holds the same entries in a different order")
    return "first differs at line %d; it %s" % (line, " and ".join(clauses))


def load(path):
    """(settings, error). A missing file is ({}, None) — nothing to merge into yet."""
    if not os.path.exists(path):
        return {}, None
    try:
        with open(path) as handle:
            loaded = json.load(handle)
    except (ValueError, OSError) as exc:
        return None, str(exc)
    if not isinstance(loaded, dict):
        return None, "top-level value is not an object"
    return loaded, None


def read_text(path):
    try:
        with open(path) as handle:
            return handle.read()
    except OSError:
        return None


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def report(status, message):
    sys.stdout.write("%s\t%s\n" % (status, message))
    return OK if status in OK_STATUSES else NEEDS_ATTENTION


def describe_gaps(need_hook, missing_edit, missing_bash, missing_ask):
    gaps = []
    if need_hook:
        gaps.append("%s hook" % HOOK_MARKER)
    for label, kind, missing in ((EDIT_RULE_LABEL, DENY_RULE_KIND, missing_edit),
                                 (BASH_RULE_LABEL, DENY_RULE_KIND, missing_bash),
                                 (EDIT_RULE_LABEL, ASK_RULE_KIND, missing_ask)):
        if missing:
            gaps.append("%d %s %s rule(s)" % (len(missing), label, kind))
    return " and ".join(gaps)


def run_self(path, check):
    """agentTooling's own file, which is generated rather than merged. `--check` is a
    byte comparison and `--write` restores the bytes."""
    expected = generated_text(True)
    actual = read_text(path)
    if actual == expected:
        return report(
            STATUS_IN_SYNC if check else STATUS_KEPT,
            "%s (byte-for-byte what --self --write generates)" % SETTINGS_REL)
    if check:
        if actual is None:
            return report(STATUS_MISSING,
                          "%s (absent; %s)" % (SETTINGS_REL, REGENERATE_HINT))
        return report(
            STATUS_UNWIRED,
            "%s (hand-edited: %s; %s)"
            % (SETTINGS_REL, describe_drift(actual, expected), REGENERATE_HINT))
    existed = actual is not None
    write_text(path, expected)
    return report(
        STATUS_CREATED if not existed else STATUS_WIRED,
        "%s (generated from the policy constants) — commit it so worktrees and fresh "
        "clones inherit it" % SETTINGS_REL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="consuming repo root")
    parser.add_argument(
        "--self", action="store_true", dest="self_mode",
        help="agentTooling's own checkout: hooks/ is at the root, not under "
             "agentTooling/, and the file is generated rather than merged")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report without writing")
    mode.add_argument("--write", action="store_true", help="create or merge the entries")
    args = parser.parse_args()

    path = os.path.join(args.repo, SETTINGS_REL)
    if args.self_mode:
        return run_self(path, args.check)

    settings, error = load(path)
    if error is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, error))
    broken = structure_error(settings)
    if broken is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, broken))

    need_hook, missing_edit, missing_bash, missing_ask = gaps_in(settings, False)
    existed = os.path.exists(path)

    if not need_hook and not missing_edit and not missing_bash and not missing_ask:
        return report(
            STATUS_IN_SYNC if args.check else STATUS_KEPT,
            "%s (%s hook, Edit and Bash deny rules and the hooks/ ask rule present)"
            % (SETTINGS_REL, HOOK_MARKER),
        )

    if args.check:
        return report(
            STATUS_UNWIRED if existed else STATUS_MISSING,
            "%s (no %s; run sync-plans.sh)"
            % (SETTINGS_REL,
               describe_gaps(need_hook, missing_edit, missing_bash, missing_ask)),
        )

    apply_gaps(settings, False, need_hook, missing_edit, missing_bash, missing_ask)
    write_text(path, settings_text(settings))

    return report(
        STATUS_CREATED if not existed else STATUS_WIRED,
        "%s (added %s) — commit it so worktrees and fresh clones inherit it"
        % (SETTINGS_REL,
           describe_gaps(need_hook, missing_edit, missing_bash, missing_ask)),
    )


if __name__ == "__main__":
    sys.exit(main())
