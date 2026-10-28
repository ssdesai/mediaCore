# 102 — hook: deny a chained cd, expand simple brace lists

feature: agentTooling/hook-cd-deny-braces — plan 2 of 4. `hooks/allow-repo-commands.sh`
gains a `deny` decision for any Bash command that chains `cd`/`pushd` with another
command (the reason tells the model how to rewrite it), and stops refusing simple brace
lists (`ls {src,tests}`) in otherwise-approvable reads by expanding them before its
path checks.

Implement both in the hook, and bring its docs in line.

Depends on: 101-hook-tests-sonnet.md. The contract is `self/tests/allow-repo-commands.sh`.
Read it in full before editing the hook: every list in it is a case this plan must
satisfy exactly.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Pinned facts:
- The hook is Python 3, standard library only, despite the `.sh` name. Constants live at
  the top under short label comments (`CONVENTIONS.md` → Named constants).
- This directory has no `.claude/settings.json`, so the `Edit(**/agentTooling/hooks/**)`
  deny rule described in `hooks/README.md` does not bind here. Edit the hook with the
  Edit tool.
- Claude Code's `PreToolUse` protocol: a `deny` decision blocks the call and sends
  `permissionDecisionReason` back to the model; an `allow` skips the prompt; no output
  means the normal permission flow.

## Files

- Modify `hooks/allow-repo-commands.sh`
- Modify `hooks/README.md`
- Modify `README.md` (the `hooks/` row only)
- Modify `CONVENTIONS.md` (§ Shell commands only)
- Modify `sync-plans.sh` (the comment at line 24 only)

## `hooks/allow-repo-commands.sh`

### 1. Deny a chained cd

Add under `# Hook protocol`:

```python
DECISION_DENY = "deny"
DENY_REASON = (
    "allow-repo-commands: don't chain cd with other commands (CONVENTIONS.md § Shell "
    "commands). A path after a chained cd resolves only at run time, so the call stops "
    "for approval. Run `cd <absolute path>` as its own Bash call and the command as the "
    "next one, or name every path absolutely and drop the cd.")
```

Add a new label block:

```python
# Chain detection. A directory change sharing a command with anything else is denied.
# Unlike the approval analysis, a line break separates commands here, as it does in bash.
CHDIR_PROGRAMS = frozenset(["cd", "pushd"])
CHAIN_PUNCTUATION = "();<>|&\n"
CHAIN_WHITESPACE = " \t\r"
REDIRECT_CHARS = frozenset("<>")
HEREDOC_OPERATOR = "<<"
```

Add this function (tested against every `DENY` and `NOT_DENIED` case in the test):

```python
def chains_chdir(command):
    """True when a cd or pushd shares the command with any other command. What it cannot
    tokenize, and anything carrying a heredoc (whose body lines would read as commands),
    is never judged a chain: a deny must not fire on a guess."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=CHAIN_PUNCTUATION)
    lexer.whitespace = CHAIN_WHITESPACE
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        return False
    if any(t.startswith(HEREDOC_OPERATOR) for t in tokens):
        return False
    heads, at_head, redirect_target = [], True, False
    for t in tokens:
        if all(ch in CHAIN_PUNCTUATION for ch in t):
            if any(ch in REDIRECT_CHARS for ch in t):
                redirect_target = True
            else:
                at_head = True
        elif redirect_target:
            redirect_target = False
        elif at_head:
            heads.append(t)
            at_head = False
    return len(heads) > 1 and any(h in CHDIR_PROGRAMS for h in heads)
```

In `main()`, after the `tool_name` check and after reading `command` (move the command
read and its empty check up to sit directly after the `tool_name` check), and **before**
the root and cwd checks, call `chains_chdir(command)` inside `try/except Exception`
(an exception means no deny). When true, print the deny decision and return. The deny
does not depend on `CLAUDE_PROJECT_DIR` or `cwd`. Factor the `json.dump` of the decision
into one helper taking `(decision, reason)` and use it for both allow and deny.

### 2. Expand simple brace lists

Today `{` and `}` are in `SHELL_ACTIVE_CHARS`, so any unquoted brace refuses. Replace that
with the following rules. They are written so the hook's view of each word is exactly
bash's, or a superset that refuses more.

