# Core Continuity Hook Pack -- SessionStart state injector (read-only).
# Provenance: ORIGINAL (Apache-2.0). Prints RESTORE.md + CAPSULE.md so a new/cleared/compacted
# session boots with durable state in context. Never writes. Exits 0 always (graceful degrade).
param([string]$SessionDir = ".counsel\session")
try {
  $restore = Join-Path $SessionDir "RESTORE.md"
  $capsule = Join-Path $SessionDir "CAPSULE.md"
  if (Test-Path $restore) {
    Write-Host "=== COUNSEL SESSION STATE (RESTORE.md) ==="
    Get-Content $restore -Encoding UTF8
  }
  if (Test-Path $capsule) {
    Write-Host ""
    Write-Host "=== ACTIVE CAPSULE (CAPSULE.md) ==="
    Get-Content $capsule -Encoding UTF8
  }
} catch { }
exit 0
