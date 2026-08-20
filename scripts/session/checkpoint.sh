#!/usr/bin/env sh
# Counsel Engineering OS — atomic session checkpoint (POSIX sh).
# Provenance: ORIGINAL (Apache-2.0). Same contract as checkpoint.ps1 (D-T2-018):
# tmp -> capture -> validate -> promote -> only then update pointer. On failure the previous
# valid checkpoint stays authoritative; the attempt is preserved as FAILED-* with FAILURE.txt.
# Dependencies: git, coreutils only. Network: none. Exit: 0 success, 1 failure.

set -u
WORKSPACE="${1:-$(pwd)}"
SESSION_DIR="${2:-$WORKSPACE/.counsel/session}"
LABEL="${3:-manual}"

[ -d "$SESSION_DIR" ] || { echo "Session dir not found: $SESSION_DIR" >&2; exit 1; }
CP_ROOT="$SESSION_DIR/CHECKPOINTS"
mkdir -p "$CP_ROOT"

for d in "$CP_ROOT"/.tmp-* "$CP_ROOT"/FAILED-*; do
  [ -d "$d" ] && echo "WARNING: residue from prior incomplete/failed attempt: $(basename "$d")" >&2
done

STAMP=$(date +%Y%m%d-%H%M%S)
TMP="$CP_ROOT/.tmp-$STAMP-$LABEL"
FINAL="$CP_ROOT/$STAMP-$LABEL"
mkdir -p "$TMP"
FAIL_FILE="$TMP/.failreasons"
: > "$FAIL_FILE"

# --- capture session files
for name in RESTORE.md STATE.json DECISIONS.md OPEN-ITEMS.md ARTIFACT-REGISTRY.md CAPSULE.md; do
  [ -f "$SESSION_DIR/$name" ] && cp "$SESSION_DIR/$name" "$TMP/$name"
done
for name in RESTORE.md STATE.json; do
  if [ -f "$SESSION_DIR/$name" ] && [ ! -f "$TMP/$name" ]; then
    echo "Required session file failed to copy: $name" >> "$FAIL_FILE"
  fi
done

# --- capture git state (workspace itself + first-level children), dedupe by resolved root
MS="$TMP/MACHINE-STATE.json"
SEEN="$TMP/.seenroots"
: > "$SEEN"
{
  printf '{\n  "schema_version": 2,\n  "timestamp_local": "%s",\n  "label": "%s",\n  "workspace": "%s",\n  "repositories": [\n' \
    "$(date -Iseconds)" "$LABEL" "$WORKSPACE"
  first=1
  for cand in "$WORKSPACE" "$WORKSPACE"/*/; do
    cand="${cand%/}"
    [ -e "$cand/.git" ] || continue
    top=$(git -C "$cand" rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$top" ]; then
      echo "Repository capture error at '$cand': git cannot resolve repository" >> "$FAIL_FILE"
      continue
    fi
    case "$(cat "$SEEN")" in *"|$top|"*) continue;; esac
    printf '|%s|' "$top" >> "$SEEN"
    branch=$(git -C "$top" branch --show-current 2>/dev/null)
    head=$(git -C "$top" rev-parse --verify HEAD 2>/dev/null) || head=""
    dirty=$(git -C "$top" status --short 2>/dev/null | wc -l | tr -d ' ')
    unborn=false; headjson="\"$head\""
    [ -z "$head" ] && { unborn=true; headjson=null; }
    [ $first -eq 0 ] && printf ',\n'
    first=0
    printf '    { "root": "%s", "branch": "%s", "head": %s, "unborn": %s, "dirty": %s }' \
      "$top" "$branch" "$headjson" "$unborn" "$dirty"
  done
  printf '\n  ]\n}\n'
} > "$MS"

# --- validate: HEAD re-verification for every recorded head
grep -o '"root": "[^"]*", "branch": "[^"]*", "head": "[0-9a-f]\{40\}"' "$MS" | while IFS= read -r line; do
  root=$(printf '%s' "$line" | sed 's/^"root": "\([^"]*\)".*/\1/')
  rec=$(printf '%s' "$line" | sed 's/.*"head": "\([0-9a-f]\{40\}\)".*/\1/')
  live=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null)
  [ "$live" = "$rec" ] || echo "HEAD drift during capture at '$root': recorded $rec, live $live" >> "$FAIL_FILE"
done

# --- promote or fail
rm -f "$SEEN"
if [ -s "$FAIL_FILE" ]; then
  mv "$FAIL_FILE" "$TMP/FAILURE.txt"
  mv "$TMP" "$CP_ROOT/FAILED-$STAMP-$LABEL"
  echo "CHECKPOINT FAILED — previous valid checkpoint remains authoritative." >&2
  sed 's/^/  - /' "$CP_ROOT/FAILED-$STAMP-$LABEL/FAILURE.txt" >&2
  exit 1
fi
rm -f "$FAIL_FILE"
mv "$TMP" "$FINAL"
printf '%s\n' "$FINAL" > "$SESSION_DIR/LAST-CHECKPOINT.txt.new" && mv -f "$SESSION_DIR/LAST-CHECKPOINT.txt.new" "$SESSION_DIR/LAST-CHECKPOINT.txt"
echo "Checkpoint created: $FINAL"
exit 0
