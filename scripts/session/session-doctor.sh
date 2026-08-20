#!/usr/bin/env sh
# Counsel Engineering OS -- session-state doctor (POSIX sh). Read-only.
# Provenance: ORIGINAL (Apache-2.0). Exit: 0 healthy, 1 FAIL present, 2 WARN present.
set -u
WORKSPACE="${1:-$(pwd)}"
SESSION_DIR="${2:-$WORKSPACE/.counsel/session}"
FAILS=0; WARNS=0
ok()   { echo "OK    $1"; }
warn() { echo "WARN  $1"; WARNS=$((WARNS+1)); }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

[ -d "$SESSION_DIR" ] || { echo "FAIL  Session dir missing: $SESSION_DIR"; exit 1; }
ok "Session dir present: $SESSION_DIR"
for name in RESTORE.md STATE.json; do
  [ -f "$SESSION_DIR/$name" ] && ok "$name present" || fail "$name missing"
done
if [ -f "$SESSION_DIR/CAPSULE.md" ]; then
  chars=$(wc -c < "$SESSION_DIR/CAPSULE.md")
  [ "$chars" -gt 6000 ] && warn "CAPSULE.md ~$((chars/4)) tokens exceeds ~1k budget (D-T2-017)" || ok "CAPSULE.md within budget"
fi
CP_ROOT="$SESSION_DIR/CHECKPOINTS"
if [ ! -d "$CP_ROOT" ]; then warn "No CHECKPOINTS directory yet"
else
  for d in "$CP_ROOT"/.tmp-*; do [ -d "$d" ] && warn "Aborted checkpoint residue: $(basename "$d")"; done
  for d in "$CP_ROOT"/FAILED-*; do [ -d "$d" ] && warn "Failed checkpoint preserved: $(basename "$d") (see FAILURE.txt)"; done
  if [ ! -f "$SESSION_DIR/LAST-CHECKPOINT.txt" ]; then fail "LAST-CHECKPOINT.txt missing"
  else
    PTR=$(head -n1 "$SESSION_DIR/LAST-CHECKPOINT.txt" | tr -d '\r')
    case "$(basename "$PTR")" in
      .tmp-*|FAILED-*) fail "Pointer targets an invalid checkpoint: $(basename "$PTR")";;
      *) if [ ! -d "$PTR" ]; then fail "Stale pointer: $PTR does not exist"
         elif [ ! -f "$PTR/MACHINE-STATE.json" ]; then fail "Pointed checkpoint incomplete: $(basename "$PTR")"
         else
           ok "Pointer -> valid checkpoint: $(basename "$PTR")"
           grep -o '"root": "[^"]*", "branch": "[^"]*", "head": "[0-9a-f]\{40\}"' "$PTR/MACHINE-STATE.json" | \
           while IFS= read -r line; do
             root=$(printf '%s' "$line" | sed 's/^"root": "\([^"]*\)".*/\1/')
             rec=$(printf '%s' "$line" | sed 's/.*"head": "\([0-9a-f]\{40\}\)".*/\1/')
             if [ ! -d "$root" ]; then echo "WARN  Recorded repo missing on disk: $root"
             else
               live=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null) || live=""
               [ "$live" = "$rec" ] && echo "OK    Git consistent: $(basename "$root")" \
                 || echo "WARN  Git drift at $(basename "$root"): recorded $(printf '%.7s' "$rec"), live $(printf '%.7s' "$live")"
             fi
           done | tee "$SESSION_DIR/.doctor-sub"
           grep -q '^WARN' "$SESSION_DIR/.doctor-sub" && WARNS=$((WARNS+1))
           rm -f "$SESSION_DIR/.doctor-sub"
         fi;;
    esac
  fi
fi
echo ""
if [ "$FAILS" -gt 0 ]; then echo "SESSION DOCTOR: FAIL ($FAILS fail, $WARNS warn)"; exit 1; fi
if [ "$WARNS" -gt 0 ]; then echo "SESSION DOCTOR: WARN ($WARNS warn)"; exit 2; fi
echo "SESSION DOCTOR: HEALTHY"; exit 0
