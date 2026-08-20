# Counsel Engineering OS -- credential liveness engine (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Consumed by scripts/doctor.ps1; runnable standalone.
#
# WHY THIS EXISTS (D-T2-030): tooling presence is not readiness. `gh` on PATH with an expired
# token, a POSTHOG key rotated last week, a Vercel login that lapsed -- every one of those
# passes a presence check and fails at the moment of use. That is silent-delayed failure, the
# exact class this OS exists to move forward. READY is therefore withheld unless every
# credential required by an INSTALLED capability is either probed LIVE or explicitly SKIPped.
#
# LAWS:
#   1. Never fabricate LIVE. Unprobed is UNKNOWN. Unreachable network is UNKNOWN, not DEAD --
#      a probe that could not run has proven nothing about the key.
#   2. Never print secret material. Values are scrubbed from all output, including error text.
#   3. Probes are read-only. mutating:true in the registry is refused, not honoured.
#   4. Probes leave the machine, so they are opt-in (-Probe). A default run is offline and says so.
#
# Exit: 0 all-clear | 1 blocking (dead/missing cred for an installed capability) | 3 unverified

param(
  [string]$ProjectDir = (Get-Location).Path,
  [string]$OsDir = "",
  [switch]$Probe,
  [switch]$AllowRegistryCommands,
  [int]$CacheTtlHours = 12,
  [switch]$NoCache
)
$ErrorActionPreference = "Stop"
if (-not $OsDir) { $OsDir = Split-Path $PSScriptRoot -Parent }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:secrets = @()
function Protect-Text([string]$Text) {
  if (-not $Text) { return $Text }
  foreach ($s in $script:secrets) { if ($s -and $s.Length -ge 6) { $Text = $Text.Replace($s, "***REDACTED***") } }
  return $Text
}
function Get-Fingerprint([string]$Value) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("counsel-cred-fp-v1:" + $Value))
  $sha.Dispose()
  return ([BitConverter]::ToString($h) -replace '-','').Substring(0,8).ToLower()
}

# --- registry parse (line-based; PS 5.1 has no YAML parser) ------------------
$depFile = Join-Path $OsDir "registry\dependencies.yaml"
if (-not (Test-Path $depFile)) { Write-Host "CRED SKIP - :: dependency registry not found at $depFile"; exit 0 }

$creds = @(); $curDep = $null; $cur = $null; $inCreds = $false
foreach ($line in (Get-Content $depFile -Encoding UTF8)) {
  if ($line -match '^- id:\s*(\S+)') { if ($cur) { $creds += $cur; $cur = $null }; $curDep = $Matches[1]; $inCreds = $false; continue }
  if ($line -match '^  credentials:\s*$') { $inCreds = $true; continue }
  if ($inCreds -and $line -match '^  \S') { if ($cur) { $creds += $cur; $cur = $null }; $inCreds = $false; continue }
  if (-not $inCreds) { continue }
  if ($line -match '^    - id:\s*(\S+)') {
    if ($cur) { $creds += $cur }
    $cur = [ordered]@{ id = $Matches[1]; dep = $curDep; env = @(); via = ""; scope = ""; probe = "none";
                       probe_note = ""; probe_url = ""; probe_auth = ""; probe_cmd = "";
                       cost = "unknown"; mutating = $false; rotate = ""; required_by = @() }
    continue
  }
  if ($cur -and $line -match '^      ([a-z_]+):\s*(.*)$') {
    $k = $Matches[1]; $v = $Matches[2].Trim()
    if ($v -match '^\[(.*)\]$') { $cur[$k] = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim([char]34).Trim([char]39) } | Where-Object { $_ }) }
    elseif ($v -eq 'true' -or $v -eq 'false') { $cur[$k] = ($v -eq 'true') }
    else { $cur[$k] = $v.Trim([char]34).Trim([char]39) }
  }
}
if ($cur) { $creds += $cur }
if ($creds.Count -eq 0) { Write-Host "CRED SKIP - :: registry declares no credentials"; exit 0 }

# --- which capabilities are actually installed ------------------------------
$installed = @(); $configSeen = $false
$cfg = Join-Path $ProjectDir ".counsel\config.yaml"
if (Test-Path $cfg) {
  $configSeen = $true
  $m = Select-String -Path $cfg -Pattern '^installed_layers:\s*\[(.*)\]' | Select-Object -First 1
  if ($m) { $installed = @($m.Matches[0].Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim([char]34).Trim([char]39) } | Where-Object { $_ }) }
}

