# 62 — Analysis scripts self-mode

Feature: `agenttooling-self-host`, plan 4 of 5. Makes `agentTooling/` able to run the
delegated-plan workflow on itself (`--self`), so harness features are planned, executed
and costed inside agentTooling instead of inside whichever repo vendors it.

Give the three analysis scripts a `--self` flag, and split the single `REPO_DIR` they
share into the two roots that diverge under it.

Independent of other plans.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- All three scripts currently derive `REPO_DIR = Path(__file__).resolve().parents[2]` at
  module level and build feature paths as `Path(repo_dir, "plans", "features")` — eight
  such constructions across the three files. Every one is listed below; do not search
  for more.
- **Two roots, not one.** `REPO_DIR` today means both "where artifacts are written" and
  "the cwd sessions ran from". Under `--self` those differ: artifacts go to
  `agentTooling/`, but planning sessions ran from the enclosing repo, so
  `~/.claude/projects/` directory names encode *that* path. Resolving the session root
  as the nearest ancestor holding `.git` gives the consuming repo when agentTooling is a
  subtree and agentTooling itself in a standalone clone.
- Scripts are stdlib-only Python 3, run directly (`python3 agentTooling/analysis/x.py`),
  never installed. There is no package and no `__init__.py`; `from pricing import …`
  resolves because Python puts the script's own directory on `sys.path`. `roots.py` is
  imported the same bare way.
- `--self` is a flag, not a positional, and takes no value. It must not be confused with
  `report.py`'s existing optional `slug` positional or its `--all`.
- `argparse` would name the attribute `args.self` by default; use `dest="self_mode"`.
- `.git` is a directory in an ordinary clone and a *file* in a worktree or submodule, so
  the session-root walk tests `.exists()`, not `.is_dir()`.

## Files

- Create `agentTooling/analysis/roots.py`
- Modify `agentTooling/analysis/backfill_usage.py`
- Modify `agentTooling/analysis/capture_planning.py`
- Modify `agentTooling/analysis/report.py`
- Modify `agentTooling/analysis/README.md`

## `agentTooling/analysis/roots.py` (create)

```python
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


def session_root(self_mode):
    """The cwd sessions ran from: nearest ancestor (inclusive) holding .git.

    .exists() rather than .is_dir(): .git is a file in a worktree or submodule.
    """
    start = artifact_root(self_mode)
    for candidate in (start, *start.parents):
        if (candidate / ".git").exists():
            return candidate
    return start
```

## `agentTooling/analysis/backfill_usage.py`

Delete the module-level `REPO_DIR` and import from `roots` alongside the existing
imports:

```python
from roots import add_self_flag, artifact_root, features_root
```

`extract_usage(stream_path, plan_stem)` reaches for the module global at its
`to_repo_relative(file_path, REPO_DIR)` call. Give it the root explicitly — add a third
parameter `repo_dir`, use it at that call site, and pass the artifact root at the single
call site in `main`.

In `main`: register the flag with `add_self_flag(parser)` next to the existing `--force`
argument.

The local variable currently named `features_root` would shadow the imported function —
rename it to `features_dir`, and make the not-found message name the path it actually
looked at rather than a hardcoded `plans/features`:

```python
    features_dir = features_root(args.self_mode)
    if not features_dir.exists():
        print(f"no features directory at {features_dir}, nothing to do")
        return
```

The `rglob` over `features_dir` and everything below it is unchanged apart from the
rename and passing `artifact_root(args.self_mode)` into `extract_usage`.

## `agentTooling/analysis/capture_planning.py`

Delete the module-level `REPO_DIR`; import `add_self_flag`, `features_root` and
`session_root` from `roots`.

Two helpers build feature paths from a repo root. Both should take the features root
directly instead, since that is all they use it for — rename the parameter and drop the
`"plans", "features"` segments:

- `collect_excluded_session_ids(repo_dir, manifest)` → `(features_dir, manifest)`, with
  `Path(repo_dir, "plans", "features").rglob("*.usage.json")` becoming
  `features_dir.rglob("*.usage.json")`.
- `check_branch_overlap(repo_dir, slug, manifest)` → `(features_dir, slug, manifest)`,
  with the `glob("*/README.md")` call adjusted the same way.

In `main`, add `add_self_flag(parser)`, and reword the `slug` positional's help to
"feature slug under plans/features/<slug>/ (or self/features/<slug>/ with --self)".
Then resolve both roots and use each for its own purpose:

```python
    features_dir = features_root(args.self_mode)
    sessions_dir = session_root(args.self_mode)

    manifest_path = Path(features_dir, args.slug, "README.md")
```

`check_branch_overlap` and `collect_excluded_session_ids` take `features_dir`. The
output path near the end of `main` becomes
`Path(features_dir, args.slug, "planning.json")`.

The session-matching block is the part that must use `sessions_dir`, not the artifact
root — this is the whole point of the split:

```python
    session_dir_str = str(sessions_dir)
    dir_fragment = transcript_dir_name(sessions_dir)
```

and `find_transcript_dirs(sessions_dir)`.

**Fix the fallback in the `repo_match` test while you are in it.** It currently reads:

```python
            repo_match = any(
                line.get("cwd") == repo_dir_str
                or (isinstance(line.get("cwd"), str) and dir_fragment in line["cwd"])
                for line in lines
            )
```

