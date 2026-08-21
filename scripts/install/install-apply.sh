#!/usr/bin/env bash
# Counsel Engineering OS -- consented install applier (POSIX port).
# Provenance: ORIGINAL (Apache-2.0). Same contract as install-apply.ps1 (POSIX port).
# Implements D-T2-026 R5-S2 steps 5-10. Applies a PLAN.json produced by install-plan.sh:
#   - refuses if the target drifted since planning (stale plan)
#   - applies CREATE items and MERGE items explicitly approved (approved==true)
#   - NEVER applies CONFLICT items; never blind-overwrites anything
#   - backs up every pre-existing file it replaces to .counsel/originals/<stamp>/
#   - writes atomically (temp file + rename, same directory)
#   - upserts the ownership manifest .counsel/manifest.json (atomic)
#   - post-verifies every applied file hash
# Dependencies: bash 3.2+, coreutils, python3 (JSON engine; ships with Xcode CLT).
# Exit codes: 0 = applied + verified; 1 = failure/stale (target untouched or partially
# applied files are reported explicitly -- nothing is silently half-done).

set -u
. "$(dirname "$0")/../lib/common.sh"

PLAN_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    -PlanPath|--plan-path) PLAN_PATH="${2:?missing value for $1}"; shift 2 ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$PLAN_PATH" ] || ceos_die "Missing required argument: -PlanPath"

ceos_require_python3
[ -e "$PLAN_PATH" ] || ceos_die "Plan not found: $PLAN_PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/counsel-apply.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Plan -> header lines + items TSV. Field order per line:
# path class owned sha_staged sha_target approved region_sha ('~' marks null/absent).
python3 - "$PLAN_PATH" "$WORK" <<'PY' || ceos_die "Plan unreadable: $PLAN_PATH"
import json, sys
plan = json.load(open(sys.argv[1], 'r', encoding='utf-8-sig'))
work = sys.argv[2]
def tok(v):
    if v is None: return '~'
    if v is True: return 'true'
    if v is False: return 'false'
    s = str(v)
    return s if s else '~'
with open(work + '/head.txt', 'w') as out:
    out.write(tok(plan.get('target')) + '\n')
    out.write(tok(plan.get('stage_dir')) + '\n')
    out.write(tok(plan.get('runtime_version')) + '\n')
    out.write(tok(plan.get('control_plane_schema')) + '\n')
with open(work + '/items.tsv', 'w') as out:
    for i in (plan.get('items') or []):
        out.write('\t'.join([tok(i.get('path')), tok(i.get('class')), tok(i.get('owned')),
                             tok(i.get('sha_staged')), tok(i.get('sha_target')),
                             tok(i.get('approved')), tok(i.get('region_sha'))]) + '\n')
PY

TARGET=$(sed -n '1p' "$WORK/head.txt")
STAGE_DIR=$(sed -n '2p' "$WORK/head.txt")
RUNTIME_VERSION=$(sed -n '3p' "$WORK/head.txt")
CONTROL_PLANE_SCHEMA=$(sed -n '4p' "$WORK/head.txt")
[ -e "$TARGET" ] || ceos_die "Plan target missing: $TARGET"
[ -e "$STAGE_DIR" ] || ceos_die "Stage dir missing (re-run plan): $STAGE_DIR"

# --- stale check: every item's target must match the state recorded at plan time
: > "$WORK/stale.txt"
while IFS=$'\t' read -r ipath iclass iowned isha_staged isha_target iapproved iregion; do
  tp="$TARGET/$ipath"
  if [ "$isha_target" = "~" ]; then
    if [ -e "$tp" ]; then printf '%s\n' "$ipath (appeared after planning)" >> "$WORK/stale.txt"; fi
  else
    if [ ! -e "$tp" ]; then
      printf '%s\n' "$ipath (vanished after planning)" >> "$WORK/stale.txt"
    elif [ "$(ceos_sha256 "$tp")" != "$isha_target" ]; then
      printf '%s\n' "$ipath (changed after planning)" >> "$WORK/stale.txt"
    fi
  fi
