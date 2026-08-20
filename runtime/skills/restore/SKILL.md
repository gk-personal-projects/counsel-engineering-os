---
name: restore
description: Recover working state after a crash, /clear, compaction, or new session. Verifies durable state against live git/filesystem and surfaces drift instead of guessing.
user_invocable: true
---

# /counsel:restore

Provenance: ORIGINAL (Apache-2.0).

Recovery never trusts conversational memory. Order:

1. Run the platform script (read-only):
   - Windows: `scripts/session/restore.ps1 -Workspace <ws> -SessionDir <sessiondir>`
   - POSIX: `scripts/session/restore.sh <ws> <sessiondir>`
   It prints RESTORE.md, STATE.json, CAPSULE.md, the authoritative checkpoint, and a
   recorded-vs-live git drift report. Stale pointers fall back to the newest VALID
   checkpoint automatically — with the drift surfaced.

2. Exit 0 (consistent): state the current phase/gate, the exact next action, and the top
   safety constraints; resume from RESTORE.md §"exact next action". Do not re-read
   historical sources the state files already distill.

3. Exit 2 (drift/warnings): **STOP. Do not pick a winner silently.** For each drift line,
   verify against git/filesystem, reconstruct the most recent durable truth, update
   RESTORE.md only after evidence supports it, run /counsel:checkpoint, then resume.

4. Exit 1 (unrecoverable): report exactly what is missing; ask before rebuilding state.

Never mark restored work "verified" — restoration recovers *claims*; verification status
comes from re-running the verification, or stays flagged unverified.
