#!/usr/bin/env bash
# Counsel Engineering OS -- mechanical doctor engine (POSIX).
# Provenance: ORIGINAL (Apache-2.0). Same contract as doctor.ps1 (POSIX port).
# Dependencies: bash 3.2+, git, coreutils, python3 (JSON engine per the port
#   ruling; a missing python3 is reported as a BLOCKING finding, not an abort,
#   so diagnosis always runs to completion).
# Exit codes: 0 READY; 1 blocking issue(s) present; 2 recommendations only;
#   3 credential check(s) UNVERIFIED (tooling present, liveness unproven).
# Deliberate fixes vs doctor.ps1 (spec section 8): model-map read from
#   adapters/claude/model-map.json first then registry/model-map.json; user
#   messages name .sh scripts; the python dependency check accepts python3.

set -u
. "$(dirname "$0")/lib/common.sh"

SCRIPT_DIR=$(ceos_resolve_dir "$(dirname "$0")") || ceos_die "Cannot resolve script directory for $0"

PROJECT_DIR=$(pwd)
OS_DIR=""
PROBE=0
ALLOW_REGISTRY_COMMANDS=0
while [ $# -gt 0 ]; do
  case "$1" in
    -ProjectDir|--project-dir) PROJECT_DIR="${2:?missing value for $1}"; shift 2 ;;
    -OsDir|--os-dir)           OS_DIR="${2:?missing value for $1}"; shift 2 ;;
    -Probe|--probe)            PROBE=1; shift ;;
    -AllowRegistryCommands|--allow-registry-commands) ALLOW_REGISTRY_COMMANDS=1; shift ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$OS_DIR" ] || OS_DIR=$(dirname "$SCRIPT_DIR")

# python3 availability is itself a diagnostic finding (emitted in the deps
# section), so the script degrades instead of dying when it is absent.
HAVE_PY3=0
command -v python3 >/dev/null 2>&1 && HAVE_PY3=1
py3() {
  [ "$HAVE_PY3" = 1 ] || return 127
  python3 "$@"
}

BLOCKING_N=0; RECOMMENDED_N=0; UNVERIFIED_N=0
out_check() {
  case "$1" in
    BLOCKING)    BLOCKING_N=$((BLOCKING_N+1)) ;;
    RECOMMENDED) RECOMMENDED_N=$((RECOMMENDED_N+1)) ;;
    UNVERIFIED)  UNVERIFIED_N=$((UNVERIFIED_N+1)) ;;
  esac
  printf '%-12s %-12s %s\n' "$1" "$2" "$3"
}

# --- CORE INTEGRITY --------------------------------------------------------
# Constitution: AGENTS.md (0.1.5+, harness-neutral) with a CLAUDE.md shim on
# Claude Code; a fat CLAUDE.md without AGENTS.md is a pre-0.1.5 install.
AGENTS_MD="$PROJECT_DIR/AGENTS.md"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
CONSTITUTION=""
if [ -f "$AGENTS_MD" ]; then
  CONSTITUTION="$AGENTS_MD"
  out_check INFO core "Constitution present (AGENTS.md)"
  agentsBytes=$(ceos_bytes "$AGENTS_MD")
  if [ "$agentsBytes" -gt 32768 ]; then
    out_check RECOMMENDED core "AGENTS.md is $agentsBytes bytes -- Codex truncates beyond 32 KiB; trim content"
  else
    out_check INFO core "AGENTS.md size OK ($agentsBytes bytes / 32 KiB budget)"
  fi
  hasBegin=0; hasEnd=0
  grep -q -e '<!-- counsel:rules v.*begin' "$AGENTS_MD" && hasBegin=1
  grep -qF -- '<!-- counsel:rules end -->' "$AGENTS_MD" && hasEnd=1
  if [ "$hasBegin" = 1 ] && [ "$hasEnd" = 1 ]; then
    out_check INFO core "counsel:rules sentinel block intact"
  elif [ "$hasBegin" = 1 ] || [ "$hasEnd" = 1 ]; then
    out_check BLOCKING core "counsel:rules sentinel block DAMAGED (one marker missing) - re-run install-plan/apply"
  else
    out_check RECOMMENDED core "no counsel:rules sentinel block in AGENTS.md - always-on rules are not embedded"
  fi
  if [ -f "$CLAUDE_MD" ]; then
    shimFirst=$(head -n 1 "$CLAUDE_MD" | tr -d '\r')
    if printf '%s\n' "$shimFirst" | grep -qE '^@AGENTS\.md[[:space:]]*$'; then
      out_check INFO core "CLAUDE.md shim imports AGENTS.md"
    else
      out_check RECOMMENDED core "CLAUDE.md exists but does not start with @AGENTS.md - Claude Code may not load the constitution (or content is duplicated)"
    fi
  fi
