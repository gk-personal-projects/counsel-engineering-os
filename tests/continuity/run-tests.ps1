# Counsel Engineering OS -- continuity acceptance tests (D-T2-018 ruled list)
# Provenance: ORIGINAL (Apache-2.0). Runs in an isolated sandbox under $env:TEMP.
# Exit 0 = all pass. Each case prints PASS/FAIL with its D-T2-018 test-list name.

param([string]$ScriptsDir = (Join-Path $PSScriptRoot "..\..\scripts\session"))
$ErrorActionPreference = "Stop"
$ScriptsDir = (Resolve-Path $ScriptsDir).Path
$CP = Join-Path $ScriptsDir "checkpoint.ps1"
$RS = Join-Path $ScriptsDir "restore.ps1"
$DR = Join-Path $ScriptsDir "session-doctor.ps1"

$SB = Join-Path $env:TEMP ("ceos-continuity-tests-" + (Get-Date -Format "yyyyMMddHHmmss"))
New-Item -ItemType Directory -Force $SB | Out-Null
$script:passed = 0; $script:failed = 0

function Assert([bool]$Cond, [string]$Name, [string]$Detail = "") {
  if ($Cond) { $script:passed++; Write-Host "PASS  $Name" }
  else { $script:failed++; Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red }
}
function New-Workspace([string]$Name) {
  $ws = Join-Path $SB $Name
  $sd = Join-Path $ws ".counsel\session"
  New-Item -ItemType Directory -Force $sd | Out-Null
  Set-Content -Encoding UTF8 (Join-Path $sd "RESTORE.md") "# RESTORE`nnext action: test"
  Set-Content -Encoding UTF8 (Join-Path $sd "STATE.json") '{"phase":"test"}'
  return $ws
}
function New-Repo([string]$Ws, [string]$Name, [bool]$Commit = $true, [bool]$Dirty = $false) {
  $r = Join-Path $Ws $Name
  New-Item -ItemType Directory -Force $r | Out-Null
  git -C $r init -q 2>$null | Out-Null
  git -C $r config user.email "test@test.local" 2>$null; git -C $r config user.name "test" 2>$null
  if ($Commit) {
    Set-Content (Join-Path $r "f.txt") "x"
    git -C $r add . 2>$null; git -C $r commit -q -m "init" 2>$null | Out-Null
  }
  if ($Dirty) { Set-Content (Join-Path $r "dirty.txt") "y" }
  return $r
}
function Invoke-Checkpoint([string]$Ws, [string]$Label) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $CP -Workspace $Ws -SessionDir (Join-Path $Ws ".counsel\session") -Label $Label 2>&1
  return @{ code = $LASTEXITCODE; out = ($out | Out-String) }
}
function Get-Pointer([string]$Ws) {
  $p = Join-Path $Ws ".counsel\session\LAST-CHECKPOINT.txt"
  if (Test-Path $p) { return (Get-Content $p -Raw).Trim() } else { return $null }
}

# -- T1: zero-commit / unborn repo -- checkpoint SUCCEEDS, unborn recorded ------
$ws = New-Workspace "t01-unborn"; New-Repo $ws "app" $false | Out-Null
$r = Invoke-Checkpoint $ws "t1"
$ptr = Get-Pointer $ws
$ms = if ($ptr) { Get-Content (Join-Path $ptr "MACHINE-STATE.json") -Raw | ConvertFrom-Json } else { $null }
Assert ($r.code -eq 0 -and $ms -and $ms.repositories[0].unborn -eq $true -and $null -eq $ms.repositories[0].head) `
  "T1  zero-commit/unborn repo captured as valid state" "code=$($r.code)"

# -- T2: duplicate repository discovery (junction) -- deduped, single entry -----
$ws = New-Workspace "t02-dup"; $repo = New-Repo $ws "app"
cmd /c mklink /J (Join-Path $ws "app-link") $repo | Out-Null
$r = Invoke-Checkpoint $ws "t2"
$ms = Get-Content (Join-Path (Get-Pointer $ws) "MACHINE-STATE.json") -Raw | ConvertFrom-Json
$appEntries = @($ms.repositories | Where-Object { $_.head })
Assert ($r.code -eq 0 -and $appEntries.Count -eq 1) "T2  duplicate repo discovery deduped" "entries=$($appEntries.Count)"

# -- T3: git failure mid-capture (corrupt .git) -- FAIL, no promote, forensics --
$ws = New-Workspace "t03-gitfail"; New-Repo $ws "good" | Out-Null
$bad = Join-Path $ws "bad"; New-Item -ItemType Directory -Force $bad | Out-Null
Set-Content (Join-Path $bad ".git") "gitdir: Z:\nonexistent\nowhere"
$r = Invoke-Checkpoint $ws "t3"
$failedDirs = @(Get-ChildItem (Join-Path $ws ".counsel\session\CHECKPOINTS") -Directory -Filter "FAILED-*" -ErrorAction SilentlyContinue)
Assert ($r.code -ne 0 -and $failedDirs.Count -eq 1 -and (Test-Path (Join-Path $failedDirs[0].FullName "FAILURE.txt")) -and $null -eq (Get-Pointer $ws)) `
  "T3  git failure mid-capture: no promotion, failure surfaced+preserved" "code=$($r.code) failed=$($failedDirs.Count)"

