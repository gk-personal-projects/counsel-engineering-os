---
name: save-and-restart
description: Deliberately end the current session with full state preservation so a fresh session resumes precisely. Use when context is heavy, before switching to unrelated work, or when the user says "save and restart".
user_invocable: true
---

# /counsel:save-and-restart

Provenance: ORIGINAL (Apache-2.0).

1. Finish or cleanly stop the current atomic operation — never mid-edit, mid-commit, or
   mid-checkpoint.
2. Perform the full semantic checkpoint (see counsel-checkpoint §1), including a
   self-contained SESSION-LOG.md append (a reader of this entry alone can resume).
3. Refresh CAPSULE.md — it is the first thing the next session reads after RESTORE.
4. Run the mechanical checkpoint with label `save-and-restart`. Require exit 0.
5. Verify: re-read LAST-CHECKPOINT.txt, confirm it points at the new checkpoint.
6. Tell the user state is saved, give the checkpoint path, and instruct: start a fresh
   session and invoke `/counsel:restore` (or paste the recovery prompt from
   `scaffold/session/RECOVERY-PROMPT.md`).

Cost note (D-T2-016): prefer save-and-restart over keeping a large session alive as
memory — durable state belongs in continuity artifacts, not in context.
