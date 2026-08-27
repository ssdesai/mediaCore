"""Root resolution shared by the analysis scripts.

Two roots, identical in an ordinary run and divergent under --self:

  artifact root   where feature directories live and results are written
  session root    the cwd Claude Code sessions ran from, which is what the
                  directory names under ~/.claude/projects/ encode

Ordinary run: both are the consuming repo root, two levels above this file.

--self: artifacts belong to the agentTooling checkout one level up, but planning
sessions still ran from the enclosing repo, so the session root is the nearest
ancestor holding .git. That is the consuming repo when agentTooling is vendored as a
subtree, and agentTooling itself in a standalone clone — one rule covering both, and
the reason nothing here takes a repo path argument.
"""

from pathlib import Path

AGENT_TOOLING_DIR = Path(__file__).resolve().parents[1]


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
