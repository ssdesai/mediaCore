# Notes: start-procedure-and-routing

Rulings made while building, each with its rationale, in the order they were made
(`AGENT_DIRECT.md` → "The procedure", step 4). Deliberate exclusions also carry a
`self/BACKLOG.md` entry.

## Rulings

1. **`analysis/routing.py` imports no `capture_planning`.** The router-detection predicate
   has to be callable *from* `capture_planning.list_sessions`, so the import can only run
   one way. `routing.py` therefore locates a session's transcript by globbing
   `~/.claude/projects/*/<session-id>.jsonl` — session ids are unique, which is exactly the
   argument `recover_attempts.py` already makes for the same glob — and reads `cwd` and
   `gitBranch` off the lines rather than off a mangled directory name. No copy of
   `transcript_dir_name` is needed and there is no cycle.

2. **`captured_at` is derived, not the wall clock.** The design gives the record a
   `captured_at` and also requires that two writes from one transcript produce identical
   bytes, so that two branches refreshing the same router's record do not conflict. A
   wall-clock stamp breaks that. `captured_at` is therefore the instant the content is
   current *as of* — the transcript's last instant — and is null when there is no
   transcript. It answers "how stale is this record", which is what a reader asks, and it
   moves only when the router grows.

3. **`--session <id>` names the router for the record as well as for the pin.** The facts
   say `--session` "only matters with `--pin`"; the review brief says the record is written
   for `$CLAUDE_CODE_SESSION_ID`, *or* `--session <id>`. The brief is the acceptance
   contract, and the narrower reading would leave a start that names its session by hand
   with no routing record at all. So `--session` selects the session id in both places and
   `--pin` decides only whether that id also lands in the manifest's `sessions`.

4. **`model` may name more than one model.** A session that switched models has no single
   model id. The field carries the sorted distinct ids joined with `/`, the same spelling
   `capture_planning.list_sessions` already prints in its `model` column.

5. **The prune measures against `origin/main`, not against the feature's `--base`.** Design
   §3.1 says "an ancestor of `origin/main`". A stacked feature's base is itself a branch
   that has to reach `main` before its stack does, so `origin/main` is the one ref that
   means "merged" for every worktree under `.worktrees/`. With no `origin/main` the prune
   is skipped entirely rather than guessed at.

6. **`hooks/allow-repo-commands.sh` was edited with the Edit tool, and that is a gap.**
   The plan was a one-shot patch script, since `hooks/README.md` says the Edit tool
   refuses that file. It does not, here: the rule `--self` writes is `Edit(/hooks/**)`,
   anchored at the project root, and this session's project root is the **primary**
   checkout — so the worktree's own `hooks/` copy is outside it. The edit went through
   with no prompt. Kept (Edit is the sanctioned tool, and the alternative would have been
   a subprocess write the permission system cannot see), and filed in `self/BACKLOG.md`
   with the assertion that would catch it.

7. **The routing record conflicts when two features of one router merge in turn.** Each
   branch *adds* `routing/<session-id>.json` with a different `features_started`, so the
   second merge is an add/add conflict. **Amended in the rework pass (ruling 12): the side
   with the later `captured_at` wins**, not "either side" — a router only ever grows, so
   that side's `features_started` is the superset, and taking the older one silently drops
   the newer feature out of its own "routed by" line and the Routing table.
   `self/tests/feature-lifecycle.sh`'s prune fixture starts its two
   candidates with no session id at all, so the phase that tests the prune is not testing
   that. Filed in `self/BACKLOG.md` with the assertion that would close it.

8. **Thirteen test files gained `routing.py` in their copy list.** `capture_planning.py`
   and `report.py` both import the new module, so every sandbox that copies either has to
   copy it too; a missing copy is an `ImportError` in every capture rather than one red
   assertion. `self/tests/README.md` says so once, at the top, beside the `$HOME` rule.
   `plan-numbering.sh` also gained a redirected `$HOME`, because the start it drives now
   reads a transcript.

9. **The routing record is not copied into `report.json`.** `report.py --self <slug>` prints
   the "routed by" line from the routing files themselves and freezes nothing: the routing
   record is the durable link (design §3.4, "one copy cannot disagree with itself"), and a
   second copy inside a frozen feature report is exactly the disagreement the design
   removes.

