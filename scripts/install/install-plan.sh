#!/usr/bin/env bash
# Counsel Engineering OS -- deterministic install planner (POSIX port).
# Provenance: ORIGINAL (Apache-2.0). Same contract as install-plan.ps1 (POSIX port).
# Implements D-T2-026 R5-S2 steps 1-4: inspect target -> render full staged file
# set -> classify -> emit PLAN.json. NEVER writes into the target project.
# Apply is a separate consented step (install-apply.sh).
#
# Classes: CREATE   target file absent
#          PRESERVE target exists and is byte-identical to staged content (no-op)
#          MERGE    target exists and differs; requires explicit approval to apply
#          CONFLICT target is counsel-OWNED per manifest but locally modified;
#                   never auto-applied -- resolve, then re-plan
# Behavior contract: writes only under -StageDir (default ${TMPDIR:-/tmp}). Network: none.
# Dependencies: bash 3.2+, coreutils, python3 (JSON + staging engine; see docs).
# Exit codes: 0 = plan written; 1 = failure (message on stderr).

. "$(dirname "$0")/../lib/common.sh"

TARGET=""
LAYERS="core"
SOURCE=""
STAGE_DIR=""
CLAUDE_MD_CONTENT_PATH=""
MODE="pair"
INSTALL_SETTINGS_BASELINE="yes"
HARNESS="claude"

while [ $# -gt 0 ]; do
  case "$1" in
    -Target|--target)                   TARGET="${2:?missing value for $1}"; shift 2 ;;
    -Layers|--layers)                   LAYERS="${2:?missing value for $1}"; shift 2 ;;
    -Source|--source)                   SOURCE="${2:?missing value for $1}"; shift 2 ;;
    -StageDir|--stage-dir)              STAGE_DIR="${2:?missing value for $1}"; shift 2 ;;
    -ClaudeMdContentPath|--claude-md-content-path) CLAUDE_MD_CONTENT_PATH="${2:?missing value for $1}"; shift 2 ;;
    -Mode|--mode)                       MODE="${2:?missing value for $1}"; shift 2 ;;
    -InstallSettingsBaseline|--install-settings-baseline) INSTALL_SETTINGS_BASELINE="${2:?missing value for $1}"; shift 2 ;;
    -Harness|--harness)                 HARNESS="${2:?missing value for $1}"; shift 2 ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$TARGET" ] || ceos_die "Missing required argument: -Target"

ceos_require_python3

[ -d "$TARGET" ] || ceos_die "Target not found: $TARGET"
TARGET=$(ceos_resolve_dir "$TARGET") || ceos_die "Target not found: $TARGET"

# --- resolve runtime source ------------------------------------------------
if [ -z "$SOURCE" ]; then
  CACHE_ROOT=$(ceos_plugin_cache_root)
  [ -d "$CACHE_ROOT" ] || ceos_die "No -Source given and no installed counsel plugin at $CACHE_ROOT"
  SOURCE=$(ceos_newest_semver_dir "$CACHE_ROOT")
  [ -n "$SOURCE" ] || ceos_die "No semver-shaped release dir in plugin cache: $CACHE_ROOT (pass -Source)"
fi
[ -d "$SOURCE" ] || ceos_die "Source not found: $SOURCE"
SOURCE=$(ceos_resolve_dir "$SOURCE") || ceos_die "Source not found: $SOURCE"

HARNESS=$(printf '%s' "$HARNESS" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
case "$HARNESS" in
  claude|cursor|codex) : ;;
  *) ceos_die "Unknown harness: $HARNESS (claude|cursor|codex)" ;;
esac

for REQ in "runtime/rules" "scaffold/session" "scaffold/work" "scaffold/SCHEMA-VERSION" "VERSION"; do
  [ -e "$SOURCE/$REQ" ] || ceos_die "Source is missing required piece: $REQ (at $SOURCE)"
done

# Model alias map is Claude-adapter data. Non-claude harnesses use the semantic
# class names themselves as effort guidance (runtime/HARNESS.md); the synthetic
# identity map for those lives in the python stager below.
MM_PATH=""
if [ "$HARNESS" = "claude" ]; then
  MM_PATH="$SOURCE/adapters/claude/model-map.json"
  [ -e "$MM_PATH" ] || MM_PATH="$SOURCE/registry/model-map.json"   # pre-0.1.5 source
  [ -e "$MM_PATH" ] || ceos_die "Source is missing model-map.json (adapters/claude/ or registry/)"
fi

