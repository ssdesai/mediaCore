# Checkpoint: own-push-real-gitdir

status: committed
updated: 2026-11-16T15:40:00Z
gate: not run — ran self/tests/hook-cloud-profile.sh (all checks passed), self/tests/allow-repo-commands.sh

## Slices
- [x] acceptance tests — self/tests/hook-cloud-profile.sh (Q7, three table rows flipped, header); committed alone as `own-push-real-gitdir: acceptance tests`; red on main: evil2/evil3 `-C` and GIT_DIR-env rows, `-C <root>`, subdir cwd, every config key, push.default upstream/matching/nothing, url shapes, push hooks
- [x] 1. hooks/allow-repo-commands.sh: own_checkout, own_push_config_allows, own_push_hooks_absent, git_probe_text, OWN_PUSH constants
- [x] 2. applied to the real hooks/ files by Edit; both test files re-run there
- [x] 3. docs: hooks/README.md, README.md, CONVENTIONS.md, self/tests/README.md, NOTES build rulings B1-B8
- [x] commit

## Learned
- the test file is bash wrapping one python heredoc; `AT` is two dirs above the script, so a scratch copy tests its own hook
- the evil2 plant needs `core.repositoryformatversion = 0` or git 2.43 ignores `core.worktree` there
- a test file takes ~10 minutes; pipe through grep and run in the background
- fixtures with no origin (Q5's WD) needed an https origin added: the approval now requires one

## Resume
- `bash /home/user/agentTooling/self/tests/hook-cloud-profile.sh | grep -v "^  ok"`, then allow-repo-commands.sh, then the coordinator's gate
