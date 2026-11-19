#!/usr/bin/env python3
"""The orchestrator-role rule, written once.

An orchestrator session spawns one implementer session per feature and builds nothing
itself (`LIFECYCLE.md` → "Orchestrator and implementer sessions"). The record it opens with
`orchestration-start.sh` — `<tooling>/self/orchestrations/<slug>/README.md` (agentTooling's
own, or a consumer's legacy one) or the consuming repo's `plans/orchestrations/<slug>/
README.md`, whose LAST ```json fence carries the session id as `session` — IS the role: a
session whose id is some record's `session` is an orchestrator, and nothing it runs may
build a feature. (The role reads every fence of the file, not only the last, and every
source — working tree, history, ledger — over both roots; see below.)

Two callers ask the same question and must never answer it differently, so the rule lives
here and nowhere else:

  * `plan-runner-roots.sh` — `orchestrator_record_for_session` / `refuse_orchestrator_session`,
    which every lifecycle script that builds calls before it writes anything;
  * `allow-repo-commands.sh` — the PreToolUse hook, which denies a build script in a Bash
    command and an implementer delegate in an `Agent` call with the same reason, as early
    feedback (the scripts are the enforcement; the hook only names the remedy sooner).

    python3 -B hooks/orchestrator_role.py [--reason] -- <tooling-dir> <session-id>

prints the record's path (with `--reason`, the refusal's reason text) or nothing, and exits 0:
an empty session id, a missing records root, an unreadable file and an unparseable fence are
each "no record", never an error. A rule that RAISES exits RULE_FAILED, and an import that
fails (a missing `shared_rules.py`) exits non-zero too; `plan-runner-roots.sh` refuses the
build on either, naming the module, rather than reading a broken install as no record. Stdlib only, so the hook can import
it as a sibling and a fixture that copies the file needs nothing else.

A **coordinator record** — a fence carrying `"kind": "coordinator"`
(`orchestration-start.sh --coordinator`, self/features/coordinator-cost-records/) — is NOT a
role and is skipped here. It names a session only so that session's own transcript can be
priced on a line of its own. A coordinator's delegates run in its session: a subagent's hook
payload carries the PARENT's `session_id`, and its Bash inherits the parent's
`$CLAUDE_CODE_SESSION_ID`, so a role keyed on that id would refuse every feature its
delegates start, build and close. Only a record with no `kind` (or any other value) is an
orchestrator's.

**The exemption is earned by shape, not by the word alone** (self/features/hook-role-hardening/,
F1). The record is a file its own orchestrator can Edit, so one added `"kind": "coordinator"`
— or a later fence appended below the real one — used to drop the role. Two readings close
that, and `analysis/manifest.py --orchestration` keeps a genuine coordinator record on the
right side of both:

  * a fence saying `coordinator` whose `features[]` holds an entry with a non-null `session`
    or `branch` is still a role: that is the orchestrator's `add-feature` shape (it records
    each implementer's session and branch), while a coordinator's entries carry `pr` and
    `report` with `session`/`branch` null — and `add-feature`/`set-feature` refuse to write
    either into a coordinator record;
  * EVERY ```json fence of the file is read, not only the last: a record any of whose fences
    names the session as a role is a role, so an appended `{}` or coordinator fence cannot
    shadow the one `orchestration-start.sh` wrote.

What neither reading can see is an in-place rewrite of the one fence (the `session` changed,
or `kind` added to a record with no features yet). Two things cover it. The `ask` rule
`hooks/wire-settings.py` writes over a consuming repo's records folder puts the Edit in
front of a human. And `orchestration-start.sh` also appends `<session> <slug>` to a LEDGER
in the checkout's git common directory (`LEDGER_NAME`) for every orchestrator record it
writes — never a coordinator one. The Edit tool cannot write under `.git/` in any
permission mode (wire-settings.py's `Edit(**/.git/**)` deny), and a shell write there is a
command the hook hands to a human, so a session the ledger names stays an orchestrator
whatever its record now says: `record_for_session` falls back to it, naming the record the
ledger's slug points at. The ledger is local to the clone, a belt to the record's braces.
"""

import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True

# The rules this one shares with analysis/ and the lifecycle scripts, defined once in
# shared_rules.py (self/features/shared-hook-rules/) and bound here by name. Unguarded: the
# two files ship as one directory, and the hook's own guarded import of THIS module is what
# turns a missing or broken shared_rules.py into a silent role rule.
import shared_rules  # noqa: E402

