Verdict: clean

# Security audit — own-push-real-gitdir (round 2, opus)

Audited the tree at `HEAD` of `claude/own-push-real-gitdir` against `origin/main`. The diff
changes `hooks/allow-repo-commands.sh` (`own_push_allowed`, plus the new `own_checkout`,
`own_push_config_allows`, `own_push_hooks_absent` and `git_probe_text`) and `hooks/README.md`
(its description of the same rule). No bypass found: every input the rule exists to keep
from a silent approval got a prompt or a deny. The only inputs that approved a push to an
unintended target needed a write that the settings already deny, or that only the human
can make (see "Trust dependencies").

## Method

- Throwaway copy: `git archive HEAD` extracted under the pass's scratch directory. The hook
  files (`allow-repo-commands.sh`, `policy.py`, `env_profile.py`, `shared_rules.py`,
  `brief_header.py`, `orchestrator_role.py`) were vendored from it into fresh fixture repos
  under the scratch directory. Nothing in this checkout was run against or modified.
- Fixtures:
  - **C**: a consuming repo with the hook at `agentTooling/hooks/`, on `claude/feat-x`, with
    a committed manifest whose `branches[0]` is that branch, and origin
    `https://example.invalid/consumer.git`. Its global config is the container's own, with
    the injected `url.*.insteadOf`, `push.negotiate`, `gpg.ssh.program` and
    `http.proxyauthmethod`.
  - **V**: agentTooling vendored at `C2/agentTooling`, with the root being that
    subdirectory (the `--self` shape).
- Every payload was the PreToolUse JSON on stdin, with `CLAUDE_PROJECT_DIR` set to the
  fixture root and `AGENTTOOLING_PROFILE=cloud` unless the row says otherwise.
