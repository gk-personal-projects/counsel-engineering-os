---
name: systematic-debugging
description: Counsel-native root-cause debugging. Use for any bug, test failure, or unexpected behavior BEFORE proposing fixes.
---

# Systematic debugging (Counsel-native)

Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Core is complete without any external
debugging plugin; if an enhanced external workflow is installed and functional, the
capability registry may offer it — this procedure always works.

1. **Reproduce first.** A bug you can't reproduce is a HYPOTHESIS; say so.
2. **Read the actual error.** Full message, full trace, the exact failing line.
3. **Locate the boundary.** Binary-search the failure: last known-good point vs first
   bad point (input → transform → output; commit range; layer by layer).
4. **Form ONE hypothesis** that explains all observed evidence — not the first plausible
   story. State what evidence would falsify it.
5. **Test the hypothesis minimally** (targeted probe, log, or unit test) before changing
   product code.
6. **Fix the root cause**, not the symptom. If you patch a symptom knowingly, label it a
   mitigation and open an item for the cause.
7. **Prove the fix:** failing case now passes, adjacent cases still pass, regression test
   added where the class of bug warrants it.
8. Two materially different failed fix attempts → STOP (retry breaker): report what
   failed, new evidence, why the next attempt differs; propose escalation.