# --- liveness cache (states only; never secret material) --------------------
$cachePath = Join-Path $ProjectDir ".counsel\credential-liveness.json"
$cache = @{}
if (-not $NoCache -and (Test-Path $cachePath)) {
  try { (Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } } catch { $cache = @{} }
}
$cacheOut = @{}

# --- probes (read-only, non-mutating, closed set) ---------------------------
function Invoke-HttpProbe([string]$Url, [string]$Auth, [string]$Value) {
  $headers = @{}
  $uri = $Url
  if ($Auth -eq 'bearer' -or -not $Auth) { $headers["Authorization"] = "Bearer $Value" }
  elseif ($Auth -like 'header:*') { $headers[$Auth.Substring(7)] = $Value }
  elseif ($Auth -like 'query:*') {
    $sep = "?"; if ($uri.Contains("?")) { $sep = "&" }
    $uri = $uri + $sep + $Auth.Substring(6) + "=" + [uri]::EscapeDataString($Value)
  }
  try {
    $r = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -UseBasicParsing -TimeoutSec 20
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { return @{ state = "LIVE"; reason = "HTTP $($r.StatusCode)" } }
    return @{ state = "UNKNOWN"; reason = "probe-error: unexpected HTTP $($r.StatusCode)" }
  } catch {
    $code = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $code = [int]$_.Exception.Response.StatusCode }
    if ($code -eq 401 -or $code -eq 403) { return @{ state = "DEAD"; reason = "HTTP $code -- credential rejected" } }
    if ($code) { return @{ state = "UNKNOWN"; reason = "probe-error: HTTP $code (not a credential verdict)" } }
    return @{ state = "UNKNOWN"; reason = "probe-error: " + (Protect-Text $_.Exception.Message) + " (a network fault is not a credential verdict)" }
  }
}
function Invoke-CliProbe([string]$Exe, [string[]]$CliArgs) {
  if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
    return @{ state = "UNKNOWN"; reason = "tool-missing: $Exe not on PATH (the dependency check owns this finding)" }
  }
  $ErrorActionPreference = "Continue"
  & $Exe @CliArgs *> $null
  $code = $LASTEXITCODE
  $ErrorActionPreference = "Stop"
  if ($code -eq 0) { return @{ state = "LIVE"; reason = "$Exe exited 0" } }
  return @{ state = "DEAD"; reason = "$Exe exited $code -- not authenticated" }
}

