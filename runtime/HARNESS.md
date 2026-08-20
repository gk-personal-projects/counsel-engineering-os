# Harness conventions — one portable core, thin adapters
<!-- Provenance: ORIGINAL (Apache-2.0). Authoritative home of harness-portability vocabulary.
     The runtime (skills, rules, agents) is written harness-neutral; anything
     harness-specific lives in adapters/<harness>/. -->

The Counsel runtime targets any agent harness that can read markdown instruction files
and Agent Skills (`SKILL.md` folders): **Claude Code** (first-class), **Cursor**, and
**OpenAI Codex CLI** (specified adapters). All durable state is plain in-repo files —
the only store every harness can read, diff, and git-version.

## Portable vocabulary (how to interpret runtime text on your harness)

| Runtime phrase | Claude Code | Cursor / Codex |
|---|---|---|
| "ask the user" | AskUserQuestion or plain question | plain question in chat |
| "delegated explorer / subagent where supported" | spawn a subagent with the stated output contract | do the read yourself, in a bounded pass, honoring the same output contract; never flood main context |
| "agent" files (`runtime/agents/`) | may run as real subagents with their own context | **role cards**: adopt the role's mandate and constraints in-context; parallelism is lost, discipline is not |
| model classes (ECONOMY / STANDARD / DEEP-REASONING) | mapped to model aliases via `adapters/claude/model-map.json` | semantic effort guidance for the session model |
| "context compaction / nearing limits" | /compact, PreCompact hook | any context-pressure moment — checkpoint manually first |
| hooks (SessionStart / PreCompact) | optional hook pack in `adapters/claude/hooks/` | not available — use the degraded-mode protocol below |

Agent files carry Claude-specific frontmatter (`model:`, `tools:`). On other harnesses
that YAML is inert metadata; treat the body as the role card.

## Continuity degraded mode (harnesses without lifecycle hooks)

1. **Boot:** before any work, read `.counsel/session/RESTORE.md` and `CAPSULE.md`.
   If they conflict with live git state, STOP and run the restore procedure
   (`runtime/skills/restore/`) — never guess.
2. **Checkpoint discipline is manual and mandatory:** at ticket close, before ending or
   abandoning a session, and whenever context feels near its limit (the manual
   substitute for PreCompact).
3. Staleness is detected outside the model: `scripts/session/session-doctor` flags a
   RESTORE older than recent commits; a stale RESTORE is drift, not truth.

The `.ps1`/`.sh` script pairs under `scripts/session/` run on any harness with a shell;
checkpoint/restore are fully functional without hooks (registry: session-continuity-hooks
is Claude-only, fallback manual).

## Capability degradation summary

| Capability | Claude Code | Cursor | Codex CLI |
|---|---|---|---|
| Constitution | AGENTS.md via CLAUDE.md shim (`@AGENTS.md`) | AGENTS.md native (+ generated `.cursor/rules/counsel-*.mdc`) | AGENTS.md native (< 32 KiB — doctor checks) |
| Skills | `.claude/skills/` (plugin) | Agent Skills standard | `.codex/skills/` |
| Subagents | native | role cards in-context | role cards in-context |
| Hooks | optional pack | none — degraded mode | none — degraded mode |
| Per-task model routing | model-map | session model + effort guidance | session model + effort guidance |

One authoritative home per policy: this file owns the vocabulary; adapters own their
harness's mechanics; skills and rules cite, never restate.
