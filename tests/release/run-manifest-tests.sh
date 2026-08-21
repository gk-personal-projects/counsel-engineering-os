#!/usr/bin/env bash
# run-manifest-tests.sh - release coherence gate.
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-manifest-tests.ps1 (POSIX port).
# Dependencies: bash 3.2+, git, python3 (JSON parsing per the port ruling).
# Exit codes: 0 all pass | 1 any fail.
#
# WHY THIS EXISTS. 0.1.6 shipped with VERSION=0.1.6 and plugin.json=0.1.5. Releases
# 0.1.1 through 0.1.5 were all coherent; the sixth broke silently because nothing
# asserted the contract that docs/DISTRIBUTION.md states in plain words:
#
#     "VERSION governs; plugin.json mirrors it."
#
# The consequence was not cosmetic. Claude Code names the plugin cache directory from
# plugin.json, while the install manifest stamps runtime_version from VERSION. When
# they disagree, scripts/doctor.sh compares the two and reports RUNTIME VERSION SKEW
# on a clean, correct install - forever. A diagnostic that cries wolf is worse than no
# diagnostic, and this OS is built on the claim that its gates can be trusted.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

command -v python3 >/dev/null 2>&1 || { echo "python3 not found on PATH - required by this suite" >&2; exit 1; }

pass=0; fail=0; skipped=0
assert() { # $1 = 0/nonzero condition result, $2 name, $3 detail (printed on FAIL only)
  if [ "$1" -eq 0 ]; then printf 'PASS  %s\n' "$2"; pass=$((pass+1))
  else
    printf 'FAIL  %s\n' "$2"
    [ -n "${3:-}" ] && printf '        %s\n' "$3"
    fail=$((fail+1))
  fi
}
# A skip is not a pass. It is counted and printed separately so that a contract which
# silently stops being checked cannot masquerade as a contract that is holding.
skip() {
  printf 'SKIP  %s\n' "$1"
  printf '        %s\n' "$2"
  skipped=$((skipped+1))
}

echo ""

# --- M1: the stated contract ---------------------------------------------------------
version=$(tr -d ' \t\r\n' < "$ROOT/VERSION")
plugin_path="$ROOT/.claude-plugin/plugin.json"
plugin_info=$(python3 - "$plugin_path" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8-sig"))
print(p.get("name", "") or "")
print(p.get("version", "") or "")
print(p.get("skills", "") or "")
PY
) || { echo "FAIL  M1 plugin.json parse" >&2; exit 1; }
plugin_name=$(printf '%s\n' "$plugin_info" | sed -n 1p)
plugin_version=$(printf '%s\n' "$plugin_info" | sed -n 2p)
plugin_skills=$(printf '%s\n' "$plugin_info" | sed -n 3p)
ok=1; [ "$plugin_version" = "$version" ] && ok=0
assert $ok "M1 plugin.json version mirrors VERSION" "VERSION=$version plugin.json=$plugin_version"

# --- M2: VERSION is semver-shaped, because doctor version-sorts the cache dir names --
ok=1; printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && ok=0
assert $ok "M2 VERSION is semver-shaped" "got '$version'"

# --- M3: every JSON manifest parses (a BOM broke this once - see 0a0ec58) ------------
bad_json=$(python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
bad = []
for dirpath, dirnames, filenames in os.walk(root):
    if ".git" in dirnames:
        dirnames.remove(".git")
    for f in sorted(filenames):
        if f.endswith(".json"):
            p = os.path.join(dirpath, f)
            try:
                with open(p, encoding="utf-8-sig") as fh:
                    json.load(fh)
            except Exception:
                bad.append(os.path.relpath(p, root))
print(", ".join(bad))
PY
)
ok=1; [ -z "$bad_json" ] && ok=0
assert $ok "M3 every JSON manifest parses" "$bad_json"

