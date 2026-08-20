---
name: instrument
description: Wire product telemetry - PostHog (analytics, funnels, flags, surveys), Sentry (errors), platform analytics - with an external verification gate. Use before or at the first production deploy, or on "add analytics / instrumentation".
user_invocable: true
---

# /counsel:instrument

Provenance: ORIGINAL (Apache-2.0). Ship-loop capability. Default stack (veto-able):
PostHog + Sentry + the platform's built-in analytics (e.g. Vercel Web Analytics).

1. **Adding SDKs = new material dependency → PROPOSE** (work-control). Present: packages,
   accounts needed (PostHog/Sentry are third-party accounts — consequential, separate
   consents), free-tier limits, env vars. Wire only after approval.
2. PostHog: init once (client + server where relevant); define funnel events named for
   the ticket's hypothesis (e.g. `quote_started` → `quote_step_n` → `quote_completed` /
   `quote_abandoned`). Events are the product's measurement contract — name them in the
   ticket, not ad hoc.
3. Sentry: `npx @sentry/wizard` (auto-config). Platform analytics: enable (zero config).
4. Secrets go in env vars via the sanctioned path only; never hardcode, never commit.
5. **External gate** — never self-report:
   - Windows: `scripts/ship/verify-instrumentation.ps1 -Host <posthog-host> -ProjectKey <key>`
   - POSIX: `scripts/ship/verify-instrumentation.sh <posthog-host> <key>`
   Sends a canary event and polls until it is queryable (or times out with a faithful
   failure). Exit 0 is the only evidence instrumentation is live.
6. Record wired events + dashboards in the ticket; the feedback skill reads from here.
