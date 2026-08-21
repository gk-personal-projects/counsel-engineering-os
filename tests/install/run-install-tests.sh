#!/usr/bin/env bash
# Counsel Engineering OS -- install plan/apply acceptance tests (POSIX port)
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-install-tests.ps1.
# Covers D-T2-026 R5-S2 requirements: plan-first, consent classes, no blind
# overwrite, permission approval gating, ownership manifest, atomic apply,
# post-verify, stale plan refusal, idempotency.
# Uses the repo itself as -Source so tests run pre-release.
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
work="${TMPDIR:-/tmp}/counsel-install-tests-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$work"

pass=0; fail=0
# assert <exit-status: 0 = condition true> <name>
assert() {
  if [ "$1" -eq 0 ]; then pass=$((pass+1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail+1)); printf 'FAIL  %s\n' "$2"; fi
}

# json_check <file> <python expression over parsed object d> -> exit 0 if truthy
json_check() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if eval(sys.argv[2]) else 1)
' "$1" "$2"
}

# set_item_approved <stage_dir> <path glob> <true|false>
# Flips "approved" on plan items whose path matches the glob (PS -like).
set_item_approved() {
  python3 -c '
import json, sys, fnmatch
p = sys.argv[1]
pl = json.load(open(p))
val = (sys.argv[3] == "true")
for i in pl["items"]:
    if fnmatch.fnmatch(i["path"], sys.argv[2]):
        i["approved"] = val
open(p, "w").write(json.dumps(pl, indent=2))
' "$1/PLAN.json" "$2" "$3"
}

# ---------- T1: fresh install (core+builder) --------------------------------
t1="$work/t1"; mkdir -p "$t1"
cm="$work/claude-md.txt"
printf '# TestProj -- Engineering Constitution\n(test content)\n' > "$cm"
s1="$work/stage1"
bash "$plan" -Target "$t1" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$s1" -ClaudeMdContentPath "$cm" >/dev/null
assert $? "T1 plan exits 0"
json_check "$s1/PLAN.json" 'len([i for i in d["items"] if i["class"] != "CREATE"]) == 0'
assert $? "T1 fresh target: every item is CREATE"
json_check "$s1/PLAN.json" '[i for i in d["items"] if i["path"] == ".claude/settings.json"][0]["approved"] is False'
assert $? "T1 settings.json CREATE is approval-gated (approved=false)"
bash "$apply" -PlanPath "$s1/PLAN.json" >/dev/null
assert $? "T1 apply exits 0"
[ -e "$t1/.counsel/rules/evidence.md" ]; assert $? "T1 rules installed (.counsel/rules)"
[ -e "$t1/.claude/agents/tech-lead.md" ]; assert $? "T1 builder agents installed"
[ ! -e "$t1/.claude/settings.json" ]; assert $? "T1 settings NOT written without approval"
[ -e "$t1/AGENTS.md" ]; assert $? "T1 AGENTS.md constitution created"
grep -q 'counsel:rules v.*begin' "$t1/AGENTS.md" && grep -q '<!-- counsel:rules end -->' "$t1/AGENTS.md"
assert $? "T1 sentinel rules block embedded"
grep -q 'DISCOVERED WORK' "$t1/AGENTS.md"
assert $? "T1 always-on rules content inside AGENTS.md"
[ -e "$t1/CLAUDE.md" ]; assert $? "T1 CLAUDE.md shim created"
head -n 1 "$t1/CLAUDE.md" | grep -q '^@AGENTS\.md'
assert $? "T1 shim first line is @AGENTS.md"
[ -e "$t1/.counsel/manifest.json" ]; assert $? "T1 manifest written"
json_check "$t1/.counsel/manifest.json" 'bool(d.get("runtime_version")) and bool(d.get("control_plane_schema"))'
assert $? "T1 manifest carries runtime + control-plane versions"
! grep -q '{{MODEL_' "$t1/.claude/agents/tech-lead.md"
assert $? "T1 model placeholders fully resolved"
ownedCount=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for f in d["files"] if f.get("owned")))' "$t1/.counsel/manifest.json")
[ "$ownedCount" -gt 10 ] 2>/dev/null
assert $? "T1 manifest records owned files ($ownedCount)"

