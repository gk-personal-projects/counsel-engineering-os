# Recovery prompt (paste into a fresh session)

```text
Recover from durable state. Do not rely on conversational memory.

1. Run /counsel:restore (or scripts/session/restore.ps1|sh).
2. If it reports drift: STOP, reconcile each drift line against git/filesystem evidence,
   update RESTORE.md only when evidence supports it, checkpoint, then resume.
3. If consistent: state the phase, exact next action, and top safety constraints, then
   resume from RESTORE.md's next action. Do not re-read sources the state distills.
4. Never claim restored work is verified without re-running its verification.
```
