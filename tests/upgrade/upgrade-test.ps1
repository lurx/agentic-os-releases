<#
  Upgrade test for the Windows installer.

  Installs FromTag, opens it on a workspace whose CLAUDE.md predates the
  data/ads pointer, then installs ToTag over it and opens it again. Passes
  when the upgraded app added the pointer exactly once, under the outputs/
  line, and kept the member's own note.
#>
param(
  [Parameter(Mandatory)] [string] $FromTag,
  [Parameter(Mandatory)] [string] $ToTag,
  [Parameter(Mandatory)] [string] $Repo
)

$ErrorActionPreference = 'Stop'

$Marker = 'data/ads/summary.md'
$MemberNote = '<!-- member note: the upgrade must keep this line -->'
$StartupTimeoutSeconds = 120

$Root = Join-Path $env:RUNNER_TEMP 'upgrade-test'
$Downloads = Join-Path $Root 'downloads'
$Workspace = Join-Path $Root 'workspace'
$UserData = Join-Path $Root 'userdata'
$Out = Join-Path $Root 'out'
New-Item -ItemType Directory -Force -Path $Downloads, $Workspace, $UserData, $Out | Out-Null

function Get-Installer([string] $Tag) {
  # The releases API lists drafts for this token; `gh release download` does not find them by tag.
  $releases = gh api "repos/$Repo/releases?per_page=100" | ConvertFrom-Json
  $release = $releases | Where-Object { $_.tag_name -eq $Tag } | Select-Object -First 1
  if ($null -eq $release) { throw "No release (published or draft) with tag $Tag" }
  $asset = $release.assets | Where-Object { $_.name -like '*.exe' } | Select-Object -First 1
  if ($null -eq $asset) { throw "Release $Tag has no .exe asset" }
  $target = Join-Path $Downloads "$Tag.exe"
  # Straight to disk: piping gh output through PowerShell would re-encode the binary.
  Invoke-WebRequest -Uri $asset.url -OutFile $target -Headers @{
    Authorization = "Bearer $env:GH_TOKEN"
    Accept = 'application/octet-stream'
  }
  if ((Get-Item $target).Length -ne $asset.size) { throw "Download of $($asset.name) is incomplete" }
  Write-Host "Downloaded $($asset.name) for $Tag ($([math]::Round($asset.size / 1MB)) MB)"
  return $target
}

function Install-App([string] $Installer) {
  $process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "Installer $Installer exited with $($process.ExitCode)" }
  $exe = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs') -Filter 'AgenticOS.exe' -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $exe) { throw 'AgenticOS.exe not found after install' }
  return $exe.FullName
}

function Stop-App([string] $Exe) {
  $installDir = Split-Path $Exe
  Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($installDir) } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}

function Invoke-AppUntil([string] $Exe, [string] $Label, [scriptblock] $Condition) {
  $env:AGENTIC_OS_USER_DATA = $UserData
  $logOut = Join-Path $Out "$Label-stdout.log"
  $logErr = Join-Path $Out "$Label-stderr.log"
  Start-Process -FilePath $Exe -RedirectStandardOutput $logOut -RedirectStandardError $logErr | Out-Null
  $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  $met = $false
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) { $met = $true; break }
    Start-Sleep -Seconds 2
  }
  # Let in-flight writes finish before stopping.
  Start-Sleep -Seconds 5
  Stop-App $Exe
  return $met
}

function Read-ClaudeMd { Get-Content -Raw -Encoding utf8 (Join-Path $Workspace 'CLAUDE.md') }

# Workspace and settings as an older install left them.
Copy-Item (Join-Path $PSScriptRoot 'fixtures/CLAUDE.md') (Join-Path $Workspace 'CLAUDE.md')
@{ workspacePath = $Workspace; theme = 'system'; language = 'he'; contentDir = $Workspace } |
  ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $UserData 'settings.json')

$fromInstaller = Get-Installer $FromTag
$toInstaller = Get-Installer $ToTag

Write-Host "== $FromTag"
$exe = Install-App $fromInstaller
$skillsDir = Join-Path $Workspace '.claude/skills'
$ranRefresh = Invoke-AppUntil $exe 'from' { Test-Path $skillsDir }
if (-not $ranRefresh) { throw "$FromTag never refreshed the workspace within $StartupTimeoutSeconds s; see the logs artifact" }
Write-Host "$FromTag refreshed the workspace; CLAUDE.md has the pointer: $((Read-ClaudeMd).Contains($Marker))"

Write-Host "== $ToTag (installed over $FromTag)"
$exe = Install-App $toInstaller
$gotPointer = Invoke-AppUntil $exe 'to' { (Read-ClaudeMd).Contains($Marker) }
Copy-Item (Join-Path $Workspace 'CLAUDE.md') (Join-Path $Out 'CLAUDE.after-upgrade.md')

$failures = @()
$text = Read-ClaudeMd
$lines = $text -split "`r?`n"
$pointerIndexes = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($Marker)) { $i } })
if (-not $gotPointer) { $failures += "CLAUDE.md never gained the $Marker line" }
if ($pointerIndexes.Count -gt 1) { $failures += "the $Marker line appears $($pointerIndexes.Count) times" }
if ($pointerIndexes.Count -eq 1 -and -not $lines[$pointerIndexes[0] - 1].Contains('`outputs/`')) {
  $failures += "the $Marker line is not directly under the outputs/ line"
}
if (-not $text.Contains($MemberNote)) { $failures += "the member's own note was lost" }

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "::error::$_" }
  exit 1
}
Write-Host "PASS: upgrading $FromTag -> $ToTag added the data/ads pointer once and kept the member's edits"
