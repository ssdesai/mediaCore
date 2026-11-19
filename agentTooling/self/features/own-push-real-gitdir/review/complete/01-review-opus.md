# 01 — review: own-push-real-gitdir

Review this feature against its spec, which is the coordinator's rulings in
`self/features/own-push-real-gitdir/NOTES.md` → "Coordinator rulings". Do not use the
builder's report as the spec. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Close one gap. In the cloud profile, `hooks/allow-repo-commands.sh`'s `own_push_allowed`
approved `git -C <path> push origin <own-branch>` when `<path>` was a git directory planted
in the tree as plain files. Its `core.worktree` named the root, and its config redirected
the push to `main` (evil2) or ran a command through `core.sshCommand` with an `ssh://` url
(evil3). After this feature, a push is approved silently only when ALL of these hold.
Anything else is a prompt, never a deny.

1. The words are exactly `git push [-u | --set-upstream] origin <B>`, with no global option
   (no `-C`, `--git-dir`, `--work-tree`, `-c`). There is no env assignment on the line. The
   payload's `cwd` is the project root.
2. The git directory git uses, run from the root, is the root checkout's own. The checkout
   is the nearest directory at or above the root holding a `.git` entry, found by walking
   the filesystem. Its gitdir is that `.git` directory, or the `gitdir:` path its `.git`
   file names. `--show-toplevel` must equal that checkout. Both are compared by realpath.
3. `<B>` is the current branch, a plain name, and `branches[0]` of the manifest committed
   at `HEAD`, as before. No refspec has a colon.
4. The effective config (`git config --list -z`, every scope) holds none of the keys in
   ruling 4's presence list. `push.default` is absent, `simple` or `current`.
   `remote.origin.url` has one value, with an http or https scheme, and `git remote get-url
   --push --all origin` gives exactly that one value. No `pre-push` or
   `reference-transaction` hook exists in the common gitdir's `hooks/`. Any read error
   means a prompt.

Excluded: the read-only git approvals in a planted gitdir. That is a pre-existing gap,
filed in `self/BACKLOG.md`, and is not a finding against this diff. Excluded too: any
change to the deny side, `policy.py` or `.claude/settings.json`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `own_push_allowed(args, cwd, root)` keeps its signature and its call site in
  `subcommand_allowed`, under `except Exception: return False`.
- Every new literal is a named constant at the top of the hook's constants block (key
  list, regexes, schemes, `push.default` values, hook names), per `CONVENTIONS.md` →
  "Named constants".
- `GIT_NO_REPLACE_OBJECTS` and the HEAD-committed manifest read are unchanged (Q5 and Q6
  still pass).
- `self/tests/hook-cloud-profile.sh` holds:
  - evil2 and evil3 as the audit planted them, with both `-C` spellings and `-u`, as
    prompts;
  - a prompt row for each condition and each presence key;
  - approve rows for the plain push, `-u`, `--set-upstream`, a read chained before the
    push, `push.default=simple`, and a non-applying `insteadOf`.

  The commit history shows those tests committed before the fix (`<slug>: acceptance tests`).
- Rows that approved `git -C <root> push …` now expect a prompt. No other row of the table
  changes its answer.
- Every deny row is unchanged. This feature adds no deny and removes none.
- `hooks/README.md` → "The one cloud approval" states the new conditions and claims
  nothing that a test does not prove. `CONVENTIONS.md` → "Approved silently" says the push
  runs from the project root. The root `README.md` and `self/tests/README.md` agree.
- `./self/gate.sh` is green.

Check also: can any approved push still reach a git directory, config, hook or URL that a
file write under the root (with no `.git` in its path) controls? Can a push the old rule
approved, which a human legitimately makes, newly prompt beyond what ruling 1 says
(`-C`, a subdirectory cwd)?

## Verdict
