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
#   ./embed.sh status                                 show active project, allowed roots, last scan
#
# Security: harness/allowed-roots is YOUR allowlist of trusted project roots + git remotes. The
# guard.sh hook blocks untrusted remotes/clones/submodules, symlinks, --add-dir, and writes outside
# the active project. Tunable: PERM=<permission-mode> (passed to claude; hooks enforce safety either way).

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT" || exit 1
. ".claude/hooks/_common.sh"

TARGET_FILE="harness/target"
PERM="${PERM:-}"
CMD="${1:-}"; ARG="${2:-}"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

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

  status)
    echo "EmbedFactory : $ROOT"
    echo "active project: $(ef_target || echo '(none — run ./embed.sh setup <path>)')"
    echo "allowed roots :"; ef_roots | sed 's/^/   /'
    echo "trusted remotes:"; ef_remotes | sed 's/^/   /'
    echo "last reports :"; ls -1t harness/reports/*.md 2>/dev/null | head -3 | sed 's/^/   /' || true
    echo "recent logs  :"; ls -1t harness/logs/*.log 2>/dev/null | head -3 | sed 's/^/   /' || true
    ;;

  *) usage ;;
esac
