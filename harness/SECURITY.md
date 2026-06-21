# EmbedFactory — security model

This harness is built for a developer who is an **active target of attackers**. Its threat model
centers on **malicious interference with embedded projects**, especially the **injection of unknown
repositories or parent/external folders** into the work.

## The trust anchor: `harness/allowed-roots`
You curate an allowlist of trusted **project roots** (absolute paths) and trusted **git remotes**
(`remote:` URL prefixes). Everything not on the list is treated as hostile. This file is gitignored
(machine-specific) — keep it tight.

## Enforced as machinery (the `guard.sh` PreToolUse hook), not just prompts
Blocked outright (the agent is stopped, with an explanation):
- `git remote add` / `set-url` to an **untrusted URL**; `git clone` of an untrusted URL.
- `git submodule add` and edits to `.gitmodules` (nested-repository injection).
- **symlink** creation (`ln -s`) — parent/external-folder injection.
- `--add-dir` (scope-widening to an unlisted directory).
- piping a download into a shell (`curl|wget … | sh`).
- any write to the harness config (`.claude/`).
- any write **outside the active project + `harness/`** (parent-folder injection / exfil).
- any write by the **sentinel** except into `harness/reports/` (it is read-only).
- any `WebFetch` to a URL **not** allowlisted in `.env` (`REFERENCE_DOC_URLS`) — the mentor may
  fetch trusted documentation sites (e.g. Flux.ai) and nothing else.

## Watched and reported (the `sentinel` agent — `./embed.sh scan`)
A read-only deep audit: untrusted remotes, submodules and nested `.git` dirs, escaping symlinks,
network-fetching/RCE in build files, parent/external path references, Arduino board-manager
supply-chain, and **drift vs the baseline** recorded at setup. Produces a CLEAN / SUSPICIOUS /
COMPROMISED report in `harness/reports/`.

## Surfaced immediately (`SessionStart` hook)
A fast banner + anomaly check (untrusted remotes, `.gitmodules`, symlinks) every time a session starts.

## Forensic trail (`log-action.sh`)
Every tool call is appended to `harness/audit.log` (timestamp, agent role, tool, argument) so you can
reconstruct exactly what ran.

## Honest limits
These controls raise the cost of tampering and make it visible — they are **not** a substitute for
OS-level security. They run inside Claude Code and assume the hook scripts and your shell are not
already compromised. Keep your OS, Claude Code, the STM32/Arduino toolchains, and your git
credentials patched and protected; use full-disk encryption and a hardware key where you can. If the
sentinel ever returns **COMPROMISED**, stop, do not build or flash, and investigate from a known-good
machine.
