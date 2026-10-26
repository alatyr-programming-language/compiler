#!/usr/bin/env bash
# scripts/install-hooks.sh — install this repository's git hooks into the CURRENT checkout or worktree.
#
# Why an installer is needed: git does not clone `.git/hooks/`. A hook committed under `scripts/hooks/`
# is inert until something copies it into the git directory, so every clone, every worktree and every
# panel's machine needs this run once. It is not the guarantee — `scripts/land.sh` PHASE 2 holds the
# rule on the machine that lands, and `scripts/land.sh --self-test` proves the decider fires. The hook
# only moves the refusal earlier, to the moment the message is written.
#
# Usage: bash scripts/install-hooks.sh          (this checkout/worktree)
#        bash scripts/install-hooks.sh --all   (this one and every registered worktree)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/hooks"

install_into() { # repo-or-worktree path
  local wd="$1" hooks dst n=0 bad=0
  cd "$wd" 2>/dev/null || { echo "skip $wd: not a directory"; return 1; }
  hooks="$(git rev-parse --git-path hooks 2>/dev/null)" || { echo "skip $wd: not a git repository"; return 1; }
  mkdir -p "$hooks"
  for f in "$SRC"/*; do
    [ -f "$f" ] || continue
    dst="$hooks/$(basename "$f")"
    if [ -e "$dst" ] && ! cmp -s "$f" "$dst"; then
      # Never silently overwrite a hook that is not ours: it may be a user's own, or another tool's.
      if grep -q "scripts/attribution.sh" "$dst" 2>/dev/null; then
        cp "$f" "$dst"; chmod +x "$dst"; echo "updated $(basename "$f") (stale copy of ours)"
      else
        echo "LEFT ALONE $dst: not our hook and not identical. Install by hand if it is yours to replace."
        bad=$((bad + 1)); continue
      fi
    elif [ ! -e "$dst" ]; then
      cp "$f" "$dst"; chmod +x "$dst"; echo "installed $(basename "$f")"
    fi
    n=$((n + 1))
  done
  echo "  $wd — $n hook(s) active, $bad left alone"
  [ "$bad" = 0 ]
}

rc=0
case "${1:-}" in
  --all)
    install_into "$ROOT" || rc=1
    # `git worktree list --porcelain` lists the main checkout first, then each linked worktree.
    while IFS= read -r line; do
      case "$line" in worktree\ *) wd="${line#worktree }"; [ "$wd" = "$ROOT" ] && continue
                       install_into "$wd" || rc=1 ;; esac
    done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)
    ;;
  '') install_into "$ROOT" || rc=1 ;;
  *)  echo "usage: bash scripts/install-hooks.sh [--all]" >&2; exit 2 ;;
esac
exit $rc
