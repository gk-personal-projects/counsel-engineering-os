# Research briefing — agent-OS landscape, portability, ship-loop stack (2026-08-17)

Provenance: research digest (web-sourced 2026-08-17); grounds the 0.1.5 portability +
ship-loop design. Claims below were source-verified at research time; re-verify before
citing externally.

## Comparable frameworks

| Framework | Distribution | State model | Portability | Reported weakness |
|---|---|---|---|---|
| GitHub Spec Kit | uvx/uv CLI; markdown command templates | per-feature constitution/spec/plan/tasks md | 20+ agents | Ceremony tax: reported ~9x slower than iterative prompting on small tasks; 3.5:1 spec-to-code line ratios |
| BMAD-Method | npx installer; `_bmad/` | PRD/architecture docs + story files + decision log | BYO model; Claude/Cursor/web | ~2-month learning curve; heavy token spend; "agents reviewing agents is the same optimism twice" (documented false-complete auth incident) |
| Agent OS (Builder Methods) | base + per-project install; `.agent-os/` | standards (index.yml-injected), product docs, specs | explicitly tool-agnostic; converts standards to Skills | standards-injection focus, no execution management; small community |
| Claude Task Master | MCP server (`task-master-ai`) | `.taskmaster/` tasks.json w/ dependencies + complexity | MCP → Cursor/Windsurf/VS Code/Claude | planning-layer only; needs a decent PRD |
| Amazon Kiro | standalone IDE | per-spec requirements(EARS)/design/tasks triad | none (IDE lock-in) | lock-in; specs only as good as their review |
| Conductor | Mac app; git worktrees per agent | worktrees + checkpoints | Claude Code + Codex | orchestration ≠ methodology; macOS only |
| Anthropic Agent Skills | SKILL.md folders; skills.sh / `npx skills add` | stateless capability packs | **de facto cross-tool standard** (Claude, Codex CLI, Cursor, Gemini, Copilot) | distribution primitive, not a workflow |

## Portability least-common-denominator (what all three harnesses execute)

1. **AGENTS.md at repo root** — native in Codex/Cursor (+Copilot/Gemini/Windsurf/Zed);
   Claude Code via `@AGENTS.md` first line in CLAUDE.md. Keep < 32 KiB (Codex truncates).
2. **SKILL.md folders** (Agent Skills standard) — `.claude` plugin / `.cursor/skills/` /
   `.codex/skills/` + `~/.codex/skills/`.
3. **State as plain in-repo files** — the only store every harness reads/diffs/versions;
   every surviving framework converged on it independently.
4. Harness-native sugar (Claude hooks/subagents, Cursor `.mdc` glob rules, Codex config)
   as thin adapters only.

## Ship/feedback default stack (solo builder, Vercel + Supabase)

- **PostHog** — analytics + funnels + flags + experiments + surveys + replay in one SDK;
  free tier ~1M events + 1M flag requests/mo; full API from free tier.
- **Sentry Developer** — 5K errors/mo, hard-stop limits (no surprise bills);
  `npx @sentry/wizard` auto-config.
- **Vercel Web Analytics** — comes with hosting, zero config, 50K events/mo Hobby.
- Skip GrowthBook until PostHog's stats engine is outgrown. Optional later: self-hosted
  feedback board (Quackback / FasterFixes).
- Deliberate duplication: PostHog errors = product signal, Sentry = debug depth.

## Evidence-backed design principles (drove 0.1.5 decisions)

1. Small, dependency-ordered, independently verifiable tickets.
2. **Verification gates OUTSIDE the model** — METR RCT: experienced devs were 19%
   SLOWER with AI while believing they were 20% faster; agent self-report is not
   evidence; telemetry and script exit codes are.
3. Progressive disclosure over context dumps (why SKILL.md beat monolithic prompts).
4. **Right-size ceremony to the task** — mandatory-heavyweight-always is the documented
   failure mode (Spec Kit's ~9x) → the fast path (work-control SMALL clause).
5. State in plain versioned files, not tool databases.
6. Compounding memory: capture learnings after every task (→ LEARNINGS.md).
7. Standards injected at the right moment beat standards always-loaded.
8. Fresh context per task (subagent/worktree isolation) against context rot.
9. Measure with production telemetry, not developer vibes (METR perception gap).
10. Portability via open standards (AGENTS.md + Agent Skills + MCP); native features as
    adapters only — the 2026 ecosystem consensus.

**Bottom line:** the winning 2026 shape is a thin file-based layer (AGENTS.md + skills +
in-repo tickets) with hard external verification gates and compounding memory, sized to
skip ceremony on small tasks, running identically on Claude Code / Cursor / Codex, and
closed-loop instrumented (PostHog + Sentry) so "shipped" is measured, not felt.
