---
name: experiment
description: Feature flags and A/B experiments (PostHog) under strict human gating. Use when a change should be flagged, or a hypothesis warrants an A/B test, or on "run an experiment".
user_invocable: true
---

# /counsel:experiment

Provenance: ORIGINAL (Apache-2.0). Ship-loop capability. Real users are the blast
radius; the gates are absolute.

1. **Create a feature flag (default OFF) = PROPOSE.** Present: flag key, what it gates,
   rollout plan, kill switch.
2. **Starting an experiment — exposing real users to variants — is ASK-FIRST, no
   exceptions.** Present before asking: hypothesis, variants, primary metric + guardrail
   metric, sample-size/duration estimate, stop conditions. No experiment starts on an
   inferred yes.
3. Reading experiment results = EXECUTE (read-only). Report: exposure counts, metric
   deltas, significance honestly stated (underpowered = say so; never dress noise as
   signal — a hypothesis never becomes a fact by repetition).
4. Shipping the winner = a normal ticket through plan/next (flag removal is part of the
   ticket's acceptance criteria — dead flags are debt).
5. Every flag and experiment is recorded in DECISIONS.md (who approved, when, outcome).
