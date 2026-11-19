Verdict: escalated

# Review — orchestration-record-fixes, round 5 (`291eb20`)

## What the batch was supposed to do

Close round 4's escalations (`escalations/04-review-opus.md`, `escalations/04-audit-opus.md`):

- **B1:** a `case` arm's `)` inside `$(…)`, a backtick pair or `<(…)` ended the substitution's
  scope early, so `echo $(case x in x) git push origin main;; esac)` dropped from DENY to a prompt.
- **Outer-word fragmenting:** the scoped reading split `X="$(pwd)"` and `"./run-$(echo plans).sh"`
  into pieces, so the assign-then-use check and the build-script check stopped recognizing them.

The fix: `command_words` now reads each line twice. The **scoped** reading is
`command_words_read(…, True)`. The **flat** reading is `command_words_read(…, False)`, which uses
`chain_tokens(…, lift=False)`: it masks quotes only, and every operator ends a command. The
function returns the commands from both readings.

## Does it do it

It covers every shape the round-4 findings named, but there is a gap in the same family.

**What holds:**
- All six B1 rows in `self/tests/hook-cloud-profile.sh` get the right decision.
- The ASSIGN_DENY rows and the H12 build-script rows behave as described.
- `command_allowed` was not changed, so a line containing `$` or a backtick is still never
  approved. The union of the two readings can only add denies.
- No false deny turned up on common approved reads. I tried `grep -n "(x)"`, `grep -c "a)b"`,
  pipes, `&&` chains, `find -name "*.sh"` and the cloud push of the feature's own branch; all are
  still approved.
- `hooks/README.md` and NOTES.md → round 4 match the code.
- The gate is green.

**The gap:** the same B1 shape inside double quotes is still a prompt rather than a DENY, because
neither reading sees the push.

## Fixed in this pass

Nothing.

## Escalated to the next round

### 1. B1 inside double quotes: the hidden command is seen by neither reading (security; DENY → prompt)

I ran the hook on each command below in both profiles (`AGENTTOOLING_PROFILE=cloud` and `local`).
Each one produced **no decision**, which means the human gets a prompt. Each should be DENY:

```
echo "$(case x in x) git push origin main;; esac)"
echo "`case x in x) git push origin main;; esac`"
echo "$(case x in x) git reset --hard HEAD~1;; esac)"
echo "$(echo a) $(case x in x) git push origin main;; esac)"
```

The same commands without the double quotes are DENY, as the round-5 rows require.

**Why each reading misses it** (`hooks/allow-repo-commands.sh`):

- **Scoped reading.** `mask_quoted_punctuation(lift=True)`, around lines 1064–1130, lifts `$(` out
  of the quotes and pushes `CONTEXT_SUBSTITUTION`. At the case arm's `)` it pops that context and
  goes back into the double-quote context. So `git push origin main;; esac)` gets masked as quoted
  text. Even where it is lexed, the scope has already closed at the first `)`
  (`command_words_read`, lines 1333–1338), so the words land on `echo`.
- **Flat reading.** `lift=False` masks the whole quoted string, so the line comes out as one word
  and the reading finds no command inside it.

**Why this needs a design decision rather than a local fix:** in the flat reading, lifting and
scoping are tied together. If the flat reading simply lifted substitutions out of quotes, it would
split `X="$(pwd)"` and `"./run-$(echo plans).sh"` into fragments again, and the
`ASSIGN_DENY` / H12 rows would regress. Two possible approaches:

- (a) Add a third reading that lifts out of quotes but has no scopes (every operator ends a
  command). It would feed only `git_commands`, and leave `assigned_names` and
  `invokes_build_script` on the flat reading.
- (b) Make the mask's substitution context count parentheses so it closes on the *matching* `)`.
  A bare case-arm `)` with no matching `(` would then be treated as unbalanced, and the line falls
  to whichever reading handles it.

**Missing rows:** add the four commands above to `self/tests/hook-cloud-profile.sh` `TABLE`
(`D, D`), plus `echo "$(case x in x) git push origin HEAD:other;; esac)"` as `P, D`.

**Docs to correct:** NOTES.md → round 4 states B1 is fixed for "`$(…)`, a backtick pair or
`<(…)`", and `hooks/README.md` repeats it. Both should either name the quoted form as covered once
it is fixed, or list it as a known gap.

### 2. No test asserts the invariant "the union approves nothing"

The design depends on the flat reading only ever adding denies. That holds today only because
`command_allowed` refuses any `$` or backtick, and `git_commands` / `assigned_names` /
`invokes_build_script` only feed denies. No row pins this down.

**Missing test:** a row in `self/tests/allow-repo-commands.sh` that asserts a line on which the
flat reading yields a command not in the scoped reading's output is never `allow`. Use, for
example, `echo $(true) git status`: today the flat reading sees `git status`, an approved read, and
the line must still not be approved. Without that row, a future change that lets `command_words`
feed an approval would quietly turn the flat reading's extra commands into approvals.
