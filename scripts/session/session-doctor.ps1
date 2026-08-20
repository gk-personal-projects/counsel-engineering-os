# Counsel Engineering OS -- session-state doctor (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0).
# Read-only health check of the continuity system. Severities: FAIL (recovery at risk),
# WARN (degraded/attention), INFO. Exit: 0 healthy, 1 FAIL present, 2 WARN present.

param(
  [string]$Workspace = (Get-Location).Path,
  [string]$SessionDir = "",
  [int]$MaxCheckpointAgeHours = 24
)
$ErrorActionPreference = "Stop"
if (-not $SessionDir) { $SessionDir = Join-Path $Workspace ".counsel\session" }

$fail = 0; $warn = 0
function Report([string]$Level, [string]$Msg) {
  if ($Level -eq "FAIL") { $script:fail++; Write-Host "FAIL  $Msg" -ForegroundColor Red }
  elseif ($Level -eq "WARN") { $script:warn++; Write-Host "WARN  $Msg" -ForegroundColor Yellow }
  else { Write-Host "OK    $Msg" }
}

if (-not (Test-Path $SessionDir)) { Report FAIL "Session dir missing: $SessionDir"; exit 1 }
Report OK "Session dir present: $SessionDir"

foreach ($name in @("RESTORE.md","STATE.json")) {
  $p = Join-Path $SessionDir $name
  if (Test-Path $p) { Report OK "$name present" } else { Report FAIL "$name missing" }
}
$statePath = Join-Path $SessionDir "STATE.json"
if (Test-Path $statePath) {
  try { Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; Report OK "STATE.json parses" }
  catch { Report FAIL "STATE.json does not parse: $($_.Exception.Message)" }
}
# STALE-RESTORE: on harnesses without lifecycle hooks, a RESTORE older than recent work
# is drift, not truth (runtime/HARNESS.md degraded mode). Compare RESTORE mtime to the
# newest commit time in the workspace repo, if any.
$restorePath = Join-Path $SessionDir "RESTORE.md"
if (Test-Path $restorePath) {
  $ErrorActionPreference = "Continue"
  $lastCommitUnix = (& git -C $Workspace log -1 --format=%ct 2>$null | Out-String).Trim()
  $ErrorActionPreference = "Stop"
  if ($lastCommitUnix -match '^\d+$') {
    $lastCommit = ([datetime]'1970-01-01Z').AddSeconds([long]$lastCommitUnix).ToLocalTime()
    $restoreMtime = (Get-Item $restorePath).LastWriteTime
    if ($restoreMtime -lt $lastCommit) {
      Report WARN ("STALE-RESTORE: RESTORE.md ({0:g}) predates the newest commit ({1:g}) -- treat as drift; checkpoint or restore before trusting it" -f $restoreMtime, $lastCommit)
    } else { Report OK "RESTORE.md is newer than the last commit" }
  }
}

$capsule = Join-Path $SessionDir "CAPSULE.md"
if (Test-Path $capsule) {
  $chars = (Get-Content $capsule -Raw -Encoding UTF8).Length
  if ($chars -gt 6000) { Report WARN "CAPSULE.md is ~$([math]::Round($chars/4)) tokens -- capsule budget is ~1,000 (D-T2-017); trim it" }
  else { Report OK "CAPSULE.md within budget (~$([math]::Round($chars/4)) tokens)" }
}

$root = Join-Path $SessionDir "CHECKPOINTS"
if (-not (Test-Path $root)) { Report WARN "No CHECKPOINTS directory yet" }
else {
  Get-ChildItem $root -Directory -Force | Where-Object { $_.Name -like ".tmp-*" } |
    ForEach-Object { Report WARN "Aborted checkpoint residue: $($_.Name) (safe to archive/delete; never a restore target)" }
  Get-ChildItem $root -Directory -Force | Where-Object { $_.Name -like "FAILED-*" } |
    ForEach-Object { Report WARN "Failed checkpoint preserved: $($_.Name) (see FAILURE.txt)" }

  $ptrFile = Join-Path $SessionDir "LAST-CHECKPOINT.txt"
  if (-not (Test-Path $ptrFile)) { Report FAIL "LAST-CHECKPOINT.txt missing" }
  else {
    $ptr = (Get-Content $ptrFile -Raw -Encoding UTF8).Trim()
    $leaf = Split-Path $ptr -Leaf
    if (-not (Test-Path $ptr)) { Report FAIL "Stale pointer: $ptr does not exist" }
    elseif ($leaf -like ".tmp-*" -or $leaf -like "FAILED-*") { Report FAIL "Pointer targets an invalid checkpoint: $leaf" }
    elseif (-not (Test-Path (Join-Path $ptr "MACHINE-STATE.json"))) { Report FAIL "Pointed checkpoint incomplete (no MACHINE-STATE.json): $leaf" }
    else {
      try {
        $ms = Get-Content (Join-Path $ptr "MACHINE-STATE.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        Report OK "Pointer -> valid checkpoint: $leaf"
        $age = (Get-Date) - [datetime]$ms.timestamp_local
        if ($age.TotalHours -gt $MaxCheckpointAgeHours) { Report WARN ("Last checkpoint is {0:N1}h old (max {1}h)" -f $age.TotalHours, $MaxCheckpointAgeHours) }
        else { Report OK ("Last checkpoint age {0:N1}h" -f $age.TotalHours) }
        foreach ($r in $ms.repositories) {
          if (-not $r.root) { continue }
          if (-not (Test-Path $r.root)) { Report WARN "Recorded repo missing on disk: $($r.root)"; continue }
          $ErrorActionPreference = "Continue"
          $live = (& git -C $r.root rev-parse --verify HEAD 2>$null | Out-String).Trim()
          $ErrorActionPreference = "Stop"
          $name = Split-Path $r.root -Leaf
          if ($r.head -and $live -and ($live -ne $r.head)) { Report WARN "Git drift at ${name}: recorded $($r.head.Substring(0,7)), live $($live.Substring(0,7)) -- reconcile via restore" }
          else { Report OK "Git consistent: $name" }
        }
      } catch { Report FAIL "Pointed checkpoint MACHINE-STATE.json invalid: $($_.Exception.Message)" }
    }
  }
}

Write-Host ""
if ($fail -gt 0) { Write-Host "SESSION DOCTOR: FAIL ($fail fail, $warn warn)"; exit 1 }
if ($warn -gt 0) { Write-Host "SESSION DOCTOR: WARN ($warn warn)"; exit 2 }
Write-Host "SESSION DOCTOR: HEALTHY"; exit 0