done < "$WORK/items.tsv"
if [ -s "$WORK/stale.txt" ]; then
  printf 'STALE PLAN -- target drifted since planning. Nothing applied. Re-run install-plan.sh.\n'
  while IFS= read -r line; do printf '  ! %s\n' "$line"; done < "$WORK/stale.txt"
  exit 1
fi

STAMP=$(ceos_stamp)
ORIGINALS_DIR="$TARGET/.counsel/originals/$STAMP"
applied_count=0; removed_count=0; skipped_count=0; declined_count=0; conflict_count=0
: > "$WORK/applied.tsv"
: > "$WORK/removed.txt"
: > "$WORK/declined.txt"
: > "$WORK/conflicts.txt"
: > "$WORK/failures.txt"
fail_count=0

add_failure() {
  printf '%s\n' "$1" >> "$WORK/failures.txt"
  fail_count=$((fail_count+1))
}

backup_original() {
  # $1 = target file, $2 = plan-relative path
  mkdir -p "$ORIGINALS_DIR"
  _backup="$ORIGINALS_DIR/$2"
  mkdir -p "$(dirname "$_backup")"
  cp "$1" "$_backup"
}

while IFS=$'\t' read -r ipath iclass iowned isha_staged isha_target iapproved iregion; do
  tp="$TARGET/$ipath"
  sp="$STAGE_DIR/$ipath"
  case "$iclass" in
    PRESERVE)
      skipped_count=$((skipped_count+1)) ;;
    CONFLICT)
      printf '%s\n' "$ipath" >> "$WORK/conflicts.txt"
      conflict_count=$((conflict_count+1)) ;;
    CREATE)
      if [ "$iapproved" = "false" ]; then
        printf '%s\n' "$ipath" >> "$WORK/declined.txt"
        declined_count=$((declined_count+1))
      else
        ceos_copy_atomic "$sp" "$tp"
        printf '%s\n' "$ipath	$iclass	$iowned	$isha_staged	$iregion" >> "$WORK/applied.tsv"
        applied_count=$((applied_count+1))
      fi ;;
    MERGE)
      if [ "$iapproved" != "true" ]; then
        printf '%s\n' "$ipath" >> "$WORK/declined.txt"
        declined_count=$((declined_count+1))
      else
        backup_original "$tp" "$ipath"
        ceos_copy_atomic "$sp" "$tp"
        printf '%s\n' "$ipath	$iclass	$iowned	$isha_staged	$iregion" >> "$WORK/applied.tsv"
        applied_count=$((applied_count+1))
      fi ;;
    REMOVE)
      # Migration-only: counsel-owned, unmodified file whose home moved. Backed up, then deleted.
      if [ "$iapproved" != "true" ]; then
        printf '%s\n' "$ipath" >> "$WORK/declined.txt"
        declined_count=$((declined_count+1))
      else
        backup_original "$tp" "$ipath"
        chmod u+w "$tp" 2>/dev/null
        rm -f "$tp"
        printf '%s\n' "$ipath" >> "$WORK/removed.txt"
        removed_count=$((removed_count+1))
      fi ;;
    *)
      add_failure "$ipath: unknown class '$iclass'" ;;
  esac
done < "$WORK/items.tsv"

# --- post-verify every applied file (and every removal)
while IFS=$'\t' read -r ipath iclass iowned isha_staged iregion; do
  tp="$TARGET/$ipath"
  sha=$(ceos_sha256 "$tp" 2>/dev/null)
  if [ "$sha" != "$isha_staged" ]; then
    add_failure "$ipath: post-apply hash mismatch (expected $isha_staged, got $sha)"
  fi
