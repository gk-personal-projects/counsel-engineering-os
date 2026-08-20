# Counsel Engineering OS -- session restore reader (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0).
# Reads durable session state for recovery. Never writes authoritative state. If the
# LAST-CHECKPOINT pointer is missing/stale/invalid, falls back to the newest VALID completed
# checkpoint and surfaces the drift explicitly (D-T2-018: incomplete/failed checkpoints are
# never restore targets). Also reports live git state and drift vs the recorded snapshot.

param(
  [string]$Workspace = (Get-Location).Path,
  [string]$SessionDir = ""
)
$ErrorActionPreference = "Stop"
if (-not $SessionDir) { $SessionDir = Join-Path $Workspace ".counsel\session" }
if (-not (Test-Path $SessionDir)) { Write-Error "Session dir not found: $SessionDir"; exit 1 }

function Test-ValidCheckpoint([string]$Dir) {
  if (-not (Test-Path $Dir -PathType Container)) { return $false }
  $leaf = Split-Path $Dir -Leaf
  if ($leaf -like ".tmp-*" -or $leaf -like "FAILED-*") { return $false }
  $ms = Join-Path $Dir "MACHINE-STATE.json"
  if (-not (Test-Path $ms)) { return $false }
  try { Get-Content $ms -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; return $true } catch { return $false }
}

$CheckpointRoot = Join-Path $SessionDir "CHECKPOINTS"
$target = $null; $drift = @()

$ptrFile = Join-Path $SessionDir "LAST-CHECKPOINT.txt"
if (Test-Path $ptrFile) {
  $ptr = (Get-Content $ptrFile -Raw -Encoding UTF8).Trim()
  if (Test-ValidCheckpoint $ptr) { $target = $ptr }
  else { $drift += "STALE POINTER: LAST-CHECKPOINT.txt -> '$ptr' is missing or not a valid completed checkpoint." }
} else { $drift += "LAST-CHECKPOINT.txt is missing." }

if (-not $target -and (Test-Path $CheckpointRoot)) {
  $fallback = Get-ChildItem $CheckpointRoot -Directory | Where-Object { Test-ValidCheckpoint $_.FullName } |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($fallback) { $target = $fallback.FullName; $drift += "FALLBACK: using newest valid checkpoint '$($fallback.Name)'." }
  else { $drift += "NO VALID CHECKPOINT FOUND under $CheckpointRoot." }
}

Write-Host "=== RESTORE.md ==="
$restore = Join-Path $SessionDir "RESTORE.md"
if (Test-Path $restore) { Get-Content $restore -Encoding UTF8 } else { Write-Host "(missing)" }
Write-Host "`n=== STATE.json ==="
$state = Join-Path $SessionDir "STATE.json"
if (Test-Path $state) { Get-Content $state -Encoding UTF8 } else { Write-Host "(missing)" }
Write-Host "`n=== CAPSULE.md ==="
$capsule = Join-Path $SessionDir "CAPSULE.md"
if (Test-Path $capsule) { Get-Content $capsule -Encoding UTF8 } else { Write-Host "(none)" }

Write-Host "`n=== CHECKPOINT ==="
if ($target) {
  Write-Host $target
  $recorded = Get-Content (Join-Path $target "MACHINE-STATE.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Host "`n=== GIT DRIFT (recorded vs live) ==="
  foreach ($r in $recorded.repositories) {
    if (-not $r.root) { continue }
    $ErrorActionPreference = "Continue"
    $live = (& git -C $r.root rev-parse --verify HEAD 2>$null | Out-String).Trim()
    $liveDirty = @(& git -C $r.root status --short 2>$null).Count
    $ErrorActionPreference = "Stop"
    $name = Split-Path $r.root -Leaf
    if (-not (Test-Path $r.root)) { $drift += "MISSING REPO: $($r.root) recorded but absent on disk."; continue }
    if ($r.unborn -and $live) { $drift += "DRIFT ${name}: recorded unborn, live HEAD $live" }
    elseif ($r.head -and ($live -ne $r.head)) { $drift += "DRIFT ${name}: recorded $($r.head), live $live" }
    else { Write-Host ("  {0}: OK ({1}{2})" -f $name, $(if ($r.unborn) { "unborn" } else { $r.head.Substring(0,7) }), $(if ($liveDirty -gt 0) { ", dirty:$liveDirty" } else { "" })) }
  }
}

if ($drift.Count -gt 0) {
  Write-Host "`n=== DRIFT / WARNINGS -- reconcile before resuming (do not pick a winner silently) ===" -ForegroundColor Yellow
  $drift | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
  exit 2
}
Write-Host "`nState consistent. Resume from RESTORE.md 'exact next action'."
exit 0
