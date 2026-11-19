"""Root resolution shared by the analysis scripts.

Three root-like facts, identical in an ordinary run and divergent under --self:

  artifact root     where feature directories live and results are written
  session root      the cwd Claude Code sessions ran from, which is what the
                    directory names under ~/.claude/projects/ encode
  corpus identity   which repo a corpus's features BELONG to — the `repo` half of
                    the `(repo, slug)` key the claims ledger and the session share
                    split dedupe on

Ordinary run: both roots are the consuming repo root, two levels above this file, and
that repo's own origin is the identity of the corpus under it.

--self: artifacts belong to the agentTooling checkout one level up, but planning
sessions still ran from the enclosing repo, so the session root is the nearest
ancestor holding .git. That is the consuming repo when agentTooling is vendored as a
subtree, and agentTooling itself in a standalone clone — one rule covering both, and
the reason nothing here takes a repo path argument. When that ancestor is a linked
worktree (a feature's `<primary>/.worktrees/<slug>`), the session root is the primary
checkout it belongs to, so a worktree's copy resolves what the primary's copy does.

The self corpus's identity, though, is DECLARED rather than derived, because neither
root can be asked for it: `self/features` can only ever belong to agentTooling, and a
copy vendored into a consumer has no .git of its own, so asking git about it answers
with the consumer's origin and files every agentTooling feature under a repo it does
not belong to. See SELF_CORPUS_IDENTITY below.
"""

import sys
from pathlib import Path

AGENT_TOOLING_DIR = Path(__file__).resolve().parents[1]

# The rules the PreToolUse hook shares with this directory (record roots, fence keys, the
# two refusal texts, how git marks a checkout) have one definition, `hooks/shared_rules.py`
# (self/features/shared-hook-rules/). The hook may not import `analysis/`, so it lives on the
# hook's side and is reached here by path — appended, so nothing in `hooks/` can shadow a
# module of this directory, as `capture_planning.py` reaches `brief_header.py`. Unguarded: a
# missing definition is an ImportError and the tool writes nothing, never a rule read another way.
HOOKS_DIR = AGENT_TOOLING_DIR / "hooks"
if str(HOOKS_DIR) not in sys.path:
    sys.path.append(str(HOOKS_DIR))
import shared_rules  # noqa: E402

# Who agentTooling's own corpus belongs to, stated rather than derived. `self/features`
# can only ever belong to agentTooling, and the vendored copy has no `.git` to ask —
# `git -C <consumer>/agentTooling remote get-url origin` walks up and answers with the
# CONSUMER's origin, which puts every self-corpus feature in the consumer's claim set
# under a `<consumer>/<slug>` name that names no feature. `capture_planning.corpus_identity`
# is the one place that reads this.
#
# The same URL is `update.sh`'s DEFAULT_REMOTE and the remote `README.md` -> "Updating"
# names in its `git subtree` commands; all three have to move together.
SELF_CORPUS_IDENTITY = "https://github.com/ssdesai/agentTooling.git"

# How a linked worktree points home (`worktree_primary`). Its `.git` is a file holding one
# line, `gitdir: <path>` — `<common git dir>/worktrees/<name>`, absolute unless
# `worktree.useRelativePaths` wrote it relative to the worktree — and that per-worktree
# directory holds `commondir`, the path of the common git dir relative to itself. A
# submodule's `.git` file points into `<super>/.git/modules/<name>`, which has no
# `commondir`, and is left as the root it always was.
GIT_ENTRY = shared_rules.GIT_ENTRY
GITDIR_PREFIX = shared_rules.GITDIR_PREFIX
COMMONDIR_FILE = shared_rules.COMMONDIR_NAME

# A feature MENTION is the display string `<repo_name>/<slug>` a record's
# `also_claimed_by` and `share_basis[].feature` carry. Its repo half is a display name,
# and two captures of one repo can spell it differently by case: a Claude Code cloud
# container clones from a lowercase origin URL (`https://github.com/ssdesai/musicmap`), so
# its captures write `musicmap/<slug>` where a laptop's wrote `musicMap/<slug>`
# (self/features/cloud-pull-fixes/, defect C). GitHub repo names are case-insensitive, so
# the two are one feature. The slug half is compared exactly — slugs are lowercase by rule.
FEATURE_MENTION_SEPARATOR = "/"


