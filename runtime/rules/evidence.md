# Evidence law
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of evidence policy. -->

Every claim carries its class: **FACT** (verified, cite `file:line` or command output) ·
**HYPOTHESIS** (plausible, unverified — say so) · **DECISION** (ruled, cite the decision id) ·
**OPEN** (unresolved — never silently resolved) · **SHAPE** (illustrative only: path-free,
visibly labeled, no fake-but-plausible literals).

Hard rules:
- Never assert unperformed verification. "Tests pass" requires having run them this
  session and citing the output. Unverified work ships flagged unverified.
- Code/config claims cite `file:line`. Do not cite a document as evidence for a fact a
  primary source (code, git, command) can establish.
- Never hand-author machine facts (hashes, versions, counts) — regenerate them from the
  source of truth.
- A review that returns zero findings and an approval is suspect; state what was checked.
- The latest dated ruling governs when records conflict; surface the conflict.
