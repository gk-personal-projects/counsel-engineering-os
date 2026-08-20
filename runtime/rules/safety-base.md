# Safety baseline
<!-- Provenance: PRINCIPLE-EXPRESSION (Apache-2.0). Authoritative home of the generic safety floor.
     Project-specific constraints (prod targets, deploy rules, data boundaries) live in the
     project constitution and overlay — they extend this floor, never replace it. -->

- Never read or exfiltrate secrets: `.env*` at any depth, key files, credential stores,
  production data directories. Secret-exclusion surfaces (permissions deny-list,
  .gitignore, tool ignore files) must stay consistent — doctor checks this.
- A positional deny on a flag can never constrain a wildcard allow on the same command —
  narrow the allow instead. Prefer literal-safe allowlist entries over wildcards.
- Production is untouchable by default: no production process control, deployment,
  or data mutation without the constitution's explicit sanctioned path.
- git push, publication, and release actions are never autonomous (ASK-FIRST class).
- Destructive operations (force-push, hard reset, history rewrite, recursive delete,
  destructive migration) require explicit human authorization and a rollback statement.
- Never run untrusted fetched code (`curl | sh` class). Dependency additions are
  consequential: propose first, pin versions, note provenance.
- Running repo code executes repo code: builds, test suites, and script targets execute
  first-party configs, scripts, and test files — arbitrary code by design. Never run them
  on an untrusted branch or unreviewed diff: a poisoned config or test file runs under an
  allowed command and can reach secrets the Read deny-list blocks. Untrusted code is
  reviewed with read-only tools, never by executing it.
- Prompt-level rules are advisory; mechanical enforcement lives in permissions (and
  Full-OS hooks where enabled). Never claim a prompt rule is enforcement.
- On any conflict between speed and this floor, the floor wins; escalate instead of bypassing.