if [ -z "$STAGE_DIR" ]; then
  STAGE_DIR="${TMPDIR:-/tmp}/counsel-install/stage-$(ceos_stamp)"
fi
mkdir -p "$STAGE_DIR" || ceos_die "Cannot create stage dir: $STAGE_DIR"

# --- stage + classify + emit (python3 is the JSON/templating engine) --------
CEOS_TARGET="$TARGET" \
CEOS_SOURCE="$SOURCE" \
CEOS_STAGE_DIR="$STAGE_DIR" \
CEOS_LAYERS="$LAYERS" \
CEOS_MODE="$MODE" \
CEOS_HARNESS="$HARNESS" \
CEOS_ISB="$INSTALL_SETTINGS_BASELINE" \
CEOS_CMD_PATH="$CLAUDE_MD_CONTENT_PATH" \
CEOS_MM_PATH="$MM_PATH" \
CEOS_NOW="$(ceos_now_iso)" \
python3 - <<'PY'
import hashlib
import json
import os
import re
import sys


def die(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)


def read_text(path):
    # Raw bytes -> str: no newline translation, no trailing-newline stripping,
    # no BOM handling changes. Mirrors PS Read-Text.
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def write_file(path, content):
    # Mirrors PS Write-FileSafe: mkdir -p parent, clear read-only, UTF-8 no BOM.
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    if os.path.exists(path):
        try:
            os.chmod(path, 0o644)
        except OSError:
            pass
        os.remove(path)
    with open(path, "wb") as f:
        f.write(content.encode("utf-8"))


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


env = os.environ
target = env["CEOS_TARGET"]
source = env["CEOS_SOURCE"]
stage_dir = env["CEOS_STAGE_DIR"]
layers_csv = env["CEOS_LAYERS"]
mode = env["CEOS_MODE"]
harness = env["CEOS_HARNESS"]
install_settings_baseline = env["CEOS_ISB"]
claude_md_content_path = env["CEOS_CMD_PATH"]
mm_path = env["CEOS_MM_PATH"]
now_iso = env["CEOS_NOW"]

runtime_version = read_text(os.path.join(source, "VERSION")).strip()
cp_schema = read_text(os.path.join(source, "scaffold", "SCHEMA-VERSION")).strip()

if harness == "claude":
    model_map = json.loads(read_text(mm_path))
else:
    model_map = {
        "placeholders": {
            "{{MODEL_ECONOMY}}": "ECONOMY",
            "{{MODEL_STANDARD}}": "STANDARD",
            "{{MODEL_DEEP}}": "DEEP-REASONING",
        },
        "classes": {
            "ECONOMY": "ECONOMY",
            "STANDARD": "STANDARD",
            "DEEP-REASONING": "DEEP-REASONING",
        },
        "fallback": "STANDARD",
    }

warnings = []
layer_list = [p.strip().lower() for p in layers_csv.split(",")]
layer_list = [p for p in layer_list if p]
for l in layer_list:
    if l not in ("core", "builder", "engineering", "full"):
        die("Unknown layer: " + l)
if "core" not in layer_list:
    layer_list = ["core"] + layer_list


def list_files(d, suffix=None):
    # Non-recursive file listing, name-sorted (case-insensitive, like GCI).
    out = []
    for name in sorted(os.listdir(d), key=lambda n: n.lower()):
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            continue
        if suffix is not None and not name.lower().endswith(suffix):
            continue
        out.append((name, p))
    return out


def resolve_model_placeholders(text):
    out = text
    placeholders = model_map.get("placeholders") or {}
    classes = model_map.get("classes") or {}
    fallback = model_map.get("fallback")
    for ph_name, cls in placeholders.items():
        value = classes.get(cls)
        if not value:
            value = fallback
            warnings.append("Model class '%s' unmapped; used fallback '%s'" % (cls, value))
        out = out.replace(ph_name, value)
    if re.search(r"\{\{MODEL_[A-Z_]+\}\}", out):
        warnings.append(
            "Unknown model placeholder remained; replaced with fallback '%s'" % fallback
        )
        out = re.sub(r"\{\{MODEL_[A-Z_]+\}\}", fallback, out)
    return out


staged = []  # dicts: rel, owned, [region_sha], [settings]


def stage_file(rel, content):
    write_file(os.path.join(stage_dir, rel), content)
    return rel


# 1. Rules (counsel-OWNED after install) -> harness-neutral home .counsel/rules/.
#    Always-on delivery happens via the AGENTS.md sentinel block (step 5); these
#    on-disk copies serve on-demand loading, doctor integrity, non-claude harnesses.
for name, p in list_files(os.path.join(source, "runtime", "rules"), ".md"):
    staged.append({"rel": stage_file(".counsel/rules/" + name, read_text(p)), "owned": True})

