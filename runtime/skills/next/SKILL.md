---
name: next
description: Pick up and activate the top READY ticket within the approved lane. Use on /counsel:next or "what's next / keep going".
user_invocable: true
---

# /counsel:next

Provenance: ORIGINAL (Apache-2.0).

1. Lease check: no other ACTIVE ticket; batch counter under the lease max (at max →
   deliver the concise batch progress review first, then wait for go-ahead).
2. Take the top READY ticket in the approved lane from WORKING-QUEUE.yaml; load its full
   ticket file (this is the ONLY full-detail load).
3. Run the work-control decision order + second-order preflight (in-context; no extra
   agent). EXECUTE only if the ticket's autonomy is `execute` and every condition holds;
   otherwise deliver the PROPOSE package or ASK-FIRST question and stop.
4. Refresh CAPSULE.md (≤~1k tokens) with this ticket as the active objective.
5. Execute at the ticket's cost class and staffing level → verify (verify skill) →
   checkpoint → update queue/ledger → status DONE → archive on close. On close, append
   ONE learning line to `.counsel/session/LEARNINGS.md` (what surprised us / what to do
   differently) — compounding memory, not ceremony.
6. Discovered work → BACKLOG candidates (id, source ticket, one-line note). Never execute
   discoveries. Scope drift beyond the ticket envelope → STOP, report, reassess.
