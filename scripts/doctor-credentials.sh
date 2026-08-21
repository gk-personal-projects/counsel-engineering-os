#!/usr/bin/env bash
# Counsel Engineering OS -- credential liveness engine (POSIX port).
# Provenance: ORIGINAL (Apache-2.0). Same contract as doctor-credentials.ps1 (POSIX port).
# Dependencies: bash 3.2+, python3 (JSON cache, sha256 fingerprints, HTTP probes via urllib).
# Exit codes: 0 all-clear | 1 blocking (dead/missing cred for an installed capability) | 3 unverified.
#
# WHY THIS EXISTS (D-T2-030): tooling presence is not readiness. A tool on PATH with an
# expired token passes a presence check and fails at the moment of use. READY is therefore
# withheld unless every credential required by an INSTALLED capability is probed LIVE or SKIPped.
#
# LAWS:
#   1. Never fabricate LIVE. Unprobed is UNKNOWN. Unreachable network is UNKNOWN, not DEAD.
#   2. Never print secret material. Values are scrubbed from all output, including error text.
#   3. Probes are read-only. mutating:true in the registry is refused, not honoured.
#   4. Probes leave the machine, so they are opt-in (-Probe). A default run is offline and says so.

. "$(dirname "$0")/lib/common.sh"
ceos_require_python3

PROJECT_DIR="$(pwd)"
OS_DIR=""
PROBE=0
ALLOW_REGISTRY_COMMANDS=0
CACHE_TTL_HOURS=12
NO_CACHE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -ProjectDir|--project-dir)  PROJECT_DIR="${2:?missing value for $1}"; shift 2 ;;
    -OsDir|--os-dir)            OS_DIR="${2:?missing value for $1}"; shift 2 ;;
    -Probe|--probe)             PROBE=1; shift ;;
    -AllowRegistryCommands|--allow-registry-commands) ALLOW_REGISTRY_COMMANDS=1; shift ;;
    -CacheTtlHours|--cache-ttl-hours) CACHE_TTL_HOURS="${2:?missing value for $1}"; shift 2 ;;
    -NoCache|--no-cache)        NO_CACHE=1; shift ;;
    *) ceos_die "Unknown argument: $1" ;;
  esac
done
[ -n "$OS_DIR" ] || OS_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

exec python3 - "$PROJECT_DIR" "$OS_DIR" "$PROBE" "$ALLOW_REGISTRY_COMMANDS" "$CACHE_TTL_HOURS" "$NO_CACHE" <<'PY'
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from datetime import datetime, timedelta, timezone

# Behave like a normal Unix filter when stdout is closed early (e.g. | head).
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass

project_dir = sys.argv[1]
os_dir = sys.argv[2]
probe_flag = sys.argv[3] == "1"
allow_registry_commands = sys.argv[4] == "1"
try:
    cache_ttl_hours = int(sys.argv[5])
except ValueError:
    sys.stderr.write("Invalid -CacheTtlHours value: %s\n" % sys.argv[5])
    sys.exit(1)
no_cache = sys.argv[6] == "1"


def out(line):
    print(line)


secrets = []


def protect(text):
    if not text:
        return text
    for s in secrets:
        if s and len(s) >= 6:
            text = text.replace(s, "***REDACTED***")
    return text


def fingerprint(value):
    h = hashlib.sha256(("counsel-cred-fp-v1:" + value).encode("utf-8"))
    return h.hexdigest()[:8].lower()


# --- registry parse (line-based; mirror of the PS mini-parser, NOT real YAML) --
dep_file = os.path.join(os_dir, "registry", "dependencies.yaml")
if not os.path.isfile(dep_file):
    out("CRED SKIP - :: dependency registry not found at " + dep_file)
    sys.exit(0)


def coerce(v):
    m = re.match(r"^\[(.*)\]$", v)
    if m:
        items = []
        for part in m.group(1).split(","):
            part = part.strip().strip('"').strip("'")
            if part:
                items.append(part)
        return items
    if v == "true" or v == "false":
        return v == "true"
    return v.strip('"').strip("'")


def new_cred(cid, dep):
    return {
        "id": cid, "dep": dep, "env": [], "via": "", "scope": "", "probe": "none",
        "probe_note": "", "probe_url": "", "probe_auth": "", "probe_cmd": "",
        "cost": "unknown", "mutating": False, "rotate": "", "required_by": [],
    }


creds = []
cur_dep = None
cur = None
in_creds = False
with open(dep_file, "r", encoding="utf-8-sig") as fh:
    for raw in fh:
        line = raw.rstrip("\r\n")
        m = re.match(r"^- id:\s*(\S+)", line)
        if m:
            if cur is not None:
                creds.append(cur)
                cur = None
            cur_dep = m.group(1)
            in_creds = False
            continue
        if re.match(r"^  credentials:\s*$", line):
            in_creds = True
            continue
        if in_creds and re.match(r"^  \S", line):
            if cur is not None:
                creds.append(cur)
                cur = None
            in_creds = False
            continue
        if not in_creds:
            continue
        m = re.match(r"^    - id:\s*(\S+)", line)
        if m:
            if cur is not None:
                creds.append(cur)
            cur = new_cred(m.group(1), cur_dep)
            continue
        if cur is not None:
            m = re.match(r"^      ([a-z_]+):\s*(.*)$", line)
            if m:
                cur[m.group(1)] = coerce(m.group(2).strip())
