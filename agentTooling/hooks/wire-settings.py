#!/usr/bin/env python3
"""Wire the hook and its deny rules into a consuming repo's `.claude/settings.json`.

Called by `sync-plans.sh` at install and after every `subtree pull`, and by
`self/gate.sh --self` for agentTooling's own checkout. The settings file is repo-owned
and may hold anything, so this merges rather than copies: it appends the `PreToolUse`
entry for `allow-repo-commands.sh` when no hook already references the script, and
appends each `Edit` and `Bash` deny rule that is absent. It never removes, reorders or
rewrites another entry. Everything it adds is a restriction or a prompt-remover for
reads; it never adds an allow rule.

The `Edit` rules exist because `--permission-mode acceptEdits` — which the batch runners
use — accepts every Edit-tool write under the working directory, including into `.git/`
(hooks are executable), `.claude/` (permissions), and the dependency trees (code that
runs on the next test). Deny rules bind in every permission mode and cannot be
overridden by a mode or an allow rule. They cover the Edit and Write tools and `> file`
redirects, not a subprocess that opens a file itself.

The `Bash` rules are the visible half of `LIFECYCLE.md` rule 2 — agents never create or
destroy branches and worktrees, and never rewrite history. They are prefix rules, so
they match only the spelling they name: `git -C /repo worktree add x` and
`x=$(git rebase main)` slip past every one of them. The *enforcement* is
`allow-repo-commands.sh`'s git deny, which reads the whole line; `GIT_MUTATING_*` there
and `BASH_DENY_RULES` here are the same list and move together. Keeping the rules as
well costs nothing and puts the policy where `/permissions` will show it.

`--self` writes agentTooling's own checkout instead of a consuming repo's: the hook path
loses the `agentTooling/` segment and the policy deny rule becomes `Edit(/hooks/**)`,
since here `hooks/` is at the root. Everything else is identical.

Emits one `status<TAB>message` line for the caller to format, and exits 0 when nothing
needs attention, 1 otherwise.
"""

import argparse
import json
import os
import sys

# Where the wiring lives in the consuming repo
SETTINGS_REL = os.path.join(".claude", "settings.json")

# The hook entry. The marker identifies it across hand-edits to the path, the matcher
# or an added `if:` — a repo that customized the entry keeps its version, and a second
# one is never appended alongside it.
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
# The policy itself: an unattended executor must not be able to widen what the hook
# approves. Editing it is rare and prompts, which is the point. The two spellings are
# the same rule — the hooks directory is vendored one level in, or at the root here.
POLICY_EDIT_DENY_RULE = "Edit(**/agentTooling/hooks/**)"
SELF_POLICY_EDIT_DENY_RULE = "Edit(/hooks/**)"

# Bash deny rules: LIFECYCLE.md rule 2, written where `/permissions` shows it. These are
# PREFIX rules — each matches only a command that begins with the text it names, so
# `git -C /repo worktree add x`, `x=$(git rebase main)` and `ls && git stash` match none
# of them. What actually enforces the rule is the git deny in `allow-repo-commands.sh`
# (`GIT_ALWAYS_MUTATING` and the `GIT_*` constants beside it), which reads every command
# on the line; this tuple and that list are the same policy and are changed together.
BASH_DENY_RULES = (
    "Bash(git push --force:*)",
    "Bash(git push -f:*)",
    "Bash(git push --force-with-lease:*)",
    "Bash(git reset --hard:*)",
    "Bash(git clean:*)",
    "Bash(git stash:*)",
    "Bash(git rebase:*)",
    "Bash(git worktree add:*)",
    "Bash(git worktree remove:*)",
    "Bash(git worktree prune:*)",
    "Bash(git checkout -b:*)",
    "Bash(git checkout -B:*)",
    "Bash(git switch -c:*)",
    "Bash(git switch -C:*)",
    "Bash(git branch -d:*)",
    "Bash(git branch -D:*)",
    "Bash(git branch -m:*)",
    "Bash(git branch -M:*)",
)
PERMISSIONS_KEY = "permissions"
DENY_KEY = "deny"
EDIT_RULE_LABEL = "Edit"
BASH_RULE_LABEL = "Bash"

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
NEEDS_ATTENTION = 1
OK = 0


