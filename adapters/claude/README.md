# Claude Code adapter

Provenance: ORIGINAL (Apache-2.0).

Everything Claude Code-specific lives here (or is documented here). The portable core
(`runtime/`, `scaffold/`) never references Claude mechanics directly — see
`runtime/HARNESS.md` for the vocabulary contract.

## Pieces

- **`hooks/continuity/`** — optional SessionStart / PreCompact hook pack (moved from
  `runtime/hooks/`). Registered in `.claude/settings.json` only with explicit consent
  and doctor validation (registry: `session-continuity-hooks`, Claude-only; manual
  checkpoint/restore is fully functional without it).
- **`model-map.json`** — maps the semantic model classes (ECONOMY / STANDARD /
  DEEP-REASONING, doctrine in `registry/`) to Claude Code model aliases. Re-validated
  against the installed CLI each release. Other harnesses use the classes as effort
  guidance and have no alias map.
- **`../../.claude-plugin/plugin.json`** — MUST stay at the repo root (the Claude Code
  plugin marketplace requires it there). It is logically part of this adapter. Its
  `"skills": "./runtime/skills/"` path couples the marketplace to the `runtime/skills/`
  location — do not rename that directory.

## Constitution behavior on Claude Code

The installer emits `AGENTS.md` (the real constitution, with the Counsel rules block
between sentinel comments) plus a ~4-line `CLAUDE.md` shim whose first line is
`@AGENTS.md`. Always-on rules are NOT duplicated into `.claude/rules/` — that directory
is reserved for future path-scoped rules only (a Claude/Cursor feature). Doctor checks:
shim present, sentinel block intact, AGENTS.md under 32 KiB.
