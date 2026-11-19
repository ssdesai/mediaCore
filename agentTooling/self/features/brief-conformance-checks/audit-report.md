Verdict: clean

# Security audit 03: brief-conformance-checks

- **Head:** `claude/brief-conformance-checks` at `a533b88`.
- **Base:** `origin/main`.
- **Copies:** two throwaway copies, made with `git archive HEAD` and `git archive origin/main`. They were extracted under this pass's scratch directory as `scratch/head/` and `scratch/base/`.
- **Fixtures:** every queue scenario ran in a fresh fixture built from one of the copies.
- **Edits:** this report is the only file changed in this checkout.

## Scope of this round

Round 2 (`617b11d`) came back clean. Since then, one audit-path file changed:

- **`conformance.py`:** two string constants (`DEVIATIONS_MISSING_NOTE` and `OUT_OF_SCOPE_LEAD`) gained a space after `=`. Their values are unchanged, so behaviour is unchanged.

Nothing else on the audit path changed. That covers `run-review.sh`, `feature-close.sh`, `feature-start.sh`, `plan-runner-lib.sh`, `plan-runner-roots.sh` and `self/gate.sh`, and also `hooks/` and `.claude/`. `a533b88` adds tests and a queued review plan only.

Even so, the rules this diff adds were attacked again from scratch against both copies:

- **R-h:** `refuse_unowed_conformance_plans`, plus how it interacts with `queue_security_audit` and `queue_conformance_check`.
- **R-i / R-j:** the `conformance.py` subcommands that the close and `pr.sh` read.
- **Hook payloads:** the hook itself, with payloads aimed at the new files.

The head's own `self/tests/brief-conformance.sh` also ran inside `scratch/head/`, and every check passed. That includes B1a–d (stray conformance plans refused) and L1e–f (an owed check resumed, not refused).

## Inputs tried

Result codes used in the tables:

- **refuse:** the script exits 1 before any plan launches.
- **goes on:** the pass runs.
- **defer:** the hook printed nothing, so the human decides.
- **allow / deny / ask:** the hook's explicit decision.

### R-h: conformance plans queued before `run-review.sh`

Each scenario runs `bash scratch/attack.sh <copy> <brief> <state:stem>...`, and all of them are driven by `bash scratch/all.sh scratch/head` and `bash scratch/all.sh scratch/base`. Each one:

1. Runs the copy's real `feature-start.sh --self atk --no-gate`.
2. Makes a work commit that appends a line to `hooks/policy.py`, so a security audit is owed. When the scenario's brief value is 1, the same commit adds a two-item `OWNER_BRIEF.md`.
3. Places the listed plans under `review/<state>/`.
4. Runs `./run-review.sh --self atk` with a stub `claude`.

The launch lists in the table come from the stub's log:

- `c` is a launch with `--tools ""`, the conformance check.
- `r` is any other launch: a review, or the audit, which logs as `r` too.

