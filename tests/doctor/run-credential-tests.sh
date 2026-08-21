#!/usr/bin/env bash
# Counsel Engineering OS -- credential liveness acceptance tests (D-T2-030).
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-credential-tests.ps1 (POSIX port).
# Dependencies: bash 3.2+, python3 (via the scripts under test). Runs in an isolated
#   sandbox under ${TMPDIR:-/tmp}. NO TEST HERE TOUCHES THE NETWORK: every case uses a
#   synthetic registry with probes that resolve locally, so the suite is deterministic
#   and free to run.
# Exit codes: 0 all pass | 1 any fail.
#
# The load-bearing assertion is T5/T6: unproven liveness must NOT be reported as READY.
# POSIX fixture note: the PS suite's cmd-exit0 probe was `cmd /c exit 0`; here it is
# `true` (probe_cmd splits on whitespace with no quoting, so plain `true` is safest).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SCRIPTS_DIR="$SCRIPT_DIR/../../scripts"
while [ $# -gt 0 ]; do
  case "$1" in
    -ScriptsDir|--scripts-dir) SCRIPTS_DIR="${2:?missing value for $1}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
SCRIPTS_DIR=$(cd "$SCRIPTS_DIR" 2>/dev/null && pwd -P) || { echo "Scripts dir not found" >&2; exit 1; }
CRED="$SCRIPTS_DIR/doctor-credentials.sh"
DOC="$SCRIPTS_DIR/doctor.sh"

SB="${TMPDIR:-/tmp}/ceos-cred-tests-$(date +%Y%m%d%H%M%S)"
mkdir -p "$SB"
passed=0; failed=0

# assert <0|nonzero> <name> [detail] -- 0 means the condition held.
assert() {
  if [ "$1" -eq 0 ]; then passed=$((passed+1)); printf 'PASS  %s\n' "$2"
  else failed=$((failed+1)); printf 'FAIL  %s  %s\n' "$2" "${3:-}"; fi
}

# A synthetic OS dir: registry only, so tests never depend on the shipped registry's content.
new_os_dir() { # name; registry body on stdin; prints the os dir path
  _os="$SB/$1"
  mkdir -p "$_os/registry"
  cat > "$_os/registry/dependencies.yaml"
  printf '%s\n' "$_os"
}
new_project() { # name layers; prints the project path
  _p="$SB/$1"
  mkdir -p "$_p/.counsel"
  if [ -n "$2" ]; then
    printf 'installed_layers: [%s]\nmode: BUILD\n' "$2" > "$_p/.counsel/config.yaml"
  fi
  printf '%s\n' "$_p"
}
run_cred() { # proj os [extra args...]; sets CRED_OUT, CRED_CODE
  _proj="$1"; _osd="$2"; shift 2
  CRED_OUT=$(bash "$CRED" -ProjectDir "$_proj" -OsDir "$_osd" -NoCache "$@")
  CRED_CODE=$?
}
outmatch() { printf '%s\n' "$CRED_OUT" | grep -Eq "$1"; }

# Registry A: one env-var credential, no probe available (honest UNKNOWN).
osNoProbe=$(new_os_dir "os-noprobe" <<'EOF'
- id: fake-svc
  name: Fake Service
  classification: capability-required
  purpose: test
  detect: "n/a"
  install_source: "n/a"
  verify: "n/a"
  fallback: "n/a"
  consequential_install: false
  credentials:
    - id: fake-key
      env: [CEOS_TEST_FAKE_KEY]
      scope: "test scope"
      probe: none
      probe_note: "no unauthenticated endpoint distinguishes live from dead"
      cost: free
      mutating: false
      rotate: "https://example.invalid/rotate"
      required_by: [ship-loop]
EOF
)

# Registry B: same credential, but the probe is declared mutating (must be refused).
osMutating=$(new_os_dir "os-mutating" <<'EOF'
- id: fake-svc
  name: Fake Service
  classification: capability-required
  purpose: test
  detect: "n/a"
  install_source: "n/a"
  verify: "n/a"
  fallback: "n/a"
  consequential_install: false
  credentials:
    - id: fake-key
      env: [CEOS_TEST_FAKE_KEY]
      scope: "test scope"
      probe: http-get-200
      probe_note: "no unauthenticated endpoint distinguishes live from dead"
      cost: free
      mutating: true
      rotate: "https://example.invalid/rotate"
      required_by: [ship-loop]
EOF
)

# Registry C: probe cmd-exit0 (registry-authored exec -- must require explicit consent).
osCmd=$(new_os_dir "os-cmd" <<'EOF'
- id: fake-svc
  name: Fake Service
  classification: capability-required
  purpose: test
  detect: "n/a"
  install_source: "n/a"
  verify: "n/a"
  fallback: "n/a"
  consequential_install: false
  credentials:
    - id: fake-key
      env: [CEOS_TEST_FAKE_KEY]
      scope: "test scope"
      probe: cmd-exit0
      probe_cmd: "true"
      probe_note: "no unauthenticated endpoint distinguishes live from dead"
      cost: free
      mutating: false
      rotate: "https://example.invalid/rotate"
      required_by: [ship-loop]
EOF
)

