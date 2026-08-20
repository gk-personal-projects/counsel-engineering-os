<#
  run-all.ps1 - run every test suite in this repository.

  Provenance: ORIGINAL (Apache-2.0).

  WHY THIS EXISTS. Before this file, the suites could only be run one at a time, by
  name, from memory. "Run the tests" therefore meant "run the suites you happen to
  remember" - and a suite nobody remembers is a suite that does not gate anything.
  0.1.6 shipped a version-coherence defect partly for this reason: the check did not
  exist, and there was no single place that would have made its absence obvious.

  Adding a suite means adding one line here. If you add a suite and do not add the
  line, it does not run in any release, and this comment is the reason you will be
  annoyed later.

  ASCII ONLY - PowerShell 5.1 reads UTF-8-no-BOM as cp1252.

  Usage:
    .\run-all.ps1            # run everything, summarise
    .\run-all.ps1 -Quiet     # drop the per-suite banners (see the caveat below)

  -Quiet CAVEAT, stated rather than pretended: the suites emit their results with
  Write-Host, which writes straight to the host and cannot be captured or suppressed
  by a caller in PowerShell 5.1. So -Quiet removes this script's own banners and
  nothing else; suite output still appears. Making it truly quiet means converting
  every suite to Write-Output, which is a larger change than it looks and is not
  worth breaking five working suites over. The summary at the end is the part to read.

  Exit: 0 if every suite exits 0, otherwise 1.
#>
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$TestsRoot = $PSScriptRoot

$Suites = @(
  @{ Name = 'release';    Path = 'release\run-manifest-tests.ps1' }
  @{ Name = 'doctor';     Path = 'doctor\run-credential-tests.ps1' }
  @{ Name = 'continuity'; Path = 'continuity\run-tests.ps1' }
  @{ Name = 'install';    Path = 'install\run-install-tests.ps1' }
  @{ Name = 'lifecycle';  Path = 'install\run-lifecycle-tests.ps1' }
)

$results = @()
foreach ($s in $Suites) {
  $full = Join-Path $TestsRoot $s.Path
  if (-not (Test-Path $full)) {
    Write-Host "MISSING SUITE: $($s.Path)" -ForegroundColor Red
    $results += [pscustomobject]@{ Suite = $s.Name; Exit = 127; Status = 'MISSING' }
    continue
  }
  if (-not $Quiet) { Write-Host ''; Write-Host "===== $($s.Name) =====" -ForegroundColor Cyan }
  $out = & $full 2>&1
  $code = $LASTEXITCODE
  if (-not $Quiet) { $out | ForEach-Object { Write-Host $_ } }
  # Suites report their own counts; capture the tail line that carries them.
  $tail = ($out | Select-String -Pattern 'passed,\s*\d+\s*failed' | Select-Object -Last 1)
  $results += [pscustomobject]@{
    Suite  = $s.Name
    Exit   = $code
    Status = $(if ($code -eq 0) { 'PASS' } else { 'FAIL' })
    Detail = $(if ($tail) { $tail.ToString().Trim() } else { '' })
  }
}

Write-Host ''
Write-Host '===== SUMMARY =====' -ForegroundColor Cyan
foreach ($r in $results) {
  $color = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
  Write-Host ("  {0,-11} {1,-5} exit={2}  {3}" -f $r.Suite, $r.Status, $r.Exit, $r.Detail) -ForegroundColor $color
}
$failed = @($results | Where-Object { $_.Exit -ne 0 })
Write-Host ''
if ($failed.Count) {
  Write-Host "SUITES FAILED: $($failed.Count) of $($results.Count)" -ForegroundColor Red
  exit 1
}
Write-Host "ALL $($results.Count) SUITES PASSED" -ForegroundColor Green
exit 0
