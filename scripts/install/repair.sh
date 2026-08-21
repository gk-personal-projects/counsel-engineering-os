#!/usr/bin/env bash
# Counsel Engineering OS -- repair (POSIX port).
# Provenance: ORIGINAL (Apache-2.0). Same contract as repair.ps1 (POSIX port).
# D-T2-026 S3: restores counsel-OWNED files from the SAME runtime version recorded
# in the ownership manifest. Reuses the tested install-plan/install-apply machinery --
# repair is a plan whose restorations are approved.
#   - missing owned files: restored
#   - locally-modified owned files: PRESERVED unless -IncludeModified (then backed up + restored)
#   - user-owned files (constitution, settings, config, .gitignore): NEVER touched
#   - source runtime version != manifest runtime version: STOP (that is an update, not a
#     repair -- run the onboard update flow instead). Ambiguity always stops (exit 1).
# Dependencies: git, coreutils, python3 (JSON), plus sibling install-plan.sh / install-apply.sh.
# Exit codes: 0 success, 1 failure (missing manifest, version lock, ambiguity, plan/apply failure).

set -u
SCRIPT_DIR=$(dirname "$0")
. "$SCRIPT_DIR/../lib/common.sh"

TARGET=""; SOURCE=""; INCLUDE_MODIFIED=0
while [ $# -gt 0 ]; do
  case "$1" in
    -Target|--target)   TARGET="${2:?missing value for $1}"; shift 2 ;;
    -Source|--source)   SOURCE="${2:?missing value for $1}"; shift 2 ;;
    -IncludeModified|--include-modified) INCLUDE_MODIFIED=1; shift ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$TARGET" ] || ceos_die "Missing required argument: -Target"

ceos_require_python3

RESOLVED=$(ceos_resolve_dir "$TARGET") || ceos_die "Target not found: $TARGET"
TARGET="$RESOLVED"
MANIFEST_PATH="$TARGET/.counsel/manifest.json"
[ -f "$MANIFEST_PATH" ] || ceos_die "No ownership manifest at $MANIFEST_PATH - nothing to repair against"

RUNTIME_VERSION=$(python3 - "$MANIFEST_PATH" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        mf = json.load(f)
except Exception as e:
    sys.stderr.write("Existing manifest unreadable: %s\n" % e)
    sys.exit(1)
v = mf.get("runtime_version", "")
print("" if v is None else v)
PY
)
[ $? -eq 0 ] || exit 1

# resolve source and enforce same-version repair
if [ -z "$SOURCE" ]; then
  CACHE_ROOT=$(ceos_plugin_cache_root)
  CANDIDATE="$CACHE_ROOT/$RUNTIME_VERSION"
  if [ -d "$CANDIDATE" ]; then
    SOURCE="$CANDIDATE"
  else
    NEWEST=$(ceos_newest_semver_dir "$CACHE_ROOT")
    if [ -n "$NEWEST" ]; then
      SOURCE="$NEWEST"
    else
      ceos_die "No source available for repair (no plugin cache; pass -Source)"
    fi
  fi
fi
RESOLVED=$(ceos_resolve_dir "$SOURCE") || ceos_die "Source not found: $SOURCE"
SOURCE="$RESOLVED"
[ -f "$SOURCE/VERSION" ] || ceos_die "Source is missing required piece: VERSION (at $SOURCE)"
SRC_VERSION=$(tr -d '[:space:]' < "$SOURCE/VERSION")
if [ "$SRC_VERSION" != "$RUNTIME_VERSION" ]; then
  echo "STOP: source runtime is $SRC_VERSION but the manifest records $RUNTIME_VERSION."
  echo "That is an UPDATE, not a repair. Run the onboard update flow (plan + consented apply)."
  exit 1
fi

# read installed layers + mode from config.yaml (control plane)
CFG_PATH="$TARGET/.counsel/config.yaml"
LAYERS="core"; MODE="pair"
if [ -f "$CFG_PATH" ]; then
  CFG_OUT=$(python3 - "$CFG_PATH" <<'PY'
import re, sys
with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
    text = f.read()
layers = "core"
mode = "pair"
m = re.search(r'^installed_layers:\s*\[([^\]]*)\]', text, re.M)
if m:
    layers = re.sub(r'\s', '', m.group(1))
m = re.search(r'^mode:\s*(\S+)', text, re.M)
if m:
    mode = m.group(1)
sys.stdout.write("L\t%s\n" % layers)
sys.stdout.write("M\t%s\n" % mode)
PY
)
  [ $? -eq 0 ] || ceos_die "Config read failed: $CFG_PATH"
  LAYERS=$(printf '%s\n' "$CFG_OUT" | awk -F '\t' '$1=="L"{print $2}')
  MODE=$(printf '%s\n' "$CFG_OUT" | awk -F '\t' '$1=="M"{print $2}')
