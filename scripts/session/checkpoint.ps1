# Counsel Engineering OS -- atomic session checkpoint (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Implements the ATOMIC-CHECKPOINT invariant (D-T2-018):
# a checkpoint becomes authoritative ONLY after complete capture + validation; on failure the
# previous valid checkpoint remains authoritative and the failure is surfaced explicitly.
#
# Flow: tmp dir -> capture session files + machine/git state -> validate (parse, uniqueness,
# HEAD re-verification) -> promote (rename) -> only then update LAST-CHECKPOINT pointer.
#
# Behavior contract (documented per ruling A8/D-T2-009):
#   Files written: CHECKPOINTS/<stamp>-<label>/* and LAST-CHECKPOINT.txt inside -SessionDir.
#   Network: none. External commands: git only. Exit codes: 0 success, 1 failure (previous
#   checkpoint untouched). Failed attempts are preserved as CHECKPOINTS/FAILED-* for forensics
#   and are never selected as restore targets.

param(
  [string]$Workspace = (Get-Location).Path,
  [string]$SessionDir = "",
  [string]$Label = "manual"
)

$ErrorActionPreference = "Stop"
if (-not $SessionDir) { $SessionDir = Join-Path $Workspace ".counsel\session" }
if (-not (Test-Path $SessionDir)) { Write-Error "Session dir not found: $SessionDir"; exit 1 }

# UTF-8 (no BOM) writer tolerant of read-only / cloud-placeholder files (D-T2-010).
function Write-FileSafe([string]$Path, [string]$Content) {
  if (Test-Path $Path) {
    try { (Get-Item $Path -Force).Attributes = 'Normal' } catch {}
    Remove-Item $Path -Force
  }
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-GitSnapshot([string]$RepoPath) {
  # Never throws. Returns an entry; failures are recorded, unborn repos are a VALID state.
  $ErrorActionPreference = "Continue"
  $entry = [ordered]@{ root = $null; branch = $null; head = $null; unborn = $false; status = @(); error = $null }
  $top = (& git -C $RepoPath rev-parse --show-toplevel 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $top) { $entry.root = $RepoPath; $entry.error = "git cannot resolve repository (corrupt .git or git failure)"; return $entry }
  $entry.root = $top
  $entry.branch = (& git -C $RepoPath branch --show-current 2>$null | Out-String).Trim()
  $head = (& git -C $RepoPath rev-parse --verify HEAD 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $head) { $entry.unborn = $true }
  else { $entry.head = $head }
  $entry.status = @(& git -C $RepoPath status --short 2>$null)
  return $entry
}

$CheckpointRoot = Join-Path $SessionDir "CHECKPOINTS"
New-Item -ItemType Directory -Force -Path $CheckpointRoot | Out-Null

# Surface residue from prior aborted/failed attempts (never restore targets).
Get-ChildItem $CheckpointRoot -Directory -Force | Where-Object { $_.Name -like ".tmp-*" -or $_.Name -like "FAILED-*" } |
  ForEach-Object { Write-Warning "Residue from a prior incomplete/failed checkpoint attempt: $($_.Name)" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$final = Join-Path $CheckpointRoot "$stamp-$Label"
$tmp   = Join-Path $CheckpointRoot ".tmp-$stamp-$Label"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$failReasons = @()

# --- CAPTURE ---------------------------------------------------------------
$sessionFiles = @("RESTORE.md","STATE.json","DECISIONS.md","OPEN-ITEMS.md","ARTIFACT-REGISTRY.md","CAPSULE.md")
$copied = @()
foreach ($name in $sessionFiles) {
  $src = Join-Path $SessionDir $name
  if (Test-Path $src) { Copy-Item $src (Join-Path $tmp $name); $copied += $name }
}

# Repo discovery: the workspace itself if it is a repo, plus first-level children.
$candidates = @()
if (Test-Path (Join-Path $Workspace ".git")) { $candidates += $Workspace }
Get-ChildItem -Path $Workspace -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  if (Test-Path (Join-Path $_.FullName ".git")) { $candidates += $_.FullName }
}

$repos = @(); $seenRoots = @{}
foreach ($c in $candidates) {
  $snap = Get-GitSnapshot $c
  $key = ($snap.root -replace '\\','/').ToLower()
  if ($seenRoots.ContainsKey($key)) { continue }   # duplicate discovery (junctions/links) -> dedupe
  $seenRoots[$key] = $true
  $repos += $snap
}

$machine = [ordered]@{
  schema_version  = 2
  timestamp_local = (Get-Date).ToString("o")
  label           = $Label
  workspace       = $Workspace
  computer        = $env:COMPUTERNAME
  repositories    = $repos
}
Write-FileSafe (Join-Path $tmp "MACHINE-STATE.json") ($machine | ConvertTo-Json -Depth 8)

# --- VALIDATE --------------------------------------------------------------
# 1. MACHINE-STATE parses.
try { $parsed = Get-Content (Join-Path $tmp "MACHINE-STATE.json") -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $failReasons += "MACHINE-STATE.json does not parse: $($_.Exception.Message)" }

# 2. Required session files that existed at source were copied.
foreach ($name in @("RESTORE.md","STATE.json")) {
  if ((Test-Path (Join-Path $SessionDir $name)) -and -not (Test-Path (Join-Path $tmp $name))) {
    $failReasons += "Required session file failed to copy: $name"
  }
}

# 3. No repo capture errors; roots unique; recorded HEADs re-verified against live git.
if ($parsed) {
  $roots = @{}
  foreach ($r in $parsed.repositories) {
    if ($r.error) { $failReasons += "Repository capture error at '$($r.root)': $($r.error)" }
    if ($r.root) {
      $k = ($r.root -replace '\\','/').ToLower()
      if ($roots.ContainsKey($k)) { $failReasons += "Duplicate repository entry: $($r.root)" }
      $roots[$k] = $true
    }
    if ($r.head) {
      $ErrorActionPreference = "Continue"
      $live = (& git -C $r.root rev-parse --verify HEAD 2>$null | Out-String).Trim()
      $ErrorActionPreference = "Stop"
      if ($live -ne $r.head) { $failReasons += "HEAD drift during capture at '$($r.root)': recorded $($r.head), live $live" }
    }
  }
}

# --- PROMOTE or FAIL -------------------------------------------------------
if ($failReasons.Count -gt 0) {
  $failDir = Join-Path $CheckpointRoot "FAILED-$stamp-$Label"
  Rename-Item $tmp $failDir
  Write-FileSafe (Join-Path $failDir "FAILURE.txt") (($failReasons -join "`n") + "`n")
  Write-Host "CHECKPOINT FAILED -- previous valid checkpoint remains authoritative." -ForegroundColor Red
  $failReasons | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host "Forensics preserved at: $failDir"
  exit 1
}

Rename-Item $tmp $final
Write-FileSafe (Join-Path $SessionDir "LAST-CHECKPOINT.txt") ($final + "`n")
Write-Host "Checkpoint created: $final"
Write-Host ("Captured: {0} session file(s), {1} repositorie(s)." -f $copied.Count, $repos.Count)
exit 0
