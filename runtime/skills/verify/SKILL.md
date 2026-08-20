---
name: verify
description: Verification before any completion claim. Use before saying done, fixed, passing, or closing a ticket.
---

# Verification before completion

Provenance: PRINCIPLE-EXPRESSION (Apache-2.0).

No completion claim without evidence produced THIS session:

1. Re-read the ticket's acceptance criteria and verification method.
2. Run the verification (tests, build, typecheck, the actual command, the actual flow).
   Capture the output.
3. Compare expected vs actual scope touched (work-control preflight epilogue) — report
   drift instead of absorbing it.
4. Report faithfully: failures are reported as failures with output; partial completion
   is reported as partial; skipped steps are named. "Should work" is HYPOTHESIS, not done.
5. Ticket close = verified + checkpointed + ledger updated. DONE without recorded
   verification is prohibited (autonomy governance: never mark human-priority work done
   without verification).