elif [ -f "$CLAUDE_MD" ]; then
  CONSTITUTION="$CLAUDE_MD"
  out_check INFO core "Constitution present (legacy CLAUDE.md; pre-0.1.5)"
  out_check RECOMMENDED core "no AGENTS.md - re-run install to migrate to the harness-neutral constitution"
else
  out_check BLOCKING core "constitution missing (no AGENTS.md, no CLAUDE.md) - run /counsel:onboard"
fi

# --- CONSTITUTION IMPORTS / PLACEHOLDERS / BOOT WEIGHT ----------------------
if [ -n "$CONSTITUTION" ]; then
  while IFS= read -r cline || [ -n "$cline" ]; do
    cline=${cline%$'\r'}
    case "$cline" in
      @?*)
        imp="${cline#@}"
        if [ -e "$PROJECT_DIR/$imp" ]; then
          out_check INFO core "rule resolves: $imp"
        else
          out_check BLOCKING core "always-on rule MISSING: $imp"
        fi ;;
    esac
  done < "$CONSTITUTION"
  if grep -qF -- '{{' "$CONSTITUTION"; then
    out_check RECOMMENDED core "unfilled {{placeholders}} remain in constitution"
  fi
  bootTokens=$(py3 - "$CONSTITUTION" "$PROJECT_DIR" 2>/dev/null <<'PY'
import os, sys
const, proj = sys.argv[1], sys.argv[2]
def chars(p):
    try:
        with open(p, 'rb') as f:
            return len(f.read().decode('utf-8', 'replace'))
    except OSError:
        return 0
total = chars(const)
for rd in ('.claude/rules', '.counsel/rules'):
    d = os.path.join(proj, rd)
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if name.lower().endswith('.md') and os.path.isfile(p):
                total += chars(p)
print(int(round(total / 4.0)))  # PS [math]::Round rounds half-to-even, as does python round()
PY
) || bootTokens=""
  if [ -z "$bootTokens" ]; then
    # degraded (no python3): byte-based estimate, round-half-up
    total=$(ceos_bytes "$CONSTITUTION")
    for rd in .claude/rules .counsel/rules; do
      for rf in "$PROJECT_DIR/$rd"/*.md; do
        [ -f "$rf" ] || continue
        total=$((total + $(ceos_bytes "$rf")))
      done
    done
    bootTokens=$(((total + 2) / 4))
  fi
  out_check INFO cost "boot weight estimate ~$bootTokens tokens (constitution + rules; chars/4)"
fi

# --- RULE REACHABILITY (scoped rules whose globs match nothing) -------------
SCOPED_DIR="$PROJECT_DIR/.claude/rules/scoped"
if [ -d "$SCOPED_DIR" ]; then
  for sf in "$SCOPED_DIR"/*.md; do
    [ -f "$sf" ] || continue
    pline=$(grep -E '^[[:space:]]*paths?:[[:space:]]*.+$' "$sf" 2>/dev/null | head -n 1)
    if [ -n "$pline" ]; then
      glob=$(printf '%s' "$pline" | tr -d '\r' \
        | sed -E 's/^[[:space:]]*paths?:[[:space:]]*//; s/[[:space:]]+$//' \
        | sed -e "s/^['\"]*//" -e "s/['\"]*\$//")
      probe=$(printf '%s' "$glob" | sed -E -e 's|/\*\*/\*.*$||' -e 's|/\*\*.*$||' -e 's|\*.*$||')
      if [ -n "$probe" ] && [ ! -e "$PROJECT_DIR/$probe" ]; then
        out_check RECOMMENDED rules "scoped rule '$(basename "$sf")' targets '$glob' but '$probe' does not exist - it will never fire"
      else
        out_check INFO rules "scoped rule reachable: $(basename "$sf")"
      fi
    fi
  done
