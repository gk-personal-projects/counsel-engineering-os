#!/usr/bin/env bash
# Provenance: ORIGINAL (Apache-2.0).
# Shared helpers for the POSIX ports of the Counsel install/doctor scripts.
# Contract siblings: the .ps1 scripts under scripts/ (see docs/INSTALL.md).
# Dependencies: git, coreutils, python3 (JSON; ships with Xcode CLT alongside git).
# Bash 3.2 compatible (macOS default shell for scripts). ASCII only. LF only.
# Usage: . "$(dirname "$0")/../lib/common.sh"   (adjust relative depth per caller)

set -u

# Fatal error: message to stderr, exit 1. Mirrors PS Write-Error + exit 1.
ceos_die() {
  printf '%s\n' "$1" >&2
  exit 1
}

# python3 is the JSON engine for these ports. On macOS it arrives with the
# Xcode Command Line Tools -- the same install that provides git, which
# Counsel already requires -- so this adds no new install step in practice.
ceos_require_python3() {
  command -v python3 >/dev/null 2>&1 || ceos_die \
    "python3 not found on PATH - required by Counsel scripts on macOS/Linux (on macOS: xcode-select --install)"
}

# SHA-256 of a file's bytes, lowercase hex. Matches PS Get-FileHash output.
ceos_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  fi
}

# Timestamp for directory names. Matches PS Get-Date -Format "yyyyMMdd-HHmmss".
ceos_stamp() {
  date +%Y%m%d-%H%M%S
}

# ISO-8601 UTC instant. Stands in for PS (Get-Date).ToString("o"); parseable by
# both python3 datetime.fromisoformat and a PowerShell [datetime] cast.
ceos_now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%S.0000000+00:00'
}

# Byte count of a file (avoid stat: flags differ between BSD and GNU).
ceos_bytes() {
  wc -c < "$1" | tr -d ' '
}

# Absolute physical path of an existing directory.
ceos_resolve_dir() {
  (cd "$1" 2>/dev/null && pwd -P) || return 1
}

# Atomic write: stdin -> temp file in dest's directory -> rename over dest.
# Mirrors PS Write-Atomic/Write-FileSafe (UTF-8, no BOM; rename in same dir).
ceos_write_atomic() {
  _ceos_dest="$1"
  _ceos_dir=$(dirname "$_ceos_dest")
  _ceos_base=$(basename "$_ceos_dest")
  mkdir -p "$_ceos_dir" || return 1
  cat > "$_ceos_dir/.tmp-$_ceos_base" || return 1
  rm -f "$_ceos_dest"
  mv "$_ceos_dir/.tmp-$_ceos_base" "$_ceos_dest"
}

# Atomic copy: src file -> temp in dest's directory -> rename over dest.
ceos_copy_atomic() {
  _ceos_src="$1"
  _ceos_dest="$2"
  _ceos_dir=$(dirname "$_ceos_dest")
  _ceos_base=$(basename "$_ceos_dest")
  mkdir -p "$_ceos_dir" || return 1
  cp "$_ceos_src" "$_ceos_dir/.tmp-$_ceos_base" || return 1
  rm -f "$_ceos_dest"
  mv "$_ceos_dir/.tmp-$_ceos_base" "$_ceos_dest"
}

# Newest semver-named subdirectory (names matching ^\d+(\.\d+)+$) of $1,
# printed as its full path; prints nothing if none. Mirrors the PS
# Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1.
ceos_newest_semver_dir() {
  [ -d "$1" ] || return 0
  python3 - "$1" <<'PY'
import os, re, sys
root = sys.argv[1]
best = None
for name in os.listdir(root):
    if re.match(r'^\d+(\.\d+)+$', name) and os.path.isdir(os.path.join(root, name)):
        key = tuple(int(p) for p in name.split('.'))
        if best is None or key > best[0]:
            best = (key, name)
if best:
    print(os.path.join(root, best[1]))
PY
}

# The plugin cache root shared by install-plan, repair, and doctor.
ceos_plugin_cache_root() {
  printf '%s\n' "$HOME/.claude/plugins/cache/counsel-os/counsel"
}