# Where records live: relative to the tooling directory (agentTooling's own, and the old
# vendored home of a consumer's) and relative to its parent, the consuming repo's root
ORCHESTRATIONS_SELF_REL = shared_rules.ORCHESTRATIONS_SELF_REL
ORCHESTRATIONS_CONSUMER_REL = shared_rules.ORCHESTRATIONS_CONSUMER_REL
RECORD_NAME = shared_rules.RECORD_NAME
# A tooling directory holding this entry (a directory in a clone, a file in a linked worktree)
# is a standalone checkout, not a copy vendored into a consuming repo.
GIT_ENTRY = shared_rules.GIT_ENTRY
# The fence key that makes a session an orchestrator
SESSION_KEY = shared_rules.SESSION_KEY
# The fence key and value that mark a coordinator record: a cost record, never a role.
KIND_KEY = shared_rules.KIND_KEY
KIND_COORDINATOR = shared_rules.KIND_COORDINATOR
# The orchestrator's shape: `features[]` entries recording the implementer's session or
# branch. A coordinator's entries leave both null, and analysis/manifest.py refuses to set
# them on one.
FEATURES_KEY = shared_rules.FEATURES_KEY
ORCHESTRATOR_FEATURE_KEYS = shared_rules.ORCHESTRATOR_FEATURE_KEYS
# A record's JSON fences, the way plan-runner-roots.sh's manifest_field and the hook's
# manifest reader find them. Readers of the record's DATA take the LAST fence; the role
# reads every one (all_fences), so an appended fence cannot shadow the real one.
FENCE_OPEN_RE = re.compile(r"^```json[ \t]*$")
FENCE_CLOSE_RE = re.compile(r"^```[ \t]*$")
# The local ledger of orchestrator sessions, under the checkout's git common directory.
# orchestration-start.sh writes it (reading the name from shared_rules). One `<session> <slug>`
# per line.
LEDGER_NAME = shared_rules.LEDGER_NAME
LEDGER_SLUG_RE = shared_rules.SLUG_RE
# A ledger line naming the session with no usable slug is still the role, under this name
LEDGER_UNKNOWN_SLUG = "unknown"
# What record_for_session returns, and the reason refusal_reason renders, when a checkout is
# there and its ledger cannot be read — the fail-closed answer (round 1, F12)
LEDGER_UNREADABLE = "<the orchestrator ledger could not be read>"
LEDGER_UNREADABLE_REASON = (
    "this checkout's orchestrator ledger (`.git/%s`) or the git history of its "
    "orchestration records could not be read — a `.git` that does not resolve, a ledger that "
    "is not a readable file, or git itself unavailable — so no session can be shown not to "
    "be an orchestrator, and building is refused (ordinary commands are not); repair the "
    "checkout, then run this again" % LEDGER_NAME)
# How git marks a checkout, read without running git: `.git` (a directory, or a file naming
# `gitdir: <dir>`), and a linked worktree's `commondir`
GIT_MARKER = GIT_ENTRY
GIT_HEAD_NAME = "HEAD"
# The history source runs git, bounded: one `git log -p` under one deadline (round 3, R6)
GIT_TIMEOUT_SECONDS = 5
HISTORY_DEADLINE_SECONDS = 3
SHALLOW_NAME = "shallow"
DIFF_HEADER = "diff --git "
NEW_FILE_PREFIX = "+++ b/"
GITDIR_PREFIX = shared_rules.GITDIR_PREFIX
COMMONDIR_NAME = shared_rules.COMMONDIR_NAME
# CLI: after this, every word is positional
END_OF_OPTIONS = "--"
# The one reason, rendered from a constant template. The brief it names is the remedy's
# source: a child session is briefed from it, never from this one.
IMPLEMENTER_BRIEF = "templates/plans/ORCHESTRATOR_BRIEF.md"
REASON_TEMPLATE = (
    "this session is the orchestrator of `%(slug)s` (`%(record)s`): a feature is built in a "
    "session of its own — create one with the implementer brief (`%(brief)s`) and never "
    "run this here")
# CLI
REASON_FLAG = "--reason"
CLI_MIN_ARGS = 2
OK = 0
# A rule that raised: the shell reader refuses the build on it, naming this module, rather
# than reading a broken install as "no record" (self/features/hook-silent-allow-sweep/, item 7)
RULE_FAILED = 3


def fence_bodies(path):
    """The text of every closed ```json fence of `path`, in file order; [] for an
    unreadable file."""
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return []
    return fence_bodies_of_lines(lines)


def fence_bodies_of_lines(lines):
    """The text of every closed ```json fence in `lines`, in order."""
    bodies, buffer, inside = [], [], False
    for line in lines:
        if FENCE_OPEN_RE.match(line):
            buffer, inside = [], True
        elif FENCE_CLOSE_RE.match(line):
            if inside:
                bodies.append("\n".join(buffer))
            inside = False
        elif inside:
            buffer.append(line)
    return bodies


