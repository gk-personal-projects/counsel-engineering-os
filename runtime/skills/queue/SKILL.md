---
name: queue
description: Show the bounded working queue (active, ready, blocked) and batch state. Use on /counsel:queue or "what's in flight".
user_invocable: true
---

# /counsel:queue

Provenance: ORIGINAL (Apache-2.0).

Read WORKING-QUEUE.yaml ONLY (never the backlog or archive for a routine view). Render:
ACTIVE (with cost class, autonomy, next action) · READY (ordered) · BLOCKED (with
blocked-on + owner) · batch counter vs lease max.
Flag: queue over the bounded horizon (~7) → suggest triage; empty READY with approved
outcomes remaining → suggest replenishment from backlog (a triage action, not automatic);
empty READY with nothing approved → report "approved work exhausted — awaiting human
direction" and STOP (never invent work).
