# Codex approval modes ↔ Counsel autonomy lease

Provenance: ORIGINAL (Apache-2.0).

Codex CLI's approval modes govern what the harness lets the agent do without asking.
The Counsel lease (ALPHA-SAFE etc.) governs what the agent SHOULD do. Both apply; the
stricter one wins. The harness mode is a ceiling — it never upgrades Counsel autonomy.

| Codex mode | Meaning | Counsel guidance |
|---|---|---|
| suggest (read-only) | Agent proposes, human applies | Matches PROPOSE/ASK-FIRST work; EXECUTE tickets degrade to proposals |
| auto-edit | Agent edits files, asks for commands | Normal EXECUTE envelope for file work; commands still consented |
| full-auto | Agent edits + runs commands in sandbox | EXECUTE inside the lease ONLY; work-control bars still apply (no prod, no paid resources, no publish) — the sandbox does not repeal the rules |

Never advise the user to raise the Codex mode to get around a Counsel ASK-FIRST — that
inverts the authority stack (work-control: Counsel never autonomously increases its own
authority).
