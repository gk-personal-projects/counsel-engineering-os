#!/usr/bin/env bash
# Counsel Engineering OS -- uninstall (POSIX port).
# Provenance: ORIGINAL (Apache-2.0). Same contract as uninstall.ps1 (POSIX port).
# D-T2-026 S3: removes ONLY counsel-owned files whose content still matches the
# ownership manifest. Preserves, always:
#   - user-owned files (constitution, .claude/settings.json, .counsel/config.yaml,
#     .gitignore) -- reported, never deleted
#   - locally-MODIFIED owned files (user changed them; deleting would destroy user work)
#   - .counsel/session/ working state and .counsel/originals/ backups
# The manifest is archived (not deleted) so uninstall is auditable. App code is never touched.
# Dependencies: bash 3.2+, coreutils, python3 (JSON engine; ships with Xcode CLT).
# Exit codes: 0 = uninstalled; 1 = validation failure (bad target / no manifest).

set -u
. "$(dirname "$0")/../lib/common.sh"

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -Target|--target) TARGET="${2:?missing value for $1}"; shift 2 ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$TARGET" ] || ceos_die "Missing required argument: -Target"

ceos_require_python3

TARGET_RESOLVED=$(ceos_resolve_dir "$TARGET") || ceos_die "Target not found: $TARGET"
TARGET="$TARGET_RESOLVED"
MANIFEST_PATH="$TARGET/.counsel/manifest.json"
[ -e "$MANIFEST_PATH" ] || ceos_die "No ownership manifest at $MANIFEST_PATH - nothing to uninstall"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/counsel-uninstall.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Manifest -> TSV: path <TAB> owned <TAB> sha256 ('~' marks null/absent fields).
python3 - "$MANIFEST_PATH" "$WORK/files.tsv" <<'PY' || ceos_die "Manifest unreadable: $MANIFEST_PATH"
import json, sys
mf = json.load(open(sys.argv[1], 'r', encoding='utf-8-sig'))
def tok(v):
    if v is None: return '~'
    if v is True: return 'true'
    if v is False: return 'false'
    s = str(v)
    return s if s else '~'
with open(sys.argv[2], 'w') as out:
    for f in (mf.get('files') or []):
        if not f: continue
        out.write('\t'.join([tok(f.get('path')), tok(f.get('owned')), tok(f.get('sha256'))]) + '\n')
PY

removed_count=0; preserved_count=0; left_count=0
: > "$WORK/preserved.txt"
: > "$WORK/left.txt"
already_gone=""

while IFS=$'\t' read -r fpath fowned fsha; do
  [ "$fpath" = "~" ] && continue
  p="$TARGET/$fpath"
  if [ "$fowned" != "true" ]; then
    printf '%s\n' "$fpath" >> "$WORK/left.txt"
    left_count=$((left_count+1))
    continue
  fi
  if [ ! -e "$p" ]; then
    if [ -z "$already_gone" ]; then already_gone="$fpath"; else already_gone="$already_gone, $fpath"; fi
    continue
  fi
  sha=$(ceos_sha256 "$p")
  if [ "$sha" != "$fsha" ]; then
    printf '%s\n' "$fpath" >> "$WORK/preserved.txt"
    preserved_count=$((preserved_count+1))
    continue
  fi
  chmod u+w "$p" 2>/dev/null
  rm -f "$p"
  removed_count=$((removed_count+1))
done < "$WORK/files.tsv"

# prune now-empty directories that the install created (never removes non-empty dirs)
for d in ".claude/agents" ".claude/rules" ".counsel/work/tickets" ".counsel/work" ".counsel/session"; do
  dp="$TARGET/$d"
  if [ -d "$dp" ] && [ -z "$(ls -A "$dp" 2>/dev/null)" ]; then
    rmdir "$dp" 2>/dev/null
  fi
done

# archive the manifest (audit trail), then remove the live copy
STAMP=$(ceos_stamp)
ARCHIVE_DIR="$TARGET/.counsel/originals/uninstall-$STAMP"
mkdir -p "$ARCHIVE_DIR"
cp "$MANIFEST_PATH" "$ARCHIVE_DIR/manifest.json"
rm -f "$MANIFEST_PATH"

printf 'UNINSTALL: removed %s counsel-owned file(s).\n' "$removed_count"
if [ "$preserved_count" -gt 0 ]; then
  printf 'PRESERVED locally-modified owned file(s) (%s) - user work is never deleted:\n' "$preserved_count"
  while IFS= read -r line; do printf '  = %s\n' "$line"; done < "$WORK/preserved.txt"
fi
if [ "$left_count" -gt 0 ]; then
  printf 'LEFT user-owned file(s) (%s):\n' "$left_count"
  while IFS= read -r line; do printf '  = %s\n' "$line"; done < "$WORK/left.txt"
fi
if [ -n "$already_gone" ]; then
  printf 'Already absent: %s\n' "$already_gone"
fi
printf 'Manifest archived: %s/manifest.json\n' "$ARCHIVE_DIR"
printf 'App code untouched. Session state and originals preserved.\n'
exit 0