fi

# --- PERMISSIONS SELF-AUDIT -------------------------------------------------
SETTINGS_PATH="$PROJECT_DIR/.claude/settings.json"
if [ -f "$SETTINGS_PATH" ]; then
  sOut=$(py3 - "$SETTINGS_PATH" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'rb') as f:
        s = json.loads(f.read().decode('utf-8-sig'))
except Exception as e:
    print("ERR %s" % str(e).replace("\n", " ").replace("\r", " "))
    sys.exit(0)
perms = s.get('permissions') if isinstance(s, dict) else None
perms = perms if isinstance(perms, dict) else {}
allow = perms.get('allow')
deny = perms.get('deny')
allow = allow if isinstance(allow, list) else ([] if allow is None else [allow])
deny = deny if isinstance(deny, list) else ([] if deny is None else [deny])
wild = [a for a in allow if isinstance(a, str) and '*' in a]
push = 1 if ('Bash(git push *)' in deny or 'Bash(git push*)' in deny) else 0
print("OK %d %d %d %d" % (len(allow), len(deny), len(wild), push))
PY
) || sOut="ERR python3 not available on PATH"
  case "$sOut" in
    "OK "*)
      sAllow=$(printf '%s' "$sOut" | cut -d' ' -f2)
      sDeny=$(printf '%s' "$sOut" | cut -d' ' -f3)
      sWild=$(printf '%s' "$sOut" | cut -d' ' -f4)
      sPush=$(printf '%s' "$sOut" | cut -d' ' -f5)
      if [ "$sWild" -gt 0 ]; then
        out_check RECOMMENDED perms "$sWild wildcard allow(s) - remember: a positional deny can never constrain a wildcard allow; prefer literal-safe forms"
      fi
      if [ "$sPush" = 0 ]; then
        out_check RECOMMENDED perms "git push is not deny-listed (prompt-gated only)"
      fi
      out_check INFO perms "settings.json parses ($sAllow allow / $sDeny deny)"
      ;;
    *)
      out_check BLOCKING perms "settings.json does not parse: ${sOut#ERR }"
      ;;
  esac
else
  out_check INFO perms "no project settings.json (defaults apply)"
fi

# --- INSTALL MANIFEST / VERSIONS / OWNERSHIP (D-T2-026 S3) ------------------
MANIFEST_PATH="$PROJECT_DIR/.counsel/manifest.json"
if [ -f "$MANIFEST_PATH" ]; then
  mfOut=$(py3 - "$MANIFEST_PATH" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'rb') as f:
        mf = json.loads(f.read().decode('utf-8-sig'))
except Exception as e:
    print("ERR %s" % str(e).replace("\n", " ").replace("\r", " "))
    sys.exit(0)
files = mf.get('files') if isinstance(mf, dict) else None
files = files if isinstance(files, list) else []
print("OK")
print("%s" % mf.get('runtime_version', ''))
print("%s" % mf.get('control_plane_schema', ''))
print("%d" % len(files))
for fe in files:
    if not isinstance(fe, dict):
        continue
    path = fe.get('path') or '-'
    sha = fe.get('sha256') or '-'
    print("F %d %s %s" % (1 if fe.get('owned') else 0, sha, path))
