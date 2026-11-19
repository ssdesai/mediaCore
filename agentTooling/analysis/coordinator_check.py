#!/usr/bin/env python3
"""Name a coordinator whose own cost no record claims.

    python3 -B agentTooling/analysis/coordinator_check.py <session-id> <checkout-dir> [--self]

`--self` (feature-start.sh passes it for a `--self` start) makes the advisory's command
`orchestration-start.sh --self <slug> …`, agentTooling's own record — in agentTooling's own
checkout only: from a copy vendored in a consuming repo that start is refused
(`roots.self_record_write_allowed`; self/features/consumer-record-guard/), so there, as
without `--self`, the command names no flag, the consuming repo's.

`feature-start.sh` runs this under the cloud profile, where every session that runs a start
is taken to be the feature's coordinator, claimed by the feature's branch. That holds for a
session working IN the checkout. It does not hold for a session coordinating several
features from somewhere else — a Claude Code cloud session with several repositories starts
in their parent directory, outside every checkout — whose delegates run the starts: they
share its session id (`$CLAUDE_CODE_SESSION_ID`), so the start names it, but its transcript
records that other directory's branch (`HEAD` outside any repository), which no feature
selects. Its delegates are claimed by their brief headers; its own transcript is claimed by
nothing (self/features/coordinator-cost-records/).

Prints one `warn` line, without the `  warn      ` prefix the caller adds, when ALL hold:

  * a transcript for the session is found (`routing.find_transcript`);
  * the first `cwd` it records lies outside the checkout `<checkout-dir>` sits in
    (`roots.checkout_of`, compared resolved);
  * no orchestration record of either kind names the session (`self/orchestrations/*/
    README.md` or the consuming repo's `plans/orchestrations/*/README.md`, the last
    fence's `session`).

and a second line when that `cwd` lies in no git checkout at all: no repository's
`.claude/settings.json` loaded there, so the session ran under no repository's hooks.
Prints nothing otherwise, and exits 0 always — an advisory, never a refusal: a missing
transcript, an unreadable record and any error are each silence.
"""

import json
import sys
from pathlib import Path

from roots import all_orchestrations_roots, checkout_of, self_record_write_allowed, shared_rules
from routing import find_transcript, parse_manifest

OK = 0
CLI_MIN_ARGS = 2
CWD_KEY = "cwd"
SESSION_KEY = shared_rules.SESSION_KEY
RECORD_NAME = shared_rules.RECORD_NAME
UNCLAIMED_TEMPLATE = (
    "session {session} works from {cwd}, outside this checkout, so this feature's branch "
    "does not claim its own transcript and no record does: if it coordinates several "
    "features, record its cost on a line of its own with orchestration-start.sh {flag}<slug> "
    "--coordinator --session {session} (ORCHESTRATION.md → \"Coordinator shapes\")"
)
# The flag the advisory's command carries: `--self ` for a `--self` start (agentTooling's own
# record), none otherwise. feature-start.sh hands the mode over as a third argument.
SELF_ARG = "--self"
SELF_FLAG_WORDING = SELF_ARG + " "
NO_FLAG_WORDING = ""
NO_CHECKOUT_TEMPLATE = (
    "{cwd} is in no git checkout, so that session runs under no repository's hooks "
    "(allow-repo-commands.sh, session-start.sh) and records branch HEAD: start a "
    "coordinator inside a repository checkout"
)


def first_cwd(path):
    """The first `cwd` a transcript records, read line by line so a large transcript is
    not loaded whole; None when no line carries one."""
    try:
        with open(path, "r") as handle:
            for raw in handle:
                raw = raw.strip()
                if not raw or CWD_KEY not in raw:
                    continue
                try:
                    line = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                cwd = line.get(CWD_KEY) if isinstance(line, dict) else None
                if isinstance(cwd, str) and cwd:
                    return cwd
    except OSError:
        return None
    return None


def recorded(session_id):
    """True when any orchestration record — orchestrator's or coordinator's, in either
    root — names the session as its `session`."""
    for root in all_orchestrations_roots():
        if not root.is_dir():
            continue
        for readme in sorted(root.glob("*/" + RECORD_NAME)):
            try:
                if parse_manifest(readme).get(SESSION_KEY) == session_id:
                    return True
            except Exception:  # an unreadable record names nobody
                continue
    return False


def same_checkout(a, b):
    return a is not None and b is not None and Path(a).resolve() == Path(b).resolve()


def warnings_for(session_id, checkout_dir, self_mode=False):
    """The lines to print, as a list (empty for none). `self_mode` is the start's `--self`:
    the advisory's `orchestration-start.sh` command then carries it, where that start may
    write (not from a vendored copy)."""
    if not session_id:
        return []
    transcript = find_transcript(session_id)
    if transcript is None:
        return []
    cwd = first_cwd(transcript)
    if cwd is None:
        return []
    session_checkout = checkout_of(cwd)
    if same_checkout(session_checkout, checkout_of(checkout_dir)):
        return []
    if recorded(session_id):
        return []
    # `--self` only where the start would write it: from a vendored copy it is refused
    # (roots.self_record_write_allowed; self/features/consumer-record-guard/)
    flag = SELF_FLAG_WORDING if self_mode and self_record_write_allowed() else NO_FLAG_WORDING
    lines = [UNCLAIMED_TEMPLATE.format(session=session_id, cwd=cwd, flag=flag)]
    if session_checkout is None:
        lines.append(NO_CHECKOUT_TEMPLATE.format(cwd=cwd))
    return lines


def main(argv):
    if len(argv) < CLI_MIN_ARGS:
        return OK
    try:
        self_mode = SELF_ARG in argv[CLI_MIN_ARGS:]
        for line in warnings_for(argv[0], argv[1], self_mode):
            print(line)
    except Exception:  # advisory: never a failure
        pass
    return OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
