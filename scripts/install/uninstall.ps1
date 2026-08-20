# Counsel Engineering OS -- uninstall (Windows PowerShell 5.1+)
# Provenance: ORIGINAL (Apache-2.0). D-T2-026 S3: removes ONLY counsel-owned files whose
# content still matches the ownership manifest. Preserves, always:
#   - user-owned files (CLAUDE.md constitution, .claude/settings.json, .counsel/config.yaml,
#     .gitignore) -- reported, never deleted
#   - locally-MODIFIED owned files (user changed them; deleting would destroy user work)
#   - .counsel/session/ working state and .counsel/originals/ backups
# The manifest is archived (not deleted) so uninstall is auditable. App code is never touched.

param(
  [Parameter(Mandatory=$true)][string]$Target
)
$ErrorActionPreference = "Stop"

$Target = (Resolve-Path $Target).Path
$manifestPath = Join-Path $Target ".counsel\manifest.json"
if (-not (Test-Path $manifestPath)) { Write-Error "No ownership manifest at $manifestPath - nothing to uninstall"; exit 1 }
$mf = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json

$removed = @(); $preservedModified = @(); $leftUserOwned = @(); $alreadyGone = @()
foreach ($f in $mf.files) {
  $p = Join-Path $Target ($f.path -replace "/", "\")
  if (-not $f.owned) { $leftUserOwned += $f.path; continue }
  if (-not (Test-Path $p)) { $alreadyGone += $f.path; continue }
  $sha = (Get-FileHash -Algorithm SHA256 -Path $p).Hash.ToLower()
  if ($sha -ne $f.sha256) { $preservedModified += $f.path; continue }
  try { (Get-Item $p -Force).Attributes = 'Normal' } catch {}
  Remove-Item $p -Force
  $removed += $f.path
}

# prune now-empty directories that the install created (never removes non-empty dirs)
foreach ($d in @(".claude\agents", ".claude\rules", ".counsel\work\tickets", ".counsel\work", ".counsel\session")) {
  $dp = Join-Path $Target $d
  if ((Test-Path $dp) -and -not (Get-ChildItem $dp -Force -ErrorAction SilentlyContinue)) { Remove-Item $dp -Force }
}

# archive the manifest (audit trail), then remove the live copy
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archiveDir = Join-Path $Target (".counsel\originals\uninstall-" + $stamp)
New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
Copy-Item $manifestPath (Join-Path $archiveDir "manifest.json") -Force
Remove-Item $manifestPath -Force

Write-Host ("UNINSTALL: removed {0} counsel-owned file(s)." -f $removed.Count)
if ($preservedModified.Count -gt 0) {
  Write-Host ("PRESERVED locally-modified owned file(s) ({0}) - user work is never deleted:" -f $preservedModified.Count)
  $preservedModified | ForEach-Object { Write-Host "  = $_" }
}
if ($leftUserOwned.Count -gt 0) {
  Write-Host ("LEFT user-owned file(s) ({0}):" -f $leftUserOwned.Count)
  $leftUserOwned | ForEach-Object { Write-Host "  = $_" }
}
if ($alreadyGone.Count -gt 0) { Write-Host ("Already absent: {0}" -f ($alreadyGone -join ", ")) }
Write-Host "Manifest archived: $archiveDir\manifest.json"
Write-Host "App code untouched. Session state and originals preserved."
exit 0
