#!/usr/bin/env sh
# Counsel Engineering OS — session restore reader (POSIX sh).
# Provenance: ORIGINAL (Apache-2.0). Same contract as restore.ps1: read-only; falls back to
# the newest VALID completed checkpoint when the pointer is stale; surfaces drift explicitly.
# Exit: 0 consistent, 2 drift/warnings present, 1 unrecoverable.

set -u
WORKSPACE="${1:-$(pwd)}"
SESSION_DIR="${2:-$WORKSPACE/.counsel/session}"
[ -d "$SESSION_DIR" ] || { echo "Session dir not found: $SESSION_DIR" >&2; exit 1; }
CP_ROOT="$SESSION_DIR/CHECKPOINTS"
DRIFT=0

valid_cp() {
  case "$(basename "$1")" in .tmp-*|FAILED-*) return 1;; esac
  [ -d "$1" ] && [ -f "$1/MACHINE-STATE.json" ]
}

TARGET=""
if [ -f "$SESSION_DIR/LAST-CHECKPOINT.txt" ]; then
  PTR=$(head -n1 "$SESSION_DIR/LAST-CHECKPOINT.txt" | tr -d '\r')
  if valid_cp "$PTR"; then TARGET="$PTR"
  else echo "! STALE POINTER: $PTR"; DRIFT=1; fi
else
  echo "! LAST-CHECKPOINT.txt missing"; DRIFT=1
fi
if [ -z "$TARGET" ] && [ -d "$CP_ROOT" ]; then
  for d in $(ls -1d "$CP_ROOT"/*/ 2>/dev/null | sort -r); do
    d="${d%/}"
    if valid_cp "$d"; then TARGET="$d"; echo "! FALLBACK: using newest valid checkpoint $(basename "$d")"; DRIFT=1; break; fi
  done
fi

echo "=== RESTORE.md ==="; [ -f "$SESSION_DIR/RESTORE.md" ] && cat "$SESSION_DIR/RESTORE.md" || echo "(missing)"
echo; echo "=== STATE.json ==="; [ -f "$SESSION_DIR/STATE.json" ] && cat "$SESSION_DIR/STATE.json" || echo "(missing)"
echo; echo "=== CAPSULE.md ==="; [ -f "$SESSION_DIR/CAPSULE.md" ] && cat "$SESSION_DIR/CAPSULE.md" || echo "(none)"
echo; echo "=== CHECKPOINT ==="; [ -n "$TARGET" ] && echo "$TARGET" || echo "(none valid)"

if [ -n "$TARGET" ]; then
  echo; echo "=== GIT DRIFT (recorded vs live) ==="
  grep -o '"root": "[^"]*"\(, "branch": "[^"]*"\)\?, "head": \("[0-9a-f]\{40\}"\|null\)' "$TARGET/MACHINE-STATE.json" | \
  while IFS= read -r line; do
    root=$(printf '%s' "$line" | sed 's/^"root": "\([^"]*\)".*/\1/')
    rec=$(printf '%s' "$line" | sed 's/.*"head": //; s/"//g')
    name=$(basename "$root")
    if [ ! -d "$root" ]; then echo "! MISSING REPO: $root"; continue; fi
    live=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null) || live=""
    if [ "$rec" = "null" ]; then
      [ -n "$live" ] && echo "! DRIFT $name: recorded unborn, live $live" || echo "  $name: OK (unborn)"
    else
      [ "$live" = "$rec" ] && echo "  $name: OK ($(printf '%.7s' "$rec"))" || echo "! DRIFT $name: recorded $rec, live $live"
    fi
  done | tee "$SESSION_DIR/.restore-drift"
  grep -q '^!' "$SESSION_DIR/.restore-drift" && DRIFT=1
  rm -f "$SESSION_DIR/.restore-drift"
fi

if [ $DRIFT -ne 0 ]; then
  echo; echo "=== DRIFT PRESENT — reconcile before resuming (never pick a winner silently) ==="
  exit 2
fi
echo; echo "State consistent. Resume from RESTORE.md 'exact next action'."
exit 0
