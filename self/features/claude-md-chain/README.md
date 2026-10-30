# claude-md-chain: the instruction chain, trimmed and measured

Every consuming repo loads `CONVENTIONS.md` into every session through its root
`CLAUDE.md`, and the vendored `agentTooling/CLAUDE.md` imports it again. This feature
measures what that chain actually costs and cuts what does not earn its place. Measured
with an `InstructionsLoaded` hook on Claude Code 2.1.314: an import already loaded is
loaded once, a subdirectory's `CLAUDE.md` (and its `.claude/CLAUDE.md`) loads lazily on
the first read under it, and an ancestor's `CLAUDE.md` loads at launch — so the "loads
twice" cost `CLAUDE.md` and `RUNNER.md` described was never paid, and relocating the file
would not have changed what loads. Both files now say what was measured. `CONVENTIONS.md`
drops to the rules that still do work: the shell section becomes the one rule and the
rewrite table, with the reasoning left to `hooks/README.md`, which already held it; the
README section keeps the index, the two entry shapes and the update rule, and drops the
"never Grep or Glob" traversal ritual and the per-read stop conditions, written for
models that wandered and now forcing a 95 KB README read before any work; the pointer to
`plans/PROJECT_FACTS.md` before authoring plans moves here from each consumer's root file,
which the install template now says must hold nothing about plans, branches or the
lifecycle. `AGENT_PLANS.md` stops naming `/fast` as a cheaper model (it is Opus at a
higher rate). And the one settings drift every consumer carries — the old
`Edit(**/agentTooling/hooks/**)` deny sitting beside the ask rule that replaced it, deny
winning — is retired: `wire-settings.py` removes it on the next sync, as it does a retired
`Bash` deny, so the ask rule works for the first time in a consuming repo.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Reviews the diff against this paragraph and the contracts in the brief. |

## Deliberately excluded

- The consumers' own root `CLAUDE.md` files (vinylCatalogue's CLI reference, musicMap's
  contract list, mediaCore's stale camelCase branch rule, the boilerplate all four share):
  each is that repo's file and its own PR, briefed from the session's report.
- Any rule on README *size*. The measured problem in the consumers is READMEs of 100–300
  KB that the old traversal rule forced into context whole; the fix is a redesign of what
  a README entry holds, proposed to the owner, not a line here.
- A relocation of `agentTooling/CLAUDE.md` to `.claude/CLAUDE.md`: measured, it loads
  lazily just the same, so there is nothing to gain.
- Removing the old `Edit(**/agentTooling/hooks/**)` deny from the four consumers: the
  retired rule does it on their next `subtree pull` + `sync-plans.sh`.

## Machine-readable

```json
{
  "slug": "claude-md-chain",
  "method": "hand",
  "plans": ["01-review-opus"],
  "branches": ["claude/brave-planck-no5foj"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "session_window": {"from": "2026-10-30T01:02:29.906Z", "to": "2026-10-30T02:14:32Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, the profile, the gate and `from`, with the id lists empty — and
`feature-capture.sh` stamps `to` on the branch, provisionally until the merge freezes it
(`agentTooling/LIFECYCLE.md`). Do not hand-copy it. Only `slug`, `plans` and `branches`
are required: `method` reads as `"plans"` when absent, `base` as `main`,
`session_window` as unbounded, and the four id lists as empty. See
`templates/plans/features/TEMPLATE.md` for what each field means and how it goes wrong.