# -- T4: partial checkpoint (leftover .tmp) -- never a restore target -----------
$ws = New-Workspace "t04-partial"; New-Repo $ws "app" | Out-Null
(Invoke-Checkpoint $ws "t4-good") | Out-Null
$good = Get-Pointer $ws
$tmpDir = Join-Path $ws ".counsel\session\CHECKPOINTS\.tmp-99999999-999999-killed"
New-Item -ItemType Directory -Force $tmpDir | Out-Null   # simulated kill mid-checkpoint
$rsOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $RS -Workspace $ws -SessionDir (Join-Path $ws ".counsel\session") 2>&1 | Out-String
Assert (($rsOut -match [regex]::Escape((Split-Path $good -Leaf))) -and ($rsOut -notmatch "tmp-99999999")) `
  "T4  partial checkpoint ignored by restore; valid one used"

# -- T5: stale LAST-CHECKPOINT pointer -- fallback + drift surfaced -------------
$ws = New-Workspace "t05-stale"; New-Repo $ws "app" | Out-Null
(Invoke-Checkpoint $ws "t5") | Out-Null
$sd = Join-Path $ws ".counsel\session"
Set-Content -Encoding UTF8 (Join-Path $sd "LAST-CHECKPOINT.txt") (Join-Path $sd "CHECKPOINTS\20990101-000000-ghost")
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $RS -Workspace $ws -SessionDir $sd 2>&1 | Out-String
Assert (($LASTEXITCODE -eq 2) -and ($out -match "STALE POINTER") -and ($out -match "FALLBACK")) `
  "T5  stale pointer: fallback to newest valid + drift surfaced" "code=$LASTEXITCODE"

# -- T6: failed validation preserves previous authoritative checkpoint ---------
$ws = New-Workspace "t06-preserve"; New-Repo $ws "app" | Out-Null
(Invoke-Checkpoint $ws "t6-first") | Out-Null
$first = Get-Pointer $ws
$bad = Join-Path $ws "corrupt"; New-Item -ItemType Directory -Force $bad | Out-Null
Set-Content (Join-Path $bad ".git") "gitdir: Z:\nope"
$r = Invoke-Checkpoint $ws "t6-second"
Assert (($r.code -ne 0) -and ((Get-Pointer $ws) -eq $first)) "T6  failed validation: previous checkpoint remains authoritative"

# -- T7: UTF-8 content survives checkpoint round-trip --------------------------
$ws = New-Workspace "t07-utf8"; New-Repo $ws "app" | Out-Null
$sd = Join-Path $ws ".counsel\session"
# Non-ASCII built from code points so this script file stays ASCII-safe on PS 5.1:
# e-acute, middle dot, Japanese "nihongo", check mark, em dash.
$utf8Text = "# RESTORE`nna" + [char]0x00EF + "ve " + [char]0x00B7 + " " + [char]0x65E5 + [char]0x672C + [char]0x8A9E + " " + [char]0x00B7 + " " + [char]0x00E9 + "moji " + [char]0x2705 + " " + [char]0x2014 + " dash"
[System.IO.File]::WriteAllText((Join-Path $sd "RESTORE.md"), $utf8Text, (New-Object System.Text.UTF8Encoding($false)))
(Invoke-Checkpoint $ws "t7") | Out-Null
$copied = [System.IO.File]::ReadAllText((Join-Path (Get-Pointer $ws) "RESTORE.md"), [System.Text.Encoding]::UTF8)
Assert ($copied -eq $utf8Text) "T7  UTF-8 content round-trips intact"

