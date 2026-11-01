# NOTES — hook-opaque-commands-and-audit

Rulings the implementer made where the spec (`review/incomplete/108-review-opus.md`
§1–§6) left a choice, each with its rationale and where a reader finds it in the tree.

1. **A subagent's hook payload carries `agent_id`, and the counter is keyed on
   `session_id` + `agent_id`.** The spec asked to establish this. The Claude Code hooks
   reference (`https://code.claude.com/docs/en/hooks`, "Common input fields") says
   `agent_id` is "present only when the hook fires inside a subagent call. Use this to
   distinguish subagent hook calls from main-thread calls", alongside `agent_type`;
   `session_id` and `transcript_path` are the **parent's** in both cases. So the key is
   the pair — with `session_id` alone a delegate's rewrites would escalate its
   coordinator, and the coordinator would get an `ask` for a command it never wrote.
   Asserted in `self/tests/hook-escalation.sh` 3d–3f; recorded in `hooks/README.md` →
   "Escalation after N rewrites" and in the Cross-layer dependencies list.

2. **The opaque check runs LAST — after the three shape denies and after the approval
   analysis has declined.** The spec builds "cannot read" partly from "the analysis's
   existing structural refusals (a `$`, backtick, `<` or `>` outside single quotes; a
   line break; a `#`; an unbalanced quote; a token that will not tokenize)". Taken
   literally that denies commands the hook currently **approves** — `ls src # list it`,
   `grep -n '\$HOME' README.md`, `cat 'a$b'` all carry one of those and are in the ALLOW
   list — and commands whose refusal has nothing to do with readability: `cat README.md >
   out.txt` and `echo hi > f` are refused for *writing*, and "write the script to the
   scratchpad" is not their fix. Two decisions follow, and they are what the acceptance
   contract's "the readable commands are unchanged" asks for:
   - the check runs after the approval, so an approved command is never opaque by
     construction, and
   - the category is the **six named shapes** in §1 and not the structural refusals as
     such. Every structural refusal that genuinely hides code is one of the six; the rest
     (a redirect, a `~`, a line break, an unbalanced quote) still print nothing, exactly
     as `rm -rf x` does — *refused*, not *opaque*, which is the distinction the contract
     draws in its own words.
   The deviation is deliberate and is in `hooks/README.md` → "The opaque shape"; the
   widening it declines is `self/BACKLOG.md`.

3. **Which existing test cases moved.** The contract says every existing case still
   holds. Every one does except the ones this feature exists to change, and each was
   *moved* into the new `OPAQUE_DENY` / `OPAQUE_NOT_DENIED` groups rather than deleted,
   so nothing lost its assertion: `python3 -c`, `python3 -B -c`, `.venv/bin/python -c`,
   `bash -c`, `sh -c ls`, `eval ls`, `ls | sh`, `ls |& sh`,
   `find . -name x -execdir sh -c id \;` and `ls $(cd ROOT && pwd)/src` went from
   `prompt` to `DENY`. A deny is strictly stronger than a prompt, so the bypasses those
   cases guarded are still guarded.

4. **A payload with no `session_id` is denied every time and never escalates.** There is
   no session to count against, and the safe direction is another deny rather than an
   `ask` nobody asked for. It also keeps `self/tests/allow-repo-commands.sh`
   deterministic: that file sends no session, so it writes no state at all and asserts
   decisions one command at a time. `hook-escalation.sh` 4e.

5. **A readable command resets the counter even when it is DENIED.** The spec says "any
   Bash command the analysis *can* read resets the counter, whether it approves or not".
   A chained `cd`, a ref-moving git command and the assignment shape are all commands the
   analysis read fine — it denied them for what they *do* — so each clears the count.
   `hook-escalation.sh` 2a–2d runs the reset three times, once per outcome.

6. **A line carrying any heredoc is judged on the heredoc alone.** A heredoc's body lines
   read as commands to every scanner in the file, so evaluating the other five shapes
   over them would deny `cat <<'EOF' … python3 -c … EOF` for text that is a string. This
   is the same guard `chains_chdir`, `mutates_git_refs` and `assigned_names` already
   keep, for the same reason. The cost is a conservative miss: a real
   `python3 - <<'EOF'` nested inside a `cat` heredoc prompts instead of denying.

