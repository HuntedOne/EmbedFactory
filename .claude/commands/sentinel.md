---
name: sentinel
description: Run the read-only security sentinel against the active project and write a report.
disable-model-invocation: true
---

Act as the **sentinel** agent.

1. Read `harness/target` for the active project path (`$PROJECT`) and `harness/allowed-roots` for
   the trust allowlist. If no target is set, tell me to run `./embed.sh setup <path>` first.
2. Perform the full audit from your agent definition (git remotes, submodules/nested repos,
   symlinks, network-fetching build files, parent/external path references, Arduino supply-chain,
   recently changed files), comparing against `harness/baseline/<project>.json` if present.
3. Write your report to `harness/reports/<timestamp>-<project>.md` with a CLEAN / SUSPICIOUS /
   COMPROMISED verdict on the first line, then evidence-based findings.

You are read-only with respect to the project — never modify its files.