if cur is not None:
    creds.append(cur)
if not creds:
    out("CRED SKIP - :: registry declares no credentials")
    sys.exit(0)


def listify(v):
    if isinstance(v, list):
        return v
    if v is None or v == "" or v is False:
        return []
    return [str(v)]


# --- which capabilities are actually installed --------------------------------
installed = []
config_seen = False
cfg = os.path.join(project_dir, ".counsel", "config.yaml")
if os.path.isfile(cfg):
    config_seen = True
    try:
        with open(cfg, "r", encoding="utf-8-sig") as fh:
            for raw in fh:
                m = re.match(r"^installed_layers:\s*\[(.*)\]", raw)
                if m:
                    for part in m.group(1).split(","):
                        part = part.strip().strip('"').strip("'")
                        if part:
                            installed.append(part)
                    break
    except OSError:
        pass

# --- liveness cache (states only; never secret material) ----------------------
cache_path = os.path.join(project_dir, ".counsel", "credential-liveness.json")
cache = {}
if not no_cache and os.path.isfile(cache_path):
    try:
        with open(cache_path, "r", encoding="utf-8-sig") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            cache = data
    except Exception:
        cache = {}
cache_out = {}


def parse_when(s):
    m = re.match(
        r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})"
        r"(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$",
        str(s or ""),
    )
    if not m:
        return None
    frac = (m.group(7) or "0")[:6].ljust(6, "0")
    tz = m.group(8)
    tzinfo = None
    if tz == "Z":
        tzinfo = timezone.utc
    elif tz:
        sign = 1 if tz[0] == "+" else -1
        tzinfo = timezone(sign * timedelta(hours=int(tz[1:3]), minutes=int(tz[-2:])))
    try:
        return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                        int(m.group(4)), int(m.group(5)), int(m.group(6)),
                        int(frac), tzinfo=tzinfo)
    except ValueError:
        return None


def age_hours(entry):
    dt = parse_when(entry.get("probedAt")) if isinstance(entry, dict) else None
    if dt is None:
        return 999 * 24.0
    now = datetime.now(timezone.utc) if dt.tzinfo else datetime.now()
    return (now - dt).total_seconds() / 3600.0


# --- probes (read-only, non-mutating, closed set) ------------------------------
def http_probe(url, auth, value):
    import urllib.error
    import urllib.parse
    import urllib.request

    headers = {}
    uri = url
    if auth == "bearer" or not auth:
        headers["Authorization"] = "Bearer " + (value or "")
    elif auth.startswith("header:"):
        headers[auth[7:]] = value or ""
    elif auth.startswith("query:"):
        sep = "&" if "?" in uri else "?"
        uri = uri + sep + auth[6:] + "=" + urllib.parse.quote(value or "", safe="")
    try:
        req = urllib.request.Request(uri, headers=headers, method="GET")
        resp = urllib.request.urlopen(req, timeout=20)
        code = resp.getcode()
        try:
            resp.read()
            resp.close()
        except Exception:
            pass
        if 200 <= code < 300:
            return ("LIVE", "HTTP %d" % code)
        return ("UNKNOWN", "probe-error: unexpected HTTP %d" % code)
    except urllib.error.HTTPError as e:
        code = e.code
        if code in (401, 403):
            return ("DEAD", "HTTP %d -- credential rejected" % code)
        return ("UNKNOWN", "probe-error: HTTP %d (not a credential verdict)" % code)
    except Exception as e:
        return ("UNKNOWN", "probe-error: " + protect(str(e))
                + " (a network fault is not a credential verdict)")


