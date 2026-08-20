---
name: code-review
description: Counsel-native code review with anti-rubber-stamping discipline. Use before merging, after implementing features, or on request.
---

# Code review (Counsel-native)

Provenance: PRINCIPLE-EXPRESSION (Apache-2.0); anti-self-approval and review-scale ideas
acknowledge upstream Agent Scaffold governance (see NOTICE).

1. **Scope the diff.** Review the change against its ticket's acceptance criteria and
   expected touched scope — scope drift is itself a finding.
2. **No self-approval.** The implementer never certifies their own work; at L3+ the
   reviewer is a separate agent (two independent reviewers for security-critical).
3. **Review for:** correctness (trace the failure modes, not just the happy path),
   contract/compatibility breaks, security (input trust, authz, secrets), data integrity,
   test adequacy (do tests verify behavior or mirror implementation?), convention fit.
4. **Every finding carries:** severity (S0–S3), evidence `file:line`, concrete failure
   scenario, cheapest viable fix. No vague "consider improving".
5. **Zero findings + approve is suspect.** State explicitly what was checked and found
   clean.
6. **Review resolution:** findings → triage (human rules on contested ones) → apply →
   spot-check the applied fixes. A concern is not a rewrite reflex — preserve shipped
   truth unless change is ruled.
7. Oversized changes (roughly >800 changed lines) get split before meaningful review is
   claimed.