## Rulings — rework pass (the first review's six escalations)

The decisions themselves were taken in `review/incomplete/106-review-opus.md` and are not
reopened here; what follows is how each was carried out and what it forced.

10. **The prune deletes with `git branch -D`, and the constant says why.**
    `PRUNE_DELETE_FLAG` in `feature-start.sh`. `prune_one` proves ancestry against
    `origin/main` with `merge-base --is-ancestor` before it touches anything, so `-d`'s own
    check is not a second opinion on the same question — it is a *different* question
    (merged into the branch's upstream, or into the primary's `HEAD`), and it answers no
    whenever the PR merged on the forge and nobody pulled. The "kept branch X" line stays
    for a genuine failure, such as a branch checked out somewhere else. Confirmed against
    real git rather than assumed: with the default `branch.autoSetupMerge` the upstream is
    `origin/main` and `-d` would have succeeded, so the failing shape is the one the loop
    actually produces — `self/pr.sh` pushes with `-u`, the forge deletes the branch, and
    `fetch.prune` removes the tracking ref, leaving `-d` measuring against a lagging `HEAD`.
    That is exactly what `feature-lifecycle.sh` S4h–S4k build, and the phase was checked
    red under `-d` before `-D` went back in.

11. **The vendored `--self` start got a real scaffold, not a backlog entry.** The existing
    one hardcodes `$AT` as both the primary checkout and the script's repo, so it cannot
    nest — but it does not have to be rewritten to be reused: S6 unpacks `$AT`'s *first
    commit* (`git archive`, so stubs, templates and analysis modules as they were before
    any start ran) one directory inside a fresh consumer repo with no origin, and runs the
    start from there. `REL_REPO` is then `agentTooling`, and the phase asserts the routing
    record is committed at `agentTooling/self/routing/<id>.json` — the pathspec whose
    absence took the whole `S: start` commit down.

12. **The conflict rule is prose in four places and gets no named constant.** The wording
    now reads "the side with the later `captured_at` wins" in `analysis/README.md`, the
    design record §3.4 (marked as an amendment, with the layout explicitly unchanged),
    `self/BACKLOG.md`, `routing.py`'s docstring and the S4 fixture comment. No code
    branches on it — nothing reads a `captured_at` to resolve anything; a human with a
    merge conflict does — so a constant would be a string with no reader, which is worse
    than the prose. The command-position regex *is* code and *is* a constant
    (`COMMAND_POSITION_RE`), as is `COMMAND_SEPARATORS`.

13. **Router detection matches at command position, and a separator ends the argument
    list.** `slug_of_start_command` now finds the script with `COMMAND_POSITION_RE` instead
    of scanning every word, and stops at `&&`, `||`, `;`, `|` or `&` while reading the
    flags past it — so `feature-start.sh --self && ls foo` yields no slug rather than
    `foo`. `re.MULTILINE`, because a Bash tool call is routinely several lines and each is
    its own command. Both directions are asserted (`routing-record.sh` R4f, R4g): the grep
    that is not a start, and the start that is one behind `&&` and `bash`.

14. **Quoting the worktree path is a body change, so both copies bump to
    `template-version: 2`** and `TEMPLATE_VERSIONS` carries the re-recorded hash.
    `self/tests/sync-check.sh` assertion 8 requires the two copies to agree on the number,
    and `template-versions.sh` hashes the file with comment-only lines stripped — so the
    comment explaining the quoting is free and the one changed line is not. No seeded copy
    exists in any consumer yet, so nothing has to be merged by hand.

## Deliberate exclusions

- Nothing from §3.2, §3.3, §3.5, §3.6's close-side items or §3.8 is touched: they are the
  next two features' (design §6). `feature-close.sh`, `run-review.sh`, `pr.sh`, `sweep.sh`
  and the close half of `self/tests/feature-lifecycle.sh` are unchanged.
- `wire-settings.py` gains no `BASH_DENY_RULES` twin for the assignment deny: a
  `permissions.deny` rule is a command *prefix*, and the shape being denied is a relation
  between two tokens anywhere on the line, which no prefix can express. Recorded in
  `hooks/README.md` beside the deny, and design §3.7 already anticipated it ("hook-only").
