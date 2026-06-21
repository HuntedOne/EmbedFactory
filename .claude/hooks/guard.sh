#!/bin/bash
# SECURITY guard (PreToolUse: Bash|Write|Edit). Enforces EmbedFactory's anti-tamper rules as
# machinery, not prompt wishes. Built for a user who is actively targeted: the priority is keeping
# UNKNOWN REPOSITORIES and PARENT/EXTERNAL FOLDERS out of the embedded projects worked on here.
#
# Blocks (exit 2):
#   - git remote add/set-url to an untrusted URL          (repository injection)
#   - git clone of an untrusted URL                       (repository injection)
#   - git submodule add / edits to .gitmodules            (nested repository injection)
#   - symlink creation (ln -s)                            (parent/external-folder injection)
#   - use of --add-dir                                    (scope-widening to an unlisted dir)
#   - piping a download into a shell (curl|wget ... | sh) (remote code execution)
#   - writing/editing the harness config (.claude/)       (self-tampering)
#   - any write outside the active project + harness/      (parent-folder injection / exfil)
#   - any write by the sentinel except into harness/reports (sentinel is read-only)
#
# "Trusted" = present in harness/allowed-roots (you curate it). exit 0 allows; exit 2 blocks.

DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/_common.sh"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)
ROLE="$(ef_role)"
TARGET="$(ef_target)"

block() { echo "🛑 EmbedFactory guard BLOCKED: $1" >&2; exit 2; }

# ---- Bash: scan for injection vectors ---------------------------------------
if [ "$TOOL" = "Bash" ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

  printf '%s' "$CMD" | grep -Eq -- '--add-dir' \
    && block "use of --add-dir — scope-widening to an unlisted directory is not allowed."

  printf '%s' "$CMD" | grep -Eq '\bln\b[^|;&]*[[:space:]]-s(f|n)?\b' \
    && block "symlink creation — a classic parent/external-folder injection vector."

  printf '%s' "$CMD" | grep -Eq '(curl|wget|fetch)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh\b' \
    && block "piping a download straight into a shell (remote code execution)."

  if printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bremote\b.*\b(add|set-url)\b'; then
    url=$(printf '%s' "$CMD" | grep -Eo '(https?://|git@|ssh://)[^[:space:]"'"'"']+' | head -1)
    { [ -n "$url" ] && remote_trusted "$url"; } \
      || block "adding/altering a git remote to an untrusted URL (${url:-unknown}). If you trust it, add a 'remote:' line to harness/allowed-roots first."
  fi

  printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bsubmodule\b.*\badd\b' \
    && block "git submodule add — unknown-repository injection."

  if printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bclone\b'; then
    url=$(printf '%s' "$CMD" | grep -Eo '(https?://|git@|ssh://)[^[:space:]"'"'"']+' | head -1)
    { [ -n "$url" ] && remote_trusted "$url"; } \
      || block "cloning an untrusted repository (${url:-unknown}). Add a 'remote:' prefix to harness/allowed-roots to authorize."
  fi

  exit 0
fi

# ---- WebFetch: only allowlisted reference documentation URLs ----------------
if [ "$TOOL" = "WebFetch" ]; then
  URL=$(printf '%s' "$INPUT" | jq -r '.tool_input.url // ""' 2>/dev/null)
  doc_url_trusted "$URL" \
    || block "WebFetch to a non-allowlisted URL (${URL:-unknown}). Add its base URL to REFERENCE_DOC_URLS in .env to authorize it."
  exit 0
fi

# ---- Write/Edit: confine writes, block tamper vectors -----------------------
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  [ -z "$FILE" ] && exit 0
  ABS="$(abspath "$FILE")"

  [ "$(basename "$ABS")" = ".gitmodules" ] && block "editing .gitmodules — submodule/repository injection vector."

  case "$ABS" in "$EF_DIR/.claude/"*) block "agents may not modify the harness config (.claude/)." ;; esac

  # Sentinel is read-only except for its reports.
  if [ "$ROLE" = "sentinel" ]; then
    within "$ABS" "$EF_DIR/harness/reports" && exit 0
    block "the sentinel is read-only (may only write harness/reports/)."
  fi

  # Writes are confined to the active project (which must itself be inside an allowed root) + harness/.
  if [ -n "$TARGET" ]; then
    path_in_roots "$TARGET" || block "the active project ($TARGET) is not inside any allowed root — refusing all writes. Fix harness/allowed-roots."
    within "$ABS" "$TARGET" && exit 0
  fi
  within "$ABS" "$EF_DIR/harness" && exit 0

  block "write outside the active project and harness/ — possible parent-folder injection: $ABS"
fi

exit 0