# ---------- T2: idempotent re-run -------------------------------------------
s2="$work/stage2"
bash "$plan" -Target "$t1" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$s2" -ClaudeMdContentPath "$cm" >/dev/null
json_check "$s2/PLAN.json" 'len([i for i in d["items"] if i["class"] != "PRESERVE" and i["path"] != ".claude/settings.json"]) == 0'
assert $? "T2 re-plan: everything PRESERVE except declined settings"
bash "$apply" -PlanPath "$s2/PLAN.json" >/dev/null
assert $? "T2 idempotent apply exits 0"

# ---------- T3: explicit settings approval ----------------------------------
s3="$work/stage3"
bash "$plan" -Target "$t1" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$s3" -ClaudeMdContentPath "$cm" >/dev/null
set_item_approved "$s3" ".claude/settings.json" true
bash "$apply" -PlanPath "$s3/PLAN.json" >/dev/null
assert $? "T3 apply exits 0"
json_check "$t1/.claude/settings.json" '"Read(./.env)" in d["permissions"]["deny"]'
assert $? "T3 approved settings baseline applied"

# ---------- T4: modified owned file -> CONFLICT, untouched ------------------
evPath="$t1/.counsel/rules/evidence.md"
printf '\nLOCAL EDIT\n' >> "$evPath"
s4="$work/stage4"
bash "$plan" -Target "$t1" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$s4" -ClaudeMdContentPath "$cm" >/dev/null
json_check "$s4/PLAN.json" '[i for i in d["items"] if i["path"] == ".counsel/rules/evidence.md"][0]["class"] == "CONFLICT"'
assert $? "T4 locally-modified owned file classified CONFLICT"
bash "$apply" -PlanPath "$s4/PLAN.json" >/dev/null
grep -q 'LOCAL EDIT' "$evPath"
assert $? "T4 CONFLICT file left untouched by apply"

# ---------- T5: pre-existing user file needs approval -----------------------
t5="$work/t5"; mkdir -p "$t5"
printf "user's own file\n" > "$t5/CLAUDE.md"
s5="$work/stage5"
bash "$plan" -Target "$t5" -Layers "core" -Source "$REPO_ROOT" -StageDir "$s5" -ClaudeMdContentPath "$cm" >/dev/null
json_check "$s5/PLAN.json" '(lambda i: i["class"] == "MERGE" and i["approved"] is False)([i for i in d["items"] if i["path"] == "CLAUDE.md"][0])'
assert $? "T5 pre-existing CLAUDE.md is unapproved MERGE"
bash "$apply" -PlanPath "$s5/PLAN.json" >/dev/null
grep -q "user's own file" "$t5/CLAUDE.md"
assert $? "T5 user CLAUDE.md untouched without approval"

# ---------- T6: stale plan refused ------------------------------------------
t6="$work/t6"; mkdir -p "$t6"
s6="$work/stage6"
bash "$plan" -Target "$t6" -Layers "core" -Source "$REPO_ROOT" -StageDir "$s6" >/dev/null
# drift the target after planning (a path the plan stages)
mkdir -p "$t6/.counsel/rules"
printf 'drifted\n' > "$t6/.counsel/rules/evidence.md"
bash "$apply" -PlanPath "$s6/PLAN.json" >/dev/null
[ $? -eq 1 ]; assert $? "T6 stale plan exits 1"
[ ! -e "$t6/.counsel/manifest.json" ]; assert $? "T6 stale apply wrote nothing"

# ---------- T7: MERGE approval creates backup -------------------------------
s7="$work/stage7"
bash "$plan" -Target "$t5" -Layers "core" -Source "$REPO_ROOT" -StageDir "$s7" -ClaudeMdContentPath "$cm" >/dev/null
set_item_approved "$s7" "CLAUDE.md" true
bash "$apply" -PlanPath "$s7/PLAN.json" >/dev/null
assert $? "T7 approved merge applies"
grep -q '@AGENTS\.md' "$t5/CLAUDE.md"
assert $? "T7 merged CLAUDE.md is the shim"
grep -q 'TestProj' "$t5/AGENTS.md"
assert $? "T7 constitution content lives in AGENTS.md"
backup=$(find "$t5/.counsel/originals" -type f -name "CLAUDE.md" 2>/dev/null | head -n 1)
[ -n "$backup" ]; assert $? "T7 original backed up before replacement"
[ -n "$backup" ] && grep -q "user's own file" "$backup"
assert $? "T7 backup holds pre-merge content"

