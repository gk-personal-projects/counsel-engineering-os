# Session continuity — behavior reference

Provenance: ORIGINAL (Apache-2.0). Governing rulings: D-T2-018 (atomic checkpoint),
D-T2-009 (hook pack class), D-T2-017 (capsule budget), D-T2-020 §14–15.

## State model (project control plane, `.counsel/session/`)

| File | Write mode | Purpose |
|---|---|---|
| RESTORE.md | overwrite blind | resume brief: phase, verified state, exact next action |
| STATE.json | overwrite | machine-readable phase/gate/git/next-action |
| CAPSULE.md | overwrite | active-ticket execution context, ≈≤1,000 tokens, never history |
| DECISIONS.md | append-only | decisions of record; supersede, never rewrite |
| OPEN-ITEMS.md | edit rows | open items; never silently resolved |
| ARTIFACT-REGISTRY.md | edit rows | durable outputs + authority |
| SESSION-LOG.md | append at anchor | self-contained entries |
| CHECKPOINTS/ | immutable | promoted snapshots + FAILED-* forensics |
| LAST-CHECKPOINT.txt | script-only | pointer to the authoritative checkpoint |

## Atomic checkpoint invariant (D-T2-018)

`.tmp-*` → capture (session files + machine/git state) → validate (JSON parses; required
copies present; repo roots unique; recorded HEADs re-verified against live git) →
promote (rename) → update pointer LAST. Failure: previous checkpoint stays authoritative,
attempt preserved as `FAILED-*` with `FAILURE.txt`, exit 1. Unborn (zero-commit) repos are
a valid captured state, not a failure. Recovery tooling never hand-authors git facts.

## Scripts (`scripts/session/`, ps1 + sh parity, ASCII source, git-only dependency)

checkpoint / restore / session-doctor. Exit codes: checkpoint 0|1; restore 0 consistent,
2 drift (stop and reconcile), 1 unrecoverable; doctor 0|1 fail|2 warn.

## Acceptance tests (`tests/continuity/run-tests.ps1`) — D-T2-018 ruled list

13 cases, all passing as of 2026-08-12: unborn repo, duplicate discovery (junction),
git failure mid-capture, partial checkpoint, stale pointer, failed-validation
preservation, UTF-8 round-trip, locked/read-only pointer (placeholder class), dirty tree,
missing repo at recovery, save-and-restart cycle, abrupt-termination residue, recovery
after failed attempt. POSIX smoke: normal/unborn/stale-pointer via checkpoint.sh +
restore.sh.

Engineering notes baked in from live failures: PS 5.1 misparses BOM-less UTF-8 source →
scripts are ASCII-only; `Set-Content` fails on OneDrive cloud placeholders → delete-then-
`WriteAllText`; PS variable case-insensitivity bit the test harness once ($rs vs $RS).

## Hook pack

See `runtime/hooks/continuity/README.md`. Default OFF; crash recovery never relies on
SessionEnd; hooks only read state or invoke the atomic checkpoint.