# 2. Agents per layer (counsel-OWNED; model placeholders resolved per R3)
tier_map = {
    "builder": ["builder"],
    "engineering": ["builder", "engineering"],
    "full": ["builder", "engineering", "full"],
}
tiers = []
for l in layer_list:
    for t in tier_map.get(l, []):
        if t not in tiers:
            tiers.append(t)
agents_dir = ".claude/agents/" if harness == "claude" else ".counsel/agents/"
for tier in tiers:
    tier_dir = os.path.join(source, "runtime", "agents", tier)
    if not os.path.isdir(tier_dir):
        warnings.append("Tier dir missing in source: " + tier)
        continue
    for name, p in list_files(tier_dir, ".md"):
        staged.append({
            "rel": stage_file(agents_dir + name, resolve_model_placeholders(read_text(p))),
            "owned": True,
        })

# 3. .counsel/config.yaml (control plane, user-owned)
classes = model_map.get("classes") or {}
cfg = read_text(os.path.join(source, "scaffold", "templates", "config.yaml.template"))
cfg = cfg.replace("{{CONTROL_PLANE_SCHEMA}}", cp_schema)
cfg = cfg.replace("{{RUNTIME_VERSION}}", runtime_version)
cfg = cfg.replace("{{LAYERS}}", ", ".join(layer_list))
cfg = cfg.replace("{{MODE}}", mode)
cfg = cfg.replace("{{HARNESS}}", harness)
cfg = cfg.replace("{{MODEL_ECONOMY_VALUE}}", classes.get("ECONOMY") or "")
cfg = cfg.replace("{{MODEL_STANDARD_VALUE}}", classes.get("STANDARD") or "")
cfg = cfg.replace("{{MODEL_DEEP_VALUE}}", classes.get("DEEP-REASONING") or "")
staged.append({"rel": stage_file(".counsel/config.yaml", cfg), "owned": False})

# 4. Session + work scaffolds (counsel-OWNED templates)
for name, p in list_files(os.path.join(source, "scaffold", "session")):
    staged.append({"rel": stage_file(".counsel/session/" + name, read_text(p)), "owned": True})
work_root = os.path.join(source, "scaffold", "work")
for dirpath, dirnames, filenames in os.walk(work_root):
    dirnames.sort(key=lambda n: n.lower())
    for fn in sorted(filenames, key=lambda n: n.lower()):
        full = os.path.join(dirpath, fn)
        rel_part = os.path.relpath(full, work_root).replace(os.sep, "/")
        staged.append({"rel": stage_file(".counsel/work/" + rel_part, read_text(full)), "owned": True})

# 5. AGENTS.md constitution (control plane, user-owned; content composed
#    conversationally). The Counsel always-on rules ride inside a
#    sentinel-delimited region managed by the installer; user content outside
#    the region is never touched on update.
sentinel_begin_line = (
    "<!-- counsel:rules v" + runtime_version + " begin"
    " -- Counsel-owned always-on rules. Managed by the installer; edits inside"
    " this block are overwritten on update. Put project-specific law ABOVE this block. -->"
)
sentinel_end = "<!-- counsel:rules end -->"
always_on_rules = [
    "authority.md", "evidence.md", "orchestration.md",
    "cost-governor.md", "work-control.md", "safety-base.md",
]
rules_block = ""
for r in always_on_rules:
    rp = os.path.join(source, "runtime", "rules", r)
    if os.path.exists(rp):
        rules_block += read_text(rp).rstrip() + "\n\n"
    else:
        warnings.append("Always-on rule missing in source: " + r)
rules_block = rules_block.rstrip()

constitution_base = None
if claude_md_content_path:
    if not os.path.exists(claude_md_content_path):
        die("ClaudeMdContentPath not found: " + claude_md_content_path)
    constitution_base = read_text(claude_md_content_path)
elif os.path.exists(os.path.join(target, "AGENTS.md")):
    # Update path: refresh the sentinel region inside the user's constitution.
    constitution_base = read_text(os.path.join(target, "AGENTS.md"))

