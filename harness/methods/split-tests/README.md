# split-tests

`vanilla-conv` plus an independent test author. Not a rung of the tooling-ablation ladder
but a variant beside `vanilla-conv`: it asks whether acceptance tests written by a session
that will not implement the feature change what the implementer builds and what it costs.
Two fresh sessions run in sequence in the same tree, both through `harness_claude` with
`vanilla-conv`'s model and flags (`--model "$HARNESS_MODEL" --permission-mode acceptEdits
--allowedTools Bash`), in a tree whose `CLAUDE.md` and command hook load as they normally
would.

1. **The test author** gets the spec, the facts, the isolation rules and the gate command,
   and writes the black-box acceptance tests the spec implies — through the real routes,
   CLI and disk, against the contract fixtures where the repo has them, never against
   internals — where the repo's tests live and per its README rules. It writes no
   implementation, runs the tests to see them fail for the right reason (the feature is
   missing, not a broken test), and commits the test files alone as `<slug>: acceptance
   tests`. It does not push and opens no PR.
2. **The implementer** is a fresh session with `vanilla-conv`'s brief byte for byte plus one
   paragraph: the commit `<sha>` (`<slug>: acceptance tests`) holds acceptance tests written
   from the spec by someone else; make them pass; do not delete or weaken them; change one
   only where it contradicts the spec or guesses a name or seam the spec leaves open, and
   list every such change with its reason in the PR body under "Test changes". It gates
   green, commits, pushes and opens the PR as `vanilla-conv` does.

- `template.md` — **both briefs, in one file**: the author's, then the line
  `<!-- split-tests: the implementer brief starts on the next line -->`, then the
  implementer's. One file because the harness fills exactly one template per method
  (`run.sh`'s `do_brief`) and passes the method only the filled result: the variables
  behind `@@FACTS@@`, `@@ISOLATION@@`, `@@SPEC_*@@` and the rest are not exported to a
  method's process, and `harness_fill_template` fills an unset one with the empty string, so
  a second template filled inside this method would ship a brief with no spec and no facts
  rather than fail. Carried in the one template, both halves get the harness's own fill and
  its unfilled-`@@NAME@@` refusal, and the method contract (one `template.md`) and
  `harness/run.sh` stay as they are. The implementer's one slot the harness cannot fill,
  `%%TESTS_SHA%%`, is deliberately not `@@`-shaped, so the harness's check passes it
  through; `run.sh` refuses a brief without it and fills it with the author's sha.
- `run.sh` — splits the filled brief at the marker, runs the author, checks its work, fills
  the sha, runs the implementer. **Exit 1** (work failure, no implementer) when the author
  commits nothing; when its commit range changes a file that is not a test (a path through
  a `test/`, `tests/`, `__tests__/` or `e2e/` directory, or a name shaped `test_*`,
  `conftest.py`, `*_test.*`, `*.test.*`, `*.spec.*` or `*Test.*`/`*Tests.*` — `TEST_DIR_RE`
  and `TEST_NAME_RE`), the one exception being the `README.md` of a folder holding a test
  file the same range changes (`TEST_README_NAME`: the line the brief asks for, which a repo
  keeping tests next to their source, `src/components/Foo.test.tsx`, puts in
  `src/components/README.md`); when the tip is not the `<slug>: acceptance tests` commit;
  or when it leaves work uncommitted that was not there before it ran (the harness's own
  `plans/features/<slug>/` aside). The last two are checked on the author's usage-limit
  stop too, before its exit 2, once the tests commit exists: the re-entry then goes
  straight to the implementer, which must not start in a tree holding the author's
  source. Anything else a test needs outside those files (a gate's test list, a runner
  config) the brief leaves for the implementer. **Exit 2** on either session's usage limit; the harness
  then runs the method again, and a re-entry that finds the author's commit (searched from
  the HEAD the first author started at, kept in `<branch>-author-start`) runs the
  implementer alone. **Exit 0** when the implementer exits 0.

**Side outputs**, in the cell's log directory (`HARNESS_LOG_DIR`, `<experiment>/logs/`),
never in the tree — a dirty path there stops `feature-close.sh` (`../plans/README.md`):

| File | What it holds |
|---|---|
| `<branch>-test-diff.txt` | `git diff --stat <sha>..HEAD -- <the files the author's commit changed>` after the implementer, whatever its exit: what the implementer did to the authored tests. Empty means it left them untouched. Read beside the PR body's "Test changes", which says why. |
| `<branch>-author-brief.md`, `<branch>-implementer-brief.md` | The two briefs exactly as sent, the sha filled. |
| `<branch>-author-result.json` | The author's result object. `<branch>-method-result.json` is the implementer's (or the author's, copied there on its usage-limit stop, where the harness reads the reset time). |
| `<branch>-author-start` | The HEAD the author started from. |

**Cost.** Both sessions run on the cell's branch in its tree, so the capture claims both into
the method's cost; `claude -p`'s own reported figure in the ledger
(`cost_method_reported_usd`) is the implementer's alone.

`../../../self/tests/split-tests-pair.sh` fails the gate if the implementer half drifts from
`../vanilla-conv/template.md` plus exactly the one paragraph, and drives `run.sh` end to end
with a fake `claude`. Like every method, the arm gets the harness's review and rework
afterwards.
