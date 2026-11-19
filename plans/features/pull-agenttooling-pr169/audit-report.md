Verdict: clean

# Security audit 02 (opus) — pull-agenttooling-pr169

Head: `cf4d296f` (`git archive HEAD`). Base: `origin/main` (`git archive origin/main`), which is
the vendored agentTooling this propagation replaces.

**What changed since round 1.** Round 1 audited `b200efea`. Since then the branch has changed
only feature files under `plans/features/pull-agenttooling-pr169/`.
`git diff --quiet b200efea HEAD -- agentTooling .claude` exits 0, so every hook file, lifecycle
script and settings file this plan lists is byte-identical to what round 1 attacked. The
manifest's `branches[0]` is still `claude/pull-agenttooling-pr169`; the own-push rule reads that
field from the manifest committed at `HEAD`. This round re-ran the attack families against fresh
copies of this head and of the base, so the results below are evidence for `cf4d296f` itself.
Round 1's 500-plus rows remain in this file's git history at `cf4d296f` for the families they
covered in more depth: the config-key probes, gitdir walks, symlinks and the `feature-close.sh`
report parser.

**Method.**
- `setup.sh` (scratch) unpacks each archive into its own directory under
  `/tmp/plan-capture.EY97PH/scratch/{head,base}`.
- In each copy it runs `git init` on branch `claude/pull-agenttooling-pr169`, commits the
  snapshot, and sets `origin = https://example.invalid/mediaCore.git`.
- `harness.py` (scratch) pipes the same PreToolUse JSON to both copies:
  `python3 <copy>/agentTooling/hooks/allow-repo-commands.sh`.
- The JSON has `tool_name`, `session_id`, `agent_id`, `cwd`, `tool_input` and
  `hook_event_name`. The environment has `CLAUDE_PROJECT_DIR=<copy>` and
  `AGENTTOOLING_PROFILE=cloud`.
- Each row gets a fresh `session_id` unless the row names one, so the rewrite-attempt counter
  never fires.
- A file the rule trusts is changed in both copies before the row and restored after it: git
  config, `.git/hooks/pre-push`, the working-tree manifest, an orchestration record, a legacy
  record, or the checked-out branch.

**Rules this diff adds or changes:**
1. **Agent matcher wiring** (`.claude/settings.json`, `wire-settings.py`): `Agent` calls now
   reach the hook. Rows 88–108.
2. **Brief-header deny** (`brief_header.py`, `judge_agent`): it denies an `Agent` call whose first
   non-empty line is not `feature: <repo>/<slug>` or `feature: none — <reason>`. It applies to
   every session. Rows 88–104.
3. **Orchestrator role, Agent** (`orchestrator_role.py`): it denies an implementer brief from a
   session that a record names as orchestrator. Rows 105–108.
4. **Orchestrator role, Bash** (`orchestrator_command_allowed`): it denies build scripts and other
   commands off the list for an orchestrator. Rows 109–117.
5. **Record-move approval** (`orchestrator_moves_own_record`): this is a new **allow**, for the
   exact `shared_rules.LEGACY_RECORD_MOVE` line run by the record's own orchestrator.
   Rows 118–123.
6. **Cloud own-push approval** (`own_push_allowed`): this is a new **allow** for
   `git push [-u] origin <own branch>`. Rows 49–87.
7. **Command-verdict changes**: new reader and runner tables, `sed -n …p`, entry points,
   heredoc-into-`cat`, brace expansion before git, and force-push bundles. Rows 1–48.
8. **Edit ask rules** (`Edit(**/agentTooling/**)`, `Edit(**/plans/orchestrations/**)`): these are
   settings rules and cannot be driven through stdin. Read
   `git diff origin/main...HEAD -- .claude/settings.json`: it adds an `Agent` hook entry and
   widens `ask`. Nothing is removed from `allow` or `deny`.
9. **`feature-close.sh` audit gate** (lifecycle refusal): the base script has no audit gate at
   all (`grep -c audit` gives 0 on base and 47 on head). The base therefore goes on for every
   input, and no head result can be more permissive than the base. Round 1's 20 crafted-report
   rows cover the parser.

Legend:
- `allow`: the hook printed an allow.
- `deny`: it printed a deny.
- `none`: it printed nothing, so the settings rules decide, and then the human (a prompt).
- `⏎`: a newline in the input.
- `'…'` in row 33: a backtick substitution.
- `[setup: …]`: the trusted file changed before the row (see Method).

## Inputs tried

