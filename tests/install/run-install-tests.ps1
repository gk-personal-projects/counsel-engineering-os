# Counsel Engineering OS -- install plan/apply acceptance tests (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Covers D-T2-026 R5-S2 requirements:
# plan-first, consent classes, no blind overwrite, permission approval gating,
# ownership manifest, atomic apply, post-verify, stale plan refusal, idempotency.
# Uses the repo itself as -Source so tests run pre-release. Exit 0 = all pass.

param([string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = "Stop"
$plan = Join-Path $RepoRoot "scripts\install\install-plan.ps1"
$apply = Join-Path $RepoRoot "scripts\install\install-apply.ps1"
$work = Join-Path $env:TEMP ("counsel-install-tests-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$script:pass = 0; $script:fail = 0
function Assert([bool]$Cond, [string]$Name) {
  if ($Cond) { $script:pass++; Write-Host "PASS  $Name" }
  else { $script:fail++; Write-Host "FAIL  $Name" -ForegroundColor Red }
}
function Get-Plan([string]$StageDir) { [System.IO.File]::ReadAllText((Join-Path $StageDir "PLAN.json")) | ConvertFrom-Json }
function Set-ItemApproved([string]$StageDir, [string]$PathLike, [bool]$Value) {
  $p = Join-Path $StageDir "PLAN.json"
  $pl = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json
  foreach ($i in $pl.items) { if ($i.path -like $PathLike) { $i.approved = $Value } }
  [System.IO.File]::WriteAllText($p, ($pl | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- T1: fresh install (core+builder) --------------------------------
$t1 = Join-Path $work "t1"; New-Item -ItemType Directory -Force -Path $t1 | Out-Null
$cm = Join-Path $work "claude-md.txt"
[System.IO.File]::WriteAllText($cm, "# TestProj -- Engineering Constitution`n(test content)`n", (New-Object System.Text.UTF8Encoding($false)))
$s1 = Join-Path $work "stage1"
& $plan -Target $t1 -Layers "core,builder" -Source $RepoRoot -StageDir $s1 -ClaudeMdContentPath $cm | Out-Null
Assert ($LASTEXITCODE -eq 0) "T1 plan exits 0"
$p1 = Get-Plan $s1
Assert (@($p1.items | Where-Object { $_.class -ne "CREATE" }).Count -eq 0) "T1 fresh target: every item is CREATE"
$settingsItem = $p1.items | Where-Object { $_.path -eq ".claude/settings.json" }
Assert ($settingsItem.approved -eq $false) "T1 settings.json CREATE is approval-gated (approved=false)"
& $apply -PlanPath (Join-Path $s1 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 0) "T1 apply exits 0"
Assert (Test-Path (Join-Path $t1 ".counsel\rules\evidence.md")) "T1 rules installed (.counsel/rules)"
Assert (Test-Path (Join-Path $t1 ".claude\agents\tech-lead.md")) "T1 builder agents installed"
Assert (-not (Test-Path (Join-Path $t1 ".claude\settings.json"))) "T1 settings NOT written without approval"
Assert (Test-Path (Join-Path $t1 "AGENTS.md")) "T1 AGENTS.md constitution created"
$agentsMd1 = [System.IO.File]::ReadAllText((Join-Path $t1 "AGENTS.md"))
Assert ($agentsMd1 -match '<!-- counsel:rules v[^\r\n]*begin' -and $agentsMd1 -match '<!-- counsel:rules end -->') "T1 sentinel rules block embedded"
Assert ($agentsMd1 -match 'DISCOVERED WORK') "T1 always-on rules content inside AGENTS.md"
Assert (Test-Path (Join-Path $t1 "CLAUDE.md")) "T1 CLAUDE.md shim created"
Assert ((Get-Content (Join-Path $t1 "CLAUDE.md") -TotalCount 1) -match '^@AGENTS\.md') "T1 shim first line is @AGENTS.md"
Assert (Test-Path (Join-Path $t1 ".counsel\manifest.json")) "T1 manifest written"
$mf1 = [System.IO.File]::ReadAllText((Join-Path $t1 ".counsel\manifest.json")) | ConvertFrom-Json
Assert ($mf1.runtime_version -and $mf1.control_plane_schema) "T1 manifest carries runtime + control-plane versions"
$agentText = [System.IO.File]::ReadAllText((Join-Path $t1 ".claude\agents\tech-lead.md"))
Assert (-not ($agentText -match "\{\{MODEL_")) "T1 model placeholders fully resolved"
$ownedCount = @($mf1.files | Where-Object { $_.owned }).Count
Assert ($ownedCount -gt 10) "T1 manifest records owned files ($ownedCount)"

# ---------- T2: idempotent re-run -------------------------------------------
$s2 = Join-Path $work "stage2"
& $plan -Target $t1 -Layers "core,builder" -Source $RepoRoot -StageDir $s2 -ClaudeMdContentPath $cm | Out-Null
$p2 = Get-Plan $s2
$nonPreserve = @($p2.items | Where-Object { $_.class -ne "PRESERVE" })
Assert (@($nonPreserve | Where-Object { $_.path -ne ".claude/settings.json" }).Count -eq 0) "T2 re-plan: everything PRESERVE except declined settings"
& $apply -PlanPath (Join-Path $s2 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 0) "T2 idempotent apply exits 0"

# ---------- T3: explicit settings approval ----------------------------------
$s3 = Join-Path $work "stage3"
& $plan -Target $t1 -Layers "core,builder" -Source $RepoRoot -StageDir $s3 -ClaudeMdContentPath $cm | Out-Null
Set-ItemApproved $s3 ".claude/settings.json" $true
& $apply -PlanPath (Join-Path $s3 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 0) "T3 apply exits 0"
$st = [System.IO.File]::ReadAllText((Join-Path $t1 ".claude\settings.json")) | ConvertFrom-Json
Assert (@($st.permissions.deny) -contains "Read(./.env)") "T3 approved settings baseline applied"

# ---------- T4: modified owned file -> CONFLICT, untouched ------------------
$evPath = Join-Path $t1 ".counsel\rules\evidence.md"
[System.IO.File]::AppendAllText($evPath, "`nLOCAL EDIT`n")
$s4 = Join-Path $work "stage4"
& $plan -Target $t1 -Layers "core,builder" -Source $RepoRoot -StageDir $s4 -ClaudeMdContentPath $cm | Out-Null
$p4 = Get-Plan $s4
$ev = $p4.items | Where-Object { $_.path -eq ".counsel/rules/evidence.md" }
Assert ($ev.class -eq "CONFLICT") "T4 locally-modified owned file classified CONFLICT"
& $apply -PlanPath (Join-Path $s4 "PLAN.json") | Out-Null
$evText = [System.IO.File]::ReadAllText($evPath)
Assert ($evText -match "LOCAL EDIT") "T4 CONFLICT file left untouched by apply"

# ---------- T5: pre-existing user file needs approval -----------------------
$t5 = Join-Path $work "t5"; New-Item -ItemType Directory -Force -Path $t5 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $t5 "CLAUDE.md"), "user's own file`n", (New-Object System.Text.UTF8Encoding($false)))
$s5 = Join-Path $work "stage5"
& $plan -Target $t5 -Layers "core" -Source $RepoRoot -StageDir $s5 -ClaudeMdContentPath $cm | Out-Null
$p5 = Get-Plan $s5
$cmItem = $p5.items | Where-Object { $_.path -eq "CLAUDE.md" }
Assert ($cmItem.class -eq "MERGE" -and $cmItem.approved -eq $false) "T5 pre-existing CLAUDE.md is unapproved MERGE"
& $apply -PlanPath (Join-Path $s5 "PLAN.json") | Out-Null
Assert (([System.IO.File]::ReadAllText((Join-Path $t5 "CLAUDE.md"))) -match "user's own file") "T5 user CLAUDE.md untouched without approval"

# ---------- T6: stale plan refused ------------------------------------------
$t6 = Join-Path $work "t6"; New-Item -ItemType Directory -Force -Path $t6 | Out-Null
$s6 = Join-Path $work "stage6"
& $plan -Target $t6 -Layers "core" -Source $RepoRoot -StageDir $s6 | Out-Null
# drift the target after planning (a path the plan stages)
New-Item -ItemType Directory -Force -Path (Join-Path $t6 ".counsel\rules") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $t6 ".counsel\rules\evidence.md"), "drifted`n", (New-Object System.Text.UTF8Encoding($false)))
& $apply -PlanPath (Join-Path $s6 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 1) "T6 stale plan exits 1"
Assert (-not (Test-Path (Join-Path $t6 ".counsel\manifest.json"))) "T6 stale apply wrote nothing"

# ---------- T7: MERGE approval creates backup -------------------------------
$s7 = Join-Path $work "stage7"
& $plan -Target $t5 -Layers "core" -Source $RepoRoot -StageDir $s7 -ClaudeMdContentPath $cm | Out-Null
Set-ItemApproved $s7 "CLAUDE.md" $true
& $apply -PlanPath (Join-Path $s7 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 0) "T7 approved merge applies"
Assert (([System.IO.File]::ReadAllText((Join-Path $t5 "CLAUDE.md"))) -match "@AGENTS\.md") "T7 merged CLAUDE.md is the shim"
Assert (([System.IO.File]::ReadAllText((Join-Path $t5 "AGENTS.md"))) -match "TestProj") "T7 constitution content lives in AGENTS.md"
$backup = Get-ChildItem (Join-Path $t5 ".counsel\originals") -Recurse -Filter "CLAUDE.md" | Select-Object -First 1
Assert ($null -ne $backup) "T7 original backed up before replacement"
Assert (([System.IO.File]::ReadAllText($backup.FullName)) -match "user's own file") "T7 backup holds pre-merge content"

# ---------- T8: pre-0.1.5 migration -> REMOVE of legacy .claude/rules copies --
$t8 = Join-Path $work "t8"; New-Item -ItemType Directory -Force -Path $t8 | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $t8 ".claude\rules") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $t8 ".counsel") | Out-Null
$legacyRule = Join-Path $t8 ".claude\rules\evidence.md"
[System.IO.File]::WriteAllText($legacyRule, "legacy rule content`n", (New-Object System.Text.UTF8Encoding($false)))
$legacySha = (Get-FileHash -Algorithm SHA256 -Path $legacyRule).Hash.ToLower()
$legacyMf = [pscustomobject]@{ schema_version = 1; runtime_version = "0.1.2"; control_plane_schema = "1";
  files = @([pscustomobject]@{ path = ".claude/rules/evidence.md"; owned = $true; sha256 = $legacySha; runtime_version = "0.1.2"; applied_class = "CREATE"; applied_at = "2026-08-12T00:00:00" }) }
