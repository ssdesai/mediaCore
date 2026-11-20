Verdict: clean

# Security audit: orchestrator-record-move-guard

Hook files changed against `origin/main`: `hooks/allow-repo-commands.sh`, `hooks/README.md`
(the README edit only documents the code change).

## Rules the diff adds or changes

1. **`orchestrator_stranded_own_record`, a new conjunct of `orchestrator_record_move`.** It
   applies to an orchestrator session's `git mv <tooling>/self/orchestrations/<slug>
   plans/orchestrations/<slug>`, the one orchestrator write the hook approves outright. The
   move is now approved only when the source folder's `README.md` is a regular file and no
   symlink, `names_role(readme, session_id)` holds, and `<python> -B -E -s
   <tooling>/analysis/roots.py stranded <slug>` exits 0. A missing or symlinked classifier, a
   non-zero exit, a timeout (15 s) or an exception means no approval. The change can only
   narrow what the hook approves: on the base the move was approved without this check.
2. **The `session` id is now passed through** `orchestrator_moves_own_record`,
   `orchestrator_git_allowed` and `orchestrator_command_allowed` (taken from
   `payload["session_id"]`).
3. **`main()` was reordered.** `moves` is now computed first, and the result is
   `allowed = moves or orchestrator_command_allowed(...)`, where the base computed
   `moves = allowed and ...`. `orchestrator_command_allowed` itself returns True as soon as
   `orchestrator_moves_own_record` does, with the same arguments, so the set of allowed lines
   is unchanged. The one difference is that `cwd` is now normalised to `cwd_text`, a str or
   None, before the move check. Rows 12, 70, 71 and 72 confirm this empirically.

## Method

- `git archive HEAD` and `git archive origin/main` were extracted under the scratch
  directory.
- Each copy was vendored whole as `agentTooling/` into a fresh consuming repo
  (`consumer/`, `git init`, with a `plans/features/` directory).
- The hook was run as `consumer/agentTooling/hooks/allow-repo-commands.sh`, with the payload
  `{"tool_name":"Bash","session_id":…,"cwd":<consumer>,"tool_input":{"command":…}}` on stdin.
  The environment was `CLAUDE_PROJECT_DIR=<consumer>` and `AGENTTOOLING_PROFILE=cloud`
  (row 2: `local`).
- Records, the ledger (`.git/agenttooling-orchestrators`), the classifier, the `origin`
  remote and symlinks were edited in each copy for each case, and the same setup was used on
  both copies.
- Harness: `python3 /tmp/plan-capture.FQn39D/scratch/audit.py`. It runs every row below on
  the head copy and on the base copy.
- Unless a row says otherwise, session S's record is `agentTooling/self/orchestrations/wavex/README.md`.
  Its fence names S, and it lists `{"repo":"consumer"}`, which makes it stranded.

Result legend:
- `allow`: an explicit allow.
- `silent`: no output, so the input falls through to the normal permission flow.
- `deny (allowlist)`: the orchestrator allowlist denial.

## Attempts

| # | case | command | session | head | base | regression? |
|---|---|---|---|---|---|---|
| 1 | own stranded record | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 2 | own stranded, local profile | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 3 | own record, features [] (shipped shape) | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 4 | own record, ambiguous | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 5 | own record, features not a list | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 6 | own record, repo case CONSUMER | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 7 | remedy mkdir lead (plans/orchestrations absent) | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 8 | other session T, S's stranded record | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 7a7a7a7a | silent | silent | no |
| 9 | no session_id | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | None | silent | silent | no |
| 10 | session_id an int | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 12345 | silent | silent | no |
| 11 | session_id a list | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | [S] | silent | silent | no |
| 12 | cwd missing | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 13 | cwd agentTooling/ | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 14 | README two fences, last names T | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 15 | README two fences, last names S | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 16 | ledger-only: folder names T (B1/O39) | `git mv agentTooling/self/orchestrations/others plans/orchestrations/others` | 0390b390 | deny (allowlist) | allow | no |
| 17 | ledger-only: empty folder (O40) | `git mv agentTooling/self/orchestrations/empty plans/orchestrations/empty` | 0400b400 | deny (allowlist) | allow | no |
| 18 | ledger-only: own stranded record | `git mv agentTooling/self/orchestrations/mine plans/orchestrations/mine` | 0410b410 | allow | allow | no |
| 19 | ledger-only: README.md is a directory | `git mv agentTooling/self/orchestrations/empty plans/orchestrations/empty` | 0400b400 | deny (allowlist) | allow | no |
| 20 | README symlink to S's stranded record | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 21 | classifier missing | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 22 | classifier a symlink to the real one | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 23 | classifier exits 3 | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 24 | classifier a directory | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 25 | planted routing.py / capture_planning.py / shared_rules.py at consumer root (subprocess cwd), record not stranded | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 26 | origin url renames consumer to the record's repo | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 27 | variant | `env git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 28 | variant | `env env git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 29 | variant | `/usr/bin/env git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 30 | variant | `command git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 31 | variant | `exec -a git git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 32 | variant | `nohup git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 33 | variant | `sudo git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 34 | variant | `echo agentTooling/self/orchestrations/wavex \| xargs -I{} git mv {} plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 35 | variant | `bash -c 'git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex'` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 36 | variant | `echo 'git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex' \| sh` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 37 | variant | `find agentTooling/self/orchestrations/wavex -maxdepth 0 -exec git mv {} plans/orchestrations/wavex \;` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 38 | variant | `"git" "mv" "agentTooling/self/orchestrations/wavex" "plans/orchestrations/wavex"` | 5e5e5e5e | allow | allow | no |
| 39 | variant | `git mv 'agentTooling/self/orchestrations/wavex' plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 40 | variant | `git mv agentTooling/self/orchestrations/wa""vex plans/orchestrations/wavex` | 5e5e5e5e | allow | allow | no |
| 41 | variant | `git mv agentTooling/self/orchestrations/wav\ex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 42 | variant | `git mv agentTooling/self/orchestrations/wave? plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 43 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wav""ex` | 5e5e5e5e | allow | allow | no |
| 44 | variant | `git mv agentTooling/self/orchestrations/{wavex,} plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 45 | variant | `git mv agentTooling/self/orchestrations/wavex/ plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 46 | variant | `git mv ./agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 47 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex/` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 48 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex-2` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 49 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex extra` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 50 | variant | `git mv -f agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 51 | variant | `git mv -- agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 52 | variant | `git -C . mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 53 | variant | `GIT_DIR=x git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 54 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex; touch x` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 55 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex && touch x` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 56 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex > out.log` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 57 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex # c` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 58 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex &` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 59 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/$(echo wavex)` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 60 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/${X:-wavex}` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 61 | variant | `git mv agentTooling/self/orchestrations/wavex ~/plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 62 | variant | `git mv agentTooling/self/orchestrations/wavex plans/../plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 63 | variant | `git mv agentTooling/self/orchestrations/wavex\nplans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 64 | variant | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex\ntouch x` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 65 | variant | `mkdir -p plans/orchestrations;git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 66 | variant | `mkdir -p plans/orchestrations  &&  git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 67 | variant | `mkdir -p plans/x && git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 68 | variant | `mkdir -p plans/orchestrations && git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex && touch y` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 69 | variant: another record (coordinator `coord`) | `git mv agentTooling/self/orchestrations/coord plans/orchestrations/coord` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 70 | allowlist sanity after `main()` reorder | `ls plans` | 5e5e5e5e | allow | allow | no |
| 71 | allowlist sanity after `main()` reorder | `touch x` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 72 | allowlist sanity after `main()` reorder | `git status` | 5e5e5e5e | allow | allow | no |
| 73 | classifier hangs 30 s (timeout 15 s) | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 74 | S named by ledger, working-tree README now names T | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | allow | no |
| 75 | plans/orchestrations a symlink | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |
| 76 | record folder a symlink | `git mv agentTooling/self/orchestrations/wavex plans/orchestrations/wavex` | 5e5e5e5e | deny (allowlist) | deny (allowlist) | no |

### Results that differ between head and base

No input is more permissive on the head than on the base. Every row where the two differ
is a base `allow` that became a head `deny`, which is the narrowing the feature intends:

- Rows 3–5: a shipped, ambiguous or unreadable record.
- Rows 16, 17, 19 and 74: B1, where the ledger names the slug but the folder does not hold
  this session's record.
- Rows 21–25 and 73: a classifier that is missing, symlinked, failing or hanging, or modules
  planted at the consumer's root.

### Allowed rows checked for a bypass

These rows are allowed on the head. Each was examined, and none is one:

- **Rows 38–40 and 43** are allowed on both copies. The quotes resolve to exactly the
  approved words, so these are the same move in another spelling.
- **Rows 14 and 15** are allowed on both copies. `names_role` holds when any fence of the
  record names the session, which is the role lookup's own reading, so the record does name
  S and the result is correct.
- **Row 26** is allowed on both copies. Pointing the consumer's `origin` URL at a name the
  record lists makes the classifier read the record as stranded. That needs a write to
  `.git/config`, which is outside the orchestrator's allowlist, and the base approves the
  move without any classification at all. The record is still S's own, so the move takes
  nothing that is not S's.

## Findings

None.

## Non-blocking findings

None.
