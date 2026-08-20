---
name: feedback
description: Read production telemetry and user feedback, turn signals into evidence-backed BACKLOG candidates. Use after real traffic exists, on a cadence, or on "what are users telling us".
user_invocable: true
---

# /counsel:feedback

Provenance: ORIGINAL (Apache-2.0). Ship-loop capability. Reading is EXECUTE (read-only);
what it produces is never self-authorizing.

1. Pull the signals (read-only): PostHog insights/funnels (drop-off points, event
   volumes), survey/widget responses, Sentry issues (new, regressed, high-frequency),
   platform analytics (traffic, top paths).
2. Interpret against the ticket hypotheses on record — what did we predict, what does
   the data say? Numbers over adjectives; cite the query/insight and the date range.
3. Output: **BACKLOG candidates only**, each with `source: telemetry` and an evidence
   pointer (insight query, event counts, Sentry issue id, response quote). Verbatim
   work-control: **DISCOVERED WORK ≠ APPROVED WORK.** This skill never promotes to
   READY, never re-lanes, never starts work — `/counsel:triage` does, with the human's
   ruling.
4. Where the signal suggests an experiment, note it as a candidate for the experiment
   skill — starting one is ASK-FIRST there; do not pre-commit here.
5. Close with a compact signal table: metric | expected | observed | candidate raised.