def parse_fence(body):
    """A fence body as a dict, or None when it is empty, unparseable or not an object."""
    try:
        fence = json.loads(body) if body else None
    except ValueError:
        return None
    return fence if isinstance(fence, dict) else None


def all_fences(path):
    """Every ```json fence of `path` that parses to an object, in file order."""
    return [fence for fence in map(parse_fence, fence_bodies(path)) if fence is not None]


def orchestrator_shaped(fence):
    """True when some `features[]` entry carries a non-null `session` or `branch` — what
    the orchestrator's `add-feature` records, and what no coordinator record holds."""
    features = fence.get(FEATURES_KEY)
    if not isinstance(features, list):
        return False
    return any(isinstance(entry, dict) and
               any(entry.get(key) is not None for key in ORCHESTRATOR_FEATURE_KEYS)
               for entry in features)


def is_role(fence):
    """True for an orchestrator's record; False only for a coordinator record (`kind:
    coordinator`) that has a coordinator's shape — one with an orchestrator's features is a
    role whatever its `kind` says."""
    return fence.get(KIND_KEY) != KIND_COORDINATOR or orchestrator_shaped(fence)


def names_role(path, session_id):
    """True when ANY fence of the record at `path` names `session_id` and is a role."""
    return any(fence.get(SESSION_KEY) == session_id and is_role(fence)
               for fence in all_fences(path))


def record_roots(tooling_dir):
    """The directories a record can sit in, self first: `<tooling_dir>/self/orchestrations`
    (agentTooling's own records, and the old home of a consumer's) and the consuming repo's
    `plans/orchestrations`, the repo being the parent of `tooling_dir` — but only from a vendored
    copy: a tooling directory with a `.git` of its own is agentTooling's standalone checkout, whose
    parent is no repository, so a directory there can never give a session a role."""
    return [os.path.join(base, *rel.split("/")) for base, rel in record_bases(tooling_dir)]


def record_bases(tooling_dir):
    """`record_roots` as `(base directory, relative root)` pairs — the form the history source
    runs git with (`git -C <base> log --relative -- <rel>`), so the consuming repo's records are
    read from the consuming repo's directory, never through a `..` path."""
    tooling_dir = os.path.normpath(tooling_dir)
    bases = [(tooling_dir, ORCHESTRATIONS_SELF_REL)]
    if not os.path.exists(os.path.join(tooling_dir, GIT_ENTRY)):
        bases.append((os.path.dirname(tooling_dir) or os.curdir, ORCHESTRATIONS_CONSUMER_REL))
    return bases


def record_for_session(tooling_dir, session_id):
    """The path of the record — `<tooling_dir>/self/orchestrations/<slug>/README.md` or, from
    a vendored copy, the consuming repo's `plans/orchestrations/<slug>/README.md`
    (`record_roots`) — that makes `session_id` an orchestrator, else None. Three sources,
    unioned, the first that answers winning, each over every root (self first): the working
    tree's records (`names_role`, each root's folders in sorted order); each record AS FIRST
    COMMITTED (`committed_role_record`: the role reaches every clone, and a later edit or
    deletion in the working tree does not drop it); and the ledger of every enclosing git
    directory (`ledger_lookup`, the same-machine guard for a record not yet committed).
    LEDGER_UNREADABLE when the git metadata a source needs cannot be read — fail closed
    (hook-role-hardening NOTES.md, rounds 1–2)."""
    if not isinstance(session_id, str) or not session_id:
        return None
    roots = record_roots(tooling_dir)
    for root in roots:
        try:
            slugs = sorted(os.listdir(root))
        except OSError:  # no records to read is no reason to skip the others (round 1, F11)
            slugs = []
        for slug in slugs:
            path = os.path.join(root, slug, RECORD_NAME)
            if names_role(path, session_id):
                return path
    # Every source is asked: one that names the session wins whatever another could not
    # read, and LEDGER_UNREADABLE is the answer only when none names it and some source
    # could not be read (round 3, R4: an unreadable history used to hide the ledger).
    unreadable = False
    found = committed_role_record(tooling_dir, session_id)
    if found == LEDGER_UNREADABLE:
        unreadable = True
    elif found:
        return found
    slug = ledger_lookup(tooling_dir, session_id)
    if slug == LEDGER_UNREADABLE:
        unreadable = True
    elif slug:
        return ledger_record_path(roots, slug)
    return LEDGER_UNREADABLE if unreadable else None