PY
) || mfOut="ERR python3 not available on PATH"
  mfStatus=$(printf '%s\n' "$mfOut" | sed -n '1p')
  if [ "$mfStatus" = "OK" ]; then
    mfRv=$(printf '%s\n' "$mfOut" | sed -n '2p')
    mfCps=$(printf '%s\n' "$mfOut" | sed -n '3p')
    mfCount=$(printf '%s\n' "$mfOut" | sed -n '4p')
    out_check INFO install "manifest parses (runtime $mfRv, control-plane schema $mfCps, $mfCount files)"
    mfMissing=0; mfModified=0
    while IFS= read -r fline; do
      case "$fline" in
        "F "*) ;;
        *) continue ;;
      esac
      frest="${fline#F }"
      fOwned="${frest%% *}"; frest="${frest#* }"
      fSha="${frest%% *}"; fPath="${frest#* }"
      [ "$fPath" = "-" ] && continue
      fAbs="$PROJECT_DIR/$fPath"
      if [ ! -e "$fAbs" ]; then
        if [ "$fOwned" = 1 ]; then
          out_check BLOCKING install "owned file MISSING: $fPath (scripts/install/repair.sh restores it)"
          mfMissing=$((mfMissing+1))
        fi
      elif [ "$fOwned" = 1 ]; then
        liveSha=$(ceos_sha256 "$fAbs")
        if [ "$liveSha" != "$fSha" ]; then
          out_check RECOMMENDED install "owned file locally modified: $fPath (kept; repair -IncludeModified restores)"
          mfModified=$((mfModified+1))
        fi
      fi
    done <<EOF
$mfOut
EOF
    if [ "$mfMissing" = 0 ] && [ "$mfModified" = 0 ]; then
      out_check INFO install "ownership integrity: all owned files present and unmodified"
    fi
    cacheRoot=$(ceos_plugin_cache_root)
    if [ -d "$cacheRoot" ]; then
      # semver-shaped dirs only (SHA-named dirs are transient cache artifacts, never releases)
      newest=$(ceos_newest_semver_dir "$cacheRoot")
      if [ -n "$newest" ]; then
        newestName=$(basename "$newest")
        if [ "$newestName" != "$mfRv" ]; then
          out_check RECOMMENDED install "RUNTIME VERSION SKEW: installed plugin $newestName vs project files from $mfRv - re-run plan+apply (update flow) to reconcile"
        else
          out_check INFO install "runtime version matches installed plugin ($newestName)"
        fi
        srcSchema="$newest/scaffold/SCHEMA-VERSION"
        if [ -f "$srcSchema" ]; then
          pluginCps=$(head -n 1 "$srcSchema" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
          if [ "$mfCps" != "$pluginCps" ]; then
            out_check RECOMMENDED install "CONTROL-PLANE SCHEMA SKEW: project $mfCps vs plugin $pluginCps - re-plan to migrate templates"
          else
            out_check INFO install "control-plane schema matches ($pluginCps)"
          fi
        fi
      fi
    else
      out_check INFO install "no counsel plugin cache (scaffold-source install is valid; version skew unchecked)"
    fi
  else
    out_check BLOCKING install "manifest does not parse: ${mfStatus#ERR }"
  fi
else
  out_check INFO install "no ownership manifest (not yet onboarded via installer)"
fi

# --- AGENT MODEL VALUES (D-T2-026 R3) ---------------------------------------
AGENTS_DIR="$PROJECT_DIR/.claude/agents"
if [ -d "$AGENTS_DIR" ]; then
  # Deliberate fix vs doctor.ps1: two-location model-map lookup matching
  # install-plan (adapters/claude first, then legacy registry path).
  mapOut=$(py3 - "$OS_DIR/adapters/claude/model-map.json" "$OS_DIR/registry/model-map.json" 2>/dev/null <<'PY'
import json, os, sys
allowed = ["inherit"]
for p in sys.argv[1:3]:
    if not os.path.isfile(p):
        continue
    try:
        with open(p, 'rb') as f:
            m = json.loads(f.read().decode('utf-8-sig'))
    except Exception:
        continue
    classes = m.get('classes') if isinstance(m, dict) else None
    if isinstance(classes, dict):
        for v in classes.values():
            allowed.append(v)
    fb = m.get('fallback') if isinstance(m, dict) else None
    if fb:
        allowed.append(fb)
    break
seen = []
for a in allowed:
    a = str(a)
    if a not in seen:
        seen.append(a)
print(", ".join(seen))
for a in seen:
    print(a)
PY
) || mapOut=""
  if [ -n "$mapOut" ]; then
    allowedCsv=$(printf '%s\n' "$mapOut" | sed -n '1p')
    allowedList=$(printf '%s\n' "$mapOut" | sed '1d')
  else
    allowedCsv="inherit"; allowedList="inherit"
  fi
  agentCount=0
  for af in "$AGENTS_DIR"/*.md; do
    [ -f "$af" ] || continue
    agentCount=$((agentCount+1))
    if grep -qF -- '{{MODEL_' "$af"; then
      out_check BLOCKING agents "unresolved model placeholder in $(basename "$af")"
    fi
    mline=$(grep -E '^model:.' "$af" 2>/dev/null | head -n 1)
    if [ -n "$mline" ]; then
      mval=$(printf '%s' "$mline" | tr -d '\r' \
        | sed -E 's/^model:[[:space:]]*//; s/^[[:space:]]+//; s/[[:space:]]+$//' \
        | sed -e "s/^['\"]*//" -e "s/['\"]*\$//")
      if [ -z "$mval" ] || ! printf '%s\n' "$allowedList" | grep -qxF -- "$mval"; then
        out_check RECOMMENDED agents "unsupported model value '$mval' in $(basename "$af") - allowed: $allowedCsv"
      fi
    fi
  done
  out_check INFO agents "agent model values checked ($agentCount agent(s))"