7. **A heredoc inside a `$(…)` belongs to the substitution's program, not the line's.**
   Without this, `git commit -m "$(cat <<'EOF' … EOF)"` — Claude Code's own
   commit-message shape, and an explicit exemption in the spec — reads as a heredoc
   feeding `git` and is denied. `heredoc_programs` takes the owner from the innermost
   `$(` before the operator when there is one.

8. **The executor scratch directory lives INSIDE `CAPTURE_TMPDIR`**, not beside it as a
   second `mktemp -d`. Three reasons: the existing teardown (and `on_interrupt`'s, on the
   paths that never reach it) removes it for free; there is no second directory to leak;
   and `self/tests/stream-capture.sh`'s `capture_dirs_left` counts directories at depth 1
   under `$TMPDIR` and asserts exactly one in flight (8b, 9b), which a sibling would
   break. It is still "under `$TMPDIR` by an explicit template", transitively.

9. **`env` rather than a `NAME=value` prefix at the launch site.** The two variable names
   are named constants, and bash 3.2 cannot assign through a variable holding the name.
   `env` execs, so `$!` is still `claude`'s own pid and the `wait`/marker machinery is
   untouched.

10. **The scratch entry point takes the script and nothing else.** `bash <scratch>/x.sh`
    and `python3 [-B] <scratch>/x.py`, one argument. An argument after the script is one
    more thing nothing in the hook has checked, and this is the only rule in the file
    that reaches outside the project root, so it is the one to keep narrowest. A script
    that needs arguments can read them from a file beside itself. Filed in
    `self/BACKLOG.md` in case the narrowness bites.

11. **`ruff --fix`, a bare `ruff format` and `mypy --install-types` are closed even
    though runners were out of the spec's literal list.** §4's mandate is any "write,
    exec or read outside the root approved without a prompt", and `ruff check --fix src`
    rewrote the tree with no prompt at all. The existing "Repo code runs" accepted limit
    covers a suite *executing* what the repo contains, not a linter rewriting it — so the
    limit is now stated with that line drawn. `RUNNER_FORBIDDEN_FLAGS` plus a report-flag
    rule for `ruff format`.

12. **An attached-value flag carrying a `/` is refused outright rather than parsed.**
    `grep -f/etc/hosts src` read outside the tree because `value_confined` returns True
    for any token starting with `-`. Where an attached option's value begins is the
    program's business (`-fsrc/a.py` is `-f src/a.py`, but `-o/tmp/x` is `-o /tmp/x` and
    `-la` is neither), so the analysis cannot say which part is the path. It refuses the
    token instead: a prompt, never an approval. No flag this hook approves is spelled
    with a `/` in it, which is asserted by the whole ALLOW list still passing.

13. **`capture_planning.py --force` was added to `CAPTURE_WRITING_FLAGS` although it is
    not a demonstrated bypass.** With a `--list-` flag present the listing mode exits
    before any write, so nothing escapes today. It is in the table as a tightening, not
    as a closed bypass: `--force` is the flag that makes a capture overwrite a frozen
    cost record, and a reader should not have to reason about argparse's ordering to know
    it cannot reach a write from here.

14. **The `wire-settings.py` gap is a doc note, not a change.** `git worktree
    move|lock|unlock|repair` and `git branch --delete|--move` are denied by the hook and
    have no `permissions.deny` prefix twin, and unlike the run-time-value and opaque
    denies they *could* have one. Adding them rewrites this checkout's committed
    `.claude/settings.json`, `self/tests/hook-wiring.sh`'s rule list and every consuming
    repo's settings on its next sync — a blast radius this feature has no reason to take,
    and `capture-on-branch` is in flight. `hooks/README.md` → "The `wire-settings.py`
    gap" and `self/BACKLOG.md`.

15. **`grep -n '<<' src/a.py` prompts rather than being approved.** A quoted `<<` is not
    a heredoc (the opaque check skips single-quoted text, which is what keeps it out of
    the deny) but it lexes as an all-punctuation token, which the approval analysis has
    always refused. Asserted at its real value in `OPAQUE_NOT_DENIED` rather than at the
    value the shape suggests.

## Rework (2026-09-17)

The review pass escalated four findings instead of fixing them (`self/review-report.md`
E1–E4). Each is fixed here as the report wrote it; the rulings above stand unchanged
except where 6 is narrowed by R3.

