# 01 — review: own-push-credential-keys

Review this feature against its spec, which is the coordinator's rulings in
`self/features/own-push-credential-keys/NOTES.md` → "Coordinator rulings". Do not use the
builder's report as the spec. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Close one gap. In the cloud profile, `own_push_config_allows` in
`hooks/allow-repo-commands.sh` silently approved `git push [-u] origin <own-branch>` while
the effective git config held a credential program. The audit showed this with
`credential.helper = !f() { touch …/PWNED; … }; f`: the push ran the helper on a 401.
It also showed a url-scoped `credential.<url>.helper` and `core.askPass`. After this
feature, the push prompts when any of these holds:

- `credential.helper` is present in any config scope;
- any `credential.<subsection>.helper` is present (regex, any subsection, any case as
  written);
- `core.askPass` is present;
- `GIT_ASKPASS` or `SSH_ASKPASS` is set **non-empty** in the hook's environment. An empty
  `GIT_ASKPASS` is no prompt: git runs nothing for it, and the cloud container sets it
  empty.

Excluded:
- Any deny. A failing push prompts.
- `http.proxy*` and the non-program credential keys (`credential.interactive`, …).
- The wider "writable git config defeats the approvals" class. It goes to
  `self/BACKLOG.md` only.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `OWN_PUSH_PRESENT_KEYS` holds `credential.helper` and `core.askpass` in lower case.
  `OWN_PUSH_PRESENT_KEY_RES` holds a regex matching `credential.<any>.helper` and nothing
  broader. Check that `credential.interactive`, `credential.helperx` and
  `credential.x.username` are not matched.
- The env check reads `os.environ` for `GIT_ASKPASS` and `SSH_ASKPASS`. Any non-empty value
  is no approval. The names and the rule are named constants (CONVENTIONS.md → "Named
  constants").
- Every approve row that held on main still holds: Q7's approvals and the table's own-push
  approvals. This includes the container's `credential.interactive=false` and an empty
  `GIT_ASKPASS`.
- `self/tests/hook-cloud-profile.sh` has a Q8 block with these rows: F2 (the `!`-helper),
  F3 (a url-scoped helper, plus a mixed-case subsection), F4 (`core.askPass`), a helper in
  the global config only, `GIT_ASKPASS` non-empty, `SSH_ASKPASS` non-empty, and
  `GIT_ASKPASS` empty approving. Each must fail on `origin/main`'s hook. Check this by
  running the rows against main's `hooks/allow-repo-commands.sh` if the NOTES do not
  record it.
- In `hooks/README.md` → "The one cloud approval", the new keys and the env condition are
  in the conditions list, not the "deliberately not read" sentence. That sentence's reason
  no longer claims credential programs are harmless. The README claims only what Q8
  proves.
- `self/tests/README.md` names Q8.
- `self/BACKLOG.md` carries the wider-class entry: a writable `.git/config` or a global or
  included config defeats the approvals. It notes the Edit-deny and that a prior approved
  write is needed.
- `./self/gate.sh` is green.

## Verdict
