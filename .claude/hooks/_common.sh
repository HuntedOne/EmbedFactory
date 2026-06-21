#!/bin/bash
# Shared helpers for EmbedFactory hooks and the embed.sh orchestrator.
# Sourced, not executed. Provides path resolution and the security allowlist primitives.

# EmbedFactory root: the harness's own directory.
EF_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

ef_role() { printf '%s' "${AGENT_ROLE:-interactive}"; }
ef_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Active project path (absolute), if one is set.
ef_target() { [ -f "$EF_DIR/harness/target" ] && head -1 "$EF_DIR/harness/target" || true; }

# Portable absolute path (does not require the path to exist).
abspath() { realpath -m -- "$1" 2>/dev/null || python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$1"; }

# Trusted project roots from the allowlist (absolute). The EmbedFactory projects/ dir is always
# trusted (it only ever holds repos cloned from an allowed remote).
ef_roots() {
  printf '%s\n' "$(abspath "$EF_DIR/projects")"
  local f="$EF_DIR/harness/allowed-roots"
  [ -f "$f" ] || return 0
  grep -vE '^[[:space:]]*(#|remote:|$)' "$f" | while IFS= read -r line; do
    [ -n "$line" ] && abspath "$line"
  done
}

# Trusted git remote URL prefixes from the allowlist.
ef_remotes() {
  local f="$EF_DIR/harness/allowed-roots"
  [ -f "$f" ] || return 0
  grep -E '^[[:space:]]*remote:' "$f" | sed -E 's/^[[:space:]]*remote:[[:space:]]*//'
}

# within <path> <root> : 0 if path is inside root.
within() {
  local p r; p="$(abspath "$1")/"; r="$(abspath "$2")/"
  case "$p" in "$r"*) return 0;; *) return 1;; esac
}

# path_in_roots <path> : 0 if path is inside ANY trusted root.
path_in_roots() {
  local p="$1" root
  while IFS= read -r root; do [ -n "$root" ] && within "$p" "$root" && return 0; done < <(ef_roots)
  return 1
}

# remote_trusted <url> : 0 if url matches ANY trusted remote prefix.
remote_trusted() {
  local url="$1" pre
  while IFS= read -r pre; do [ -n "$pre" ] && case "$url" in "$pre"*) return 0;; esac; done < <(ef_remotes)
  return 1
}

# Allowlisted reference documentation URL prefixes, from REFERENCE_DOC_URLS in .env.
ef_doc_urls() {
  local f="$EF_DIR/.env"
  [ -f "$f" ] || return 0
  grep -E '^[[:space:]]*REFERENCE_DOC_URLS=' "$f" | tail -1 \
    | sed -E 's/^[^=]*=//; s/^["'\'']//; s/["'\'']$//' \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$'
}

# doc_url_trusted <url> : 0 if url matches ANY allowlisted documentation prefix.
doc_url_trusted() {
  local url="$1" pre
  while IFS= read -r pre; do [ -n "$pre" ] && case "$url" in "$pre"*) return 0;; esac; done < <(ef_doc_urls)
  return 1
}