R1. **`--add-dir "$scratch_dir"` at the `claude -p` site, as a named constant
    (`EXECUTOR_ADD_DIR_FLAG`).** `--permission-mode acceptEdits` auto-accepts an Edit or a
    Write only under the executor's *working* directory, and the scratch directory is
    under `$TMPDIR`. Without the flag every executor prompt named a directory the
    executor's own Write tool would then refuse — the deny's rewrite had nowhere to land,
    and under `--allowedTools Bash` the third attempt simply ran. Asserted end to end in
    `self/tests/stream-capture.sh` 10h–10i, through the stub recording its whole argv
    (`$CLAUDE_STUB_ENV_LOG.argv`, one word per line) beside the environment it already
    recorded — the launch site is the only thing that sets the flag and a stub is the only
    way to see it. One line in `RUNNER.md` → "The executor's environment" and a clause in
    `hooks/README.md` → "Headless runners and the scratch directory".

R2. **`interpreter_takes_code` stops at the first word that is not a flag.** It used to
    look for the code letter in *every* word after the interpreter, so
    `python3 src/a.py -c conf.yaml` and `node src/a.js -e x` were denied for hiding code
    they do not hide — and counted toward the `ask`. A consuming repo's
    `python3 tool.py -c config.yaml` hit it every time. Every shape the check exists to
    catch puts the code flag *before* any script by construction (the flag is what
    replaces the script), so nothing in `OPAQUE_DENY` moves. `OPAQUE_NOT_DENIED` gains
    `python3 src/a.py -c conf.yaml` and `bash self/gate.sh -c x`.

R3. **A `cat` heredoc no longer excuses the rest of the first line.** Ruling 6 above —
    "a line carrying any heredoc is judged on the heredoc alone" — is right about the
    *body* and was wrong about the line the operator sits on. `is_opaque` returned as soon
    as every heredoc fed `cat`, so `cat <<'EOF' | python3` and
    `bash -c "$(cat <<'EOF' … EOF)"` prompted, and worse, counted as readable and reset
    the counter to zero — the two rewrites a model reaches for first once
    `python3 - <<EOF` is denied. Now, when every heredoc feeds `cat`, `code_as_string` and
    `piped_into_interpreter` still run over the segments before the first line break
    (`segments_before_line_break`, keyed on the existing `LINE_BREAK_CHARS`). A heredoc
    body always begins after that break, so it stays unjudged and the
    `git commit -m "$(cat <<'EOF' … EOF)"` exemption is untouched — still asserted in
    `OPAQUE_NOT_DENIED`. Only those two shapes are checked on that line: a `$(…)` in a
    path or a one-line compound beside a heredoc keeps ruling 6's conservative miss,
    because neither can be told from body text with any confidence.

R4. **The env-prefix audit case is now a row in "Considered and not a bypass".** The
    guard was always there and always asserted (`subcommand_allowed` refuses any
    assignment at command position; `FOO=1 ls` and `X=/tmp/e/pytest src/a.py`). §4's
    record is "an assertion **or** a README row", and this was the one case with the
    assertion and no row, so the next audit would have re-derived `PAGER=… git log`,
    `GIT_DIR=`, `PYTHONPATH=`, `LD_PRELOAD=` and `IFS=` from scratch.

R5. **The `hooks/` Edit deny reaches a worktree's copy for a session whose project root
    is that worktree (the runners' executors), and not for a delegate of a session rooted
    at the primary — ruling 6 of `start-procedure-and-routing` holds only for the
    latter.** This is why the review executor could not apply its own three-line fixes
    ("File is in a directory that is denied by your permission settings") while this
    rework, delegated from a session rooted at the primary checkout, edits the same files
    freely. `Edit(**/agentTooling/hooks/**)` matches at any depth and `--self` writes
    `Edit(/hooks/**)`, whose `/` anchors at *the session's* project root — which for a
    `run-review.sh` executor is the worktree. The `CHECKPOINT.md` "Learned" note that
    reads "anchored at the PRIMARY checkout" is true only of the session that wrote it.
    The consequence for briefing: **a verify or review pass must never be asked to change
    anything under `hooks/`** — it will read the fix, find it refused, and escalate, which
    is exactly what happened. Recorded in `hooks/README.md` → "The deny rules" → `Edit`.
