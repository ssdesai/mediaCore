# detached-at-branch-tip-attach — notes

Rulings made while building this feature by hand, in the order they came up.

## 0. The reproduction

Seen twice on the night of 2026-10-27 (humanNetworkMap, feature `pull-agenttooling-pr99`).
A cloud session created to CONTINUE an existing feature branch (`create_session` with
`source_revision` = the branch, `outcome_branch` = the branch) came up like this:

```
git status: HEAD detached from refs/heads/claude/pull-agenttooling-pr99 (clean)
git branch -vv:
* (HEAD detached from refs/heads/claude/pull-agenttooling-pr99) f1c0a8db pull-agenttooling-pr99: cost records
  claude/pull-agenttooling-pr99 bbb69f76 [origin/claude/pull-agenttooling-pr99: behind 12] pull-agenttooling-pr99: cost records
```

HEAD was detached exactly AT the branch's current remote tip, and the stale local branch
ref (from an earlier session's cached clone) was a strict ancestor, 12 behind. The hook
refused `git checkout -B claude/pull-agenttooling-pr99 origin/claude/pull-agenttooling-pr99`
(rule 2), the harness's commit steps refuse a detached HEAD, and so the session could do
nothing. A fresh session reproduced the same state, so `cloud-off-branch-remedy`'s remedy
("launch a fresh session") does not cure it. The environment appears to cache the clone
and re-check-out the requested revision detached when the local branch already exists and
is stale.

## 1. A script, not a hook carve-out for `checkout -B`

Allowing `git checkout -B <b> origin/<b>`, `git switch -C` or `git branch -f` in the hook
would do nothing on its own: those are prefix deny rules in the settings file
(`policy.bash_deny_rules()`, `Bash(git checkout -B:*)` and its kin), and a deny rule
refuses whatever the hook says. Lifting them would mean changing the rendered settings of
every consuming repo, in both profiles, to let through a command that is safe in one
narrow repository state. The hook cannot express that state as a prefix.

`attach-branch.sh [--self] [<branch>]` is smaller. It checks the state itself
(`plan-runner-roots.sh`'s `attachable_branches`) and acts only when nothing can move:

- HEAD is detached;
- `<branch>` is a tracked manifest's `branches[0]`;
- `origin/<branch>` IS HEAD's commit;
- the local `<branch>` is absent or an ancestor of HEAD.

When all four hold it runs `git update-ref refs/heads/<b> HEAD <old>`, a compare-and-swap,
then `git checkout <b>` (the same commit, so the working tree and any edit are untouched),
then sets the upstream. Every other state is refused with nothing changed, and the
refusal names the condition that failed. The hook's reason teaches one command, not a git
incantation the agent has to get exactly right.

The script is cloud only. A detached local worktree is the human's to sort out.

## 2. The script prompts, it is not silently approved

The brief suggested "have the hook allow it by name". The entry-point list's own rule
(hooks/allow-repo-commands.sh, "The harness's own entry points") is that anything which
moves a ref stays off it and keeps prompting, the way `feature-start.sh` and
`feature-close.sh` do. `attach-branch.sh` moves a ref, so it prompts too. The hook does
not deny it (it cannot see inside a script), so in a cloud session it reaches the
permission flow like `feature-start.sh`. What the hook does change is the REASON on every
refusal in that shape, which now names the script.

## 3. The attach reason applies to every cloud refusal on an attachable detached HEAD

The reason is keyed on the container's state, not on the command's words. `checkout -B`
and `switch -C` name the branch, but `git branch -f` does not go through
`switch_target_names`, and a push or a `checkout -b x` names nothing at all. In every one
of those cases the container is in the same state and has the same remedy. So
`cloud_git_deny_reason` reads the head once, and on a detached HEAD it asks
`attachable_branch` before anything else. That probe (`for-each-ref --points-at HEAD
refs/remotes/origin`, then the manifest grep and `merge-base --is-ancestor` for each
candidate) runs only on a refusal from a detached HEAD. The head read was hoisted so the
reason reads it once rather than once per block, which keeps the X5 probe counts as they
were.

## 4. A detached HEAD's switch that moves the tree is now refused (reverses #97 ruling 4)

`cloud-off-branch-remedy` ruling 4 left a detached HEAD's switch silent, because "a branch
it cannot read refuses nothing". That silence is the trap in this shape: a plain
`git checkout claude/pull-agenttooling-pr99` would have gone through and put the working
tree 12 commits back, on the stale local ref. So in the cloud, `cloud_refuses` on a
detached HEAD now asks `detached_switch_moves`. A switch or checkout is refused when it is
`-` or `--orphan`, or when its target resolves (as written, else as `origin/<target>`, the
DWIM `git checkout <x>` would do) to a commit other than HEAD's. These are not refused:

- a switch landing on HEAD's own commit, including the brief's "`git checkout <branch>`
  when the local ref already equals HEAD";
- `git switch --detach`;
- `git checkout origin/<b>` at HEAD;
- a file checkout;
- a target git cannot resolve.

This is a new refusal, which `hook-cloud-profile.sh` O7 now asserts (it asserted the
opposite before). The reason it prints is the attach reason when the state is attachable,
else the off-branch reason when the target is a manifest's branch, else the ordinary cloud
reason.

## 5. session-start.sh replaces the start and restart lines in this shape

On a detached HEAD in the cloud with an attachable branch, `session-start.sh` prints one
line naming the feature, `attach-branch.sh <branch>`, and that a fresh session will not
cure it. It prints that instead of the `--branch <name>` start line and the restart line:
both would send the session the wrong way. The probe is `attachable_branches`, which is
git only, with no network and no fetch. It runs only on a detached HEAD.

## 6. No fetch

Both readings compare HEAD with the remote-tracking ref as the clone has it, with no
fetch. If origin has moved since, attaching is still harmless (nothing moves), and the
next push is an ordinary non-fast-forward the session handles as usual. A fetch would put
network into a SessionStart hook and into a hook reason, which must stay fast.
