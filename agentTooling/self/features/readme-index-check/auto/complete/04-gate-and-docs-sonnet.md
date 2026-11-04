# 04 — build: wire the check into `self/gate.sh`, the ignore list, and the docs

Feature: `readme-index-check` (agentTooling, `--self`) — plan 3 of 3 build plans. The
feature ships `check-readme-index.py`, a read-only checker that reports every tracked
file and direct subfolder its folder's `README.md` never names, wires it into
`self/gate.sh`, and documents opt-in adoption for consuming repos.

Run the checker as a blocking check in agentTooling's own gate, give it agentTooling's
ignore list, add the one README line the tree is missing, and document the rule and its
adoption.

Depends on: `03-checker-sonnet.md` (read the module docstring of `check-readme-index.py`
before writing any prose here — it is the one statement of the rules; point at it, do not
restate it).

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

## Pinned facts

- A prototype of the checker was run over this tree when the plans were written. With the
  three ignore patterns below, exactly **one** README is missing an entry:
  `self/README.md` does not name `DESIGN-2026-09-17-close-and-review-rounds.md`. That gap
  is fixed by **adding the README row** (below), never by an ignore entry. Each ignore
  pattern covers records or a stub that must not describe the file, never a folder index
  that should have been written.
- New files this batch creates are each named by a README in this batch:
  `check-readme-index.py` (root `README.md`, below), `self/readme-index-ignore`
  (`self/README.md`, below), `self/tests/readme-index.sh` (`self/tests/README.md`, plan 02).
- The checker reads tracked files only, so untracked new files are invisible to it until
  staged. That is the contract, not a gap to work around.
- `templates/` is **not** changed by this feature: a commented gate example in
  `templates/plans/gate.sh` would need a `template-version` bump (comments are hashed,
  `self/tests/template-versions.sh`), and `self/gate.sh` mirrors that number
  (`self/tests/sync-check.sh`), so every consumer's `sync-plans.sh --check` would report
  drift for a no-op. Adoption is documented in the root `README.md` instead.
- Do not edit `harness/`, `analysis/`, `.claude/` or anything under `templates/`. No model
  name may appear in any file.

## Files

- Create `self/readme-index-ignore`
- Modify `self/gate.sh`
- Modify `self/README.md`
- Modify `self/PROJECT_FACTS.md`
- Modify `README.md` (agentTooling root)
- Modify `CONVENTIONS.md`

## `self/readme-index-ignore` — paste verbatim

```
# Paths agentTooling's README-index check (../check-readme-index.py, run blocking by
# gate.sh) does not require a README to name. The pattern rules are the checker's
# docstring. Every entry says why; an entry is never a way to avoid writing a README
# line (CONVENTIONS.md -> "READMEs").

# A feature directory is its manifest and plan queues: the manifest README is the
# feature's record, not an index of auto/, verify/, review/ and the cost files.
self/features/*/
# An orchestration record is the same kind of record, for a group of features.
self/orchestrations/*/
# The version-and-hash table beside the templates. Its folder's README.md is the generated
# plans/ stub every consumer receives, which must not describe agentTooling-only files;
# templates/README.md documents it.
templates/plans/TEMPLATE_VERSIONS
```

## `self/gate.sh`

1. After the profile-confinement block — the line
   `record "profile variables confined to the detector and its adapters" bash self/profile-confinement.sh`
   — and before `echo "=== gate: python syntax ==="`, insert:

```bash

echo "=== gate: readme index ==="
# Every tracked folder's README.md names each tracked file and direct subfolder in it
# (CONVENTIONS.md -> "Keeping READMEs up to date"; the rules are check-readme-index.py's
# docstring). Blocking: a file no README names is a file whose contracts a reader cannot
# find. The records that legitimately have no entry are in self/readme-index-ignore,
# each with its reason. -B: the checker writes nothing, not even a __pycache__.
record "readme index" python3 -B check-readme-index.py --root "$REPO_DIR" --ignore self/readme-index-ignore
```

2. In the python-syntax block, after the `record "py_compile hooks" …` line, add:

```bash
record "py_compile readme index" python3 -m py_compile check-readme-index.py
```

## `self/README.md`

The file is one table of `| Path | What it is |` rows.

1. After the row starting ``| `profile-confinement.sh` |``, add:
   ``| `readme-index-ignore` | The ignore list `gate.sh`'s README-index check (`../check-readme-index.py`) reads: the paths no README is required to name — the feature and orchestration records, and the templates' version table — each with its reason in a comment. An entry here is never a substitute for a README line. |``
2. After the row starting ``| `DESIGN-2026-09-16-lifecycle-restructure.md` |``, add:
   ``| `DESIGN-2026-09-17-close-and-review-rounds.md` | Design record for the close and review rounds: supersedes §3.2 ("no close") of `DESIGN-2026-09-16-lifecycle-restructure.md`. The review pass ends a round on its verdict and stops; `feature-close.sh` alone opens the PR and captures the cost, and an escalated verdict starts the next round. |``
