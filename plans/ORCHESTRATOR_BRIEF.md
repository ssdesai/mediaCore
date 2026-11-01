<!-- Generated from agentTooling/templates/ by agentTooling/sync-plans.sh and overwritten on
every pull — never edit it. An orchestrator session copies it, fills it in for ONE feature
and sends the copy as the implementer session's first message. Every <placeholder> must be
replaced, and each [optional] in the start line kept without its brackets or dropped; a
brief that still carries either is not sent. `<tooling>` is where the scripts sit relative
to the repo root: `.` in agentTooling itself, `./agentTooling` in a consuming repo. Write
the Why and Items sections yourself; the rest is fixed. -->

<repo> feature `<slug>` — implementer brief

## Role

You are the implementer session for ONE feature, `<slug>`, in `<repo>`, start to close.
An orchestrator session created you, and no branch was given to you at creation. The orchestrator
reads your final report and forwards anything you need from the repository owner: if you
are blocked, say exactly what you need and stop. Sibling sessions may be building other
features; never do their work.

## Branch

Your first command in the repo is exactly:

    <tooling>/feature-start.sh [--self] <slug> --method <method> --branch claude/<slug> [--orchestration <orchestration>]

Run it in the background, its output captured to a file in your scratchpad, and wait for
its exit notification before you read or edit anything in the tree: the start runs the base
gate (minutes) and refuses a tree that changes while it runs.

Your branch is `claude/<slug>`. You come up on a detached HEAD at origin/main; the start
cuts the branch off it and refuses a detached HEAD without `--branch`. If the start
refuses, report the refusal verbatim and stop.

## Read first (in this order, before any edit)

1. `CLAUDE.md`, `<tooling>/CONVENTIONS.md`, `<tooling>/LIFECYCLE.md`, `<PROJECT_FACTS path>` (shell shapes are
   enforced by a PreToolUse hook; a denial names the rewrite).
2. <the READMEs and files the items touch, in the order they matter>

## Lifecycle

- Build the items below, directly or through subagents; the gate, the review and the
  close are yours.
- Run the gate (`<gate command>`) in the background with its output captured to a file in
  your scratchpad, and wait for its exit notification: no `sleep`, no polling. Fix
  failures in the code, never by weakening a check.
- Run the review (`<review command>`). An escalated verdict is a new round: read the
  feature's `escalations/`, fix, queue the next review plan the way `<tooling>/LIFECYCLE.md` says,
  run the review again. On `Verdict: clean` run the close straight away, without asking.
- Commit as you go with subjects prefixed `<slug>:`. Every commit message ends with the
  two trailer lines your own session instructions give you. Never put a model identifier
  in a committed file. Never edit anything under `.claude/`, nor under another feature's
  folder.

## Why

<one paragraph: what the feature is for and what prompted it>

## Items

### 1. <item>

<what changes, by file, and what the test asserts>

### 2. <item>

<what changes, by file, and what the test asserts>

## Report, terse

The PR URL; the feature's `report.py` cost table (build versus review); per item what
changed, by file; each check that failed on first run and what you changed; anything not
done and why; any fact in this brief you found untrue.
