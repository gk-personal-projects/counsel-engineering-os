---
scope: project            # project | shared — every store declares which tier it is
# For shared stores add:  owner: shared across all projects of {{USER_OR_ORG}}
---
# Memory index — {{PROJECT_OR_ORG_NAME}}

Read protocol: read this index first, then ONLY the area files relevant to the task.
Never bulk-load the store. Writes follow `CONVENTIONS.md` §5 (append-at-anchor; never
blind-Write an existing file).

| File | Description | Last updated |
|---|---|---|
| `decisions.md` | Ruled decisions ledger (append-only) | {{DATE}} |
| `open-questions.md` | Unresolved items ledger | {{DATE}} |
<!-- ANCHOR:index -->

Last rebuilt: {{DATE}} (rebuilds are read-validate-promote only — CONVENTIONS §5.6)
