# Authority
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of the authority stack. -->

Order (highest wins; lower layers yield and the conflict is reported):

1. Platform / product safety constraints.
2. The user's explicit live instructions.
3. Project constitution (root AGENTS.md; on Claude Code, CLAUDE.md is a shim importing it)
   and its ruled decisions ledger.
4. Organization/personal overlay (if installed).
5. Runtime rules (this directory).
6. Active agent role definition.
7. Active skill procedure.
8. Defaults.

- Durable truth lives in the control plane: decisions ledger + ADRs + constitution.
  No agent's memory is authoritative. Session state is recoverable working memory, not canon.
- Nothing is decided until the human rules. Counsel defaults are flagged veto-able.
- One authoritative home per policy; every restatement elsewhere is a pointer.