# -- T8: read-only/placeholder-like pointer file -- write still succeeds --------
$ws = New-Workspace "t08-readonly"; New-Repo $ws "app" | Out-Null
$sd = Join-Path $ws ".counsel\session"
(Invoke-Checkpoint $ws "t8-a") | Out-Null
Set-ItemProperty (Join-Path $sd "LAST-CHECKPOINT.txt") -Name IsReadOnly -Value $true
$r = Invoke-Checkpoint $ws "t8-b"
Assert (($r.code -eq 0) -and ((Get-Pointer $ws) -like "*t8-b")) "T8  locked/read-only pointer file: safe-write path succeeds" "code=$($r.code)"

# -- T9: dirty working tree captured -------------------------------------------
$ws = New-Workspace "t09-dirty"; New-Repo $ws "app" $true $true | Out-Null
(Invoke-Checkpoint $ws "t9") | Out-Null
$ms = Get-Content (Join-Path (Get-Pointer $ws) "MACHINE-STATE.json") -Raw | ConvertFrom-Json
Assert (@($ms.repositories[0].status).Count -gt 0) "T9  dirty working tree captured in snapshot"

# -- T10: missing repository during recovery -- flagged, not silent -------------
$ws = New-Workspace "t10-missing"; $repo = New-Repo $ws "app"
(Invoke-Checkpoint $ws "t10") | Out-Null
Remove-Item $repo -Recurse -Force
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $RS -Workspace $ws -SessionDir (Join-Path $ws ".counsel\session") 2>&1 | Out-String
Assert (($LASTEXITCODE -eq 2) -and ($out -match "MISSING REPO")) "T10 missing repo at recovery: surfaced as drift" "code=$LASTEXITCODE"

# -- T11: deliberate save-and-restart -- restore reconstructs consistent state --
$ws = New-Workspace "t11-savecycle"; New-Repo $ws "app" | Out-Null
(Invoke-Checkpoint $ws "t11") | Out-Null
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $RS -Workspace $ws -SessionDir (Join-Path $ws ".counsel\session") 2>&1 | Out-String
Assert (($LASTEXITCODE -eq 0) -and ($out -match "State consistent") -and ($out -match "next action: test")) `
  "T11 save-and-restart: clean reconstruction, consistent verdict" "code=$LASTEXITCODE"

# -- T12: abrupt termination mid-checkpoint -- doctor flags residue; next run OK -
$ws = New-Workspace "t12-abrupt"; New-Repo $ws "app" | Out-Null
$sd = Join-Path $ws ".counsel\session"
New-Item -ItemType Directory -Force (Join-Path $sd "CHECKPOINTS\.tmp-11111111-111111-killed") | Out-Null
$doc = & powershell -NoProfile -ExecutionPolicy Bypass -File $DR -Workspace $ws -SessionDir $sd 2>&1 | Out-String
$docFlagged = $doc -match "residue"
$r = Invoke-Checkpoint $ws "t12-after"
Assert ($docFlagged -and $r.code -eq 0 -and (Get-Pointer $ws) -like "*t12-after") `
  "T12 abrupt termination: residue flagged by doctor, next checkpoint clean" "code=$($r.code)"

# -- T13: recovery after failed attempt -- subsequent checkpoint restores health -
$ws = New-Workspace "t13-recover"; New-Repo $ws "app" | Out-Null
$bad = Join-Path $ws "corrupt"; New-Item -ItemType Directory -Force $bad | Out-Null
Set-Content (Join-Path $bad ".git") "gitdir: Z:\nope"
$r1 = Invoke-Checkpoint $ws "t13-fail"
Remove-Item $bad -Recurse -Force
$r2 = Invoke-Checkpoint $ws "t13-ok"
$doc = & powershell -NoProfile -ExecutionPolicy Bypass -File $DR -Workspace $ws -SessionDir (Join-Path $ws ".counsel\session") 2>&1 | Out-String
Assert (($r1.code -ne 0) -and ($r2.code -eq 0) -and ((Get-Pointer $ws) -like "*t13-ok") -and ($doc -match "Pointer -> valid checkpoint")) `
  "T13 recovery after failed attempt: pointer moves only to the new valid checkpoint"

# -- summary -------------------------------------------------------------------
Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed  (sandbox: {2})" -f $script:passed, $script:failed, $SB)
if ($script:failed -eq 0) { Remove-Item $SB -Recurse -Force -ErrorAction SilentlyContinue; exit 0 }
exit 1
