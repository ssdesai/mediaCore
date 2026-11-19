Verdict: clean

# Security audit: python-entry-exact (round 2, opus)

## Scope

**The hook has not changed since round 1.** Round 2's rework commit (`99ee402`) touches only
`hooks/README.md`, the tests and the feature's notes. So `git diff origin/main...HEAD` of
`hooks/allow-repo-commands.sh` and the three `analysis/*.py` parsers is the same diff that
round 1 audited. This pass did not re-read round 1's table. It ran its own battery against
that diff.

**How each payload was run.**
- **Copy:** a `git archive HEAD` copy under the pass's scratch directory, `git init`-ed.
- **Orchestration record:** the copy has `self/orchestrations/wave/README.md`, which names
  session S as orchestrator.
- **Payload:** the PreToolUse JSON (`tool_name: Bash`, `session_id`, `cwd` set to the copy
  root, `tool_input.command`).
- **Environment:** `CLAUDE_PROJECT_DIR` set to the copy, `HOME`/`TMPDIR` set to scratch,
  and `AGENTTOOLING_PROFILE=local` unless the table says otherwise.

**How results are recorded.** Every command was run twice: once from a plain session, once
from session S.
- **plain** column:
  - **allow** means silently approved.
  - **ask** means the hook printed nothing and the command falls to the normal prompt.
  - **deny** means sent back with a rewrite.
- **orch** column:
  - **allow** means silently approved.
  - **admitted** means the orchestrator allowlist let the command through to the ordinary
    policy, which then prompted.
  - **deny** means the role denial.

## Rules the diff adds or changes

| # | Rule | Who |
|---|---|---|
| R1 | `capture_planning.py` is approved only as `[--self] --list-sessions\|--list-subagents` followed by that listing's own options. Each option may appear at most once. `--since`/`--for` must be followed by one word that does not start with `-` (`capture_listing_shape`). | plain (silent approval), orchestrator (allowlist) |
| R2 | `manifest.py` is approved only as `[--self] [--orchestration] <slug> get <key>`. The slug must fully match `SLUG_RE`, and the key must not start with `-` (`manifest_get_shape`). | plain |
| R3 | The orchestrator admits `manifest.py [--self] --orchestration <slug> <sub> <operands…>` only under four conditions: the slug fully matches `SLUG_RE`; no word after the slug starts with `-`; `get`/`set-window-to` take exactly one operand; `add-feature`/`set-feature` take one or more. | orchestrator |
| R4 | The orchestrator's `report.py --orchestration <slug> (--checkout <v>)*` also refuses a `--checkout` value that starts with `-`. | orchestrator |
| R5 | `allow_abbrev=False` is set on the top-level parsers of `capture_planning.py`, `manifest.py` (both) and `report.py`. | runtime, both roles |

## Attempts: shapes, B1/B2, R2 edges

| Input (`python3 analysis/…` unless shown) | plain | orch |
|---|---|---|
| `manifest.py a-slug get base` | allow | deny |
| `manifest.py a-slug set-window-to now` | ask | deny |
| `manifest.py --self --orchestration wave get session` | allow | allow |
| `manifest.py --orchestration wave set-window-to now` | ask | admitted |
| `capture_planning.py --list-sessions` | allow | allow |
| `capture_planning.py --self --list-subagents --unclaimed --for agentTooling/x --since 2026-01-01 --everywhere` | allow | allow |
| `capture_planning.py a-slug` / `--force a-slug` | ask | deny |
| B1: `manifest.py --orchestration wave --orchestration get --orchestration=other set-window-to now` | ask | deny |
| B2: `capture_planning.py a-slug --forc --since '--list- x'` | ask | deny |
| `manifest.py a-slug get base extra` / `get` with no key / `get -- base` / `get --help` | ask | deny |
| `manifest.py --self --self a-slug get base` | ask | deny |
| `manifest.py --orchestration --orchestration wave get session` / `--orchestration=wave get session` | ask | deny |
| `manifest.py --self=1 a-slug get base` | ask | deny |
| `manifest.py a-slug init --method x --branch b --base m --from now` | ask | deny |
| `manifest.py a-slug pin-session get` / `get a-slug base` | ask | deny |
| `manifest.py a-slug "get" base` / `g""et` / `ge\t` | allow (each dequotes to `get`, a read) | deny |
| `manifest.py a-slug {get,set-window-to} base` | ask | deny |
| `manifest.py a-slug get {base,--replace}` / `{a-slug,--orchestration} get base` | ask | deny |
| `manifest.py a-slug get base --replace` | ask | deny |
| `manifest.py 'a-slug⏎' get base` / `$'a-slug\n'` / `get 'base⏎x'` | ask | deny |
| `manifest.py A-SLUG get base` / `a.slug` / `a/b` | ask | deny |
| `manifest.py ../x get base` | deny (`..`) | deny |
| `manifest.py a-slug get +base` / `' --replace'` / `—replace` (em dash) | allow (one literal key: a read; run below) | deny |
| `manifest.py a-slug get $(echo --replace)` / backticks | ask | deny |
| `manifest.py a-slug get $X` | deny | deny |
| `… get base < /dev/null` / `>> analysis/manifest.py` / `\| tee x` | ask | deny |
| `… get base; manifest.py a-slug set-window-to now` / `\|\|` | deny (mixed line) | deny |
| `… get base & manifest.py a-slug set-window-to now` | ask | deny |

