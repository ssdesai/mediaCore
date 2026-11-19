Verdict: escalated

# Security audit — own-push-real-gitdir

Scope: the rules this feature's diff adds or changes in `hooks/allow-repo-commands.sh`
(`own_push_allowed`, `own_checkout`, `own_push_config_allows`, `own_push_hooks_absent`) and
their description in `hooks/README.md`. Base `origin/main`, head `HEAD`.

## The rules under attack

1. **Words.** Only the approval `git push [-u|--set-upstream] origin <B>` is narrowed. Nothing may
   come before `push`: no `-C`, `--git-dir`, `--work-tree`, `-c`, or other global option, and
   no env assignment. Anything else prompts.
2. **cwd.** The payload's `cwd`, after realpath, must equal the project root. Otherwise the push
   prompts.
3. **Own git directory.** `own_checkout` walks the filesystem from the root to the nearest `.git`
   entry, which may be a directory or a `gitdir:` file. `git rev-parse --absolute-git-dir
   --show-toplevel`, run from the root, must report the same pair. Otherwise the push prompts.
4. **Effective config.** `git config --list -z` must contain none of `OWN_PUSH_PRESENT_KEYS` or
   `OWN_PUSH_PRESENT_KEY_RES`. `push.default` must be absent, `simple` or `current`. There must
   be exactly one http(s) `remote.origin.url`, and `remote get-url --push --all origin` must
   print it unchanged. Otherwise the push prompts.
5. **Push hooks.** Neither `pre-push` nor `reference-transaction` may exist, as any file type,
   in `<common dir>/hooks/`. Otherwise the push prompts.

## Method

I extracted `git archive HEAD hooks` into the scratch directory and vendored the four hook files
into a throwaway consuming repo `<C>`. `<C>` is on branch `claude/feat-x`, which a committed
manifest names as `branches[0]`. It has a bare local origin, and its origin url was then set to
`https://example.invalid/consumer.git`. I ran the hook with `AGENTTOOLING_PROFILE=cloud`,
`CLAUDE_PROJECT_DIR=<C>`, and a PreToolUse payload (`tool_name`, `session_id`, `agent_id`, `cwd`,
`tool_input.command`) on stdin. I made every config, hook-file and plant mutation in the copy
and undid it after its row. The last row shows the fixture still approves. Separately, a plain
git repo with a submodule (no hook) checked what git 2.43 actually does with each config key the
hook does not read.

In the table, **ALLOW** means approved silently, **prompt** means no output (the human is asked),
and **DENY** means denied with a reason. `<B>` = `claude/feat-x`.

## Results

### Baseline

| Input | Result | Note |
|---|---|---|
| `git push origin <B>` | ALLOW | expected |
| `git push -u origin <B>` | ALLOW | expected |
| `git push origin <B>` after all mutations undone | ALLOW | fixture intact |

### Program spelling and wrappers (rule 1)

| Input | Result | Note |
|---|---|---|
| `./git push origin <B>` | prompt | |
| `plans/git push origin <B>` | prompt | |
| `<C>/plans/git push origin <B>` | prompt | |
| `/usr/bin/git push origin <B>` | prompt | |
| `\git push origin <B>` | ALLOW | bash removes the quoting, so this runs the same `git push origin <B>`: not a bypass |
| `"git" push origin <B>` | ALLOW | same: quote removal |
| `g''it push origin <B>` | ALLOW | same: quote removal |
| `command git …`, `env git …`, `env env git …`, `/usr/bin/env git …` | prompt | |
| `exec git …`, `exec -a git git …`, `nohup git …`, `time git …`, `sudo git …`, `nice git …`, `builtin git …` | prompt | |
| `echo origin <B> \| xargs git push` | prompt | |
| `find . -maxdepth 0 -exec git push origin <B> ;` | prompt | |
| `bash -c 'git push origin <B>'` | DENY | |
| `echo 'git push origin <B>' \| bash` | DENY | |
| `cat <<'EOF' \| sh` + `git push origin <B>` + `EOF` | prompt | |
| `gi?  push …`, `gi[t] push …`, `{git,git} push …` | prompt | |

### Words after `git` (rules 1 and 4)

