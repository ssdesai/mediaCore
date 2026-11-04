# direct-bare

The control for `direct`'s procedure steps. It is `direct` with exactly two edits
(below), and it exists to measure what they cost.

- `template.md` — `../direct/template.md` minus (1) the whole `## Procedure` section: the
  `CHECKPOINT.md` slicing and rewriting at every milestone, the
  `./agentTooling/stamp-timing.sh` calls, and the acceptance-tests-first commit; and
  (2) the parenthetical "(`CHECKPOINT.md` at status `committed`)" in Finish step 2. Every
  other byte, placeholders included, is identical. `self/tests/direct-bare-pair.sh`
  derives the expected file from `direct`'s by those two removals and fails on any other
  difference, so an edit to `direct/template.md` fails the gate until this file follows.
- `run.sh` — `../direct/run.sh` with only the method name changed (its log lines and
  its `mktemp` prefix):
  nothing in it touches the checkpoint or the stamps.

Because there is no checkpoint and no stamp, a `direct-bare` cell has no tests/build/gate
split in its Time table; its implementer span is undivided. Compare it to `direct` on
total cost and on the spec's results, not on that split. Like `direct`, it is not one
`claude -p`: the harness review and rework still run on it.