## Attempts: wrappers, interpreters, script paths

| Input | plain | orch |
|---|---|---|
| `env` / `env env` / `/usr/bin/env` / `command` / `exec -a x` / `nohup` / `sudo` in front of a `get` | ask | deny |
| `echo a-slug \| xargs python3 analysis/manifest.py` | ask | deny |
| `find analysis -name manifest.py -exec python3 {} a-slug set-window-to now \;` | ask | deny |
| `bash -c '…set-window-to…'` / `echo '…' \| sh` | deny | deny |
| `python3 - <<'EOF'` | ask | deny |
| `python3 -c …` / `-m analysis.manifest` / `-X importtime` / `-W error` / `-u` / `-S` / `-i` | ask | deny |
| `PYTHONINSPECT=1 python3 …get…` | ask | deny |
| `python3 -B analysis/manifest.py a-slug get base` | allow | deny |
| `python3 hooks/../analysis/manifest.py …` | deny (`..`) | deny |
| `python3 ./analysis/manifest.py …get…` / `analysis/./manifest.py` | allow | deny |
| `python3 analysis/manifest.py/ …` / `self/manifest.py` (absent) | ask | deny |
| `python3 analysis/manifest.p? … set-window-to now` / `manifes*` / `{manifest,capture_planning}.py` | ask | deny |
| `capture_planning.py analysis/manifest.py --list-sessions` | ask | deny |
| `report.py analysis/manifest.py a-slug set-window-to now` | allow (the unchanged `report.py` row; argparse refuses it, run below) | deny |

## Attempts: R1 (capture listing)

