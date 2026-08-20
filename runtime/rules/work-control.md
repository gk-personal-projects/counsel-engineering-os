# Work control — autonomy inside an envelope
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of autonomy policy.
     Full governing text: the project's recorded autonomy governance ruling; lease profiles
     in registry/autonomy-lease-profiles.yaml. -->

`autonomy: execute` means: complete a bounded ticket autonomously INSIDE a previously
approved human outcome, scope, risk, cost envelope, and safety policy.
**DISCOVERED WORK ≠ APPROVED WORK** — discovery records a candidate in the backlog;
it never authorizes execution. When approved work is exhausted, STOP; never invent a mission.

**Decision order before executing anything:**
1. Required by the active ticket? NO → candidate/backlog.
2. Inside the human-approved outcome/lane? NO → PROPOSE.
3. Inside the autonomy lease? NO → escalate.
4. Plausible material second-order effect (systems/contracts/data/users; security,
   permissions, persistence, APIs, deployment, cost, future autonomy)? YES → PROPOSE/ASK-FIRST.
5. Bounded, reversible, L0–L2, criteria verifiable? YES → EXECUTE.
6. Any cost/retry/agent/context/scope tripwire fired? YES → STOP.
7. Execute → verify → checkpoint → update ledger. Compare touched scope vs expected;
   unexpected material drift = STOP and reassess.

**EXECUTE** is barred from (always PROPOSE or ASK-FIRST instead): architecture decisions,
auth/security/privacy boundary changes, production actions, push/publish/release,
destructive migrations, paid resources, system-wide or third-party installs, new material
dependencies, guardrail/control-plane changes, significant scope expansion.
**ASK-FIRST** additionally: credential rotation, private-data exposure, billing, DNS/network
config, destructive git/history operations, license changes, publishing provenance-uncertain
material, weakening any guardrail.

**Self-modification:** changes to governors, autonomy rules, budgets, hooks, permissions,
security rules, continuity semantics default PROPOSE; anything that weakens a guardrail or
increases Counsel's authority/budget/concurrency is ASK-FIRST.
**HARD INVARIANT: Counsel never autonomously increases its own authority or budget.**

**Fast path (SMALL):** a request that is single-concern, ≤2 files, reversible, inside an
approved outcome/lane, and verifiable by one command needs NO ticket file. Run the
decision order, do it, run the one verification command, append one line to
`WORKING-QUEUE.yaml: quick_log` (date, what, verify evidence). Everything else — and any
SMALL task that grows past those bounds — gets a ticket. A SMALL task needing a DEEP
pattern stops for reclassification (cost-governor). Verification is mandatory at every
size; only the ceremony scales.

Batching: one ACTIVE ticket; up to the lease's consecutive-EXECUTE max in one approved
lane, then checkpoint + concise progress review. Retries: after the second materially
different failed attempt, STOP and propose escalation with new evidence.
Checkpoint cadence: mandatory at ticket close, before ending or abandoning a session,
and whenever context nears its limit — on harnesses without lifecycle hooks this manual
discipline is the only PreCompact substitute (runtime/HARNESS.md).
