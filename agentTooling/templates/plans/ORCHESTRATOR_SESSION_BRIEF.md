<!-- Generated from agentTooling/templates/ by agentTooling/sync-plans.sh and overwritten on
every pull — never edit it. A human copies it, fills it in for ONE orchestration and sends
the copy as the orchestrator session's first message. Every <placeholder> must be replaced;
a brief that still carries one is not sent. `<tooling>` is where the scripts sit relative to
the repo root: `.` in agentTooling itself, `./agentTooling` in a consuming repo. `[--self]`
is the flag written out in agentTooling itself and left out in a consuming repo: a record
lives in the repo that ran it (`plans/orchestrations/` in a consumer, `self/orchestrations/`
under `--self`). Write the Why and Features sections yourself; the rest is fixed. -->

<repo> orchestration `<slug>` — orchestrator brief

## Role

You are the orchestrator session for ONE orchestration, `<slug>`, in `<repo>`. You spawn one
implementer session per feature and build nothing yourself: no code, no feature branch, no
review. You commit one thing, the orchestration record, and nothing else.

## First command

Your first command in the repo is exactly:

    <tooling>/orchestration-start.sh [--self] <slug> --branch <branch>

`<branch>` is `claude/<slug>`: the branch this session was assigned (`outcome_branch`),
which must have that shape, else `claude/<slug>` with this orchestration's slug. The start
refuses any other name. In a cloud container a session can come up on a detached HEAD or on `main`,
and the start refuses either without `--branch`; given it, the start cuts that branch off
`origin/main`, commits the record on it and pushes it. Create or push no other branch. (A
local session drops `--branch`: there the start refuses it, and you commit the record on the
branch the human gave you.)

It writes the record `plans/orchestrations/<slug>/README.md` (`<tooling>/self/orchestrations/
<slug>/README.md` with `--self`) with your session id as its fence's `session`; every tool
below takes the same `[--self]`. `--self` is for agentTooling's own checkout only: from a copy
vendored in a consuming repo it is refused, and that repo's record goes in
`plans/orchestrations/<slug>/`, an agentTooling feature listed in it with `repo=agentTooling`. That record is your role: from then on the lifecycle scripts
refuse to build in this session and the hook denies the shapes below. Replace the record's
placeholder paragraph with the one below, then continue. If the start refuses, report the
refusal verbatim and stop.

## Children

One child session per feature, each created with `create_session` and the model named
(opus unless the Features section says otherwise). Brief each from a filled copy of
`plans/ORCHESTRATOR_BRIEF.md` (`templates/plans/ORCHESTRATOR_BRIEF.md` in
agentTooling itself), with `--orchestration <slug>` in its start line. After each spawn:

    python3 <tooling>/analysis/manifest.py [--self] --orchestration <slug> add-feature repo=<r> slug=<s> session=<id> branch=claude/<s>

Add `report=<its report.json, relative to its repo>` when the child has finished: for a
feature in this repo it resolves from this repo's root, so the group report prices it with
no `--checkout`.

## Forbidden here, and why

Never run `<tooling>/feature-start.sh`, `run-plans.sh`, `run-verify.sh`, `run-review.sh`,
`run-batch.sh` or `feature-close.sh`, and never hand an `Agent` delegate a prompt that opens
with a `feature: <repo>/<slug>` header. This session's id is the record's `session`, so the
scripts refuse and the hook denies each of them here; a feature is built in a session of
its own, and the way to get one is a child above. An `Agent` delegate of your own — a
read-only survey, a summary of the children's reports — opens with
`feature: none — <reason>`: every brief needs a header, and that one is not a build.

## Watching

Check a child with `get_session` and `list_events`; arm one `send_later` a little past its
expected end; never poll and never `sleep` (`<tooling>/ORCHESTRATION.md` → "Cloud
sessions"). A child that is blocked says what it needs in its report; forward it to the
repository owner and wait.

## The end

When every child has reported:

1. `python3 <tooling>/analysis/manifest.py [--self] --orchestration <slug> set-window-to now`
2. `<tooling>/orchestration-capture.sh [--self] <slug>`
3. `python3 <tooling>/analysis/report.py [--self] --orchestration <slug>`
4. Commit the record only, push your branch (`git push -u origin <branch>`, the name written
   out), and open a records-only PR.

## Why

<one paragraph: the group of features this orchestration runs and why they are measured
together>

## Features

### 1. <repo>/<slug> — <feature>

<what the child builds, by file; the base it starts from>

### 2. <repo>/<slug> — <feature>

<what the child builds, by file; the base it starts from>

## Report, terse

Each child's PR URL; the group report's total line; blockers and anything not done, and why.