# ---------------------------------------------------------------------------
# T1  Capability not installed => credential is not applicable, never blocking.
p=$(new_project "p-nolayer" "counsel-core")
run_cred "$p" "$osNoProbe"
ok=1; outmatch "CRED SKIP" && [ "$CRED_CODE" -eq 0 ] && ok=0
assert $ok "T1 uninstalled capability -> SKIP, exit 0" "code=$CRED_CODE"

# T2  No config.yaml at all => unknown install set, nothing is asserted as broken.
p=$(new_project "p-noconfig" "")
run_cred "$p" "$osNoProbe"
ok=1; outmatch "installed capabilities unknown" && [ "$CRED_CODE" -eq 0 ] && ok=0
assert $ok "T2 no config -> SKIP, exit 0" "code=$CRED_CODE"

# T3  Installed capability + credential absent => BLOCKING (exit 1), with a rotate pointer.
p=$(new_project "p-missing" "counsel-core, ship-loop")
unset CEOS_TEST_FAKE_KEY
run_cred "$p" "$osNoProbe"
ok=1; outmatch "NOT CONFIGURED" && [ "$CRED_CODE" -eq 1 ] && ok=0
assert $ok "T3 missing key for installed capability -> exit 1" "code=$CRED_CODE"
ok=1; outmatch "example.invalid/rotate" && ok=0
assert $ok "T3 remediation carries the registry rotate pointer"

# T4  Credential present but declared unprobeable => UNKNOWN + the honest reason, never LIVE.
CEOS_TEST_FAKE_KEY="ceos-test-value-not-a-real-secret-0001"
export CEOS_TEST_FAKE_KEY
run_cred "$p" "$osNoProbe" -Probe
ok=1; outmatch "NOT PROBEABLE" && ! outmatch "CRED LIVE" && ok=0
assert $ok "T4 probe:none -> UNKNOWN, never LIVE"
ok=1; outmatch "no unauthenticated endpoint" && ok=0
assert $ok "T4 probe_note is surfaced verbatim"

# T5  *** THE POINT OF THIS SUITE *** unproven liveness is exit 3, never exit 0.
ok=1; [ "$CRED_CODE" -eq 3 ] && ok=0
assert $ok "T5 unproven liveness -> exit 3 (NOT ready)" "code=$CRED_CODE"

# T6  Secrets never appear in output, in any state.
ok=1; printf '%s\n' "$CRED_OUT" | grep -Fq "$CEOS_TEST_FAKE_KEY" || ok=0
assert $ok "T6 secret value never printed"
ok=1; outmatch "fp [0-9a-f]{8}" && ok=0
assert $ok "T6 fingerprint is printed instead of the value"

# T7  Offline default: configured credential, probes not requested => UNKNOWN, exit 3.
run_cred "$p" "$osNoProbe"
ok=1; [ "$CRED_CODE" -eq 3 ] && ok=0
assert $ok "T7 offline default withholds READY" "code=$CRED_CODE"

# T8  A probe declared mutating is refused, not run.
run_cred "$p" "$osMutating" -Probe
ok=1; outmatch "REFUSED" && [ "$CRED_CODE" -eq 3 ] && ok=0
assert $ok "T8 mutating probe refused" "code=$CRED_CODE"

# T9  Registry-authored commands need explicit consent (a modified registry is code exec).
run_cred "$p" "$osCmd" -Probe
ok=1; outmatch "AllowRegistryCommands" && [ "$CRED_CODE" -eq 3 ] && ok=0
assert $ok "T9 cmd-exit0 gated behind consent" "code=$CRED_CODE"

# T10 With consent, the registry command runs and a zero exit reads LIVE.
run_cred "$p" "$osCmd" -Probe -AllowRegistryCommands
ok=1; outmatch "CRED LIVE" && [ "$CRED_CODE" -eq 0 ] && ok=0
assert $ok "T10 consented cmd probe -> LIVE, exit 0" "code=$CRED_CODE"

# T11 Full doctor surfaces the family and refuses to print bare READY while unproven.
doctor_out=$(bash "$DOC" -ProjectDir "$p")
ok=1; printf '%s\n' "$doctor_out" | grep -Eq "UNVERIFIED[[:space:]]+creds" && ok=0
assert $ok "T11 doctor emits the UNVERIFIED severity"
ok=1; printf '%s\n' "$doctor_out" | grep -Eq "RESULT: READY\$" || ok=0
assert $ok "T11 doctor does not report bare READY while credentials are unproven"

unset CEOS_TEST_FAKE_KEY
rm -rf "$SB" 2>/dev/null

echo ""
echo "credential tests: $passed passed, $failed failed"
if [ "$failed" -gt 0 ]; then exit 1; fi
exit 0
