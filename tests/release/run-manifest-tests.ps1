<#
  run-manifest-tests.ps1 - release coherence gate.

  Provenance: ORIGINAL (Apache-2.0).

  WHY THIS EXISTS. 0.1.6 shipped with VERSION=0.1.6 and plugin.json=0.1.5. Releases
  0.1.1 through 0.1.5 were all coherent; the sixth broke silently because nothing
  asserted the contract that docs/DISTRIBUTION.md states in plain words:

      "VERSION governs; plugin.json mirrors it."

  The consequence was not cosmetic. Claude Code names the plugin cache directory from
  plugin.json, while the install manifest stamps runtime_version from VERSION. When
  they disagree, scripts/doctor.ps1 compares the two and reports RUNTIME VERSION SKEW
  on a clean, correct install - forever. A diagnostic that cries wolf is worse than no
  diagnostic, and this OS is built on the claim that its gates can be trusted.

  Five releases of human discipline held. The sixth did not. That is what a test is for.

  ASCII ONLY - PowerShell 5.1 reads UTF-8-no-BOM as cp1252.

  Usage: .\run-manifest-tests.ps1     (exit 0 all pass, exit 1 any fail)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$pass = 0; $fail = 0
function Assert($cond, $name, $detail) {
  if ($cond) { Write-Host "PASS  $name" -ForegroundColor Green; $script:pass++ }
  else { Write-Host "FAIL  $name" -ForegroundColor Red; if ($detail) { Write-Host "        $detail" -ForegroundColor Red }; $script:fail++ }
}
# A skip is not a pass. It is counted and printed separately so that a contract which
# silently stops being checked cannot masquerade as a contract that is holding.
function Skip($name, $why) {
  Write-Host "SKIP  $name" -ForegroundColor Yellow
  Write-Host "        $why" -ForegroundColor DarkGray
  $script:skipped++
}
$skipped = 0

Write-Host ''

# --- M1: the stated contract ---------------------------------------------------------
$version = (Get-Content (Join-Path $Root 'VERSION') -Raw -Encoding UTF8).Trim()
$pluginPath = Join-Path $Root '.claude-plugin\plugin.json'
$plugin = Get-Content $pluginPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($plugin.version -eq $version) 'M1 plugin.json version mirrors VERSION' "VERSION=$version plugin.json=$($plugin.version)"

# --- M2: VERSION is semver-shaped, because doctor casts the cache dir to [version] ----
Assert ($version -match '^\d+\.\d+\.\d+$') 'M2 VERSION is semver-shaped' "got '$version'"

# --- M3: every JSON manifest parses (a BOM broke this once - see 0a0ec58) ------------
$badJson = @()
foreach ($j in (Get-ChildItem $Root -Recurse -Filter *.json | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
  try { Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
  catch { $badJson += $j.FullName.Substring($Root.Length + 1) }
}
Assert ($badJson.Count -eq 0) 'M3 every JSON manifest parses' ($badJson -join ', ')

# --- M4: plugin.json declares the fields the harness reads ---------------------------
Assert ($plugin.name -and $plugin.version -and $plugin.skills) 'M4 plugin.json has name, version, skills'
$skillsRel = ($plugin.skills -replace '^\./', '') -replace '/', '\'
Assert (Test-Path (Join-Path $Root $skillsRel)) 'M4 plugin.json skills path resolves' $plugin.skills

# --- M5: marketplace manifest is coherent with the plugin ----------------------------
$mkt = Get-Content (Join-Path $Root '.claude-plugin\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($mkt.plugins.Count -ge 1) 'M5 marketplace declares at least one plugin'
Assert ($mkt.plugins[0].name -eq $plugin.name) 'M5 marketplace plugin name matches plugin.json' "$($mkt.plugins[0].name) vs $($plugin.name)"

# --- M6: every shipped skill is loadable ---------------------------------------------
$skillDirs = Get-ChildItem (Join-Path $Root $skillsRel) -Directory
$badSkills = @()
foreach ($d in $skillDirs) {
  $s = Join-Path $d.FullName 'SKILL.md'
  if (-not (Test-Path $s)) { $badSkills += "$($d.Name): no SKILL.md"; continue }
  $head = Get-Content $s -TotalCount 10 -Encoding UTF8
  if ($head[0] -ne '---')                        { $badSkills += "$($d.Name): no frontmatter" }
  elseif (-not ($head -match '^name:'))          { $badSkills += "$($d.Name): no name:" }
  elseif (-not ($head -match '^description:'))   { $badSkills += "$($d.Name): no description:" }
}
Assert ($badSkills.Count -eq 0) "M6 all $($skillDirs.Count) skills have valid frontmatter" ($badSkills -join '; ')

# --- M7: the changelog records the version being shipped -----------------------------
$changelog = Get-Content (Join-Path $Root 'CHANGELOG.md') -Raw -Encoding UTF8
Assert ($changelog -match [regex]::Escape($version)) 'M7 CHANGELOG mentions the current VERSION' $version

# --- M8: the version being shipped is tagged in CANONICAL ----------------------------
#     WHY. 0.1.9 was published with the public build tagged counsel--v0.1.9 while
#     canonical carried no such tag: publish.ps1 tagged the generated snapshot and
#     nothing tagged the source. docs/RELEASE-SYNC.md section 2.2 states the contract in
#     plain words - "every public tag traces to one canonical commit" - and for one
#     release that sentence was simply false. The tag existed only on the build output,
#     which is the artifact meant to be reproducible rather than authoritative: if the
#     public repo were lost, nothing in canonical said which commit 0.1.9 was.
#
#     M1 already proves VERSION == plugin.json. This proves VERSION == canonical tag.
#     Together they close the loop the 0.1.6 skew defect opened and 0.1.9 reopened from
#     the other end. Doctrine stated a rule and no gate enforced it; that is the whole
#     lesson, and this is the gate.
#
#     SKIPPED, deliberately, when there is no .git: the suite also runs INSIDE the
#     generated snapshot (publish.ps1 step 3), where no repository exists yet and tag
#     coherence is not a property the snapshot can have. Skipping is correct there;
#     failing would make the publish pipeline unable to verify its own artifact.
if (-not (Test-Path (Join-Path $Root '.git'))) {
  Skip "M8 canonical tag counsel--v$version exists" 'no .git here - canonical-only contract (this is the generated snapshot)'
} else {
  $tag = git -C $Root tag --list "counsel--v$version"
  Assert ([bool]$tag) "M8 canonical tag counsel--v$version exists" `
    "VERSION=$version but canonical has no counsel--v$version tag. Tag the release commit and push the tag; do not rely on the snapshot's tag."
}

Write-Host ''
$suffix = if ($skipped -gt 0) { ", $skipped skipped" } else { '' }
if ($fail -gt 0) { Write-Host "MANIFEST TESTS: $pass passed, $fail failed$suffix" -ForegroundColor Red; exit 1 }
Write-Host "MANIFEST TESTS: $pass passed, $fail failed$suffix" -ForegroundColor Green
exit 0
