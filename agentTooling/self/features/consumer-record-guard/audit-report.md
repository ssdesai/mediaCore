Verdict: clean

# Security audit 02: consumer-record-guard

Head: `9f40ab4` (`HEAD` of `claude/consumer-record-guard`). Base: `origin/main`. Since round 1
the diff changed only `analysis/roots.py` (it pulls the new predicate `self_record_write_allowed()`
out of `record_write_refusal`, with no change in behaviour) and `analysis/coordinator_check.py`
(the advisory names `--self` only where `self_record_write_allowed()` is true). This round re-ran
the round-1 attack families against the new head, and also attacked the advisory change.

**Method.** `git archive HEAD` and `git archive origin/main` were written to tarballs under
`/tmp/plan-capture.G3hRPg/scratch/work/`. Each input ran once on a fresh head copy and once on a
fresh base copy, each in its own `mktemp -d`:
- A **vendored** copy is a consuming git repo with the archive extracted to
  `agentTooling/`, which has no `.git` of its own.
- A **standalone** copy is the archive extracted to `agentTooling/` and `git init`-ed there.

Every copy carries a shipped record at `self/orchestrations/shipped/README.md` (repo
`agentTooling`, session `eeee…c`). A fake `$HOME` holds priceable transcripts for the sessions
`dddd…b`, `cccc…a` and `eeee…c`, whose cwd `/w` lies outside any checkout. Each result is the
exit code, whether anything under the copy's `agentTooling/self/orchestrations/` changed (a sorted
`cksum` + `find` snapshot taken before and after), and the first salient line of output. The
harness is `/tmp/plan-capture.G3hRPg/scratch/attack.sh`.

## Rules the diff adds or changes

The diff changes no PreToolUse hook file and no settings: `git diff origin/main...HEAD --stat`
lists no path under `hooks/` or `.claude/`. `hooks/allow-repo-commands.sh` imports neither
`analysis/roots.py` nor `coordinator_check.py` (grep). So the hook's decisions are identical on
head and base by construction. Every rule audited is a **record-tool refusal**, where "allowed"
means the tool went on and wrote into a vendored copy's `agentTooling/self/orchestrations/`.

- **G1** `orchestration-start.sh --self <slug>` (orchestrator and `--coordinator`) refuses in a
  vendored copy before any write. It asks `roots.py self-write <slug>`, and any non-zero exit
  refuses.
- **G2** `manifest.py --self --orchestration <slug>` with `add-feature`, `set-feature` or
  `set-window-to` refuses in a vendored copy (`load_orchestration(write=True)`). `get` still reads.
- **G3** `orchestration_capture.py --self` and `orchestration-capture.sh --self` refuse in a
  vendored copy.
- **G4** `report.py --self --orchestration` refuses in a vendored copy.
- **G5** The `roots.py` CLI gains `self-write <slug>`, and `stranded <slug>` must be unchanged.
- **G6** (round 2) The coordinator advisory names `orchestration-start.sh --self <slug>` only when
  `self_record_write_allowed()` is true, and `orchestration-start.sh <slug>` otherwise. It is
  advice text, not a gate. "More permissive" would mean it now steers a vendored copy toward a
  `--self` write.
- **Swap check:** `record_write_refusal` returns either its own refusal or `record_refusal`'s
  answer unchanged. So at each of the four call sites it is at least as strict as the
  `record_refusal` it replaces. No call site moved from a write check to a read check.

## Attempts

Each result reads rc / wrote under `agentTooling/self/orchestrations/` / message. `AT` is the
copy's agentTooling, `D` is the copy's run directory, and `O`, `K` and `L` are the session ids
`dddd…b`, `cccc…a` and `eeee…c`.