| Input | Result | Note |
|---|---|---|
| `git "push" origin <B>`, `git pu''sh origin <B>`, `git push 'origin' <B>`, `git push or\igin <B>`, `git push origin '<B>'`, `git push origin "<B>"` | ALLOW | quote removal gives the approved words: not a bypass |
| `git push origin <B> 2>&1` | ALLOW | the same push with a stream merge: not a bypass |
| `git push origin <B> &` | ALLOW | the same push in the background: not a bypass |
| `git push origin <B>\ ` | DENY | |
| `git push orig?n <B>` | prompt | |
| `git push {origin,origin} <B>`, `git push origin {<B>,main}` | DENY | |
| `git push origin <B> main`, `git push origin <B>:main` | DENY | |
| `git push origin +<B>` | prompt | |
| `git push origin <B> --`, `git push -- origin <B>` | prompt | |
| `git push origin <B> --no-verify`, `git push --no-verify origin <B>` | prompt | |
| `git push -u -u origin <B>`, `git push -u --set-upstream origin <B>` | prompt | |
| `git push origin HEAD`, `git push origin @` | prompt | |
| `git push --repo=x origin <B>` | DENY | |
| `git push origin <B> > out.log` | prompt | |
| `git push origin <B>; git push origin main` | DENY | |
| `git push origin <B> && rm -rf x` | DENY | |
| `git push origin <B> \| sh` | DENY | |
| `git push origin $(echo <B>)`, ``git push origin `echo main` ``, `git push origin ${X:-<B>}`, `git push origin $'<B>'` | DENY | |

### Global options and environment before `push` (rule 1)

| Input | Result |
|---|---|
| `git -C . push origin <B>` | prompt |
| `git -C <C> push origin <B>` | prompt |
| `git -C plans push origin <B>` | prompt |
| `git -Cplans push origin <B>` | prompt |
| `git --git-dir=.git push origin <B>` | prompt |
| `git --git-dir .git push origin <B>` | prompt |
| `git --work-tree=. push origin <B>` | prompt |
| `git -c core.sshCommand=x push origin <B>` | prompt |
| `git --exec-path=plans push origin <B>` | prompt |
| `git --namespace=x push origin <B>` | prompt |
| `git --config-env=core.hooksPath=HOME push origin <B>` | prompt |
| `git -p push …`, `git --paginate push …` | prompt |
| `git --no-replace-objects push …`, `git --bare push …`, `git --literal-pathspecs push …` | prompt |
| `GIT_DIR=plans/evil git push origin <B>` | prompt |
| `env GIT_DIR=plans/evil git push origin <B>` | prompt |
| `GIT_SSH_COMMAND=x git push …`, `GIT_CONFIG_COUNT=1 git push …` | prompt |
| `export GIT_DIR=plans/evil; git push origin <B>` | DENY |
| `declare -x GIT_DIR=plans/evil; git push origin <B>` | DENY |
| `export GIT_DIR=plans/evil && git push origin <B>` | prompt |
| `set -a; GIT_DIR=plans/evil; git push origin <B>` | prompt |
| `GIT_DIR=plans/evil; git push origin <B>` | prompt |
| `readonly …; git push …`, `local …; git push …`, `typeset -x …; git push …` | prompt |

### A directory change on the same line (rule 2)

| Input | Result |
|---|---|
| `cd <C>/plans && git push origin <B>` | DENY |
| `cd <C>/plans; git push origin <B>` | DENY |
| `cd <C>/plans \|\| git push origin <B>` | DENY |
| `cd <C>/plans` then a newline, then `git push origin <B>` | DENY |
| `pushd <C>/plans; git push origin <B>` | DENY |
| `(cd <C>/plans; git push origin <B>)` | DENY |
| `{ cd <C>/plans; git push origin <B>; }` | DENY |
| `cd plans && git push origin <B>` | DENY |
| `cd -- <C>/plans && git push origin <B>` | DENY |
| `CDPATH=x cd plans && git push origin <B>` | DENY |
| `git status && cd <C>/plans && git push origin <B>` | DENY |
| `cd <C>/plans \| git push origin <B>` | DENY |
| `cd <C>/plans & git push origin <B>` | DENY |

### Payload `cwd` and malformed fields (rule 2)

| Input (command `git push origin <B>`) | Result | Note |
|---|---|---|
| cwd = `<C>/plans` | prompt | |
| cwd = `<C>/plans/rootlink` (a symlink to `<C>`) | ALLOW | the same physical directory, so git discovers the same `.git`: not a bypass |
| cwd = `<C>/` | ALLOW | the root itself |
| cwd = `<C>/./` | ALLOW | the root itself |
| cwd = `<C>/plans/..` | ALLOW | the root itself |
| cwd missing | prompt | |
| cwd = `7` | prompt | |
| cwd = `[<C>]` | prompt | |
| cwd = `.` | prompt | |
| cwd = `""` | prompt | |
| `tool_input: null` | prompt | |
| `tool_name: "bash"` | prompt | |
| `CLAUDE_PROJECT_DIR=<C>/plans`, cwd = `<C>/plans` | prompt | |
| `CLAUDE_PROJECT_DIR=<C>/plans`, cwd = `<C>` | prompt | |

### Planted git directories (rule 3)

`plans/evil2` is a git directory written as plain files. Its `core.worktree` names `<C>`,
`remote.origin.push` maps `<B>` to `main`, and `objects/info/alternates` points at the real
object store.