- Remove `{` and `}` from `SHELL_ACTIVE_CHARS`.
- **Raw-word rule**, checked on the stripped command text before `shlex` (which drops the
  quotes this rule needs). Split the text into raw words the way the existing
  `shell_active_outside_quotes` scanner tracks quoting: words end at unquoted whitespace
  and at unquoted `;|&()<>`, and each raw word keeps its quote and backslash characters.
  For every raw word containing `{` or `}`:
  - if the whole word is one single-quoted string (`'…'`, no other quote inside), accept it:
    bash reads its braces literally;
  - else if the word contains `'`, `"` or `\`, refuse;
  - else remove every match of the simple-group pattern in **one** `re.sub` pass, and
    refuse if a `{` or `}` remains. A simple group is `{` + alternatives separated by
    commas, at least one comma, no brace, whitespace, quote, `$` or backtick inside, + `}`.
    One pass is what refuses nesting: `{a,{b,c}}` leaves `{a,}` behind.
- **Expansion**, per `shlex` token that contains a simple group: expand every group,
  left to right and cartesian, the way bash does (`a{b,c}d{e,f}` → `abde abdf acde acdf`).
  More than `MAX_BRACE_WORDS = 256` words from one token refuses.
- **Two argvs.** For each subcommand, build the **literal** argv (the `shlex` tokens as
  they are) and the **expanded** argv (each token replaced in place by its expansion
  words). The subcommand passes only when `subcommand_allowed` passes for both, with the
  same effective cwd. The literal pass is what keeps a single-quoted `'{-a,-v}'` from
  approving `git branch`; the expanded pass is what checks each path and flag bash will
  really see. `cd` keeps the existing rule, one argument, so `cd {a,b}` refuses on the
  expanded argv.
- The `~` refusal (`TILDE`) applies to every expanded word too, since bash expands a
  tilde after brace expansion (`{a,~/x}` → `~/x` → home).
- `..` is already refused anywhere in the command, which covers sequence expressions
  (`{a..c}`).

Name the new constants under a `# Brace expansion` label (`MAX_BRACE_WORDS`, the compiled
group pattern, the quote/backslash set if it is not already a constant) and reuse
`QUOTE_SINGLE`, `QUOTE_DOUBLE` and `ESCAPE`. Keep the functions small and next to the ones
they extend. Match the module's style: docstrings that say why, no inline magic values.

### 3. Module docstring

Rewrite it. The hook approves read-only and test commands confined to the repo, and it
**denies** one shape, a chained `cd`, because that shape is always a mistake with a
mechanical fix, and a deny puts the fix in front of the model instead of spending an
approval from the human. Everything else it does not approve falls through to the normal
prompt. Keep the paragraphs on `blockReadsOutsideWorkingDirectories` and the threat model.

## `hooks/README.md`

- The `allow-repo-commands.sh` bullet: replace "It never emits `"deny"` — it removes
  prompts, it does not add refusals." with: it emits `permissionDecision: "deny"` for
  exactly one shape, a command chaining `cd` or `pushd` with any other command, with a
  reason naming the rewrite. Keep "Every rule is a refusal…" for the approval analysis.
- § Why it exists: the hook now answers a `cd X && cmd` chain with a deny and its fix,
  not an approval, since the rule in `CONVENTIONS.md` § Shell commands is otherwise unenforced
  and every miss costs the human a prompt while teaching the model nothing.
- Add a section **What it denies**, above § What it approves: the rule (a `cd`/`pushd` at
  command position alongside any other command, where commands are separated by `&&`,
  `||`, `;`, `|`, `&`, a line break, `(`, or `$(`), that it runs before and independently of
  the approval analysis and of `CLAUDE_PROJECT_DIR`/`cwd`, and what it deliberately does
  not deny: a standalone `cd`, `cd` as an argument or inside quotes, a redirect target, a
  heredoc body (any command containing `<<` is never denied), and a command that does not
  tokenize. Note that the deny also reaches the runners' Bash-enabled executors (verify,
  review) in a consuming repo, which is intended.
- § What it approves: in "Refused outright", drop `{ }` and brace expansion from the list,
  and add a paragraph on brace lists with the raw-word rule, the two argvs, the 256-word
  cap, and `~` after expansion.
- § What the audit found: change the `cat {/etc/passwd,}` row's "Was" to say brace expansion
  produced a path the checker never saw, and is now expanded and each word checked.
- § Editing the policy: add `CHDIR_PROGRAMS` and `MAX_BRACE_WORDS` to the constants list,
  and say a change to `CHDIR_PROGRAMS` adds a `DENY` case and a `NOT_DENIED` case.

## `README.md`

The `hooks/` row: replace "approving repo-confined read and test Bash commands, so
`blockReadsOutsideWorkingDirectories` stops prompting on `cd X && cmd` chains — reads and
tests only, writes still prompt" with "approving repo-confined read and test Bash commands,
simple brace lists included, and denying a chained `cd` with a reason naming the rewrite,
so the model corrects the shape rather than the human approving it. Reads and tests only;
writes still prompt".

## `CONVENTIONS.md`

At the end of § Shell commands' first block (after "Delegated agents and batch runs
inherit this rule. A brief that pastes a `cd X && ...` command teaches the wrong shape."),
add one paragraph: where `hooks/allow-repo-commands.sh` is wired, a chained `cd` is
**denied**, and the denial's reason is the correction. Rewrite the command as the reason
says; do not retry it, and do not work around it with `pushd` or a subshell, which are
denied too.

## `sync-plans.sh`

Line 24's comment says the hook exists to stop prompting on every `cd X && cmd`. Change it
to say the hook approves repo-confined reads and denies a chained `cd`. Comment only.