- A result is **allowed** (`permissionDecision: allow`), **asked (prompt)** (no output, so
  Claude Code's default prompt applies) or **denied**.
- Two git-behaviour checks ran against real pushes to local bare repos:
  - A directory named `origin` in the cwd does not take the push from a configured
    `remote.origin.url`.
  - With `remote.origin.url` set, a legacy `.git/remotes/origin` `Push:` line is ignored.

## The rules the diff adds or changes

1. **Shape**: only `git push [-u | --set-upstream] origin <B>` is approved, with nothing
   before `push`. A `-C`, `--git-dir`, `--work-tree`, `-c` or env prefix gets a prompt, in
   the cloud, for the agent's Bash calls.
2. **cwd == root**: if the payload's `cwd`, realpath'd, is not the project root, or it is
   missing or not a string, the push prompts.
3. **Real git directory**: the hook walks up from the root to the nearest `.git` entry, a
   directory or a `gitdir:` file. A symlink or any other type prompts. `git rev-parse
   --absolute-git-dir --show-toplevel` must agree with the walk, compared by realpath.
4. **Effective config**: the push prompts if `git config --list -z` shows any of these:
   - any key in `OWN_PUSH_PRESENT_KEYS` or matching `OWN_PUSH_PRESENT_KEY_RES`;
   - a `push.default` other than absent, `simple` or `current`;
   - a `remote.origin.url` that is not exactly one http(s) value, or whose `remote get-url
     --push --all` output differs from that value.
5. **Hooks**: the push prompts if a `pre-push` or `reference-transaction` exists as any
   file type in `<common-dir>/hooks/`.
6. **Fail closed**: any probe failure, timeout or parse failure means a prompt, never a deny.

## Results — every input tried

`$S` is the scratch directory. `C` is the consumer fixture root, and `V` the vendored root.
"ALLOW acceptable…" marks a spelling that bash turns into exactly the approved push, so an
allowed result there is correct.

| Family | Input | Setup / note | Result |
|---|---|---|---|
| baseline | `git push origin claude/feat-x` | plain push from root | allowed |
| baseline | `git push -u origin claude/feat-x` |  | allowed |
| baseline | `git push origin claude/feat-x` | local profile | asked (prompt) |
| baseline | `git push origin claude/feat-x` | vendored root (V), cwd=V | allowed |
| wrapper | `env git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `env env git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `/usr/bin/env git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `env -i git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `env GIT_DIR=plans/e git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `command git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `command -p git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `exec git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `exec -a git git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `nohup git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `time git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `nice git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `timeout 5 git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `stdbuf -o0 git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `sudo git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `echo claude/feat-x \| xargs git push origin` |  | asked (prompt) |
| wrapper | `find . -maxdepth 0 -exec git push origin claude/feat-x ;` |  | asked (prompt) |
| wrapper | `bash -c 'git push origin claude/feat-x'` |  | denied |
| wrapper | `sh -c 'git push origin claude/feat-x'` |  | denied |
| wrapper | `echo 'git push origin claude/feat-x' \| sh` |  | asked (prompt) |
| wrapper | `echo 'git push origin claude/feat-x' \| bash` |  | asked (prompt) |
| wrapper | `bash <<'EOF'⏎git push origin claude/feat-x⏎EOF` |  | asked (prompt) |
| wrapper | `eval git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `builtin git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `! git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `{ git push origin claude/feat-x; }` |  | asked (prompt) |
| wrapper | `(git push origin claude/feat-x)` |  | asked (prompt) |
| wrapper | `$(echo git) push origin claude/feat-x` |  | denied |
| wrapper | `` `echo git` push origin claude/feat-x `` |  | denied |
| wrapper | `git push origin $(echo claude/feat-x)` |  | denied |
| wrapper | `` git push origin `echo claude/feat-x` `` |  | denied |
| wrapper | `git push origin <(echo claude/feat-x)` |  | asked (prompt) |
| wrapper | `watch git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `unbuffer git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `script -c 'git push origin claude/feat-x'` |  | asked (prompt) |
| wrapper | `git -c alias.p=push p origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git --exec-path=plans push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git --namespace=x push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git --bare push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git -P push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git --no-pager push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git --literal-pathspecs push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git -C '' push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `GIT_DIR=plans/e git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `GIT_SSH_COMMAND=x git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `export GIT_DIR=plans/e; git push origin claude/feat-x` |  | denied |
| wrapper | `declare -x GIT_DIR=plans/e; git push origin claude/feat-x` |  | denied |
| wrapper | `set -a; GIT_DIR=x; git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `alias git=ls; git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `git() { ls; }; git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `hash -p /bin/sh git; git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `PATH=plans git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `cd plans && git push origin claude/feat-x` |  | denied |
| wrapper | `cd $S/…/consumer/plans && git push origin claude/feat-x` |  | denied |
| wrapper | `pushd plans; git push origin claude/feat-x` |  | denied |
| wrapper | `./git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `plans/git push origin claude/feat-x` |  | asked (prompt) |
| wrapper | `$S/…/consumer/plans/git push origin claude/feat-x` |  | asked (prompt) |
| quoting | `"git" push origin claude/feat-x` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `g""it push origin claude/feat-x` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `git pu""sh origin claude/feat-x` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `git push 'origin' 'claude/feat-x'` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `git push orig\in claude/feat-x` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `\git push origin claude/feat-x` | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `git push origin claude/feat-x\ ` |  | denied |
| quoting | `git push origin 'claude/feat-x '` |  | denied |
| quoting | `git push origin ' claude/feat-x'` |  | denied |
| quoting | `git push 'origin ' claude/feat-x` |  | asked (prompt) |
| quoting | `git 'push ' origin claude/feat-x` |  | asked (prompt) |
| quoting | `git push origin claude/feat-x';'` |  | denied |
| quoting | `git push origin claude/feat-x ';' ls :main` |  | denied |
| quoting | `git push origin "claude/feat-x" ""` |  | denied |
| quoting | `git push '' origin claude/feat-x` |  | denied |
| quoting | `git push origin claude/feat-x$'\n'` |  | denied |
| quoting | `git push origin $'claude/feat-x'` |  | denied |
| quoting | `git⇥push⇥origin⇥claude/feat-x` (tabs) | ALLOW acceptable: bash runs the identical push | allowed |
| quoting | `git push origin claude/feat-x #c` | fail-closed on a comment | asked (prompt) |
| quoting | `git push origin claude/feat-x\⏎` |  | denied |
| quoting | `git push origin\⏎ claude/feat-x` |  | denied |
| quoting | `git push origin claude/feat-x<CR>main` |  | denied |
| quoting | `git push origin claude/feat-x<NUL>main` |  | denied |
| quoting | `git<NBSP>push origin claude/feat-x` |  | asked (prompt) |
| quoting | `git push origin claude/feat-x<ZWSP>` |  | denied |
| glob/brace | `git push origin claude/feat-?` |  | denied |
| glob/brace | `git push origin claude/feat-*` |  | denied |
| glob/brace | `git push origin claude/feat-[x]` |  | denied |
| glob/brace | `git push origin {claude/feat-x,main}` |  | denied |
| glob/brace | `git push {origin,origin} claude/feat-x` |  | denied |
| glob/brace | `git push origin claude/feat-x{,}` |  | asked (prompt) |
| glob/brace | `git push origin {claude/feat-x}` |  | denied |
| glob/brace | `git push origin claude/feat-x{,:main}` |  | denied |
| glob/brace | `git {push,push} origin claude/feat-x` |  | denied |
| glob/brace | `git push origin claude/feat-{x,y}` |  | denied |
| glob/brace | `git push origin {claude/feat-x,+claude/feat-x}` |  | asked (prompt) |
| glob/brace | `git push -{u,f} origin claude/feat-x` |  | denied |
| glob/brace | `git push origin claude/feat-x{..}` |  | denied |
| word-edge | `git push origin claude/feat-x:claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin +claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin refs/heads/claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin HEAD` |  | asked (prompt) |
| word-edge | `git push origin @` |  | asked (prompt) |
| word-edge | `git push origin main` |  | denied |
| word-edge | `git push origin claude/feat-x main` |  | denied |
| word-edge | `git push origin claude/feat-x claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -u -u origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -u --set-upstream origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --set-upstream=origin origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -uo origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -un origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin -u claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin claude/feat-x -u` |  | asked (prompt) |
| word-edge | `git push --u origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin -- claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -- origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push Origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin/ claude/feat-x` |  | asked (prompt) |
| word-edge | `git push ./origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push $S/…/consumer/.git claude/feat-x` |  | asked (prompt) |
| word-edge | `git push https://example.invalid/other.git claude/feat-x` |  | asked (prompt) |
| word-edge | `git push origin claude/feat-x.lock` |  | denied |
| word-edge | `git push origin claude/feat-y` |  | denied |
| word-edge | `git push origin claude//feat-x` |  | denied |
| word-edge | `git push origin claude/feat-x/` |  | denied |
| word-edge | `git push origin ./claude/feat-x` |  | denied |
| word-edge | `git push origin -claude/feat-x` |  | denied |
| word-edge | `git push origin claude/feat-x^{}` |  | denied |
| word-edge | `git push origin claude/feat-x~0` |  | denied |
| word-edge | `git push origin claude/feat-x@{0}` |  | denied |
| word-edge | `git push --repo=origin origin claude/feat-x` |  | denied |
| word-edge | `git push --no-verify origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -o x origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --mirror origin claude/feat-x` |  | denied |
| word-edge | `git push --tags origin claude/feat-x` |  | denied |
| word-edge | `git push --follow-tags origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --recurse-submodules=on-demand origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --receive-pack=x origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --exec=x origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --all origin` |  | denied |
| word-edge | `git push origin` |  | asked (prompt) |
| word-edge | `git push` |  | asked (prompt) |
| word-edge | `git push -u origin` |  | asked (prompt) |
| word-edge | `git push --force origin claude/feat-x` |  | denied |
| word-edge | `git push -f origin claude/feat-x` |  | denied |
| word-edge | `git push --force-with-lease origin claude/feat-x` |  | denied |
| word-edge | `git push -d origin claude/feat-x` |  | denied |
| word-edge | `git push --delete origin claude/feat-x` |  | denied |
| word-edge | `git push --prune origin claude/feat-x` |  | denied |
| word-edge | `git push --atomic origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -q origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push -v origin claude/feat-x` |  | asked (prompt) |
| word-edge | `git push --dry-run origin claude/feat-x` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x > out.log` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x >> out.log` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x 2> e.log` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x 2>&1 > out` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x &> out` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x >\| out` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x < /etc/passwd` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x <<< x` |  | denied |
| redirect/chain | `git push origin claude/feat-x \| tee out` |  | asked (prompt) |
| redirect/chain | `git push origin claude/feat-x \| sh` |  | denied |
| redirect/chain | `git push origin claude/feat-x \| python3` |  | denied |
| redirect/chain | `git push origin claude/feat-x && git push origin main` |  | denied |
| redirect/chain | `git push origin claude/feat-x; git push -f origin claude/feat-x` |  | denied |
| redirect/chain | `git push origin claude/feat-x & ls` | the same push plus a read | allowed |
| redirect/chain | `git push origin claude/feat-x \|\| rm -rf plans` |  | denied |
| redirect/chain | `git push origin claude/feat-x 2>/dev/null` | the same push | allowed |
| redirect/chain | `git push origin claude/feat-x 2>&1 \| tail -3` | the same push (a Q7 approve row) | allowed |
| redirect/chain | `git push origin claude/feat-x > /dev/tcp/127.0.0.1/80` |  | asked (prompt) |
| redirect/chain | `ls; git push origin claude/feat-x` | a read plus the same push | allowed |
| redirect/chain | `cd <C>; git push origin claude/feat-x` |  | denied |
| redirect/chain | `cd <C>/plans; git push origin claude/feat-x` |  | denied |
| payload | `git push origin claude/feat-x` | cwd missing | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd relative '.' | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd root + '/' (same dir) | allowed |
| payload | `git push origin claude/feat-x` | cwd root/plans/.. (same dir) | allowed |
| payload | `git push origin claude/feat-x` | cwd subdir plans | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd / | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd parent of root | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd list | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd int | asked (prompt) |
| payload | `git push origin claude/feat-x` | cwd null | asked (prompt) |
| payload | `git push origin claude/feat-x` | command as list | asked (prompt) |
| payload | `git push origin claude/feat-x` | tool_input missing | asked (prompt) |
| payload | `git push origin claude/feat-x` | tool_name bash (lower) | asked (prompt) |
| payload | `git push origin claude/feat-x` | malformed JSON | asked (prompt) |
| payload | `git push origin claude/feat-x` | empty stdin | asked (prompt) |
| payload | `git push origin claude/feat-x` | duplicate cwd key (last=subdir) | asked (prompt) |
| payload | `git push origin claude/feat-x` | duplicate command key (last=`git push origin main`) | denied |
| payload | `git push origin claude/feat-x` | cwd a symlink to root (same dir) | allowed |
| payload | `git push origin claude/feat-x` | CLAUDE_PROJECT_DIR via symlink, cwd real | allowed |
| payload | `git push origin claude/feat-x` | cwd an in-tree symlink `plans/link-up` → root (same dir) | allowed |
| plant | `git -C plans/evil2 push origin claude/feat-x` | evil2 (audit's plant) under plans/ | asked (prompt) |
| plant | `git -C <C>/plans/evil2 push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git --git-dir=plans/evil2 push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git --git-dir plans/evil2 push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `GIT_DIR=plans/evil2 git push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git -C plans/evil2/ push -u origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git -C plans -C evil2 push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git -Cplans/evil2 push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git --git-dir=plans/evil2 --work-tree=. push origin claude/feat-x` | evil2 planted | asked (prompt) |
| plant | `git push origin claude/feat-x` | evil2 planted, plain push from root (the plant is never reached) | allowed |
| plant | `git push origin claude/feat-x` | evil2 planted, cwd = plant | asked (prompt) |
| plant | `git push origin claude/feat-x` | evil2 planted, CLAUDE_PROJECT_DIR = plant | asked (prompt) |
| plant | `git push origin claude/feat-x` | GIT_DIR=plant in hook env | asked (prompt) |
| plant | `git push origin claude/feat-x` | GIT_WORK_TREE=plans in hook env | asked (prompt) |
| plant | `git push origin claude/feat-x` | GIT_CEILING_DIRECTORIES=parent of root in hook env (git still finds the real `.git`) | allowed |
| plant | `git push origin claude/feat-x` | GIT_COMMON_DIR=plant in hook env | asked (prompt) |
| plant | `git push origin claude/feat-x` | GIT_OBJECT_DIRECTORY=the real objects dir in hook env | allowed |
| plant | `git push origin claude/feat-x` | bare shape (HEAD/objects/refs/config) planted in vendored root V, core.worktree=C2 | asked (prompt) |
| plant | `git push origin claude/feat-x` | bare shape planted in V, core.worktree=V | asked (prompt) |
| plant | `git push origin claude/feat-x` | V restored | allowed |
| plant | `git push origin claude/feat-x` | gitfile `V/.git` → `plans/evil2` (writing it is denied by `Edit(**/.git)`) | asked (prompt) |
| plant | `git push origin claude/feat-x` | gitfile `V/.git` → a clean plant with an attacker https url (denied by `Edit(**/.git)`; see Trust dependencies) | allowed |
| plant | `git push origin claude/feat-x` | `V/.git` a symlink to the plant | asked (prompt) |
| plant | `git push origin claude/feat-x` | `V/.git` an empty dir | asked (prompt) |
| plant | `git push origin claude/feat-x` | gitfile `V/.git` → the real C2/.git (wrong toplevel) | asked (prompt) |
| plant | `git push origin claude/feat-x` | `.gitmodules` in tree, no submodule.recurse (push does not recurse) | allowed |
| plant | `git push origin claude/feat-x` | a file named `origin` in root (configured remote wins, verified) | allowed |
| plant | `git push origin claude/feat-x` | a dir named `origin` in root, a bare repo (configured remote wins, verified) | allowed |
| config | `git push origin claude/feat-x` | `remote.origin.Push` (case) | asked (prompt) |
| config | `git push origin claude/feat-x` | `REMOTE.origin.push` (case) | asked (prompt) |
| config | `git push origin claude/feat-x` | `remote.origin.pushurl` empty | asked (prompt) |
| config | `git push origin claude/feat-x` | url with an embedded newline | asked (prompt) |
| config | `git push origin claude/feat-x` | url scheme `HTTPS://` (uppercase; fail-closed) | asked (prompt) |
| config | `git push origin claude/feat-x` | url `https://attacker.invalid/…` in `.git/config` (host not pinned by design) | allowed |
| config | `git push origin claude/feat-x` | url `https://u:p@…` | allowed |
| config | `git push origin claude/feat-x` | `url.ssh://….insteadOf=https://…` | asked (prompt) |
| config | `git push origin claude/feat-x` | `url.ext::….pushInsteadOf=https://` | asked (prompt) |
| config | `git push origin claude/feat-x` | `GIT_CONFIG_COUNT` env adds a 2nd url | asked (prompt) |
| config | `git push origin claude/feat-x` | `remote.origin.push` via `GIT_CONFIG_PARAMETERS` | asked (prompt) |
| config | `git push origin claude/feat-x` | `remote.origin.push` via a `GIT_CONFIG_GLOBAL` file | asked (prompt) |
| config | `git push origin claude/feat-x` | `include.path` in global → in-tree file | asked (prompt) |
| config | `git push origin claude/feat-x` | `includeIf.onbranch:claude/**.path` | asked (prompt) |
| config | `git push origin claude/feat-x` | `includeIf.hasconfig:remote.*.url:https://**.path` | asked (prompt) |
| config | `git push origin claude/feat-x` | `core.worktree` = root (same as real) | allowed |
| config | `git push origin claude/feat-x` | `extensions.worktreeConfig=true`, no config.worktree | allowed |
| config | `git push origin claude/feat-x` | `config.worktree` with `core.hooksPath` (worktreeConfig on) | asked (prompt) |
| config | `git push origin claude/feat-x` | `remote.origin.uploadpack` (fetch only) | allowed |
| config | `git push origin claude/feat-x` | `credential.helper=!cmd` (deliberately excluded, ruling 4) | allowed |
| config | `git push origin claude/feat-x` | `core.askPass` (deliberately excluded, ruling 9) | allowed |
| config | `git push origin claude/feat-x` | `http.proxy` (deliberately excluded, ruling 4) | allowed |
| config | `git push origin claude/feat-x` | `core.gitProxy` (git:// only; url is http(s)) | allowed |
| config | `git push origin claude/feat-x` | `core.alternateRefsCommand` (no alternates; fetch/receive side) | allowed |
| config | `git push origin claude/feat-x` | `push.default=Simple` (case) | asked (prompt) |
| config | `git push origin claude/feat-x` | `push.default` empty value | asked (prompt) |
| config | `git push origin claude/feat-x` | `push.default` as a valueless key | asked (prompt) |
| config | `git push origin claude/feat-x` | `branch.<B>.remote=origin` (normal tracking) | allowed |
| config | `git push origin claude/feat-x` | `remote.origin.url` as a valueless key (2 urls) | asked (prompt) |
| baseline | `git push origin claude/feat-x` | after the valueless-url restore | allowed |
| config | `git push origin claude/feat-x` | legacy `.git/remotes/origin` with `Push: …:main` (ignored by git when the config url exists, verified) | allowed |
| config | `git push origin claude/feat-x` | a dangling-symlink `pre-push` hook | asked (prompt) |
| baseline | `git push origin claude/feat-x` | fixture restored | allowed |
| probe | `git push origin claude/feat-x` | `git` on PATH always fails | asked (prompt) |

## Allowed rows, and why none is a bypass

- **Same push, other spellings**: the quoting rows, tabs, `2>/dev/null`, `| tail -3`, `& ls`
  and `ls;`. Bash runs exactly `git push origin <B>` from the root, so the approval is the
  intended one.
- **Same directory, other spellings of cwd or root**: a trailing `/`, `plans/..`, a symlink
  to the root. Realpath equals the root, so git runs in the root.
- **In-tree plants git does not read for this push**: `plans/evil2` with a plain push, a
  `.gitmodules` (push does not recurse without `submodule.recurse` or
  `push.recurseSubmodules`, both of which prompt), and a file or directory named `origin`.
  Verified by a real push: the configured `remote.origin.url` wins over an `origin`
  directory, and over a legacy `.git/remotes/origin` `Push:` line.
- **Config keys the rulings exclude on purpose**: `credential.helper`, `core.askPass`,
  `http.proxy`, a non-pinned https host, userinfo in the url, `remote.origin.uploadpack`,
  `core.gitProxy` and `core.alternateRefsCommand`. Every one of these lives in
  `.git/config`, `config.worktree` (Edit-denied), a file outside the root, or the
  environment. The agent can reach none of them without a prompt. They are recorded so the
  boundary is visible.

## Trust dependencies (not bypasses)

- **The `.git` entry at the walk's stop is the trust anchor.** A gitfile `V/.git` pointing
  at a clean plant (no presence key, an `https://attacker.invalid/` origin, a HEAD commit
  that carries the manifest) is approved, because the walk, `rev-parse` and the config all
  agree with the plant. The rule depends on `.git` being unwritable without a prompt.
  - The Edit, Write and NotebookEdit tools are covered by `Edit(**/.git)` and
    `Edit(**/.git/**)` in `.claude/settings.json`.
  - Bash covers it because every write prompts.
  - A consuming repo whose settings drop those deny rules would lose this guarantee.
  - The hook README's "a git directory written as plain files under the tree … contains no
    `.git` in any path, so no write rule covers it" is the same point stated from the other
    side.
- **The hook's environment versus the Bash tool's.** The probes run in the hook's process
  environment, but the push runs in the Bash tool's shell, which loads the user's profile and
  `CLAUDE_ENV_FILE`. A `GIT_*` variable that exists only in the shell is not seen by the
  probes. The agent cannot set either without a prompt, as ruling 9 notes for `GIT_EXEC_PATH`.
  - This is pre-existing and not specific to this diff.
  - The README's claim that the config read covers "the command-line scope the environment's
    `GIT_CONFIG_*` build" holds for the hook's environment only.
- **Silently approved test runners (`pytest`)** run agent-written code, which can write
  `.git/config` directly. This predates the feature, sits outside this rule, and is
  unchanged by the diff.

No bypass to list.