if constitution_base is not None:
    region_text = sentinel_begin_line + "\n" + rules_block + "\n" + sentinel_end
    region_pattern = re.compile(
        r"<!-- counsel:rules v[^\r\n]*begin.*?<!-- counsel:rules end -->", re.S
    )
    if region_pattern.search(constitution_base):
        agents_md = region_pattern.sub(lambda m: region_text, constitution_base)
    elif "{{ALWAYS_ON_RULES_CONTENT}}" in constitution_base:
        agents_md = constitution_base.replace("{{ALWAYS_ON_RULES_CONTENT}}", rules_block)
        if not region_pattern.search(agents_md):
            agents_md = agents_md + "\n" + region_text + "\n"
    else:
        agents_md = constitution_base.rstrip() + "\n\n" + region_text + "\n"
    agents_md = agents_md.replace("{{RUNTIME_VERSION}}", runtime_version)
    agents_md = agents_md.replace("{{HARNESS}}", harness)
    if len(agents_md.encode("utf-8")) > 32768:
        warnings.append(
            "AGENTS.md exceeds 32 KiB -- Codex truncates beyond this;"
            " trim project content or rules"
        )
    region_sha = hashlib.sha256(region_text.encode("utf-8")).hexdigest()
    staged.append({"rel": stage_file("AGENTS.md", agents_md), "owned": False,
                   "region_sha": region_sha})
    if harness == "claude":
        shim = read_text(os.path.join(source, "scaffold", "templates", "CLAUDE.md.template"))
        staged.append({"rel": stage_file("CLAUDE.md", shim), "owned": False})
else:
    warnings.append(
        "No constitution content (-ClaudeMdContentPath) and no existing AGENTS.md"
        " -- always-on rules will only exist under .counsel/rules/, not in a constitution"
    )

# 5b. Skills for harnesses without a plugin channel (counsel-OWNED copies)
if harness != "claude":
    skills_root = os.path.join(source, "runtime", "skills")
    skills_target_dir = ".codex/skills/" if harness == "codex" else ".cursor/skills/"
    if os.path.exists(skills_root):
        for name in sorted(os.listdir(skills_root), key=lambda n: n.lower()):
            d = os.path.join(skills_root, name)
            if not os.path.isdir(d):
                continue
            sk = os.path.join(d, "SKILL.md")
            if os.path.exists(sk):
                staged.append({
                    "rel": stage_file(skills_target_dir + name + "/SKILL.md", read_text(sk)),
                    "owned": True,
                })

# 5c. Cursor rule emission (.mdc) per adapters/cursor/rules-map.json (counsel-OWNED)
if harness == "cursor":
    rm_path = os.path.join(source, "adapters", "cursor", "rules-map.json")
    if os.path.exists(rm_path):
        rules_map = json.loads(read_text(rm_path))
        for key, val in (rules_map.get("rules") or {}).items():
            src_rule = os.path.join(source, "runtime", "rules", key)
            if not os.path.exists(src_rule):
                warnings.append("rules-map references missing rule: " + key)
                continue
            fm = "---\n"
            if val.get("description"):
                fm += "description: %s\n" % val["description"]
            if val.get("globs"):
                fm += "globs: %s\n" % val["globs"]
            fm += "alwaysApply: %s\n---\n" % ("true" if val.get("alwaysApply") else "false")
            mdc_name = "counsel-" + re.sub(r"\.md$", "", key) + ".mdc"
            staged.append({
                "rel": stage_file(".cursor/rules/" + mdc_name, fm + read_text(src_rule)),
                "owned": True,
            })
    else:
        warnings.append(
            "cursor harness: adapters/cursor/rules-map.json missing in source;"
            " no .mdc rules emitted (AGENTS.md still carries always-on rules)"
        )

# 6. .claude/settings.json proposal (claude only; user-owned; ALWAYS approval-gated)
if harness == "claude" and install_settings_baseline == "yes":
    baseline = json.loads(
        read_text(os.path.join(source, "scaffold", "templates", "settings-baseline.json"))
    )
    target_settings_path = os.path.join(target, ".claude", "settings.json")
    if os.path.exists(target_settings_path):
        try:
            existing = json.loads(read_text(target_settings_path))
        except Exception as e:
            die("Existing .claude/settings.json unreadable: %s" % e)
        if not existing.get("permissions"):
            existing["permissions"] = {}
        for kind in ("deny", "ask"):
            cur = list(existing["permissions"].get(kind) or [])
            add = [e for e in ((baseline.get("permissions") or {}).get(kind) or [])
                   if e not in cur]
            existing["permissions"][kind] = cur + add
        proposed = json.dumps(existing, indent=2)
    else:
        proposed = json.dumps({"permissions": baseline["permissions"]}, indent=2)
    staged.append({"rel": stage_file(".claude/settings.json", proposed), "owned": False,
                   "settings": True})