def feature_mention_key(mention):
    """What two mentions are compared by: `(repo_name.lower(), slug)`. A mention with no
    separator is its own key, lowercased, so it can never merge with a real one."""
    repo_name, sep, slug = str(mention).rpartition(FEATURE_MENTION_SEPARATOR)
    if not sep:
        return (str(mention).lower(), None)
    return (repo_name.lower(), slug)


def preferred_mention(spellings):
    """The one spelling to keep among mentions that differ only in repo-name case: any
    spelling that is not all lowercase beats one that is — case is only ever LOST (a
    lowercase clone, a case-folding tool), never invented — and ties go to the smallest
    string, so the answer depends on the set and never on the order it was read in."""
    return min(spellings, key=lambda s: (s == s.lower(), s))


def collapse_feature_mentions(mentions):
    """`mentions` with every group that differs only in repo-name case collapsed to its
    `preferred_mention`, sorted. Deterministic in the SET of spellings, so a refresh that
    runs it twice over the same inputs writes the same list both times."""
    groups = {}
    for mention in mentions:
        groups.setdefault(feature_mention_key(mention), set()).add(mention)
    return sorted(preferred_mention(spellings) for spellings in groups.values())


def add_self_flag(parser):
    """Register --self, worded identically across the three scripts."""
    parser.add_argument(
        "--self",
        dest="self_mode",
        action="store_true",
        help="operate on agentTooling's own corpus (self/features/) rather than "
        "the consuming repo's (plans/features/)",
    )


# Measuring is the driver's, building is the arm's. The experiment harness runs these
# scripts from the DRIVER's own copy (current rates, current capture rules) over a
# worktree whose vendored agentTooling/ may be months old; `--arm-root <worktree>` points
# the ordinary (non---self) artifact root at that worktree, so its `plans/features/` is
# read and written while the code that prices it is the driver's. Process-wide, set once
# by `apply_arm_root` before anything resolves a root.
_arm_root = None


def add_arm_root_flag(parser):
    """Register --arm-root on a script that prices or reports a feature."""
    parser.add_argument(
        "--arm-root",
        dest="arm_root",
        metavar="DIR",
        help="read and write plans/features/ under this checkout instead of the one "
        "this copy of the scripts is vendored in (the experiment harness's driver "
        "measuring an arm's worktree). Not with --self",
    )


def apply_arm_root(parser, args):
    """Make `--arm-root` the ordinary artifact root; a usage error with --self."""
    global _arm_root
    if not getattr(args, "arm_root", None):
        return
    if args.self_mode:
        parser.error("--arm-root is for a consuming repo's corpus, not --self")
    arm = Path(args.arm_root).resolve()
    if not arm.is_dir():
        parser.error(f"--arm-root {args.arm_root!r} is not a directory")
    _arm_root = arm


def artifact_root(self_mode):
    """Where feature directories live and results are written."""
    if self_mode:
        return AGENT_TOOLING_DIR
    return _arm_root or AGENT_TOOLING_DIR.parent


def features_root(self_mode):
    """The per-feature tree under the artifact root."""
    if self_mode:
        return AGENT_TOOLING_DIR / "self" / "features"
    return artifact_root(False) / "plans" / "features"


