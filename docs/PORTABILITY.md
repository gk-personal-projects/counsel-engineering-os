# Portability — one logic layer, three harnesses

Provenance: ORIGINAL (Apache-2.0). Companion: `runtime/HARNESS.md` (the vocabulary
contract skills/rules are written against), `adapters/*/README.md` (per-harness
mechanics + validation checklists).

## Design (0.1.5)

The 2026 cross-tool consensus the design follows: **AGENTS.md** as the canonical
instruction file (native in Codex/Cursor/Copilot/Gemini; Claude Code via a `@AGENTS.md`
shim in CLAUDE.md), **Agent Skills** (`SKILL.md` folders) as the portable procedure
format, **plain in-repo files** as the only harness-portable state, and harness-native
features as thin adapters only.

| Layer | Where | Portability |
|---|---|---|
| Constitution | `AGENTS.md` (+ CLAUDE.md shim on Claude) | Native on all three; < 32 KiB for Codex |
| Always-on rules | Sentinel region inside AGENTS.md, installer-managed | All three |
| On-demand rules | `.counsel/rules/*.md` | All three (read on demand) |
| Skills | Claude plugin / `.cursor/skills/` / `.codex/skills/` | Agent Skills standard |
| Agents | `.claude/agents/` (real subagents) / `.counsel/agents/` (role cards) | Discipline portable; parallelism Claude-only |
| State | `.counsel/` (config, manifest, session, work, memory) | Identical everywhere |
| Hooks | `adapters/claude/hooks/` | Claude-only; degraded mode elsewhere |
| Model routing | `adapters/claude/model-map.json` | Claude-only; classes = effort guidance elsewhere |

## Install per harness

`scripts/install/install-plan.ps1` (Windows) or `bash scripts/install/install-plan.sh`
(POSIX — same flags) `-Target <proj> -Harness claude|cursor|codex` →
review PLAN.json → `install-apply.ps1` / `install-apply.sh`. The ownership manifest,
repair, uninstall, and doctor work identically on every harness (they are path-driven,
not harness-driven) — and now on every platform: the `.sh` ports provide POSIX parity
with the same contracts and exit codes.
`.counsel/config.yaml` records `harness:` + `runtime_version` so doctor's version-skew
check is harness-agnostic.

## Status

- **Claude Code — first-class, tested** (install/lifecycle/continuity suites).
- **Cursor, Codex — specified, emission implemented and covered by install tests
  (T9), NOT yet validated in live sessions.** Run the adapter README checklists before
  telling anyone these are supported.

## Migration from pre-0.1.5 installs

Re-running plan/apply on a legacy install stages AGENTS.md (CREATE), turns CLAUDE.md
into a MERGE (fat constitution → shim; the fat content should be carried into AGENTS.md
via -ClaudeMdContentPath), and proposes approval-gated REMOVE items for the orphaned
`.claude/rules/` copies (covered by install test T8). Nothing is removed or replaced
without per-item approval.
