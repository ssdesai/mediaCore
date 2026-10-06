#!/usr/bin/env python3
"""Wire the hook and its permission rules into a repo's `.claude/settings.json`.

Called by `sync-plans.sh` at install and after every `subtree pull`; and, under `--self`
for agentTooling's own checkout, by hand after a change to the policy constants
(`--write`, then commit the file) and by `self/gate.sh` (`--check`).

**In a consuming repo the file is repo-owned and may hold anything, so this merges
rather than copies**: it appends the `PreToolUse` entry for `allow-repo-commands.sh`
when no hook already references the script, the `SessionStart` entry running
`plans/cloud-setup.sh` when no SessionStart hook already names that script (once per
container in a Claude Code cloud container; the script itself is a no-op anywhere else),
and appends each `Edit` deny, `Bash` deny
and `Edit` ask rule that is absent. It never reorders or rewrites another entry, and it
removes exactly one kind: a `Bash` deny rule this helper itself once wrote and the policy
table has since retired (`policy.retired_bash_deny_rules()` — `Bash(git stash:*)`, which
denied `git stash list` too, and a deny rule beats the hook's allow). Everything it adds
is a restriction or a prompt-remover for reads; it never adds an allow rule.

The `sandbox` block is the one section with owned VALUES: `enabled`, `failIfUnavailable`
and `allowUnsandboxedCommands` are set to the generator's value wherever they stand (a
repo that flipped `enabled` by hand is set back to `SANDBOX_ENABLED` — OFF today, so the
one place to turn the sandbox on is that constant), while
`filesystem.denyRead` and `network.allowedDomains` are unions: the repo's own entries
stay first and the generator's missing ones are appended. Every other sandbox key is
the repo's. An allowed domain is a narrowing, not a widening: before this block the
executor's network was unrestricted.

**Under `--self` the one file, `.claude/settings.json`, is wholly GENERATED and TRACKED**
(self/features/self-cloud-bootstrap), because nothing else writes agentTooling's own:
`--check` compares it BYTE FOR BYTE with what a fresh write would produce and names the
first line that differs, and `--write` puts those bytes back. That is the difference a
merge check could not see — a hand-added allow rule, a hook command repointed at a path
that would never run, a reordered list — each of which left the gate green while
`hooks/README.md` said it failed. The hook path loses its `agentTooling/` segment there
and is GUARDED (`SELF_HOOK_COMMAND`), and the policy ask rule is spelled for a checkout
whose `hooks/` is at the root. Nothing else is generated: no SessionStart entry, and no
`.claude/settings.local.json`, which is Claude Code's own per-user file (git-ignored).

It is tracked because a fresh clone — every new cloud container — must have the hook and
the deny rules from its FIRST tool call, and only a file present at startup is read before
it: a policy that a SessionStart hook wrote into an untracked file (that feature's round
1) reloaded asynchronously and missed the first call in 3 of 15 fresh sessions (its
NOTES.md, ruling 1). Tracking it ships it with the subtree, which is harmless: a session
launched at a consuming repo's root never loads a nested
`agentTooling/.claude/settings.json`, and one launched INSIDE `agentTooling/` does, with
`${CLAUDE_PROJECT_DIR}` that directory, where every path the file names exists (ruling
2). The guard covers whatever is left — a project directory with no
`hooks/allow-repo-commands.sh` — as a silent exit 0.

A vendored agentTooling (no `.git` of its own, one above it) is checked like any other —
the shipped bytes against the generator's — but `--write` writes nothing there, so a
failure names the fix UPSTREAM (regenerate in a standalone checkout, commit, pull) rather
than a local command. In a standalone checkout a failure names the exact command that
regenerates.

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
destroy branches and worktrees, and never rewrite history. They are prefix rules (and one
exact rule, bare `git stash`), so they match only the spelling they name: `git -C /repo worktree add x` and
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

# Where the wiring lives: the consuming repo's own file, and under `--self` agentTooling's
# tracked, generated policy (self/features/self-cloud-bootstrap)
SETTINGS_REL = os.path.join(".claude", "settings.json")

# The hook entry. The marker identifies it across hand-edits to the path, the matcher
# or an added `if:` — a repo that customized the entry keeps its version, and a second
# one is never appended alongside it. (Under `--self` a customized entry is drift, not a
# customization: that file is generated.)
HOOK_MARKER = "allow-repo-commands.sh"
HOOK_COMMAND = "${CLAUDE_PROJECT_DIR}/agentTooling/hooks/allow-repo-commands.sh"
# agentTooling's own checkout: `hooks/` is at the root, not under `agentTooling/`
SELF_HOOK_PATH = "${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh"
# ...and GUARDED, because that file is tracked and ships with the subtree: where the
# script does not exist under the project directory (a consuming repo's root, were it ever
# loaded there) the `test` exits 0 with no output, and the hook is a silent no-op. Where it
# exists, the script runs and reads the PreToolUse payload on stdin, which the shell hands
# on untouched — `test` reads none of it (self/tests/self-settings.sh F).
SELF_HOOK_COMMAND = 'test ! -f "%s" || "%s"' % (SELF_HOOK_PATH, SELF_HOOK_PATH)
HOOK_EVENT = "PreToolUse"
HOOK_MATCHER = "Bash"

# The SessionStart entry (self/DESIGN-2026-10-05-cloud-execution.md §7): the repo's seeded
# plans/cloud-setup.sh, the once-per-container step. It carries no matcher (every start —
# a container restart resumes the session) and no guard: the GUARD IS THE SCRIPT'S OWN, which
# asks env-profile.sh and exits 0 outside the cloud profile, so nothing in this file spells
# the profile variables (self/profile-confinement.sh). Recognised by the marker across
# hand-edits, like the PreToolUse entry. Consuming repos only: a `--self` checkout has no
# plans/cloud-setup.sh (its corpus is self/, never seeded), so its generated file carries
# none (self/features/execution-profiles/NOTES.md) — and needs none, being tracked.
SESSION_MARKER = "cloud-setup.sh"
SESSION_COMMAND = "${CLAUDE_PROJECT_DIR}/plans/cloud-setup.sh"
SESSION_EVENT = "SessionStart"

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

# The OS sandbox (Claude Code's `sandbox` settings key; Seatbelt on macOS, bubblewrap on
# Linux): the boundary under every Bash subprocess, which the permission rules above
# cannot see into. It binds `claude -p` too, so a runner's executor inherits it from
# this file. See hooks/README.md → "The sandbox block".
SANDBOX_KEY = "sandbox"
SANDBOX_FILESYSTEM_KEY = "filesystem"
SANDBOX_NETWORK_KEY = "network"
SANDBOX_DENY_READ_KEY = "denyRead"
SANDBOX_DOMAINS_KEY = "allowedDomains"
# The one switch for the whole block. OFF (self/features/sandbox-consumer-reads): where
# the user's `permissions.blockReadsOutsideWorkingDirectories` is on, the sandbox refuses
# every read under the home directory, so a consumer's verify pass cannot reach the
# Playwright browser cache — and an `allowRead` in this repo-level file cannot re-open it
# (Claude Code drops repository `allowRead` entries under that block). Turn it on once
# the machine's USER settings re-open the cache (`~/.claude/settings.json` →
# `sandbox.filesystem.allowRead`), or the block is off. Flipping this constant plus a
# propagation pull (`sync-plans.sh` rewrites every consumer's file) is the whole
# procedure; everything below stays written either way.
SANDBOX_ENABLED = False
# Owned outright, in both layouts: `enabled` from the switch above (a repo that flipped
# it by hand is set back), failing closed where the sandbox is unavailable (a batch must
# never run unsandboxed without saying so), and no escape hatch for a command that fails
# inside it — the last two inert while the switch is off, correct once it is on. `autoAllowBashIfSandboxed` is deliberately NOT written — Bash
# approval stays the runner's `--allowedTools` and the hook's policy. With `enabled` on,
# Claude Code's built-in write denies apply with no setting of ours (`.git/hooks`,
# `.git/config`, `.git/HEAD`, `objects/`, `refs/`, `.claude/settings*`,
# `.claude/{skills,agents,commands,hooks,workflows}/`, `.mcp.json`, shell rc files,
# `~/.claude/`), so no `denyWrite` is written: it would only restate that list.
SANDBOX_OWNED_SETTINGS = (
    ("enabled", SANDBOX_ENABLED),
    ("failIfUnavailable", True),
    ("allowUnsandboxedCommands", False),
)
# The sandbox's own read default is open, so the block closes only the credential stores
# — never `~/` or `~/.claude`, which the Playwright cache and analysis/'s reads of
# ~/.claude/projects need. Other settings layers can narrow reads further: where
# `permissions.blockReadsOutsideWorkingDirectories` is on, the
# sandbox enforces it too and a subprocess cannot read the home directory at all
# (self/features/runner-sandbox/NOTES.md). That is the other layer's choice, not this one.
SANDBOX_DENY_READ = ("~/.ssh", "~/.aws", "~/.config/gh")
# The network allowlist, unioned into a consumer's own. Package registries first, then
# the model API and GitHub; extended only with what a real run under the sandbox was
# refused (self/features/runner-sandbox/NOTES.md). `strictAllowlist` is left at its
# default (off): an unknown domain PROMPTS in an attended session and, with nobody to
# answer in `claude -p`, is refused there.
SANDBOX_ALLOWED_DOMAINS = (
    "registry.npmjs.org",
    "pypi.org",
    "files.pythonhosted.org",
    "api.anthropic.com",
    "github.com",
    "api.github.com",
    "objects.githubusercontent.com",
)
SANDBOX_LABEL = "sandbox"
SANDBOX_OWNED_LABEL = "owned setting(s)"
SANDBOX_DENY_READ_LABEL = "denyRead path(s)"
SANDBOX_DOMAINS_LABEL = "allowed domain(s)"

PERMISSIONS_KEY = "permissions"
DENY_KEY = "deny"
ASK_KEY = "ask"
EDIT_RULE_LABEL = "Edit"
BASH_RULE_LABEL = "Bash"
DENY_RULE_KIND = "deny"
ASK_RULE_KIND = "ask"
RETIRED_RULE_LABEL = "retired"
# How a gap is worded in the one-line message
CHECK_MISSING_LEAD = "no "
WRITE_MISSING_LEAD = "added "
CHECK_RETIRED_TAIL = " to remove"
WRITE_RETIRED_LEAD = "removed "
CHANGE_SEPARATOR = "; "

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
JSON_SEPARATOR = ","
# The one command that puts agentTooling's own file back, spelled with this checkout's
# absolute paths so a failure can be pasted as it stands (python3 -B: no __pycache__).
REGENERATE_COMMAND = "python3 -B %s --self --repo %s --write"
REGENERATE_HINT = "regenerate it: %s, then commit it"
# A vendored copy's fix: its file is the subtree's and `--write` writes nothing there, so
# no local command can put it right. Deliberately no `--repo <path>` pasteable here.
VENDORED_FIX_HINT = (
    "a vendored copy is the subtree's, so the fix is upstream: regenerate it in a "
    "standalone agentTooling checkout (python3 -B hooks/wire-settings.py --self --repo "
    "<that checkout> --write), commit it there, and pull it here")
VENDORED_NOTHING_WRITTEN = "nothing written"
VENDORED_IN_SYNC_NOTE = "the subtree's copy"
# What marks a git checkout's root: a directory in a clone, a file in a worktree. A
# vendored agentTooling/ has none of its own and one in an ancestor (the consuming repo).
GIT_MARKER = ".git"
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


def entry_for_session():
    return {"hooks": [{"type": "command", "command": SESSION_COMMAND}]}


def wrong_type(container, key, kind):
    """True when `key` is PRESENT and not a `kind` — an explicit null included, since a
    write would setdefault() into it and crash rather than report."""
    return key in container and not isinstance(container[key], kind)


def structure_error(settings):
    """The reason this file cannot be merged into, or None. Checked in both modes so
    `--check` never promises a write that `--write` would refuse."""
    if wrong_type(settings, "hooks", dict):
        return '"hooks" is not an object'
    for event in (HOOK_EVENT, SESSION_EVENT):
        if wrong_type(settings.get("hooks") or {}, event, list):
            return '"hooks.%s" is not a list' % event
    if wrong_type(settings, PERMISSIONS_KEY, dict):
        return '"%s" is not an object' % PERMISSIONS_KEY
    for key in (DENY_KEY, ASK_KEY):
        if wrong_type(settings.get(PERMISSIONS_KEY) or {}, key, list):
            return '"%s.%s" is not a list' % (PERMISSIONS_KEY, key)
    if wrong_type(settings, SANDBOX_KEY, dict):
        return '"%s" is not an object' % SANDBOX_KEY
    sandbox = settings.get(SANDBOX_KEY) or {}
    for section, key in ((SANDBOX_FILESYSTEM_KEY, SANDBOX_DENY_READ_KEY),
                         (SANDBOX_NETWORK_KEY, SANDBOX_DOMAINS_KEY)):
        if wrong_type(sandbox, section, dict):
            return '"%s.%s" is not an object' % (SANDBOX_KEY, section)
        if wrong_type(sandbox.get(section) or {}, key, list):
            return '"%s.%s.%s" is not a list' % (SANDBOX_KEY, section, key)
    return None


def event_wired(settings, event, marker):
    """True when any hook command under `event` mentions `marker`, however spelled."""
    for entry in (settings.get("hooks") or {}).get(event) or []:
        for hook in (entry or {}).get("hooks") or []:
            if marker in str((hook or {}).get("command", "")):
                return True
    return False


def hook_wired(settings):
    """True when any PreToolUse hook command mentions the script, however spelled."""
    return event_wired(settings, HOOK_EVENT, HOOK_MARKER)


def session_needed(settings, self_mode):
    """True when a consuming repo's file has no SessionStart entry naming cloud-setup.sh.
    Never under `--self`, whose generated file carries none."""
    return not self_mode and not event_wired(settings, SESSION_EVENT, SESSION_MARKER)


def missing_rules(settings, key, rules):
    present = (settings.get(PERMISSIONS_KEY) or {}).get(key) or []
    return [rule for rule in rules if rule not in present]


def present_rules(settings, key, rules):
    present = (settings.get(PERMISSIONS_KEY) or {}).get(key) or []
    return [rule for rule in rules if rule in present]


def sandbox_section(settings, section):
    return ((settings.get(SANDBOX_KEY) or {}).get(section)) or {}


def wrong_sandbox_settings(settings):
    """The owned keys whose value is not the generator's — absent included. Compared by
    identity so a `1` or `"true"` is wrong too: the sandbox reads a JSON boolean."""
    sandbox = settings.get(SANDBOX_KEY) or {}
    return [key for key, value in SANDBOX_OWNED_SETTINGS
            if key not in sandbox or sandbox[key] is not value]


def missing_entries(present, wanted):
    return [entry for entry in wanted if entry not in (present or [])]


def gaps_in(settings, self_mode):
    """(need_hook, missing Edit denies, missing Bash denies, missing ask rules, retired
    Bash denies still present, wrong owned sandbox settings, missing denyRead paths,
    missing allowed domains, need_session). Only the hook command, the ask spelling and
    the SessionStart entry (consuming repos only) differ between the modes; the deny rules
    and the sandbox block are the same in both, since the policy's own rule left it for
    `permissions.ask`."""
    return (
        not hook_wired(settings),
        missing_rules(settings, DENY_KEY, EDIT_DENY_RULES),
        missing_rules(settings, DENY_KEY, policy.bash_deny_rules()),
        missing_rules(settings, ASK_KEY, edit_ask_rules(self_mode)),
        present_rules(settings, DENY_KEY, policy.retired_bash_deny_rules()),
        wrong_sandbox_settings(settings),
        missing_entries(sandbox_section(settings, SANDBOX_FILESYSTEM_KEY).get(
            SANDBOX_DENY_READ_KEY), SANDBOX_DENY_READ),
        missing_entries(sandbox_section(settings, SANDBOX_NETWORK_KEY).get(
            SANDBOX_DOMAINS_KEY), SANDBOX_ALLOWED_DOMAINS),
        session_needed(settings, self_mode),
    )


def apply_sandbox(settings, wrong_owned, missing_deny_read, missing_domains):
    """Set the owned keys to the generator's values where they stand (appended when
    absent), and union the generator's denyRead paths and domains in AFTER whatever the
    repo already lists. Every other sandbox key is the repo's and is left alone."""
    if not (wrong_owned or missing_deny_read or missing_domains):
        return
    sandbox = settings.setdefault(SANDBOX_KEY, {})
    for key, value in SANDBOX_OWNED_SETTINGS:
        if key in wrong_owned:
            sandbox[key] = value
    if missing_deny_read:
        sandbox.setdefault(SANDBOX_FILESYSTEM_KEY, {}).setdefault(
            SANDBOX_DENY_READ_KEY, []).extend(missing_deny_read)
    if missing_domains:
        sandbox.setdefault(SANDBOX_NETWORK_KEY, {}).setdefault(
            SANDBOX_DOMAINS_KEY, []).extend(missing_domains)


