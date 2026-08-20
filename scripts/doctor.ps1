# Counsel Engineering OS -- mechanical doctor engine (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). The counsel-doctor SKILL interprets this output and
# adds goal-awareness + remediation cards; this script does the deterministic checks.
# Severities: BLOCKING / REQUIRED-FOR-SELECTED / RECOMMENDED / OPTIONAL / INFO.
# Missing optional tools are NEVER blocking. Exit: 0 ready, 1 blocking present, 2 recommendations.

param(
  [string]$ProjectDir = (Get-Location).Path,
  [string]$OsDir = ""      # where the Counsel OS source lives (for registry access); defaults to script root
  ,[switch]$Probe                 # perform read-only credential liveness probes (leaves the machine)
  ,[switch]$AllowRegistryCommands # additionally permit registry-authored probe commands (cmd-exit0)
)
$ErrorActionPreference = "Stop"
if (-not $OsDir) { $OsDir = Split-Path $PSScriptRoot -Parent }
$blocking = 0; $recommended = 0; $unverified = 0
function Out-Check([string]$Sev, [string]$Area, [string]$Msg) {
  if ($Sev -eq "BLOCKING") { $script:blocking++ }
  if ($Sev -eq "RECOMMENDED") { $script:recommended++ }
  if ($Sev -eq "UNVERIFIED") { $script:unverified++ }
  Write-Host ("{0,-12} {1,-12} {2}" -f $Sev, $Area, $Msg)
}

# --- CORE INTEGRITY --------------------------------------------------------
# Constitution: AGENTS.md (0.1.5+, harness-neutral) with a CLAUDE.md shim on Claude Code;
# a fat CLAUDE.md without AGENTS.md is a pre-0.1.5 install (works, migration recommended).
$agentsMd = Join-Path $ProjectDir "AGENTS.md"
$claudeMd = Join-Path $ProjectDir "CLAUDE.md"
$constitution = $null
if (Test-Path $agentsMd) {
  $constitution = $agentsMd
  Out-Check INFO core "Constitution present (AGENTS.md)"
  $agentsRaw = Get-Content $agentsMd -Raw -Encoding UTF8
  $bytes = [System.Text.Encoding]::UTF8.GetByteCount($agentsRaw)
  if ($bytes -gt 32768) { Out-Check RECOMMENDED core ("AGENTS.md is {0} bytes -- Codex truncates beyond 32 KiB; trim content" -f $bytes) }
  else { Out-Check INFO core ("AGENTS.md size OK ({0} bytes / 32 KiB budget)" -f $bytes) }
  $hasBegin = $agentsRaw -match '<!-- counsel:rules v[^\r\n]*begin'
  $hasEnd = $agentsRaw -match '<!-- counsel:rules end -->'
  if ($hasBegin -and $hasEnd) { Out-Check INFO core "counsel:rules sentinel block intact" }
  elseif ($hasBegin -or $hasEnd) { Out-Check BLOCKING core "counsel:rules sentinel block DAMAGED (one marker missing) - re-run install-plan/apply" }
  else { Out-Check RECOMMENDED core "no counsel:rules sentinel block in AGENTS.md - always-on rules are not embedded" }
  if (Test-Path $claudeMd) {
    $shimFirst = (Get-Content $claudeMd -TotalCount 1)
    if ($shimFirst -match '^@AGENTS\.md\s*$') { Out-Check INFO core "CLAUDE.md shim imports AGENTS.md" }
    else { Out-Check RECOMMENDED core "CLAUDE.md exists but does not start with @AGENTS.md - Claude Code may not load the constitution (or content is duplicated)" }
  }
} elseif (Test-Path $claudeMd) {
  $constitution = $claudeMd
  Out-Check INFO core "Constitution present (legacy CLAUDE.md; pre-0.1.5)"
  Out-Check RECOMMENDED core "no AGENTS.md - re-run install to migrate to the harness-neutral constitution"
} else {
  Out-Check BLOCKING core "constitution missing (no AGENTS.md, no CLAUDE.md) - run /counsel:onboard"
}
if ($constitution) {
  $imports = Select-String -Path $constitution -Pattern '^@(.+)$' -AllMatches
  if ($imports) {
    $imports.Matches | ForEach-Object {
      $imp = $_.Groups[1].Value
      if (Test-Path (Join-Path $ProjectDir $imp)) { Out-Check INFO core "rule resolves: $imp" }
      else { Out-Check BLOCKING core "always-on rule MISSING: $imp" }
    }
  }
  if (Select-String -Path $constitution -Pattern '\{\{' -Quiet) { Out-Check RECOMMENDED core "unfilled {{placeholders}} remain in constitution" }
  $chars = (Get-Content $constitution -Raw -Encoding UTF8).Length
  $ruleChars = 0
  foreach ($rd in @(".claude\rules", ".counsel\rules")) {
    Get-ChildItem (Join-Path $ProjectDir $rd) -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { $ruleChars += (Get-Content $_.FullName -Raw -Encoding UTF8).Length }
  }
  Out-Check INFO cost ("boot weight estimate ~{0} tokens (constitution + rules; chars/4)" -f [math]::Round(($chars + $ruleChars)/4))
}

