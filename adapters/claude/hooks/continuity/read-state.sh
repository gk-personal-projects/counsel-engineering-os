#!/usr/bin/env sh
# Core Continuity Hook Pack -- SessionStart state injector (read-only).
# Provenance: ORIGINAL (Apache-2.0). Prints RESTORE.md + CAPSULE.md. Never writes. Exit 0 always.
SESSION_DIR="${1:-.counsel/session}"
if [ -f "$SESSION_DIR/RESTORE.md" ]; then
  echo "=== COUNSEL SESSION STATE (RESTORE.md) ==="
  cat "$SESSION_DIR/RESTORE.md"
fi
if [ -f "$SESSION_DIR/CAPSULE.md" ]; then
  echo ""
  echo "=== ACTIVE CAPSULE (CAPSULE.md) ==="
  cat "$SESSION_DIR/CAPSULE.md"
fi
exit 0