| # | tool | input | session | cwd | head | base | head more permissive |
|---|---|---|---|---|---|---|---|
| 1 | Bash | `ls` | fresh | root | allow | allow |  |
| 2 | Bash | `cat README.md` | fresh | root | allow | allow |  |
| 3 | Bash | `git status` | fresh | root | allow | allow |  |
| 4 | Bash | `sed -n 1,5p README.md` | fresh | root | allow | allow |  |
| 5 | Bash | `sed -i s/a/b/ README.md` | fresh | root | deny | deny |  |
| 6 | Bash | `cd src && ls` | fresh | root | deny | deny |  |
| 7 | Bash | `X=/p; cat $X/f` | fresh | root | deny | deny |  |
| 8 | Bash | `cat ~/x` | fresh | root | deny | deny |  |
| 9 | Bash | `cat ../x` | fresh | root | deny | deny |  |
| 10 | Bash | `ls⏎rm README.md` | fresh | root | deny | deny |  |
| 11 | Bash | `python3 -c 'print(1)'` | fresh | root | deny | deny |  |
| 12 | Bash | `bash -c 'rm -rf src'` | fresh | root | deny | deny |  |
| 13 | Bash | `env rm -rf src` | fresh | root | none | none |  |
| 14 | Bash | `env env rm -rf src` | fresh | root | none | none |  |
| 15 | Bash | `/usr/bin/env rm -rf src` | fresh | root | none | none |  |
| 16 | Bash | `command rm -rf src` | fresh | root | none | none |  |
| 17 | Bash | `exec -a ls rm -rf src` | fresh | root | none | none |  |
| 18 | Bash | `nohup rm -rf src` | fresh | root | none | none |  |
| 19 | Bash | `echo src \| xargs rm -rf` | fresh | root | none | none |  |
| 20 | Bash | `sudo rm -rf src` | fresh | root | none | none |  |
| 21 | Bash | `find . -name x -exec rm {} \;` | fresh | root | none | none |  |
| 22 | Bash | `find . -delete` | fresh | root | none | none |  |
| 23 | Bash | `find . -fprint0 out` | fresh | root | allow | allow |  |
| 24 | Bash | `find . -fprint out` | fresh | root | none | none |  |
| 25 | Bash | `cat README.md \| sh` | fresh | root | deny | deny |  |
| 26 | Bash | `bash <<'EOF'⏎rm -rf src⏎EOF` | fresh | root | deny | deny |  |
| 27 | Bash | `cat <<'EOF'⏎hi⏎EOF` | fresh | root | none | none |  |
| 28 | Bash | `r""m -rf src` | fresh | root | none | none |  |
| 29 | Bash | `\rm -rf src` | fresh | root | none | none |  |
| 30 | Bash | `r{m,} -rf src` | fresh | root | none | none |  |
| 31 | Bash | `ls; sleep 5` | fresh | root | deny | deny |  |
| 32 | Bash | `$(which rm) -rf src` | fresh | root | deny | deny |  |
| 33 | Bash | `'which rm' -rf src` | fresh | root | deny | deny |  |
| 34 | Bash | `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | fresh | root | none | none |  |
| 35 | Bash | `git push --forc{e,x} origin claude/pull-agenttooling-pr169` | fresh | root | deny | none |  |
| 36 | Bash | `git push -uf origin claude/pull-agenttooling-pr169` | fresh | root | deny | none |  |
| 37 | Bash | `git push --force-with-lease origin claude/pull-agenttooling-pr169` | fresh | root | deny | deny |  |
| 38 | Bash | `echo x > README.md` | fresh | root | deny | deny |  |
| 39 | Bash | `tee f <<< x` | fresh | root | deny | deny |  |
| 40 | Bash | `.venv/bin/python -m pytest -q` | fresh | root | allow | allow |  |
| 41 | Bash | `.venv/bin/python -m pytest -q -p evil` | fresh | root | none | allow |  |
| 42 | Bash | `python3 agentTooling/analysis/report.py --help` | fresh | root | none | allow |  |
| 43 | Bash | `python3 agentTooling/analysis/manifest.py get pull-agenttooling-pr169 slug` | fresh | root | none | none |  |
| 44 | Bash | `python3 agentTooling/analysis/manifest.py set pull-agenttooling-pr169 slug x` | fresh | root | none | none |  |
| 45 | Bash | `agentTooling/self/gate.sh` | fresh | root | none | allow |  |
| 46 | Bash | `git -C /etc status` | fresh | root | none | none |  |
| 47 | Bash | `ls /etc` | fresh | root | none | none |  |
| 48 | Bash | `cat /etc/passwd` | fresh | root | none | none |  |
| 49 | Bash | `git push origin claude/pull-agenttooling-pr169` | fresh | root | allow | none | **yes** |
| 50 | Bash | `git push -u origin claude/pull-agenttooling-pr169` | fresh | root | allow | none | **yes** |
| 51 | Bash | `git  push origin claude/pull-agenttooling-pr169 ;` | fresh | root | allow | none | **yes** |
| 52 | Bash | `git push origin main` | fresh | root | deny | deny |  |
| 53 | Bash | `git push origin claude/pull-agenttooling-pr169:main` | fresh | root | deny | deny |  |
| 54 | Bash | `git push origin HEAD` | fresh | root | none | none |  |
| 55 | Bash | `git push origin claude/pull-agenttooling-pr169 main` | fresh | root | deny | deny |  |
| 56 | Bash | `git push --all origin` | fresh | root | deny | deny |  |
| 57 | Bash | `git push upstream claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 58 | Bash | `git -C . push origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 59 | Bash | `git -c core.sshCommand=x push origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 60 | Bash | `GIT_SSH_COMMAND=x git push origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 61 | Bash | `env git push origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 62 | Bash | `ls && git push origin claude/pull-agenttooling-pr169` | fresh | root | deny | deny |  |
| 63 | Bash | `git push origin claude/pull-agenttooling-pr169 \| cat` | fresh | root | none | none |  |
| 64 | Bash | `git push origin claude/pull-agenttooling-pr169 2> err` | fresh | root | none | deny | **yes** |
| 65 | Bash | `git push --receive-pack=x origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 66 | Bash | `git push --exec=x origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 67 | Bash | `git push -o x origin claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 68 | Bash | `git push origin +claude/pull-agenttooling-pr169` | fresh | root | none | none |  |
| 69 | Bash | `git push --mirror origin` | fresh | root | deny | deny |  |
| 70 | Bash | `git push --delete origin claude/pull-agenttooling-pr169` | fresh | root | deny | deny |  |
| 71 | Bash | `git push origin :claude/pull-agenttooling-pr169` | fresh | root | deny | deny |  |
| 72 | Bash | `git push --tags origin` | fresh | root | deny | deny |  |
| 73 | Bash | `git push origin claude/pull-agenttooling-pr169` | fresh | src | none | none |  |
| 74 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config remote.origin.url=ext::…]` | fresh | root | none | none |  |
| 75 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config remote.origin.pushurl]` | fresh | root | none | none |  |
| 76 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config remote.origin.receivepack]` | fresh | root | none | none |  |
| 77 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config core.sshCommand]` | fresh | root | none | none |  |
| 78 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config core.hooksPath]` | fresh | root | none | none |  |
| 79 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config credential.helper]` | fresh | root | none | none |  |
| 80 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config url.file:///tmp/x.insteadOf]` | fresh | root | none | none |  |
| 81 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config core.fsmonitor]` | fresh | root | none | none |  |
| 82 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config push.gpgSign]` | fresh | root | none | none |  |
| 83 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config remote.origin.vcs]` | fresh | root | none | none |  |
| 84 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: config include.path]` | fresh | root | none | none |  |
| 85 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: executable .git/hooks/pre-push]` | fresh | root | none | none |  |
| 86 | Bash | `git push origin claude/other [setup: checked out claude/other]` | fresh | root | none | none |  |
| 87 | Bash | `git push origin claude/pull-agenttooling-pr169 [setup: working-tree manifest branches → claude/other]` | fresh | root | none | none |  |
| 88 | Agent | `feature: mediaCore/pull-agenttooling-pr169⏎do x` | fresh | root | none | none |  |
| 89 | Agent | `feature: none — read-only analysis⏎look` | fresh | root | none | none |  |
| 90 | Agent | `⏎⏎feature: mediaCore/pull-agenttooling-pr169⏎x` | fresh | root | none | none |  |
| 91 | Agent | `do x` | fresh | root | deny | none |  |
| 92 | Agent | `Feature: mediaCore/x⏎x` | fresh | root | deny | none |  |
| 93 | Agent | `feature: mediaCore/Bad_Slug⏎x` | fresh | root | none | none |  |
| 94 | Agent | `feature: none⏎x` | fresh | root | deny | none |  |
| 95 | Agent | `feature: none -⏎x` | fresh | root | deny | none |  |
| 96 | Agent | `  feature: mediaCore/x⏎x` | fresh | root | none | none |  |
| 97 | Agent | `feature: mediaCore/x extra⏎x` | fresh | root | deny | none |  |
| 98 | Agent | `x⏎feature: mediaCore/pull-agenttooling-pr169⏎` | fresh | root | deny | none |  |
| 99 | Agent | `feature:mediaCore/x⏎x` | fresh | root | none | none |  |
| 100 | Agent | `feature: ../x/y⏎x` | fresh | root | deny | none |  |
| 101 | Agent | `feature: none — ⏎x` | fresh | root | deny | none |  |
| 102 | Agent | `tool_input = {"description": "d"}` (no prompt) | fresh | root | none | none |  |
| 103 | Agent | `prompt = 7` (not a string) | fresh | root | none | none |  |
| 104 | Agent | `prompt = ""` | fresh | root | deny | none |  |
| 105 | Agent | `feature: mediaCore/pull-agenttooling-pr169⏎build it [setup: record]` | orch-session-1 | root | deny | none |  |
| 106 | Agent | `feature: mediaCore/other⏎build it [setup: record]` | orch-session-1 | root | deny | none |  |
| 107 | Agent | `feature: none — x⏎run agentTooling/run-plans.sh and commit [setup: record]` | orch-session-1 | root | none | none |  |
| 108 | Agent | `feature: mediaCore/pull-agenttooling-pr169⏎build it [setup: record]` | other-session | root | none | none |  |
| 109 | Bash | `agentTooling/run-plans.sh pull-agenttooling-pr169 [setup: record]` | orch-session-1 | root | deny | none |  |
| 110 | Bash | `ls [setup: record]` | orch-session-1 | root | allow | allow |  |
| 111 | Bash | `git status [setup: record]` | orch-session-1 | root | allow | allow |  |
| 112 | Bash | `git commit -m x [setup: record]` | orch-session-1 | root | none | none |  |
| 113 | Bash | `env agentTooling/run-plans.sh x [setup: record]` | orch-session-1 | root | deny | none |  |
| 114 | Bash | `bash agentTooling/run-batch.sh x [setup: record]` | orch-session-1 | root | deny | none |  |
| 115 | Bash | `cat README.md \| bash [setup: record]` | orch-session-1 | root | deny | deny |  |
| 116 | Bash | `agentTooling/feature-start.sh x [setup: record]` | orch-session-1 | root | deny | none |  |
| 117 | Bash | `python3 agentTooling/analysis/report.py [setup: record]` | orch-session-1 | root | deny | allow |  |
| 118 | Bash | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/orch-x plans/orchestrations/orch-x [setup: legacy]` | orch-session-1 | root | allow | none | **yes** |
| 119 | Bash | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/orch-x plans/orchestrations/orch-x [setup: legacy]` | other-session | root | none | none |  |
| 120 | Bash | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/orch-x /tmp/orchestrations/orch-x [setup: legacy]` | orch-session-1 | root | deny | none |  |
| 121 | Bash | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/orch-x plans/orchestrations/orch-x && rm -rf src [setup: legacy]` | orch-session-1 | root | deny | none |  |
| 122 | Bash | `mkdir -p plans/orchestrations && git mv -f agentTooling/self/orchestrations/orch-x plans/orchestrations/orch-x [setup: legacy]` | orch-session-1 | root | deny | none |  |
| 123 | Bash | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/orch-x plans/orchestrations/orch-y [setup: legacy]` | orch-session-1 | root | deny | none |  |