3. In the ``| `gate.sh` |`` row, add one clause naming the README-index check over this
   checkout (`../check-readme-index.py` with `readme-index-ignore`, blocking).

## `self/PROJECT_FACTS.md`

1. In "## Layout", after the bullet beginning ``- `self/` — this corpus.``, add:

```markdown
- `check-readme-index.py` — the README-index checker, stdlib Python at the top level,
  always run `python3 -B` (it writes nothing). `self/gate.sh` runs it blocking over this
  checkout with `self/readme-index-ignore`, so a new tracked file needs its line in its
  folder's `README.md` — the ignore list is for records, never for a missing entry. Its
  docstring is the one statement of its rules.
```

2. In "## Tests", after the bullet beginning ``- `python3 -B hooks/wire-settings.py``, add:

```markdown
- `python3 -B check-readme-index.py --root <root> --ignore self/readme-index-ignore` —
  blocking: every tracked folder's `README.md` names each tracked file and direct
  subfolder in it. `self/tests/readme-index.sh` tests the checker itself.
```

3. In the `python3 -m py_compile` bullet of "## Tests", add `check-readme-index.py` to the
   files it lists.

## `README.md` (agentTooling root)

1. In the table under "### Installing into a consuming repo, and keeping it current",
   after the ``| `CONVENTIONS.md` |`` row, add a ``| `check-readme-index.py` |`` row:
   the read-only README-index checker — for every tracked folder with a `README.md`, each
   tracked file and direct subfolder the README never names, one line each, exit 1 if any
   (`--report-only`: exit 0), 2 on an error; `--ignore <file>` for the repo-owned ignore
   list; a generated README checked together with the repo-owned file its header names.
   Run with `python3 -B`. agentTooling's own gate runs it blocking; a consuming repo opts
   in ("Adopting the README-index check"). Its docstring is the one statement of the
   recognition rule and the ignore format.
2. Append a new section at the end of the file, `### Adopting the README-index check`,
   in the voice of the "Adopting …" sections above it. Prose, covering exactly:
   - Nothing changes on a pull: the seeded `plans/gate.sh` is repo-owned and the template
     does not call the checker, so no consumer's gate turns red; adoption is opt-in, by
     hand, once. (Why the template is unchanged: one sentence, from the pinned facts.)
   - Step 1: create `plans/readme-index-ignore` — paste these starter lines in the
     section as a code block:
     ```
     # The vendored subtree is checked by agentTooling's own gate, upstream.
     agentTooling/
     # A feature directory is its manifest and plan queues, not a folder index.
     plans/features/*/
     ```
     and list the file in `plans/PROJECT_FACTS.md` → "This repo's `plans/` contents"
     (its folder's README is generated).
   - Step 2: in `plans/gate.sh`'s REPO-SPECIFIC checks block, add — as a code block —
     `record "readme index" python3 -B "$REPO_DIR/agentTooling/check-readme-index.py" --root "$REPO_DIR" --ignore "$REPO_DIR/plans/readme-index-ignore" --report-only`.
     Report-only lists every missing entry in `gate-report.txt` and never fails the gate.
   - Step 3: add the README lines it lists (an ignore entry only for a genuine record or
     fixture directory, with its reason), then drop `--report-only`: the check is
     blocking from then on.
   - Generated READMEs: the `plans/` stubs are never edited; the check reads each with
     the repo-owned file its header names (`PROJECT_FACTS.md`), which is where the repo's
     own entries for those folders already belong.
   - Limits, one sentence each: it reads `git ls-files`, so a new file is checked once
     it is staged; it checks that an entry exists, not that it is true.
   - **The companion test, per repo, not shipped here.** The field lists README Rule 1
     requires (`CONVENTIONS.md` → "Required README content") are where an entry most often
     goes untrue, and no repo-agnostic checker can read a schema. Each repo can hold its
     own with a test in its own gate that, for every Rule 1 entry, compares the README's
     field list with the fields of the type or schema it describes, failing when either
     side changes alone. musicMap's `types.conformance.ts` is the model: it ties each
     README Rule 1 field list to the TypeScript type it describes, so the repo's
     typecheck fails on drift. A Python repo writes the same as a test comparing the
     list with the model's fields. Describe this; do not invent details of
     `types.conformance.ts` beyond that sentence.

## `CONVENTIONS.md`

At the end of "### Keeping READMEs up to date" (after the paragraph ending "…make a
README misleading."), add this paragraph verbatim:

```markdown
The index half of this is mechanical, and a gate holds it: agentTooling's
`check-readme-index.py` lists every tracked file and direct subfolder its folder's
`README.md` never names, and exits non-zero if there is one. agentTooling's own gate runs
it blocking; a consuming repo opts in (`agentTooling/README.md` → "Adopting the
README-index check"), with a repo-owned ignore list for record and fixture directories —
never for a file that should have had its line. It checks that an entry exists, not that
it is true: a Rule 1 field list against its schema is a per-repo test, described there.
```
