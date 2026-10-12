# Notes: review-base-and-cloud-hook

Rulings the spec left open, made by the direct implementer as the build went, each with
its one-line rationale. Deviations from the spec, if any, are said so.

## Part B — the review's base

1. **The fetch runs as each review plan's prompt is built** (`review_diff_base`, called
   from `build_prompt`), not once per `run-review.sh` invocation. The slug and its
   manifest's `base` are only known inside `run_all`; a pass normally holds one plan, and a
   second fetch for a second plan is cheap and fresher.
2. **The fetch names an explicit refspec**, `+refs/heads/<base>:refs/remotes/origin/<base>`,
   rather than bare `git fetch origin <base>`, so the remote-tracking ref moves however the
   remote's fetch refspecs are configured — the spec's intent ("fetch origin <base>, then
   diff origin/<base>") without depending on git's opportunistic update.
3. **The fallback is decided by the ref, not by the fetch.** `origin/<base>` is used when it
   exists after the fetch — a failed fetch warns (stderr, `WARN: git fetch origin <base>
   failed …`) and still uses a stale `origin/<base>` if one is there; only no `origin`
   remote, or no `origin/<base>` at all, falls back to the local `<base>`, and the prompt
   says which it is.
4. **The prompt states the resolved ref outright** (`git diff origin/main...HEAD`) instead
   of "the plan names the base", and tells the executor to use it even where an older
   brief names a bare `<base>`: briefs written before this feature say `main...HEAD`.
5. **`feature-start.sh`'s fetch and fast-forward are untouched**; only the two comments that
   said "the review diffs `<base>...HEAD`" and the two status lines that repeated it were
   reworded, since that is no longer true of the review. The `updated   local <base>` and
   `could not fast-forward local <base>` prefixes tests read are unchanged.

5a. **The fetch runs with `GIT_TERMINAL_PROMPT=0`**: a remote that wants credentials fails
   the fetch (a warning) instead of hanging an unattended pass on a prompt.

## Part A — the module

6. **`env_profile.detect(environ=None)` returns a `Detection(profile, decided_by)`
   namedtuple and raises `InvalidProfile` (a `ValueError` carrying `.value`)** for an
   override that is neither profile; `is_cloud()` is the yes/no the hook asks, and reads an
   invalid override as NOT cloud — today's answers — since the hook must never crash and
   the refusal belongs to `profile_check`.
7. **Run as a script it prints two lines, profile then decider**; for an invalid override
   it prints the raw value and `AGENTTOOLING_PROFILE` and exits 2, so env-profile.sh keeps
   the value and `profile_check` refuses it by name exactly as before.
8. **env-profile.sh with no answer from the module** (python3 or the module missing — a
   broken install) leaves `AGENTTOOLING_PROFILE` EMPTY and `PROFILE_DECIDED_BY=undetected`,
   warns on stderr naming the module, and `profile_check` refuses. It does not re-implement
   step 1 in bash to keep a forced value working: one rule, one place. Consequence: every
   test fixture that copies env-profile.sh now copies `hooks/env_profile.py` beside it.
9. **env-profile.sh stays on the confinement allowlist**, because it exports the answer
   under `AGENTTOOLING_PROFILE` and its functions read it back (and `profile_describe` prints
   `CLAUDE_CODE_REMOTE=true` as text); the hook is not on it, and the env-profile test plants
   a hook that spells a variable to prove the check catches it.
10. **The hook's `import env_profile` is guarded** (an ImportError reads as local), unlike
    `import policy`: a partial copy of `hooks/` must not turn every Bash call into a crash.

## Part A — the hook

11. **Detached HEAD (or no repo, or git failing) in the cloud: the cloud-only denies stay
    silent** — today's prompt — because "the current branch" does not exist to compare
    with; the always-denied shapes still deny, with the cloud reason naming "this session's
    assigned branch" instead of a name. The spec's "falls back to today's prompts".
12. **`git push --tags` is refused in the cloud**, as are `--all`, `--branches`, `--mirror`:
    each pushes refs that are not the branch, and the cloud rule is "push only <branch>".
    `--follow-tags` is not judged (it pushes the branch, plus tags reachable from it).
13. **Every push deletion is refused in the cloud** — `--delete`, `-d` (also inside a short
    cluster), `--prune`, and a `:<dst>` refspec — even of the current branch: "never delete
    a branch".
14. **A refspec's destination is what is compared**: `[+]<src>[:<dst>]`, `dst` defaulting
    to `src`, `HEAD`/`@` meaning the current branch, `refs/heads/` stripped. So `HEAD:<cur>`,
    `<cur>`, `HEAD`, `refs/heads/<cur>` keep today's prompt; `HEAD:x`, `main`, `+main`, a
    tag and a glob are refused. The first positional is always the remote.
15. **`git checkout`: a file checkout is never a switch.** Anything after `--`, `-p/--patch`
    or `--pathspec-from-file`, or two or more positionals (tree-ish + paths, or paths) is a
    file checkout and is not judged. Exactly one positional is a switch when it is `-`, or
    when git says it names a commit (`rev-parse --verify --quiet <arg>^{commit}`) or a
    remote-tracking branch's short name (what `git checkout <name>` would create a branch
    from); otherwise it is a path. So the hook tells a branch from a path the way git does —
    a ref wins — and when git cannot answer, it reads a path: today's answer.