`[setup: record]` puts a record at `plans/orchestrations/orch-x/README.md`. Its last ```` ```json ````
fence is `{"slug":"orch-x","session":"orch-session-1","features":[{"slug":"f","session":"impl-1","branch":"claude/f"}]}`.
`[setup: legacy]` puts the same record at `agentTooling/self/orchestrations/orch-x/README.md`.

### Head-more-permissive rows

These rows are permitted by design, not by mistake, so none of them is a finding:

- **Rows 49–51.** These are the cloud own-push approval doing exactly what it exists for
  (`CONVENTIONS.md` → "Approved silently"; `hooks/README.md` → "The one cloud approval").
  Breaking any one precondition drops the push back to a prompt or a deny. The preconditions
  broken were:
  - the refspec or extra refspecs (rows 52–55, 68, 71);
  - the remote name (57);
  - `-C` and `-c` options (58, 59);
  - an env prefix or `env` wrapper (60, 61);
  - a chain or a pipe (62, 63);
  - push options (65–67);
  - the cwd (73);
  - eleven dangerous config keys (74–84);
  - a pre-push hook (85);
  - another branch (86);
  - the working-tree manifest (87).

  Round 1 covered the rest: gitdir walks, symlinks, a manifest committed at `HEAD`, and further
  config keys.
- **Row 64.** Base denies this push with the reason "this git command creates, switches or
  deletes a branch", which misreads a push that has a stderr redirect. Head hands the call to
  the human because `2> err` is a captured output, and `CONVENTIONS.md` routes captured outputs
  to the human. The head result is the correct one. The push itself is the one head approves
  silently without the redirect.
- **Row 118.** This is the record-move approval for the exact `LEGACY_RECORD_MOVE` line, run by
  the record's own orchestrator. Every variation was refused:
  - another session gets a prompt (row 119);
  - another destination, a chained command, `-f`, or another slug gets a deny (rows 120–123).

Rows 35–36, 41–42, 45, 91–101, 104–106, 109, 113–114, 116–117 and 120–123 are the opposite case:
head is stricter than base there.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | `find . -fprint0 out`, cwd = project root (row 23) | allow | allow | `python3 harness.py` (scratch): the same PreToolUse Bash JSON piped to `head/agentTooling/hooks/allow-repo-commands.sh` and `base/agentTooling/hooks/allow-repo-commands.sh`, each run with `CLAUDE_PROJECT_DIR` set to its copy and `AGENTTOOLING_PROFILE=cloud`; `-fprint0` writes the file `out` |
| non-blocking | Agent call from session `orch-session-1`, which the record `plans/orchestrations/orch-x/README.md` names as orchestrator, prompt `feature: none — x⏎run agentTooling/run-plans.sh and commit` (row 107) | none | none | `python3 harness.py`: the same Agent JSON piped to both copies' hook, with the record planted in both |
| non-blocking | Agent prompt whose header is malformed but accepted: `feature: mediaCore/Bad_Slug`, `  feature: mediaCore/x` (leading spaces), `feature:mediaCore/x` (no space) (rows 93, 96, 99) | none | none | `python3 harness.py`: the same Agent JSON piped to both copies' hook |

## Non-blocking findings

1. **Pre-existing silent allow: `find … -fprint0 <file>` is approved even though it writes a
   file.**
   - Input: `find . -fprint0 out`. Head: allow. Base: allow.
   - The hook already treats `-fprint` as a write (row 24 gets no output). `-fprint0` is missing
     from that list. Round 1 reported the same thing.
   - What the rule should do instead: class `-fprint0` as a writing `find` action alongside
     `-fprint`, `-fprintf` and `-fls`, so the call goes to the human.
   - Where to file it: `plans/BACKLOG.md`, in a `pull-agenttooling-pr169: backlog` commit. The fix
     belongs upstream in agentTooling.
2. **Prompt-only: an orchestrator gets past the orchestrator-role Agent rule by labelling an
   implementer brief `feature: none — …`.**
   - Head: no output (the call proceeds). Base: no output (base has no Agent rule at all).
   - What the rule should do instead: for a session that a record names as orchestrator, refuse
     a `feature: none` brief too, unless it goes to a read-only subagent type (`Explore`,
     `Plan`). Alternatively, refuse a brief that names a build script (`BUILD_SCRIPTS`).
   - Where to file it: `plans/BACKLOG.md`, for an upstream fix.
3. **Pre-existing: the brief-header parser accepts headers that attribute to no real feature.**
   - It accepts a slug that does not match `SLUG_PATTERN` (`Bad_Slug`), leading whitespace, and a
     missing space after `feature:`.
   - Head: no output (accepted). Base: no output (base has no header rule).
   - Impact: these break cost attribution only. They grant no capability.
   - What the rule should do instead: require the exact `feature: <repo>/<slug>` shape, with
     `<slug>` matching `shared_rules.SLUG_PATTERN`, and deny with the expected format as the
     reason.
   - Where to file it: `plans/BACKLOG.md`.

## Blocking findings

None. No input's result on this head is more permissive than base's in a way I would report as
wrong.

Observations that are not findings:
- Rows 102–103, a malformed Agent `tool_input` (prompt missing or not a string), print nothing
  on both copies. Claude Code does not send these shapes, and an empty output is a prompt, not
  an allow.
- The base has no `feature-close.sh` audit gate, so the gate cannot regress against it.
