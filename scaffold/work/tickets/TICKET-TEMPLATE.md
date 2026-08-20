---
id: T-{{NNNN}}
title: {{TITLE}}
outcome: O-{{NNN}}            # human-approved roadmap outcome this serves
lane: NOW|NEXT|LATER
status: BACKLOG|READY|ACTIVE|BLOCKED|VERIFY|DONE|CANCELLED
priority_in_lane: {{N}}
depends_on: []
risk_staffing: L0|L1|L2|L3|L4
cost_class: SMALL|STANDARD|DEEP
autonomy: execute|propose|ask-first   # execute only if ALL D-T2-020 SS2 conditions hold
created: {{DATE}}
updated: {{DATE}}
---

## Acceptance criteria
- {{VERIFIABLE_CRITERION}}

## Autonomy envelope
Expected touched scope: {{FILES/AREAS}}. Anything materially beyond this = scope drift → STOP.

## Decisions / evidence (pointers only)
- {{D-IDS, file:line}}

## Verification (how DONE is proven)
{{COMMANDS/CHECKS — verification runs before close; never assert unperformed verification}}

## Definition of done
{{INCLUDES: verified, checkpointed, ledger updated}}

## Exact next action
{{NEXT}}

## Preflight (D-T2-020 SS4 — answer before executing)
required-by-ticket? in-approved-outcome? in-lease? reversible? second-order effects?
alters security/permissions/persistence/APIs/deploy/cost/autonomy? scope expanded?