# ---------- T8: pre-0.1.5 migration -> REMOVE of legacy .claude/rules copies --
t8="$work/t8"; mkdir -p "$t8/.claude/rules" "$t8/.counsel"
legacyRule="$t8/.claude/rules/evidence.md"
printf 'legacy rule content\n' > "$legacyRule"
python3 -c '
import json, sys, hashlib
sha = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
mf = {"schema_version": 1, "runtime_version": "0.1.2", "control_plane_schema": "1",
      "files": [{"path": ".claude/rules/evidence.md", "owned": True, "sha256": sha,
                 "runtime_version": "0.1.2", "applied_class": "CREATE",
                 "applied_at": "2026-08-12T00:00:00"}]}
open(sys.argv[1], "w").write(json.dumps(mf, indent=2))
' "$t8/.counsel/manifest.json" "$legacyRule"
s8="$work/stage8"
bash "$plan" -Target "$t8" -Layers "core" -Source "$REPO_ROOT" -StageDir "$s8" -ClaudeMdContentPath "$cm" >/dev/null
json_check "$s8/PLAN.json" '(lambda i: i["class"] == "REMOVE" and i["approved"] is False)([i for i in d["items"] if i["path"] == ".claude/rules/evidence.md"][0])'
assert $? "T8 legacy owned rule proposed as approval-gated REMOVE"
set_item_approved "$s8" ".claude/rules/evidence.md" true
bash "$apply" -PlanPath "$s8/PLAN.json" >/dev/null
assert $? "T8 apply exits 0"
[ ! -e "$legacyRule" ]; assert $? "T8 legacy rule removed"
rmBackup=$(find "$t8/.counsel/originals" -type f -name "evidence.md" 2>/dev/null | head -n 1)
[ -n "$rmBackup" ]; assert $? "T8 removed file backed up first"
json_check "$t8/.counsel/manifest.json" 'len([f for f in d["files"] if f["path"] == ".claude/rules/evidence.md"]) == 0'
assert $? "T8 manifest entry dropped"

# ---------- T9: codex harness plan (no Claude surfaces, skills staged) -------
t9="$work/t9"; mkdir -p "$t9"
s9="$work/stage9"
bash "$plan" -Target "$t9" -Layers "core,builder" -Source "$REPO_ROOT" -StageDir "$s9" -ClaudeMdContentPath "$cm" -Harness codex >/dev/null
assert $? "T9 codex plan exits 0"
json_check "$s9/PLAN.json" 'd["harness"] == "codex"'
assert $? "T9 plan records harness"
json_check "$s9/PLAN.json" 'len([i for i in d["items"] if i["path"].startswith(".claude/")]) == 0'
assert $? "T9 no .claude/ surfaces for codex"
json_check "$s9/PLAN.json" 'len([i for i in d["items"] if i["path"] == "CLAUDE.md"]) == 0'
assert $? "T9 no CLAUDE.md shim for codex"
json_check "$s9/PLAN.json" 'len([i for i in d["items"] if i["path"].startswith(".codex/skills/")]) > 10'
assert $? "T9 skills staged to .codex/skills/"
json_check "$s9/PLAN.json" 'len([i for i in d["items"] if i["path"].startswith(".counsel/agents/")]) > 0'
assert $? "T9 agents staged as role cards (.counsel/agents)"
[ -e "$s9/.counsel/agents/tech-lead.md" ] && ! grep -q '{{MODEL_' "$s9/.counsel/agents/tech-lead.md"
assert $? "T9 model placeholders resolved to semantic classes"

# ---------- summary ---------------------------------------------------------
printf '\n'
printf 'INSTALL TESTS: %s passed, %s failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'Sandbox kept for inspection: %s\n' "$work"
  exit 1
fi
rm -rf "$work"
exit 0