| Input | Result | Note |
|---|---|---|
| `git -C plans/evil2 push origin <B>` | prompt | the audit's original gap is closed |
| `git --git-dir=plans/evil2 push origin <B>` | prompt | |
| `GIT_DIR=plans/evil2 git push origin <B>` | prompt | |
| `git push origin <B>` with the plant present | ALLOW | git finds `<C>/.git` first and never reaches the plant: not a bypass |
| plant present, payload cwd = the plant | prompt | |
| plant present, `GIT_DIR=<plant>` in the hook's environment | prompt | |
| plant present, `GIT_COMMON_DIR=<plant>` in the hook's environment | prompt | |
| plant present, `GIT_WORK_TREE=<C>` in the hook's environment | ALLOW | the git directory is unchanged, and the agent cannot set the hook's env |
| `GIT_CONFIG_GLOBAL=<plant>/config` in the hook's environment | prompt | |
| `GIT_CONFIG_PARAMETERS` setting `remote.origin.push` in the hook's environment | prompt | |
| `GIT_CONFIG_PARAMETERS` setting `core.sshcommand` in the hook's environment | prompt | |
| `GIT_NAMESPACE=x` in the hook's environment | ALLOW | the hook's env is not agent-settable; see observations |
| `GIT_EXEC_PATH=<plant>` in the hook's environment | ALLOW | the hook's env is not agent-settable; see observations |
| vendored root `<C>/agentTooling`, clean | prompt | my fixture has no manifest under that root |
| vendored root with a bare shape (`HEAD`, `objects/`, `refs/`, `config`) planted in it | prompt | git would use the plant; the rev-parse comparison catches it |
| a bare shape planted in `<C>` beside `.git` | ALLOW | `.git` takes precedence, so the plant is unused: not a bypass |
| a `.git` file `gitdir: ../.git` in the vendored root (written by the audit; `Edit(**/.git)` denies it to the agent) | prompt | |

### Effective config (rule 4)

The agent cannot write `.git/config`: `Edit(**/.git/**)` denies it, and so do the shell-write
rows. Each row below is a config some other writer set. The rule exists to catch that case.

| Config set in `<C>/.git/config` | Result | What git does with it |
|---|---|---|
| `remote.origin.pushUrl=https://evil.invalid/x.git` | prompt | |
| `remote.origin.push=` (empty) | prompt | |
| `push.default=matching` | prompt | |
| a second `remote.origin.url` | prompt | |
| `core.bare=true` | prompt | |
| `url.https://evil.invalid/.insteadOf=https://example.invalid/` | prompt | |
| `url.https://evil.invalid/.pushInsteadOf=https://example.invalid/con` | prompt | |
| **`submodule.recurse=true`** | **ALLOW** | **BYPASS.** It makes the push recurse into submodules, the same as `push.recurseSubmodules=on-demand`, which the rule prompts on. Verified below. |
| `push.followTags=true` | ALLOW | Verified: an annotated tag is pushed beside `<B>` (`refs/tags/rides`). It reaches tags only, never `main`. Observation. |
| `core.askPass=/bin/true` | ALLOW | It runs a program when credentials are needed. This is the same class as `credential.helper`, which the README excludes on purpose. Observation. |
| `credential.helper=!touch …` | ALLOW | Excluded on purpose (README) |
| `remote.origin.proxy=http://127.0.0.1:9` | ALLOW | It reroutes the push through a proxy, the same class as `http.proxy*`, which is excluded on purpose. Observation. |
| `http.sslVerify=false` | ALLOW | Not a target change on its own. With `remote.origin.proxy` or `http.curloptResolve` it lets a man-in-the-middle receive the push and the credential. Observation. |
| `http.curloptResolve=example.invalid:443:127.0.0.1` | ALLOW | It reroutes the connection's IP. TLS still verifies unless `sslVerify` is off. Observation. |
| `hook.x.event=pre-push` + `hook.x.command=touch …` | ALLOW | Verified: git 2.43 does not run config-based hooks. Observation for newer git. |
| `remote.origin.tagOpt=--tags` | ALLOW | Fetch only |
| `core.pager=…` | ALLOW | Push is not paged unless `pager.push` is set, and that prompts |
| `core.alternateRefsCommand=…` | ALLOW | Used only on the receiving side |
| `Remote.Origin.Push=…` | ALLOW | The subsection is case-sensitive, so this is remote `Origin`, not `origin`: not a bypass |
| `protocol.version=0` | ALLOW | Inert |
| `http.extraHeader=X: y` | ALLOW | Inert |
| `core.worktree=<C>` | ALLOW | The same pair as without it: inert |
| `extensions.worktreeConfig=true` | ALLOW | `config.worktree` is inside `.git` and is read by `--list` |
| `url.https://example.invalid/.insteadOf=https://example.invalid/` | ALLOW | Rewrites the url to itself: inert |
| `branch.<B>.remote=evil` | ALLOW | Verified: with an explicit `origin <B>`, nothing reaches `main` |
| `branch.<B>.merge=refs/heads/main` | ALLOW | Verified under `push.default` simple, current and unset: `main` is never updated |

