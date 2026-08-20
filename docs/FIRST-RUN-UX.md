# First-run UX — GitHub → READY

Provenance: ORIGINAL (Apache-2.0). T2.7 deliverable for Gate T2-G (HUMAN UX review).
Behavioral home: the onboard skill (`/counsel:onboard`); this document is the reviewable
specification. Install mechanics (plugin + consented control-plane instantiation, teammate
path, update/repair/uninstall): `docs/INSTALL.md`.

## Principles
Ask GOALS, never components. Recommend the smallest useful layer. Every addition shows its
card (WHY/ADDS/COSTS/REQUIRES/WITHOUT/RECOMMENDED). Never blind-overwrite existing config.
Consequential installs are separate consents. Doctor gates READY. Full is never default.

## First screen (README + first conversation)

```text
Welcome to Counsel.

Counsel is an AI CTO and engineering team for Claude Code that starts
small and grows with your project.

What are you trying to do?

  1. Understand an existing project
  2. Learn software development with Claude
  3. Fix bugs and make small changes
  4. Build features
  5. Run a disciplined engineering workflow
  6. Review architecture or security
  7. Prepare for production
  8. Install the complete system
  9. I'm not sure — recommend a setup
```

## Goal → recommendation mapping (defaults; repo inspection can adjust)

| Goal | Layer | Mode default |
|---|---|---|
| 1 Understand | Core | Pair |
| 2 Learn | Core | Learn |
| 3 Fix bugs | Core (Builder offered if repo is substantial) | Pair |
| 4 Build features | Builder | Pair |
| 5 Disciplined workflow | Builder (+work plane walkthrough) | Pair |
| 6 Architecture/security review | Engineering Team | Pair |
| 7 Production prep | Engineering Team (Full offered with card) | Pair |
| 8 Everything | Full — after full-scope preview + consents | Pair |
| 9 Not sure | 3 questions (project state? building or learning? alone or team?) → smallest fit | per answers |

## The five paths

**Beginner (goal 2):** plain-language everything; Learn mode; Core only; first mentor loop
starts immediately after READY.
**Help me choose (goal 9):** three questions max, then a single recommendation card.
**Existing project:** detect stack/tests/config; existing CLAUDE.md or .claude/ → show a
merge plan (diff, what's added, nothing overwritten) and require approval; Cursor config
detected → coexistence note (Counsel does not touch .cursor/).
**New project:** offer generic starter constitution; stack facts filled as they become real
(detection later re-verifies).
**Full install:** preview everything it adds + external deps + projected context impact +
which pieces need separate consent (system software, third-party plugins); then install;
then doctor.

## Example: existing-project run (goal 4)

```text
You: Build features

Counsel: Looked at your repo: TypeScript + Express + React, tests present,
no existing Claude config.

Recommended: BUILDER

  WHY      You want to ship features; Builder adds an implementation team.
  ADDS     Tech Lead + frontend/backend/test/debug specialists, code
           review, git workflow. (Core is always included: CTO, doctor,
           planning, session recovery.)
  COSTS    Moderate context when agents are active; nothing when idle.
  REQUIRES Git (found). Node (found).
  WITHOUT  Core alone can still plan and advise — it just won't staff
           implementation.

Install Builder? [yes / adjust / explain more]

You: yes

Counsel: Installed. Mode? [Learn / Pair (recommended) / Autopilot / CTO]

You: Pair

Counsel: Running doctor...
  ✓ Core · ✓ Builder · ✓ Git · ✓ Node · ✓ Session continuity
  ⚠ RECOMMENDED: no CI detected — fine for now, ask me about it anytime.
  ⚠ UNVERIFIED: 2 credentials unproven (gh, POSTHOG_PERSONAL_API_KEY)
                run /counsel:doctor --probe to prove them (read-only, free)

NOT READY — 2 credential checks unverified. Your tools are installed; whether
your keys still work is unproven, and I will not call that ready.

Want me to prove them now, grok the codebase first (recommended), or straight to
your first feature?
```

## Failure honesty
A BLOCKING doctor finding ends in an actionable card, never a dead end. Optional missing
tools appear as OPTIONAL/INFORMATIONAL — READY is still READY. But an UNPROVEN
credential is never READY: presence checks pass while the token is expired, and the
failure surfaces later, mid-work, as someone else's bug. Doctor moves it forward.

## Uninstall/update promise (stated at install)
Update preserves your decisions/ADRs/context; uninstall removes only Counsel-owned files
(manifest-tracked); your code is never touched.