fi

# plan against the version-locked source; keep the existing constitution out of scope
STAGE="${TMPDIR:-/tmp}/counsel-repair/stage-$(ceos_stamp)"
bash "$SCRIPT_DIR/install-plan.sh" \
  -Target "$TARGET" -Layers "$LAYERS" -Source "$SOURCE" -StageDir "$STAGE" \
  -Mode "$MODE" -InstallSettingsBaseline "no" >/dev/null
[ $? -eq 0 ] || ceos_die "Repair planning failed"

PLAN_PATH="$STAGE/PLAN.json"
# Mutate the plan: owned CREATEs are approved (restore), owned CONFLICTs restored
# only under -IncludeModified, user-owned proposals are force-declined, and any
# other owned state is ambiguous -- repair will not guess. Exit 3 = ambiguous
# (plan NOT written); tagged stdout lines: R=restored, P=preserved, A=ambiguous.
MUT_OUT=$(python3 - "$PLAN_PATH" "$INCLUDE_MODIFIED" <<'PY'
import json, sys
plan_path = sys.argv[1]
include_modified = sys.argv[2] == "1"
try:
    with open(plan_path, encoding='utf-8') as f:
        plan = json.load(f)
except Exception as e:
    sys.stderr.write("PLAN.json unreadable: %s\n" % e)
    sys.exit(1)
restored = []
preserved = []
ambiguous = []
for i in plan.get("items", []):
    cls = i.get("class")
    if not i.get("owned"):
        # user-owned staged items must never be applied by repair
        if cls in ("CREATE", "MERGE"):
            i["approved"] = False
        continue
    if cls == "CREATE":
        i["approved"] = True            # missing owned -> restore
        restored.append(i["path"])
    elif cls == "PRESERVE":
        pass
    elif cls == "CONFLICT":
        if include_modified:
            i["class"] = "MERGE"
            i["approved"] = True        # apply backs the original up
            restored.append(i["path"])
        else:
            preserved.append(i["path"])
    elif cls == "MERGE":
        # owned differing without local-mod evidence: ambiguous
        i["approved"] = False
        ambiguous.append(i["path"])
    else:
        ambiguous.append("%s (class %s)" % (i["path"], cls))
if ambiguous:
    for a in ambiguous:
        sys.stdout.write("A\t%s\n" % a)
    sys.exit(3)
with open(plan_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(plan, f, indent=2)
    f.write("\n")
for r in restored:
    sys.stdout.write("R\t%s\n" % r)
for p in preserved:
    sys.stdout.write("P\t%s\n" % p)
PY
)
MUT_RC=$?
if [ "$MUT_RC" -eq 3 ]; then
  echo "STOP: ambiguous ownership state - repair will not guess:"
  printf '%s\n' "$MUT_OUT" | awk -F '\t' '$1=="A"{print "  ! " $2}'
  exit 1
fi
[ "$MUT_RC" -eq 0 ] || exit 1

bash "$SCRIPT_DIR/install-apply.sh" -PlanPath "$PLAN_PATH"
[ $? -eq 0 ] || ceos_die "Repair apply failed"

RESTORED_COUNT=$(printf '%s\n' "$MUT_OUT" | awk -F '\t' '$1=="R"{n++} END{print n+0}')
PRESERVED_COUNT=$(printf '%s\n' "$MUT_OUT" | awk -F '\t' '$1=="P"{n++} END{print n+0}')

echo ""
echo "REPAIR: restored $RESTORED_COUNT owned file(s)."
if [ "$RESTORED_COUNT" -gt 0 ]; then
  printf '%s\n' "$MUT_OUT" | awk -F '\t' '$1=="R"{print "  + " $2}'
fi
if [ "$PRESERVED_COUNT" -gt 0 ]; then
  echo "Locally-modified owned files PRESERVED ($PRESERVED_COUNT) - rerun with -IncludeModified to restore (originals are backed up):"
  printf '%s\n' "$MUT_OUT" | awk -F '\t' '$1=="P"{print "  = " $2}'
fi
exit 0
