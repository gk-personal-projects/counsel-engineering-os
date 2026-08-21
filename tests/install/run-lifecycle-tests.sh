#!/usr/bin/env bash
# Counsel Engineering OS -- repair/uninstall/doctor lifecycle tests (POSIX port)
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-lifecycle-tests.ps1.
# D-T2-026 R5-S3 acceptance: repair restores missing owned files, preserves
# modified ones without the explicit flag, restores with it (backed up);
# uninstall removes only unmodified owned files, preserves user work; doctor
# reports manifest integrity.
# Dependencies: bash 3.2+, coreutils, python3 (JSON).
# Exit codes: 0 = all pass; 1 = at least one failure (sandbox kept).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

while [ $# -gt 0 ]; do
  case "$1" in
    -RepoRoot|--repo-root) REPO_ROOT="${2:?missing value for $1}"; shift 2 ;;
    *) printf '%s\n' "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

plan="$REPO_ROOT/scripts/install/install-plan.sh"
apply="$REPO_ROOT/scripts/install/install-apply.sh"
repair="$REPO_ROOT/scripts/install/repair.sh"
uninstall="$REPO_ROOT/scripts/install/uninstall.sh"
doctor="$REPO_ROOT/scripts/doctor.sh"
work="${TMPDIR:-/tmp}/counsel-lifecycle-tests-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$work"

pass=0; fail=0
# assert <exit-status: 0 = condition true> <name>
assert() {
  if [ "$1" -eq 0 ]; then pass=$((pass+1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail+1)); printf 'FAIL  %s\n' "$2"; fi
}

install_fresh() {
  _tgt="$1"
  mkdir -p "$_tgt"
  cm="$work/cm.txt"
  [ -e "$cm" ] || printf '# Test constitution\n' > "$cm"
  _st="$work/stage-$(basename "$_tgt")"
  bash "$plan" -Target "$_tgt" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$_st" -ClaudeMdContentPath "$cm" >/dev/null
  bash "$apply" -PlanPath "$_st/PLAN.json" >/dev/null
}

# ---------- L1: repair restores a missing owned file ------------------------
t1="$work/l1"; install_fresh "$t1"
rm -f "$t1/.counsel/rules/evidence.md"
bash "$repair" -Target "$t1" -Source "$REPO_ROOT" >/dev/null
assert $? "L1 repair exits 0"
[ -e "$t1/.counsel/rules/evidence.md" ]; assert $? "L1 missing owned file restored"

# ---------- L2: repair preserves modified owned file without flag -----------
authPath="$t1/.counsel/rules/authority.md"
printf '\nLOCAL EDIT\n' >> "$authPath"
bash "$repair" -Target "$t1" -Source "$REPO_ROOT" >/dev/null
assert $? "L2 repair exits 0 with modified file present"
grep -q 'LOCAL EDIT' "$authPath"
assert $? "L2 modified owned file preserved without -IncludeModified"

# ---------- L3: repair -IncludeModified restores + backs up -----------------
bash "$repair" -Target "$t1" -Source "$REPO_ROOT" -IncludeModified >/dev/null
assert $? "L3 repair -IncludeModified exits 0"
! grep -q 'LOCAL EDIT' "$authPath"
assert $? "L3 modified owned file restored"
bk=$(find "$t1/.counsel/originals" -type f -name "authority.md" 2>/dev/null | head -n 1)
[ -n "$bk" ] && grep -q 'LOCAL EDIT' "$bk"
assert $? "L3 pre-repair content backed up"

# ---------- L4: repair refuses version mismatch (update masquerade) ---------
mfPath="$t1/.counsel/manifest.json"
origVer=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_version"])' "$mfPath")
python3 -c '
import json, sys
p = sys.argv[1]
mf = json.load(open(p))
mf["runtime_version"] = sys.argv[2]
open(p, "w").write(json.dumps(mf, indent=2))
' "$mfPath" "0.0.9-test"
bash "$repair" -Target "$t1" -Source "$REPO_ROOT" >/dev/null 2>&1
[ $? -eq 1 ]; assert $? "L4 repair STOPS on runtime version mismatch (update, not repair)"
python3 -c '
import json, sys
p = sys.argv[1]
mf = json.load(open(p))
mf["runtime_version"] = sys.argv[2]
open(p, "w").write(json.dumps(mf, indent=2))
' "$mfPath" "$origVer"

# ---------- L5: doctor detects missing owned file as BLOCKING ---------------
rm -f "$t1/.counsel/rules/safety-base.md"
run_doctor_l5() {
  dOut=$(bash "$doctor" -ProjectDir "$t1" -OsDir "$REPO_ROOT" 2>&1)
  dRc=$?
}
run_doctor_l5
# doctor.sh may be mid-port; retry once before recording a failure
if [ "$dRc" -ne 1 ] || ! printf '%s\n' "$dOut" | grep -q 'owned file MISSING: .counsel/rules/safety-base.md'; then
  run_doctor_l5
fi
[ "$dRc" -eq 1 ]; assert $? "L5 doctor exits 1 (blocking) on missing owned file"
printf '%s\n' "$dOut" | grep -q 'owned file MISSING: .counsel/rules/safety-base.md'
assert $? "L5 doctor names the missing owned file"
bash "$repair" -Target "$t1" -Source "$REPO_ROOT" >/dev/null
[ -e "$t1/.counsel/rules/safety-base.md" ]; assert $? "L5 repair fixes it"

# ---------- L6: uninstall removes owned, preserves user work ----------------
t6="$work/l6"; install_fresh "$t6"
# simulate real use: user modifies one owned session file + owns their constitution
restorePath="$t6/.counsel/session/RESTORE.md"
printf '\nreal session state\n' >> "$restorePath"
bash "$uninstall" -Target "$t6" >/dev/null
assert $? "L6 uninstall exits 0"
[ ! -e "$t6/.counsel/rules/evidence.md" ]; assert $? "L6 owned rules removed"
[ ! -e "$t6/.claude/agents/tech-lead.md" ]; assert $? "L6 owned agents removed"
[ -e "$t6/CLAUDE.md" ]; assert $? "L6 user constitution preserved"
[ -e "$t6/.counsel/config.yaml" ]; assert $? "L6 user config preserved"
[ -e "$restorePath" ]; assert $? "L6 modified session file (user work) preserved"
[ ! -e "$t6/.counsel/manifest.json" ]; assert $? "L6 live manifest removed"
arch=$(find "$t6/.counsel/originals" -type f -name "manifest.json" 2>/dev/null | head -n 1)
[ -n "$arch" ]; assert $? "L6 manifest archived for audit"

# ---------- L7: doctor clean on healthy install -----------------------------
t7="$work/l7"; install_fresh "$t7"
bash "$doctor" -ProjectDir "$t7" -OsDir "$REPO_ROOT" >/dev/null 2>&1
d7=$?
if [ "$d7" -eq 1 ]; then
  # doctor.sh may be mid-port; retry once before recording a failure
  bash "$doctor" -ProjectDir "$t7" -OsDir "$REPO_ROOT" >/dev/null 2>&1
  d7=$?
fi
[ "$d7" -ne 1 ]; assert $? "L7 doctor reports no BLOCKING on healthy install (exit $d7)"

printf '\n'
printf 'LIFECYCLE TESTS: %s passed, %s failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'Sandbox kept for inspection: %s\n' "$work"
  exit 1
fi
rm -rf "$work"
exit 0
