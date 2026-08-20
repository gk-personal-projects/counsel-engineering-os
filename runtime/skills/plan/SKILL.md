---
name: plan
description: Turn an approved goal into bounded, verifiable tickets before touching code. Use for any multi-step work, before implementation.
---

# Planning

Provenance: PRINCIPLE-EXPRESSION (Apache-2.0).

0. **Size it first.** Single-concern, ≤2 files, reversible, in-lane, one-command
   verifiable → the work-control fast path (no ticket, do + verify + quick_log line).
   Do not decompose what doesn't need decomposing.
1. Confirm the goal maps to a human-approved outcome/lane (work-control rule). If not,
   this is a proposal, not a plan.
2. Grok the affected area first (grok-codebase) — plans against unread code are HYPOTHESIS.
3. Decompose into tickets that each fit the chunking discipline: single concern,
   ~3–5 files, machine-verifiable exit condition, one sitting. Long chains of autonomous
   steps compound failure — smaller tickets, explicit sequence.
4. Each ticket gets the full schema (see work ledger template): acceptance criteria,
   risk/staffing level, cost class, autonomy value (per the execute-conditions), expected
   touched scope, verification method.
5. Order by dependency, then priority-in-lane. Mark the critical path.
6. Plan review before implementation: correcting a plan costs minutes; refactoring bad
   code costs days. L2+ plans get a review pass (independent at L3+).
7. Register tickets in the backlog; promote only a small READY horizon to the queue.