# --- RULE REACHABILITY (scoped rules whose globs match nothing) -------------
$scopedDir = Join-Path $ProjectDir ".claude\rules\scoped"
if (Test-Path $scopedDir) {
  Get-ChildItem $scopedDir -Filter *.md | ForEach-Object {
    $paths = (Select-String -Path $_.FullName -Pattern '^\s*paths?:\s*(.+)$' | Select-Object -First 1)
    if ($paths) {
      $glob = $paths.Matches[0].Groups[1].Value.Trim().Trim('"',"'")
      $probe = $glob -replace '/\*\*/\*.*$','' -replace '/\*\*.*$','' -replace '\*.*$',''
      if ($probe -and -not (Test-Path (Join-Path $ProjectDir $probe))) {
        Out-Check RECOMMENDED rules "scoped rule '$($_.Name)' targets '$glob' but '$probe' does not exist - it will never fire"
      } else { Out-Check INFO rules "scoped rule reachable: $($_.Name)" }
    }
  }
}

# --- PERMISSIONS SELF-AUDIT -------------------------------------------------
$settings = Join-Path $ProjectDir ".claude\settings.json"
if (Test-Path $settings) {
  try {
    $s = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    $allows = @($s.permissions.allow) ; $denies = @($s.permissions.deny)
    $wild = @($allows | Where-Object { $_ -match '\*' })
    if ($wild.Count -gt 0) { Out-Check RECOMMENDED perms "$($wild.Count) wildcard allow(s) - remember: a positional deny can never constrain a wildcard allow; prefer literal-safe forms" }
    if ($denies -notcontains "Bash(git push *)" -and $denies -notcontains "Bash(git push*)") { Out-Check RECOMMENDED perms "git push is not deny-listed (prompt-gated only)" }
    Out-Check INFO perms "settings.json parses ($($allows.Count) allow / $($denies.Count) deny)"
  } catch { Out-Check BLOCKING perms "settings.json does not parse: $($_.Exception.Message)" }
} else { Out-Check INFO perms "no project settings.json (defaults apply)" }

