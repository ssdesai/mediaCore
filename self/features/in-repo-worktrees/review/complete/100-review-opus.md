# 100 — review: in-repo-worktrees

Feature: `in-repo-worktrees` (`--self`). One opus implementer built it **direct**, per
`AGENT_DIRECT.md`, with no build or verify plans. That makes this pass the only independent look
before a human sees the PR. This brief was written before the build, from the request and from a
read of the scripts. It has not seen the implementer's reasoning. The implementer's rulings are in
`self/features/in-repo-worktrees/NOTES.md`: judge them, don't take them on trust.

Paths below are relative to `agentTooling/`, your working directory.

## What the feature was supposed to do

Today `feature-start.sh` creates each feature's worktree as a **sibling** of the primary checkout,
`<R>-<S>`. The user works in a single Claude Code session launched in the primary checkout. Their
settings block reads outside the launch folder, and they will not widen access to the parent
directory. So every sibling worktree has needed a manual `/add-dir`, and every delegate working
there has triggered permission prompts.

The feature moves the worktree **inside** the primary checkout, to `<R>/.worktrees/<S>`, kept out of
git. A session launched in the primary checkout can then reach it without any access outside that
folder. The branch naming (`S`), the manifest, and every lifecycle step stay the same. Only the
worktree's location changes.

## The diff

Base is `main`. Start with `git diff main...HEAD --stat`, then read the full diff. The gate
(`./self/gate.sh`) ran green before this pass, and `self/gate-report.txt` has the result. Do not
re-run the whole gate. Running one `self/tests/*.sh` script to confirm a finding is fine.

## Contracts to hold it to

- **One derivation.** Before this feature, the worktree path was built in four places:
  - `feature-start.sh` (`WORKTREE="$PRIMARY-$SLUG"`);
  - `feature-close.sh` (the same line);
  - `analysis/capture_planning.py`, twice (`f"{session_dir_str}-{slug}"`, beside its comments
    "LIFECYCLE.md: the feature's worktree is the primary checkout's path plus `-<slug>`").

  Each place must now build the new path from one named constant for the `.worktrees` directory
  name, not a re-typed literal. The two languages cannot share a constant, but each script must have
  exactly one.
- **Kept out of git.** A worktree nested in the primary checkout shows up as untracked in the
  primary's `git status` unless it is ignored. `feature-close.sh` refuses a dirty primary, so an
  unignored `.worktrees/` would block every close.
  - Check how it is ignored.
  - Check that the mechanism writes nothing a consuming repo tracks, or, if it does, that this is
    justified in NOTES.md.
  - Check that it is idempotent: a second `feature-start.sh` must not append a duplicate line or
    clobber existing exclude entries.
  - Check that a test asserts the primary's `git status --porcelain` is empty after a start.
- **Features started under the old layout still close.** This matters now: at least one live
  feature (`discogs-merge-unconfirm-delete`) has a sibling worktree `<R>-<S>` today.
  - `feature-close.sh` must find, carry timing from, and remove a legacy sibling worktree as well as
    a nested one.
  - `capture_planning.py` must keep the legacy `<R>-<S>` claimable **alongside** the nested path.
    Otherwise a `--recapture` of any closed feature silently drops the sessions launched in its
    worktree, and the re-captured cost shrinks.
  - Both need a test.
- **Other features' worktrees stay unclaimable.** `cwd_under_any` is a prefix test (`cwd == root`
  or `cwd.startswith(root + "/")`), and the primary checkout is one of the roots. A nested
  `<R>/.worktrees/<other>` is under the primary, so without a fix every feature's sessions become
  claimable by every other feature. That undoes the rule `launched_elsewhere` and
  `check_unmatched_branches` exist to enforce. Required:
  - A session whose cwd is `<R>/.worktrees/<other-slug>` must not match for feature `S`.
  - One in `<R>/.worktrees/S` must match.
  - One in `<R>` itself still matches.

  Check that the tests assert all three, and the legacy sibling case too.
- **Transcript discovery.** Claude Code files a session under a project directory named after its
  launch cwd, with `/` and `.` both mangled to `-`. So `<R>/.worktrees/S` becomes
  `-…-<R>--worktrees-S`. Check that `--list-sessions`, `--list-subagents` and the capture's project-
  directory scan find transcripts under that name, not just the `<primary>-*` sibling pattern.
- **Refusals unchanged.** Running `feature-start.sh` or `feature-close.sh` from a worktree's own
  copy still refuses, now that the worktree sits inside the primary. The script's own path is under
  the primary checkout either way, so check the refusal still keys on git-dir vs common-dir and not
  on a path prefix. An existing branch or worktree still refuses too.
- **Docs match the code, everywhere they name the path.**
  - `LIFECYCLE.md`: the naming block ("a sibling directory of the primary checkout") and the three
    rules.
  - `README.md`: the `feature-start.sh` and `feature-close.sh` rows.
  - `self/PROJECT_FACTS.md` → Commands.
  - `AGENT_DIRECT.md` → "The brief" item 2 (`<repo>-<slug>`).
  - `analysis/README.md`.
  - `capture_planning.py`'s docstrings and help text.
  - `self/tests/README.md`: the rows for any test touched.
  - The "Next" lines `feature-start.sh` prints.

  A doc still saying `<repo>-<slug>`, `R-S` or "sibling" about the *current* layout is a finding.
  Saying it about the legacy layout is fine.
- **bash 3.2, `set -uo pipefail` without `set -e`, and named constants.** These are the house
  rules (`self/PROJECT_FACTS.md`).

## The judgment calls worth an adversarial read

1. **Nested inside the primary.** A nested worktree is exposed to anything that walks the primary
   checkout: a consuming repo's tooling that lints `.`, a pytest with no `testpaths`, a `git clean`.
   Establish what `git clean -fdx` run in the primary does to `.worktrees/<S>`: does git treat a
   directory with a `.git` file as a nested repository and skip it without `-ff`? Judge whether the
   feature needs a warning for consuming repos in `README.md` → "Updating", or anything stronger.
2. **The launch advice.** `LIFECYCLE.md` rule 1 and `feature-start.sh`'s "Next" lines tell the
   human to launch the coordinator inside the worktree. The point of this feature is that they may
   stay in the primary instead, pinned by `feature-start.sh`, with delegates pinned in `subagents`.
   Judge whether the implementer left the doctrine honest: neither silently rewritten nor
   contradicted by the new layout.
3. **Propagation.** This ships to every consuming repo on its next `update.sh`. Is there anything a
   consuming repo must do by hand (an ignore entry, a tool config) that the PR body should say?

## Verdict

Write `self/review-report.md`. `self/pr.sh` uses it verbatim as the PR body, so the audience is the
human approving the merge.
- Say what the feature was supposed to do and whether it does it.
- Then give two separate lists: fixed here, and escalated.
- Do not transcribe the investigation.

**"No findings" is a legitimate verdict.** A clean verdict should still say it specifically checked
two things: that other features' nested worktrees are unclaimable, and that legacy sibling features
still close and recapture.

The most valuable finding is a missing assertion: "this invariant has no test, here is the
assertion". Fix only what is local: a drifted doc line, a missing constant, an unguarded idempotence
case. Anything that needs a design decision goes in the escalated list; do not implement it.
