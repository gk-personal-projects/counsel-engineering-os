# Counsel Engineering OS -- repair (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). D-T2-026 S3: restores counsel-OWNED files from the
# SAME runtime version recorded in the ownership manifest. Reuses the tested
# install-plan/install-apply machinery -- repair is a plan whose restorations are approved.
#   - missing owned files: restored
#   - locally-modified owned files: PRESERVED unless -IncludeModified (then backed up + restored)
#   - user-owned files (constitution, settings, config, .gitignore): NEVER touched
#   - source runtime version != manifest runtime version: STOP (that is an update, not a
#     repair -- run the onboard update flow instead). Ambiguity always stops (exit 1).

param(
  [Parameter(Mandatory=$true)][string]$Target,
  [string]$Source = "",
  [switch]$IncludeModified
)
$ErrorActionPreference = "Stop"
function Read-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }

$Target = (Resolve-Path $Target).Path
$manifestPath = Join-Path $Target ".counsel\manifest.json"
if (-not (Test-Path $manifestPath)) { Write-Error "No ownership manifest at $manifestPath - nothing to repair against"; exit 1 }
$mf = Read-Text $manifestPath | ConvertFrom-Json

# resolve source and enforce same-version repair
if (-not $Source) {
  $cacheRoot = Join-Path $env:USERPROFILE ".claude\plugins\cache\counsel-os\counsel"
  $candidate = Join-Path $cacheRoot "$($mf.runtime_version)"
  if (Test-Path $candidate) { $Source = $candidate }
  else {
    $newest = $null
    if (Test-Path $cacheRoot) { $newest = Get-ChildItem $cacheRoot -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 }
    if ($newest) { $Source = $newest.FullName } else { Write-Error "No source available for repair (no plugin cache; pass -Source)"; exit 1 }
  }
}
$Source = (Resolve-Path $Source).Path
$srcVersion = (Read-Text (Join-Path $Source "VERSION")).Trim()
if ($srcVersion -ne "$($mf.runtime_version)") {
  Write-Host "STOP: source runtime is $srcVersion but the manifest records $($mf.runtime_version)." -ForegroundColor Red
  Write-Host "That is an UPDATE, not a repair. Run the onboard update flow (plan + consented apply)." -ForegroundColor Red
  exit 1
}

# read installed layers + mode from config.yaml (control plane)
$cfgPath = Join-Path $Target ".counsel\config.yaml"
$layers = "core"; $mode = "pair"
if (Test-Path $cfgPath) {
  $cfgText = Read-Text $cfgPath
  $mLayers = [regex]::Match($cfgText, "(?m)^installed_layers:\s*\[([^\]]*)\]")
  if ($mLayers.Success) { $layers = ($mLayers.Groups[1].Value -replace "\s", "") }
  $mMode = [regex]::Match($cfgText, "(?m)^mode:\s*(\S+)")
  if ($mMode.Success) { $mode = $mMode.Groups[1].Value }
}

# plan against the version-locked source; keep the existing constitution out of scope
$stage = Join-Path $env:TEMP ("counsel-repair\stage-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install-plan.ps1") `
  -Target $Target -Layers $layers -Source $Source -StageDir $stage -Mode $mode -InstallSettingsBaseline "no" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Repair planning failed"; exit 1 }

$planPath = Join-Path $stage "PLAN.json"
$plan = Read-Text $planPath | ConvertFrom-Json
$restored = @(); $preservedModified = @(); $ambiguous = @()
foreach ($i in $plan.items) {
  if (-not $i.owned) {
    # user-owned staged items must never be applied by repair
    if ($i.class -eq "CREATE" -or $i.class -eq "MERGE") { $i.approved = $false }
    continue
  }
  switch ($i.class) {
    "CREATE"   { $i.approved = $true; $restored += $i.path }            # missing owned -> restore
    "PRESERVE" { }
    "CONFLICT" {
      if ($IncludeModified) { $i.class = "MERGE"; $i.approved = $true; $restored += $i.path }
      else { $preservedModified += $i.path }
    }
    "MERGE"    { $ambiguous += $i.path; $i.approved = $false }          # owned differing without local-mod evidence: ambiguous
    default    { $ambiguous += "$($i.path) (class $($i.class))" }
  }
}
if ($ambiguous.Count -gt 0) {
  Write-Host "STOP: ambiguous ownership state - repair will not guess:" -ForegroundColor Red
  $ambiguous | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Red }
  exit 1
}
[System.IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install-apply.ps1") -PlanPath $planPath
if ($LASTEXITCODE -ne 0) { Write-Error "Repair apply failed"; exit 1 }

Write-Host ""
Write-Host ("REPAIR: restored {0} owned file(s)." -f $restored.Count)
if ($restored.Count -gt 0) { $restored | ForEach-Object { Write-Host "  + $_" } }
if ($preservedModified.Count -gt 0) {
  Write-Host ("Locally-modified owned files PRESERVED ({0}) - rerun with -IncludeModified to restore (originals are backed up):" -f $preservedModified.Count)
  $preservedModified | ForEach-Object { Write-Host "  = $_" }
}
exit 0