def ledger_record_path(roots, slug):
    """Where the record a ledger line names sits: the first root holding `<slug>/`, else the
    last root (the consuming repo's from a vendored copy, where `orchestration-start.sh`
    writes by default; `self/orchestrations` in a standalone checkout). The ledger carries a
    slug, not a root; the path only names the record in the refusal."""
    for root in roots:
        if os.path.isdir(os.path.join(root, slug)):
            return os.path.join(root, slug, RECORD_NAME)
    return os.path.join(roots[-1], slug, RECORD_NAME)


def resolve_git_marker(here):
    """The common git directory a `.git` in `here` stands for, or None when it cannot be
    resolved: a directory must hold `HEAD` (round 2, N12: a stray empty `.git/` is no
    checkout), a file must name `gitdir: <dir>` that exists, and a linked worktree's
    `commondir` must name a directory."""
    marker = os.path.join(here, GIT_MARKER)
    if os.path.isdir(marker):
        gitdir = marker
        if not os.path.isfile(os.path.join(gitdir, GIT_HEAD_NAME)):
            return None
    else:
        try:
            with open(marker, encoding="utf-8", errors="replace") as handle:
                line = handle.readline().strip()
        except OSError:
            return None
        if not line.startswith(GITDIR_PREFIX):
            return None
        gitdir = line[len(GITDIR_PREFIX):].strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(here, gitdir)
        if not os.path.isfile(os.path.join(gitdir, GIT_HEAD_NAME)):
            return None
    try:
        with open(os.path.join(gitdir, COMMONDIR_NAME), encoding="utf-8", errors="replace") as handle:
            common = handle.readline().strip()
    except FileNotFoundError:
        return os.path.normpath(gitdir)
    except OSError:
        return None
    common = common if os.path.isabs(common) else os.path.join(gitdir, common)
    return os.path.normpath(common) if os.path.isdir(common) else None


def git_common_dirs(tooling_dir):
    """Every enclosing checkout's common git directory, nearest first, found the way git finds
    one but without running git (round 1, F12) and without stopping at the first (round 2,
    N12: a vendored copy sits in the consuming repo's checkout, and a nested `.git` must not
    hide the ledger above it). None in the list stands for a `.git` that cannot be resolved."""
    found, here = [], os.path.abspath(tooling_dir)
    while True:
        if os.path.lexists(os.path.join(here, GIT_MARKER)):
            found.append(resolve_git_marker(here))
        parent = os.path.dirname(here)
        if parent == here:
            return found
        here = parent


