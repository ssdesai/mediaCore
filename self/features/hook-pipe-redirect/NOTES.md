# Notes: hook-pipe-redirect

Direct build (AGENT_DIRECT.md). Closes two `self/BACKLOG.md` entries: "`git stash list`
is denied with the rest of `git stash`" and "A pipe into an interpreter followed by a
redirect is not read as one". Both entries are deleted.

## What the reading found

- The `git stash` deny lived in two places: `policy.GIT_ALWAYS_MUTATING` (the hook's
  enforcement) and its rendered twin, the `Bash(git stash:*)` prefix rule in
  `permissions.deny`. A deny rule beats the hook's `allow`, so approving `git stash list`
  in the hook alone would have changed nothing in any session that loads the settings.
  The prefix therefore had to go, and in a consuming repo the merge never removed a rule,
  so the old one would have survived every `sync-plans.sh`.
- `python3 < script.py` (and `ls | python3 < script.py`) was readable before and still
  is: the old segment reader saw `<` as a non-flag word and so as a script. The new
  reader strips redirects, so the input redirect is now recognised on purpose
  (`REDIRECT_SCRIPT_OP`) rather than by accident.
- `ls |` followed by a line break and `sh` was the opaque deny through `opaque_segments`
  (its separator accumulates `|\n`); `redirect_members` overwrote the pipe with the line
  break. Kept, by carrying the pipe across a break that ends no member.

## Rulings

1. **The pipe is read on `redirect_members`' members, not on `opaque_segments`'
   segments.** `piped_into_interpreter(sep, member)` now takes a `RedirectMember`, whose
   words carry no redirect; `is_opaque` computes it once over
   `redirect_members(command, stop_at_line_break=bool(heredocs))`, which is the same cut
   `segments_before_line_break` makes on a heredoc line. The other shapes still read
   segments. Rationale: the brief asked to reuse the reader that already takes redirects
   out rather than add a second; it also reads `2>&1` and `>|` as operators where the
   segment reader split them at `&`/`|`.
2. **An input redirect from a file is the script.** A member whose redirects include `<`
   is not "an interpreter with no script". `<<`, `<<<`, `<&` are not this; a heredoc or
   herestring into an interpreter was and stays the heredoc deny.
3. **`redirect_members` keeps a pipe separator across a line break that ends no
   member.** Needed so rule 1 does not lose `ls |\nsh`; it also makes `echo x |\ntee f`
   visible to the shell-authored-file reader, which is the same pipeline to bash.
4. **`git stash` becomes a subcommand table like `git worktree`**
   (`policy.GIT_STASH_SUBCOMMANDS`): `list` and `show` READ_ONLY; `push`, `save`, `pop`,
   `apply`, `drop`, `clear`, `branch`, `create`, `store` MUTATING. The hook denies a stash
   unless its **first** argument is READ_ONLY — so bare `git stash`, a leading flag or
   pathspec (each a push), and an unknown subcommand are denied — and approves `stash`
   in `git_allowed` only with a READ_ONLY first argument. First argument rather than
   first positional (the `worktree` rule) because a stash's leading flag makes it a push.
5. **`git stash show` is allowed too.** It is one more READ_ONLY entry in the same table
   and costs nothing extra; git's exec-through flags (`--ext-diff`, `--textconv`,
   `--output`) are still forbidden behind it, as for `git show`.
6. **Bare `git stash` is an exact rule, `Bash(git stash)`** (`BASH_EXACT_RULE_TEMPLATE`,
   `GIT_BARE_DENIED`), rendered after every prefix rule. The prefix spelling is exactly
   what denied the listing. A leading-flag push (`git stash -u`) has no rule at all —
   any prefix naming it would name `git stash list` — and is the hook's alone, like
   `git -C … worktree add`.
7. **`wire-settings.py` removes retired rules in a merge** — exactly
   `policy.retired_bash_deny_rules()` (today `Bash(git stash:*)`), in place, and nothing
   else. `--check` reports such a file `UNWIRED` ("N retired Bash deny rule(s) (…) to
   remove"); `--write` reports "removed …". Rationale: without it every consuming repo
   keeps a deny rule that overrides the hook's approval, so the feature would only have
   worked in this checkout. The exception is narrow — the rule is one this helper itself
   wrote — and is stated in the writer's docstring and `hooks/README.md`.
8. **The replay fixture's `git stash list` record** was DENY; it is ALLOW now, and
   `git stash pop` takes its place as the git-deny record so the fixture still carries one
   (the count stays ≥ 24). Its `provenance` says so.

## Propagation

- **`CONVENTIONS.md` changed** (the read-only git list gains `stash list`; the
  pipe-into-interpreter row mentions the redirect). It ships to every consuming repo, so
  the next propagation carries it.
- **`.claude/settings.json` was regenerated** (`wire-settings.py --self --write`): the
  stash prefix rule is replaced by nine per-subcommand rules plus the exact bare rule.
  The sibling `self-settings-untracked` feature stops tracking that file; whichever merges
  second resolves by regenerating rather than by hand.
- A consuming repo's settings lose `Bash(git stash:*)` on its next `sync-plans.sh`.

## Open questions

- None left open by this build.