def apply_gaps(settings, self_mode, need_hook, missing_edit, missing_bash, missing_ask,
               retired_bash, wrong_owned, missing_deny_read, missing_domains, need_session):
    """Remove the retired rules where they stand, append what is absent, in the
    documented order, set the owned sandbox keys, and change nothing else."""
    if retired_bash:
        deny = settings[PERMISSIONS_KEY][DENY_KEY]
        deny[:] = [rule for rule in deny if rule not in retired_bash]
    if need_hook:
        settings.setdefault("hooks", {}).setdefault(HOOK_EVENT, []).append(
            entry_for_hook(self_mode))
    if need_session:
        settings.setdefault("hooks", {}).setdefault(SESSION_EVENT, []).append(
            entry_for_session())
    if missing_edit or missing_bash:
        settings.setdefault(PERMISSIONS_KEY, {}).setdefault(DENY_KEY, []).extend(
            missing_edit + missing_bash)
    if missing_ask:
        settings.setdefault(PERMISSIONS_KEY, {}).setdefault(ASK_KEY, []).extend(
            missing_ask)
    apply_sandbox(settings, wrong_owned, missing_deny_read, missing_domains)


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
    # Entries compared without their separator: appending to a list moves the comma onto
    # the old last entry, which would otherwise be named as the drift in its place.
    actual_entries = [ln.rstrip(JSON_SEPARATOR) for ln in actual_lines]
    expected_entries = [ln.rstrip(JSON_SEPARATOR) for ln in expected_lines]
    extra = [ln for ln in actual_entries if ln not in expected_entries]
    absent = [ln for ln in expected_entries if ln not in actual_entries]
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


