Verdict: clean

# Review round 2: own-push-real-gitdir

## What the batch was supposed to do

Round 2 carries out ruling 9, which is the triage of round 1:

- Prompt whenever any of these is present: `submodule.recurse`, `push.followtags`, `hook.<name>.event` and `hook.<name>.command`.
- Give each one a Q7 row that asserts a prompt.
- Name `core.askPass` and `remote.origin.proxy` in `hooks/README.md`'s sentence on what is deliberately not read.
- Change no other behaviour.

Round 1's verdict on the rest of the feature stands. This diff (`d1fafdf..HEAD`) does not touch that code.

## Does it do it

Yes.

- **The new keys:**
  - `hooks/allow-repo-commands.sh:675` adds `submodule.recurse` and `push.followtags` to `OWN_PUSH_PRESENT_KEYS`, in lower case.
  - `:679` adds `^hook\..+\.(event|command)$` to `OWN_PUSH_PRESENT_KEY_RES`.
  - Both sit beside the existing constants. They are compared against `git config --list -z` output, where git lower-cases the section and the key, so the comparison is right.
  - The subsection is kept as written. `.+` matches any of them, including dotted names.
  - The check at `:4306` is unchanged, so presence alone prompts.
- **Tests:** `self/tests/hook-cloud-profile.sh` has four new `PRESENCE_KEYS` rows. Each row asserts "not approved".
  - The `push.followTags` row is set in camel case, which also exercises git's normalisation.
- **README:** `hooks/README.md` names each new key and why it prompts. The exclusion sentence now lists `core.askPass` and `remote.origin.proxy`.
- **No other change:** the only code change is to these two constants. No existing test row changed. The approve rows pass with this container's real config, which holds none of the new keys.
- **Gate:** `self/gate-report.txt` says "all checks passed". The pricing-staleness probe exits 1, and that check is informational.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.

## Observations (non-escalating under the convergence rule)

- **Stale comment in the hook.** The comment above `OWN_PUSH_PRESENT_KEYS` (`hooks/allow-repo-commands.sh:667-668`) says each key "redirects a push, runs a program, or names a file". `push.followtags` does none of these: it widens the push past the one approved ref.
  - Suggested wording: "…redirects a push, widens it past the one ref approved, runs a program, or names a file…".
  - I tried to make this edit, but the hook file is write-protected in this pass.
- **Unwrapped README line.** `hooks/README.md:909` runs past the wrap width of its neighbours. This is cosmetic.
- **Manifest `plans[]`.** The feature manifest's `plans[]` changed from `["01-review-opus", "01-audit-opus"]` to `["01-review-opus", "02-review-opus"]`.
  - That drops `01-audit-opus`, which ran (`review/complete/01-audit-opus.md`). It also leaves out `02-audit-opus`, which has also completed.
  - This is a cost-record question, not a policy defect. The coordinator should confirm the list is what the capture expects before the close.
