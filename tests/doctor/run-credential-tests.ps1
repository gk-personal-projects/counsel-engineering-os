# Counsel Engineering OS -- credential liveness acceptance tests (D-T2-030)
# Provenance: ORIGINAL (Apache-2.0). Runs in an isolated sandbox under $env:TEMP.
# Exit 0 = all pass. NO TEST HERE TOUCHES THE NETWORK: every case uses a synthetic registry
# with probes that resolve locally, so the suite is deterministic and free to run.
#
# The load-bearing assertion is T5/T6: unproven liveness must NOT be reported as READY.

param(
  [string]$ScriptsDir = (Join-Path $PSScriptRoot "..\..\scripts")
)
$ErrorActionPreference = "Stop"
$ScriptsDir = (Resolve-Path $ScriptsDir).Path
$CRED = Join-Path $ScriptsDir "doctor-credentials.ps1"
$DOC  = Join-Path $ScriptsDir "doctor.ps1"

$SB = Join-Path $env:TEMP ("ceos-cred-tests-" + (Get-Date -Format "yyyyMMddHHmmss"))
New-Item -ItemType Directory -Force $SB | Out-Null
$script:passed = 0; $script:failed = 0

function Assert([bool]$Cond, [string]$Name, [string]$Detail = "") {
  if ($Cond) { $script:passed++; Write-Host "PASS  $Name" }
  else { $script:failed++; Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red }
}

# A synthetic OS dir: registry only, so tests never depend on the shipped registry's content.
function New-OsDir([string]$Name, [string]$RegistryBody) {
  $os = Join-Path $SB $Name
  New-Item -ItemType Directory -Force (Join-Path $os "registry") | Out-Null
  Set-Content -Encoding UTF8 (Join-Path $os "registry\dependencies.yaml") $RegistryBody
  return $os
}
function New-Project([string]$Name, [string]$Layers) {
  $p = Join-Path $SB $Name
  New-Item -ItemType Directory -Force (Join-Path $p ".counsel") | Out-Null
  if ($Layers -ne $null -and $Layers -ne "") {
    Set-Content -Encoding UTF8 (Join-Path $p ".counsel\config.yaml") "installed_layers: [$Layers]`nmode: BUILD"
  }
  return $p
}
function Run-Cred([string]$Proj, [string]$Os, [string[]]$Extra) {
  $a = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$CRED,"-ProjectDir",$Proj,"-OsDir",$Os,"-NoCache")
  if ($Extra) { $a += $Extra }
  $out = & powershell @a
  return @{ out = ($out -join "`n"); code = $LASTEXITCODE }
}

# Registry A: one env-var credential, no probe available (honest UNKNOWN).
$regNoProbe = @'
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
'@

# Registry B: same credential, but the probe is declared mutating (must be refused).
$regMutating = $regNoProbe -replace 'probe: none', 'probe: http-get-200' -replace 'mutating: false', 'mutating: true'

# Registry C: probe cmd-exit0 (registry-authored exec -- must require explicit consent).
$regCmd = $regNoProbe -replace 'probe: none', "probe: cmd-exit0`n      probe_cmd: `"cmd /c exit 0`""

$osNoProbe  = New-OsDir "os-noprobe"  $regNoProbe
$osMutating = New-OsDir "os-mutating" $regMutating
$osCmd      = New-OsDir "os-cmd"      $regCmd

# ---------------------------------------------------------------------------
# T1  Capability not installed => credential is not applicable, never blocking.
$p = New-Project "p-nolayer" "counsel-core"
$r = Run-Cred $p $osNoProbe @()
Assert ($r.out -match "CRED SKIP" -and $r.code -eq 0) "T1 uninstalled capability -> SKIP, exit 0" "code=$($r.code)"

# T2  No config.yaml at all => unknown install set, nothing is asserted as broken.
$p = New-Project "p-noconfig" ""
$r = Run-Cred $p $osNoProbe @()
Assert ($r.out -match "installed capabilities unknown" -and $r.code -eq 0) "T2 no config -> SKIP, exit 0" "code=$($r.code)"

# T3  Installed capability + credential absent => BLOCKING (exit 1), with a rotate pointer.
$p = New-Project "p-missing" "counsel-core, ship-loop"
if (Test-Path Env:\CEOS_TEST_FAKE_KEY) { Remove-Item Env:\CEOS_TEST_FAKE_KEY }
$r = Run-Cred $p $osNoProbe @()
Assert ($r.out -match "NOT CONFIGURED" -and $r.code -eq 1) "T3 missing key for installed capability -> exit 1" "code=$($r.code)"
Assert ($r.out -match "example.invalid/rotate") "T3 remediation carries the registry rotate pointer"

# T4  Credential present but declared unprobeable => UNKNOWN + the honest reason, never LIVE.
$env:CEOS_TEST_FAKE_KEY = "ceos-test-value-not-a-real-secret-0001"
$r = Run-Cred $p $osNoProbe @("-Probe")
Assert ($r.out -match "NOT PROBEABLE" -and $r.out -notmatch "CRED LIVE") "T4 probe:none -> UNKNOWN, never LIVE"
Assert ($r.out -match "no unauthenticated endpoint") "T4 probe_note is surfaced verbatim"

# T5  *** THE POINT OF THIS SUITE *** unproven liveness is exit 3, never exit 0.
Assert ($r.code -eq 3) "T5 unproven liveness -> exit 3 (NOT ready)" "code=$($r.code)"

# T6  Secrets never appear in output, in any state.
Assert ($r.out -notmatch [regex]::Escape($env:CEOS_TEST_FAKE_KEY)) "T6 secret value never printed"
Assert ($r.out -match "fp [0-9a-f]{8}") "T6 fingerprint is printed instead of the value"

# T7  Offline default: configured credential, probes not requested => UNKNOWN, exit 3.
$r = Run-Cred $p $osNoProbe @()
Assert ($r.code -eq 3) "T7 offline default withholds READY" "code=$($r.code)"

# T8  A probe declared mutating is refused, not run.
$r = Run-Cred $p $osMutating @("-Probe")
Assert ($r.out -match "REFUSED" -and $r.code -eq 3) "T8 mutating probe refused" "code=$($r.code)"

# T9  Registry-authored commands need explicit consent (a modified registry is code exec).
$r = Run-Cred $p $osCmd @("-Probe")
Assert ($r.out -match "AllowRegistryCommands" -and $r.code -eq 3) "T9 cmd-exit0 gated behind consent" "code=$($r.code)"

# T10 With consent, the registry command runs and a zero exit reads LIVE.
$r = Run-Cred $p $osCmd @("-Probe","-AllowRegistryCommands")
Assert ($r.out -match "CRED LIVE" -and $r.code -eq 0) "T10 consented cmd probe -> LIVE, exit 0" "code=$($r.code)"

# T11 Full doctor surfaces the family and refuses to print bare READY while unproven.
$r2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $DOC -ProjectDir $p
$doctorOut = ($r2 -join "`n")
Assert ($doctorOut -match "UNVERIFIED\s+creds") "T11 doctor emits the UNVERIFIED severity"
Assert ($doctorOut -notmatch "RESULT: READY`n" -and $doctorOut -notmatch "RESULT: READY$") "T11 doctor does not report bare READY while credentials are unproven"

if (Test-Path Env:\CEOS_TEST_FAKE_KEY) { Remove-Item Env:\CEOS_TEST_FAKE_KEY }
Remove-Item $SB -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "credential tests: $($script:passed) passed, $($script:failed) failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
