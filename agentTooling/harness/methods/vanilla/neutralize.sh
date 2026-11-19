#!/usr/bin/env bash
# vanilla's neutralization: take agentTooling's conventions and command hook out of a
# cell's tree for the length of the build, keep that out of every commit, and put it back.
# Sourced by ./run.sh and by self/tests/vanilla-pair.sh; never run. Needs git and jq, and
# lib.sh's harness_log / harness_warn.
#
# What is neutralized (README.md → "What the build does not see"):
#   - every tracked CLAUDE.md: each line that is only an import of CONVENTIONS.md (the
#     root's `@agentTooling/CONVENTIONS.md`, the vendored copy's own `@CONVENTIONS.md`) is
#     dropped; every other line stays, so the project's own part of the file is unchanged;
#   - the tracked .claude/settings.json at the tree root: its `hooks` and `permissions`
#     keys are deleted (the PreToolUse command hook, the SessionStart hook, the deny and
#     ask rules); every other key stays.
#
# How it stays out of the arm's diff: each changed file is marked skip-worktree, which
# `git add -A`, `git commit -a` and an explicit `git add <file>` all respect (only
# `--sparse` or clearing the bit gets past it). vanilla_verify refuses a build whose
# commits changed one of them anyway; vanilla_restore clears the bit and checks the file
# out from HEAD. The list of neutralized paths lives in the worktree's own git dir, never
# in the tree, so a killed attempt is found and restored by the next neutralization.

# The line Claude Code expands into the conventions: `@` + a path ending in CONVENTIONS.md
VANILLA_IMPORT_RE='^@([^[:space:]]*/)?CONVENTIONS\.md[[:space:]]*$'
# Every tracked CLAUDE.md, the root's included
VANILLA_CLAUDE_MD_PATHSPEC=':(glob)**/CLAUDE.md'
# The project settings Claude Code loads from the session's cwd (the tree root)
VANILLA_SETTINGS_RELPATH=".claude/settings.json"
VANILLA_SETTINGS_JQ='del(.hooks, .permissions)'
# The neutralized-path list, in the worktree's git dir (git rev-parse --git-path)
VANILLA_LIST_NAME="harness-vanilla-neutralized"
# run.sh's exit codes when a signal ends it, so its EXIT trap still restores the tree
VANILLA_TERM_RC=143
VANILLA_INT_RC=130

vanilla_list_path() {  # $1 tree -> the absolute path of the neutralized-path list
  git -C "$1" rev-parse --path-format=absolute --git-path "$VANILLA_LIST_NAME"
}

# vanilla_rewrite <tree> <relpath> <filter command...>: rewrite one tracked file through a
# filter; when the content changes, mark it skip-worktree and record it. Returns 1 on error.
vanilla_rewrite() {
  local tree="$1" rel="$2" list tmp
  shift 2
  list="$(vanilla_list_path "$tree")" || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/harness-vanilla.XXXXXX")" || return 1
  if ! "$@" < "$tree/$rel" > "$tmp"; then
    rm -f "$tmp"; harness_warn "vanilla: could not filter $rel"; return 1
  fi
  if cmp -s "$tmp" "$tree/$rel"; then
    rm -f "$tmp"; return 0
  fi
  git -C "$tree" update-index --skip-worktree -- "$rel" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$rel" >> "$list"
  cat "$tmp" > "$tree/$rel"
  rm -f "$tmp"
  harness_log "vanilla: neutralized $rel for the build"
}

vanilla_drop_imports() { grep -vE "$VANILLA_IMPORT_RE" || true; }
vanilla_drop_hooks() { jq "$VANILLA_SETTINGS_JQ"; }

# vanilla_neutralize <tree>
vanilla_neutralize() {
  local tree="$1" list rel
  list="$(vanilla_list_path "$tree")" || return 1
  if [[ -f "$list" ]]; then
    harness_warn "vanilla: an earlier attempt left $tree neutralized — restoring it first"
    vanilla_restore "$tree" || return 1
  fi
  : > "$list"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    vanilla_rewrite "$tree" "$rel" vanilla_drop_imports || return 1
  done < <(git -C "$tree" ls-files -- "$VANILLA_CLAUDE_MD_PATHSPEC")
  if git -C "$tree" ls-files --error-unmatch -- "$VANILLA_SETTINGS_RELPATH" >/dev/null 2>&1; then
    vanilla_rewrite "$tree" "$VANILLA_SETTINGS_RELPATH" vanilla_drop_hooks || return 1
  elif [[ -e "$tree/$VANILLA_SETTINGS_RELPATH" ]]; then
    harness_warn "vanilla: $VANILLA_SETTINGS_RELPATH is not tracked — left as it is, so its hook stays live"
  fi
  [[ -s "$list" ]] || harness_log "vanilla: nothing to neutralize in $tree (no CONVENTIONS.md import, no tracked hook)"
}

# vanilla_verify <tree> <start commit>: fail when a commit since <start> changed a
# neutralized file — the arm's diff would then carry the tooling change.
vanilla_verify() {
  local tree="$1" start="$2" list rel bad=0
  list="$(vanilla_list_path "$tree")" || return 1
  [[ -f "$list" ]] || return 0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if ! git -C "$tree" diff --quiet "$start" HEAD -- "$rel"; then
      harness_warn "vanilla: a commit since ${start:0:7} changed $rel, which was neutralized for the build — the arm's diff is not the feature alone"
      bad=1
    fi
  done < "$list"
  return "$bad"
}

# vanilla_restore <tree>: clear the bits and check every neutralized file out from HEAD.
vanilla_restore() {
  local tree="$1" list rel rc=0
  list="$(vanilla_list_path "$tree")" || return 1
  [[ -f "$list" ]] || return 0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    git -C "$tree" update-index --no-skip-worktree -- "$rel" || rc=1
    git -C "$tree" checkout HEAD -- "$rel" || rc=1
  done < "$list"
  if (( rc == 0 )); then
    rm -f "$list"
    harness_log "vanilla: restored the neutralized files in $tree"
  else
    harness_warn "vanilla: could not restore every file in $list"
  fi
  return "$rc"
}
