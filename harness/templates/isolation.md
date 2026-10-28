## Isolation — this is one arm of an experiment

Everything you produce is measured against another arm of the same feature. Reading
anything from another arm, or from the scoring instruments, invalidates the whole run —
including work already finished. These are not preferences.

- **Work only in `@@TREE@@`**, on the branch already checked out there. Never run
  `git`, `pip`, `npm` or any other state-changing command in another checkout.
- **Do not read, list, open or `git log` these paths** — they are the repository's main
  checkout and the other arms' worktrees:

@@SIBLINGS@@

- **Do not read `plans/experiments/` in any repo** (it lives at
  `@@EXPERIMENTS_DIR@@`). The acceptance probe and the review brief are the scoring
  instruments and are deliberately withheld: the spec is the whole brief, for you and
  for every other arm alike.
- **Do not edit `@@AGENT_TOOLING@@`** — it is vendored from a shared repo and a change
  there ships to every repo that pulls it.
- The read-only spec worktree at `@@SPEC_TREE@@` is reference material, checked out
  detached at a pinned commit. Read it; never write to it.