# 7. .gitignore additions (user-owned merge)
gi_lines = [".counsel/session/", ".counsel/originals/", ".counsel/install/",
            ".counsel/credential-liveness.json"]
gi_path = os.path.join(target, ".gitignore")
gi_existing = read_text(gi_path) if os.path.exists(gi_path) else ""
gi_new = gi_existing
if gi_new and not gi_new.endswith("\n"):
    gi_new += "\n"
existing_lines = re.split(r"\r?\n", gi_existing)
for line in gi_lines:
    if line not in existing_lines:
        gi_new += line + "\n"
staged.append({"rel": stage_file(".gitignore", gi_new), "owned": False})

# --- classify ---------------------------------------------------------------
manifest_path = os.path.join(target, ".counsel", "manifest.json")
owned_by_manifest = {}
if os.path.exists(manifest_path):
    try:
        mf = json.loads(read_text(manifest_path))
        for f in (mf.get("files") or []):
            if f.get("owned"):
                owned_by_manifest[f.get("path")] = f.get("sha256")
    except Exception as e:
        warnings.append("Existing manifest unreadable: %s" % e)

items = []
for s in staged:
    rel = s["rel"]
    staged_path = os.path.join(stage_dir, rel)
    target_path = os.path.join(target, rel)
    sha_staged = sha_file(staged_path)
    sha_target = None
    approved = None
    note = ""
    if not os.path.exists(target_path):
        cls = "CREATE"
        approved = True
    else:
        sha_target = sha_file(target_path)
        if sha_target == sha_staged:
            cls = "PRESERVE"
        elif rel in owned_by_manifest:
            if owned_by_manifest[rel] != sha_target:
                cls = "CONFLICT"
                note = "counsel-owned file locally modified; resolve then re-plan"
            else:
                cls = "MERGE"
                approved = False
                note = "owned file changed upstream; approval = accept update"
        else:
            cls = "MERGE"
            approved = False
            note = "pre-existing user file; requires explicit approval"
    if s.get("settings"):
        if cls == "CREATE":
            approved = False
            note = "PERMISSION CHANGE: requires explicit approval (never silent)"
        if cls == "MERGE":
            note = "PERMISSION CHANGE: " + note
    item = {"path": rel, "class": cls, "owned": bool(s["owned"]),
            "sha_staged": sha_staged, "sha_target": sha_target,
            "approved": approved, "note": note}
    if s.get("region_sha"):
        item["region_sha"] = s["region_sha"]
    items.append(item)

# 8. Migration removals: counsel-owned files from pre-0.1.5 installs whose home
#    moved (.claude/rules/ -> AGENTS.md sentinel + .counsel/rules/).
#    Approval-gated; unmodified-only.
staged_rels = [s["rel"] for s in staged]
for owned_path in owned_by_manifest:
    if owned_path.startswith(".claude/rules/") and owned_path not in staged_rels:
        tp = os.path.join(target, owned_path)
        if os.path.exists(tp):
            sha_t = sha_file(tp)
            if sha_t == owned_by_manifest[owned_path]:
                items.append({
                    "path": owned_path, "class": "REMOVE", "owned": True,
                    "sha_staged": None, "sha_target": sha_t, "approved": False,
                    "note": "pre-0.1.5 always-on rule copy; now delivered via"
                            " AGENTS.md sentinel block + .counsel/rules/"
                            " (approval = remove, backed up)",
                })
            else:
                items.append({
                    "path": owned_path, "class": "CONFLICT", "owned": True,
                    "sha_staged": None, "sha_target": sha_t, "approved": None,
                    "note": "counsel-owned legacy rule locally modified;"
                            " resolve then re-plan",
                })

plan = {
    "schema_version": 1,
    "created": now_iso,
    "source": source,
    "runtime_version": runtime_version,
    "control_plane_schema": cp_schema,
    "target": target,
    "layers": layer_list,
    "mode": mode,
    "harness": harness,
    "stage_dir": stage_dir,
    "warnings": warnings,
    "items": items,
}
plan_path = os.path.join(stage_dir, "PLAN.json")
write_file(plan_path, json.dumps(plan, indent=2))

counts = {}
for i in items:
    counts[i["class"]] = counts.get(i["class"], 0) + 1
print("PLAN written: " + plan_path)
print("Items: " + "  ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)))
for w in warnings:
    print("WARN  " + w)
for i in items:
    suffix = ("  -- " + i["note"]) if i["note"] else ""
    print("  %-9s %s%s" % (i["class"], i["path"], suffix))
sys.exit(0)
PY
exit $?
