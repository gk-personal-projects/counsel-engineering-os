# Reserve pool — dormant seats
<!-- Provenance: ORIGINAL (Apache-2.0). -->

These seats are NOT active: this directory is outside the agent discovery path, so
dormancy costs zero context. Activation (a control-plane change, per work-control rule):

1. A real trigger exists (see each seat's trigger) — never "might be useful".
2. Copy the seat file into the active agents directory; installer records it in the manifest.
3. Note the activation in the decisions ledger. Deactivation = reverse + note.

| Seat | Trigger |
|---|---|
| product-manager | multi-person team / formal product discovery begins |
| project-manager | external work-tracking coordination beyond the Counsel ledger |
| requirements-analyst | formal requirements elicitation with stakeholders |
| api-designer | public/partner-facing API surface is being designed |
| devops-engineer | CI/CD, containerization, or infra-as-code surface appears |
| sre-engineer | SLOs, alerting, or production operations ownership begins |
| technical-writer | docs beyond README/changelog become a deliverable |
