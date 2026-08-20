# Counsel Engineering OS -- consented install applier (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Implements D-T2-026 R5-S2 steps 5-10.
# Applies a PLAN.json produced by install-plan.ps1:
#   - refuses if the target drifted since planning (stale plan)
#   - applies CREATE items and MERGE items explicitly approved (approved==true)
#   - NEVER applies CONFLICT items; never blind-overwrites anything
#   - backs up every pre-existing file it replaces to .counsel/originals/<stamp>/
#   - writes atomically (temp file + rename, same directory)
#   - upserts the ownership manifest .counsel/manifest.json (atomic)
#   - post-verifies every applied file hash
# Exit: 0 = applied + verified; 1 = failure/stale (target untouched or partially
# applied files are reported explicitly -- nothing is silently half-done).

param(
  [Parameter(Mandatory=$true)][string]$PlanPath
)
$ErrorActionPreference = "Stop"

function Read-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }
function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower() }
function Write-Atomic([string]$Path, [string]$SourceFile) {
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = Join-Path $dir (".tmp-" + [System.IO.Path]::GetFileName($Path))
  Copy-Item $SourceFile $tmp -Force
  if (Test-Path $Path) { try { (Get-Item $Path -Force).Attributes = 'Normal' } catch {}; Remove-Item $Path -Force }
  Rename-Item $tmp $Path
}

if (-not (Test-Path $PlanPath)) { Write-Error "Plan not found: $PlanPath"; exit 1 }
$plan = Read-Text $PlanPath | ConvertFrom-Json
$Target = $plan.target
$StageDir = $plan.stage_dir
if (-not (Test-Path $Target)) { Write-Error "Plan target missing: $Target"; exit 1 }
if (-not (Test-Path $StageDir)) { Write-Error "Stage dir missing (re-run plan): $StageDir"; exit 1 }