| # | brief | queue | head | base |
|---|---|---|---|---|
| sa | 0 | inc `01-review-opus`, inc `02-conformance-opus` | refuse: "no OWNER_BRIEF.md" | goes on: r r r |
| sb | 0 | inc `01-audit-opus`, `01-review-opus`, `02-conformance-opus` | refuse: "no OWNER_BRIEF.md" | refuse: "audit is 02-audit-opus" |
| sd | 1 | inc `01-audit-opus`, `01-review-opus`, `02-conformance-opus` | refuse: "check is 01-conformance-opus" | refuse: "audit is 02-audit-opus" |
| se | 1 | inc `01-review-opus`, `01-conformance-sonnet` | refuse: wrong model | goes on: r r r |
| sf | 1 | inc `01-review-opus`, `01-conformance-opus` (owed) | goes on: r c r | goes on: r r r |
| sg | 1 | inp `01-conformance-opus`, inc `01-review-opus` | goes on: c r r | goes on: r r r |
| sh | 0 | inp `02-conformance-opus`, inc `01-review-opus` | refuse: "no OWNER_BRIEF.md" | goes on: r r r |
| sj | 1 | inc `01-review-opus`, `01-conformance-opus`, `02-review-opus` | refuse: "check is 02-conformance-opus" | goes on: r r r r |
| sk | 0 | inc `01-review-opus`, `02-Conformance-opus` (case, outside the regex) | goes on: r r r | goes on: r r r |
| sl | 0 | inc `01-review-opus`, `01-conformance-opus` | refuse: "no OWNER_BRIEF.md" | goes on: r r r |
| sm | 1 | inc `01-conformance-opus` alone | refuse: "no review is queued beside it" | goes on: r r |
| so | 1 | inp `01-review-opus`, inc `01-conformance-opus` | refuse: "would resume with no security audit" | goes on: r r r |
| sr | 0 | inc `01-review-opus`, `01-conformance-opus-x` | goes on: r r r | goes on: r r r |
| ss | 1 | inc `1-review-opus`, `1-conformance-opus` (unpadded) | goes on: r c r | goes on: r r r |
| st | 1 | inc `01-review-opus`, `001-conformance-opus` | refuse: "check is 01-conformance-opus" | goes on: r r r |
| sx | 1 | inp `01-review-opus`, inp `01-conformance-opus` | refuse: "would resume with no security audit" | refuse: the same |
| sy | 1 | inc `01-review-opus`, `01-conformance-opus ` (trailing space in the stem) | goes on: r r c r (the spaced stem runs as a review, and the owed check is queued) | goes on: r r r |
| sz | 1 | inc `01-review-opus`, `01-conformance-OPUS` | goes on: r r c r | goes on: r r r |
| s0 | 0 | inc `02-conformance-opus` alone | refuse: "no OWNER_BRIEF.md" | goes on: r r |
| s1 | 1 | inc `01-review-opus`, `01-conformance-opus`, `01-conformance-opus.bak` | goes on: r r c r | goes on: r r r r |
| s2 | 1 | inc `01-review-x-opus`, `01-conformance-opus` | goes on: r c r | goes on: r r r |

Comparison of the two copies:

- **Where the base refuses** (sb, sd, sx), the head refuses too.
- **Where the head goes on** (sf, sg, sk, sr, ss, sy, sz, s1, s2), the base goes on too.
- **Stems outside `^[0-9]+-conformance-[a-z]+$`** (sk, sr, sy, sz, s1) run as reviews on both copies. That follows the base's existing rule that any stem that is not an audit is a review, and they get the same audit pairing on both copies.
- **Every other row:** the head is stricter than the base.

### R-i / R-j: `conformance.py` (head only; the base has no such file)

Command: `bash scratch/conf.sh`.

