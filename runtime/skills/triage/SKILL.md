---
name: triage
description: Groom the work system - decompose approved outcomes, triage discovered candidates, replenish the queue, propose lane changes. Use on /counsel:triage or periodically between batches.
user_invocable: true
---

# /counsel:triage

Provenance: ORIGINAL (Apache-2.0). The ONLY procedure that reads BACKLOG.yaml and ROADMAP.md
together (routine execution never does).

1. **Decompose:** approved outcomes without tickets → draft tickets (full schema, honest
   autonomy values per the execute-conditions) into the backlog.
2. **Candidates:** for each discovered-work candidate: propose promote (only direct
   technical prerequisites inside an approved outcome qualify for READY), keep, or drop.
   The human rules on promotions outside that narrow class. Candidates with
   `source: telemetry` (feedback skill) carry evidence pointers — weigh the numbers,
   not the narrative; a candidate without evidence is a hunch, triaged as such.
2b. **Learnings:** if `.counsel/session/LEARNINGS.md` exceeds ~100 lines, distill it —
   propose promoting repeated lessons to a rule or the constitution (the human rules),
   archive the rest.
3. **Replenish:** top up the READY horizon (small, bounded) from decomposed backlog,
   ordered by dependency + priority-in-lane.
4. **Groom:** stale BLOCKED items surfaced with owners; DONE verified before archive;
   reopened-DONE flagged (autonomy health signal).
5. **Propose lane changes** where evidence justifies — as proposals with rationale; the
   human rules. Counsel never re-lanes on its own.
6. Output: compact triage table + the specific decisions needed from the human (only
   those — no ceremony).
