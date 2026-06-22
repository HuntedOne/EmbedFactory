#!/bin/bash
# EmbedFactory — an embedded-development mentor + security sentinel for STM32 / Arduino projects.
#
#   ./embed.sh setup <project-path|trusted-git-url>   register the active project (validated against
#                                                     harness/allowed-roots), record a baseline,
#                                                     and run a first security scan
#   ./embed.sh scan                                   run the security sentinel; writes harness/reports/
#   ./embed.sh mentor                                 open the embedded mentor (interactive)
#   ./embed.sh capture "<build/flash cmd>"            run a command in the project, saving output to
#                                                     harness/logs/ for the mentor to read
#   ./embed.sh community-refresh                       re-harvest the ST community catalog (you run it;
#                                                     asks to confirm, temporarily allowlists
#                                                     community.st.com for that run only, logs a summary)
#   ./embed.sh status                                 show active project, allowed roots, last scan
#
# Security: harness/allowed-roots is YOUR allowlist of trusted project roots + git remotes. The
# guard.sh hook blocks untrusted remotes/clones/submodules, symlinks, --add-dir, and writes outside
# the active project. Tunable: PERM=<permission-mode> (passed to claude; hooks enforce safety either way).
# No background daemons: a "catalog is N days old" reminder is printed only when you run mentor/status.

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT" || exit 1
. ".claude/hooks/_common.sh"

TARGET_FILE="harness/target"
PERM="${PERM:-}"
CMD="${1:-}"; ARG="${2:-}"
COMMUNITY_CATALOG="docs/reference/STMicroelectronics/community-catalog.md"
REFRESH_MAX_DAYS="${REFRESH_MAX_DAYS:-7}"

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

# Print a reminder if the ST community catalog hasn't been refreshed in REFRESH_MAX_DAYS. This is the
# ONLY scheduling mechanism — it runs in-process when you invoke the harness, never in the background.
refresh_reminder() {
  [ -f "$COMMUNITY_CATALOG" ] || return 0
  local d then now days
  d="$(grep -oE 'Last refreshed: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$COMMUNITY_CATALOG" | head -1 | awk '{print $3}')"
  [ -n "$d" ] || return 0
  then="$(date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null)" || return 0
  now="$(date +%s)"; days=$(( (now - then) / 86400 ))
  [ "$days" -ge "$REFRESH_MAX_DAYS" ] && \
    echo "ℹ️  ST community catalog is ${days}d old (≥${REFRESH_MAX_DAYS}d). Refresh when convenient: ./embed.sh community-refresh"
  return 0
}

