# vanilla

The bottom rung of the tooling-ablation ladder (`vanilla` → `vanilla-conv` → `direct-bare`
→ `direct` → `plans`): the minimal brief of `../vanilla-conv/`, byte for byte, with **no
agentTooling doctrine loaded during the build** — no `CONVENTIONS.md` import and no command
hook or deny rules. `vanilla` vs `vanilla-conv` therefore measures the conventions and the
hook and nothing else.

- `template.md` — identical to `../vanilla-conv/template.md` (`self/tests/vanilla-pair.sh`).
- `run.sh` — `../vanilla-conv/run.sh` plus the lines marked `# vanilla-only`: neutralize
  the tree, run the same one `claude -p` from the tree's root, verify, restore on exit
  (an `EXIT` trap, with `TERM`/`INT` turned into exits so the trap runs).
- `neutralize.sh` — the three functions, sourced: `vanilla_neutralize <tree>`,
  `vanilla_verify <tree> <start commit>`, `vanilla_restore <tree>`. Its header says how.

## What the build does not see

For the length of the method only:

- every **tracked `CLAUDE.md`** loses each line that is only an import of `CONVENTIONS.md`
  (`^@(<path>/)?CONVENTIONS\.md$`): the root's `@agentTooling/CONVENTIONS.md`, and the
  vendored copy's own `agentTooling/CLAUDE.md` `@CONVENTIONS.md`, which Claude Code loads
  lazily the first time the session reads a file under `agentTooling/`;
- the tracked **`.claude/settings.json`** at the tree root loses its `hooks` and
  `permissions` keys — the `PreToolUse` command hook, the `SessionStart` hook (both
  agentTooling's scripts) and the deny/ask rules. Every other key stays.

Each changed file is marked **skip-worktree**, so no commit the build makes can carry it
(`git add -A`, `git commit -a` and `git add <file>` all skip it). The list of what was
changed is kept in the worktree's own git dir (`git rev-parse --git-path
harness-vanilla-neutralized`), never in the tree. When the method exits, `vanilla_verify`
fails it (exit 1) if any commit since the method started changed one of those files — the
PR diff must contain only the feature, because the review reads the diff — and
`vanilla_restore` clears the bits and checks the files out from HEAD, so the review,
rework and accept stages run on the tree exactly as every other arm's. A neutralization
left by a killed attempt is restored before the next one starts.

## The project part of `CLAUDE.md` is kept

A judgement call, made deliberately: only the `CONVENTIONS.md` import lines go; the rest
of the root `CLAUDE.md` (the project status, the commands, the repo's own field-list and
contract examples) stays, identical in `vanilla` and `vanilla-conv`. That text is the
codebase's own documentation, like its READMEs, and "vanilla" means a codebase without
agentTooling, not one stripped of its own docs. Dropping it too would change two things in
one rung (project docs and tooling), and the ladder's rule is one layer per rung. Two
residues to read the results with: the project part still names "README Rule 1 / Rule 2"
(rules the conventions define), and a fixture's `facts.md` — handed to every method — may
mention `PROJECT_FACTS.md` or `CLAUDE.md` (exportStore's does).

## What it does not take away

- The vendored `agentTooling/` directory stays in the tree: it is not loaded, but the build
  may open it, and the PR mechanics use its `forge.sh`.
- `agentTooling/.claude/settings.json` loads only for a session launched inside
  `agentTooling/`, which this one is not; user-level settings are the same for every arm.
- An **untracked** `.claude/settings.json` cannot be skip-worktree'd: it is left live, with
  a warning.
- A tree with nothing to neutralize — a base with no tracked settings file (vinylCatalogue's
  `exportStore` and `exportStoreAB` bases have none) or no import line — makes `vanilla`
  equal to `vanilla-conv` for that layer, and the run log says so. Pinning the experiment's
  agentTooling (`--agent-tooling`) runs `sync-plans.sh`, which wires the hook in.
- The harness review and rework are shared stages and run on the restored tree, conventions
  included, for every arm.