# --- evaluation -------------------------------------------------------------
$blocking = 0; $unverified = 0; $live = 0
foreach ($c in $creds) {
  $relevant = $true
  if ($c.required_by -and $c.required_by.Count -gt 0) {
    if ($configSeen) { $relevant = @($c.required_by | Where-Object { $installed -contains $_ }).Count -gt 0 }
    else { $relevant = $false }
  }
  $label = "$($c.dep)/$($c.id)"

  if (-not $relevant) {
    $why = "capability not installed"
    if (-not $configSeen) { $why = "no .counsel/config.yaml -- installed capabilities unknown" }
    Write-Host "CRED SKIP $label :: $why (needed by: $($c.required_by -join ', '))"
    continue
  }

  $value = $null; $source = $null
  foreach ($e in $c.env) {
    $v = [Environment]::GetEnvironmentVariable($e)
    if ($v) { $value = $v; $source = "env:$e"; break }
  }
  if ($value) { $script:secrets += $value }

  $toolManaged = [bool]$c.via
  if (-not $value -and -not $toolManaged) {
    $blocking++
    Write-Host "CRED DEAD $label :: NOT CONFIGURED -- none of [$($c.env -join ', ')] is set, but $($c.required_by -join '/') is installed. Grants: $($c.scope). Set or rotate at: $($c.rotate)"
    continue
  }
  if (-not $value) { $source = "tool-store ($($c.via))" }

  $fp = "n/a"
  if ($value) { $fp = Get-Fingerprint $value }
  $shown = $source
  if ($value) { $shown = "$source, len $($value.Length), fp $fp" }

  if ($c.mutating -eq $true) {
    $unverified++
    Write-Host "CRED UNKNOWN $label :: REFUSED -- the registry marks this probe mutating; a probe with side effects is not a diagnostic. Fix the registry entry. [$shown]"
    continue
  }

  if ($c.probe -eq "none") {
    $unverified++
    $note = $c.probe_note
    if (-not $note) { $note = "the registry declares no probe and gives no reason -- registry defect" }
    Write-Host "CRED UNKNOWN $label :: NOT PROBEABLE -- $note [$shown]"
    continue
  }

  $ck = "$label|$fp"
  if (-not $NoCache -and $cache.ContainsKey($ck)) {
    $entry = $cache[$ck]
    $age = New-TimeSpan -Days 999
    try { $age = (Get-Date) - [datetime]$entry.probedAt } catch { }
    if ($age.TotalHours -lt $CacheTtlHours) {
      $cacheOut[$ck] = $entry
      $mins = [math]::Round($age.TotalMinutes)
      if ($entry.state -eq "LIVE") { $live++; Write-Host "CRED LIVE $label :: cached ${mins}m ago -- $($entry.reason) [$shown]"; continue }
      if ($entry.state -eq "DEAD") { $blocking++; Write-Host "CRED DEAD $label :: cached ${mins}m ago -- $($entry.reason). Grants: $($c.scope). Rotate at: $($c.rotate)"; continue }
    }
  }

  if (-not $Probe) {
    $unverified++
    Write-Host "CRED UNKNOWN $label :: NOT PROBED -- offline run, liveness unproven. Re-run with -Probe to reach $($c.dep) (read-only, cost: $($c.cost)). [$shown]"
    continue
  }
  if ($c.cost -ne "free") {
    $unverified++
    Write-Host "CRED UNKNOWN $label :: NOT PROBED -- probe cost is '$($c.cost)'; metered or unknown-cost probes are ask-first and never run unattended. [$shown]"
    continue
  }

  $res = $null
  switch ($c.probe) {
    "gh-auth"       { $res = Invoke-CliProbe "gh" @("auth","status") }
    "supabase-auth" { $res = Invoke-CliProbe "supabase" @("projects","list") }
    "vercel-whoami" { $res = Invoke-CliProbe "vercel" @("whoami") }
    "posthog-me"    { $res = Invoke-HttpProbe "https://us.posthog.com/api/users/@me/" "bearer" $value }
    "sentry-api"    { $res = Invoke-HttpProbe "https://sentry.io/api/0/organizations/" "bearer" $value }
    "http-get-200"  {
      if (-not $c.probe_url) { $res = @{ state = "UNKNOWN"; reason = "registry defect: probe http-get-200 without probe_url" } }
      else { $res = Invoke-HttpProbe $c.probe_url $c.probe_auth $value }
    }
    "cmd-exit0"     {
      if (-not $AllowRegistryCommands) { $res = @{ state = "UNKNOWN"; reason = "probe cmd-exit0 needs -AllowRegistryCommands: a modified registry would become code execution, so running its command is a separate consent" } }
      elseif (-not $c.probe_cmd) { $res = @{ state = "UNKNOWN"; reason = "registry defect: probe cmd-exit0 without probe_cmd" } }
      else {
        $parts = @($c.probe_cmd -split '\s+')
        $rest = @()
        if ($parts.Count -gt 1) { $rest = $parts[1..($parts.Count - 1)] }
        $res = Invoke-CliProbe $parts[0] $rest
      }
    }
    default         { $res = @{ state = "UNKNOWN"; reason = "unknown probe '$($c.probe)' -- registry defect" } }
  }

  $stamp = (Get-Date).ToString("o")
  if ($res.state -eq "LIVE" -or $res.state -eq "DEAD") {
    $cacheOut[$ck] = @{ state = $res.state; reason = $res.reason; probedAt = $stamp }
  }
  $msg = Protect-Text $res.reason
  if ($res.state -eq "LIVE") { $live++; Write-Host "CRED LIVE $label :: $msg [$shown]" }
  elseif ($res.state -eq "DEAD") { $blocking++; Write-Host "CRED DEAD $label :: $msg. Grants: $($c.scope). Rotate at: $($c.rotate)" }
  else { $unverified++; Write-Host "CRED UNKNOWN $label :: $msg [$shown]" }
}

if (-not $NoCache -and (Test-Path (Join-Path $ProjectDir ".counsel"))) {
  try { ($cacheOut | ConvertTo-Json -Depth 5) | Set-Content -Path $cachePath -Encoding UTF8 } catch { }
}

Write-Host "CRED SUMMARY live=$live dead-or-missing=$blocking unverified=$unverified"
if ($blocking -gt 0) { exit 1 }
if ($unverified -gt 0) { exit 3 }
exit 0
