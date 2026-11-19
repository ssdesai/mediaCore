# Notes: own-push-credential-keys

Rulings, with a one-line reason each. The coordinator's come first; the implementer
appends its own under "Build rulings" as it makes them.

## Source

humanNetworkMap's `pull-agenttooling-pr141` round-4 audit
(`plans/features/pull-agenttooling-pr141/escalations/04-audit-opus.md`, on its branch
`claude/pull-agenttooling-pr141`), against agentTooling aee04c4 (#150). In the cloud
profile, `own_push_config_allows` approved `git push -u origin <B>` silently with:

- **F2.** `credential.helper = !f() { touch <scratch>/PWNED; echo username=x; echo password=y; }; f`
  in `.git/config`. Against a local server answering 401 the push ran the helper, and PWNED
  was created. The base (before #150) asked.
- **F3.** `credential.http://127.0.0.1.helper = !…` (url-scoped). Allowed.
- **F4.** `core.askPass = <scratch>/askpass.sh`. Allowed. It ran nothing only because the
  cloud environment sets `credential.interactive=false`.
- The same holds for a helper in `~/.gitconfig` or an included file.

The audit template classes a silent allow of a command that runs code as blocking.
#150 had excluded these keys on purpose (`self/features/own-push-real-gitdir/NOTES.md`,
ruling 4 "Deliberately not checked" and ruling 9 "Docs only"). That exclusion assumed
the keys could not run code on the approved push. F2 shows they can.

## Coordinator rulings

1. **Presence keys added.** Each of these prompts when present in the effective config,
   from any scope (`git config --list -z` already reads system, global, repo, worktree,
   includes and the command-line scope):
   - `credential.helper`, in `OWN_PUSH_PRESENT_KEYS`;
   - `core.askpass`, in `OWN_PUSH_PRESENT_KEYS`;
   - `credential.<anything>.helper`, as a regex `^credential\..+\.helper$` in
     `OWN_PUSH_PRESENT_KEY_RES`.

   *Reason:* each one runs a program when the server asks for credentials, and a
   `!`-prefixed helper is a shell command.
   - **Case.** Git prints the section and variable name lower-case, and the subsection as
     written. So the set holds `core.askpass` and `credential.helper` in lower case, and
     the regex matches `.helper` in lower case with any subsection. This is how the
     existing keys and regexes work.
   - **Empty value.** An empty `credential.helper =` resets the helper list. It still
     prompts, because presence is the rule. Nothing cheaper is worth the subtlety.
2. **The askpass environment.** The approval also prompts when `GIT_ASKPASS` or
   `SSH_ASKPASS` is set **and non-empty** in the hook's environment.
   - **Empty means unset, from git's source and this container.** Git 2.43's
     `git_prompt` takes `GIT_ASKPASS`, else `core.askPass`, else `SSH_ASKPASS`, and runs
     the result only when it is non-empty (`askpass && *askpass`). An empty `GIT_ASKPASS`
     runs nothing, and it also masks the other two.
   - **This container sets `GIT_ASKPASS=` (empty).** A "set at all" rule would prompt on
     every real push here. So an empty value is no prompt, and a test row holds it.
   - **Inheritance.** The hook's environment and the Bash tool's shell both come from the
     Claude Code process. A push run through the Bash tool inherits that process's
     `GIT_ASKPASS` and `SSH_ASKPASS`, unless the shell or the line changes them. A
     `GIT_ASKPASS=x git push …` prefix already prompts, through ruling 1 of
     own-push-real-gitdir (nothing before `git`). The Bash tool keeps no exported state
     between calls.
   - **So the hook's environment is the right proxy, though not a proof.** A shell profile
     that exports one is outside the root and outside what the hook can see. The check
     costs nothing, and it closes the case where the session itself carries one.
3. **Prompt only.** Nothing here adds a deny. A push that fails the new conditions prompts.
4. **This container is clean.** `git config --show-origin --get-regexp
   '^credential\.|^core\.askpass'` prints only `credential.interactive false`
   (command line). `credential.interactive` is not a helper and is not listed. Normal pushes
   stay silent, and the feature's own `git push -u origin claude/own-push-credential-keys`
   is the live check.
5. **Tests.** They go in `self/tests/hook-cloud-profile.sh`, in the Q7 neighbourhood, as a
   new block `Q8` (own-push-credential-keys). They must be seen red on main before the fix.
   - **F2.** `credential.helper` set to the audit's `!f() { … }; f` form, in the fixture's
     real `.git/config`. Prompt.
   - **F3.** `credential.https://<host>.helper` (url-scoped). Prompt. Add one row with a
     mixed-case subsection to show the regex holds it.
   - **F4.** `core.askPass` (spelled with camel case at `git config`). Prompt.
   - **Global.** A helper in the global config only, through `GIT_CONFIG_GLOBAL` or a
     `HOME` with a `.gitconfig`, as fits the harness. Prompt.
   - **Env.** `GIT_ASKPASS=<path>` in the hook's environment prompts.
     `SSH_ASKPASS=<path>` prompts. `GIT_ASKPASS=` (empty) still approves.
   - **The approval still holds.** The plain push approves with
     `credential.interactive=false` set.
   - Each mutation is undone after its row.

   **Not done:** no test actually runs a push against a 401 server. The hook's verdict is
   the contract.
6. **Docs.** In `hooks/README.md` → "The one cloud approval", move `credential.helper`,
   `credential.<any>.helper` and `core.askPass` out of the "deliberately not read" sentence
   into the presence list. Add the askpass-environment condition. The rest of
   `credential.*` (`credential.interactive`, `credential.username`, …),
   `http.proxy*`, `gpg.*`, `user.*`, `push.negotiate` and `remote.origin.proxy` stay in the
   not-read sentence. Rewrite its reason so it no longer claims credential programs run
   nothing.
   - `self/tests/README.md`'s entry for the file gains Q8.
   - The `own_push_config_allows` docstring names the env check, or the env check sits in
     `own_push_allowed` with its own line there. The README claims only what Q8 proves.
7. **BACKLOG, no fix.** One entry for the wider class: a writable `.git/config`, or a
   global or included git config, defeats the hook's approvals generally. It folds into the
   existing "read-only git approvals trust a git directory planted in the tree" entry, or
   sits beside it. The entry notes that the real `.git/config` is Edit-denied, so the threat
   needs a prior approved write or a file outside the root. Raised by
   `pull-agenttooling-pr141` round 4.
9. **Round 1's triage** (`escalations/01-audit-opus.md`). The review was clean. The audit
   escalated one blocking finding, and it is taken.
   - **The finding.** `[credential ""] helper = !…` is listed by `git config --list -z` as
     `credential..helper`. The `^credential\..+\.helper$` regex needs one character of
     subsection, so that key matches neither the regex nor the exact `credential.helper`.
     Git 2.43 runs the helper for every URL, so the push is a silent allow that runs code.
     It reproduces from the repo config, the global config and `GIT_CONFIG_COUNT`.
   - **The fix.** Every subsection regex in `OWN_PUSH_PRESENT_KEY_RES` takes `.*` in place of
     `.+`. That covers `branch`, `includeif`, `hook` and `credential`.
     - *Reason:* the change is prompt-only and conservative. An empty subsection is a key git
       may honour, and testing each section's empty-subsection semantics costs more than
       prompting on a key no real config writes. `.*` still needs both dots, so
       `credential.helper` stays an exact key and `credential.helperx` stays unmatched.
   - **The rows.** These are new Q8 rows, red on the round-1 HEAD (b0ae205's hook) for the
     credential ones:
     - `credential..helper` set in the repo config with raw `[credential ""]` text, prompt;
     - `credential..helper` in the global config only, prompt;
     - `includeif..path`, `hook..command` and `branch..pushremote`, one row each, prompt.
       Each is red if it allowed before. Record which.
   - **The docs.** `hooks/README.md` names the empty subsection.
8. **Out of scope.** `http.proxy` (the audit's F5). It reroutes but runs nothing, and the
   audit did not count it. `credential.interactive` and other non-program credential keys.
   Any deny-side change.

## Build rulings

- **Red on the unfixed hook.** Q8 rows, run against main's hook: RED (got ALLOW) for
  `credential.helper` (F2), `credential.https://example.com.helper` (F3),
  `credential.https://Example.COM/Path.Helper` (F3 mixed case), `core.askPass` (F4), a helper
  in the global config only (`GIT_CONFIG_GLOBAL`), `GIT_ASKPASS=<path>` and `SSH_ASKPASS=<path>`.
  GREEN: empty `GIT_ASKPASS`, empty `SSH_ASKPASS`, `credential.interactive=false`,
  `credential.<sub>.username`, the restored fixture, and no helper ran.
- **Round 2 (ruling 9), red on b0ae205's hook.** RED (got ALLOW): raw `[credential ""]` helper in
  the repo config, the same in a `GIT_CONFIG_GLOBAL` file only, `[includeIf ""]` path,
  `[hook ""]` command. GREEN already (prompt): `[branch ""]` pushRemote (an empty branch
  name is a key git or the hook already refuses; the row stays as a guard). Fixed with `.*`.
- **Env check lives in `own_push_config_allows`** (docstring updated), before any git probe.
- **Extra rows beyond the brief:** empty `SSH_ASKPASS` and `credential.<sub>.username` approve.
