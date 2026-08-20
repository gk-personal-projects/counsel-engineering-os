# Counsel Engineering OS -- deterministic install planner (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Implements D-T2-026 R5-S2 steps 1-4:
# inspect target -> render full staged file set -> classify -> emit PLAN.json.
# NEVER writes into the target project. Apply is a separate consented step.
#
# Classes: CREATE   target file absent
#          PRESERVE target exists and is byte-identical to staged content (no-op)
#          MERGE    target exists and differs; requires explicit approval to apply
#          CONFLICT target is counsel-OWNED per manifest but locally modified;
#                   never auto-applied -- resolve, then re-plan
# Behavior contract: writes only under -StageDir (default %TEMP%). Network: none.
# External commands: none (git not required). Exit 0 = plan written; 1 = failure.

param(
  [Parameter(Mandatory=$true)][string]$Target,
  [string]$Layers = "core",             # csv from: core,builder,engineering,full
  [string]$Source = "",                 # runtime root; default = newest installed plugin cache
  [string]$StageDir = "",
  [string]$ClaudeMdContentPath = "",    # optional: conversationally composed constitution (becomes AGENTS.md)
  [string]$Mode = "pair",
  [string]$InstallSettingsBaseline = "yes",  # "no" to omit the settings.json proposal entirely (claude only)
  [string]$Harness = "claude"           # claude | cursor | codex (see runtime/HARNESS.md)
)
$ErrorActionPreference = "Stop"

function Write-FileSafe([string]$Path, [string]$Content) {
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $Path) { try { (Get-Item $Path -Force).Attributes = 'Normal' } catch {}; Remove-Item $Path -Force }
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }
function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower() }

if (-not (Test-Path $Target -PathType Container)) { Write-Error "Target not found: $Target"; exit 1 }
$Target = (Resolve-Path $Target).Path

# --- resolve runtime source ------------------------------------------------
if (-not $Source) {
  $cacheRoot = Join-Path $env:USERPROFILE ".claude\plugins\cache\counsel-os\counsel"
  if (-not (Test-Path $cacheRoot)) { Write-Error "No -Source given and no installed counsel plugin at $cacheRoot"; exit 1 }
  $verDir = Get-ChildItem $cacheRoot -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  if (-not $verDir) { Write-Error "No semver-shaped release dir in plugin cache: $cacheRoot (pass -Source)"; exit 1 }
  $Source = $verDir.FullName
}
$Source = (Resolve-Path $Source).Path
$Harness = $Harness.Trim().ToLower()
if (@("claude","cursor","codex") -notcontains $Harness) { Write-Error "Unknown harness: $Harness (claude|cursor|codex)"; exit 1 }
foreach ($req in @("runtime\rules", "scaffold\session", "scaffold\work", "scaffold\SCHEMA-VERSION", "VERSION")) {
  if (-not (Test-Path (Join-Path $Source $req))) { Write-Error "Source is missing required piece: $req (at $Source)"; exit 1 }
}
$runtimeVersion = (Read-Text (Join-Path $Source "VERSION")).Trim()
$cpSchema = (Read-Text (Join-Path $Source "scaffold\SCHEMA-VERSION")).Trim()
# Model alias map is Claude-adapter data. Non-claude harnesses use the semantic class
# names themselves as effort guidance (runtime/HARNESS.md).
if ($Harness -eq "claude") {
  $mmPath = Join-Path $Source "adapters\claude\model-map.json"
  if (-not (Test-Path $mmPath)) { $mmPath = Join-Path $Source "registry\model-map.json" }  # pre-0.1.5 source
  if (-not (Test-Path $mmPath)) { Write-Error "Source is missing model-map.json (adapters\claude\ or registry\)"; exit 1 }
  $modelMap = Read-Text $mmPath | ConvertFrom-Json
} else {
  $modelMap = [pscustomobject]@{
    placeholders = [pscustomobject]@{ "{{MODEL_ECONOMY}}" = "ECONOMY"; "{{MODEL_STANDARD}}" = "STANDARD"; "{{MODEL_DEEP}}" = "DEEP-REASONING" }
    classes = [pscustomobject]@{ "ECONOMY" = "ECONOMY"; "STANDARD" = "STANDARD"; "DEEP-REASONING" = "DEEP-REASONING" }
    fallback = "STANDARD"
  }
}