`dir_fragment` is the *mangled* form (`-Users-x-dev-repo`, slashes replaced by dashes)
and `line["cwd"]` is a real filesystem path (`/Users/x/dev/repo`), so that second clause
can never be true — only the exact-cwd match works, and the documented
"session whose cwd moved into a scratchpad" case is silently missed. The fallback wants
the real path as a prefix:

```python
            repo_match = any(
                line.get("cwd") == session_dir_str
                or (
                    isinstance(line.get("cwd"), str)
                    and line["cwd"].startswith(session_dir_str + "/")
                )
                for line in lines
            )
```

`transcript_dir_name` is still used — `find_transcript_dirs` needs the mangled form to
match directory *names* under `~/.claude/projects/`, which is what it was written for.
Update its docstring to say the mangled name is for project-directory names only and
must not be matched against a `cwd` value.

## `agentTooling/analysis/report.py`

Delete the module-level `REPO_DIR`; import `add_self_flag`, `artifact_root` and
`features_root` from `roots`.

`build_usage_index(repo_dir)` and `run_trend_mode(repo_dir)` use their argument solely to
build the features path — change both to take `features_dir` and use it directly
(`features_dir.rglob("*.usage.json")`, `features_dir.glob("*/report.json")`).

`run_single_feature` needs both roots: the features root for `feature_dir`, and the
artifact root for `compute_edit_overlap`, which relativizes absolute tool-call paths.
Change its signature to `run_single_feature(repo_dir, features_dir, slug)` and inside it:

- `feature_dir = Path(features_dir, slug)`
- `usage_index = build_usage_index(features_dir)`
- `compute_edit_overlap(loaded_plans, repo_dir, warnings)` — unchanged, `repo_dir` is now
  the artifact root.
- `load_manifest_plans(repo_dir, …)` — unchanged. Its `repo_dir` parameter is unused
  inside the function; leave the signature as it is rather than tidying it, that is not
  this plan's business.

`to_repo_relative` and `compute_edit_overlap` keep taking a repo root and need no edit —
they receive the artifact root now, which is correct: a `--self` run's `usage.json`
records `files_edited` relative to `agentTooling/`, because the runner `cd`s there.

In `main`, add `add_self_flag(parser)`, extend the `slug` help the same way as
`capture_planning.py`, and dispatch with the resolved roots:

```python
    if args.all:
        run_trend_mode(features_root(args.self_mode))
        return

    run_single_feature(
        artifact_root(args.self_mode), features_root(args.self_mode), args.slug
    )
```

Preserve whatever the existing `--all` branch does around that call (the early return and
any messages); only the argument changes.

## `agentTooling/analysis/README.md`

Rewrite the **"Where to run them"** section. It currently says the repo root is derived
from the script's own location, that cwd is irrelevant, and that running from a
standalone `agentTooling` checkout resolves to the checkout's parent and fails with a
confusing `FileNotFoundError`. The first two still hold; the third is now a supported
mode rather than a failure. It should say:

- Which copy you invoke still selects the repo, and cwd is still irrelevant — all roots
  derive from the script's own location on disk, via `roots.py`.
- Without `--self`, the artifact root is the consuming repo (`parents[2]`) and the
  feature tree is `plans/features/`. With `--self`, they are the agentTooling checkout
  (`parents[1]`) and `self/features/` — the corpus for features whose diff is entirely
  inside agentTooling.
- The two-root split, and why it is not one root: `capture_planning.py` alone reads
  `~/.claude/projects/`, whose directory names encode the cwd a session ran from. Under
  `--self` that is the enclosing repo, not `agentTooling/`, so the session root is
  resolved separately as the nearest ancestor holding `.git`. Give the concrete
  consequence — a `--self` capture in a subtree checkout reads
  `~/.claude/projects/-Users-…-vinylCatalogue/` and writes
  `agentTooling/self/features/<slug>/planning.json`.
- That a standalone `agentTooling` clone works too, with both roots landing on the clone
  itself, and is why the rule is "nearest `.git`" rather than "the parent directory".
- Keep the existing closing point that no script takes a repo path argument, and that
  this is deliberate so one repo's costs can never be written into another's tree. Note
  that `--self` does not weaken it: it selects between two fixed roots derived from the
  script's location, not an arbitrary path.

In **"How to run them"**, note after the three-command block that each command takes
`--self` in the same position to operate on agentTooling's own corpus:

```bash
python3 agentTooling/analysis/backfill_usage.py --self
python3 agentTooling/analysis/capture_planning.py --self <slug>
python3 agentTooling/analysis/report.py --self <slug>
```

In **"Scripts"**, add a `roots.py` entry ahead of `pricing.py` — the trigger for README
Rule 1 is met, so list its full surface: `AGENT_TOOLING_DIR`,
`add_self_flag(parser)`, `artifact_root(self_mode)`, `features_root(self_mode)`,
`session_root(self_mode)` — and state that every script resolves roots through it rather
than computing `parents[N]` itself, so the two modes cannot drift apart. Append to the
`capture_planning.py` entry that it is the only consumer of `session_root`, and that
this is the dependency README Rule 2 exists for: nothing in its imports reveals that its
transcript lookup keys off a different directory than its output path.
