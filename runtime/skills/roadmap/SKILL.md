---
name: roadmap
description: View or update the human-owned roadmap (outcomes and NOW/NEXT/LATER lanes). Use on /counsel:roadmap or "show the roadmap".
user_invocable: true
---

# /counsel:roadmap

Provenance: ORIGINAL (Apache-2.0).

- **View:** render ROADMAP.md — outcomes with approval state, lanes, constraints. Compact.
- **Update:** the human owns outcomes and lane assignments. Counsel edits ROADMAP.md only
  as the user's scribe (their words, confirmed) — never reorders lanes, never adds
  outcomes on its own initiative. Counsel's lane-change suggestions exist only inside
  /counsel:triage output as proposals.
- Unapproved outcomes are visible but not decomposable — flag them as awaiting approval.
