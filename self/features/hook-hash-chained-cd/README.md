# Hook: quote-aware `#` guard, no approval for a chained `cd`

A consuming repo reported a bug. `cd <root>; grep -n '^#' f | head; wc -l f` was approved
by `hooks/allow-repo-commands.sh` instead of being denied with the chained-`cd` rewrite.
Claude Code's reads fence then stopped it for the human anyway. There were two causes,
and both are fixed:

- The deny skipped any line holding a `#`, even one inside quotes. It now skips only what
  the single guard `never_judged` holds back: an unquoted `#`, or a `$'…'` that escapes a
  quote, which shlex and the shells read differently.
- The approval analysis tracked a `cd` across members and approved the chain. It now
  approves a `cd` only when the `cd` is the whole command.

Built by hand. Regression rows are in `self/tests/allow-repo-commands.sh`, and the guard
is checked against bash and zsh themselves by `self/tests/hook-quote-oracle.sh`.

## Rounds

| Round | What it changed |
|---|---|
| 1 | The fix as reported. Review: `$'\''` read as a plain quote denied a `cd` bash never runs. |
| 2 | `$'…'` read as ANSI-C quoting. Review: `$$'…'` is the PID and a plain quote in bash. |
| 3 | Only an odd run of `$` prefixes a quote. Review: clean. |
| 4 | A threat test after the close, with the shells as oracle. It found that zsh reads `$$'…'` the other way from bash, and that every reader downstream of the guard lexes with shlex, which ends a `$'…'` at an escaped quote. The guard stopped modelling ANSI-C quoting and holds such a line back instead, `#` or no `#`. |

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md` | Reviews the diff against the reported command and the no-widening / no-deny-on-a-guess contracts |
| `review/complete/02-review-sonnet.md` | Re-reviews round 2's commit |
| `review/complete/03-review-sonnet.md` | Re-reviews round 3's commit |
| `review/incomplete/04-review-sonnet.md` | Re-reviews round 4's commit |

## Deliberately excluded

- **A REWRITE for chains the deny still cannot judge** (an unquoted `#`, a heredoc, a
  `$'…'` escaping a quote). These now get no verdict from the hook (the ASK class), so the
  human judges them. Denying them would mean guessing at a comment, a heredoc body or
  where a quote ends, and the deny must never fire on a guess.
- **Teaching the readers ANSI-C quoting.** Every deny lexes with shlex, which has no such
  mode, and bash and zsh disagree about `$$'…'`. Holding the line back is one rule in one
  place; the cost is that `cd x && grep $'it\'s' f`, a real chain, gets a prompt and no
  rewrite.
- **A quoted or escaped separator read as a separator.** shlex drops the quotes, so
  `echo ';' cd` is denied as a chained `cd` on `main` too. The threat test measured it
  and left it: it needs the word `cd` right after a lone quoted `;`, `|` or `&`, and it
  is a wrong deny, never a wrong approval.
- **A payload whose `tool_input` is not an object**, which makes the hook exit 1 with a
  traceback on `main` and here. It is not a payload Claude Code sends, and a failed hook
  approves nothing.

## Machine-readable

```json
{
  "slug": "hook-hash-chained-cd",
  "method": "hand",
  "plans": ["01-review-opus", "02-review-sonnet", "03-review-sonnet", "04-review-sonnet"],
  "branches": ["hook-hash-chained-cd"],
  "base": "main",
  "session_window": {"from": "2026-10-01T22:17:34Z", "to": "2026-10-01T23:04:30Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["a1dcbf55-2ab0-4dfe-a713-b7d199c9fb95"],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence.** Do not hand-copy it; see
`templates/plans/features/README.md` for what each field means.
