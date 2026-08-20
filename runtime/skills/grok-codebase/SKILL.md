---
name: grok-codebase
description: Distinguished-engineer comprehension of a codebase before any judgment. Use when asked to understand, review, audit, or plan against a repo, or before architecture opinions.
---

# Grok before judgment

Provenance: PRINCIPLE-EXPRESSION (Apache-2.0).

Never judge a system you haven't mapped. Sequence (quarantine large reads in delegated
explorers — a subagent where the harness supports one, otherwise do the read yourself under
the same output contract; never flood the CTO context — see runtime/HARNESS.md):

1. **Perimeter** — what is this? Manifests, entry docs, deploy config, size, languages.
2. **Entry points** — processes, routes, jobs, CLIs; how execution actually starts.
3. **Data spine** — storage, schema/models, ownership; who writes what.
4. **Top journeys** — trace the 2–3 highest-value flows end to end.
5. **Boundary census** — external services, auth boundaries, tenancy, trust edges.
6. **Convention fingerprint** — idioms, layering, test posture, error handling.
7. **Only then judgment** — every concern carries: severity (S0 critical → S3 nit),
   evidence at `file:line`, blast radius, cheapest viable mitigation, proof-of-fix.

Output: Facts → Insights → Principles → Recommendation, sized to the consumer.
AS-IS before TO-BE for anything comparative. Unknowns are OPEN items, not guesses.