def describe_sandbox(wrong_owned, missing_deny_read, missing_domains):
    """`sandbox <n> owned setting(s), …`, naming only what is off, or nothing."""
    parts = ["%d %s" % (len(items), label)
             for items, label in ((wrong_owned, SANDBOX_OWNED_LABEL),
                                  (missing_deny_read, SANDBOX_DENY_READ_LABEL),
                                  (missing_domains, SANDBOX_DOMAINS_LABEL)) if items]
    return ("%s %s" % (SANDBOX_LABEL, ", ".join(parts))) if parts else ""


def describe_gaps(need_hook, missing_edit, missing_bash, missing_ask, wrong_owned,
                  missing_deny_read, missing_domains, need_session):
    gaps = []
    if need_hook:
        gaps.append("%s hook" % HOOK_MARKER)
    if need_session:
        gaps.append("%s %s hook" % (SESSION_MARKER, SESSION_EVENT))
    for label, kind, missing in ((EDIT_RULE_LABEL, DENY_RULE_KIND, missing_edit),
                                 (BASH_RULE_LABEL, DENY_RULE_KIND, missing_bash),
                                 (EDIT_RULE_LABEL, ASK_RULE_KIND, missing_ask)):
        if missing:
            gaps.append("%d %s %s rule(s)" % (len(missing), label, kind))
    sandbox = describe_sandbox(wrong_owned, missing_deny_read, missing_domains)
    if sandbox:
        gaps.append(sandbox)
    return " and ".join(gaps)