16. **`git switch`**: the first positional is the target; `-`, `--detach`/`-d` and
    `--orphan` leave the branch whatever follows; `HEAD`/`@`/`refs/heads/<cur>` are the
    current branch. No positional is not judged.
17. **Where git is asked**: the payload's cwd (else `CLAUDE_PROJECT_DIR`), moved by each
    `-C <path>` among git's global options, so `git -C <root> push origin main` is read in
    the checkout it names. One probe (`rev-parse --show-toplevel --symbolic-full-name HEAD`)
    gives the root and the branch; a `checkout` with one positional adds at most two more,
    and the reason's started-feature lookup a `git grep`. Every probe has a 5 s timeout, and
    none runs locally or for a command that is not a switch, checkout or push (or an
    already-denied git shape, for the reason). Tested under a logging git stub.
18. **The repo shape is read from where the hook file sits**: the hook at `<root>/hooks/`
    is agentTooling's own checkout (`./feature-start.sh --self`, `self/features`); otherwise
    a consuming repo (`./<vendored dir>/feature-start.sh`, `plans/features`) — no subprocess.
19. **An env prefix (`AGENTTOOLING_PROFILE=local git push …`) is not read as git** by either
    deny (the program word is the assignment), so it stays an ASK in both profiles, as the
    spec says; it is in the table.

## Docs

20. **The templates are not edited.** `templates/plans/environment.sh` and `cloud-setup.sh`
    (and `templates/README.md`) call `agentTooling/env-profile.sh` "the one place the
    profile is decided"; from a shell's side it still is the one way in, the spec says the
    templates need no edits, and an edit would be a template-version bump every consuming
    repo hand-merges. `LIFECYCLE.md`, `self/PROJECT_FACTS.md`, `env-profile.sh`,
    `self/profile-confinement.sh` and the READMEs now name the module as where the rule
    lives.

## Round 2 — a push to `main`, in both profiles

21. **Locally a push to `main` is read from the words alone, so a bare `git push` (or
    `git push origin HEAD`, `git push origin @`) while checked out on `main` is NOT caught
    and stays a prompt** — the spec's ruling to record: the local judge runs no git probe
    (X4 proves zero calls), and `HEAD`/`@` resolve to an unknown branch there. In the cloud
    the current branch is already read, so the same commands on `main` are refused.
