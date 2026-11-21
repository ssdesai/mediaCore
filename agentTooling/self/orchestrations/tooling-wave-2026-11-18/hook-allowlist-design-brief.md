agentTooling feature `hook-allowlist-design` — implementer brief

## Role

You are the implementer session for ONE feature, `hook-allowlist-design`, in agentTooling, start to close. An orchestrator session created you (orchestration `tooling-wave-2026-11-18`). It reads your final report and forwards anything you need from the repository owner: if you are blocked, say exactly what you need and stop. This feature writes a design document only: no change to `hooks/`, `analysis/` or any script. The build comes later, as its own feature, once the owner signs off on the design (the merge of your PR).

## Branch

Your first command in the repo is exactly:

    ./feature-start.sh --self hook-allowlist-design --method direct --branch claude/hook-allowlist-design --orchestration tooling-wave-2026-11-18

Run it in the background, its output captured to a file in your scratchpad, and wait for its exit notification before you read or edit anything in the tree: the start runs the base gate (minutes) and refuses a tree that changes while it runs.

Your branch is `claude/hook-allowlist-design`. You may come up on a detached HEAD at origin/main; the start cuts the branch off it. Create or push no other branch. If the start refuses, report the refusal verbatim and stop.

## Read first (in this order, before any edit)

1. `CLAUDE.md`, `CONVENTIONS.md` (→ "Shell commands", the three outcomes and the rewrite table), `LIFECYCLE.md`, `self/PROJECT_FACTS.md`.
2. `hooks/README.md` whole; `hooks/allow-repo-commands.sh` and `hooks/policy.py` (how a line is read and judged today: `shlex`, the custom walk, `does_not_tokenize`, `never_judged`, `bash_refuses`, the heredoc handling, the own-push and read-only git approvals); `self/tests/allow-repo-commands.sh` (what the gate pins).
3. `self/BACKLOG.md`: the entries "The hook judges by re-implementing bash's reader, which cannot converge", "`hooks/README.md` promises more than 'never silently approved'", "The bash-vs-hook differential harness is not committed", and the five deny-side entries it would supersede ("The git deny reads git only at command position", "The git deny matches flags as written, not as git reads them", "A line the hook cannot tokenize: three leftovers", "The deny side does not follow a substitution's scope", "On the unreadable-ledger path, a build script's name built at run time is not seen"); also "A writable git config defeats the hook's approvals generally".
4. History: `self/features/hook-audit-gaps/` (NOTES and the seven review rounds), `self/features/orchestration-record-fixes/` NOTES (the scoped reader tried in rounds 4–8 and removed), `self/features/hook-planted-gitdir/`, `self/features/hook-silent-allow-sweep/` (merged just before you start), and the earlier designs `self/DESIGN-2026-09-18-hook-rewrite-or-ask.md` and `self/DESIGN-2026-09-17-policy-module.md` for the house style of a design doc.

## Lifecycle

- Before you write the design, fill the review brief the start names in its last lines (`review/incomplete/01-review-opus.md`, still an `@@TODO@@` stub): the review judges the design against the questions below, and checks that every factual claim about today's hook is true of the code at your base.
- Run the gate (`./self/gate.sh`) in the background, its output captured to a file in your scratchpad; wait for its exit notification (no `sleep`, no polling). The gate's README-index check will want `self/README.md` to name the new design file.
- Run the review (`./run-review.sh --self hook-allowlist-design`). An escalated verdict is a new round; after 3 escalated rounds stop and report. On `Verdict: clean` run `./feature-close.sh --self hook-allowlist-design` straight away, without asking.
- Commit as you go with subjects prefixed `hook-allowlist-design:`. Every commit message ends with the two trailer lines your own session instructions give you. Never put a model identifier in a committed file. Never edit anything under `.claude/`, nor under another feature's folder. Do not edit `self/BACKLOG.md` beyond adding one line to each superseded entry pointing at the design.

## Why

The hook decides silent approval by re-implementing bash's reader, and every audit finds another spelling where it and bash disagree (`hook-audit-gaps` ran seven rounds; `orchestration-record-fixes` built and removed a scoped reader). The owner approved, on 2026-11-18, writing a design that replaces this with: silent approval only for an allowlist of simple shapes, `bash -n` as a parse oracle, a committed differential harness as a gate test, and a `hooks/README.md` that promises only what is enforced.

## The design document

Write `self/DESIGN-<today's date>-hook-allowlist.md`. It must answer, concretely and with reference to today's code:

1. **The approved grammar.** Exactly which line shapes may be approved silently (single line; no `\` continuation; which quoting; which operators — `&&`, `||`, `;`, `|`, redirects; no `$'…'`, no `$(…)` or backticks inside a word; the one canonical commit heredoc), stated as a grammar small enough to parse with certainty. For each shape approved today that falls outside it, say whether it is dropped (prompts or is sent back) and what rewrite the denial names.
2. **The oracle.** How `bash -n` (and anything else) confirms bash reads the line as the hook did; which bash and options are asked, and what happens when the session's shell differs (BACKLOG item (d) of the tokenize entry). What it cannot confirm.
3. **The deny side.** Which denies stay as best-effort (force-push, protected branches, build scripts in an orchestrator session), how the README states that, and which of the five deny-side backlog entries are closed as "best-effort by design".
4. **The differential harness.** What generates the commands, what the oracle is, what exactly fails the gate, its runtime budget inside `self/gate.sh`, and where it lives in `self/tests/`.
5. **The README contract.** The guarantees `hooks/README.md` will state, each mapped to the gate test row that holds it.
6. **Migration and cost.** Which existing test rows change verdict; an estimate of the friction (commands that start prompting), measured if you can by replaying the Bash commands from recent transcripts in this container through today's hook and the proposed grammar, otherwise argued; how the change ships to consuming repos.
7. **Out of scope and open questions** for the owner, each phrased as a decision with your recommendation.
8. **Build plan.** The feature(s) the build splits into, in order, each with its assertions.

Keep it as short as those answers allow.

## Report, terse

The PR URL; the feature's `report.py` cost table; the design's file path and a five-line summary of its decisions; the open questions for the owner; anything not done and why; any fact in this brief you found untrue. Your last line is the PR link or the exact blocker.
