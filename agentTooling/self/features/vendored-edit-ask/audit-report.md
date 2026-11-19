Verdict: clean

# Security audit — vendored-edit-ask (round 01)

Hook files changed against `origin/main`: `hooks/wire-settings.py` (code) and
`hooks/README.md` (docs only). `hooks/allow-repo-commands.sh` is unchanged.

## Rules the diff adds or changes

1. **R1 — tree-wide vendored ask** (consumer mode): `POLICY_ASK_RULES` now writes
   `Edit(**/agentTooling/**)` in place of `Edit(**/agentTooling/hooks/**)` +
   `Edit(**/agentTooling/self/orchestrations/**)`, so an Edit/Write tool call to any vendored
   file prompts an attended session and is refused in a headless one.
   `Edit(**/plans/orchestrations/**)` is kept.
2. **R2 — retired narrow asks** (consumer mode): `RETIRED_EDIT_ASK_RULES` removes the two
   narrow asks by exact string, in the same write that adds R1. `--check` reports them as
   `to remove`. `--self` is untouched.

## How it was attacked

- `git archive HEAD` was extracted into the scratch directory. For each case,
  `hooks/wire-settings.py --repo <tmp> --write` and then `--check` ran against a crafted
  `.claude/settings.json`, and the resulting `permissions` were inspected.
- A consumer layout (`<tmp>/consumer/` with `git init` and the archive at
  `consumer/agentTooling/`) was fed PreToolUse payloads to `hooks/allow-repo-commands.sh`.
  The goal was to confirm that nothing the hook approves silently writes into the vendored
  tree, which would sidestep R1. `CLAUDE_PROJECT_DIR` pointed at the copy, and every
  `AGENTTOOLING_*` variable was stripped. The headless run set `AGENTTOOLING_HEADLESS=1`
  with a different scratch dir. In a first run the copy itself sat inside the inherited
  `AGENTTOOLING_SCRATCH`, so scripts in it were approved under the scratch-script rule (the
  intended behaviour). Those results are discarded.

## R1/R2: settings merge (`wire-settings.py`)

| Input settings | `--write` result | `--check` after | Outcome |
|---|---|---|---|
| file absent | ask = broad + plans; no narrow | in-sync | as intended |
| ask = [narrow hooks, narrow orch, plans] | both narrow removed, broad appended | in-sync | as intended |
| ask = [narrow, broad, narrow] | narrow removed, broad kept once | in-sync | as intended |
| narrow asks duplicated ×2 each | all copies removed, broad added | in-sync | as intended |
| deny `Edit(**/agentTooling/hooks/**)` + both narrow asks | deny removed, asks swapped to broad | in-sync | no deny is left shadowing the ask |
| repo's own variant spellings (`Edit(agentTooling/hooks/**)`, trailing space) | kept, broad added | in-sync | repo-owned, still only asks: no loosening |
| allow `Edit(**/agentTooling/**)`, `Edit(**)` | broad ask added, allow untouched | in-sync | ask is evaluated before allow, so it still prompts |
| repo deny `Edit(**/agentTooling/self/orchestrations/**)` | kept | in-sync | stricter, so correctly left |
| ask = [dict, null, 3, narrow] | narrow removed, junk kept, broad added | in-sync | no crash |
| ask `null` / string / permissions `null` / list / top-level `[]` / bad JSON | INVALID, untouched | INVALID | fails loudly, no partial write |
| ask = [`Edit(**/agenttooling/**)`] (wrong case) | correct-case broad added | in-sync | wrong-case decoy does not satisfy the gap |
| ask = [broad only] | plans rule added | in-sync | as intended |
| `--check` on old consumer | rc 1, `2 retired Edit ask rule(s) (…) to remove` | n/a | file unchanged |
| `--self --write` (empty dir) | ask = `Edit(**/hooks/**)`, `Edit(/hooks/**)` | n/a | `--self` unchanged |
| `--self --check` with a narrow ask in the file | UNWIRED (hand-edited) | n/a | drift detected |
| tracked `.claude/settings.json` | ask = `Edit(**/hooks/**)`, `Edit(/hooks/**)` | n/a | unchanged |

