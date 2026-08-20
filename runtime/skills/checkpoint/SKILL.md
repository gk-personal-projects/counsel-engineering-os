---
name: checkpoint
description: Save a durable semantic + mechanical snapshot of the current session. Use before context compaction, clearing, or restarts, after rulings/commits/gate changes, when nearing context limits, or whenever current state would be hard to reconstruct.
user_invocable: true
---

# /counsel:checkpoint

Provenance: ORIGINAL (Apache-2.0).

A checkpoint is two layers, always in this order:

## 1 · Semantic checkpoint (you write it)

Update, in the project session dir (`.counsel/session/` unless configured otherwise):
1. `RESTORE.md` — current phase/gate, verified repo state, completed, in-flight, **exact next action**, governing decisions, safety constraints. Overwrite blind; never read-to-update.
2. `CAPSULE.md` — refresh if a ticket is active (≤ ~1,000 tokens; objective, ticket, state, decision/evidence pointers, blockers, next action, DO-NOTs; never session history).
3. `DECISIONS.md` / `OPEN-ITEMS.md` — append/close anything that changed. Append-only for decisions.

## 2 · Mechanical checkpoint (the script does it)

Run the platform script:
- Windows: `scripts/session/checkpoint.ps1 -Workspace <ws> -SessionDir <sessiondir> -Label <label>`
- POSIX: `scripts/session/checkpoint.sh <ws> <sessiondir> <label>`

The script is ATOMIC (temp → capture → validate → promote → pointer). Interpret results:
- exit 0 — checkpoint authoritative; report the created path.
- exit 1 — **the previous checkpoint is still authoritative.** Read the FAILED-*/FAILURE.txt
  reasons, fix the cause, re-run. Never hand-edit a checkpoint into existence, and never
  hand-author git facts (hashes/branches) — regenerate them from git.

Label discipline: short kebab-case describing the trigger (`gate-t3-pass`, `pre-compact`).

Never claim a checkpoint succeeded without the script's exit 0 output.