# Where orchestration records live, per mode (self/features/orchestration-records-in-repo/).
# A record belongs to the checkout it was started in, as a feature does. The roots, and the
# two refusal texts below, are shared_rules' (the hook and orchestration-start.sh read the
# same values); the *_PARTS are those roots split for `Path.joinpath`.
ORCHESTRATIONS_SELF_PARTS = tuple(shared_rules.ORCHESTRATIONS_SELF_REL.split("/"))
ORCHESTRATIONS_CONSUMER_PARTS = tuple(shared_rules.ORCHESTRATIONS_CONSUMER_REL.split("/"))
# The old home of a consuming repo's records: inside the vendored agentTooling/, as seen
# from the consumer. A record there is moved, never read in place.
LEGACY_RECORD_MOVE = shared_rules.LEGACY_RECORD_MOVE
LEGACY_RECORD_REFUSAL = shared_rules.LEGACY_RECORD_REFUSAL
# A vendored record that is NOT stranded is agentTooling's own, shipped with the subtree
# (a consumer's `agentTooling/self/orchestrations/` always holds them): never moved.
OWN_RECORD_NOTE = (
    "no record at " + shared_rules.ORCHESTRATIONS_CONSUMER_REL + "/{slug}; agentTooling/"
    + shared_rules.ORCHESTRATIONS_SELF_REL + "/{slug} is "
    "agentTooling's own record — read it with --self from an agentTooling checkout"
)
# Without --self in agentTooling's own checkout there is no consuming repo: the default
# root would be the checkout's parent, outside any repository. Refused before anything is
# written. orchestration-start.sh gives the same text, reading it from shared_rules.
STANDALONE_REFUSAL = shared_rules.STANDALONE_REFUSAL
# A vendored copy's own `self/orchestrations/` is agentTooling's shipped code: a record tool
# that WRITES there under `--self` makes a local edit to the subtree, which is how the
# consuming repos' stranded records got there (self/features/consumer-record-guard/). Every
# writer refuses it before any write, with this one text; reading a shipped record is not
# refused. agentTooling's own checkout writes there as before.
VENDORED_SELF_WRITE_REFUSAL = (
    "this agentTooling is vendored in a consuming repo, so --self would write agentTooling/"
    + shared_rules.ORCHESTRATIONS_SELF_REL + "/{slug}/ — a local edit to code that ships to "
    "every repo. A record this repo runs lives at " + shared_rules.ORCHESTRATIONS_CONSUMER_REL
    + "/{slug}/: run the same command without --self (an agentTooling feature is listed there "
    "with repo=agentTooling)"
)
# The features list a record's last fence carries, and a feature's repo key
ORCH_FEATURES_KEY = shared_rules.FEATURES_KEY
ORCH_FEATURE_REPO_KEY = shared_rules.FEATURE_REPO_KEY
# The shell's way into the classifier: `python3 roots.py stranded <slug>`
CLI_STRANDED = "stranded"
CLI_ARGC = 3
CLI_STRANDED_RC = 0
CLI_NOT_STRANDED_RC = 1
CLI_USAGE_RC = 2
# ... and into the write guard: `python3 roots.py self-write <slug>` exits 0 when a `--self`
# record write is allowed here, else prints VENDORED_SELF_WRITE_REFUSAL and exits 1 — so a
# crash (also 1, printing no text) fails closed in orchestration-start.sh
CLI_SELF_WRITE = "self-write"
CLI_SELF_WRITE_OK_RC = 0
CLI_SELF_WRITE_REFUSED_RC = 1


def orchestrations_root(self_mode):
    """Where orchestration records live: `--self` → agentTooling's own
    `self/orchestrations/`; otherwise the consuming repo's `plans/orchestrations/`, the
    sibling of `plans/features/` (`--arm-root` applies as it does to `features_root`)."""
    if self_mode:
        return AGENT_TOOLING_DIR.joinpath(*ORCHESTRATIONS_SELF_PARTS)
    return artifact_root(False).joinpath(*ORCHESTRATIONS_CONSUMER_PARTS)


def legacy_orchestrations_root():
    """The vendored location a consuming repo's records used to be written to."""
    return AGENT_TOOLING_DIR.joinpath(*ORCHESTRATIONS_SELF_PARTS)


def is_standalone_checkout():
    """True when the tooling directory is itself a checkout root (`.git` in it): agentTooling's
    own checkout, with no consuming repo above it. `--arm-root` names a consuming repo
    explicitly, so it is never standalone."""
    return _arm_root is None and checkout_of(AGENT_TOOLING_DIR) == AGENT_TOOLING_DIR


def standalone_refusal(self_mode):
    """`STANDALONE_REFUSAL` for a no-`--self` run in agentTooling's own checkout, else None."""
    if not self_mode and is_standalone_checkout():
        return STANDALONE_REFUSAL
    return None


