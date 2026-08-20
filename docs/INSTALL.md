# Installing Counsel

Provenance: ORIGINAL (Apache-2.0). T2.11 deliverable. Status: pre-alpha.

> **First time installing?** Use **`docs/QUICKSTART.md`** instead — same install path, but with a
> verification check at every step and a usage guide at the end. This document is the reference:
> platform detail, teammate setup, updating, repair, and uninstall.

Counsel is distributed as a Claude Code **plugin** (the reusable runtime: skills, agents,
scripts) plus a **project control plane** that `/counsel:onboard` instantiates into your
project with your consent (AGENTS.md constitution with the embedded always-on rules
region + CLAUDE.md shim, `.counsel/` rules + work + session system, optional permission
baseline, ownership manifest). The plugin cannot and does not touch your settings or
inject always-on rules by itself — only the consented onboard flow writes to your project.

Since 0.1.5 the runtime is a **portable core**: `install-plan.ps1 -Harness cursor|codex`
stages the same logic for other harnesses (AGENTS.md natively, skills to
`.cursor/skills/` / `.codex/skills/`, agents as role cards). See `docs/PORTABILITY.md`;
those adapters are specified but not yet live-validated.


## Platform support

| Platform | Status |
|---|---|
| Windows 10/11 (PowerShell 5.1+) | **Supported.** The tested path |
| macOS | **Onboarding unsupported.** The plugin installs and every file is readable, but `/counsel:onboard` cannot complete — `scripts/install/install-plan.ps1` and `install-apply.ps1` have no shell equivalents. A `.sh` port is tracked, not scheduled |
| Linux | Untested. Same installer constraint as macOS |

Installing PowerShell on macOS is **not** a supported workaround: availability of `pwsh` does
not establish that these PS5.1 scripts, their path handling, and their assumptions behave
correctly there. Nobody has tested it. Do not put it in front of a first-time user.

## Path A — your own machine

```
gh auth login                                              # once, if the repo is private
claude plugin marketplace add sherzadeh/counsel-engineering-os
claude plugin install counsel@counsel-os
```

Then open your project in Claude Code and run `/counsel:onboard`. You'll be asked what
you're trying to do; Counsel recommends the smallest useful layer, shows the full install
plan (every file, classed CREATE / MERGE / CONFLICT), and applies **only what you approve**.
Permission-file changes are always a separate, explicit consent. It finishes by running
`/counsel:doctor`. READY means tooling is present **and** every credential your
installed capabilities depend on was proven live — unproven keys report NOT READY rather
than a green light you cannot cash (`/counsel:doctor --probe` runs the read-only probes).

## Path B — teammate joining a project that uses Counsel

If the project's `.claude/settings.json` contains the marketplace + plugin declaration,
Claude Code will prompt you to install Counsel when you trust the project folder:

```json
{
  "extraKnownMarketplaces": {
    "counsel-os": { "source": { "source": "github", "repo": "sherzadeh/counsel-engineering-os" } }
  },
  "enabledPlugins": { "counsel@counsel-os": true }
}
```

Note: `claude plugin install --scope project` writes `enabledPlugins` but NOT
`extraKnownMarketplaces` — add that block manually (or let onboard's team-setup step do it)
so fresh clones get the prompt. Private repo access still requires each teammate to
`gh auth login` once.

## Updating

Releases are immutable tags (`counsel--vX.Y.Z`); a version bump is what makes an update
visible. Updates are manual and user-visible by design:

```
claude plugin marketplace update counsel-os
claude plugin update counsel@counsel-os        # restart Claude Code to apply
```

Then run `/counsel:doctor` in your project — if your project files came from an older
runtime it reports **RUNTIME VERSION SKEW** and walks you through the update flow
(plan + consented apply; your local edits are never overwritten silently).

## Repair, recovery, uninstall

- **Repair** (missing/damaged Counsel-owned files): `scripts/install/repair.ps1 -Target <project>`.
  Locally-modified owned files are preserved unless you pass `-IncludeModified` (originals
  are backed up first). Repair refuses to cross versions — that's an update.
- **Recovery to a previous version:** previous immutable versions are retained in the plugin
  cache (`~/.claude/plugins/cache/counsel-os/counsel/<version>/`). Re-run the plan+apply flow
  with `-Source` pointed at the prior version directory; the doctor will explain the
  resulting skew until the plugin registration matches.
- **Uninstall:** `scripts/install/uninstall.ps1 -Target <project>` removes ONLY
  Counsel-owned files that you haven't modified. Your code, constitution, settings, config,
  session state, and any owned file you edited are all preserved; the ownership manifest is
  archived to `.counsel/originals/` for audit. `claude plugin uninstall counsel@counsel-os`
  removes the runtime itself.

## Windows notes

Everything above runs in Windows PowerShell 5.1+ with git as the only requirement — no
Git Bash, Python, or other tooling needed. The optional continuity hook pack ships
default-OFF and, when enabled, invokes `powershell.exe` explicitly.