# --- stale check: every item's target must match the state recorded at plan time
$stale = @()
foreach ($i in $plan.items) {
  $tp = Join-Path $Target $i.path
  if ($null -eq $i.sha_target) {
    if (Test-Path $tp) { $stale += "$($i.path) (appeared after planning)" }
  } else {
    if (-not (Test-Path $tp)) { $stale += "$($i.path) (vanished after planning)" }
    elseif ((Get-Sha $tp) -ne $i.sha_target) { $stale += "$($i.path) (changed after planning)" }
  }
}
if ($stale.Count -gt 0) {
  Write-Host "STALE PLAN -- target drifted since planning. Nothing applied. Re-run install-plan.ps1." -ForegroundColor Red
  $stale | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Red }
  exit 1
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$originalsDir = Join-Path $Target (".counsel\originals\" + $stamp)
$applied = @(); $removed = @(); $skipped = @(); $declined = @(); $conflicts = @(); $failures = @()

foreach ($i in $plan.items) {
  $tp = Join-Path $Target $i.path
  $sp = Join-Path $StageDir ($i.path -replace "/", "\")
  switch ($i.class) {
    "PRESERVE" { $skipped += $i.path; continue }
    "CONFLICT" { $conflicts += $i.path; continue }
    "CREATE" {
      if ($i.approved -eq $false) { $declined += $i.path; continue }
      Write-Atomic $tp $sp
      $applied += $i
      continue
    }
    "MERGE" {
      if ($i.approved -ne $true) { $declined += $i.path; continue }
      if (-not (Test-Path $originalsDir)) { New-Item -ItemType Directory -Force -Path $originalsDir | Out-Null }
      $backup = Join-Path $originalsDir ($i.path -replace "/", "\")
      $bdir = Split-Path $backup -Parent
      if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Force -Path $bdir | Out-Null }
      Copy-Item $tp $backup -Force
      Write-Atomic $tp $sp
      $applied += $i
      continue
    }
    "REMOVE" {
      # Migration-only: counsel-owned, unmodified file whose home moved. Backed up, then deleted.
      if ($i.approved -ne $true) { $declined += $i.path; continue }
      if (-not (Test-Path $originalsDir)) { New-Item -ItemType Directory -Force -Path $originalsDir | Out-Null }
      $backup = Join-Path $originalsDir ($i.path -replace "/", "\")
      $bdir = Split-Path $backup -Parent
      if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Force -Path $bdir | Out-Null }
      Copy-Item $tp $backup -Force
      Remove-Item $tp -Force
      $removed += $i
      continue
    }
    default { $failures += "$($i.path): unknown class '$($i.class)'" }
  }
}

# --- post-verify every applied file (and every removal)
foreach ($i in $applied) {
  $tp = Join-Path $Target $i.path
  $sha = Get-Sha $tp
  if ($sha -ne $i.sha_staged) { $failures += "$($i.path): post-apply hash mismatch (expected $($i.sha_staged), got $sha)" }
}
foreach ($i in $removed) {
  $tp = Join-Path $Target $i.path
  if (Test-Path $tp) { $failures += "$($i.path): REMOVE approved but file still present" }
}

# --- manifest upsert (atomic)
$manifestPath = Join-Path $Target ".counsel\manifest.json"
$mf = $null
if (Test-Path $manifestPath) {
  try { $mf = Read-Text $manifestPath | ConvertFrom-Json } catch { $failures += "existing manifest unreadable: $($_.Exception.Message)" }
}
if (-not $mf) {
  $mf = [pscustomobject]@{ schema_version = 1; runtime_version = $plan.runtime_version;
                           control_plane_schema = $plan.control_plane_schema; files = @() }
}
$mf.runtime_version = $plan.runtime_version
$mf.control_plane_schema = $plan.control_plane_schema
$fileList = @($mf.files | Where-Object { $_ })
foreach ($i in $applied) {
  $entry = [pscustomobject]@{ path = $i.path; owned = $i.owned; sha256 = $i.sha_staged
                              runtime_version = $plan.runtime_version; applied_class = $i.class
                              applied_at = (Get-Date).ToString("o") }
  if ($i.PSObject.Properties.Name -contains "region_sha" -and $i.region_sha) {
    $entry | Add-Member -MemberType NoteProperty -Name region_sha256 -Value $i.region_sha
  }
  $fileList = @($fileList | Where-Object { $_.path -ne $i.path }) + $entry
}
foreach ($i in $removed) { $fileList = @($fileList | Where-Object { $_.path -ne $i.path }) }
$mf.files = $fileList
$mfDir = Split-Path $manifestPath -Parent
if (-not (Test-Path $mfDir)) { New-Item -ItemType Directory -Force -Path $mfDir | Out-Null }
$mfTmp = Join-Path $mfDir ".tmp-manifest.json"
[System.IO.File]::WriteAllText($mfTmp, ($mf | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
Rename-Item $mfTmp $manifestPath

# --- report
Write-Host ("APPLIED  : {0}" -f $applied.Count)
Write-Host ("REMOVED  : {0}" -f $removed.Count)
Write-Host ("PRESERVED: {0}" -f $skipped.Count)
Write-Host ("DECLINED/UNAPPROVED (untouched): {0}" -f $declined.Count)
if ($declined.Count -gt 0) { $declined | ForEach-Object { Write-Host "  - $_" } }
if ($conflicts.Count -gt 0) {
  Write-Host "CONFLICTS (untouched -- resolve, then re-plan):" -ForegroundColor Yellow
  $conflicts | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
}
if ($applied.Count -gt 0 -and (Test-Path $originalsDir)) { Write-Host "Originals backed up: $originalsDir" }
Write-Host "Manifest: $manifestPath"
if ($failures.Count -gt 0) {
  Write-Host "FAILURES:" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Red }
  exit 1
}
Write-Host "Post-verify: all applied files match staged hashes."
exit 0
