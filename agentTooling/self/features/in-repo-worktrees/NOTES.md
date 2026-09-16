# Notes: in-repo-worktrees

Rulings made during the direct build, one line of rationale each. The request and the
exclusions are in `README.md`; the review brief is `review/incomplete/100-review-opus.md`.

## Rulings

1. **Ignored through the common git dir's `info/exclude`, not a tracked `.gitignore`.**
   `feature-start.sh` appends `/.worktrees/` to `$(git rev-parse --git-common-dir)/info/exclude`
   before `git worktree add`, only when no line equal to it is already there, after
   making sure the file ends in a newline so an unterminated last entry is never
   extended. Rationale: it changes nothing any consuming repo tracks, so there is no
   commit to make and no hand-merge on `update.sh`; it is per clone, exactly as the
   worktree is. The anchored pattern ignores the top-level directory only.
2. **The worktree is found by branch first, then by derivation.** `feature-close.sh` asks
   `git worktree list --porcelain` for the worktree holding `refs/heads/<S>`; absent
   that, it takes `<R>/.worktrees/<S>` if it exists, else the legacy `<R>-<S>` if that
   exists, else the nested path (for the "already gone" message and `worktree prune`).
   Rationale: git is the record of where a worktree is, so a legacy sibling closes with
   no flag, and the fallback still covers a worktree whose branch was checked out
   elsewhere or deleted.
3. **Claimability is a longest-prefix rule over roots and fences.** The roots are the
   primary `<R>`, the nested `<R>/.worktrees/<S>` and the legacy `<R>-<S>`; the one fence
   is `<R>/.worktrees`. A cwd is claimable when the longest root-or-fence path it equals
   or sits under is a root. So `<R>/.worktrees/<other>` falls to the fence, while
   `<R>/.worktrees/<S>` is claimed by its more specific root. Rationale: one rule, no
   special case per path, and it keeps the legacy sibling claimable, so a `--recapture`
   of an old feature finds every session it found before.
4. **`transcript_dir_name` mangles `.` as well as `/`.** Claude Code names a project dir
   after the launch cwd with both mangled to `-`; before this, a primary checkout whose
   path held a `.` produced a fragment matching no project directory. The nested dir
   itself (`…-<R>--worktrees-<S>`) already contained the unchanged fragment, so this is
   correctness for the fragment, not what makes nested sessions visible.
5. **The doctrine keeps rule 1 and names the primary as a place to launch.**
   `LIFECYCLE.md` rule 1 stays word for word in substance: a session is billed to its
   launch directory's branch. What changes is the advice: a session launched in the
   primary reaches the nested worktree now, and it is claimed by the pin
   `feature-start.sh` writes for it (its delegates pinned in `subagents`); launching in
   the worktree remains the route that needs no pin. `feature-start.sh`'s "Next" lines
   print the pinned route only when it actually pinned a session.
6. **Every test fixture that names a project directory now mangles `.` too.** Ruling 4
   made `transcript_dir_name` match what Claude Code writes, and seven existing tests
   (`capture-guard`, `subagent-capture`, `claims-ledger`, `session-share`,
   `session-claims`, `timestamps-are-utc`, `sweep`) built their fixture dirs with
   `tr '/' '-'` over a bare `mktemp -d` path, `…/T/tmp.XXXX`, which has a `.` in it. Their
   dirs were then named in a way Claude Code never names one, and matched only because
   the code had the same bug. Fixed at the fixture (`tr '/.' '--'`), not by matching both
   spellings in the code: a second spelling would exist only to serve wrong fixtures.
7. **`git clean` needs no guard, only a sentence.** Measured on git 2.50.1 in a throwaway
   repo: with `/.worktrees/` in `info/exclude`, `git clean -fdx` prints `Skipping
   repository .worktrees/<slug>` and leaves the worktree intact; `git clean -ffdx` (two
   `-f`s) removes `.worktrees/` entirely. The primary's `git status --porcelain --ignored`
   shows it as `!! .worktrees/`. `README.md` → "Updating" says so for consuming repos,
   together with scoping a linter or test runner to the repo's own directories; nothing
   stronger, since `-ff` is git's own explicit "yes, nested repositories too".
8. **Only `feature-start.sh` writes the exclude entry.** `feature-close.sh` does not
   re-assert it: a nested worktree only ever exists because `feature-start.sh` made it,
   and that run wrote the entry first. A clone that lost it (a hand-edited
   `info/exclude`) refuses its close on the dirty primary, naming `.worktrees/`, which is
   the right, loud outcome; the next `feature-start.sh` puts it back.
9. **The worktrees directory is not removed when it empties.** `feature-close.sh` removes
   the feature's worktree and leaves an empty, ignored `.worktrees/` behind; the next
   start reuses it. Removing it would be one more write outside the feature for nothing.

## Open questions

- `harness/` builds its own experiment-arm worktrees and was not touched; whether those
  should move inside the checkout too is the harness's call, not this feature's.