# --- INSTALL MANIFEST / VERSIONS / OWNERSHIP (D-T2-026 S3) ------------------
$manifestPath = Join-Path $ProjectDir ".counsel\manifest.json"
if (Test-Path $manifestPath) {
  try {
    $mf = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Out-Check INFO install ("manifest parses (runtime {0}, control-plane schema {1}, {2} files)" -f $mf.runtime_version, $mf.control_plane_schema, @($mf.files).Count)
    $mfMissing = 0; $mfModified = 0
    foreach ($f in $mf.files) {
      $p = Join-Path $ProjectDir ($f.path -replace "/", "\")
      if (-not (Test-Path $p)) {
        if ($f.owned) { Out-Check BLOCKING install "owned file MISSING: $($f.path) (scripts/install/repair.ps1 restores it)"; $mfMissing++ }
      } elseif ($f.owned) {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $p).Hash.ToLower()
        if ($sha -ne $f.sha256) { Out-Check RECOMMENDED install "owned file locally modified: $($f.path) (kept; repair -IncludeModified restores)"; $mfModified++ }
      }
    }
    if ($mfMissing -eq 0 -and $mfModified -eq 0) { Out-Check INFO install "ownership integrity: all owned files present and unmodified" }
    $cacheRoot = Join-Path $env:USERPROFILE ".claude\plugins\cache\counsel-os\counsel"
    if (Test-Path $cacheRoot) {
      # semver-shaped dirs only (SHA-named dirs are transient cache artifacts, never releases)
      $newest = Get-ChildItem $cacheRoot -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
      if ($newest -and ($newest.Name -ne "$($mf.runtime_version)")) {
        Out-Check RECOMMENDED install ("RUNTIME VERSION SKEW: installed plugin {0} vs project files from {1} - re-run plan+apply (update flow) to reconcile" -f $newest.Name, $mf.runtime_version)
      } elseif ($newest) { Out-Check INFO install "runtime version matches installed plugin ($($newest.Name))" }
      if ($newest) {
        $srcSchema = Join-Path $newest.FullName "scaffold\SCHEMA-VERSION"
        if (Test-Path $srcSchema) {
          $cps = (Get-Content $srcSchema -Raw).Trim()
          if ("$($mf.control_plane_schema)" -ne $cps) { Out-Check RECOMMENDED install ("CONTROL-PLANE SCHEMA SKEW: project {0} vs plugin {1} - re-plan to migrate templates" -f $mf.control_plane_schema, $cps) }
          else { Out-Check INFO install "control-plane schema matches ($cps)" }
        }
      }
    } else { Out-Check INFO install "no counsel plugin cache (scaffold-source install is valid; version skew unchecked)" }
  } catch { Out-Check BLOCKING install "manifest does not parse: $($_.Exception.Message)" }
} else { Out-Check INFO install "no ownership manifest (not yet onboarded via installer)" }

# --- AGENT MODEL VALUES (D-T2-026 R3) ---------------------------------------
$agentsDir = Join-Path $ProjectDir ".claude\agents"
if (Test-Path $agentsDir) {
  $allowed = @("inherit")
  $mapPath = Join-Path $OsDir "registry\model-map.json"
  if (Test-Path $mapPath) {
    $map = Get-Content $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $map.classes.PSObject.Properties | ForEach-Object { $allowed += $_.Value }
    $allowed += $map.fallback
  }
  $allowed = @($allowed | Select-Object -Unique)
  $agentCount = 0
  Get-ChildItem $agentsDir -Filter *.md | ForEach-Object {
    $agentCount++
    if (Select-String -Path $_.FullName -Pattern '\{\{MODEL_' -Quiet) { Out-Check BLOCKING agents "unresolved model placeholder in $($_.Name)" }
    $m = Select-String -Path $_.FullName -Pattern '^model:\s*(.+)$' | Select-Object -First 1
    if ($m) {
      $val = $m.Matches[0].Groups[1].Value.Trim().Trim('"',"'")
      if ($allowed -notcontains $val) { Out-Check RECOMMENDED agents "unsupported model value '$val' in $($_.Name) - allowed: $($allowed -join ', ')" }
    }
  }
  Out-Check INFO agents ("agent model values checked ({0} agent(s))" -f $agentCount)
}