case "$CMD" in
  setup)
    [ -n "$ARG" ] || { echo "usage: ./embed.sh setup <project-path|trusted-git-url>"; exit 1; }
    if printf '%s' "$ARG" | grep -Eq '^(https?://|git@|ssh://)'; then
      remote_trusted "$ARG" || { echo "🛑 untrusted remote: $ARG"; echo "   Add a 'remote:<prefix>' line to harness/allowed-roots to authorize it first."; exit 1; }
      name="$(basename "${ARG%.git}")"; proj="$ROOT/projects/$name"; mkdir -p "$ROOT/projects"
      if [ ! -e "$proj" ]; then echo "==> cloning trusted repo into projects/$name"; git clone "$ARG" "$proj" || { echo "clone failed"; exit 1; }; fi
    else
      proj="$(abspath "$ARG")"; [ -d "$proj" ] || { echo "not a directory: $proj"; exit 1; }
    fi
    path_in_roots "$proj" || { echo "🛑 $proj is not inside any allowed root."; echo "   Add its root to harness/allowed-roots to authorize it."; exit 1; }
    printf '%s\n' "$proj" > "$TARGET_FILE"
    echo "==> active project: $proj"
    mkdir -p harness/baseline
    base="harness/baseline/$(basename "$proj").json"
    remotes="$(git -C "$proj" remote -v 2>/dev/null | awk '{print $1" "$2}' | sort -u | paste -sd';' -)"
    head="$(git -C "$proj" rev-parse HEAD 2>/dev/null || echo none)"
    jq -n --arg p "$proj" --arg h "$head" --arg r "$remotes" --arg ts "$(ef_now)" \
      '{project:$p, head:$h, remotes:$r, recorded:$ts}' > "$base"
    echo "==> baseline recorded: $base"
    "$0" scan
    ;;

  scan)
    t="$(ef_target)"; [ -n "$t" ] || { echo "no active project; run ./embed.sh setup <path>"; exit 1; }
    mkdir -p harness/reports
    rpt="harness/reports/$(date -u +%Y%m%d-%H%M%S)-$(basename "$t").md"
    echo "==> running security sentinel on: $t"
    AGENT_ROLE=sentinel claude --agent sentinel --add-dir "$t" ${PERM:+--permission-mode "$PERM"} \
      -p "Audit the active embedded project at $t for malicious interference (untrusted git remotes, submodules / nested repos, symlinks escaping the project, external URLs/IPs or curl|bash in build scripts, Arduino board-manager URL injection, parent/external folder references, and drift vs harness/baseline/$(basename "$t").json). Write your report to $rpt with a CLEAN/SUSPICIOUS/COMPROMISED verdict on the first line."
    echo "==> report: $rpt"
    ;;

  mentor)
    refresh_reminder
    t="$(ef_target)"
    [ -n "$t" ] || echo "(no active project set — the mentor can still answer general questions; run ./embed.sh setup <path> to focus it)"
    AGENT_ROLE=mentor claude --agent mentor ${t:+--add-dir "$t"} ${PERM:+--permission-mode "$PERM"}
    ;;

  capture)
    t="$(ef_target)"; [ -n "$t" ] || { echo "no active project; run ./embed.sh setup <path>"; exit 1; }
    [ -n "$ARG" ] || { echo 'usage: ./embed.sh capture "<command>"'; exit 1; }
    mkdir -p harness/logs
    log="harness/logs/$(date -u +%Y%m%d-%H%M%S).log"
    { echo "# cmd: $ARG"; echo "# cwd: $t"; echo "# at:  $(ef_now)"; echo "---"; } | tee "$log"
    ( cd "$t" && eval "$ARG" ) 2>&1 | tee -a "$log"
    echo "==> saved: $log  (the mentor reads harness/logs/)"
    ;;

  community-refresh)
    # Re-harvest the ST community forum into docs/reference/STMicroelectronics/community-catalog.md.
    # REQUIRES interactive confirmation (never runs unattended). The forum is allowlisted ONLY for the
    # duration of this run (a temporary REFERENCE_DOC_URLS line is appended to .env and removed on
    # exit). The mentor cannot write to docs/ (guard.sh), so it writes a staged file under harness/ and
    # THIS script (running as you, not the agent) promotes it after a sanity check, then prints + logs
    # a summary to harness/community-refresh-history.log for future review.
    command -v claude >/dev/null 2>&1 || { echo "claude CLI not found in PATH"; exit 1; }
    CATALOG="docs/reference/STMicroelectronics/community-catalog.md"
    STAGE_DIR="harness/staging"; STAGE="$STAGE_DIR/community-catalog.md"
    PREV="$STAGE_DIR/community-catalog.prev.md"
    HIST="harness/community-refresh-history.log"
    today="$(date -u +%Y-%m-%d)"

    # --- permission gate: must be confirmed at an interactive terminal ----------------------------
    if [ ! -t 0 ]; then
      echo "🛑 community-refresh needs interactive confirmation and will not run unattended."
      echo "   Run it yourself from a terminal:  ./embed.sh community-refresh"
      exit 1
    fi
    printf 'Re-harvest the ST community forum now? This WebFetches community.st.com and rewrites\n  %s\nProceed? [y/N] ' "$CATALOG"
    read -r ans; case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "aborted — nothing changed."; exit 0 ;; esac

    mkdir -p "$STAGE_DIR" harness/logs
    log="harness/logs/$(date -u +%Y%m%d-%H%M%S)-community-refresh.log"
    rm -f "$STAGE"
    [ -f "$CATALOG" ] && cp "$CATALOG" "$PREV"

    # --- temporarily allowlist community.st.com (restored on any exit) -----------------------------
    cp .env "$STAGE_DIR/.env.refreshbak"
    cur="$(grep -E '^[[:space:]]*REFERENCE_DOC_URLS=' .env | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')"
    printf '\nREFERENCE_DOC_URLS="%s,https://community.st.com/"\n' "$cur" >> .env
    restore_env() { [ -f "$STAGE_DIR/.env.refreshbak" ] && mv -f "$STAGE_DIR/.env.refreshbak" .env; }
    trap restore_env EXIT INT TERM

    echo "==> refreshing ST community catalog ($today) — agent log: $log"
    read -r -d '' PROMPT <<EOF
