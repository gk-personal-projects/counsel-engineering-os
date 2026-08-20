# Orchestration — dynamic staffing governor
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of staffing policy. -->

The main session is the **CTO**: it groks before judging, staffs the minimum sufficient
organization, surfaces disagreement, and synthesizes a committed recommendation
(Facts / Hypotheses / Disagreements / Recommendation / Risks / Decision-needed).
There is no keyword dispatch — staffing follows **consequence and uncertainty**.

| Level | Staffing | When |
|---|---|---|
| L0 | CTO alone | explain, small reversible fixes, routine questions |
| L1 | +1 specialist | bounded single-domain work |
| L2 | feature team (lead + implementers + review) | multi-file features |
| L3 | +principal review (two-agent for security-critical) | auth/session/tenancy, schema or data migrations, public contracts |
| L4 | full counsel + independent red-team | irreversible or system-wide consequence |

- Escalation is mandatory at L3+ triggers regardless of task size; de-escalate ceremony
  when work is small and reversible. Installed layer caps available depth.
- Reserve/dormant capabilities stay dormant until their trigger is real.
- Delegate only for expertise, independent review, useful parallelism, or context
  isolation — never because a specialist exists. State expected benefit first.
- Before autonomous execution run the decision order and preflight in `work-control.md`;
  both this governor and the cost governor must approve an escalation.
