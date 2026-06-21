#!/bin/bash
# SessionStart hook — a fast, non-blocking security banner + anomaly check for the active project.
# Surfaces obvious tamper signs (untrusted remotes, .gitmodules, symlinks) so they're visible the
# moment a session starts. The deep audit is the sentinel agent (./embed.sh scan).

DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/_common.sh"
TARGET="$(ef_target)"

echo "🛡  EmbedFactory active — guard.sh is enforcing: no untrusted remotes/clones/submodules, no symlinks, no --add-dir, no pipe-to-shell; writes confined to the active project + harness/."

if [ -z "$TARGET" ]; then
  echo "   No active project set. Run: ./embed.sh setup <project-path>"
  exit 0
fi
echo "   Active project: $TARGET"
path_in_roots "$TARGET" || echo "   ⚠️  WARNING: active project is NOT inside any allowed root (harness/allowed-roots)."

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r line; do
    url=$(printf '%s' "$line" | awk '{print $2}')
    [ -n "$url" ] && { remote_trusted "$url" || echo "   ⚠️  UNTRUSTED git remote: $line"; }
  done < <(git -C "$TARGET" remote -v 2>/dev/null | awk '{print $1, $2}' | sort -u)
fi

[ -f "$TARGET/.gitmodules" ] && echo "   ⚠️  .gitmodules present — review submodules: $TARGET/.gitmodules"
syms=$(find "$TARGET" -maxdepth 4 -type l 2>/dev/null | head -5)
[ -n "$syms" ] && { echo "   ⚠️  Symlinks found (review):"; printf '       %s\n' $syms; }
exit 0