# --- HOOK COMPATIBILITY (ruling A8: no hidden Git Bash dependency) ----------
if (Test-Path $settings) {
  try {
    $sH = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($sH.hooks) {
      $gitBash = $null -ne (Get-Command bash -ErrorAction SilentlyContinue)
      $hookCmds = @()
      $sH.hooks.PSObject.Properties | ForEach-Object { @($_.Value) | ForEach-Object { @($_.hooks) | ForEach-Object { if ($_.command) { $hookCmds += $_.command } } } }
      $nonPs = @($hookCmds | Where-Object { $_ -notmatch 'powershell(\.exe)?' })
      if (-not $gitBash -and $nonPs.Count -gt 0) {
        Out-Check RECOMMENDED hooks "$($nonPs.Count) hook(s) without explicit powershell.exe invocation and no bash on PATH - they may silently not run on Windows"
      } else { Out-Check INFO hooks ("hooks configured: {0} command(s), shell-compatible" -f $hookCmds.Count) }
    } else { Out-Check INFO hooks "no hooks configured (continuity hook pack default OFF)" }
  } catch {}
} else { Out-Check INFO hooks "no hooks configured (continuity hook pack default OFF)" }

# --- SESSION CONTINUITY -----------------------------------------------------
$sessionDir = Join-Path $ProjectDir ".counsel\session"
if (Test-Path $sessionDir) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "session\session-doctor.ps1") -Workspace $ProjectDir -SessionDir $sessionDir | ForEach-Object { Write-Host "             session      $_" }
  if ($LASTEXITCODE -eq 1) { Out-Check BLOCKING session "session doctor reports FAIL (above)" }
  elseif ($LASTEXITCODE -eq 2) { Out-Check RECOMMENDED session "session doctor reports warnings (above)" }
  # D-T2-023 semantic coherence: recorded git facts vs live git (mechanical completeness
  # is session-doctor's job; this catches semantically-stale STATE)
  $statePathSem = Join-Path $sessionDir "STATE.json"
  if (Test-Path $statePathSem) {
    try {
      $stSem = Get-Content $statePathSem -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($stSem.git) {
        $projLeaf = Split-Path $ProjectDir -Leaf
        $stSem.git.PSObject.Properties | ForEach-Object {
          $rec = $_.Value
          if ($_.Name -eq $projLeaf -and $rec.head) {
            $ErrorActionPreference = "Continue"
            $liveSem = (& git -C $ProjectDir rev-parse --verify HEAD 2>$null | Out-String).Trim()
            $ErrorActionPreference = "Stop"
            if ($liveSem -and $liveSem -ne $rec.head) {
              Out-Check RECOMMENDED session ("SEMANTIC DRIFT (D-T2-023): STATE.json records {0} @ {1} but live is {2} - reconcile openly, never silently" -f $_.Name, $rec.head.Substring(0,[Math]::Min(7,$rec.head.Length)), $liveSem.Substring(0,7))
            }
          }
        }
      }
    } catch {}
  }
} else { Out-Check RECOMMENDED session "no .counsel/session - continuity not initialized (run /counsel:onboard or /counsel:checkpoint)" }

# --- WORK PLANE -------------------------------------------------------------
$wq = Join-Path $ProjectDir ".counsel\work\WORKING-QUEUE.yaml"
if (Test-Path $wq) {
  $ready = @(Select-String -Path $wq -Pattern '^\s*-\s*\{?\s*id:').Count
  if ($ready -gt 10) { Out-Check RECOMMENDED work "working queue holds $ready entries - horizon should stay bounded (~7); triage" }
  else { Out-Check INFO work "working queue bounded ($ready entries)" }
} else { Out-Check INFO work "no work ledger yet (optional until first planned work)" }

