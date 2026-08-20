# Start here

Provenance: ORIGINAL (Apache-2.0).

**Just want it working?** **`docs/QUICKSTART.md`** → `/counsel:onboard` → `/counsel:doctor` → build.

## Documentation by depth (read only as far as you need)

1. **Get working** — docs/QUICKSTART.md (install with a check at every step, then the modes,
   the command map, and the working loop), README.md, `/counsel:doctor` output.
2. **Use Counsel** — talk to the CTO in plain language; `/counsel:capabilities`,
   `/counsel:recommend`, `/counsel:next`, `/counsel:queue`. docs/FIRST-RUN-UX.md is the
   *design specification* for the onboarding flow — read it to review the design, not to learn
   the tool.
3. **Understand** — docs/ARCHITECTURE.md (layers, staffing, memory/authority model),
   docs/CONTINUITY.md (checkpoints and recovery).
4. **Extend** — runtime/ (agents, skills, rules, hook pack), registry/ (capabilities,
   dependencies, autonomy-lease profiles).
5. **Provenance/legal** — LICENSE, NOTICE, PROVENANCE.md.

## The 60-second mental model

Your project gets a **constitution** (CLAUDE.md) + a small set of always-on **rules**.
The main session is your **CTO**. Work above trivial size becomes **tickets** in a bounded
queue under human-owned priorities. Specialists staff in only when consequence justifies
them. Everything durable (decisions, session state, checkpoints) lives on disk in
`.counsel/` — sessions are disposable, your state is not. Autonomy is real but leased:
Counsel executes bounded low-risk work and stops at everything consequential.