def cli_probe(exe, cli_args):
    if shutil.which(exe) is None:
        return ("UNKNOWN", "tool-missing: %s not on PATH (the dependency check owns this finding)" % exe)
    try:
        code = subprocess.call([exe] + cli_args, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        return ("UNKNOWN", "probe-error: " + protect(str(e))
                + " (a network fault is not a credential verdict)")
    if code == 0:
        return ("LIVE", "%s exited 0" % exe)
    return ("DEAD", "%s exited %d -- not authenticated" % (exe, code))


# --- evaluation ----------------------------------------------------------------
blocking = 0
unverified = 0
live = 0
for c in creds:
    req_by = listify(c.get("required_by"))
    relevant = True
    if req_by:
        if config_seen:
            relevant = any(r in installed for r in req_by)
        else:
            relevant = False
    label = "%s/%s" % (c["dep"], c["id"])

    if not relevant:
        why = "capability not installed"
        if not config_seen:
            why = "no .counsel/config.yaml -- installed capabilities unknown"
        out("CRED SKIP %s :: %s (needed by: %s)" % (label, why, ", ".join(req_by)))
        continue

    value = None
    source = None
    env_list = [str(e) for e in listify(c.get("env"))]
    for e in env_list:
        v = os.environ.get(e)
        if v:
            value = v
            source = "env:%s" % e
            break
    if value:
        secrets.append(value)

    tool_managed = bool(c.get("via"))
    if not value and not tool_managed:
        blocking += 1
        out("CRED DEAD %s :: NOT CONFIGURED -- none of [%s] is set, but %s is installed. Grants: %s. Set or rotate at: %s"
            % (label, ", ".join(env_list), "/".join(req_by), c["scope"], c["rotate"]))
        continue
    if not value:
        source = "tool-store (%s)" % c["via"]

    fp = "n/a"
    if value:
        fp = fingerprint(value)
    shown = source
    if value:
        shown = "%s, len %d, fp %s" % (source, len(value), fp)

    if c.get("mutating") is True:
        unverified += 1
        out("CRED UNKNOWN %s :: REFUSED -- the registry marks this probe mutating; a probe with side effects is not a diagnostic. Fix the registry entry. [%s]"
            % (label, shown))
        continue

    if c.get("probe") == "none":
        unverified += 1
        note = c.get("probe_note") or "the registry declares no probe and gives no reason -- registry defect"
        out("CRED UNKNOWN %s :: NOT PROBEABLE -- %s [%s]" % (label, note, shown))
        continue

    ck = "%s|%s" % (label, fp)
    if not no_cache and ck in cache and isinstance(cache[ck], dict):
        entry = cache[ck]
        age = age_hours(entry)
        if age < cache_ttl_hours:
            cache_out[ck] = entry
            mins = int(round(age * 60))
            state = entry.get("state")
            reason = entry.get("reason")
            if state == "LIVE":
                live += 1
                out("CRED LIVE %s :: cached %dm ago -- %s [%s]" % (label, mins, reason, shown))
                continue
            if state == "DEAD":
                blocking += 1
                out("CRED DEAD %s :: cached %dm ago -- %s. Grants: %s. Rotate at: %s"
                    % (label, mins, reason, c["scope"], c["rotate"]))
                continue

    if not probe_flag:
        unverified += 1
        out("CRED UNKNOWN %s :: NOT PROBED -- offline run, liveness unproven. Re-run with -Probe to reach %s (read-only, cost: %s). [%s]"
            % (label, c["dep"], c["cost"], shown))
        continue
    if c.get("cost") != "free":
        unverified += 1
        out("CRED UNKNOWN %s :: NOT PROBED -- probe cost is '%s'; metered or unknown-cost probes are ask-first and never run unattended. [%s]"
            % (label, c["cost"], shown))
        continue

    p = c.get("probe")
    if p == "gh-auth":
        res = cli_probe("gh", ["auth", "status"])
    elif p == "supabase-auth":
        res = cli_probe("supabase", ["projects", "list"])
    elif p == "vercel-whoami":
        res = cli_probe("vercel", ["whoami"])
    elif p == "posthog-me":
        res = http_probe("https://us.posthog.com/api/users/@me/", "bearer", value)
    elif p == "sentry-api":
        res = http_probe("https://sentry.io/api/0/organizations/", "bearer", value)
    elif p == "http-get-200":
        if not c.get("probe_url"):
            res = ("UNKNOWN", "registry defect: probe http-get-200 without probe_url")
        else:
            res = http_probe(c["probe_url"], c["probe_auth"], value)
    elif p == "cmd-exit0":
        if not allow_registry_commands:
            res = ("UNKNOWN", "probe cmd-exit0 needs -AllowRegistryCommands: a modified registry would become code execution, so running its command is a separate consent")
        elif not c.get("probe_cmd"):
            res = ("UNKNOWN", "registry defect: probe cmd-exit0 without probe_cmd")
        else:
            parts = str(c["probe_cmd"]).split()
            res = cli_probe(parts[0], parts[1:])
    else:
        res = ("UNKNOWN", "unknown probe '%s' -- registry defect" % p)

    state, reason = res
    if state in ("LIVE", "DEAD"):
        cache_out[ck] = {"state": state, "reason": reason,
                         "probedAt": datetime.now(timezone.utc).isoformat()}
    msg = protect(reason)
    if state == "LIVE":
        live += 1
        out("CRED LIVE %s :: %s [%s]" % (label, msg, shown))
    elif state == "DEAD":
        blocking += 1
        out("CRED DEAD %s :: %s. Grants: %s. Rotate at: %s" % (label, msg, c["scope"], c["rotate"]))
    else:
        unverified += 1
        out("CRED UNKNOWN %s :: %s [%s]" % (label, msg, shown))

if not no_cache and os.path.isdir(os.path.join(project_dir, ".counsel")):
    try:
        with open(cache_path, "w", encoding="utf-8") as fh:
            json.dump(cache_out, fh, indent=2)
            fh.write("\n")
    except Exception:
        pass

out("CRED SUMMARY live=%d dead-or-missing=%d unverified=%d" % (live, blocking, unverified))
if blocking > 0:
    sys.exit(1)
if unverified > 0:
    sys.exit(3)
sys.exit(0)
PY
