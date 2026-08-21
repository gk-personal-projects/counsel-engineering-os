# Distribution channels

Provenance: ORIGINAL (Apache-2.0).


## Channels (specced)

| Channel | Harness | Mechanism | Repo changes needed |
|---|---|---|---|
| Claude Code plugin marketplace | Claude | `claude plugin marketplace add <owner>/counsel-engineering-os` + `claude plugin install counsel@counsel-os` (`.claude-plugin/` at root; immutable `counsel--vX.Y.Z` tags via `claude plugin tag`) | none — existing first-class channel |
| `npx skills add` (skills.sh / Vercel skills CLI) | Cursor, Codex, others | Discovers `SKILL.md` folders; `runtime/skills/` already conforms to the Agent Skills standard | **zero** — enable by publishing only |
| Installer (this repo / release snapshot) | all | `install-plan.ps1 -Harness ...` + `install-apply.ps1` (Windows) / `install-plan.sh` + `install-apply.sh` (POSIX, same flags) | none |

## Versioning

`VERSION` governs; `plugin.json` mirrors it; adapters version with the repo. Releases
are immutable tags. Per-harness installs stamp `harness:` + `runtime_version` into
`.counsel/config.yaml`; doctor reports RUNTIME VERSION SKEW identically everywhere.
