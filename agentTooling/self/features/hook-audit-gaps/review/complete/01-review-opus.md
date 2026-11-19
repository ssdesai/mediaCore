# 01 — review: hook-audit-gaps

Written by the coordinator before the build, from the audit findings and the owner's
instruction, not from the builder's report. A security audit (`NN-audit-opus.md`) runs
beside this review because the diff touches `hooks/`; this pass is the ordinary review.
"No findings" is a legitimate verdict.

## What the feature was supposed to do

Close three gaps in the Bash policy hook `hooks/allow-repo-commands.sh`, plus one the
parent coordinator added. The feature's `NOTES.md` has the exploits and rulings.

- **B1, heredoc terminator.** A whole-argument `"$(cat <<'EOF' … )"` (the `git commit -m`
  and `gh pr create --body` shapes) has its body end exactly where bash ends it: at a line
  holding only the delimiter (leading tabs stripped under `<<-`). A line such as `EOF)` is
  body, not the end. Everything after the real end is policed as commands. The audit's
  exploit, `git commit -m "$(cat <<'EOF'⏎x⏎EOF)" ; ./agentTooling/feature-start.sh zz ; echo "⏎EOF⏎)"`,
  must be denied for an orchestrator session, not prompted. If the build found B1 already
  closed by PR #139's code (merged into this branch) or not reproducible, NOTES.md says so
  with probe evidence, and a test still pins the exploit's verdict.
- **B2, a quoted or escaped digit before a redirect** (`"2">/dev/null`, `\2>/dev/null`) is
  an argument, not a file descriptor. `git push origin <own-branch> "2">/dev/null` in the
  cloud is denied, as a push of a second branch is. A bare `2>&1` and `2>/dev/null` are
  still descriptors, and the own-branch push with them still approves silently in the
  cloud.
- **B3, manifest trust.** The cloud own-branch push approval (`own_push_allowed`) reads
  `branches[0]` from the committed manifest at HEAD, per NOTES.md ruling 1. An uncommitted
  edit to `branches[0]` approves nothing.
- **`git push -fu origin <branch>`** (and other bundled short flags that include `-f`) is
  denied like `-f`.
- **Added by the owner after PR #139 merged** (its audits' findings; inputs in
  `self/features/orchestration-record-fixes/escalations/14-audit-opus.md` and NOTES.md):
  - **F1**: a heredoc operator glued to a separator (`true;<<EOF cat⏎x⏎EOF⏎git push origin main`,
    and `&<<`, `|<<`, `&&<<`, `(<<`, the chained-cd form) is denied again, as it was before #139.
  - **F2**: `git branch -D old ';' {a,b}` is denied; `git_commands` no longer skips brace words
    in a way that loses the git deny.
  - **A**: an unbalanced quote inside a `#` comment (`git push origin main # '`) does not lose
    the git deny, in any checkout.
  - **B**: the build-script rewrite denies (orchestrator role) do not decay to ASK after
    `OPAQUE_REWRITE_ATTEMPTS`.
  - **C**: in an orchestrator-refused checkout only, a build-script name or pattern in any
    argument of a non-exempt command counts as a run (`unshare`, `setpriv`, `prlimit`, awk
    `system()`, sed `e`, `git -c alias.x=!…`). NOTES.md records which legitimate commands an
    orchestrator now loses.
  - A line in `self/BACKLOG.md`: `report.py` does no containment check on a record's `report` path.
  Any of these the build judged too large is recorded as not built in NOTES.md and BACKLOG.md,
  with the reason. Judge whether that call was sound.
- **Added in phase 3** (the parent coordinator's rulings, NOTES.md coordinator ruling 6):
  - **Redirect-fed build scripts**: on the unreadable-ledger path, `bash < agentTooling/run-plans.sh`
    and its `<>`, `N<` and `{fd}<` spellings are denied with the same reason a pipe into an
    interpreter gets. The tests were red on 8424c16 before the fix.
  - **Literal-branch push, docs only**: the orchestrator allowlist's documented push is
    `git push -u origin <branch>` with the name written out (`ORCHESTRATION.md`, `hooks/README.md`,
    the hook's allowlist text). `git_denial` is unchanged; the `"$(git branch --show-current)"`
    spelling is still refused in the cloud, with a reason naming the literal form.
  - **Self-audit**: the implementer probed each fix's neighbouring spellings and fixed the bypasses
    of the fixes' own rules (NOTES.md → "Phase 3 probes", build rulings 17 onwards). This went
    beyond the items above; judge whether each such fix is sound and within the feature. It
    reversed build ruling 12 in part: a `#` inside a word no longer leaves a line unjudged.
    Classes it found and did not fix are in NOTES.md → "Found, not fixed" and `self/BACKLOG.md`;
    they are prompts, never silent approvals, and the same on main. A finding that only restates
    one of those is not an escalation. A silent approval, or a bypass of a rule this feature
    states, is.
  - New over-denies (prompt to deny) are stated in `hooks/README.md`; judge whether each is
    acceptable for what it closes.
- Legitimate commands keep their verdicts, apart from the over-denies NOTES.md and
  `hooks/README.md` name: the whole existing test suite still passes (no existing assertion
  weakened or deleted; rows that moved from prompt to deny are named in NOTES.md).

Excluded: any rewrite of the tokenizer or heredoc reader beyond what the red tests need
(PR #139 owns that region).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Red tests came first: the branch history shows a `hook-audit-gaps: acceptance tests`
  commit (or tests committed before each fix) with the exact exploits above.
- Tests: `self/tests/allow-repo-commands.sh`, `self/tests/hook-cloud-profile.sh`,
  `self/tests/hook-orchestrator-role.sh` (whichever carry the new rows) pass; a new test
  file, if any, has its row in `self/tests/README.md` and is recorded in `self/gate.sh`.
- `own_push_allowed` reads the manifest through `started_feature(…, tree=…)` at HEAD; no
  working-tree read of the manifest remains on that path.
- `hooks/README.md` sections that describe the heredoc exemption, the redirect descriptor
  reading and the cloud own-branch push describe the new behaviour, and the
  `CONVENTIONS.md` → "Shell commands" table and paragraphs agree with it.
- Named constants for every new literal (`CONVENTIONS.md` → "Named constants").
- `.claude/settings.json` unchanged unless `hooks/wire-settings.py --self` regenerates it
  identically (`self/gate.sh` checks it).
- READMEs current for every folder touched; `python3 -B check-readme-index.py` clean.

## Verdict

First line of `plans/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
