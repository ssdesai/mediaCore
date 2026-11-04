#!/usr/bin/env python3
"""The profile detector: where is agentTooling running — a laptop (`local`) or a Claude
Code cloud container (`cloud`)? (self/DESIGN-2026-10-05-cloud-execution.md §1,
self/features/review-base-and-cloud-hook/.)

This module is the ONE place the rule lives and the only code that spells either of the
two variables it reads; self/profile-confinement.sh fails the gate on any other tracked
script that does, outside the adapters and the tests. The rule, in order:

  1. an explicit AGENTTOOLING_PROFILE wins — tests and forcing. A value that is neither
     `local` nor `cloud` is an ERROR (InvalidProfile), never a fallback: a typo in a
     forcing variable must not quietly mean `local`;
  2. otherwise CLAUDE_CODE_REMOTE=true (exactly `true`) → `cloud`;
  3. otherwise `local`.

`detect()` returns the profile AND what decided it — `AGENTTOOLING_PROFILE`,
`CLAUDE_CODE_REMOTE` or `default`, the three values env-profile.sh's PROFILE_DECIDED_BY
has always held.

Two callers, two ways in:

  - hooks/allow-repo-commands.sh IMPORTS it in-process, as a sibling, the way it imports
    policy.py — no extra process per Bash call:

        sys.dont_write_bytecode = True
        sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
        import env_profile

  - env-profile.sh RUNS it once when sourced (`python3 -B <agentTooling>/hooks/env_profile.py`)
    and reads two lines from stdout: the profile, then the decider. For an invalid
    override it prints the raw value and `AGENTTOOLING_PROFILE` and exits
    INVALID_PROFILE_RC, with the reason on stderr, so env-profile.sh's profile_check
    refuses it by name exactly as it always did.

Standard library only, and no I/O beyond reading the environment it is handed (or the
process's own when handed none) — and, run as a script, writing those two lines.
"""

import collections
import os
import sys

# The two variables, spelled here and nowhere else in the lifecycle's code
PROFILE_ENV = "AGENTTOOLING_PROFILE"
REMOTE_ENV = "CLAUDE_CODE_REMOTE"

# The two profiles
PROFILE_LOCAL = "local"
PROFILE_CLOUD = "cloud"
PROFILES = (PROFILE_LOCAL, PROFILE_CLOUD)

# The value of CLAUDE_CODE_REMOTE that means "this is a Claude Code cloud container"
REMOTE_ON = "true"

# What decided the profile: the variable's own name, or this when neither did
DECIDED_BY_OVERRIDE = PROFILE_ENV
DECIDED_BY_REMOTE = REMOTE_ENV
DECIDED_BY_DEFAULT = "default"

# Run as a script: the exit code for an invalid override (0 otherwise)
INVALID_PROFILE_RC = 2

Detection = collections.namedtuple("Detection", ["profile", "decided_by"])


class InvalidProfile(ValueError):
    """An explicit AGENTTOOLING_PROFILE that is neither profile. `value` is what it held."""

    def __init__(self, value):
        self.value = value
        super().__init__("%s=%r is neither %s nor %s — unset it to detect the profile, or "
                         "set one of the two" % (PROFILE_ENV, value, PROFILE_LOCAL,
                                                 PROFILE_CLOUD))


def detect(environ=None):
    """The rule above over `environ` (the process environment when None): a Detection
    `(profile, decided_by)`. Raises InvalidProfile for an override that is neither."""
    if environ is None:
        environ = os.environ
    override = environ.get(PROFILE_ENV) or ""
    if override:
        if override not in PROFILES:
            raise InvalidProfile(override)
        return Detection(override, DECIDED_BY_OVERRIDE)
    if environ.get(REMOTE_ENV) == REMOTE_ON:
        return Detection(PROFILE_CLOUD, DECIDED_BY_REMOTE)
    return Detection(PROFILE_LOCAL, DECIDED_BY_DEFAULT)


def is_cloud(environ=None):
    """True only when the rule decides `cloud`. An invalid override is NOT cloud: a caller
    asking this yes/no question falls back to today's local answers on a value nobody can
    read, and one that must refuse it calls detect() itself."""
    try:
        return detect(environ).profile == PROFILE_CLOUD
    except InvalidProfile:
        return False


def main():
    try:
        detection = detect()
    except InvalidProfile as exc:
        sys.stdout.write("%s\n%s\n" % (exc.value, DECIDED_BY_OVERRIDE))
        sys.stderr.write("env_profile: %s\n" % exc)
        return INVALID_PROFILE_RC
    sys.stdout.write("%s\n%s\n" % detection)
    return 0


if __name__ == "__main__":
    sys.exit(main())