fi

# --- HOOK COMPATIBILITY (ruling A8: no hidden Git Bash dependency) ----------
if [ -f "$SETTINGS_PATH" ]; then
  hOut=$(py3 - "$SETTINGS_PATH" 2>/dev/null <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], 'rb') as f:
        s = json.loads(f.read().decode('utf-8-sig'))
except Exception:
    print("ERR")
    sys.exit(0)
hooks = s.get('hooks') if isinstance(s, dict) else None
if not hooks:
    print("NOHOOKS")
    sys.exit(0)
cmds = []
if isinstance(hooks, dict):
    for v in hooks.values():
        entries = v if isinstance(v, list) else [v]
        for e in entries:
            if not isinstance(e, dict):
                continue
            hk = e.get('hooks')
            hk = hk if isinstance(hk, list) else ([] if hk is None else [hk])
            for x in hk:
                if isinstance(x, dict) and x.get('command'):
                    cmds.append(str(x['command']))
nonps = [c for c in cmds if not re.search(r'powershell(\.exe)?', c)]
print("HOOKS %d %d" % (len(cmds), len(nonps)))
PY
) || hOut="ERR"
  case "$hOut" in
    NOHOOKS)
      out_check INFO hooks "no hooks configured (continuity hook pack default OFF)"
      ;;
    "HOOKS "*)
      hTotal=$(printf '%s' "$hOut" | cut -d' ' -f2)
      hNonPs=$(printf '%s' "$hOut" | cut -d' ' -f3)
      if ! command -v bash >/dev/null 2>&1 && [ "$hNonPs" -gt 0 ]; then
        out_check RECOMMENDED hooks "$hNonPs hook(s) without explicit powershell.exe invocation and no bash on PATH - they may silently not run on Windows"
      else
        out_check INFO hooks "hooks configured: $hTotal command(s), shell-compatible"
      fi
      ;;
    *) : ;;  # parse failure swallowed, matching the .ps1 catch {}
  esac
else
  out_check INFO hooks "no hooks configured (continuity hook pack default OFF)"
fi

# --- SESSION CONTINUITY -----------------------------------------------------
SESSION_DIR="$PROJECT_DIR/.counsel/session"
if [ -d "$SESSION_DIR" ]; then
  sessOut=$(sh "$SCRIPT_DIR/session/session-doctor.sh" "$PROJECT_DIR" "$SESSION_DIR")
  sessExit=$?
  if [ -n "$sessOut" ]; then
    while IFS= read -r sline; do
      printf '             session      %s\n' "$sline"
    done <<EOF