done < "$WORK/applied.tsv"
while IFS= read -r ipath; do
  if [ -e "$TARGET/$ipath" ]; then
    add_failure "$ipath: REMOVE approved but file still present"
  fi
done < "$WORK/removed.txt"

# --- manifest upsert (atomic). Runs even when there are failures (intentional).
MANIFEST_PATH="$TARGET/.counsel/manifest.json"
APPLIED_AT=$(ceos_now_iso)
: > "$WORK/mferr.txt"
python3 - "$MANIFEST_PATH" "$WORK" "$RUNTIME_VERSION" "$CONTROL_PLANE_SCHEMA" "$APPLIED_AT" <<'PY' \
  || add_failure "manifest write failed: $MANIFEST_PATH"
import json, os, sys
manifest_path, work, rv, cps, now = sys.argv[1:6]
def untok(t):
    if t == '~': return None
    if t == 'true': return True
    if t == 'false': return False
    return t
mf = None
if os.path.exists(manifest_path):
    try:
        mf = json.load(open(manifest_path, 'r', encoding='utf-8-sig'))
    except Exception as e:
        with open(work + '/mferr.txt', 'w') as out:
            out.write('existing manifest unreadable: %s\n' % e)
        mf = None
if not isinstance(mf, dict):
    mf = {'schema_version': 1, 'runtime_version': rv, 'control_plane_schema': cps, 'files': []}
mf['runtime_version'] = rv
mf['control_plane_schema'] = cps
files = [f for f in (mf.get('files') or []) if f]
with open(work + '/applied.tsv', 'r') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line: continue
        path, cls, owned, sha_staged, region = line.split('\t')
        entry = {'path': path, 'owned': untok(owned), 'sha256': untok(sha_staged),
                 'runtime_version': rv, 'applied_class': cls, 'applied_at': now}
        if region != '~':
            entry['region_sha256'] = region
        files = [f for f in files if f.get('path') != path]
        files.append(entry)
with open(work + '/removed.txt', 'r') as fh:
    for line in fh:
        path = line.rstrip('\n')
        if not path: continue
        files = [f for f in files if f.get('path') != path]
mf['files'] = files
mf_dir = os.path.dirname(manifest_path)
if not os.path.isdir(mf_dir):
    os.makedirs(mf_dir)
tmp = os.path.join(mf_dir, '.tmp-manifest.json')
with open(tmp, 'w') as out:
    out.write(json.dumps(mf, indent=2) + '\n')
os.replace(tmp, manifest_path)
PY
if [ -s "$WORK/mferr.txt" ]; then
  while IFS= read -r line; do add_failure "$line"; done < "$WORK/mferr.txt"
fi

# --- report
printf 'APPLIED  : %s\n' "$applied_count"
printf 'REMOVED  : %s\n' "$removed_count"
printf 'PRESERVED: %s\n' "$skipped_count"
printf 'DECLINED/UNAPPROVED (untouched): %s\n' "$declined_count"
if [ "$declined_count" -gt 0 ]; then
  while IFS= read -r line; do printf '  - %s\n' "$line"; done < "$WORK/declined.txt"
fi
if [ "$conflict_count" -gt 0 ]; then
  printf 'CONFLICTS (untouched -- resolve, then re-plan):\n'
  while IFS= read -r line; do printf '  ! %s\n' "$line"; done < "$WORK/conflicts.txt"
fi
if [ "$applied_count" -gt 0 ] && [ -d "$ORIGINALS_DIR" ]; then
  printf 'Originals backed up: %s\n' "$ORIGINALS_DIR"
fi
printf 'Manifest: %s\n' "$MANIFEST_PATH"
if [ "$fail_count" -gt 0 ]; then
  printf 'FAILURES:\n'
  while IFS= read -r line; do printf '  ! %s\n' "$line"; done < "$WORK/failures.txt"
  exit 1
fi
printf 'Post-verify: all applied files match staged hashes.\n'
exit 0