def describe_changes(gaps, check):
    """The whole gap as one clause: what is missing (`no …` for a check, `added …` for a
    write) and the retired rules (`… to remove`, `removed …`)."""
    (need_hook, missing_edit, missing_bash, missing_ask, retired_bash, wrong_owned,
     missing_deny_read, missing_domains, need_session) = gaps
    parts = []
    missing = describe_gaps(need_hook, missing_edit, missing_bash, missing_ask,
                            wrong_owned, missing_deny_read, missing_domains, need_session)
    if missing:
        parts.append((CHECK_MISSING_LEAD if check else WRITE_MISSING_LEAD) + missing)
    if retired_bash:
        retired = "%d %s %s %s rule(s) (%s)" % (
            len(retired_bash), RETIRED_RULE_LABEL, BASH_RULE_LABEL, DENY_RULE_KIND,
            ", ".join(retired_bash))
        parts.append(retired + CHECK_RETIRED_TAIL if check else WRITE_RETIRED_LEAD + retired)
    return CHANGE_SEPARATOR.join(parts)


def is_vendored(repo):
    """True when `repo` is agentTooling vendored inside another checkout: no git marker
    of its own, and one in some ancestor. A directory with no git anywhere above it is
    treated as a standalone checkout — the shape a test's scratch directory has."""
    repo = os.path.abspath(repo)
    if os.path.exists(os.path.join(repo, GIT_MARKER)):
        return False
    parent = os.path.dirname(repo)
    while parent != repo:
        if os.path.exists(os.path.join(parent, GIT_MARKER)):
            return True
        repo, parent = parent, os.path.dirname(parent)
    return False