$sessOut
EOF
  fi
  if [ "$sessExit" = 1 ]; then
    out_check BLOCKING session "session doctor reports FAIL (above)"
  elif [ "$sessExit" = 2 ]; then
    out_check RECOMMENDED session "session doctor reports warnings (above)"
  fi
  # D-T2-023 semantic coherence: recorded git facts vs live git (mechanical
  # completeness is session-doctor's job; this catches semantically-stale STATE)
  statePathSem="$SESSION_DIR/STATE.json"
  if [ -f "$statePathSem" ]; then
    projLeaf=$(basename "$PROJECT_DIR")
    recHead=$(py3 - "$statePathSem" "$projLeaf" 2>/dev/null <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'rb') as f:
        st = json.loads(f.read().decode('utf-8-sig'))
    git = st.get('git') if isinstance(st, dict) else None
    rec = git.get(sys.argv[2]) if isinstance(git, dict) else None
    head = rec.get('head') if isinstance(rec, dict) else None
    if head:
        print(head)
except Exception:
    pass
PY
) || recHead=""
    if [ -n "$recHead" ]; then
      liveHead=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null) || liveHead=""
      if [ -n "$liveHead" ] && [ "$liveHead" != "$recHead" ]; then
        rec7=$(printf '%.7s' "$recHead")
        live7=$(printf '%.7s' "$liveHead")
        out_check RECOMMENDED session "SEMANTIC DRIFT (D-T2-023): STATE.json records $projLeaf @ $rec7 but live is $live7 - reconcile openly, never silently"
      fi
    fi
  fi
else
  out_check RECOMMENDED session "no .counsel/session - continuity not initialized (run /counsel:onboard or /counsel:checkpoint)"
fi

# --- WORK PLANE -------------------------------------------------------------
WQ_PATH="$PROJECT_DIR/.counsel/work/WORKING-QUEUE.yaml"
if [ -f "$WQ_PATH" ]; then
  wqCount=$(grep -c -E '^[[:space:]]*-[[:space:]]*[{]?[[:space:]]*id:' "$WQ_PATH" 2>/dev/null)
  [ -n "$wqCount" ] || wqCount=0
  if [ "$wqCount" -gt 10 ]; then
    out_check RECOMMENDED work "working queue holds $wqCount entries - horizon should stay bounded (~7); triage"
  else
    out_check INFO work "working queue bounded ($wqCount entries)"
  fi
else
  out_check INFO work "no work ledger yet (optional until first planned work)"
fi

# --- EXTERNAL DEPENDENCIES (from registry; functional > presence) -----------
if git --version >/dev/null 2>&1; then
  out_check INFO deps "git present (core-required)"
else
  out_check BLOCKING deps "git MISSING (core-required) - install from https://git-scm.com"
fi
# Port-only check (spec 9.6): python3 is the JSON engine of the POSIX scripts.
if [ "$HAVE_PY3" != 1 ]; then
  out_check BLOCKING deps "python3 MISSING (required by Counsel scripts on macOS/Linux) - install Xcode Command Line Tools or python3"
fi
# NOTE: this loop answers "is it installed" only. Whether the tool can actually
# AUTHENTICATE is the credential-liveness family below.
depPresent() {
  # $1 = command; python accepts python3 as satisfying it (deliberate port fix)
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  [ "$1" = "python" ] && command -v python3 >/dev/null 2>&1 && return 0
  return 1
}
for depSpec in \
  "gh|GitHub CLI|github-work-sync capability" \
  "node|Node.js|Node projects" \
  "python|Python|Python projects" \
  "docker|Docker|container workflows"
