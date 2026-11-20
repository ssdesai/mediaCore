# 01 — review: hook-allowlist-design

Review this feature's diff against the eight questions below, written from the owner's
brief of 2026-11-18 (orchestration `tooling-wave-2026-11-18`), not from the builder's
report. The feature writes **a design document and nothing else**: the build is a later
feature, started only once the owner has signed the design off by merging this PR. "No
findings" is a legitimate verdict.

## What the feature was supposed to do

Write `self/DESIGN-2026-11-19-hook-allowlist.md`: the design that replaces the permission
hook's re-implementation of bash's reader (`hooks/allow-repo-commands.sh`: `shlex`, the
custom walk, the readings `judged_texts` takes) with silent approval for an allowlist of
simple line shapes only, `bash -n` as a parse oracle, a committed differential harness as a
gate test, and a `hooks/README.md` that promises only what is enforced. The document must
answer each of these, concretely and with reference to the code at this feature's base:

1. **The approved grammar.** Exactly which line shapes may be approved silently (single
   line; no `\` continuation; which quoting; which operators among `&&`, `||`, `;`, `|` and
   redirects; no `$'…'`; no `$(…)` or backtick inside a word; the one canonical commit
   heredoc), stated as a grammar small enough to parse with certainty. For each shape
   approved today that falls outside it: whether it is dropped (prompts, or is sent back)
   and what rewrite the denial names.
2. **The oracle.** How `bash -n` (and anything else) confirms bash reads the line as the
   hook did; which bash and which options are asked; what happens when the session's shell
   differs (`self/BACKLOG.md`, item (d) of "A line the hook cannot tokenize"); what it
   cannot confirm.
3. **The deny side.** Which denies stay as best-effort (force-push, protected branches,
   build scripts in an orchestrator session), how the README states that, and which of the
   five deny-side backlog entries are closed as "best-effort by design".
4. **The differential harness.** What generates the commands, what the oracle is, what
   exactly fails the gate, its runtime budget inside `self/gate.sh`, and where it lives in
   `self/tests/`.
5. **The README contract.** The guarantees `hooks/README.md` will state, each mapped to the
   gate test row that holds it.
6. **Migration and cost.** Which existing test rows change verdict; an estimate of the
   friction (commands that start prompting), measured by replaying recorded Bash commands
   through today's hook and the proposed grammar where the container allows it, otherwise
   argued; how the change ships to consuming repos.
7. **Out of scope and open questions** for the owner, each phrased as a decision with a
   recommendation.
8. **Build plan.** The feature(s) the build splits into, in order, each with its
   assertions.

Excluded: any change to `hooks/`, `analysis/`, `.claude/` or any script; any change to
`self/tests/`; the build itself. `self/BACKLOG.md` may gain one pointer line on each entry
the design supersedes and nothing else — no entry is removed here, since nothing is closed
until the build lands.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The diff is documents only.** It touches `self/DESIGN-2026-11-19-hook-allowlist.md`,
  `self/README.md` (the index line the README-index check wants), `self/BACKLOG.md`
  (pointer lines only), and this feature's own folder — which may hold, under
  `prototype/`, the measuring scripts the design's figures come from and their recorded
  output: evidence, wired into nothing. Nothing under `hooks/`, `analysis/`, `.claude/`,
  `self/tests/`, `templates/`, and no existing script, changes.
- **Each of the eight questions has a section that answers it**, and the answer is a
  decision, not a survey: a grammar a builder could implement without asking, an oracle
  call a builder could type, a failing condition for the harness a builder could code.
  Name any question whose answer is missing, hedged, or contradicted elsewhere in the
  document.
- **Every factual claim about today's hook is true of the code at the base.** The design
  cites functions, constants, test tables and README sections (`command_allowed`,
  `fails_closed`, `judged_texts`, `bash_refuses`, `never_judged`, `does_not_tokenize`,
  `orchestrator_words`, `own_push_allowed`, `UNANALYSABLE`, `HARMLESS_REDIRECT_RE`, the
  tables of `self/tests/allow-repo-commands.sh`, …). Open each one it leans on and check
  the claim: what the function does, what a named example's verdict is today, what a
  backlog entry says. A wrong claim about today's behaviour is a finding, with the line
  that disproves it.
- **The grammar is closed.** Every character class and operator is either admitted with
  its reading stated or refused; the document does not leave a construct ("and similar")
  for the builder to place. Check it against bash for the classes that broke earlier
  rounds: a `#` at a word's start and inside a word, a backslash inside double quotes, a
  `!`, reserved words and `{`/`}` at command position, an assignment word, a glob and an
  extglob, a trailing `&`, `;;`, a redirect's descriptor, `2>&1` and `/dev/null`, CR, NUL
  and non-ASCII blanks.
- **Nothing the design proposes widens silent approval.** Every line approved under the
  proposal is approved today, or the design says explicitly that it is new and why it is
  safe. The verdict layer rule of `DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1 ("ALLOW is
  `command_allowed`'s answer and nothing else") is kept or its replacement is argued.
- **What the oracle cannot confirm is stated**, and no approval rests on it beyond what
  the document says it confirms.
- **The measured figures are reproducible from the document**: what was replayed, from
  where, how many commands, and the counts — or the document says plainly that it could
  not measure and argues instead. A number with no stated source is a finding, and so is a
  number in the design that the recorded output under `prototype/` does not show. Do not
  re-run the prototype (that is verify's kind of work); read its recorded output.
- **The five deny-side backlog entries, the three that motivate the design and "A
  writable git config defeats the hook's approvals generally" are each disposed of by
  name**: closed by the build (which feature), closed as best-effort by design, or left
  open with the reason. The pointer lines in `self/BACKLOG.md` match those dispositions.
- **House style**: the document reads like `self/DESIGN-2026-09-18-hook-rewrite-or-ask.md`
  and `self/DESIGN-2026-09-17-policy-module.md` — numbered sections, decisions marked,
  assertions listed, a deliberately-excluded list, a build section — and is as short as
  the eight answers allow. No model identifier appears in any committed file.
- The gate (`./self/gate.sh`) is green; `self/README.md` names the new design file.

A finding outside these contracts that is not something this diff introduces is
non-blocking and goes to `self/BACKLOG.md`.

## Verdict
