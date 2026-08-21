---
name: onboard
description: First-run setup wizard. Use on /counsel:onboard, on first contact with an un-onboarded project, or when the user asks to set up Counsel.
user_invocable: true
---

# /counsel:onboard

Provenance: ORIGINAL (Apache-2.0). Goal: GitHub → READY without the user knowing
agent/skill/hook internals. Never ask "which agents do you want?" — ask what they're doing.

1. **Ask the goal:** understand an existing project / learn development / fix bugs /
   build features / disciplined engineering workflow / architecture-security review /
   production prep / install everything / not sure — recommend for me.
2. **Inspect the repo** (ECONOMY-class delegated explorer if large — subagent where the
   harness supports one, else inspect directly): stack, size, tests, existing
   CLAUDE.md / .claude/ / Cursor config, git state. NEVER blind-overwrite existing
   config — diff and merge with consent.
3. **Recommend the smallest useful layer** for the goal (registry `recommended_for`).
   Show the card: WHY this helps / WHAT it adds / WHAT it costs (context+complexity) /
   WHAT it requires / WHAT works without it / RECOMMENDED yes-no.
4. **Ask mode:** Learn / Pair (default) / Autopilot / CTO.
   If the strategist capability is selected, ask ONE memory question in plain language:
   "Should this project remember things just for itself, or also read/write a shared
   company-wide memory? If you have one, where is it — or should I create it?" Project
   memory needs zero config; a shared store is written into `.counsel/config.yaml`
   (`memory: { shared_dir: <path> }`) by this wizard — the user never edits YAML.
5. **On approval, instantiate via the deterministic installer** (never hand-copy):
   a. Compose the constitution from `scaffold/templates/CLAUDE.md.template` (facts from
      detection, not invention) into a temp file.
   b. Run the platform installer (source auto-resolves to the installed plugin):
      - Windows: `scripts/install/install-plan.ps1 -Target <project> -Layers <ruled layers>
        -ClaudeMdContentPath <temp> -Mode <mode>`
      - POSIX: `bash scripts/install/install-plan.sh -Target <project> -Layers <ruled layers>
        -ClaudeMdContentPath <temp> -Mode <mode>`
      Read PLAN.json.
   c. Present the plan: CREATE items as a summary; every MERGE/CONFLICT individually.
      **Permission changes (`.claude/settings.json`) are ALWAYS a separate explicit
      consent — show the exact diff; never bundle it into blanket approval.** CONFLICT
      items are never applied — offer resolution, then re-plan.
   d. Record the user's ruling per item into PLAN.json (`approved: true/false`), then apply:
      - Windows: `scripts/install/install-apply.ps1 -PlanPath <PLAN.json>`
      - POSIX: `bash scripts/install/install-apply.sh -PlanPath <PLAN.json>`
      Apply is atomic,
      backs up replaced originals to `.counsel/originals/`, writes the ownership
      manifest (`.counsel/manifest.json`), post-verifies hashes, and refuses stale
      plans (re-plan on drift). Rerun is idempotent.
   Consequential installs (system software, plugins) are separate explicit consents —
   never bundled.
6. **Run /counsel:doctor.** Report READY, or actionable findings with remediation cards.
7. Offer next steps sized to the goal (e.g. "want me to grok the codebase?").

Full-install path: show everything it will add + external deps + projected context impact
first; still doctor-verified at the end.