### Origin url (rule 4)

| `remote.origin.url` | Result | Note |
|---|---|---|
| `https://user:pw@example.invalid/x.git` | ALLOW | http(s), as the rule intends |
| `http://127.0.0.1/x` | ALLOW | http(s), as the rule intends |
| `https://example.invalid/x.git#ext::sh` | ALLOW | an http(s) url, and the fragment is never a transport |
| `HTTPS://example.invalid/x.git` | prompt | |
| `https://example.invalid/x.git` followed by a newline | prompt | |
| `https::/x` | prompt | |
| `https:/example.invalid/x` | prompt | |

### Push hooks (rule 5)

| Mutation in `<C>/.git/hooks` | Result | Note |
|---|---|---|
| `pre-push` file | prompt | |
| `reference-transaction` file | prompt | |
| `pre-push` as a dangling symlink | prompt | |
| `hooks/` replaced by a symlink to a directory holding `pre-push` | prompt | |
| `post-update` file | ALLOW | runs only on the receiving side |
| `push-to-checkout` file | ALLOW | runs only on the receiving side |
| `pre-receive` file | ALLOW | runs only on the receiving side |
| `post-index-change` file | ALLOW | push does not run it |
| `fsmonitor-watchman` file | ALLOW | does not run without `core.fsmonitor`, which prompts |
| detached HEAD | prompt | |

## Bypass

### `submodule.recurse=true` gets past the `push.recurseSubmodules` check

The rule (`OWN_PUSH_PRESENT_KEYS`, README → "the effective config") prompts when
`push.recurseSubmodules` is present in any scope, because a recursing push also runs
`git push` in every submodule's git directory. That directory is `.git/modules/<name>`, with its
own config, its own `core.sshCommand`, its own `remote.origin.push` and its own hooks. The hook
reads none of these. Git's documented default is: "If `push.recurseSubmodules` is not set,
`no` is used by default, unless `submodule.recurse` is set (in which case a `true` value means
`on-demand`)." So `submodule.recurse=true` turns recursion on without the key the rule looks
for.

To reproduce against the hook, use the fixture above (cloud profile, the started feature's own
branch):

```
git -C <C> config submodule.recurse true
payload: {"tool_name":"Bash","cwd":"<C>","tool_input":{"command":"git push origin claude/feat-x"}, …}
→ hook output: permissionDecision "allow"
```

To reproduce in git 2.43.0 without the hook: take a parent repo with a submodule `sub`, make a
commit in `sub` that is not on its origin, and record the new gitlink in the parent. Then run
`git config submodule.recurse true` and `git push origin feat`. Git starts a push process in the
submodule: `fatal: process for submodule 'sub' failed`. In my fixture the push failed only
because the submodule had no branch `feat`. With a matching branch, or any other ref shape the
submodule's own config maps, the push goes through the submodule's own config and hooks. With
the key unset, the same push does not touch the submodule.

**What the rule should do:** treat `submodule.recurse` like `push.recurseSubmodules`, and prompt
when it is present at all. Add `"submodule.recurse"` to `OWN_PUSH_PRESENT_KEYS`, add it to the
README's key list, and add one Q7 row in `self/tests/hook-cloud-profile.sh`.

Reachability: the agent cannot set this key itself. Every scope is behind a write it cannot
make silently: `.git/config`, global config, or the hook's `GIT_CONFIG_*` environment. Writers
of that kind are the case the config check exists for, and `push.recurseSubmodules` has the
same reachability, so the gap counts as a bypass of the rule.

## Observations (not bypasses; for the review to weigh)

- `push.followTags=true` adds annotated tags to the approved push. They are tags only, never a
  branch and never `main`. If the approval is meant to send exactly one ref, consider adding it
  to the key list.
- `core.askPass` and `remote.origin.proxy` are the same class as the deliberately excluded
  `credential.*` and `http.proxy*`. The README's exclusion sentence does not name them, so it
  could name them, or the list could take them.
- Config-based hooks (`hook.<name>.event=pre-push`) do not run on git 2.43, which this container
  ships. A newer git that supports them would run a pre-push command with no file in `hooks/`.
  `own_push_hooks_absent` would miss that, and so would the config check, which does not list
  `hook.*`.
- `GIT_EXEC_PATH` and `GIT_NAMESPACE` in the hook's environment are not checked. The agent
  cannot set the hook's environment, so this is out of scope here.