| Input | Head |
|---|---|
| `items` on a brief listing `1. **A.**` and `2. **B.**` | ids 1 and 2 |
| `items` on a brief with lazy numbering, `1. **A.**` and `1. **B.**` | **two items that share id 1** (round 2's non-blocking finding, still present) |
| `items` on a brief with a `## 1.` heading plus a list | the heading only (headings win, per R17) |
| `items` on a brief with `> 1.`, ` 1.` (indented) and `1.nospace` | the fallback, a single item with id 1 |
| `deviations` on a report with no section | `none`, or `non-empty` with `--owner-brief-present` |
| `deviations` on a report whose section is `**None.**` | `none` in both modes |
| `deviations` on a report whose section is `None, except X` | `non-empty` in both modes |
| `deviations` with `--owner-brief-present=1` | usage error, rc 2 |

### Hook (unchanged), with payloads aimed at the new files

Command: `python3 scratch/hook.py`.

- **Payload:** `{tool_name, session_id, agent_id:"", cwd:<copy>, tool_input}`, sent on stdin to `python3 <copy>/hooks/allow-repo-commands.sh`.
- **Environment:** `CLAUDE_PROJECT_DIR=<copy>` and `AGENTTOOLING_PROFILE=local`, with `AGENTTOOLING_SCRATCH` and `AGENTTOOLING_HEADLESS` unset.

| Input | Head | Base |
|---|---|---|
| `python3 <root>/conformance.py items <root>/…/README.md` | defer | defer |
| `python3 -B <root>/conformance.py deviations <root>/…/review-report.md --owner-brief-present` | defer | defer |
| `python3 <root>/conformance.py deviations /etc/passwd` | defer | defer |
| `python3 <root>/conformance.py pr-body /etc/pa""sswd` | defer | defer |
| `env python3 <root>/conformance.py items /etc/passwd` | defer | defer |
| `env env python3 <root>/conformance.py items <root>/x` | defer | defer |
| `python3 <root>/conformance.py items <root>/x > <root>/out.txt` | defer | defer |
| `cat <root>/conformance.py \| python3` | deny | deny |
| `python3 -c 'import conformance'` | ask | ask |
| `<root>/run-review.sh --self brief-conformance-checks` | defer | defer |
| `env <root>/run-review.sh --self brief-conformance-checks` | defer | defer |
| `nohup <root>/run-review.sh --self x` | defer | defer |
| `bash <root>/run-review.sh --self x` | defer | defer |
| `<root>/feature-start.sh --self foo --owner-brief /etc/passwd` | defer | defer |
| `<root>/feature-close.sh --self brief-conformance-checks` | defer | defer |
| `rm <root>/…/review/incomplete/02-conformance-opus.md` | defer | defer |
| `echo x > <root>/…/review/incomplete/02-conformance-opus.md` | deny | deny |
| `cp /tmp/x <root>/…/OWNER_BRIEF.md` | defer | defer |
| `sed -i s/a/b/ <root>/run-review.sh` | deny | deny |
| `bash <root>/self/gate.sh` | defer | defer |
| `<root>/self/gate.sh` | allow | allow |
| `find <root> -name '*.md' -exec python3 <root>/conformance.py items {} \;` | defer | defer |
| Write `<root>/…/review/incomplete/02-conformance-opus.md` | defer | defer |
| Write `<root>/…/OWNER_BRIEF.md` | defer | defer |
| Edit `<root>/run-review.sh` | defer | defer |
| an Agent call whose brief has no `feature:` header | deny | deny |
| a Bash payload with no `tool_input` | defer | defer |
| a Bash payload whose `command` is a list | defer | defer |

The head and base results are the same on every row.

`<root>/self/gate.sh` is allowed on both copies. The head's change to `gate.sh` only adds the `brief-conformance.sh` test and a `py_compile` of `conformance.py`; it widens nothing the gate runs with permission.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | an owner brief with lazy Markdown numbering (`1. **A.**` / `1. **B.**`), where the review and conformance tables hold a `done` row for id 1 only | `conformance.py items` gives two items that share id 1, so a single row satisfies both and the close can go on | the close goes on (the base has no owner-item check) | `bash scratch/conf.sh` on head; round 2's `close.sh` run on both copies; no audit-path code changed since |

## Non-blocking findings

1. **A lazily numbered owner list collapses its items onto one id.** This is carried over from round 2 and is not yet in `self/BACKLOG.md`.
   - **Input:** an `OWNER_BRIEF.md` written `1. **Add A.** …` / `1. **Add B.** …`. That is ordinary Markdown auto-numbering, and it renders as 1, 2.
   - **Head:** `items` yields `1 A.` and `1 B.`. One acceptance row and one conformance row for id 1 satisfy both items.
   - **Base:** the close goes on. It reads no owner brief at all.
   - **Not a pre-existing silent allow:** the rule is new, and the base was never more restrictive here.
   - **What the rule should do instead:** `parse_items` should number list items by position, the way a Markdown renderer does (the first item's number, then +1 for each). At the least, `items` should exit non-zero on a duplicate id, so the review runner and the close refuse the brief.
   - **Filing:** file it in `self/BACKLOG.md` as a `brief-conformance-checks: backlog` commit after the clean verdict.

No pre-existing silent allow was found.

## Blocking findings

None. No input gets a more permissive result on the head than on the base.
