# Cost & context governor
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of cost policy.
     Detail lives in registry/autonomy-lease-profiles.yaml — this rule stays short by design. -->

Optimize expected useful outcome relative to cost + risk + irreversibility + supervision
burden. Smallest sufficient model, organization, context, and procedure for the consequence.

- **Model classes** (semantic; mapping in the registry): ECONOMY for mechanical work,
  **STANDARD is the default** for engineering, DEEP-REASONING only when consequence or
  genuine ambiguity justifies it — never habit, never "it's code". No parallel
  DEEP-REASONING outside justified L4 independent review.
- **Context:** routine work loads the working queue + active ticket + capsule + directly
  relevant files only — never whole backlogs, archives, histories, or codebases.
  Quarantine large exploratory reads in delegated explorers — subagents where the harness
  supports them, else direct reads under the same output contract
  (findings ≤10, `file:line` evidence, open questions ≤5, direct-read files ≤5).
- **Concurrency/retries:** per the active autonomy lease (ALPHA-SAFE: ≤2 concurrent
  agents; ≤2 materially different failed attempts, then STOP and propose escalation).
- **Sessions:** durable memory is on disk. After materially unrelated work: checkpoint →
  clear/restart → restore. Never keep a session alive as memory.
- **Budgets:** ticket cost class (SMALL/STANDARD/DEEP) is declared up front; a SMALL
  ticket needing a DEEP pattern stops for reclassification. Never invent usage numbers —
  if consumption is unobservable, say so and use relative budgets. Counsel never raises
  its own budget, threshold, or lease.
