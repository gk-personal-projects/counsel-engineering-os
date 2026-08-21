#!/usr/bin/env bash
# Counsel Engineering OS -- continuity acceptance tests (D-T2-018 ruled list), POSIX-side.
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-tests.ps1, exercising the .sh
# ports (checkpoint.sh / restore.sh / session-doctor.sh) with positional args.
# Runs in an isolated sandbox under ${TMPDIR:-/tmp}; sandbox retained on failure.
# Exit 0 = all pass. Each case prints PASS/FAIL with its D-T2-018 test-list name.
#
# Contract notes vs run-tests.ps1 (mirror intent, not letter):
#   - MACHINE-STATE.json on the .sh side is a flat single-line-entry JSON shape
#     (documented cross-port difference), so assertions grep that shape instead of
#     parsing objects: unborn repos record `"head": null, "unborn": true`; dirty
#     working trees record a `"dirty": <count>` field, not a `status` array.
#   - T2's NTFS junction becomes a symlink (ln -s).
#   - T8's IsReadOnly attribute becomes chmod a-w on the pointer file.

set -u

SCRIPTS_DIR="${1:-}"
if [ -z "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$(cd "$(dirname "$0")/../../scripts/session" && pwd -P)"
else
  SCRIPTS_DIR="$(cd "$SCRIPTS_DIR" && pwd -P)" || { echo "ScriptsDir not found: $1" >&2; exit 1; }
fi
CP="$SCRIPTS_DIR/checkpoint.sh"
RS="$SCRIPTS_DIR/restore.sh"
DR="$SCRIPTS_DIR/session-doctor.sh"
for s in "$CP" "$RS" "$DR"; do
  [ -f "$s" ] || { echo "Missing script under test: $s" >&2; exit 1; }
done

SB="${TMPDIR:-/tmp}/ceos-continuity-tests-$(date +%Y%m%d%H%M%S)-$$"
mkdir -p "$SB"
passed=0; failed=0

# assert <0|nonzero cond result> <name> [detail]   (0 = condition held)
assert() {
  if [ "$1" -eq 0 ]; then passed=$((passed+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2  ${3:-}"; fi
}

# new_workspace <name>  -> echoes workspace path
new_workspace() {
  local ws="$SB/$1" sd="$SB/$1/.counsel/session"
  mkdir -p "$sd"
  printf '# RESTORE\nnext action: test\n' > "$sd/RESTORE.md"
  printf '{"phase":"test"}' > "$sd/STATE.json"
  echo "$ws"
}

# new_repo <ws> <name> [commit=1] [dirty=0]  -> echoes repo path
new_repo() {
  local r="$1/$2" commit="${3:-1}" dirty="${4:-0}"
  mkdir -p "$r"
  git -C "$r" init -q >/dev/null 2>&1
  git -C "$r" config user.email "test@test.local"
  git -C "$r" config user.name "test"
  if [ "$commit" = "1" ]; then
    printf 'x\n' > "$r/f.txt"
    git -C "$r" add . >/dev/null 2>&1
    git -C "$r" commit -q -m "init" >/dev/null 2>&1
  fi
  if [ "$dirty" = "1" ]; then printf 'y\n' > "$r/dirty.txt"; fi
  echo "$r"
}

# run_checkpoint <ws> <label>  -> sets CP_CODE, CP_OUT
run_checkpoint() {
  CP_OUT="$(sh "$CP" "$1" "$1/.counsel/session" "$2" 2>&1)"; CP_CODE=$?
}

# get_pointer <ws>  -> echoes pointer path or nothing
get_pointer() {
  local p="$1/.counsel/session/LAST-CHECKPOINT.txt"
  [ -f "$p" ] && head -n1 "$p" | tr -d '\r'
}

# -- T1: zero-commit / unborn repo -- checkpoint SUCCEEDS, unborn recorded ------
ws="$(new_workspace t01-unborn)"; new_repo "$ws" app 0 >/dev/null
run_checkpoint "$ws" t1
ptr="$(get_pointer "$ws")"
cond=1
if [ "$CP_CODE" -eq 0 ] && [ -n "$ptr" ] && [ -f "$ptr/MACHINE-STATE.json" ] \
   && grep -q '"head": null, "unborn": true' "$ptr/MACHINE-STATE.json"; then cond=0; fi
assert $cond "T1  zero-commit/unborn repo captured as valid state" "code=$CP_CODE"

# -- T2: duplicate repository discovery (symlink) -- deduped, single entry ------
ws="$(new_workspace t02-dup)"; repo="$(new_repo "$ws" app)"
ln -s "$repo" "$ws/app-link"
run_checkpoint "$ws" t2
ptr="$(get_pointer "$ws")"
entries=$(grep -c '"head": "[0-9a-f]\{40\}"' "$ptr/MACHINE-STATE.json" 2>/dev/null || echo 0)
cond=1; [ "$CP_CODE" -eq 0 ] && [ "$entries" -eq 1 ] && cond=0
assert $cond "T2  duplicate repo discovery deduped" "entries=$entries"

# -- T3: git failure mid-capture (corrupt .git) -- FAIL, no promote, forensics --
ws="$(new_workspace t03-gitfail)"; new_repo "$ws" good >/dev/null
bad="$ws/bad"; mkdir -p "$bad"
printf 'gitdir: /nonexistent/nowhere\n' > "$bad/.git"
run_checkpoint "$ws" t3
faileddirs=0; failuretxt=1
for d in "$ws/.counsel/session/CHECKPOINTS"/FAILED-*; do
  [ -d "$d" ] || continue
  faileddirs=$((faileddirs+1))
  [ -f "$d/FAILURE.txt" ] && failuretxt=0
done
cond=1
if [ "$CP_CODE" -ne 0 ] && [ "$faileddirs" -eq 1 ] && [ "$failuretxt" -eq 0 ] \
   && [ -z "$(get_pointer "$ws")" ]; then cond=0; fi
assert $cond "T3  git failure mid-capture: no promotion, failure surfaced+preserved" "code=$CP_CODE failed=$faileddirs"

# -- T4: partial checkpoint (leftover .tmp) -- never a restore target -----------
ws="$(new_workspace t04-partial)"; new_repo "$ws" app >/dev/null
run_checkpoint "$ws" t4-good
good="$(get_pointer "$ws")"
mkdir -p "$ws/.counsel/session/CHECKPOINTS/.tmp-99999999-999999-killed"   # simulated kill mid-checkpoint
rs_out="$(sh "$RS" "$ws" "$ws/.counsel/session" 2>&1)"
cond=1
if printf '%s' "$rs_out" | grep -qF "$(basename "$good")" \
   && ! printf '%s' "$rs_out" | grep -q "tmp-99999999"; then cond=0; fi
assert $cond "T4  partial checkpoint ignored by restore; valid one used"

# -- T5: stale LAST-CHECKPOINT pointer -- fallback + drift surfaced -------------
ws="$(new_workspace t05-stale)"; new_repo "$ws" app >/dev/null
run_checkpoint "$ws" t5
sd="$ws/.counsel/session"
printf '%s\n' "$sd/CHECKPOINTS/20990101-000000-ghost" > "$sd/LAST-CHECKPOINT.txt"
rs_out="$(sh "$RS" "$ws" "$sd" 2>&1)"; rs_code=$?
cond=1
if [ "$rs_code" -eq 2 ] && printf '%s' "$rs_out" | grep -q "STALE POINTER" \
   && printf '%s' "$rs_out" | grep -q "FALLBACK"; then cond=0; fi
assert $cond "T5  stale pointer: fallback to newest valid + drift surfaced" "code=$rs_code"

# -- T6: failed validation preserves previous authoritative checkpoint ----------
ws="$(new_workspace t06-preserve)"; new_repo "$ws" app >/dev/null
run_checkpoint "$ws" t6-first
first="$(get_pointer "$ws")"
bad="$ws/corrupt"; mkdir -p "$bad"
printf 'gitdir: /nope\n' > "$bad/.git"
run_checkpoint "$ws" t6-second
cond=1
[ "$CP_CODE" -ne 0 ] && [ "$(get_pointer "$ws")" = "$first" ] && cond=0
assert $cond "T6  failed validation: previous checkpoint remains authoritative" "code=$CP_CODE"

# -- T7: UTF-8 content survives checkpoint round-trip ---------------------------
ws="$(new_workspace t07-utf8)"; new_repo "$ws" app >/dev/null
sd="$ws/.counsel/session"
# Non-ASCII built from UTF-8 byte escapes so this script file stays ASCII-safe:
# e-diaeresis-ish naive, middle dot, Japanese "nihongo", check mark, em dash.
printf '# RESTORE\nna\xc3\xafve \xc2\xb7 \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e \xc2\xb7 \xc3\xa9moji \xe2\x9c\x85 \xe2\x80\x94 dash' > "$sd/RESTORE.md"
run_checkpoint "$ws" t7
ptr="$(get_pointer "$ws")"
cond=1
[ -n "$ptr" ] && cmp -s "$sd/RESTORE.md" "$ptr/RESTORE.md" && cond=0
assert $cond "T7  UTF-8 content round-trips intact"

# -- T8: read-only pointer file -- write still succeeds -------------------------
ws="$(new_workspace t08-readonly)"; new_repo "$ws" app >/dev/null
sd="$ws/.counsel/session"
run_checkpoint "$ws" t8-a
chmod a-w "$sd/LAST-CHECKPOINT.txt"
run_checkpoint "$ws" t8-b
ptr="$(get_pointer "$ws")"
cond=1
[ "$CP_CODE" -eq 0 ] && case "$ptr" in *t8-b) cond=0;; esac
assert $cond "T8  locked/read-only pointer file: safe-write path succeeds" "code=$CP_CODE"

# -- T9: dirty working tree captured --------------------------------------------
ws="$(new_workspace t09-dirty)"; new_repo "$ws" app 1 1 >/dev/null
run_checkpoint "$ws" t9
ptr="$(get_pointer "$ws")"
cond=1
# .sh contract: dirty state is a nonzero "dirty" count field (not a status array).
[ -n "$ptr" ] && grep -q '"dirty": [1-9]' "$ptr/MACHINE-STATE.json" && cond=0
assert $cond "T9  dirty working tree captured in snapshot"

# -- T10: missing repository during recovery -- flagged, not silent -------------
ws="$(new_workspace t10-missing)"; repo="$(new_repo "$ws" app)"
run_checkpoint "$ws" t10
rm -rf "$repo"
rs_out="$(sh "$RS" "$ws" "$ws/.counsel/session" 2>&1)"; rs_code=$?
cond=1
[ "$rs_code" -eq 2 ] && printf '%s' "$rs_out" | grep -q "MISSING REPO" && cond=0
assert $cond "T10 missing repo at recovery: surfaced as drift" "code=$rs_code"

# -- T11: deliberate save-and-restart -- restore reconstructs consistent state --
ws="$(new_workspace t11-savecycle)"; new_repo "$ws" app >/dev/null
run_checkpoint "$ws" t11
rs_out="$(sh "$RS" "$ws" "$ws/.counsel/session" 2>&1)"; rs_code=$?
cond=1
if [ "$rs_code" -eq 0 ] && printf '%s' "$rs_out" | grep -q "State consistent" \
   && printf '%s' "$rs_out" | grep -q "next action: test"; then cond=0; fi
assert $cond "T11 save-and-restart: clean reconstruction, consistent verdict" "code=$rs_code"

# -- T12: abrupt termination mid-checkpoint -- doctor flags residue; next run OK -
ws="$(new_workspace t12-abrupt)"; new_repo "$ws" app >/dev/null
sd="$ws/.counsel/session"
mkdir -p "$sd/CHECKPOINTS/.tmp-11111111-111111-killed"
doc="$(sh "$DR" "$ws" "$sd" 2>&1)"
doc_flagged=1; printf '%s' "$doc" | grep -q "residue" && doc_flagged=0
run_checkpoint "$ws" t12-after
ptr="$(get_pointer "$ws")"
cond=1
if [ "$doc_flagged" -eq 0 ] && [ "$CP_CODE" -eq 0 ]; then
  case "$ptr" in *t12-after) cond=0;; esac
fi
assert $cond "T12 abrupt termination: residue flagged by doctor, next checkpoint clean" "code=$CP_CODE"

# -- T13: recovery after failed attempt -- subsequent checkpoint restores health -
ws="$(new_workspace t13-recover)"; new_repo "$ws" app >/dev/null
bad="$ws/corrupt"; mkdir -p "$bad"
printf 'gitdir: /nope\n' > "$bad/.git"
run_checkpoint "$ws" t13-fail; r1=$CP_CODE
rm -rf "$bad"
run_checkpoint "$ws" t13-ok; r2=$CP_CODE
doc="$(sh "$DR" "$ws" "$ws/.counsel/session" 2>&1)"
ptr="$(get_pointer "$ws")"
cond=1
if [ "$r1" -ne 0 ] && [ "$r2" -eq 0 ] \
   && printf '%s' "$doc" | grep -q "Pointer -> valid checkpoint"; then
  case "$ptr" in *t13-ok) cond=0;; esac
fi
assert $cond "T13 recovery after failed attempt: pointer moves only to the new valid checkpoint" "r1=$r1 r2=$r2"

# -- summary --------------------------------------------------------------------
echo ""
echo "RESULT: $passed passed, $failed failed  (sandbox: $SB)"
if [ "$failed" -eq 0 ]; then
  chmod -R u+w "$SB" 2>/dev/null
  rm -rf "$SB" 2>/dev/null
  exit 0
fi
exit 1