[System.IO.File]::WriteAllText((Join-Path $t8 ".counsel\manifest.json"), ($legacyMf | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$s8 = Join-Path $work "stage8"
& $plan -Target $t8 -Layers "core" -Source $RepoRoot -StageDir $s8 -ClaudeMdContentPath $cm | Out-Null
$p8 = Get-Plan $s8
$rm = $p8.items | Where-Object { $_.path -eq ".claude/rules/evidence.md" }
Assert ($rm.class -eq "REMOVE" -and $rm.approved -eq $false) "T8 legacy owned rule proposed as approval-gated REMOVE"
Set-ItemApproved $s8 ".claude/rules/evidence.md" $true
& $apply -PlanPath (Join-Path $s8 "PLAN.json") | Out-Null
Assert ($LASTEXITCODE -eq 0) "T8 apply exits 0"
Assert (-not (Test-Path $legacyRule)) "T8 legacy rule removed"
$rmBackup = Get-ChildItem (Join-Path $t8 ".counsel\originals") -Recurse -Filter "evidence.md" | Select-Object -First 1
Assert ($null -ne $rmBackup) "T8 removed file backed up first"
$mf8 = [System.IO.File]::ReadAllText((Join-Path $t8 ".counsel\manifest.json")) | ConvertFrom-Json
Assert (@($mf8.files | Where-Object { $_.path -eq ".claude/rules/evidence.md" }).Count -eq 0) "T8 manifest entry dropped"

# ---------- T9: codex harness plan (no Claude surfaces, skills staged) -------
$t9 = Join-Path $work "t9"; New-Item -ItemType Directory -Force -Path $t9 | Out-Null
$s9 = Join-Path $work "stage9"
& $plan -Target $t9 -Layers "core,builder" -Source $RepoRoot -StageDir $s9 -ClaudeMdContentPath $cm -Harness codex | Out-Null
Assert ($LASTEXITCODE -eq 0) "T9 codex plan exits 0"
$p9 = Get-Plan $s9
Assert ($p9.harness -eq "codex") "T9 plan records harness"
Assert (@($p9.items | Where-Object { $_.path -like ".claude/*" }).Count -eq 0) "T9 no .claude/ surfaces for codex"
Assert (@($p9.items | Where-Object { $_.path -eq "CLAUDE.md" }).Count -eq 0) "T9 no CLAUDE.md shim for codex"
Assert (@($p9.items | Where-Object { $_.path -like ".codex/skills/*" }).Count -gt 10) "T9 skills staged to .codex/skills/"
Assert (@($p9.items | Where-Object { $_.path -like ".counsel/agents/*" }).Count -gt 0) "T9 agents staged as role cards (.counsel/agents)"
$agent9 = [System.IO.File]::ReadAllText((Join-Path $s9 ".counsel\agents\tech-lead.md"))
Assert (-not ($agent9 -match "\{\{MODEL_")) "T9 model placeholders resolved to semantic classes"

# ---------- summary ---------------------------------------------------------
Write-Host ""
Write-Host ("INSTALL TESTS: {0} passed, {1} failed" -f $script:pass, $script:fail)
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -gt 0) { exit 1 }
exit 0
