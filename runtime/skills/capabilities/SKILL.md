---
name: capabilities
description: Show installed and available capabilities with status. Use on /counsel:capabilities or when the user asks what Counsel can do or has installed.
user_invocable: true
---

# /counsel:capabilities

Provenance: ORIGINAL (Apache-2.0).

Read the capability registry + project config (.counsel/config.yaml) + manifest; report
per capability: **READY / INSTALLED / OPTIONAL / MISSING / PARTIAL / DISABLED /
INCOMPATIBLE / OUTDATED / NOT RELEVANT**, grouped by layer (Core → Builder →
Engineering Team → Full OS → optional).

For anything not installed, one line: what it adds + when it's worth it (from
`recommended_for`) — no sales pitch, no jargon. Operations offered: install / enable /
disable / remove / upgrade (removal never deletes project decisions or context).
Enabling anything with `consequential_install: true` dependencies routes through explicit
consent. Close with: "Not sure? /counsel:recommend describes your goal instead."
