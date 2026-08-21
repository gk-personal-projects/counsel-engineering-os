#!/usr/bin/env sh
# Counsel Engineering OS -- session-state doctor (POSIX sh). Read-only.
# Provenance: ORIGINAL (Apache-2.0). Exit: 0 healthy, 1 FAIL present, 2 WARN present.
# Args (positional): workspace, session-dir, max-checkpoint-age-hours (default 24).
# Dependencies: git + coreutils only. Network: none.
set -u
WORKSPACE="${1:-$(pwd)}"
SESSION_DIR="${2:-$WORKSPACE/.counsel/session}"
MAX_AGE_HOURS="${3:-24}"
case "$MAX_AGE_HOURS" in ''|*[!0-9]*) MAX_AGE_HOURS=24;; esac
FAILS=0; WARNS=0
ok()   { echo "OK    $1"; }
warn() { echo "WARN  $1"; WARNS=$((WARNS+1)); }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

[ -d "$SESSION_DIR" ] || { echo "FAIL  Session dir missing: $SESSION_DIR"; exit 1; }
ok "Session dir present: $SESSION_DIR"
for name in RESTORE.md STATE.json; do
  [ -f "$SESSION_DIR/$name" ] && ok "$name present" || fail "$name missing"
done
# STATE.json parse sanity (git+coreutils only, so structural check, not a full JSON
# parser): first non-space char opens an object/array and braces/brackets balance.
if [ -f "$SESSION_DIR/STATE.json" ]; then
  sp="$SESSION_DIR/STATE.json"
  first=$(tr -d '[:space:]' < "$sp" | cut -c1)
  ob=$(tr -cd '{' < "$sp" | wc -c | tr -d ' '); cb=$(tr -cd '}' < "$sp" | wc -c | tr -d ' ')
  oa=$(tr -cd '[' < "$sp" | wc -c | tr -d ' '); ca=$(tr -cd ']' < "$sp" | wc -c | tr -d ' ')
  if { [ "$first" = "{" ] || [ "$first" = "[" ]; } && [ "$ob" -eq "$cb" ] && [ "$oa" -eq "$ca" ]; then
    ok "STATE.json parses"
  else
    fail "STATE.json does not parse: not well-formed JSON (structural check)"
  fi
fi
# STALE-RESTORE: on harnesses without lifecycle hooks, a RESTORE older than recent work
# is drift, not truth (runtime/HARNESS.md degraded mode). Compare RESTORE mtime to the
# newest commit time in the workspace repo, if any.
if [ -f "$SESSION_DIR/RESTORE.md" ]; then
  last_commit=$(git -C "$WORKSPACE" log -1 --format=%ct 2>/dev/null | tr -d '[:space:]')
  case "$last_commit" in
    ''|*[!0-9]*) : ;;  # no repo / no commits -- skip, same as session-doctor.ps1
    *)
      restore_mtime=$(date -r "$SESSION_DIR/RESTORE.md" +%s 2>/dev/null) || restore_mtime=""
      if [ -n "$restore_mtime" ] && [ "$restore_mtime" -lt "$last_commit" ]; then
        warn "STALE-RESTORE: RESTORE.md (mtime $restore_mtime) predates the newest commit ($last_commit) -- treat as drift; checkpoint or restore before trusting it"
      else
        ok "RESTORE.md is newer than the last commit"
      fi;;
  esac
fi
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
           # Checkpoint age (mtime of MACHINE-STATE.json -- portable, no JSON date parse).
           now=$(date +%s)
           cp_mtime=$(date -r "$PTR/MACHINE-STATE.json" +%s 2>/dev/null) || cp_mtime=""
           if [ -n "$cp_mtime" ]; then
             age_s=$((now - cp_mtime)); [ "$age_s" -lt 0 ] && age_s=0
             age_t=$((age_s * 10 / 3600))
             if [ "$age_s" -gt $((MAX_AGE_HOURS * 3600)) ]; then
               warn "Last checkpoint is $((age_t / 10)).$((age_t % 10))h old (max ${MAX_AGE_HOURS}h)"
             else
               ok "Last checkpoint age $((age_t / 10)).$((age_t % 10))h"
             fi
           fi
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