Refresh the local ST community troubleshooting catalog.

1. For each board, WebFetch the category page, identify the most-viewed and "Resolved"/solved
   TROUBLESHOOTING threads (errors, connection/flash/debug/config failures — skip release
   announcements and feature requests), then WebFetch the top threads (~6-8 CubeIDE, ~6-8
   CubeProgrammer, ~5-7 CubeMonitor) and extract the exact symptom signature, root cause, and the
   ACCEPTED or ST-staff-confirmed fix:
   - STM32CubeIDE:        https://community.st.com/stm32cubeide-mcus-28
   - STM32CubeProgrammer: https://community.st.com/stm32cubeprogrammer-mcus-30
   - STM32CubeMonitor:    https://community.st.com/stm32cubemonitor-mcus-31
2. Read the current catalog for the exact format to preserve: $CATALOG
3. Write the FULL refreshed catalog to: $STAGE
   - Keep the header, trust/disclosure notes, the three "## STM32Cube..." sections (each a
     | Signature (grep) | Cause | Fix | Source | table with [st:NNNN] tags), the per-section
     "Threads:" links, and the closing "Using this catalog" section.
   - Set the header's "Last refreshed" line to: _Last refreshed: $today._
   - Prefer threads with a marked solution or ST employee/moderator answer; note rows without one.
   - Be faithful to the forum content; do not invent fixes. Write ONLY to $STAGE (you cannot edit docs/).
EOF
    PERM_RUN="${PERM:-acceptEdits}"
    AGENT_ROLE=mentor claude --agent mentor --permission-mode "$PERM_RUN" -p "$PROMPT" >>"$log" 2>&1

    # --- promote staged file only if it looks complete --------------------------------------------
    if [ -s "$STAGE" ] && grep -q '## STM32CubeIDE' "$STAGE" \
       && grep -q '## STM32CubeProgrammer' "$STAGE" && grep -q '## STM32CubeMonitor' "$STAGE"; then
      cp "$STAGE" "$CATALOG"
      ok=1
    else
      ok=0
    fi

    # --- summary (printed AND appended to the persistent review log) -------------------------------
    ids() { grep -oE '\[st:[0-9]+\]' "$1" 2>/dev/null | sort -u; }
    n_new="$(ids "$CATALOG" | wc -l | tr -d ' ')"
    if [ -f "$PREV" ]; then
      n_prev="$(ids "$PREV" | wc -l | tr -d ' ')"
      added="$(comm -13 <(ids "$PREV") <(ids "$CATALOG") | tr -d '[]' | paste -sd' ' -)"
      removed="$(comm -23 <(ids "$PREV") <(ids "$CATALOG") | tr -d '[]' | paste -sd' ' -)"
    else
      n_prev=0; added=""; removed=""
    fi
    {
      echo "=== community-refresh  $(ef_now) ==="
      if [ "$ok" = 1 ]; then echo "result: OK (catalog updated)"; else echo "result: FAILED (kept previous catalog)"; fi
      echo "entries (unique threads): ${n_prev} -> ${n_new}"
      echo "added:   ${added:-none}"
      echo "removed: ${removed:-none}"
      echo "agent log: $log"
      echo ""
    } | tee -a "$HIST"

    [ "$ok" = 1 ] || { echo "🛑 refresh did not produce a complete catalog — see $log"; exit 1; }
    echo "==> done. summary logged to $HIST"
    ;;

  status)
    echo "EmbedFactory : $ROOT"
    echo "active project: $(ef_target || echo '(none — run ./embed.sh setup <path>)')"
    echo "allowed roots :"; ef_roots | sed 's/^/   /'
    echo "trusted remotes:"; ef_remotes | sed 's/^/   /'
    echo "last reports :"; ls -1t harness/reports/*.md 2>/dev/null | head -3 | sed 's/^/   /' || true
    echo "recent logs  :"; ls -1t harness/logs/*.log 2>/dev/null | head -3 | sed 's/^/   /' || true
    cdate="$(grep -oE 'Last refreshed: [0-9-]+' "$COMMUNITY_CATALOG" 2>/dev/null | head -1 | awk '{print $3}')"
    echo "ST community catalog: last refreshed ${cdate:-unknown}"
    refresh_reminder
    ;;

  *) usage ;;
esac
