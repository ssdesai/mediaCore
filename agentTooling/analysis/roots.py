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
the reason nothing here takes a repo path argument.

The self corpus's identity, though, is DECLARED rather than derived, because neither
root can be asked for it: `self/features` can only ever belong to agentTooling, and a
copy vendored into a consumer has no .git of its own, so asking git about it answers
with the consumer's origin and files every agentTooling feature under a repo it does
not belong to. See SELF_CORPUS_IDENTITY below.
"""

from pathlib import Path

AGENT_TOOLING_DIR = Path(__file__).resolve().parents[1]

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


def add_self_flag(parser):
    """Register --self, worded identically across the three scripts."""
    parser.add_argument(
        "--self",
        dest="self_mode",
        action="store_true",
        help="operate on agentTooling's own corpus (self/features/) rather than "
        "the consuming repo's (plans/features/)",
    )


def artifact_root(self_mode):
    """Where feature directories live and results are written."""
    return AGENT_TOOLING_DIR if self_mode else AGENT_TOOLING_DIR.parent


def features_root(self_mode):
    """The per-feature tree under the artifact root."""
    if self_mode:
        return AGENT_TOOLING_DIR / "self" / "features"
    return AGENT_TOOLING_DIR.parent / "plans" / "features"


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
    """The cwd sessions ran from: nearest ancestor (inclusive) holding .git.

    .exists() rather than .is_dir(): .git is a file in a worktree or submodule.
    """
    start = artifact_root(self_mode)
    for candidate in (start, *start.parents):
        if (candidate / ".git").exists():
            return candidate
    return start