# --- EXTERNAL DEPENDENCIES (from registry; functional > presence) -----------
function Test-Cmd([string]$Cmd, [string]$CmdArgs) {
  $ErrorActionPreference = "Continue"
  & $Cmd $CmdArgs *> $null
  $ok = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = "Stop"
  return $ok
}
if (Test-Cmd "git" "--version") { Out-Check INFO deps "git present (core-required)" } else { Out-Check BLOCKING deps "git MISSING (core-required) - install from https://git-scm.com" }
# NOTE: this loop answers "is it installed" only. Whether the tool can actually AUTHENTICATE
# is the credential-liveness family below -- registry `detect` for gh has always said functional.
foreach ($opt in @(@("gh","--version","GitHub CLI","github-work-sync capability"), @("node","--version","Node.js","Node projects"), @("python","--version","Python","Python projects"), @("docker","--version","Docker","container workflows"))) {
  if (Get-Command $opt[0] -ErrorAction SilentlyContinue) { Out-Check INFO deps "$($opt[2]) present" }
  else { Out-Check OPTIONAL deps "$($opt[2]) not found - only needed for $($opt[3])" }
}

# --- CREDENTIAL LIVENESS (D-T2-030) ----------------------------------------
# Presence is not readiness. A tool on PATH whose credential is expired, revoked, or never
# configured fails at the moment of use, not at the moment of diagnosis -- the silent-delayed
# failure this OS exists to move forward. READY is withheld unless every credential required
# by an INSTALLED capability is probed LIVE. Unprobed is UNVERIFIED, never READY.
$credScript = Join-Path $PSScriptRoot "doctor-credentials.ps1"
if (Test-Path $credScript) {
  $credArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$credScript,"-ProjectDir",$ProjectDir,"-OsDir",$OsDir)
  if ($Probe) { $credArgs += "-Probe" }
  if ($AllowRegistryCommands) { $credArgs += "-AllowRegistryCommands" }
  $ErrorActionPreference = "Continue"
  $credOut = & powershell @credArgs
  $credExit = $LASTEXITCODE
  $ErrorActionPreference = "Stop"
  $nDead = 0; $nUnk = 0; $nLive = 0
  foreach ($l in $credOut) {
    if ($l -match '^CRED SUMMARY') { continue }
    if ($l -match '^CRED (LIVE|DEAD|UNKNOWN|SKIP) (\S+) :: (.*)$') {
      $st = $Matches[1]; $who = $Matches[2]; $why = $Matches[3]
      switch ($st) {
        "LIVE"    { $nLive++;  Out-Check INFO       creds "$who LIVE -- $why" }
        "DEAD"    { $nDead++;  Out-Check BLOCKING   creds "$who -- $why" }
        "UNKNOWN" { $nUnk++;   Out-Check UNVERIFIED creds "$who -- $why" }
        "SKIP"    {            Out-Check INFO       creds "$who not applicable -- $why" }
      }
    } elseif ($l) { Write-Host ("             creds        {0}" -f $l) }
  }
  if ($nUnk -gt 0 -and -not $Probe) {
    Out-Check UNVERIFIED creds "$nUnk credential(s) unproven -- re-run: /counsel:doctor --probe (read-only, free probes only)"
  }
  if ($credExit -eq 0 -and $nLive -gt 0) { Out-Check INFO creds "all credentials required by installed capabilities are LIVE" }
} else {
  Out-Check UNVERIFIED creds "doctor-credentials.ps1 missing -- credential liveness cannot be established (repair restores it)"
}

# --- RESULT -----------------------------------------------------------------
# READY means: nothing blocking, nothing merely recommended, AND every credential an
# installed capability depends on was actually proven to work. Exit 3 exists so that
# "tools are present but your keys are unproven" can never be reported as READY.
Write-Host ""
if ($blocking -gt 0) {
  Write-Host "RESULT: $blocking BLOCKING ISSUE(S), $recommended recommendation(s), $unverified unverified"
  exit 1
}
if ($unverified -gt 0) {
  Write-Host "RESULT: NOT READY -- $unverified CREDENTIAL CHECK(S) UNVERIFIED, $recommended recommendation(s)"
  Write-Host "        Tooling is present. Liveness of the credentials above is UNPROVEN -- that is not READY."
  exit 3
}
if ($recommended -gt 0) { Write-Host "RESULT: READY WITH $recommended RECOMMENDATION(S)"; exit 2 }
Write-Host "RESULT: READY (tooling present and credentials proven live)"; exit 0
