# Notes: hook-special-params

Rulings made where the manifest left the call open, each with a one-line rationale,
plus deviations. The manifest's decisions are not reopened here.

## Rulings

- **The three `AT="$(cd "$(dirname "$0")/.." && pwd)"` cases move to a literal path, and
  the `$0` spelling joins `VAR_REWRITE`.** They were pinning the whole-argument `$(…)`
  exemption, the cd-inside-a-substitution rule and the no-own-use rule — none of which is
  about `$0` — and their "prompt" verdict held only because `$0` fell through the regex.
  The `$HOME` twin of the same command was already denied before this feature, so
  denying the `$0` form is the existing rule applied, not a new one; keeping `$0` exempt
  would mean excluding `0` from the pattern, and in the agent's shell `$0` is as
  run-time as `$HOME`.
- **The builder session is pinned in `sessions` although it started the feature without
  `--pin`.** This session first edited `main` directly, was corrected, saved the diff,
  restored `main` and ran `feature-start.sh`, so it is both the router and the hand
  builder — the `--pin` case. The routing record it wrote is left on disk;
  `report.py` skips a routing record whose session some manifest pins
  (`shell-write-rewrite`, part 2), so the pin is the link and the cost lands once.
- **Method `hand`, not `direct`.** The diff was typed before the feature existed and is
  about thirty lines; an implementer delegate would cost more than the change.

## Deviations

- The work was done on `main` first and moved across by `git diff` / `git apply`.
  `LIFECYCLE.md` → "Start before you edit" says not to; this is the record of the one
  time it happened and why (the session did not know the rule applied to the repo it
  was in).