def orchestration_home_repo(self_mode):
    """The repo name a record's own features carry in `features[].repo`: agentTooling under
    `--self` (the declared corpus identity), else the consuming repo's, as the brief header
    names it (`capture_planning.corpus_identity` → `repo_display_name`). Imported lazily:
    capture_planning imports this module."""
    from capture_planning import corpus_identity, repo_display_name
    return repo_display_name(corpus_identity(features_root(self_mode)))


def is_stranded_record(slug):
    """True when the legacy vendored record `slug` is the consuming repo's own: its LAST fence
    lists a feature whose `repo` equals the consuming repo's name, case-insensitively (the
    name `orchestration_home_repo(False)` gives). A record with no such feature — agentTooling's
    shipped ones, a record with no features yet — is not: it carries no claim, so it is left
    where it is. The one classifier every record tool and orchestration-start.sh uses."""
    from routing import parse_manifest
    try:
        record = parse_manifest(legacy_orchestrations_root() / slug / shared_rules.RECORD_NAME)
    except (OSError, ValueError):
        return False
    features = record.get(ORCH_FEATURES_KEY) if isinstance(record, dict) else None
    if not isinstance(features, list):
        return False
    home = orchestration_home_repo(False).lower()
    return any(isinstance(f, dict) and str(f.get(ORCH_FEATURE_REPO_KEY, "")).lower() == home
               for f in features)


def record_refusal(self_mode, slug):
    """The refusal text for a record tool run without `--self`, or None. In order: agentTooling's
    own checkout (`STANDALONE_REFUSAL`); `slug` with no record in the consuming repo but one at
    the legacy vendored place — `LEGACY_RECORD_REFUSAL` (the `git mv`) when stranded,
    `OWN_RECORD_NOTE` when it is agentTooling's own. One message for every tool."""
    if self_mode:
        return None
    standalone = standalone_refusal(self_mode)
    if standalone:
        return standalone
    if (orchestrations_root(False) / slug).exists():
        return None
    if (legacy_orchestrations_root() / slug).exists():
        template = LEGACY_RECORD_REFUSAL if is_stranded_record(slug) else OWN_RECORD_NOTE
        return template.format(slug=slug)
    return None


def self_record_write_allowed():
    """True when a `--self` record write is allowed from this copy: it is agentTooling's own
    standalone checkout, not a copy vendored in a consuming repo. The one predicate
    `record_write_refusal` and the coordinator advisory's wording both ask
    (self/features/consumer-record-guard/)."""
    return is_standalone_checkout()


def record_write_refusal(self_mode, slug):
    """The refusal text for a tool about to WRITE into a record folder, or None:
    `record_refusal`'s, and under `--self` in a copy that is not a standalone checkout —
    vendored in a consuming repo — `VENDORED_SELF_WRITE_REFUSAL`. The vendored test is
    `self_record_write_allowed` (`is_standalone_checkout`), the one place this module decides
    it. A read calls `record_refusal` alone, so a shipped record stays readable with `--self`."""
    if self_mode and not self_record_write_allowed():
        return VENDORED_SELF_WRITE_REFUSAL.format(slug=slug)
    return record_refusal(self_mode, slug)


def all_orchestrations_roots():
    """Both places a record can sit, self first — for reading only (the role guard's
    mirror, the coordinator advisory). From agentTooling's own checkout only the first: its
    parent is no consuming repo, as hooks/orchestrator_role.py's `record_roots` holds."""
    if is_standalone_checkout():
        return [orchestrations_root(True)]
    return [orchestrations_root(True), orchestrations_root(False)]


# An orchestration record's fence `kind`: absent on an orchestrator's record (read as
# ORCH_KIND_ORCHESTRATOR), `"coordinator"` on a coordinator record — a cost record that is
# no role (self/features/coordinator-cost-records/). The key and the coordinator value are
# shared_rules' (the role rule skips such a record).
ORCH_KIND_KEY = shared_rules.KIND_KEY
ORCH_KIND_COORDINATOR = shared_rules.KIND_COORDINATOR
ORCH_KIND_ORCHESTRATOR = "orchestrator"


