# Codex CLI adapter (specified — validated later)

Provenance: ORIGINAL (Apache-2.0).

Status: **SPECIFIED, NOT YET VALIDATED** in a live Codex session. Emission is wired in
the installer; the checklist below gates calling this adapter supported.

## What the installer emits for `-Harness codex`

- `AGENTS.md` constitution with the sentinel rules block — **the only automatic
  instruction channel Codex reads.** Budget: < 32 KiB (Codex truncates; installer warns,
  doctor checks).
- `.codex/skills/<name>/SKILL.md` — Agent Skills standard copies of `runtime/skills/`.
- `.counsel/agents/*.md` — role cards (adopt in-context; see `runtime/HARNESS.md`).
- `.counsel/` control plane identical to every harness. No `.claude/` surfaces, no
  settings baseline, no hooks.

## Autonomy mapping (see `config-notes.md`)

Codex approval modes are coarser than the Counsel lease; the lease still governs — the
harness mode is a ceiling, not a substitute.

## Validation checklist (run in a real Codex CLI session before declaring support)

1. Fresh install into a toy repo with `-Harness codex`; `codex` picks up AGENTS.md
   (verify a rule from the sentinel block is honored, e.g. discovered-work-needs-approval).
2. A skill under `.codex/skills/` is discoverable and followed.
3. Boot protocol: new session reads `.counsel/session/RESTORE.md` first (degraded mode).
4. Manual checkpoint via `scripts/session/checkpoint.sh` (Codex often runs POSIX-side);
   session-doctor healthy.
5. AGENTS.md size check under real project content — confirm nothing is truncated
   (doctor reports bytes vs the 32 KiB budget).
