# EmbedFactory — an embedded-development mentor with a security sentinel

EmbedFactory is a Claude Code harness for developing and debugging **embedded firmware** in the
**STMicroelectronics** (STM32CubeIDE, STM32CubeMX) and **Arduino** toolchains. Unlike the
build-loop factories (CodeFactory/BlueFactory) or the review harness (BrownFactory), its center is a
**Mentor** that reads your project and your terminal/build logs to advise and troubleshoot — plus a
**Sentinel** and enforced hooks that keep attackers out of your projects.

It is built for a developer who is an **active target**: the security rules are **machinery, not
prompt wishes**, and they focus on keeping **unknown repositories and parent/external folders** from
being injected into the work. See [SECURITY.md](harness/SECURITY.md).

## The two agents

| Agent | Role | Writes? |
|---|---|---|
| **Mentor** | Embedded expert (STM32CubeIDE/CubeMX, Arduino). Reads your project + `harness/logs/` + the bundled vendor manuals; explains and troubleshoots build/flash/HAL/clock/linker/serial issues; fixes inside the active project when asked. Security-vigilant. | ✅ active project only |
| **Sentinel** | Read-only security watchdog. Audits for injected repos/submodules/symlinks, network-fetching build scripts, parent/external references, and drift vs baseline; writes a CLEAN/SUSPICIOUS/COMPROMISED report. | ❌ (reports only) |

## Bundled knowledge base (`docs/`)
The mentor grounds its advice in the manuals you've placed here:
- `docs/reference/STMicroelectronics/` — UM2609 (STM32CubeIDE), UM1718 (STM32CubeMX), `.ioc` walkthroughs.
- `docs/reference/Arduino/` — board datasheets, pinout, schematics.
- `docs/project/` — project-specific notes.

## Security — enforced as machinery
- **`harness/allowed-roots`** (gitignored, you curate it) is the trust anchor: trusted project roots
  + `remote:` git-URL prefixes. Anything else is treated as injection.
- **`guard.sh`** (PreToolUse) blocks: untrusted git remote/clone/submodule, `.gitmodules` edits,
  symlink creation, `--add-dir`, pipe-to-shell, edits to `.claude/`, and any write outside the active
  project + `harness/`.
- **`sentinel-quickcheck.sh`** (SessionStart) prints a banner + fast anomaly check.
- **`log-action.sh`** appends every tool call to `harness/audit.log` (forensic trail).
- **Online docs allowlist:** the mentor may `WebFetch` only URLs listed in `.env`
  (`REFERENCE_DOC_URLS`) — e.g. `https://docs.flux.ai/` — to help with tools that have no local
  manual. Any other URL is blocked. Copy `.env.example` to `.env` and edit the list.

## Usage

```bash
# 1. Authorize your trusted projects & remotes (TIGHT list)
cp harness/allowed-roots.example harness/allowed-roots
$EDITOR harness/allowed-roots

# 2. Register the active embedded project (validates against the allowlist, scans it)
./embed.sh setup /path/to/your/stm32-or-arduino-project
#   or a trusted remote:  ./embed.sh setup https://github.com/your-org/your-repo.git

# 3. Work: capture a build/flash log, then ask the mentor
./embed.sh capture "make -j"            # or your arduino-cli / cubeide build command
./embed.sh mentor                        # interactive — or run /mentor in a claude session here

# Security audit any time
./embed.sh scan                          # writes harness/reports/<ts>-<project>.md
./embed.sh status
```

> The mentor and sentinel run *from* EmbedFactory with `--add-dir <active project>` so they can read
> the project while the harness config, logs, reports, and allowlist stay here. After editing files
> under `.claude/agents/`, restart Claude Code so new definitions load.

## A caveat worth keeping
These guards raise the cost of tampering and make it visible; they are not a replacement for
OS-level security (see SECURITY.md). Re-test whether each guard still earns its place as tools evolve.
