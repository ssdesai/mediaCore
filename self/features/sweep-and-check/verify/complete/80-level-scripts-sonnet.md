# 80 — level-verify: scripts

Feature: sweep-and-check (`self/features/sweep-and-check/README.md`). Level 1: plans
73–79, the three scripts, the capture change and their tests.

Must be green: every `bash -n`, `py_compile analysis`, and the four self-tests this
level owns — `check plans self-test`, `sync check self-test`, `sweep self-test`,
`capture guard self-test` — plus every older self-test, which this level must not have
broken (`level sentinel`, `tiered gates` and `feature lifecycle` drive `run-batch.sh`,
which plan 76 edited).

Contract rows this level owns (manifest → "Contracts across levels"): the four CLI
contract blocks, each written twice — in the tests plan and in the script plan. When a
test and a script disagree, the block is the contract: fix whichever side departs from
it, never the block. A red `bash -n` on a script that does not yet exist means a build
plan did not run; report it, do not stub the file.