22. **`git push origin main:x` is not a push to `main`** (local prompt; cloud refused as
    round 1's "not the current branch"): the destination is what a push changes, `main` is
    only the source, and the spec's entry is "whose destination is `main`".
23. **A quoted `'main'` / `"main"` is `main`**: the hook judges shlex's words, as the shell
    would hand them to git, so quoting changes nothing.
24. **`--repo` with no value** (`git push --repo`, `git push origin --repo`, `--repo=`) is
    read, not crashed on: the dangling flag consumes nothing, there is no refspec, and the
    answer is the prompt in both profiles (F4). Every reading is inside a `try` — an
    exception reads as "not refused", today's answer.
25. **`--repo` makes every positional a refspec**, per the spec, even though git itself lets
    a positional repository take precedence over `--repo` (so to git, `git push --repo
    origin main` pushes to a remote named `main`). The spec's reading can only refuse more,
    never less, and a command that spells `main` beside `push` is one no agent needs.
26. **A deletion of `main` counts** (`:main`, `--delete`/`-d origin main`): the destination
    is `main` and deleting it is the worst push to it. Locally it gets the push-to-main reason
    (round 1's cloud already refused every deletion).
27. **Locally, when a line is both a ref-moving shape and a push to `main`** (`git push
    --force origin main`), the existing GIT_DENY_REASON wins: it is the older, wider rule and
    its advice is still right; the push-to-main reason is for a push that is otherwise
    ordinary. In the cloud both get the cloud reason, from the first such command.
28. **A remote other than `origin` changes nothing** (`git push upstream main` is refused):
    the protected name is a branch name, and any remote's `main` is a `main`.
29. **The entry is a sibling table, `GIT_HOOK_ONLY`, not a row of `GIT_CLOUD_ONLY`**: the
    cloud-only table is the "cloud and only cloud" contract round 1's tests assert; a
    both-profile entry with no prefix rule is a different kind, so it gets its own table and
    `hook_only_rule()`, and the renderers never read it.

## Round 4 — the on-branch evidence ignores the provisional `to`

30. **The switch is `--ignore-to` on the CLI and `ignore_to=False` on
    `last_branch_instant`**, named for what it does; `feature-capture.sh` passes it from a
    named array (`ON_BRANCH_EVIDENCE_ARGS`) on the on-branch path only. Default off, so the
    post-merge path and the claim index's `provisional_to` (which only runs for a window
    whose `to` is null, where the two readings agree) read the window as written.
31. **The ignored `to` covers subagents too**: the same window feeds the delegate start
    check, so a delegate spawned after the stamped `to` by a late session is evidence like
    its parent — dropping only the parent's bound would leave the delegate test fencing it.
32. **Chained windows: the open upper bound stops at a later feature's `from` on the same
    branch name** (`chained_successor_from`). Reachable in the cloud: a merged feature's
    `claude/…` branch reused for the next feature (merge-commit flow today; squash once the
    BACKLOG entry lands) makes a by-hand re-run of the old feature's capture on that branch
    take the on-branch path, and with no upper bound its evidence would have pulled `to`
    over the next feature's sessions. The cap is that feature's `from` — exclusive, as
    `to` is — which is where the chain already says this feature ends; a feature sharing
    the branch whose `from` is not after this one's is not a successor. Same corpus only
    (the features dir the evidence is read for): a `--self` and a host feature sharing one
    branch name is not a chain either corpus can see. Locally the branch is the slug and
    never shared, so the cap never fires there. Tested by feature-lifecycle.sh W8c.
33. **The test extends `feature-lifecycle.sh`'s W phases (W8)** rather than a new file:
    W1–W7 already build the branch session, the stamp and the merge it needs. The late
    session is disowned with a hand-written `exclude_sessions` between phases (not deleted:
    a re-capture refuses a priced session whose transcript is gone) so W3's and W6's fixed
    bounds still hold.
    `unset CLAUDE_CODE_REMOTE` joins the file's pinned `AGENTTOOLING_PROFILE=local`.
