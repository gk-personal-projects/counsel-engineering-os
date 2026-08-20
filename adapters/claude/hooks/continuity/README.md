# Core Continuity Hook Pack

Provenance: ORIGINAL (Apache-2.0). Class ruled by D-T2-009 (A8-modified): available below
Full OS because deterministic session continuity supports Core reliability. **Default OFF.**
Installed only with explicit consent, after `/counsel:doctor` validates compatibility.

## Non-negotiable contract (D-T2-009 / D-T2-018)

- Checkpoint/restore is fully functional WITHOUT these hooks. They are convenience, not
  load-bearing safety.
- Graceful degradation: if a hook cannot run, the session continues; nothing corrupts.
- No hidden dependencies: hooks invoke only the pack's own scripts via the platform's
  native shell (PowerShell on Windows, sh on POSIX). No Python, no Git Bash requirement
  on Windows, no network, no telemetry.
- A hook failure never overwrites or corrupts authoritative session state — hooks only
  ever call the ATOMIC checkpoint (failed attempts land in FAILED-*, pointer untouched)
  or read state.
- **Crash recovery never relies on SessionEnd.** SessionEnd is best-effort only.
- Advanced automation hooks (gates, enforcement, tool interception) are NOT in this pack —
  they are Full-OS explicit-opt-in capabilities.

## Hooks in this pack

| Event | Matcher | Action | Failure mode |
|---|---|---|---|
| SessionStart | startup, resume, clear, compact | Print RESTORE.md + CAPSULE.md into context (read-only) | Silent skip; user runs /counsel:restore manually |
| PreCompact | manual, auto | Mechanical checkpoint, label `pre-compact` | Compaction proceeds; doctor flags missing checkpoint |
| SessionEnd | — | Best-effort mechanical checkpoint, label `session-end` | None (never relied upon) |

## Wiring

The installer writes hook entries into the project's `.claude/settings.json` ONLY when the
user opts in during onboarding or later via capability enable. Doctor pre-checks:
PowerShell/sh available, scripts present, session dir exists, a manual checkpoint succeeds.

Windows command shape (no Git Bash dependency):

```json
{ "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \".counsel/os/scripts/session/read-state.ps1\"" }
```

POSIX command shape:

```json
{ "type": "command", "command": "sh .counsel/os/scripts/session/read-state.sh" }
```

(Exact paths are instantiated by the installer from where it placed the runtime. The hook
JSON above is a shape reference; the installer must verify the current official Claude
Code hooks schema at install time rather than trusting this file's snapshot.)

`read-state.ps1` / `read-state.sh` are trivial read-only printers of RESTORE.md +
CAPSULE.md; `pre-compact` and `session-end` entries call the standard atomic
checkpoint script with the corresponding label.
