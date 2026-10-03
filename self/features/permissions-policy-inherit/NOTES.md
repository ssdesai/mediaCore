# Notes: permissions-policy-inherit

Rulings the spec left open, one line of rationale each, written as they were made.

## The hook's approvals

- **An entry point must exist on disk, not just spell a basename.** `entry_script`
  requires `os.path.lexists` as well as `inside`, so a basename that names nothing
  vouches for nothing and a symlink that leaves the tree is refused by `realpath` like
  every other path.
- **`--carry-lost` joins `--recapture` and `--all` in `CAPTURE_WRITING_FLAGS`**, which the
  spec did not name: it implies `--recapture`, so approving it would have been the same
  widening under another flag. A narrowing, not a widening — every case the brief asked
  for still refuses.
- **`manifest.py`'s subcommand is read positionally, never searched for.** `manifest.py
  get init` is a feature named `get` being initialized; a membership test on `get` would
  have approved it. Positional index 1 after dropping flags is the CLI's own shape
  (`manifest.py [--self] <slug> <subcommand>`).
- **`bash` and `shellcheck` are matched as literal program tokens**, not by basename:
  `/usr/bin/bash` is already refused for being an absolute path outside the root, and a
  `bash` inside the tree would be a planted file, which needs a prior write (an accepted
  limit the README already records).
- **`shellcheck` takes no flags.** `self/gate.sh` passes only file names; a flag list is a
  widening nothing needs yet, and one prompt is the whole cost of being wrong.

## The git deny

- **A word carrying a brace is not judged.** The deny performs no brace expansion, so
  what git would really be handed is a guess — `git branch {-a,new}` and
  `git branch '{-a,-v}'` therefore prompt, exactly as they did before, and the approval
  analysis (which does expand) still refuses them. This keeps the deny's standing rule:
  what it cannot read, it does not judge. Asserted as `NOT_DENIED` cases.
- **`clean`, `stash` and `rebase` are denied whatever follows**, `git stash list`
  included. A read-only spelling one keystroke from a destructive one is exactly where a
  prompt belongs, and the brief named the subcommands, not their flags.
- **A listing flag's value is not a positional.** `GIT_BRANCH_VALUE_FLAGS` exists so
  `git branch --merged main` and `--contains HEAD` are not denied as branch creation — a
  false deny would be worse than the prompt they get today.
- **The deny runs after the `cd` deny.** A command that is both (`cd X && git rebase`)
  gets the rewrite advice first, which is the one a model can act on without asking.

## The wiring

- **`EDIT_DENY_RULES` no longer holds the policy rule.** It has two spellings now
  (`Edit(**/agentTooling/hooks/**)` vendored, `Edit(/hooks/**)` under `--self`), so
  `edit_deny_rules(self_mode)` appends whichever applies rather than either constant
  carrying a mode-dependent value.
- **Counts are reported per kind** — "9 Edit deny rule(s) and 18 Bash deny rule(s)" — so
  a repo that is missing only the new rules reads why from the line `sync-plans.sh`
  prints.
- **`sync-plans.sh` was not changed.** It calls the helper without `--self`, which is
  still the default, and its own report already formats whatever status comes back.

## This checkout's settings file

- **Written by the tool, in the tool's own format, and committed.** No hand-authoring:
  the gate's `--self --check` is what keeps it honest, and the file's own
  `Edit(/.claude/**)` rule refuses an Edit-tool change to it.
- **No README inside `.claude/`.** The directory is the permission system's and its one
  file is generated; it is described in the root `README.md` row and in
  `self/PROJECT_FACTS.md` → Layout instead, where a reader will actually meet it.
- **It ships with the subtree.** Nothing reads a nested `agentTooling/.claude/settings.json`
  today, but the hook path in it does not resolve in a consuming repo; filed in
  `self/BACKLOG.md` rather than fixed here, since fixing it means changing what the
  subtree split carries.

## Plan numbering

- **The fix is for the next feature, not this one.** This feature keeps `100`; the
  corpus's next stem is now `105`, which is what `feature-start.sh` would have handed out
  had the `find` seen three digits.
- **A sibling test, not a phase of `feature-lifecycle.sh`.** The numbering fixtures have
  to live on `main` before a start runs, because the worktree is cut from `origin/<base>`
  — and `feature-lifecycle.sh` drives closes and pushes against that same `main`
  afterwards. A 60-line scaffold of its own costs less than a mutation of `main` in the
  middle of a 648-line lifecycle test.

## Deliberately not done

- **`CONVENTIONS.md` was not touched.** Its Shell-commands section documents the `cd`
  deny because that deny is about command *shape*; the git deny is about lifecycle
  authority, and `LIFECYCLE.md` rule 2 — which now names it — is where a reader looks
  for that.
