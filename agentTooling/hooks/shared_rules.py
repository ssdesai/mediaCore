#!/usr/bin/env python3
"""The rules the PreToolUse hook shares with `analysis/` and the lifecycle scripts, written once.

The hook can import only siblings in `hooks/`, so a rule it shares with `analysis/` or a
top-level `*.sh` used to be written twice or three times and held equal by a test that
compared the copies. Each such rule lives here instead, as a constant, and every other
file binds to it (`ORCH_KIND_KEY = shared_rules.KIND_KEY`): a binding is a reference, never
a second literal. `self/tests/shared-rules.sh` holds that: no other file assigns one of
these literals.

What is here: where the orchestration records live and what they are called, the fence keys
that make a record a role or a coordinator record, the orchestrator ledger's name, the slug
pattern, how git marks a checkout, and the two refusal texts `orchestration-start.sh` and
`analysis/roots.py` both give.

The shell reads these through the command line, one value per line in the order asked:

    python3 -B hooks/shared_rules.py NAME [NAME ...]

It prints the values and exits 0; for an unknown name, or none at all, it prints nothing
and exits 2, so a caller that cannot read a value refuses rather than guess one. A value that
is a tuple prints its words separated by one space.

Stdlib only and constant at import: it needs `re` and `sys` and does no file or process work
when imported, so importing it costs the hook nothing.
"""

import re
import sys

sys.dont_write_bytecode = True

# Where orchestration records live, relative to the tooling directory (agentTooling's own,
# and the old vendored home of a consumer's) and to the consuming repo's root
ORCHESTRATIONS_SELF_REL = "self/orchestrations"
ORCHESTRATIONS_CONSUMER_REL = "plans/orchestrations"
RECORD_NAME = "README.md"
# A directory holding this entry (a directory in a clone, a file in a linked worktree) is a
# checkout of its own; the lines that read it without running git use the two names below
GIT_ENTRY = ".git"
GITDIR_PREFIX = "gitdir:"
COMMONDIR_NAME = "commondir"
# The fence keys: `session` makes a record a role, `kind: coordinator` makes it a cost record
SESSION_KEY = "session"
KIND_KEY = "kind"
KIND_COORDINATOR = "coordinator"
FEATURES_KEY = "features"
FEATURE_REPO_KEY = "repo"
# A features[] entry: its keys in the order they are written, and the two an orchestrator's
# `add-feature` fills and a coordinator record never does
FEATURE_BRANCH_KEY = "branch"
ORCHESTRATOR_FEATURE_KEYS = (SESSION_KEY, FEATURE_BRANCH_KEY)
ORCH_FEATURE_KEYS = (FEATURE_REPO_KEY, "slug", SESSION_KEY, FEATURE_BRANCH_KEY, "pr", "report")
# The local ledger of orchestrator sessions, under the checkout's git common directory
LEDGER_NAME = "agenttooling-orchestrators"
# A feature or record slug
SLUG_PATTERN = "^[a-z0-9]+(-[a-z0-9]+)*$"
SLUG_RE = re.compile(SLUG_PATTERN)
# A record at the old vendored place is moved, never read in place. The `mkdir -p` first: git
# tracks no empty directory, so a consuming repo whose only record is stranded has no
# `plans/orchestrations/` for `git mv` to move into (orchestration-start-branch-v2). The hook
# approves this exact line for the record's own orchestrator.
LEGACY_RECORD_MKDIR = "mkdir -p " + ORCHESTRATIONS_CONSUMER_REL
LEGACY_RECORD_MOVE = (LEGACY_RECORD_MKDIR + " && git mv agentTooling/" + ORCHESTRATIONS_SELF_REL
                      + "/{slug} " + ORCHESTRATIONS_CONSUMER_REL + "/{slug}")
LEGACY_RECORD_REFUSAL = (
    "the record `{slug}` is at the old place, agentTooling/" + ORCHESTRATIONS_SELF_REL
    + "/{slug} — a record lives in the repo that ran it now; move it: " + LEGACY_RECORD_MOVE)
# Without --self in agentTooling's own checkout there is no consuming repo above it
STANDALONE_REFUSAL = (
    "this is agentTooling's own checkout, not a consuming repo: without --self a record "
    "would land outside it — pass --self for agentTooling's own records ("
    + ORCHESTRATIONS_SELF_REL + "/)")

# CLI
USAGE_RC = 2
OK_RC = 0
TUPLE_SEPARATOR = " "


def is_words(value):
    """True for a string, or a non-empty tuple of strings: what the command line can print."""
    return isinstance(value, str) or (
        isinstance(value, tuple) and bool(value) and all(isinstance(v, str) for v in value))


# The constants above that the command line serves, by name: this module's upper-case strings and
# string tuples, taken once when it is imported
SERVED = {name: value for name, value in dict(vars()).items() if name.isupper() and is_words(value)}


def rendered(name):
    """The line printed for `name`."""
    value = SERVED[name]
    return value if isinstance(value, str) else TUPLE_SEPARATOR.join(value)


def main(argv):
    """Print each named value, one per line; print nothing and return USAGE_RC when there is
    no name or any name is unknown, so a partial answer is never read as a whole one."""
    if not argv or not all(name in SERVED for name in argv):
        return USAGE_RC
    for name in argv:
        print(rendered(name))
    return OK_RC


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
