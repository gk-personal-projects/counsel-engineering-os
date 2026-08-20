---
name: ship
description: Deploy the project to its real stack (default Vercel) with an external verification gate. Use when a ticket requires a preview or production deployment, or on "ship it / deploy".
user_invocable: true
---

# /counsel:ship

Provenance: ORIGINAL (Apache-2.0). Ship-loop capability. Autonomy comes from
work-control — this skill cites it, never widens it.

1. Confirm the deploy is required by the active ticket (work-control decision order).
2. **Preview deploy** (e.g. `vercel` preview): inside EXECUTE — reversible, non-prod.
3. **Production deploy, domain purchase/DNS, production env-var changes: ASK-FIRST.**
   These are on work-control's barred list (production actions, paid resources, DNS);
   present what will change, the rollback path, and wait for the word.
4. Every deploy closes with the **external gate** — never self-report:
   - Windows: `scripts/ship/verify-deploy.ps1 -Url <deployment-url> -Sentinel <expected-content>`
   - POSIX: `scripts/ship/verify-deploy.sh <url> <sentinel>`
   Exit 0 (HTTP 200 + sentinel found) is the only evidence of a live deploy. Exit ≠ 0 →
   the deploy is NOT verified; report faithfully, investigate, never claim success.
5. Record: deployment URL + verify output in the ticket verification block; checkpoint.
6. First production deploy of a project: instrument BEFORE announcing (instrument skill)
   — "shipped" without telemetry is unmeasurable (feedback skill needs the data).
