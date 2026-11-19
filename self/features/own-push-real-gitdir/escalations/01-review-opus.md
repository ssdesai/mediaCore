Verdict: escalated

# Review: own-push-real-gitdir

## What the batch was supposed to do

Close the audit's gap in the cloud profile. `own_push_allowed` approved
`git -C plans/evil2 push origin <B>`, where `plans/evil2/` was a git directory written as
plain files. Its `core.worktree` named the root, and its config either redirected the push
to `main` (evil2) or ran a command through `core.sshCommand` (evil3). The coordinator's
rulings 1–8 in `NOTES.md` define the fix:

- The only approved shape is `git push [-u|--set-upstream] origin <B>`, with nothing
  before `push`.
- The push must run from the project root.
- The hook finds the root checkout's own gitdir by walking the filesystem, and it must
  match what git reports.
- The branch rules stay as they were.
- The effective config may not redirect the push or run a program, the origin url must be
  http(s) and not rewritten, and the `pre-push` and `reference-transaction` hooks must be
  absent.
- Anything else prompts and is never denied.

## Does it do it

Yes, with one gap in the presence-key list (escalated below). I checked these against the
rulings:

- **Words.** The `-C` loop is gone, so a global option or an env-prefixed command reaches
  `own_push_allowed` with something other than `push` first and returns False.
  `subcommand_allowed` already refuses an assignment at command position. The signature,
  the call site and `except Exception: return False` are unchanged.
- **cwd and walk.** The payload's `cwd` is realpath'd and must equal the realpath'd root. A
  cwd that is not a string prompts (B4). `own_checkout` walks up from the root with
  `lexists`. A symlinked `.git`, or one that is neither a file nor a directory, prompts. A
  `gitdir:` path is resolved against the checkout directory, the same way git resolves it.
  `rev-parse --absolute-git-dir --show-toplevel` must then match both values by realpath.
  This covers the vendored-subdirectory case (a bare shape planted in the root is
  discovered first and mismatches), a real-config `core.worktree`, `core.bare=true`, and
  `GIT_DIR` in the hook's environment.
- **Config.** `git config --list -z` is parsed strictly: the trailing NUL is required and
  a record with an empty key is refused. `push.default` is checked. Each
  `remote.origin.url` value is collected, and there must be exactly one, http(s), equal to
  the `remote get-url --push --all` output. This correctly separates an `insteadOf` that
  applies from one that does not.
- **Hooks.** The hook checks `pre-push` and `reference-transaction` under the common dir
  with `lexists`, so a hook of any file type prompts.
- **Unchanged parts.** `GIT_NO_REPLACE_OBJECTS` is still set first. The HEAD-committed
  manifest read is unchanged, and Q5 and Q6 still pass.
- **Table.** Only the three `-C` rows changed answer (A→P). No deny row changed.
- **Can a write under the root, with no `.git` in its path, steer an approved push?** I
  found no route. The gitdir comes from a `.git` entry at the root or above it. Its config,
  `commondir` and hooks all sit under a `.git` path. Includes prompt. The url must survive
  a rewrite check.
- **Can a legitimate push newly prompt?** Only in the cases ruling 1 and ruling 4 name:
  `-C`, a subdirectory cwd, or a non-http(s) origin. The approve rows run with the
  container's real global config, including the injected `insteadOf`, `push.negotiate`
  and `gpg.ssh.program`.
- **Docs.** `hooks/README.md` → "The one cloud approval", the `CONVENTIONS.md` push
  sentence, the root `README.md` `hooks/` row and `self/tests/README.md`'s Q7 entry all
  agree with the code. Every claim in them is backed by a Q7 row.
- **Tests first.** The tests were committed before the fix, in
  `a15f8aa own-push-real-gitdir: acceptance tests`.
- **Gate.** `self/gate-report.txt` ends `all checks passed`. The only non-zero exit is the
  advisory "pricing rate history is current", which this feature does not touch.

## Fixed in this pass

- `self/tests/hook-cloud-profile.sh`: two whitespace slips the batch introduced.
  - `#   H17(hook-audit-gaps` is back to `#   H17 (hook-audit-gaps` in the header comment.
  - `LOCAL_WORDS =(` is back to `LOCAL_WORDS = (`.

  Neither changes behaviour.

## Escalated to the next round

1. **`submodule.recurse` is missing from `OWN_PUSH_PRESENT_KEYS`**
   (`hooks/allow-repo-commands.sh:670–676`).
   - **The problem.** Ruling 4 lists `push.recursesubmodules` because a recursing push
     runs `git push` inside submodules. Git's config documentation says
     `submodule.recurse` turns on `--recurse-submodules` for every command that has the
     option, `push` included. In `builtin/push.c`, `submodule.recurse=true` sets
     on-demand recursion when `push.recurseSubmodules` is not set. That makes it an
     equivalent spelling the presence list does not cover.
   - **Severity: low.** Its realistic sources are `.git/config` (Edit-denied), global
     config and the environment. But the list's stated job is to refuse every key that
     makes a push execute, and an equivalent alias getting past it is the kind of gap that
     stays green.
   - **Why I didn't fix it here.** It is a local change, but I could not write to
     `hooks/` in this pass because of the permission policy.
   - **The fix:**
     - Add `"submodule.recurse"` to `OWN_PUSH_PRESENT_KEYS`.
     - Add `("submodule.recurse", "true")` to `PRESENCE_KEYS` in
       `self/tests/hook-cloud-profile.sh` (Q7). The test asserts a prompt.
     - Add `submodule.recurse` beside `push.recursesubmodules` in `hooks/README.md`'s key
       list (line 904).
     - Add a build-ruling line in `NOTES.md` under B1, which permits additions.

No other findings.