| id | input | layout / prep | head | base |
|---|---|---|---|---|
| S1 | `bash AT/orchestration-start.sh --self wave --session O` | vendored | 1 / no / refused (vendored text) | 0 / YES / record written |
| S2 | same, `--coordinator --session K` | vendored | 1 / no / refused | 0 / YES |
| S3 | `env CLAUDE_CODE_SESSION_ID=O bash AT/orchestration-start.sh --self wave` | vendored | 1 / no / refused | 0 / YES |
| S4 | `AT/orchestration-start.sh --self wave --session O` (direct exec) | vendored | 1 / no / refused | 0 / YES |
| S5 | `env env /usr/bin/env AT/orchestration-start.sh --self wave …` | vendored | 1 / no / refused | 0 / YES |
| S6 | `nohup AT/orchestration-start.sh --self wave …` | vendored | 1 / no / refused | 0 / YES |
| S7 | `bash -c 'exec -a x "$0" --self wave …' AT/orchestration-start.sh` | vendored | 1 / no / refused | 0 / YES |
| S8 | `find AT/orchestration-start.sh -exec {} --self wave … \;` | vendored | 0 (find's rc) / no / refused | 0 / YES |
| S9 | `printf '%s\n' --self wave … \| xargs AT/orchestration-start.sh` | vendored | 123 / no / refused | 0 / YES |
| S10 | `echo "bash AT/orchestration-start.sh --self wave …" \| bash` | vendored | 1 / no / refused | 0 / YES |
| S11 | `bash AT/orchestration-start.sh "--se""lf" wave …` | vendored | 1 / no / refused | 0 / YES |
| S12 | `… --self 'wave' --session O --coordinator` (flag order) | vendored | 1 / no / refused | 0 / YES |
| S13 | `… --self ../x …` | vendored | 1 / no / slug pattern | 1 / no / slug pattern |
| S14 | `… --self shipped …` (folder exists) | vendored | 1 / no / refused (vendored text) | 1 / no / already exists |
| S15 | `env -i PATH=/usr/bin:/bin HOME=… bash AT/orchestration-start.sh --self wave …` | vendored | 1 / no / refused | 0 / YES |
| S16 | a symlink to the start script in `D/elsewhere/`, run with `--self wave` | vendored / symlink | 1 / no / refused | 0 / YES |
| S17 | `cd AT && bash ./orchestration-start.sh --self wave …` | vendored | 1 / no / refused | 0 / YES |
| S18 | `env PATH=D/fakebin:/usr/bin:/bin … --self wave` (a fake `python3` that exits 0 on `self-write` and otherwise execs the real one) | vendored / fakepy | 0 / **YES** | 0 / YES |
| S19 | an empty `.git` file planted in `AT/`, then `--self wave` | vendored / gitfile | 0 / **YES** (warns "no git directory found") | 0 / YES |
| S20 | an empty `.git/` dir planted in `AT/`, then `--self wave` | vendored / gitdir | 0 / **YES** | 0 / YES |
| S21 | `env PYTHONPATH=D/evil …` (a `shared_rules.py` that loads the real one and sets `GIT_ENTRY=""`), then `--self wave` | vendored / evilrules | 0 / **YES** | 0 / YES |
| S22 | `… --self wave --from 2026-07-02T09:00:00Z …` | vendored | 1 / no / refused | 0 / YES |
| S23 | `--self wave` (control) | standalone | 0 / YES | 0 / YES |
| S24 | `wave --coordinator` without `--self` (control) | vendored | 0 / no (writes `plans/orchestrations/wave`) | 0 / no / same |
| M1 | `python3 -B AT/analysis/manifest.py --self --orchestration shipped add-feature repo=agentTooling slug=feat-t` | vendored | 1 / no / refused | 0 / YES |
| M2 | `… set-feature repo=agentTooling slug=feat-s pr=x` | vendored | 1 / no / refused | 0 / YES |
| M3 | `… set-window-to 2026-07-02T12:00:00Z` | vendored | 1 / no / refused | 0 / YES |
| M4 | `… --orchestration shipped --self add-feature …` (flag order) | vendored | 1 / no / refused | 0 / YES |
| M5 | M1 without `-B` | vendored | 1 / no / refused | 0 / YES |
| M6 | `… --self --orchestration shipped get session` (read control) | vendored | 0 / no / prints `L` | 0 / no / same |
| M7 | a planted `.git` file in `AT/`, then M1 | vendored / gitfile | 0 / **YES** | 0 / YES |
| M8 | the PYTHONPATH `shared_rules` shadow (as S21), then M1 | vendored / evilrules | 0 / **YES** | 0 / YES |
| M9 | M1 (control) | standalone | 0 / YES | 0 / YES |
| C1 | `bash AT/orchestration-capture.sh --self shipped` | vendored | 1 / no / refused | 0 / YES (planning.json) |
| C2 | `python3 -B AT/analysis/orchestration_capture.py --self shipped` | vendored | 1 / no / refused | 0 / YES |
| C3 | `bash AT/orchestration-capture.sh shipped` (no `--self`) | vendored | 1 / no / "no record at plans/orchestrations/shipped" | 1 / no / same |
| C4 | a planted `.git` file in `AT/`, then C1 | vendored / gitfile | 0 / **YES** | 0 / YES |
| C5 | C1 (control) | standalone | 0 / YES | 0 / YES |
| R1 | `python3 -B AT/analysis/report.py --self --orchestration shipped` | vendored | 1 / no / refused | 0 / YES (report.json/md) |
| R2 | `… --orchestration=shipped --self` | vendored | 1 / no / refused | 0 / YES |
| R3 | `… --orchestration shipped` (no `--self`) | vendored | 1 / no / "no record at plans/…" | 1 / no / same |
| R4 | a planted `.git/` dir in `AT/`, then R1 | vendored / gitdir | 0 / **YES** | 0 / YES |
| R5 | R1 (control) | standalone | 0 / YES | 0 / YES |
| T1 | `python3 -B AT/analysis/roots.py self-write x` | vendored | 1 / – / prints the refusal | 2 / – / no such subcommand |
| T2 | `… roots.py self-write x y` | vendored | 2 / – / usage | 2 / – |
| T3 | `… roots.py stranded shipped` (G5: unchanged) | vendored | 1 / – | 1 / – |
| T4 | `… roots.py self-write x` | standalone | 0 / – | 2 / – |
| T5 | `… roots.py self-write '../../x'` | vendored | 1 / – / refused | 2 / – |
| A1 | `python3 -B AT/analysis/coordinator_check.py O AT --self` | vendored | 0 / no / names `orchestration-start.sh <slug>` | 0 / no / names `orchestration-start.sh --self <slug>` |
| A2 | same without `--self` | vendored | 0 / no / names `orchestration-start.sh <slug>` | 0 / no / same |
| A3 | A1 | standalone | 0 / no / names `--self <slug>` | 0 / no / same |
| A4 | a planted `.git` file in `AT/`, then A1 | vendored / gitfile | 0 / no / names `--self <slug>` | 0 / no / same |
| A5 | `coordinator_check.py L AT --self` (the session the shipped record names) | vendored | 0 / no / silent (counted as recorded) | 0 / no / same |
| A6 | `coordinator_check.py O D --self` (the consumer root as the checkout) | vendored | 0 / no / names `orchestration-start.sh <slug>` | 0 / no / names `--self <slug>` |

**What the table shows.** On the head, every input in a vendored copy that reaches the new check
is refused, and nothing is written. The head writes in a vendored copy only for inputs that
change what the check trusts:
- the `python3` on `PATH` (S18);
- a `.git` planted in the copy (S19, S20, M7, C4, R4);
- a `PYTHONPATH` that shadows `shared_rules` (S21, M8).

The base writes for every one of those inputs too, so none of them is a regression.

**The advisory (A1, A6).** It now names the start that writes the consumer's own record, where
the base named a `--self` start that writes into the vendored subtree. That is stricter, not
more permissive. With a planted `.git` (A4) the head and the base both name `--self`, which
matches what the start then does in S19.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | S18: a `python3` earlier on `PATH` that exits 0 for `self-write`, then `orchestration-start.sh --self wave` in a vendored copy | allowed: rc 0, record written under `agentTooling/self/orchestrations/wave/` | allowed: rc 0, record written | `env PATH=$D/fakebin:/usr/bin:/bin bash $AT/orchestration-start.sh --self wave --session O` on a head copy and a base copy (attack.sh case S18) |
| non-blocking | S19/S20/M7/C4/R4: an empty `.git` file or dir planted in the vendored `agentTooling/`, then any `--self` writer (start, `manifest.py add-feature`, capture, report) | allowed: rc 0, writes under `agentTooling/self/orchestrations/` | allowed: rc 0, the same writes | attack.sh cases S19, S20, M7, C4, R4 (prep `gitfile` / `gitdir`) on head and base copies |
| non-blocking | S21/M8: `PYTHONPATH` pointing at a `shared_rules.py` that loads the real one and sets `GIT_ENTRY=""`, then a `--self` writer in a vendored copy | allowed: rc 0, record written | allowed: rc 0, record written | `env PYTHONPATH=$D/evil bash $AT/orchestration-start.sh --self wave --session O` and `env PYTHONPATH=$D/evil python3 -B $AT/analysis/manifest.py --self --orchestration shipped add-feature …` on head and base copies (attack.sh cases S21, M8) |

## Non-blocking findings

All three are **pre-existing silent allows**: the base writes into the vendored
`self/orchestrations/` for the same input, and so does the head. Round 1 reported the same three,
and `self/BACKLOG.md` does not carry them yet. This feature files each one there before it closes.

1. **Pre-existing silent allow: `python3` taken from `PATH` (S18).**
   - Results: head allowed, record written; base allowed, record written.
   - Why: `orchestration-start.sh` asks a bare `python3` for the decision, so whoever controls
     `PATH` controls the answer. That same caller also controls `git` and `bash` and could write
     the file directly, so the real cost is low.
   - **What the rule should do instead:** have the Python side of the start that writes the
     record re-check `record_write_refusal` itself, so a faked shell-side answer is not enough.
     Or resolve the interpreter to an expected absolute path.
2. **Pre-existing silent allow: a `.git` planted in the vendored copy (S19, S20, M7, C4, R4).**
   - Results: head allowed; base allowed.
   - Why: `is_standalone_checkout` and the shell's `[[ -e $SCRIPT_DIR/.git ]]` treat any `.git`
     entry as "own checkout", even an empty file or directory that git rejects. S19 even warns
     "no git directory found" and writes anyway.
   - **What the rule should do instead:** call a copy standalone only when its `.git` is a real
     git dir (`git -C <dir> rev-parse --show-toplevel` equals the dir). And/or treat a copy as
     vendored whenever an ancestor checkout tracks `agentTooling/`.
3. **Pre-existing silent allow: `PYTHONPATH` shadowing `shared_rules` (S21, M8).**
   - Results: head allowed; base allowed.
   - Why: `roots.py` appends `hooks/` to `sys.path`, so a `shared_rules.py` earlier on
     `PYTHONPATH` wins and can redefine `GIT_ENTRY`.
   - **What the rule should do instead:** put `hooks/` first (`sys.path.insert(0, …)`), and have
     the record tools' shell entry points run `python3 -E -B` so `PYTHONPATH` is ignored for the
     decision.

There are no blocking findings, so there is no reproduction section.
