Verdict: clean

# Review: audit-round-cap (round 2)

## What the batch was supposed to do

A doc-only feature that adds two process rules and removes the two BACKLOG entries they replace:

1. **A cap on audit rounds.** In `LIFECYCLE.md` → "The security audit": after 2 escalated audit rounds the coordinator stops, and the owner rules which blocking findings move to the BACKLOG.
2. **One gap per hook feature.** In `ORCHESTRATION.md` → "Rules": a coordinator brief for a fix under `hooks/` names one gap, and new findings go to the BACKLOG.

Round 1 escalated one problem: the cap promised a close that `feature-close.sh` would refuse. This round fixes it in the document only (option a in `escalations/01-review-opus.md`).

## Does it do it

Yes.

- **Scope.** Only `LIFECYCLE.md`, `ORCHESTRATION.md`, `self/BACKLOG.md` and `self/features/audit-round-cap/` change. Exactly two entries are removed from `self/BACKLOG.md`: "The security audit has no round cap." and "Hook features grow past one gap."
- **The cap paragraph is true against the close's checks** (`LIFECYCLE.md:404-413`).
  - It says the close's audit checks are unchanged.
  - It says a blocking finding is a regression the head still carries, even after the BACKLOG lists it.
  - So a ruling that closes the feature first needs a round that backs out what the moved findings flag and ends in a clean audit. Otherwise the feature is abandoned, not closed.
  - This matches the close's refusals at `:370-380` and `:398-402`: a clean stamp, a committed clean report, and no unclassed row. The paragraph promises no route the close refuses.
- **It counts `stale` stamps.** A `stale` stamp counts as an escalated round. This settles round 1's wording point and matches `:363-364`, where `stale` is "never clean".
- **Every required element is still there:**
  - the number (2)
  - the coordinator stops and queues no third rework
  - the owner rules
  - where moved findings go (`self/BACKLOG.md` or `plans/BACKLOG.md`)
  - the feature continues or closes per the ruling
- **It agrees with the non-blocking rules.** Non-blocking findings are still filed in a backlog commit after the clean verdict and are never a reason to stop.
- **The back-out round does not contradict "queues no third rework".** That round runs only on the owner's ruling. The coordinator does not queue it on its own.
- **The one-gap rule** (`ORCHESTRATION.md:255-258`):
  - It is scoped to `hooks/`.
  - It sends new findings to the BACKLOG.
  - Its cross-reference to `LIFECYCLE.md` → "The security audit" names a section that exists.
- **Gate:** `self/gate-report.txt` reads "all checks passed".

## Fixed in this pass

- `LIFECYCLE.md:413`: the cap paragraph called the backlog commit's subject `<slug>: backlog`. Elsewhere `LIFECYCLE.md` writes the slug as `S` (`:8`) and calls the same commit `S: backlog` (`:392`, `:432`). I changed it to `S: backlog`. The meaning is the same. `ORCHESTRATION.md` keeps `<slug>: backlog`, which is that file's own notation.

## Escalated to the next round

Nothing.