def hook_command(self_mode):
    return SELF_HOOK_COMMAND if self_mode else HOOK_COMMAND


def edit_deny_rules(self_mode):
    """The Edit rules in this mode's spelling: the common ones, then the policy rule."""
    policy = SELF_POLICY_EDIT_DENY_RULE if self_mode else POLICY_EDIT_DENY_RULE
    return EDIT_DENY_RULES + (policy,)


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
    deny = (permissions or {}).get(DENY_KEY)
    if deny is not None and not isinstance(deny, list):
        return '"%s.%s" is not a list' % (PERMISSIONS_KEY, DENY_KEY)
    return None


def hook_wired(settings):
    """True when any PreToolUse hook command mentions the script, however spelled."""
    for entry in (settings.get("hooks") or {}).get(HOOK_EVENT) or []:
        for hook in (entry or {}).get("hooks") or []:
            if HOOK_MARKER in str((hook or {}).get("command", "")):
                return True
    return False


def missing_deny_rules(settings, rules):
    present = (settings.get(PERMISSIONS_KEY) or {}).get(DENY_KEY) or []
    return [rule for rule in rules if rule not in present]


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


def report(status, message):
    sys.stdout.write("%s\t%s\n" % (status, message))
    return OK if status in OK_STATUSES else NEEDS_ATTENTION


def describe_gaps(need_hook, missing_edit, missing_bash):
    gaps = []
    if need_hook:
        gaps.append("%s hook" % HOOK_MARKER)
    for label, missing in ((EDIT_RULE_LABEL, missing_edit), (BASH_RULE_LABEL, missing_bash)):
        if missing:
            gaps.append("%d %s deny rule(s)" % (len(missing), label))
    return " and ".join(gaps)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="consuming repo root")
    parser.add_argument(
        "--self", action="store_true", dest="self_mode",
        help="agentTooling's own checkout: hooks/ is at the root, not under agentTooling/")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report without writing")
    mode.add_argument("--write", action="store_true", help="create or merge the entries")
    args = parser.parse_args()

    edit_rules = edit_deny_rules(args.self_mode)
    path = os.path.join(args.repo, SETTINGS_REL)
    settings, error = load(path)
    if error is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, error))
    broken = structure_error(settings)
    if broken is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, broken))

    need_hook = not hook_wired(settings)
    missing_edit = missing_deny_rules(settings, edit_rules)
    missing_bash = missing_deny_rules(settings, BASH_DENY_RULES)
    existed = os.path.exists(path)

    if not need_hook and not missing_edit and not missing_bash:
        return report(
            STATUS_IN_SYNC if args.check else STATUS_KEPT,
            "%s (%s hook and Edit and Bash deny rules present)" % (SETTINGS_REL, HOOK_MARKER),
        )

    if args.check:
        return report(
            STATUS_UNWIRED if existed else STATUS_MISSING,
            "%s (no %s; run sync-plans.sh)"
            % (SETTINGS_REL, describe_gaps(need_hook, missing_edit, missing_bash)),
        )

    if need_hook:
        settings.setdefault("hooks", {}).setdefault(HOOK_EVENT, []).append(
            entry_for_hook(args.self_mode))
    if missing_edit or missing_bash:
        settings.setdefault(PERMISSIONS_KEY, {}).setdefault(DENY_KEY, []).extend(
            missing_edit + missing_bash)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(settings, handle, indent=JSON_INDENT)
        handle.write("\n")

    return report(
        STATUS_CREATED if not existed else STATUS_WIRED,
        "%s (added %s) — commit it so worktrees and fresh clones inherit it"
        % (SETTINGS_REL, describe_gaps(need_hook, missing_edit, missing_bash)),
    )


if __name__ == "__main__":
    sys.exit(main())
