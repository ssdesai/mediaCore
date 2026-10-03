#!/usr/bin/env bash
set -uo pipefail

# Self-test for agentTooling's own .claude/settings.json being GENERATED per checkout
# rather than tracked (self/features/self-settings-untracked/README.md). Run by
# self/gate.sh, or by hand: bash self/tests/self-settings.sh
#
# The file used to be committed, so it shipped with the subtree and every consuming repo
# carried agentTooling/.claude/settings.json naming ${CLAUDE_PROJECT_DIR}/hooks/… — a hook
# path that does not exist there. Now git ignores it, self/worktree-setup.sh writes it in
# every new self worktree, feature-start.sh --self writes the primary's when it is
# missing (feature-lifecycle.sh S1v), and self/gate.sh fails without it.
#
# Stages the real hooks/, self/worktree-setup.sh, self/gate.sh and .gitignore into
# throwaway git repos under mktemp -d and asserts, in order:
#   A. the setup hook, run in a fresh standalone worktree the way feature-start.sh runs
#      it, writes .claude/settings.json byte for byte what the generator writes into an
#      empty directory, leaves the worktree's `git status` clean (the file is ignored),
#      and a second run changes nothing;
#   B. self/gate.sh's settings check passes on that file, FAILS on a missing file and on
#      a drifted one, naming the exact regenerate command each time, and passes again
#      once that command has been run;
#   C. in the VENDORED layout (agentTooling/ one directory inside a consuming repo, no
#      .git of its own) the same setup hook writes no nested agentTooling/.claude/, so
#      the worktree holds exactly one settings file that names allow-repo-commands.sh —
#      the consuming repo's own, at its root; `--self --check` there passes on the
#      absence and fails on a nested copy; and self/gate.sh's check passes on it;
#   D. this checkout tracks no .claude/settings.json, and .gitignore covers it — which
#      is what keeps it out of the subtree every consuming repo pulls;
#   E. the OS sandbox block (self/features/runner-sandbox) in each layout: the self file
#      carries it with `enabled` at wire-settings.py's SANDBOX_ENABLED switch (OFF since
#      self/features/sandbox-consumer-reads), fail-closed and no unsandboxed retry, the
#      secret denyRead paths and the package domains; a hand-added domain there fails the
#      gate and the regenerate removes it; the vendored layout's root file carries the
#      same owned settings, a consumer's own domain survives a re-run of the wiring with
#      the generator's domains unioned in after it, and a consumer's `enabled` flipped by
#      hand against the switch is set back to it.
# No model, no network; a few seconds.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/self-settings.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# What is under test, and where
SETTINGS_REL=".claude/settings.json"
HOOK_FILES=(policy.py wire-settings.py allow-repo-commands.sh)
SELF_SCRIPTS=(worktree-setup.sh gate.sh)
HOOK_MARKER="allow-repo-commands.sh"
# The section self/gate.sh writes for its settings check, and the command a failure must
# name — the one a human runs, with this checkout's absolute paths filled in.
GATE_SECTION="## permission policy wired into .claude/settings.json"
REGEN_RE='python3 -B [^ ]*/hooks/wire-settings\.py --self --repo [^ ;)]* --write'
VENDOR_DIR_NAME="agentTooling"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# stage <dir> — the pieces of agentTooling this test drives, copied from this checkout.
stage() {
  mkdir -p "$1/hooks" "$1/self"
  for f in "${HOOK_FILES[@]}"; do cp "$HERE/hooks/$f" "$1/hooks/$f"; done
  for f in "${SELF_SCRIPTS[@]}"; do cp "$HERE/self/$f" "$1/self/$f"; done
  cp "$HERE/.gitignore" "$1/.gitignore"
  chmod +x "$1"/self/*.sh
}
# commit_repo <dir> — make it a repo on main with everything committed.
commit_repo() {
  git -C "$1" init -q
  git -C "$1" symbolic-ref HEAD refs/heads/main
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name "self-settings test"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}
# run_setup <worktree> <repo dir inside it> — the hook, as feature-start.sh runs it: from
# the worktree's toplevel, by the absolute path of the worktree's own copy.
run_setup() { ( cd "$1" && "$2/self/worktree-setup.sh" ) >/dev/null 2>&1; }
# gate_exit <repo dir> / gate_output <repo dir> — self/gate.sh's settings section. The
# staged checkout carries none of the other suites, so every other section fails; only
# this one is read.
run_gate() { "$1/self/gate.sh" >/dev/null 2>&1; }
gate_section() {
  awk -v want="$GATE_SECTION" '
    $0 == want { on = 1; next }
    on && /^## / { exit }
    on && /^# VERDICT/ { exit }
    on { print }
  ' "$1/self/gate-report.txt" 2>/dev/null
}
gate_exit() { gate_section "$1" | sed -n 's/^exit: //p' | head -n 1; }
# regen_command <text> — the regenerate command a failure names, or nothing.
regen_command() { grep -oE "$REGEN_RE" <<<"$1" | head -n 1; }

echo "self-settings"

# What the generator writes into an empty directory: THE file, for every check below.
EXPECTED_DIR="$TMP/expected"
mkdir -p "$EXPECTED_DIR"
python3 -B "$HERE/hooks/wire-settings.py" --self --repo "$EXPECTED_DIR" --write >/dev/null 2>&1
EXPECTED="$EXPECTED_DIR/$SETTINGS_REL"
check "0. the generator writes a file to compare against" '[[ -s "$EXPECTED" ]]'

# ── A. the setup hook writes it into a fresh standalone worktree ─────────────
SA="$TMP/standalone"
WT="$TMP/standalone-wt"
stage "$SA"
commit_repo "$SA"
git -C "$SA" worktree add -q "$WT" -b feat
check "A0. the fresh worktree starts without the file" '[[ ! -e "$WT/$SETTINGS_REL" ]]'
run_setup "$WT" "$WT"; rc=$?
check "A1. the setup hook exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "A2. it wrote $SETTINGS_REL" '[[ -f "$WT/$SETTINGS_REL" ]]'
check "A3. ... byte for byte what the generator writes" 'cmp -s "$WT/$SETTINGS_REL" "$EXPECTED"'
check "A4. ... and git ignores it: the worktree is clean" '[[ -z "$(git -C "$WT" status --porcelain)" ]]'
run_setup "$WT" "$WT"; rc=$?
check "A5. a second run exits 0 and changes nothing (got $rc)" '[[ $rc -eq 0 ]] && cmp -s "$WT/$SETTINGS_REL" "$EXPECTED"'

# ── B. the gate fails without it, and names the fix ──────────────────────────
run_gate "$WT"
check "B1. the gate's settings check passes on the generated file (got '$(gate_exit "$WT")')" \
  '[[ "$(gate_exit "$WT")" == "0" ]]'
rm -f "$WT/$SETTINGS_REL"
run_gate "$WT"
missing_out="$(gate_section "$WT")"
check "B2. ... FAILS when the file is missing (got '$(gate_exit "$WT")')" '[[ "$(gate_exit "$WT")" == "1" ]]'
check "B3. ... naming the regenerate command, with this checkout's paths" \
  '[[ "$(regen_command "$missing_out")" == *"--repo $WT --write" ]]'
mkdir -p "$WT/.claude"
printf '{}\n' > "$WT/$SETTINGS_REL"
run_gate "$WT"
drift_out="$(gate_section "$WT")"
check "B4. ... FAILS when the file has drifted from the generator (got '$(gate_exit "$WT")')" \
  '[[ "$(gate_exit "$WT")" == "1" ]]'
check "B5. ... naming the same command" \
  '[[ -n "$(regen_command "$drift_out")" && "$(regen_command "$drift_out")" == "$(regen_command "$missing_out")" ]]'
read -r -a regen <<<"$(regen_command "$drift_out")"
if (( ${#regen[@]} )); then "${regen[@]}" >/dev/null 2>&1; fi
run_gate "$WT"
check "B6. running that command makes the check pass again (got '$(gate_exit "$WT")')" \
  '[[ "$(gate_exit "$WT")" == "0" ]] && cmp -s "$WT/$SETTINGS_REL" "$EXPECTED"'

# ── C. a vendored agentTooling carries no nested settings file ───────────────
CONSUMER="$TMP/consumer"
CWT="$TMP/consumer-wt"
stage "$CONSUMER/$VENDOR_DIR_NAME"
printf 'a consuming repo\n' > "$CONSUMER/README.md"
# The consuming repo's own wiring, at ITS root, as sync-plans.sh writes it.
python3 -B "$CONSUMER/$VENDOR_DIR_NAME/hooks/wire-settings.py" --repo "$CONSUMER" --write >/dev/null 2>&1
commit_repo "$CONSUMER"
git -C "$CONSUMER" worktree add -q "$CWT" -b feat
run_setup "$CWT" "$CWT/$VENDOR_DIR_NAME"; rc=$?
check "C1. the setup hook exits 0 in the vendored layout (got $rc)" '[[ $rc -eq 0 ]]'
check "C2. ... and writes no nested $VENDOR_DIR_NAME/$SETTINGS_REL" '[[ ! -e "$CWT/$VENDOR_DIR_NAME/$SETTINGS_REL" ]]'
hook_files="$(grep -rlF "$HOOK_MARKER" --include=settings.json "$CWT" 2>/dev/null)"
check "C3. exactly one settings file in the worktree names $HOOK_MARKER, and it is the root's" \
  '[[ "$hook_files" == "$CWT/$SETTINGS_REL" ]]'
check "C4. --self --check passes on the absence" \
  'python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --self --repo "$CWT/$VENDOR_DIR_NAME" --check >/dev/null 2>&1'
run_gate "$CWT/$VENDOR_DIR_NAME"
check "C5. ... and so does self/gate.sh's settings check (got '$(gate_exit "$CWT/$VENDOR_DIR_NAME")')" \
  '[[ "$(gate_exit "$CWT/$VENDOR_DIR_NAME")" == "0" ]]'
mkdir -p "$CWT/$VENDOR_DIR_NAME/.claude"
cp "$EXPECTED" "$CWT/$VENDOR_DIR_NAME/$SETTINGS_REL"
nested_out="$(python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --self --repo "$CWT/$VENDOR_DIR_NAME" --check 2>&1)"; rc=$?
check "C6. a nested copy fails --self --check (got $rc: $nested_out)" '[[ $rc -eq 1 && "$nested_out" == UNWIRED* ]]'
printf '{}\n' > "$CWT/$VENDOR_DIR_NAME/$SETTINGS_REL"
python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --self --repo "$CWT/$VENDOR_DIR_NAME" --write >/dev/null 2>&1
check "C7. --self --write never generates into a vendored tree, even over a nested copy" \
  '[[ "$(cat "$CWT/$VENDOR_DIR_NAME/$SETTINGS_REL")" == "{}" ]]'
rm -rf "$CWT/$VENDOR_DIR_NAME/.claude"
python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --self --repo "$CWT/$VENDOR_DIR_NAME" --write >/dev/null 2>&1
check "C8. ... nor into one that has none" '[[ ! -e "$CWT/$VENDOR_DIR_NAME/.claude" ]]'

# ── E. the sandbox block, in each layout ─────────────────────────────────────
# Self layout: the file is generated, so the block is there and a hand-widened domain
# list is drift the gate refuses. Vendored layout: the consuming repo's root file is
# merged, so the block is there too and the repo's own domain survives a re-run of the
# wiring with the generator's entries unioned in beside it.
# sandbox_field <settings file> <owned|denyRead|domains|add-domain D|only-domain D|flip-enabled>
# — prints one space-joined field of the sandbox block, or edits it in place.
sandbox_field() {
  python3 -B - "$@" <<'PY'
import json, sys
path, what = sys.argv[1], sys.argv[2]
with open(path) as f:
    settings = json.load(f)
box = settings.get("sandbox") or {}
domains = (box.get("network") or {}).get("allowedDomains") or []
if what == "owned":
    print(" ".join("%s=%s" % (k, box.get(k))
                   for k in ("enabled", "failIfUnavailable", "allowUnsandboxedCommands")))
elif what == "denyRead":
    print(" ".join((box.get("filesystem") or {}).get("denyRead") or []))
elif what == "domains":
    print(" ".join(domains))
elif what == "flip-enabled":
    settings.setdefault("sandbox", {})["enabled"] = not box.get("enabled")
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
else:
    new = domains + [sys.argv[3]] if what == "add-domain" else [sys.argv[3]]
    settings.setdefault("sandbox", {}).setdefault("network", {})["allowedDomains"] = new
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
PY
}
OWN_DOMAIN="internal.example.invalid"
# wire-settings.py's SANDBOX_ENABLED switch, as Python prints it; flip with the constant
SANDBOX_ENABLED_EXPECTED="False"
check "E1. the self worktree's generated file carries the block with enabled=$SANDBOX_ENABLED_EXPECTED, fail-closed and no unsandboxed retry still written" \
  '[[ "$(sandbox_field "$WT/$SETTINGS_REL" owned)" == "enabled=$SANDBOX_ENABLED_EXPECTED failIfUnavailable=True allowUnsandboxedCommands=False" ]]'
check "E2. ... denies reads of the three secret paths" \
  '[[ "$(sandbox_field "$WT/$SETTINGS_REL" denyRead)" == "~/.ssh ~/.aws ~/.config/gh" ]]'
check "E3. ... and allows registry.npmjs.org and pypi.org among its domains" \
  '[[ " $(sandbox_field "$WT/$SETTINGS_REL" domains) " == *" registry.npmjs.org "* && " $(sandbox_field "$WT/$SETTINGS_REL" domains) " == *" pypi.org "* ]]'
sandbox_field "$WT/$SETTINGS_REL" add-domain "$OWN_DOMAIN"
run_gate "$WT"
check "E4. a domain hand-added to the self file fails the gate's settings check (got '$(gate_exit "$WT")')" \
  '[[ "$(gate_exit "$WT")" == "1" ]]'
python3 -B "$WT/hooks/wire-settings.py" --self --repo "$WT" --write >/dev/null 2>&1
check "E5. ... and the regenerate puts the generated bytes back" 'cmp -s "$WT/$SETTINGS_REL" "$EXPECTED"'
check "E6. the vendored layout's root file carries the same owned settings" \
  '[[ "$(sandbox_field "$CWT/$SETTINGS_REL" owned)" == "$(sandbox_field "$EXPECTED" owned)" ]]'
sandbox_field "$CWT/$SETTINGS_REL" only-domain "$OWN_DOMAIN"
python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --repo "$CWT" --write >/dev/null 2>&1
check "E7. ... where a consumer's own domain survives the wiring, first, the generator's unioned in after" \
  '[[ -n "$(sandbox_field "$EXPECTED" domains)" && "$(sandbox_field "$CWT/$SETTINGS_REL" domains)" == "$OWN_DOMAIN $(sandbox_field "$EXPECTED" domains)" ]]'
sandbox_field "$CWT/$SETTINGS_REL" flip-enabled
python3 -B "$CWT/$VENDOR_DIR_NAME/hooks/wire-settings.py" --repo "$CWT" --write >/dev/null 2>&1
check "E8. ... and a consumer's enabled flipped by hand against the switch is set back to enabled=$SANDBOX_ENABLED_EXPECTED" \
  '[[ "$(sandbox_field "$CWT/$SETTINGS_REL" owned)" == "enabled=$SANDBOX_ENABLED_EXPECTED failIfUnavailable=True allowUnsandboxedCommands=False" ]]'

# ── D. this checkout tracks none, so the subtree ships none ──────────────────
check "D1. $SETTINGS_REL is not tracked here" '[[ -z "$(git -C "$HERE" ls-files -- "$SETTINGS_REL")" ]]'
check "D2. ... and .gitignore covers it" 'git -C "$HERE" check-ignore -q --no-index -- "$SETTINGS_REL"'

if (( fails )); then
  echo "self-settings: $fails FAILED"
  exit 1
fi
echo "self-settings: all passed"
