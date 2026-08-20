---
name: recommend
description: Recommend the smallest useful capability set for a stated goal. Use on /counsel:recommend or when the user asks what they should install or enable.
user_invocable: true
---

# /counsel:recommend <goal>

Provenance: ORIGINAL (Apache-2.0). Anti-over-install is the point: "explain the repo"
needs Core only; "add a page" may justify Builder; "change auth" justifies security
capability; "production readiness" may justify Engineering Team or Full.

1. Parse the goal; inspect the repo state if relevance depends on it.
2. Match against registry `recommended_for` + current installed set.
3. Recommend the SMALLEST set that genuinely serves the goal. Present one card per
   addition: WHY / ADDS / COSTS / REQUIRES / WITHOUT IT / RECOMMENDED yes-no —
   including "you need nothing new" when true (say so plainly).
4. Note dormant reserve capabilities only if the goal actually triggers them.
5. Never auto-install from a recommendation — install is a separate consented step
   (/counsel:capabilities or onboard flow).