# --- M4: plugin.json declares the fields the harness reads ---------------------------
ok=1; [ -n "$plugin_name" ] && [ -n "$plugin_version" ] && [ -n "$plugin_skills" ] && ok=0
assert $ok "M4 plugin.json has name, version, skills"
skills_rel=$(printf '%s\n' "$plugin_skills" | sed 's|^\./||')
ok=1; [ -e "$ROOT/$skills_rel" ] && ok=0
assert $ok "M4 plugin.json skills path resolves" "$plugin_skills"

# --- M5: marketplace manifest is coherent with the plugin ----------------------------
mkt_info=$(python3 - "$ROOT/.claude-plugin/marketplace.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8-sig"))
plugins = m.get("plugins") or []
print(len(plugins))
print(plugins[0].get("name", "") if plugins else "")
PY
)
mkt_count=$(printf '%s\n' "$mkt_info" | sed -n 1p)
mkt_first_name=$(printf '%s\n' "$mkt_info" | sed -n 2p)
ok=1; [ "$mkt_count" -ge 1 ] 2>/dev/null && ok=0
assert $ok "M5 marketplace declares at least one plugin"
ok=1; [ "$mkt_first_name" = "$plugin_name" ] && ok=0
assert $ok "M5 marketplace plugin name matches plugin.json" "$mkt_first_name vs $plugin_name"

# --- M6: every shipped skill is loadable ---------------------------------------------
m6=$(python3 - "$ROOT/$skills_rel" <<'PY'
import io, os, sys
root = sys.argv[1]
dirs = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
bad = []
for d in dirs:
    s = os.path.join(root, d, "SKILL.md")
    if not os.path.exists(s):
        bad.append(d + ": no SKILL.md")
        continue
    with io.open(s, encoding="utf-8-sig", errors="replace") as fh:
        head = [fh.readline().rstrip("\r\n") for _ in range(10)]
    if head[0] != "---":
        bad.append(d + ": no frontmatter")
    elif not any(l.startswith("name:") for l in head):
        bad.append(d + ": no name:")
    elif not any(l.startswith("description:") for l in head):
        bad.append(d + ": no description:")
print(len(dirs))
print("; ".join(bad))
PY
)
skill_count=$(printf '%s\n' "$m6" | sed -n 1p)
bad_skills=$(printf '%s\n' "$m6" | sed -n 2p)
ok=1; [ -z "$bad_skills" ] && ok=0
assert $ok "M6 all $skill_count skills have valid frontmatter" "$bad_skills"

# --- M7: the changelog records the version being shipped -----------------------------
ok=1; grep -Fq "$version" "$ROOT/CHANGELOG.md" && ok=0
assert $ok "M7 CHANGELOG mentions the current VERSION" "$version"

# --- M8: the version being shipped is tagged in CANONICAL ----------------------------
#     WHY. 0.1.9 was published with the public build tagged counsel--v0.1.9 while
#     canonical carried no such tag: publish tagged the generated snapshot and
#     nothing tagged the source. docs/RELEASE-SYNC.md section 2.2 states the contract in
#     plain words - "every public tag traces to one canonical commit" - and for one
#     release that sentence was simply false.
#
#     M1 already proves VERSION == plugin.json. This proves VERSION == canonical tag.
#
#     SKIPPED, deliberately, when there is no .git: the suite also runs INSIDE the
#     generated snapshot (publish step 3), where no repository exists yet and tag
#     coherence is not a property the snapshot can have. Skipping is correct there;
#     failing would make the publish pipeline unable to verify its own artifact.
if [ ! -e "$ROOT/.git" ]; then
  skip "M8 canonical tag counsel--v$version exists" "no .git here - canonical-only contract (this is the generated snapshot)"
else
  tag=$(git -C "$ROOT" tag --list "counsel--v$version")
  ok=1; [ -n "$tag" ] && ok=0
  assert $ok "M8 canonical tag counsel--v$version exists" \
    "VERSION=$version but canonical has no counsel--v$version tag. Tag the release commit and push the tag; do not rely on the snapshot's tag."
fi

echo ""
suffix=""
[ "$skipped" -gt 0 ] && suffix=", $skipped skipped"
echo "MANIFEST TESTS: $pass passed, $fail failed$suffix"
if [ "$fail" -gt 0 ]; then exit 1; fi
exit 0
