# Notes: own-push-real-gitdir

Rulings, with a one-line reason each. The coordinator's come first; the implementer
appends its own under "Build rulings" as it makes them.

## Source

A security audit in humanNetworkMap (`plans/features/pull-agenttooling-pr141/escalations/03-audit-opus.md`,
on its branch `claude/pull-agenttooling-pr141`), auditing agentTooling main df98316, found
that `own_push_allowed` trusts a git directory planted in the tree:

- **evil2.** Plain files under `plans/evil2/` (`HEAD` = `ref: refs/heads/<B>`,
  `objects/info/alternates` = `<root>/.git/objects`, `refs/heads/<B>` = a commit id, and a
  `config` with `core.bare = false`, `core.worktree = <root>`, `remote.origin.url = <real
  origin>`, `remote.origin.push = refs/heads/<B>:refs/heads/main`). Git reads the directory
  as a bare gitdir, and `core.worktree` makes `--show-toplevel` report the root.
  `git -C plans/evil2 push origin <B>` (and the absolute `-C` and the `-u` forms) was
  approved silently, and it moved `main` on the scratch remote.
- **evil3.** The same plant with an `ssh://` origin and `core.sshCommand = touch <S>/PWNED_SSH ; false`.
  The approved push ran the command.
- No path in the plant holds `.git`, so `Edit(**/.git/**)` does not cover it, and under
  acceptEdits it is written with no prompt.

## Coordinator rulings

1. **The approved shape is exactly `git push [-u | --set-upstream] origin <B>`, with nothing
   before `push`.** No `-C`, `--git-dir`, `--work-tree`, `-c` or any other global option.
   The payload's `cwd`, realpath'd, must equal the project root (`root`).
   Why: every location option moves the git directory. A literal-shape rule is simpler to
   hold than judging where a location resolves. `git -C <root> push …` now prompts, and so
   does a push from a subdirectory of the root. That is an intended narrowing (owner's
   condition 1). `hook-cloud-profile.sh` rows 1043, 1044 and 1067 flip from ALLOW to prompt.
2. **The hook finds the root checkout itself, by walking the filesystem, not by asking git.**
   The checkout is the nearest directory at or above `root` that holds a `.git` entry. Its
   expected gitdir:
   - `.git` is a directory: that directory.
   - `.git` is a regular file: the path on its `gitdir: <path>` line, resolved against the
     checkout directory when relative. This is the worktree case.
   - Anything else, or an unreadable file: prompt.

   Then `git rev-parse --absolute-git-dir --show-toplevel`, run in `root` with the hook's own
   environment, must give that gitdir and that checkout directory, both compared by realpath.
   Why: `core.worktree` makes git's toplevel lie (the audit). A bare-repo shape planted in
   the root itself (`HEAD`, `objects/`, `refs/` in a vendored `agentTooling/`) is discovered
   by git before it walks up, and this comparison catches that too. A `GIT_DIR` in the
   hook's environment gives a mismatch, so it prompts. The vendored `--self` case (the root
   is a subdirectory of the checkout, and the push runs from it) keeps its approval.
3. **The branch rules are unchanged.** `<B>` is a plain name (`OWN_PUSH_BRANCH_RE`), never
   `HEAD`, `@`, `refs/heads/…`, `+…`, `…:…` or `main`. It is the current branch, and
   `branches[0]` of the manifest committed at `HEAD`. `GIT_NO_REPLACE_OBJECTS` stays.
