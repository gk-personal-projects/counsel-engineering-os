# Counsel Engineering OS -- external deploy verification gate (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Ship-loop capability.
# The exit code IS the evidence: 0 = URL returns HTTP 200 AND contains the sentinel.
# Never let the model claim a deploy succeeded without this (or equivalent) at exit 0.
# Read-only over the network; writes nothing.

param(
  [Parameter(Mandatory=$true)][string]$Url,
  [string]$Sentinel = "",            # expected content substring; "" = status check only
  [int]$TimeoutSec = 30,
  [int]$Retries = 3,
  [int]$RetryDelaySec = 5
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

for ($attempt = 1; $attempt -le $Retries; $attempt++) {
  try {
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
    if ($resp.StatusCode -eq 200) {
      if (-not $Sentinel -or $resp.Content -like ("*" + $Sentinel + "*")) {
        Write-Host "VERIFY-DEPLOY OK: $Url -> 200$(if ($Sentinel) { ", sentinel found" })"
        exit 0
      }
      Write-Host "attempt ${attempt}: 200 but sentinel '$Sentinel' NOT in response"
    } else {
      Write-Host "attempt ${attempt}: HTTP $($resp.StatusCode)"
    }
  } catch {
    Write-Host "attempt ${attempt}: $($_.Exception.Message)"
  }
  if ($attempt -lt $Retries) { Start-Sleep -Seconds $RetryDelaySec }
}
Write-Host "VERIFY-DEPLOY FAIL: $Url (after $Retries attempts)" -ForegroundColor Red
exit 1