def orchestration_kind(record):
    """The kind of an orchestration record's parsed fence: `ORCH_KIND_COORDINATOR` when it
    says so, else `ORCH_KIND_ORCHESTRATOR`."""
    if isinstance(record, dict) and record.get(ORCH_KIND_KEY) == ORCH_KIND_COORDINATOR:
        return ORCH_KIND_COORDINATOR
    return ORCH_KIND_ORCHESTRATOR


def all_features_roots():
    """Both corpora, regardless of mode.

    Cost bookkeeping is the one thing that must not be corpus-scoped: a branch
    hosts sessions from whichever corpus was being worked on, so a runner session
    belonging to a host-repo feature can land on the same branch as a --self
    feature's planning. Scoping the exclusion scan to one tree prices those
    runner sessions a second time, as planning cost, on top of their usage.json.

    Only for reading. Everything that *writes* uses features_root(self_mode).
    """
    return [features_root(False), features_root(True)]


def session_root(self_mode):
    """The cwd sessions ran from: nearest ancestor (inclusive) holding .git — and, when
    that ancestor is a linked WORKTREE, the primary checkout it belongs to.

    .exists() rather than .is_dir(): .git is a file in a worktree or submodule. A
    worktree's copy of these scripts is the copy `feature-capture.sh` runs, on the
    feature's branch, before the merge, so it has to resolve the same session root the
    primary's own copy does: the claim roots, the fence around other features' worktrees
    and the transcript-directory scan are all derived from it, and a root that stopped at
    the worktree left every session filed under the primary out of view.
    """
    start = artifact_root(self_mode)
    checkout = checkout_of(start)
    if checkout is None:
        return start
    return worktree_primary(checkout) or checkout


def checkout_of(path):
    """The checkout `path` sits in: its nearest ancestor (inclusive) holding `.git`, or
    None when there is none. A linked worktree is its own checkout here — `.git` is a
    file there, hence `.exists()` — so `session_root` maps it home and
    `routing.feature_dir_in_worktree` uses it as it stands."""
    path = Path(path)
    for candidate in (path, *path.parents):
        if (candidate / GIT_ENTRY).exists():
            return candidate
    return None


def worktree_primary(checkout):
    """The primary checkout a linked worktree at `checkout` belongs to, or None when
    `checkout` is not one — its `.git` a directory, or a file that is not a worktree's.
    Read from the files git itself writes, with no subprocess, so a copy of these
    scripts vendored into a repo with no `git` on PATH resolves exactly as before."""
    entry = checkout / GIT_ENTRY
    if not entry.is_file():
        return None
    try:
        first = entry.read_text().strip().splitlines()[0]
    except (OSError, IndexError):
        return None
    if not first.startswith(GITDIR_PREFIX):
        return None
    gitdir = (checkout / first[len(GITDIR_PREFIX):].strip()).resolve()
    try:
        common = (gitdir / (gitdir / COMMONDIR_FILE).read_text().strip()).resolve()
    except OSError:
        return None
    if common.name != GIT_ENTRY:
        return None
    return common.parent


if __name__ == "__main__":
    import sys

    # `roots.py stranded <slug>`: exit 0 when the legacy vendored record is stranded, and
    # `roots.py self-write <slug>`: exit 0 when a `--self` record write is allowed here
    # (orchestration-start.sh asks these instead of re-implementing either decision)
    if len(sys.argv) != CLI_ARGC or sys.argv[1] not in (CLI_STRANDED, CLI_SELF_WRITE):
        sys.exit(CLI_USAGE_RC)
    if sys.argv[1] == CLI_SELF_WRITE:
        refusal = record_write_refusal(True, sys.argv[2])
        if refusal:
            print(refusal)
            sys.exit(CLI_SELF_WRITE_REFUSED_RC)
        sys.exit(CLI_SELF_WRITE_OK_RC)
    sys.exit(CLI_STRANDED_RC if is_stranded_record(sys.argv[2]) else CLI_NOT_STRANDED_RC)