No input leaves a consumer settings file without the broad ask or with any rule weaker than
before. No input leaves it with neither the narrow nor the broad rule: removal and addition
happen in one `apply_gaps` call and one `write_text`.

## Hook: can anything silently write into `agentTooling/` around R1?

Consumer layout. `<V>` is `consumer/agentTooling`. "no-decision" means the hook prints
nothing and the human is asked.

| Tool / command | Attended | Headless |
|---|---|---|
| Edit `<V>/analysis/report.py` | no-decision (R1 then asks) | no-decision (R1 then refuses) |
| Write `<V>/orchestration-start.sh` | no-decision | no-decision |
| MultiEdit `<V>/plan-runner-lib.sh` | no-decision | no-decision |
| NotebookEdit `<V>/x.ipynb` | no-decision | no-decision |
| `cp /tmp/x <V>/analysis/report.py` | no-decision (asked) | no-decision |
| `env cp …` | no-decision | no-decision |
| `sed -i s/a/b/ <V>/analysis/report.py` | deny | deny |
| `tee <V>/analysis/report.py` | no-decision | no-decision |
| `echo x > <V>/analysis/report.py` | deny | deny |
| `printf x >> <V>/plan-runner-roots.sh` | deny | deny |
| `cat > <V>/analysis/manifest.py <<'EOF' …` | ask | no-decision |
| `mv /tmp/x <V>/orchestration-capture.sh` | no-decision | no-decision |
| `ln -sf /tmp/x <V>/analysis/report.py` | no-decision | no-decision |
| `git -C <C> checkout -- agentTooling/analysis/report.py` | no-decision | no-decision |
| `git -C <C> apply /tmp/p.diff` | no-decision | no-decision |
| `find <V> -name report.py -exec cp /tmp/x {} ;` | no-decision | no-decision |
| `xargs -I{} cp /tmp/x {}` | no-decision | no-decision |
| `dd if=/tmp/x of=<V>/analysis/report.py` | no-decision | no-decision |
| `install` / `rsync` / `truncate -s0` into `<V>` | no-decision | no-decision |
| `python3 <V>/analysis/manifest.py set x y` | no-decision | no-decision |
| `python3 <V>/analysis/manifest.py slug init` | no-decision | n/a |
| `python3 <V>/analysis/manifest.py slug set-plans a b` | no-decision | n/a |
| `python3 <V>/analysis/manifest.py slug get branches` | allow (read) | n/a |
| `python3 <V>/analysis/report.py [slug]` | allow (read) | allow |
| `python3 <V>/hooks/wire-settings.py --repo <C> --write` | no-decision | n/a |
| `bash <V>/orchestration-start.sh x` (non-orchestrator session) | no-decision | n/a |
| `bash <V>/self/gate.sh` | no-decision | n/a |
| `python3 <C>/plans/evil.py` | no-decision | n/a |

The hook matches only `Bash` and `Agent`, so it never approves an Edit-family tool. R1 is
the only gate on those calls, and nothing in the hook overrides it. No Bash form tried
writes into the vendored tree without a deny or a human prompt.

## Bypasses

None found.

## Not testable here, and not introduced by this diff

- **Claude Code's own glob matcher** (case folding on a case-insensitive filesystem, and
  symlink resolution for an Edit to a link that points into `agentTooling/`) cannot be run
  in this container. The old narrow rules used the same `**/agentTooling/…` spelling, so
  this diff does not change either behaviour. Planting a symlink needs `ln`, which goes to
  the human.
- **Subprocess writes** (a script the headless scratch-script rule approves that then opens
  a vendored file) are outside an Edit rule by design. The diff states this itself
  (`hooks/README.md`: "the sandbox is the remaining layer"), and the sandbox is still off.
  This hole predates the diff and is documented. It is not a bypass of R1.
- **The vendored prefix is assumed to be `agentTooling`.** That is the documented
  `git subtree add --prefix=agentTooling` and was already assumed by the narrow rules.
