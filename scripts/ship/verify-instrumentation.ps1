# Counsel Engineering OS -- external instrumentation verification gate (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). Ship-loop capability.
# Sends a canary event to PostHog's capture endpoint, then polls the events API until it
# is queryable. Exit 0 = the pipeline works end to end. Never let the model claim
# instrumentation is live without this at exit 0.
# -PersonalApiKey (read scope) enables the query poll; without it, only capture-accepted
# is verified and the script exits 0 with a stated limitation.

param(
  [string]$PostHogHost = "https://us.i.posthog.com",
  [Parameter(Mandatory=$true)][string]$ProjectKey,     # phc_... (public capture key)
  [string]$PersonalApiKey = "",                        # phx_... (read); optional
  [string]$QueryHost = "https://us.posthog.com",
  [string]$ProjectId = "",                             # numeric; required for the query poll
  [int]$PollAttempts = 10,
  [int]$PollDelaySec = 15
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$canaryId = "counsel-canary-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + (Get-Random -Maximum 99999)
$payload = @{ api_key = $ProjectKey; event = "counsel_instrumentation_canary"
              distinct_id = $canaryId; properties = @{ source = "verify-instrumentation" } } | ConvertTo-Json

try {
  $resp = Invoke-WebRequest -Uri ($PostHogHost.TrimEnd('/') + "/i/v0/e/") -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing -TimeoutSec 30
  if ($resp.StatusCode -ne 200) { Write-Host "VERIFY-INSTRUMENTATION FAIL: capture endpoint HTTP $($resp.StatusCode)" -ForegroundColor Red; exit 1 }
  Write-Host "canary accepted by capture endpoint ($canaryId)"
} catch {
  Write-Host "VERIFY-INSTRUMENTATION FAIL: capture send error: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

if (-not $PersonalApiKey -or -not $ProjectId) {
  Write-Host "VERIFY-INSTRUMENTATION OK (capture-accepted only; pass -PersonalApiKey and -ProjectId to verify queryability)"
  exit 0
}

$headers = @{ Authorization = "Bearer $PersonalApiKey" }
$queryBody = @{ query = @{ kind = "HogQLQuery"
  query = "select count() from events where event = 'counsel_instrumentation_canary' and distinct_id = '$canaryId'" } } | ConvertTo-Json -Depth 5
for ($i = 1; $i -le $PollAttempts; $i++) {
  Start-Sleep -Seconds $PollDelaySec
  try {
    $q = Invoke-RestMethod -Uri ($QueryHost.TrimEnd('/') + "/api/projects/$ProjectId/query/") -Method Post -Headers $headers -Body $queryBody -ContentType "application/json" -TimeoutSec 30
    $count = $q.results[0][0]
    if ($count -ge 1) { Write-Host "VERIFY-INSTRUMENTATION OK: canary queryable after $($i * $PollDelaySec)s"; exit 0 }
    Write-Host "poll ${i}: not yet queryable"
  } catch { Write-Host "poll ${i}: query error: $($_.Exception.Message)" }
}
Write-Host "VERIFY-INSTRUMENTATION FAIL: canary never became queryable (accepted but not visible after $($PollAttempts * $PollDelaySec)s)" -ForegroundColor Red
exit 1
