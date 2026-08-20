# Counsel Engineering OS -- repair/uninstall/doctor lifecycle tests (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). D-T2-026 R5-S3 acceptance: repair restores missing
# owned files, preserves modified ones without the explicit flag, restores with it (backed
# up); uninstall removes only unmodified owned files, preserves user work; doctor reports
# manifest integrity. Exit 0 = all pass.

param([string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = "Stop"
$plan = Join-Path $RepoRoot "scripts\install\install-plan.ps1"
$apply = Join-Path $RepoRoot "scripts\install\install-apply.ps1"
$repair = Join-Path $RepoRoot "scripts\install\repair.ps1"
$uninstall = Join-Path $RepoRoot "scripts\install\uninstall.ps1"
$doctor = Join-Path $RepoRoot "scripts\doctor.ps1"
$work = Join-Path $env:TEMP ("counsel-lifecycle-tests-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$script:pass = 0; $script:fail = 0
function Assert([bool]$Cond, [string]$Name) {
  if ($Cond) { $script:pass++; Write-Host "PASS  $Name" }
  else { $script:fail++; Write-Host "FAIL  $Name" -ForegroundColor Red }
}
function Install-Fresh([string]$Tgt) {
  New-Item -ItemType Directory -Force -Path $Tgt | Out-Null
  $cm = Join-Path $work "cm.txt"
  if (-not (Test-Path $cm)) { [System.IO.File]::WriteAllText($cm, "# Test constitution`n", (New-Object System.Text.UTF8Encoding($false))) }
  $st = Join-Path $work ("stage-" + (Split-Path $Tgt -Leaf))
  & $plan -Target $Tgt -Layers "core,builder" -Source $RepoRoot -StageDir $st -ClaudeMdContentPath $cm | Out-Null
  & $apply -PlanPath (Join-Path $st "PLAN.json") | Out-Null
}

# ---------- L1: repair restores a missing owned file ------------------------
$t1 = Join-Path $work "l1"; Install-Fresh $t1
Remove-Item (Join-Path $t1 ".counsel\rules\evidence.md") -Force
& $repair -Target $t1 -Source $RepoRoot | Out-Null
Assert ($LASTEXITCODE -eq 0) "L1 repair exits 0"
Assert (Test-Path (Join-Path $t1 ".counsel\rules\evidence.md")) "L1 missing owned file restored"

# ---------- L2: repair preserves modified owned file without flag -----------
$authPath = Join-Path $t1 ".counsel\rules\authority.md"
[System.IO.File]::AppendAllText($authPath, "`nLOCAL EDIT`n")
& $repair -Target $t1 -Source $RepoRoot | Out-Null
Assert ($LASTEXITCODE -eq 0) "L2 repair exits 0 with modified file present"
Assert (([System.IO.File]::ReadAllText($authPath)) -match "LOCAL EDIT") "L2 modified owned file preserved without -IncludeModified"

# ---------- L3: repair -IncludeModified restores + backs up -----------------
& $repair -Target $t1 -Source $RepoRoot -IncludeModified | Out-Null
Assert ($LASTEXITCODE -eq 0) "L3 repair -IncludeModified exits 0"
Assert (-not (([System.IO.File]::ReadAllText($authPath)) -match "LOCAL EDIT")) "L3 modified owned file restored"
$bk = Get-ChildItem (Join-Path $t1 ".counsel\originals") -Recurse -Filter "authority.md" -ErrorAction SilentlyContinue | Select-Object -First 1
Assert ($null -ne $bk -and (([System.IO.File]::ReadAllText($bk.FullName)) -match "LOCAL EDIT")) "L3 pre-repair content backed up"

# ---------- L4: repair refuses version mismatch (update masquerade) ---------
$mfPath = Join-Path $t1 ".counsel\manifest.json"
$mfObj = [System.IO.File]::ReadAllText($mfPath) | ConvertFrom-Json
$origVer = $mfObj.runtime_version
$mfObj.runtime_version = "0.0.9-test"
[System.IO.File]::WriteAllText($mfPath, ($mfObj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
& $repair -Target $t1 -Source $RepoRoot | Out-Null
Assert ($LASTEXITCODE -eq 1) "L4 repair STOPS on runtime version mismatch (update, not repair)"
$mfObj.runtime_version = $origVer
[System.IO.File]::WriteAllText($mfPath, ($mfObj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

# ---------- L5: doctor detects missing owned file as BLOCKING ---------------
Remove-Item (Join-Path $t1 ".counsel\rules\safety-base.md") -Force
$dOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $doctor -ProjectDir $t1 -OsDir $RepoRoot | Out-String
Assert ($LASTEXITCODE -eq 1) "L5 doctor exits 1 (blocking) on missing owned file"
Assert ($dOut -match "owned file MISSING: .counsel/rules/safety-base.md") "L5 doctor names the missing owned file"
& $repair -Target $t1 -Source $RepoRoot | Out-Null
Assert (Test-Path (Join-Path $t1 ".counsel\rules\safety-base.md")) "L5 repair fixes it"

# ---------- L6: uninstall removes owned, preserves user work ----------------
$t6 = Join-Path $work "l6"; Install-Fresh $t6
# simulate real use: user modifies one owned session file + owns their constitution
$restorePath = Join-Path $t6 ".counsel\session\RESTORE.md"
[System.IO.File]::AppendAllText($restorePath, "`nreal session state`n")
& $uninstall -Target $t6 | Out-Null
Assert ($LASTEXITCODE -eq 0) "L6 uninstall exits 0"
Assert (-not (Test-Path (Join-Path $t6 ".counsel\rules\evidence.md"))) "L6 owned rules removed"
Assert (-not (Test-Path (Join-Path $t6 ".claude\agents\tech-lead.md"))) "L6 owned agents removed"
Assert (Test-Path (Join-Path $t6 "CLAUDE.md")) "L6 user constitution preserved"
Assert (Test-Path (Join-Path $t6 ".counsel\config.yaml")) "L6 user config preserved"
Assert (Test-Path $restorePath) "L6 modified session file (user work) preserved"
Assert (-not (Test-Path (Join-Path $t6 ".counsel\manifest.json"))) "L6 live manifest removed"
$arch = Get-ChildItem (Join-Path $t6 ".counsel\originals") -Recurse -Filter "manifest.json" | Select-Object -First 1
Assert ($null -ne $arch) "L6 manifest archived for audit"

# ---------- L7: doctor clean on healthy install -----------------------------
$t7 = Join-Path $work "l7"; Install-Fresh $t7
& $doctor -ProjectDir $t7 -OsDir $RepoRoot *> $null
Assert ($LASTEXITCODE -ne 1) "L7 doctor reports no BLOCKING on healthy install (exit $LASTEXITCODE)"

Write-Host ""
Write-Host ("LIFECYCLE TESTS: {0} passed, {1} failed" -f $script:pass, $script:fail)
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -gt 0) { exit 1 }
exit 0
