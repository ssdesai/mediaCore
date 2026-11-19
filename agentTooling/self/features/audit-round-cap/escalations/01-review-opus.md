Verdict: escalated

# Review: audit-round-cap

## What the batch was supposed to do

A doc-only feature that adds two process rules:

1. **Audit round cap.** `LIFECYCLE.md` → "The security audit" says that after 2 escalated audit rounds the coordinator stops, and the owner rules which blocking findings move to the BACKLOG. The feature then continues or closes as the owner rules. The BACKLOG entry "The security audit has no round cap." is removed.
2. **One gap per hook feature.** A coordinator brief for a fix under `hooks/` names one gap, and new findings go to the BACKLOG. The rule goes in `ORCHESTRATION.md` → "Rules". The BACKLOG entry "Hook features grow past one gap." is removed.

## Does it do it

Mostly yes, with one gap in the first rule.

- **Scope:** Only `LIFECYCLE.md`, `ORCHESTRATION.md`, `self/BACKLOG.md` and `self/features/audit-round-cap/` change. In `self/BACKLOG.md`, exactly the two named entries are removed. No scripts, hooks, templates or `.claude/` files change.
- **The cap rule** (`LIFECYCLE.md:404-409`) states every required element:
  - the number (2)
  - who stops (the coordinator), and that it queues no third rework
  - who rules (the owner)
  - where findings go (`self/BACKLOG.md` / `plans/BACKLOG.md`)
  - that the feature continues or closes per the ruling

  It keeps the non-blocking rule and the `<slug>: backlog` commit rule unchanged, so it does not contradict them.
- **The one-gap rule** (`ORCHESTRATION.md:255-258`) is a bullet under "## Rules", where a brief writer reads. It names the BACKLOG as where new findings go. Its cross-reference to `LIFECYCLE.md` → "The security audit" points to a section that exists (`### The security audit`, line 341).
- **Stale references:** Other mentions of the old entries are only in historical records of other features, which is fine. No README describes these sections, so none has drifted.
- **Gate:** Its verdict is "all checks passed". The `pricing rate history is current` check exited 1, but the gate counts that check as advisory and it has nothing to do with this diff.

## Fixed in this pass

Nothing.

## Escalated to the next round

1. **The cap allows a close that `feature-close.sh` will always refuse** (`LIFECYCLE.md:406-408`).
   - **The problem.** The new rule says the owner can move the remaining *blocking* findings to the BACKLOG, and the feature then "continues or closes per that ruling". But the close's audit checks are unchanged (`LIFECYCLE.md:370-380` and `:398-402`). For a hook change, the close refuses unless all of these hold on the judged head:
     - the latest audit stamp is clean
     - the committed `S/audit-report.md` opens `Verdict: clean`
     - `audit_report_unclassed` finds no `blocking` row

     A blocking finding is, by definition, a regression the head introduces (`LIFECYCLE.md:383-386`). Moving it to the BACKLOG leaves the regression in the diff. The next audit will class it blocking again, and the close refuses. So "closes per that ruling" names a route nothing can take, while the round cap's whole purpose is to give a stuck feature a way out.
   - **Why it stays green.** The gate checks no prose, and no test connects the cap to the close's refusal.
   - **Two ways to fix it — this is the design decision for the next round:**
     - **(a) Document-only.** Say that the close's audit checks are unchanged, so a ruling that closes the feature first needs a round that backs out the changes the moved findings flag, ending in a clean audit. Otherwise the feature is abandoned rather than closed.
     - **(b) Owner override in the close.** Give `feature-close.sh` an override that records the owner's ruling, for example a committed ruling file naming the moved findings, which `audit_report_unclassed` accepts in place of a clean verdict. This needs a script change, a new test in `self/tests/security-audit.sh`, and its own security audit, because `feature-close.sh` is an audit path.

     Whichever is chosen, the cap sentence must not promise a close the close cannot perform.
   - **Smaller wording point, same paragraph:** "rounds whose audit verdict was not clean" does not say whether a `stale` audit stamp (`LIFECYCLE.md:363-364`) counts toward the 2. Settle it in the same edit.