def regenerate_hint(repo):
    return REGENERATE_HINT % (
        REGENERATE_COMMAND % (os.path.realpath(__file__), os.path.abspath(repo)))


def describe_problem(actual, expected):
    """`absent`, or `hand-edited: <where it first differs>`."""
    if actual is None:
        return "absent"
    return "hand-edited: %s" % describe_drift(actual, expected)


def run_self(repo, check):
    """agentTooling's own file, generated rather than merged, and tracked. `--check` is a
    byte comparison in every layout; `--write` restores the bytes in a standalone checkout
    and writes nothing in a vendored one, whose copy is the subtree's: there a mismatch is
    reported with the fix upstream, the same status `--check` would give."""
    path = os.path.join(repo, SETTINGS_REL)
    vendored = is_vendored(repo)
    expected = generated_text(True)
    actual = read_text(path)
    if actual == expected:
        return report(
            STATUS_IN_SYNC if check else STATUS_KEPT,
            "%s (byte-for-byte what --self --write generates%s)"
            % (SETTINGS_REL, "; " + VENDORED_IN_SYNC_NOTE if vendored else ""))
    status = STATUS_MISSING if actual is None else STATUS_UNWIRED
    problem = describe_problem(actual, expected)
    if vendored:
        if not check:
            problem = "%s; %s" % (problem, VENDORED_NOTHING_WRITTEN)
        return report(status, "%s (%s; %s)" % (SETTINGS_REL, problem, VENDORED_FIX_HINT))
    if check:
        return report(status, "%s (%s; %s)" % (SETTINGS_REL, problem, regenerate_hint(repo)))
    write_text(path, expected)
    return report(
        STATUS_CREATED if actual is None else STATUS_WIRED,
        "%s (generated from the policy constants; it is tracked — commit it)"
        % SETTINGS_REL)


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

    if args.self_mode:
        return run_self(args.repo, args.check)
    path = os.path.join(args.repo, SETTINGS_REL)

    settings, error = load(path)
    if error is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, error))
    broken = structure_error(settings)
    if broken is not None:
        return report(STATUS_INVALID, "%s (%s; left untouched)" % (SETTINGS_REL, broken))

    gaps = gaps_in(settings, False)
    existed = os.path.exists(path)

    if not any(gaps):
        return report(
            STATUS_IN_SYNC if args.check else STATUS_KEPT,
            "%s (%s hook, %s %s hook, Edit and Bash deny rules, the hooks/ ask rule and "
            "the sandbox block present)"
            % (SETTINGS_REL, HOOK_MARKER, SESSION_MARKER, SESSION_EVENT),
        )

    if args.check:
        return report(
            STATUS_UNWIRED if existed else STATUS_MISSING,
            "%s (%s; run sync-plans.sh)" % (SETTINGS_REL, describe_changes(gaps, True)),
        )

    apply_gaps(settings, False, *gaps)
    write_text(path, settings_text(settings))

    return report(
        STATUS_CREATED if not existed else STATUS_WIRED,
        "%s (%s) — commit it so worktrees and fresh clones inherit it"
        % (SETTINGS_REL, describe_changes(gaps, False)),
    )


if __name__ == "__main__":
    sys.exit(main())