4. **Effective config, read once with `git config --list -z` in `root`.** That reading
   covers every scope: system, global, the real `.git/config`, `config.worktree`, includes,
   and the `GIT_CONFIG_*` command-line scope from the environment. A non-zero exit, a
   timeout, or a record that does not parse means a prompt. Keys are compared as git
   normalises them: section and key lower-case, subsection as written.
   - **Present at all means a prompt** (named constants, one set plus regexes):
     - `remote.origin.push`
     - `remote.origin.pushurl`
     - `remote.origin.receivepack`
     - `remote.origin.vcs` (runs a `git-remote-<vcs>` helper)
     - `remote.origin.mirror`
     - `remote.pushdefault`
     - `branch.<any>.pushremote`
     - `core.sshcommand`
     - `core.hookspath`
     - `core.fsmonitor`
     - `push.recursesubmodules`
     - `push.gpgsign`
     - `include.path`
     - `includeif.<any>.path` (the included file could be in the tree and change between
       the probe and the push)

     The implementer checks this list against git 2.43's `git help config` and `git help
     push`. It may ADD a key that redirects or executes during a push, with a NOTES line
     each. It removes none.
   - **`push.default`** must be absent, `simple` or `current`. Any other value prompts. With
     an explicit `<B>` it should change nothing, but the owner listed it, and fail-closed
     costs nothing here.
   - **URL.** `remote.origin.url` must have exactly one value, and its scheme must be
     `https://` or `http://`. Then `git remote get-url --push --all origin` must print
     exactly one line, equal to that value. This is how `url.*.insteadOf` and
     `url.*.pushInsteadOf` are judged: a rewrite that applies to this URL prompts, and one
     that does not apply does not.

     Why not "prompt if present": every cloud container injects
     `url.https://github.com/.insteadof=git@github.com:` and `…=ssh://git@github.com/` in
     the command-line scope (seen in this container's `git config --list --show-origin`). A
     presence rule would prompt on every real push. A two-value url prompts because git
     pushes to every url. The scheme rule shuts out `ssh://`, `ext::`, `fd::` and local
     paths, so evil3's route is closed twice.
   - **Hooks.** `<git rev-parse --git-common-dir>/hooks/pre-push` or
     `…/reference-transaction` existing, as any file type, means a prompt. These are the two
     hooks a push runs locally. `core.hookspath` already prompts, so the default hooks
     directory is the only one to look in.
   - **Deliberately not checked:** `credential.helper`, `http.proxy*`, `gpg.*` and
     `user.*`. None of them changes the push's target, and the cloud sets some of them
     legitimately (`gpg.ssh.program` and `http.proxyauthmethod` here). The places they can
     come from are `.git/config` (Edit-denied), files outside the root, or the environment.
5. **Fail closed, cheap first.** Order: the words, then the profile, then `cwd == root`, then
   the filesystem walk, then the git probes. Every probe is bounded by
   `GIT_PROBE_TIMEOUT_SECONDS`. Any exception or unexpected output approves nothing (the
   existing `except Exception` at the call site stays). The answer is the prompt, never a
   deny: nothing here adds a deny.
6. **Tests go in `self/tests/hook-cloud-profile.sh`, beside Q5 and Q6, and are seen red on
   main before the fix.**
   - evil2 and evil3, planted as the audit planted them, both `-C` spellings and `-u`. The
     plant's url is https in evil2, so it is red on main through the gitdir alone.
   - One row per condition above, each set in the fixture's real `.git/config` or hooks
     directory and then restored.
   - The approvals that must hold: the plain push, `-u`, `--set-upstream`, a chain with a
     read, `push.default=simple`, and the cloud's own non-applying `insteadOf`.
   - Fixture C's origin is a local path, so the approve rows need it set to a fixed https
     URL (a named constant) after the setup's last fetch. The implementer checks that no
     later section fetches through it.
7. **Docs.**
   - `hooks/README.md` → "The one cloud approval" is rewritten to these conditions. It
     claims only what a gate test proves.
   - `CONVENTIONS.md`'s push sentence says the push is run from the project root.
   - The root `README.md` line that names `own_push_allowed`, and `self/tests/README.md`'s
     entry for the file, are brought in line.
8. **Out of scope:** the read-only git approvals in a planted gitdir. The audit shows
   `git -C plans/evil status`, `diff --no-index`, `cd plans/evil` + `git status`, and
   `git --git-dir=plans/evil2 log` running `core.fsmonitor`/`diff.external`. That is already
   on main and is not this gap. It goes to `self/BACKLOG.md`.

9. **Round 1's triage** (`escalations/01-review-opus.md`, `escalations/01-audit-opus.md`).
   Convergence rule: fix only a silent approval or a regression against origin/main.
   - **Taken, as presence keys (prompt when present at all):**
     - `submodule.recurse`. Both passes found it. Git reads it as
       `push.recurseSubmodules=on-demand` when that key is unset, so the push runs inside a
       submodule's own gitdir, config and hooks.
     - `push.followtags`. It pushes annotated tags beside `<B>`. The approval is for one ref,
       per condition 3.
     - `hook.<name>.event` and `hook.<name>.command` (regex). These are config-based hooks.
       Git 2.43 ignores them, but a newer git runs a `pre-push` command with no file in
       `hooks/`. This is the same reason `own_push_hooks_absent` exists.
   - **Docs only:** `core.askPass` and `remote.origin.proxy`. They are the same class as the
     deliberately excluded `credential.helper` and `http.proxy*`: they run on credential need,
     or reroute transport under TLS. The exclusion sentence in `hooks/README.md` names them.
   - **Not taken:**
     - `http.sslVerify` and `http.curloptResolve`. Neither changes the target. They come from
       the same Edit-denied or outside-root sources as the rest of the excluded class.
     - `GIT_EXEC_PATH` and `GIT_NAMESPACE` in the hook's environment. The agent cannot set
       the hook's environment.

## Build rulings

B1. **Key list checked against git 2.43; one key added, `pager.push`.** The container has no git
    man pages, so the check is from git's documented config and push behaviour: `pager.<cmd>` set
    to a program makes git pipe that command's output through it, and `git push` is a command,
    so a planted value runs a program. Added to `OWN_PUSH_PRESENT_KEYS` with its own Q7 row. Every
    other key that redirects (`remote.origin.*`, `remote.pushdefault`, `branch.<n>.pushremote`,
    `url.*` via the get-url check) or executes (`core.sshcommand`, `core.hookspath`,
    `core.fsmonitor`, `push.recursesubmodules`, `push.gpgsign`, includes) was already in ruling 4.
B2. **`push.negotiate` (set `true` in this container's global config) is not checked.** It changes
    how the client negotiates over http(s), not the target or a program, so a presence rule would
    prompt every real push here; the tests run with it set and the approve rows prove it.
B3. **`gpg.ssh.program`, `http.proxyauthmethod` and the injected `url.*.insteadOf` stay allowed**,
    as ruling 4 says; the approve rows run with all three.
B4. **A payload with no string `cwd` prompts.** Ruling 1 reads the payload's cwd, and the old
    fallback to the project root would let a missing field stand for the check; fail closed.
B5. **A `.git` that is a symlink prompts, as does any `.git` that is neither a directory nor a
    regular file.** Ruling 2 names only the directory and the regular file; a link is "anything
    else" and nothing legitimate is one.
B6. **`git_probe` is split in two**: `git_probe_text` returns the whole stdout (`config --list -z`
    needs the NUL-separated records `splitlines` would break), `git_probe` keeps its signature and
    result on top of it. Same bounds, same failure answer (None).
B7. **The evil2 plant needs `core.repositoryformatversion = 0` in its config.** Without it git 2.43
    ignores `core.worktree` in a discovered gitdir and `--show-toplevel` fails, so the plant would
    be harmless on main and the red-on-main row would prove nothing. The audit's file list does not
    name the key; the test comments it.
B8. **Fixture C's origin url is set to `https://example.invalid/consumer.git` right after the
    setup's last fetch.** Nothing later fetches or pushes through it; the clones take `ORIGIN`.
B9. **`GIT_DOT_ENTRY` reads `shared_rules.GIT_ENTRY`, not a literal `".git"`.** The shared-rules
    test (S3) refuses a hooks/ module that restates a shared literal, and the walk added by
    ruling 2 did. With no `shared_rules.py` the name is empty and `own_checkout` returns None,
    so nothing is approved (fail closed, as S5 expects). The shared-rules test is unchanged: it
    was right. Consequence: `hook-cloud-profile.sh`'s vendored hook copy (`HOOK_FILES`) now
    includes `shared_rules.py`, as a real hooks/ always has it; without it the push never
    approved. That list pinned a hooks/ that no longer exists, not a behaviour.
B10. **Round 2 (ruling 9) done.** `submodule.recurse` and `push.followtags` added to
    `OWN_PUSH_PRESENT_KEYS`, `^hook\..+\.(event|command)$` to `OWN_PUSH_PRESENT_KEY_RES`; Q7 rows
    for each (the two hook keys set alone) were red first; `hooks/README.md` names the keys and
    lists `core.askPass` and `remote.origin.proxy` as deliberately not read.