if (-not $StageDir) { $StageDir = Join-Path $env:TEMP ("counsel-install\stage-" + (Get-Date -Format "yyyyMMdd-HHmmss")) }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

$warnings = @()
$layerList = @($Layers.Split(",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($l in $layerList) {
  if (@("core","builder","engineering","full") -notcontains $l) { Write-Error "Unknown layer: $l"; exit 1 }
}
if ($layerList -notcontains "core") { $layerList = @("core") + $layerList }

# --- helpers to stage content ----------------------------------------------
function Resolve-ModelPlaceholders([string]$Text) {
  $out = $Text
  foreach ($ph in $script:modelMap.placeholders.PSObject.Properties) {
    $class = $ph.Value
    $value = $script:modelMap.classes.PSObject.Properties | Where-Object { $_.Name -eq $class } | ForEach-Object { $_.Value }
    if (-not $value) { $value = $script:modelMap.fallback; $script:warnings += "Model class '$class' unmapped; used fallback '$value'" }
    $out = $out.Replace($ph.Name, $value)
  }
  if ($out -match "\{\{MODEL_[A-Z_]+\}\}") {
    $script:warnings += "Unknown model placeholder remained; replaced with fallback '$($script:modelMap.fallback)'"
    $out = [regex]::Replace($out, "\{\{MODEL_[A-Z_]+\}\}", $script:modelMap.fallback)
  }
  return $out
}
function Stage([string]$Rel, [string]$Content) {
  $p = Join-Path $script:StageDir $Rel
  Write-FileSafe $p $Content
  return $Rel
}

$staged = @()   # list of @{ rel; owned }

# 1. Rules (counsel-OWNED after install) -> harness-neutral home .counsel\rules\.
#    Always-on delivery happens via the AGENTS.md sentinel block (step 5); these on-disk
#    copies serve on-demand loading, doctor integrity, and non-claude harnesses.
#    (Pre-0.1.5 installs staged these to .claude\rules\ -- step 8 proposes their removal.)
Get-ChildItem (Join-Path $Source "runtime\rules") -Filter "*.md" -File | ForEach-Object {
  $staged += @{ rel = (Stage (".counsel\rules\" + $_.Name) (Read-Text $_.FullName)); owned = $true }
}

# 2. Agents per layer (counsel-OWNED; model placeholders resolved per R3)
$tierMap = @{ builder = @("builder"); engineering = @("builder","engineering"); full = @("builder","engineering","full") }
$tiers = @()
foreach ($l in $layerList) { if ($tierMap.ContainsKey($l)) { $tiers += $tierMap[$l] } }
$tiers = @($tiers | Select-Object -Unique)
$agentsDir = if ($Harness -eq "claude") { ".claude\agents\" } else { ".counsel\agents\" }  # role cards off-claude (HARNESS.md)
foreach ($tier in $tiers) {
  $tierDir = Join-Path $Source ("runtime\agents\" + $tier)
  if (-not (Test-Path $tierDir)) { $warnings += "Tier dir missing in source: $tier"; continue }
  Get-ChildItem $tierDir -Filter "*.md" -File | ForEach-Object {
    $staged += @{ rel = (Stage ($agentsDir + $_.Name) (Resolve-ModelPlaceholders (Read-Text $_.FullName))); owned = $true }
  }
}

# 3. .counsel/config.yaml (control plane, user-owned)
$cfg = Read-Text (Join-Path $Source "scaffold\templates\config.yaml.template")
$cfg = $cfg.Replace("{{CONTROL_PLANE_SCHEMA}}", $cpSchema).Replace("{{RUNTIME_VERSION}}", $runtimeVersion)
$cfg = $cfg.Replace("{{LAYERS}}", (($layerList | ForEach-Object { $_ }) -join ", ")).Replace("{{MODE}}", $Mode).Replace("{{HARNESS}}", $Harness)
$cfg = $cfg.Replace("{{MODEL_ECONOMY_VALUE}}", $modelMap.classes.'ECONOMY').Replace("{{MODEL_STANDARD_VALUE}}", $modelMap.classes.'STANDARD').Replace("{{MODEL_DEEP_VALUE}}", $modelMap.classes.'DEEP-REASONING')
$staged += @{ rel = (Stage ".counsel\config.yaml" $cfg); owned = $false }

# 4. Session + work scaffolds (counsel-OWNED templates; become working state after first use)
Get-ChildItem (Join-Path $Source "scaffold\session") -File | ForEach-Object {
  $staged += @{ rel = (Stage (".counsel\session\" + $_.Name) (Read-Text $_.FullName)); owned = $true }
}
Get-ChildItem (Join-Path $Source "scaffold\work") -File -Recurse | ForEach-Object {
  $relPart = $_.FullName.Substring((Join-Path $Source "scaffold\work").Length + 1)
  $staged += @{ rel = (Stage (".counsel\work\" + $relPart) (Read-Text $_.FullName)); owned = $true }
}

# 5. AGENTS.md constitution (control plane, user-owned; content composed conversationally).
#    The Counsel always-on rules ride inside a sentinel-delimited region managed by the
#    installer; user content outside the region is never touched on update.
$sentinelBegin = "<!-- counsel:rules v$runtimeVersion begin"
$sentinelBeginLine = "$sentinelBegin -- Counsel-owned always-on rules. Managed by the installer; edits inside this block are overwritten on update. Put project-specific law ABOVE this block. -->"
$sentinelEnd = "<!-- counsel:rules end -->"
$alwaysOnRules = @("authority.md","evidence.md","orchestration.md","cost-governor.md","work-control.md","safety-base.md")
$rulesBlock = ""
foreach ($r in $alwaysOnRules) {
  $rp = Join-Path $Source ("runtime\rules\" + $r)
  if (Test-Path $rp) { $rulesBlock += (Read-Text $rp).TrimEnd() + "`n`n" }
  else { $warnings += "Always-on rule missing in source: $r" }
}
$rulesBlock = $rulesBlock.TrimEnd()
$regionSha = $null
$constitutionBase = $null
if ($ClaudeMdContentPath) {
  if (-not (Test-Path $ClaudeMdContentPath)) { Write-Error "ClaudeMdContentPath not found: $ClaudeMdContentPath"; exit 1 }
  $constitutionBase = Read-Text $ClaudeMdContentPath
} elseif (Test-Path (Join-Path $Target "AGENTS.md")) {
  # Update path: refresh the sentinel region inside the user's existing constitution.
  $constitutionBase = Read-Text (Join-Path $Target "AGENTS.md")
}
if ($null -ne $constitutionBase) {
  $regionText = $sentinelBeginLine + "`n" + $rulesBlock + "`n" + $sentinelEnd
  $regionPattern = "(?s)<!-- counsel:rules v[^\r\n]*begin.*?<!-- counsel:rules end -->"
  if ($constitutionBase -match $regionPattern) {
    $agentsMd = [regex]::Replace($constitutionBase, $regionPattern, $regionText.Replace('$','$$'))
  } elseif ($constitutionBase.Contains("{{ALWAYS_ON_RULES_CONTENT}}")) {
    $agentsMd = $constitutionBase.Replace("{{ALWAYS_ON_RULES_CONTENT}}", $rulesBlock)
    if ($agentsMd -notmatch $regionPattern) { $agentsMd = $agentsMd + "`n" + $regionText + "`n" }
  } else {
    $agentsMd = $constitutionBase.TrimEnd() + "`n`n" + $regionText + "`n"
  }
  $agentsMd = $agentsMd.Replace("{{RUNTIME_VERSION}}", $runtimeVersion).Replace("{{HARNESS}}", $Harness)
  if ([System.Text.Encoding]::UTF8.GetByteCount($agentsMd) -gt 32768) {
    $warnings += "AGENTS.md exceeds 32 KiB -- Codex truncates beyond this; trim project content or rules"
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $regionSha = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($regionText)))).Replace("-","").ToLower()
  $staged += @{ rel = (Stage "AGENTS.md" $agentsMd); owned = $false; region_sha = $regionSha }
  if ($Harness -eq "claude") {
    $shim = Read-Text (Join-Path $Source "scaffold\templates\CLAUDE.md.template")
    $staged += @{ rel = (Stage "CLAUDE.md" $shim); owned = $false }
  }
} else {
  $warnings += "No constitution content (-ClaudeMdContentPath) and no existing AGENTS.md -- always-on rules will only exist under .counsel\rules\, not in a constitution"
}

# 5b. Skills for harnesses without a plugin channel (counsel-OWNED copies)
if ($Harness -ne "claude") {
  $skillsRoot = Join-Path $Source "runtime\skills"
  $skillsTargetDir = if ($Harness -eq "codex") { ".codex\skills\" } else { ".cursor\skills\" }
  if (Test-Path $skillsRoot) {
    Get-ChildItem $skillsRoot -Directory | ForEach-Object {
      $sk = Join-Path $_.FullName "SKILL.md"
      if (Test-Path $sk) {
        $staged += @{ rel = (Stage ($skillsTargetDir + $_.Name + "\SKILL.md") (Read-Text $sk)); owned = $true }
      }
    }
  }
}

# 5c. Cursor rule emission (.mdc) per adapters/cursor/rules-map.json (counsel-OWNED)
if ($Harness -eq "cursor") {
  $rmPath = Join-Path $Source "adapters\cursor\rules-map.json"
  if (Test-Path $rmPath) {
    $rulesMap = Read-Text $rmPath | ConvertFrom-Json
    foreach ($rp in $rulesMap.rules.PSObject.Properties) {
      $srcRule = Join-Path $Source ("runtime\rules\" + $rp.Name)
      if (-not (Test-Path $srcRule)) { $warnings += "rules-map references missing rule: $($rp.Name)"; continue }
      $fm = "---`n"
      if ($rp.Value.PSObject.Properties.Name -contains "description" -and $rp.Value.description) { $fm += "description: $($rp.Value.description)`n" }
      if ($rp.Value.PSObject.Properties.Name -contains "globs" -and $rp.Value.globs) { $fm += "globs: $($rp.Value.globs)`n" }
      $fm += "alwaysApply: $(if ($rp.Value.alwaysApply) { 'true' } else { 'false' })`n---`n"
      $mdcName = "counsel-" + ($rp.Name -replace '\.md$', '') + ".mdc"
      $staged += @{ rel = (Stage (".cursor\rules\" + $mdcName) ($fm + (Read-Text $srcRule))); owned = $true }
    }
  } else { $warnings += "cursor harness: adapters\cursor\rules-map.json missing in source; no .mdc rules emitted (AGENTS.md still carries always-on rules)" }
}

# 6. .claude/settings.json proposal (claude harness only; user-owned; ALWAYS approval-gated)
if ($Harness -eq "claude" -and $InstallSettingsBaseline -eq "yes") {
  $baseline = Read-Text (Join-Path $Source "scaffold\templates\settings-baseline.json") | ConvertFrom-Json
  $targetSettingsPath = Join-Path $Target ".claude\settings.json"
  $proposed = $null
  if (Test-Path $targetSettingsPath) {
    $existing = Read-Text $targetSettingsPath | ConvertFrom-Json
    if (-not $existing.permissions) { $existing | Add-Member -MemberType NoteProperty -Name permissions -Value ([pscustomobject]@{}) }
    foreach ($kind in @("deny","ask")) {
      $cur = @(); if ($existing.permissions.$kind) { $cur = @($existing.permissions.$kind) }
      $add = @($baseline.permissions.$kind | Where-Object { $cur -notcontains $_ })
      $merged = $cur + $add
      if ($existing.permissions.PSObject.Properties.Name -contains $kind) { $existing.permissions.$kind = $merged }
      else { $existing.permissions | Add-Member -MemberType NoteProperty -Name $kind -Value $merged }
    }
    $proposed = $existing | ConvertTo-Json -Depth 10
  } else {
    $clean = [pscustomobject]@{ permissions = $baseline.permissions }
    $proposed = $clean | ConvertTo-Json -Depth 10
  }
  $staged += @{ rel = (Stage ".claude\settings.json" $proposed); owned = $false; settings = $true }
}

# 7. .gitignore additions (user-owned merge)
$giLines = @(".counsel/session/", ".counsel/originals/", ".counsel/install/", ".counsel/credential-liveness.json")
$giPath = Join-Path $Target ".gitignore"
$giExisting = ""
if (Test-Path $giPath) { $giExisting = Read-Text $giPath }
$giNew = $giExisting
if ($giNew -and -not $giNew.EndsWith("`n")) { $giNew += "`n" }
foreach ($line in $giLines) {
  if (($giExisting -split "`r?`n") -notcontains $line) { $giNew += $line + "`n" }
}
$staged += @{ rel = (Stage ".gitignore" $giNew); owned = $false }

# --- classify ---------------------------------------------------------------
$manifestPath = Join-Path $Target ".counsel\manifest.json"
$ownedByManifest = @{}
if (Test-Path $manifestPath) {
  try {
    $mf = Read-Text $manifestPath | ConvertFrom-Json
    foreach ($f in $mf.files) { if ($f.owned) { $ownedByManifest[$f.path] = $f.sha256 } }
  } catch { $warnings += "Existing manifest unreadable: $($_.Exception.Message)" }
}

$items = @()
foreach ($s in $staged) {
  $rel = $s.rel
  $stagedPath = Join-Path $StageDir $rel
  $targetPath = Join-Path $Target $rel
  $shaStaged = Get-Sha $stagedPath
  $class = ""; $shaTarget = $null; $approved = $null; $note = ""
  if (-not (Test-Path $targetPath)) {
    $class = "CREATE"; $approved = $true
  } else {
    $shaTarget = Get-Sha $targetPath
    if ($shaTarget -eq $shaStaged) { $class = "PRESERVE" }
    elseif ($ownedByManifest.ContainsKey($rel.Replace("\","/"))) {
      if ($ownedByManifest[$rel.Replace("\","/")] -ne $shaTarget) {
        $class = "CONFLICT"; $note = "counsel-owned file locally modified; resolve then re-plan"
      } else { $class = "MERGE"; $approved = $false; $note = "owned file changed upstream; approval = accept update" }
    }
    else { $class = "MERGE"; $approved = $false; $note = "pre-existing user file; requires explicit approval" }
  }
  if ($s.settings) {
    if ($class -eq "CREATE") { $approved = $false; $note = "PERMISSION CHANGE: requires explicit approval (never silent)" }
    if ($class -eq "MERGE") { $note = "PERMISSION CHANGE: " + $note }
  }
  $item = [ordered]@{ path = $rel.Replace("\","/"); class = $class; owned = [bool]$s.owned
                      sha_staged = $shaStaged; sha_target = $shaTarget; approved = $approved; note = $note }
  if ($s.region_sha) { $item.region_sha = $s.region_sha }
  $items += $item
}

# 8. Migration removals: counsel-owned files from pre-0.1.5 installs whose home moved
#    (.claude/rules/ -> AGENTS.md sentinel + .counsel/rules/). Approval-gated; unmodified-only.
$stagedRels = @($staged | ForEach-Object { $_.rel.Replace("\","/") })
foreach ($ownedPath in $ownedByManifest.Keys) {
  if ($ownedPath -like ".claude/rules/*" -and $stagedRels -notcontains $ownedPath) {
    $tp = Join-Path $Target ($ownedPath -replace "/", "\")
    if (Test-Path $tp) {
      $shaT = Get-Sha $tp
      if ($shaT -eq $ownedByManifest[$ownedPath]) {
        $items += [ordered]@{ path = $ownedPath; class = "REMOVE"; owned = $true
                              sha_staged = $null; sha_target = $shaT; approved = $false
                              note = "pre-0.1.5 always-on rule copy; now delivered via AGENTS.md sentinel block + .counsel/rules/ (approval = remove, backed up)" }
      } else {
        $items += [ordered]@{ path = $ownedPath; class = "CONFLICT"; owned = $true
                              sha_staged = $null; sha_target = $shaT; approved = $null
                              note = "counsel-owned legacy rule locally modified; resolve then re-plan" }
      }
    }
  }
}

$plan = [ordered]@{
  schema_version = 1
  created = (Get-Date).ToString("o")
  source = $Source
  runtime_version = $runtimeVersion
  control_plane_schema = $cpSchema
  target = $Target
  layers = $layerList
  mode = $Mode
  harness = $Harness
  stage_dir = $StageDir
  warnings = $warnings
  items = $items
}
$planPath = Join-Path $StageDir "PLAN.json"
Write-FileSafe $planPath ($plan | ConvertTo-Json -Depth 6)

$counts = @{}
foreach ($i in $items) { $counts[$i.class] = 1 + $(if ($counts.ContainsKey($i.class)) { $counts[$i.class] } else { 0 }) }
Write-Host "PLAN written: $planPath"
Write-Host ("Items: " + (($counts.Keys | Sort-Object | ForEach-Object { "$_=$($counts[$_])" }) -join "  "))
if ($warnings.Count -gt 0) { $warnings | ForEach-Object { Write-Host "WARN  $_" } }
$items | ForEach-Object { Write-Host ("  {0,-9} {1}{2}" -f $_.class, $_.path, $(if ($_.note) { "  -- " + $_.note } else { "" })) }
exit 0
