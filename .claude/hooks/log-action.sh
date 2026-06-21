#!/bin/bash
# Audit-trail hook (PreToolUse, all tools). Appends one JSON line per tool call to
# harness/audit.log — a forensic timeline (who/when/what) that survives across sessions.
# Useful when you are a target: you can reconstruct exactly what ran. Never blocks.

DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/_common.sh"
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)
ARG=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
jq -nc --arg ts "$(ef_now)" --arg role "$(ef_role)" --arg tool "$TOOL" --arg arg "$ARG" \
  '{ts:$ts, role:$role, tool:$tool, arg:$arg}' >> "$EF_DIR/harness/audit.log" 2>/dev/null
exit 0
