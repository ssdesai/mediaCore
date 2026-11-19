# 14 — review: orchestration-record-fixes (round 14)

Round 13's review and audit both escalated: four more spellings past `substitution_may_build`,
the build-script judge's fine fail-closed reading on a checkout whose orchestrator ledger cannot
be read (`NOTES.md` → "Round 12 → 13"). By the orchestrator's ruling, commit `b96b3b4` replaces
that reading with a coarse rule (`unreadable_ledger_refuses`), and `8e65198` merges
`origin/main` (#142, vendored-edit-ask; no change to `allow-repo-commands.sh`), and `b0919a9`
merges `origin/main` again (#143, shared-hook-rules: in `allow-repo-commands.sh` only its three
hunks — the guarded `orchestrator_role` and `shared_rules` imports and
`ORCHESTRATOR_SLUG_RE = shared_rules.SLUG_RE`). "No findings"
is a legitimate verdict, and a bypass you find is a finding.

**Do not edit any file in this pass.** The security audit runs before you; any edit to an
audited path after it stamps the audit stale and blocks the close. A doc nit goes in your
report as a note, not a change.

## What the feature is supposed to do

- Item 1: a redirection word is never read as a refspec or remote by the push rules; a quoted
  operator word is an argument; a quoted digit is no descriptor.
- The git fail-closed rule (`NOTES.md` → "Round 9"): a line holding a git word and a `$(…)`, a
  backtick, `<(`/`>(`, a `<<` or the word `case` — quoted or not — is never approved; the deny
  side has one plain reading and refuses what it finds; what it misses there prompts. A quoted
  `<<` or a `<<<` never switches a deny off.
- **Round 14, the unreadable-ledger rule:** with the role ledger unreadable
  (`LEDGER_UNREADABLE`, the one path `build_script_denial` runs on), a RAW command holding
  `$(`, a backtick, `<(`/`>(`, `<<`, `$'`, `$"` or `${` is refused outright with
  `UNREADABLE_LEDGER_REASON` (repair `.git` or the ledger, or drop the substitution or
  heredoc), before any heredoc placeholder or quoting rewrite. Otherwise the build-script
  reading is as round 11 left it.
- Item 2, merged with #141: report paths resolve against the record's own repo root; an
  `agentTooling` entry against the agentTooling directory, with no `--checkout`.

## Out of scope by design

**Finer readings on the unreadable-ledger path.** A spelling that hides a build script from
`invokes_build_script` on a line holding none of the markers above is in scope; one that needs
a substitution, heredoc or quoting form is refused by the coarse rule and is not a finding.
Also decided (prompts, never an allow, identical on `origin/main`): wrappers, brace groups,
comments, assignment prefixes, a git command after a real heredoc's body, and the bundled force
flag `git push -fu` (a recorded follow-up).

## The diff

Base is `main` (`git fetch origin main`, then `git diff origin/main...HEAD --stat`). For this
round read `git diff c3cba33..b96b3b4 -- hooks self/tests` closely and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>","session_id":"<fresh>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, `AGENTTOOLING_PROFILE=cloud`
and `local`). `self/tests/hook-cloud-profile.sh` H3–H5 call the judge directly.

## Contracts to hold it to

- The coarse rule fires only on the unreadable-ledger path: with a readable record, or none,
  every answer is round 13's (the heredoc commit, the allowlist's documented shapes).
- On that path, every line `origin/main` refuses is still refused, and no marker-free spelling
  hides a build script that `origin/main` caught.
- Nothing `origin/main` refuses is approved.

## Verdict