| Input (`python3 analysis/capture_planning.py …`) | plain | orch |
|---|---|---|
| `--list-sessions --list-sessions` / `--list-sessions --list-subagents` | ask | deny |
| `--list-sessions --unclaimed --unclaimed` / `--since x --since y` | ask | deny |
| `--list-sessions --since` / `--since --force` / `--since=--force` | ask | deny |
| `--list-sessions --since x a-slug` / `-- a-slug` | ask | deny |
| `--list-sessions --for a/b` / `--everywhere` (not that listing's options) | ask | deny |
| `--list-subagents --for a/b --for c/d` / `--for --since x` / `--for --force` | ask | deny |
| `--list-sessions --since x --self` / `--self --self --list-sessions` / `--list-sessions --self` | ask | deny |
| `--list-sessions` + `--arm-root /tmp`, `--all`, `--recapture`, `--annotate-frozen`, `--carry-lost`, `--forc`, `-h`, `--unclaimed=1`, `--last-branch-instant a-slug`, `--claim-check a-slug` | ask | deny |
| `--since {x,--force}` / `\--force` / `"--force"` / `'-'-force` / `''--force` / `$'--force'` / `$'\t--force'` / `x$'\n'--force` | ask | deny |
| `--since x{,\ --force}` | deny | deny |
| `--since [-]-force` | allow (note 1) | deny |
| `--since ' --force'` | allow (a value beginning with a space, which argparse reads as a positional; run below) | allow |
| `--since @args` | allow (no `fromfile_prefix_chars`; run below) | allow |
| `--since x --force # x` / `--list-sessions #--force` | ask | deny |
| `--since a#--force` | allow (a literal `#` inside a word) | deny |
| `"--list-sessions"` / `--list-s""essions --since x` | allow (dequotes to the shape) | allow |
| `-list-sessions` | ask | deny |
| `--since x⏎python3 analysis/capture_planning.py --force a-slug` | deny (line break) | deny |

## Attempts: R3 and R4 (orchestrator)

| Input (`python3 analysis/…`) | plain | orch |
|---|---|---|
| `manifest.py --orchestration wave get session` | allow | allow |
| `manifest.py --orchestration wave add-feature repo=r slug=s` / `set-feature …` | ask | admitted |
| `manifest.py --orchestration wave add-feature repo=r --orchestration=other` | ask | deny |
| `manifest.py --orchestration wave add-feature` (no operand) | ask | deny |
| `… get session extra` / `set-window-to now later` / `set-window-to -1` | ask | deny |
| `… wave init` / `set-plans a` | ask | deny |
| `--orchestration wave/x` / `Wave` / `'wave⏎'` | ask | deny |
| `--self --self --orchestration …` / `--orchestration --self wave …` | ask | deny |
| `… get {session,--orchestration=x}` / `set-feature [-]-x` | ask | deny |
| `report.py --orchestration wave --checkout r=/tmp` | ask | admitted |
| `report.py --orchestration wave --checkout --orchestration` / `--checkout=r` / `wave' x'` | allow (plain `report.py` row, unchanged) | deny |
| `report.py --orchestration wave/../x` | deny | deny |
| `report.py --orchestration 'wave⏎x'` | ask | deny |

## Attempts: malformed payloads and profile

| Payload | Result |
|---|---|
| `cwd` missing / `null` / `7` | ask |
| `cwd=/tmp` with the absolute script path (get, and `--force`) | ask |
| `cwd=/tmp` with a relative path that does not exist there | ask |
| `cwd=analysis/`, `python3 ./manifest.py a-slug get base` | allow |
| `cwd=analysis/`, `python3 ./manifest.py a-slug set-window-to now` | ask |
| `command` is a list / `tool_name` is `bash` / not JSON / empty stdin | ask |
| Orchestrator write with no `session_id` / an int `session_id` | ask |
| Orchestrator `session_id` plus an `agent_id` (a delegate), write | deny |
| Duplicate `command` key, last one the write | ask (last wins, as in Claude Code's own parse) |
| Duplicate `command` key, last one the get | allow |
| `AGENTTOOLING_PROFILE=cloud`: get / list | allow |
| `AGENTTOOLING_PROFILE=cloud`: `set-window-to` / `--list-sessions --forc` | ask |

## Attempts: edits to files the rule trusts (in the copy)

| Edit | Result |
|---|---|
| `hooks/shared_rules.py` removed | Every `manifest.py` form asks (`SLUG_RE` matches nothing). Capture listings are still allowed, because R1 has no slug. |
| `SLUG_PATTERN` loosened to `^.*$` | `manifest.py --replace get base`, `--orchestration --orchestration get session`, `--orchestration=x get session` and `init get base` are allowed. At run time argparse refuses each one (`expected one argument`, `invalid choice`), or reads it as `get` on a slug named `init`. The words stay `[slug, get, key]`, so no writing subcommand is reachable. Editing the hook's own module is itself a write that goes to the human. |
| Orchestration record removed | Session S becomes plain and gets the plain results above. |

## Runtime check in the copy (R5 and the allowed edge cases)

Run with `HOME` set to scratch. Afterwards `git status --porcelain` showed only the planted
record, and `HOME` held no files: nothing was written.

| Invocation | Result |
|---|---|
| `capture_planning.py --list-sessions --since ' --force'` / `@args` / `a#--force` | listing, exit 0 |
| `capture_planning.py --self --list-subagents --unclaimed --for agentTooling/x --since 2026-01-01 --everywhere` | listing, exit 0 |
| `capture_planning.py --list-subagents --unclaimed --for ' --force'` | `--for takes <repo>/<slug>`, exit 2 |
| `manifest.py a-slug get ' --replace'` / `—replace` | read attempt (manifest absent, `FileNotFoundError`) |
| `manifest.py --self --orchestration wave get session` | prints the session |
| `report.py analysis/manifest.py a-slug set-window-to now` | `unrecognized arguments`, exit 2 |
| `report.py --orchestration wave --checkout --orchestration` | `--checkout: expected one argument`, exit 2 |
| `capture_planning.py --list-sessions --forc` / `--rec` | `unrecognized arguments`, exit 2 |
| `manifest.py --se a-slug get base` / `--orch wave get session` / `--self --orch …` | `unrecognized arguments`, exit 2 |
| `report.py --orch wave` | `unrecognized arguments`, exit 2 |
| Planted `--force` file, then `--list-sessions --since [-]-force` | `--since: expected one argument`, exit 2 |

## Notes (not bypasses)

1. **A glob in a free-text slot passes R1/R2 in a plain session.** The slots are the
   `--since`/`--for` value and the `get` key, and the inputs are `[-]-force`, `*` and `?`.
   - **Why it is not a bypass:** bash expands the glob only against files that already
     exist, and no tracked file name starts with `-`. Planting one is a write.
   - **Checked at run time:** with such a file planted, argparse refuses the expanded
     `--since --force` (exit 2).
   - **Same as round 1:** this is round 1's note 1, unchanged.
2. **Pre-existing, outside this diff:**
   - `entry_script` identifies a script by basename plus "exists inside the root". In a
     consuming repo, an unrelated `manifest.py`, `capture_planning.py` or `report.py`
     elsewhere in the tree would get these shapes too, and the `report.py` row approves any
     arguments. agentTooling tracks only the three `analysis/` copies.
   - The orchestrator's `report.py` slug check uses `.match`, not `.fullmatch` (round 1's
     note 2).

   Both are recorded so a later pass does not rediscover them. Neither is a rule this diff
   adds or changes.

None of these inputs got past a rule R1–R5 exists to deny.
