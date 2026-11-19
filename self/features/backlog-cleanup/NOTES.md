# Notes — backlog-cleanup

A hand build: the coordinator edited `self/BACKLOG.md` and nothing else outside this folder.

## Rulings

1. **No `report.py` path-resolution entry exists.** The brief asked to drop one fixed by
   humanNetworkMap #307. `self/BACKLOG.md` on `main` has no such entry (no title, no
   `#307`). The only `report.py` entry is the containment one, which is a different defect
   and still open: `compute_orchestration_report` joins a record's `report` path to its
   root with no containment check. It stays.
2. **#156 and #157 closed no entry here.** Neither PR touched `self/BACKLOG.md`, and no
   entry names the vendored-copy record writes or the `<slug>: backlog` close allowance.
3. **Untokenizable-line (a) is not fixed, it is filed elsewhere.** `git push -f origin
   y⏎echo $'\''` is still a prompt (`BASH_PARSED_PROMPT` in
   `self/tests/allow-repo-commands.sh`). The entry already pointed (a) at the next entry
   ("The deny side does not follow a substitution's scope"), so cutting it drops nothing
   still open. (b)–(d) keep their letters so earlier references still resolve.
4. **The sonnet-5-5 rates entry is dropped on the owner's word.** Its assertion is about
   consuming repos' `planning.json` files, which cannot be checked from this tree.
5. **The round-cap entry was already trimmed by #154** (`3141543`); this feature only
   restates it as an assertion: `LIFECYCLE.md` step 5 names no round limit.
6. **The three orchestrator-role entries became one.** The brief named "the
   orchestrator-role friction entry", but `main` had three separate ones (hook reads only
   this checkout; only as strong as the scripts; reverse guard). They are merged with the
   missing fourth gap, "move its own record": `LEGACY_RECORD_REFUSAL` tells a stranded
   record's orchestrator to `git mv` it, and the orchestrator allowlist has no `git mv`.
7. **The reverse-guard entry's title was half wrong.** `orchestration-start.sh` already reads
   the consuming repo's `plans/features/` (`held_feature "$TOPLEVEL" …`); what is missing is
   a test of that half and any message when no git is found.
8. **New-entry corrections against the code.** Item 4: `harness/README.md` does document
   camelCase for program names and branch stems; only the experiment name's rule is
   unstated. Item 7: the harness has no separate blind-judge stage; its judging stage is
   `review` (`HARNESS_REVIEW_MODEL`), whose preamble carries the arm-labelled worktree and
   branch. Item 8: no `claude -p` check exists in the harness or the start scripts; the
   $0.29 check is the wave's own session and is filed as reported.