do
  depCmd=${depSpec%%|*}
  depRest=${depSpec#*|}
  depLabel=${depRest%%|*}
  depReason=${depRest#*|}
  if depPresent "$depCmd"; then
    out_check INFO deps "$depLabel present"
  else
    out_check OPTIONAL deps "$depLabel not found - only needed for $depReason"
  fi
done

# --- CREDENTIAL LIVENESS (D-T2-030) ----------------------------------------
# Presence is not readiness. A tool on PATH whose credential is expired,
# revoked, or never configured fails at the moment of use, not at the moment
# of diagnosis. READY is withheld unless every credential required by an
# INSTALLED capability is probed LIVE. Unprobed is UNVERIFIED, never READY.
CRED_SCRIPT="$SCRIPT_DIR/doctor-credentials.sh"
if [ -f "$CRED_SCRIPT" ]; then
  set -- -ProjectDir "$PROJECT_DIR" -OsDir "$OS_DIR"
  [ "$PROBE" = 1 ] && set -- "$@" -Probe
  [ "$ALLOW_REGISTRY_COMMANDS" = 1 ] && set -- "$@" -AllowRegistryCommands
  credOut=$(bash "$CRED_SCRIPT" "$@")
  credExit=$?
  nDead=0; nUnk=0; nLive=0
  if [ -n "$credOut" ]; then
    while IFS= read -r cl; do
      cl=${cl%$'\r'}
      case "$cl" in
        "CRED SUMMARY"*) continue ;;
      esac
      credSt=""; credWho=""; credWhy=""; credMatched=0
      case "$cl" in
        "CRED LIVE "*|"CRED DEAD "*|"CRED UNKNOWN "*|"CRED SKIP "*)
          crest="${cl#CRED }"
          credSt="${crest%% *}"
          crest="${crest#* }"
          case "$crest" in
            *" :: "*)
              credWho="${crest%% :: *}"
              credWhy="${crest#* :: }"
              case "$credWho" in
                ""|*" "*) credMatched=0 ;;
                *) credMatched=1 ;;
              esac ;;
          esac ;;
      esac
      if [ "$credMatched" = 1 ]; then
        case "$credSt" in
          LIVE)    nLive=$((nLive+1)); out_check INFO       creds "$credWho LIVE -- $credWhy" ;;
          DEAD)    nDead=$((nDead+1)); out_check BLOCKING   creds "$credWho -- $credWhy" ;;
          UNKNOWN) nUnk=$((nUnk+1));   out_check UNVERIFIED creds "$credWho -- $credWhy" ;;
          SKIP)                        out_check INFO       creds "$credWho not applicable -- $credWhy" ;;
        esac
      elif [ -n "$cl" ]; then
        printf '             creds        %s\n' "$cl"
      fi
    done <<EOF
$credOut
EOF
  fi
  if [ "$nUnk" -gt 0 ] && [ "$PROBE" != 1 ]; then
    out_check UNVERIFIED creds "$nUnk credential(s) unproven -- re-run: /counsel:doctor --probe (read-only, free probes only)"
  fi
  if [ "$credExit" = 0 ] && [ "$nLive" -gt 0 ]; then
    out_check INFO creds "all credentials required by installed capabilities are LIVE"
  fi
else
  out_check UNVERIFIED creds "doctor-credentials.sh missing -- credential liveness cannot be established (repair restores it)"
fi

# --- RESULT -----------------------------------------------------------------
# READY means: nothing blocking, nothing merely recommended, AND every
# credential an installed capability depends on was actually proven to work.
# Exit 3 exists so that "tools are present but your keys are unproven" can
# never be reported as READY.
printf '\n'
if [ "$BLOCKING_N" -gt 0 ]; then
  printf 'RESULT: %s BLOCKING ISSUE(S), %s recommendation(s), %s unverified\n' "$BLOCKING_N" "$RECOMMENDED_N" "$UNVERIFIED_N"
  exit 1
fi
if [ "$UNVERIFIED_N" -gt 0 ]; then
  printf 'RESULT: NOT READY -- %s CREDENTIAL CHECK(S) UNVERIFIED, %s recommendation(s)\n' "$UNVERIFIED_N" "$RECOMMENDED_N"
  printf '        Tooling is present. Liveness of the credentials above is UNPROVEN -- that is not READY.\n'
  exit 3
fi
if [ "$RECOMMENDED_N" -gt 0 ]; then
  printf 'RESULT: READY WITH %s RECOMMENDATION(S)\n' "$RECOMMENDED_N"
  exit 2
fi
printf 'RESULT: READY (tooling present and credentials proven live)\n'
exit 0
