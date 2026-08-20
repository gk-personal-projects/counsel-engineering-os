# Cursor adapter (specified — validated later)

Provenance: ORIGINAL (Apache-2.0).

Status: **SPECIFIED, NOT YET VALIDATED** in a live Cursor session. Emission is wired in
the installer; the checklist below gates calling this adapter supported.

## What the installer emits for `-Harness cursor`

- `AGENTS.md` constitution with the sentinel rules block (Cursor reads it natively).
- `.cursor/rules/counsel-<name>.mdc` per `rules-map.json` — same rule bodies as
  `.counsel/rules/`, generated frontmatter (`alwaysApply` / `description`).
- `.cursor/skills/<name>/SKILL.md` — Agent Skills standard copies of `runtime/skills/`.
- `.counsel/agents/*.md` — role cards (adopt in-context; see `runtime/HARNESS.md`).
- `.counsel/` control plane identical to every harness. No `.claude/` surfaces,
  no settings baseline (Claude-only permission format).

## Validation checklist (run in a real Cursor session before declaring support)

1. Fresh install into a toy repo with `-Harness cursor`; Cursor loads AGENTS.md and an
   `alwaysApply` .mdc rule fires without being @-mentioned.
2. A skill invocation (e.g. the queue skill) is discoverable and follows its procedure.
3. Boot protocol: a new session reads `.counsel/session/RESTORE.md` before working
   (degraded-mode continuity — no hooks).
4. Manual checkpoint: `scripts/session/checkpoint.ps1` (or `.sh`) runs from Cursor's
   terminal and session-doctor reports healthy.
5. Rule double-loading check: always-on content appears once in effective context, not
   twice (AGENTS.md block vs .mdc) — if Cursor double-loads, drop `alwaysApply` emission
   and keep AGENTS.md-only delivery.
6. Verify Cursor's current skills directory convention still matches `.cursor/skills/`
   (the convention was still settling when this adapter was specified).
