# Validation test — SMB professional-services starter app

Provenance: ORIGINAL (Apache-2.0). Status: **SPEC ONLY** — a follow-on effort executes
it. Purpose: prove, measurably, that building with the OS beats raw vibe-coding, using
the full 0.1.5 surface (deep-analysis, memory, fast path, ship loop, continuity).

## Persona & hypothesis

Solo or two-person **professional-services business** (inspections, surveying,
consulting) running quotes and scheduling through email/phone today. Hypothesis: a
cheap, fast "starter app" — services catalog + quote request + scheduling request +
real-time admin — converts their manual customer flow to a web presence that can grow
with the business.

## Thin slice to build

1. Public **services catalog** with option/tier selection.
2. **Multi-step quote-request flow** (service → options → details → submit) — the funnel
   is the instrumentation showcase; every step emits a named event.
3. **Scheduling request** — customer proposes time windows. No calendar-sync scope creep.
4. **Admin dashboard** — real-time incoming-request queue (Supabase Realtime), status
   changes, canned replies.
5. Email notification on new request.

Stack: Next.js (App Router) on Vercel + Supabase (Postgres/Auth/Realtime) + PostHog
(funnel events `quote_started` / `quote_step_n` / `quote_completed` / `quote_abandoned`)
+ Sentry + Vercel Web Analytics — exactly the ship-loop default stack.

## What the OS must demonstrably do better than raw vibe-coding

Ticketed decomposition with external verification at every close · instrumented from
the FIRST production deploy, not bolted on · telemetry → BACKLOG candidates within one
session of data existing · an A/B on the quote form PROPOSED and held at the human
gate · full mid-build session-kill recovery.

## Success criteria (measured, not felt)

| # | Criterion | Evidence |
|---|---|---|
| 1 | Hypothesis → live production URL with a working end-to-end quote flow in ≤ 3 working sessions; human time spent only on rulings/consents | Session log + a running human-minutes tally |
| 2 | Zero unverified DONE: 100% of closed tickets carry captured verification output; every deploy proven by `verify-deploy` exit 0 | Ticket verification blocks; script output |
| 3 | Instrumentation live at first prod deploy: PostHog funnel shows real events and Sentry shows the release within 24h of deploy #1 | Dashboards; `verify-instrumentation` exit 0 |
| 4 | Feedback loop closed once: ≥3 telemetry-sourced BACKLOG candidates with evidence pointers; ≥1 approved via triage and shipped as a follow-up ticket; the A/B proposal exists and was NOT started without explicit approval | BACKLOG.yaml; DECISIONS.md |
| 5 | Ceremony proportional + recovery proven: ≥5 SMALL changes via the fast path (quick_log, no ticket files); one deliberate mid-ticket session kill recovered via restore with zero re-derivation questions to the human | WORKING-QUEUE quick_log; restore transcript |

Failure on any criterion is reported as failure, with the gap named — the point of the
test is to find where the OS is weak, not to declare victory.
