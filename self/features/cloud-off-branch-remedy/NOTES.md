# cloud-off-branch-remedy — notes

Rulings made while building this feature by hand, in the order they came up.

## 1. No carve-out: the switch stays refused

The obvious alternative was to let a restarted container's session run
`git checkout <feature-branch>` when a manifest names that branch, since the switch would
put the container back where it belongs. It was deliberately not added:

- **The cloud never switches branches** (`LIFECYCLE.md` rule 2, `policy.CLOUD_SWITCH_AWAY`).
  One exception tied to a manifest's contents is an exception anyone can manufacture: a
  manifest is a file in the tree, and a commit that adds one would turn the refusal into
  an allow for any branch it names.
- **The session's identity is its branch.** The platform launched the session for one
  branch (`outcome_branch`); the transcript, the capture and the cost records follow the
  branch the session reports. Switching in place makes one session span two branches,
  with `main` lines the capture then has to sort out.
- **The remedy is cheap and certain.** A fresh session launched on the branch is the
  standard flow; the human can also check the branch out in the container. Both are
  outside the agent, which is where a decision to move a checkout belongs.

So only the messages changed: the refusal is identical, and its reason now names the
remedy instead of offering the forbidden action.

## 2. The lookup also reads the target's own tree

The spec asked to reuse the existing "tracked manifest names this branch" lookup
(`started_features_on` / the hook's `started_feature`). Over the checkout alone that never
fires in the real case: `feature-start.sh` commits the manifest on the feature's branch,
and a restarted container is on `main`, where the manifest exists only once the feature has
merged. The hook's `started_feature` gained an optional tree: after the checkout's tracked
manifests, it greps the commit the switch would land on (`git grep <tree>`, then
`git show <tree>:<path>`) — the same narrowing and the same fence reader, a second source
rather than a second implementation. The probes run only on the cloud path of a refused
switch or checkout from `main` or a detached HEAD, and any failure falls back to the
ordinary cloud reason.

## 3. session-start.sh keeps to one fixed line

Naming the started branches would need the manifests of every remote branch's tree, not
`main`'s (ruling 2), on every start, resume and compaction of a hook that must stay fast.
The line says what to do without naming the branch; the hook's reason names it the moment
the agent tries to switch.

## 4. A detached HEAD is matched but rarely reached

The off-branch reason applies on `main` or a detached HEAD, as specified. On a detached
HEAD the switch-away rule itself stays silent (a branch it cannot read refuses nothing,
`hooks/README.md`), so the off-branch reason there is reached only through an
always-refused shape such as `git checkout -b <feature-branch> origin/<feature-branch>`.
Changing that would change a refusal, which this feature does not do.

## 5. Child sessions name their model (scope added by the parent session)

`ORCHESTRATION.md` → "Cloud sessions" and `LIFECYCLE.md` → "Propagate" now say to pass
`model` on `create_session` by the repo's tiering, because the 2026-10-27 wave's children
inherited the parent's higher tier by default, for work whose shape was already decided.
Docs only; no code reads it.