def ledger_lookup(tooling_dir, session_id):
    """The slug of the first line of any enclosing checkout's ledger whose first word is
    `session_id` exactly (a slug that is not one reads as LEDGER_UNKNOWN_SLUG: still the
    role); None when no ledger names it, or there is no checkout or no ledger file; or
    LEDGER_UNREADABLE when a `.git` is there that cannot be resolved, or a ledger that cannot
    be read. That case FAILS CLOSED (NOTES.md): the role of every session is unknown, and it
    denies only what the role denies — build scripts and implementer briefs — never an
    ordinary command. Read line by line with undecodable bytes replaced."""
    if not isinstance(session_id, str) or not session_id:
        return None
    for common in git_common_dirs(tooling_dir):
        if common is None:
            return LEDGER_UNREADABLE
        try:
            with open(os.path.join(common, LEDGER_NAME), encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    parts = line.split()
                    if parts and parts[0] == session_id:
                        slug = parts[1] if len(parts) > 1 and LEDGER_SLUG_RE.match(parts[1]) else None
                        return slug or LEDGER_UNKNOWN_SLUG
        except FileNotFoundError:
            continue
        except OSError:
            return LEDGER_UNREADABLE
    return None


def git_output(tooling_dir, args, timeout):
    """stdout of `git -C <tooling_dir> <args>` within `timeout` seconds, or None when git
    cannot be run, fails or runs out of time."""
    try:
        done = subprocess.run(["git", "-C", tooling_dir] + list(args), capture_output=True,
                              text=True, errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout if done.returncode == 0 else None


def shallow_commits(tooling_dir):
    """The commits a shallow clone's history stops at (`<common dir>/shallow`), as a set."""
    found = set()
    for common in git_common_dirs(tooling_dir):
        if not common:
            continue
        try:
            with open(os.path.join(common, SHALLOW_NAME), encoding="utf-8", errors="replace") as handle:
                found.update(line.strip() for line in handle if line.strip())
        except OSError:
            continue
    return found


def added_records(base_dir, rel=ORCHESTRATIONS_SELF_REL):
    """[(slug, commit, lines)] — each record README under `<base_dir>/<rel>` as the commit that
    ADDED it wrote it, from ONE bounded git call per root (round 3, R6): `git -C <base_dir> log
    -m --relative --diff-filter=A -p -- <rel>`, merges diffed against each parent so a record
    added only in a merge is seen (R5), the run under HISTORY_DEADLINE_SECONDS. None when the
    history cannot be read in time. A commit at a shallow clone's boundary only APPEARS to add
    every file, so it is never taken as the add (R5); see committed_role_record for what that
    leaves."""
    output = git_output(base_dir, ["log", "-m", "--relative", "--diff-filter=A", "--no-color",
                                   "--no-ext-diff", "--no-textconv", "--format=%x00%H", "-p",
                                   "--", rel], HISTORY_DEADLINE_SECONDS)
    if output is None:
        return None
    depth = len(rel.split("/")) + 2
    records, commit, path, lines = [], None, None, None

    def close():
        if path is not None and lines is not None:
            parts = path.split("/")
            if len(parts) == depth and parts[-1] == RECORD_NAME:
                records.append((parts[-2], commit, lines))

    for line in output.split("\n"):
        if line.startswith("\0"):
            close()
            commit, path, lines = line[1:].strip(), None, None
        elif line.startswith(DIFF_HEADER):
            close()
            path, lines = None, None
        elif line.startswith(NEW_FILE_PREFIX) and path is None:
            path, lines = line[len(NEW_FILE_PREFIX):], []
        elif lines is not None and line.startswith("+"):
            lines.append(line[1:])
    close()
    return records


def committed_role_record(tooling_dir, session_id):
    """The path of a record, in any of `record_bases`' roots (self first), that names
    `session_id` as a role in the commit that ADDED it, whatever the working tree says now;
    None when no such record was ever committed, or there is no checkout. LEDGER_UNREADABLE
    when a checkout is there but a root's history cannot be read in time — git off PATH,
    failing, or past the deadline — and no root names the session, which record_for_session
    weighs against the other sources (R4). A record whose only add is a shallow clone's
    boundary is skipped, not failed closed: a shallow clone (a cloud session's default) would
    otherwise refuse building to every session; the working tree and the ledger still answer
    for it (hook-role-hardening NOTES.md, round 3)."""
    if not any(git_common_dirs(tooling_dir)):
        return LEDGER_UNREADABLE if git_common_dirs(tooling_dir) else None
    boundary, unreadable = None, False
    for base, rel in record_bases(tooling_dir):
        records = added_records(base, rel)
        if records is None:
            # A checkout with no commit yet has no history to read, which is no failure
            if git_output(base, ["rev-parse", "--git-dir"], GIT_TIMEOUT_SECONDS) is not None and \
                    git_output(base, ["rev-parse", "-q", "--verify", "HEAD"], GIT_TIMEOUT_SECONDS) is None:
                continue
            unreadable = True
            continue
        if boundary is None:
            boundary = shallow_commits(tooling_dir)
        for slug, commit, lines in records:
            if commit in boundary:
                continue
            for body in fence_bodies_of_lines(lines):
                fence = parse_fence(body)
                if fence is not None and fence.get(SESSION_KEY) == session_id and is_role(fence):
                    return os.path.join(base, *rel.split("/"), slug, RECORD_NAME)
    return LEDGER_UNREADABLE if unreadable else None


def refusal_reason(record_path):
    """The reason text for the record at `record_path`; the slug is its folder's name."""
    if record_path == LEDGER_UNREADABLE:
        return LEDGER_UNREADABLE_REASON
    slug = os.path.basename(os.path.dirname(record_path))
    return REASON_TEMPLATE % {"slug": slug, "record": record_path, "brief": IMPLEMENTER_BRIEF}


def main(argv):
    """`[--reason] [--] <tooling-dir> <session-id>`. After `--` every word is positional, so
    a session id that starts with a dash is never read as the flag (round 1, F13); without
    `--` the old form, the flag filtered out wherever it stands, still works."""
    if END_OF_OPTIONS in argv:
        at = argv.index(END_OF_OPTIONS)
        flags, args = argv[:at], argv[at + 1:]
    else:
        flags, args = argv, [a for a in argv if a != REASON_FLAG]
    if len(args) < CLI_MIN_ARGS:
        return OK
    try:
        record = record_for_session(args[0], args[1])
    except Exception:  # a rule that raised is RULE_FAILED: the shell reader refuses on it
        return RULE_FAILED
    if record:
        print(refusal_reason(record) if REASON_FLAG in flags else record)
    return OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
