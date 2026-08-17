# ExecAI Studio installer for Windows. One command (PowerShell):
#
#   irm https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.ps1 | iex
#   # or
#   irm https://raw.githubusercontent.com/execai/execai-studio/main/install.ps1 | iex
#
# Downloads the zip (GitHub first, the Yandex mirror second), unpacks it into
# %LOCALAPPDATA%\Programs\ExecAI Studio and creates a Start Menu shortcut.
# No admin rights: everything stays in the user profile. Expand-Archive does
# not propagate the mark-of-the-web, so the unsigned exe starts without the
# SmartScreen wall a downloaded installer would hit.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Mirror = 'https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable'
$Repo = 'execai/execai-studio'
$Platform = 'win32-x64'

if ([Environment]::Is64BitOperatingSystem -eq $false) {
  throw 'ExecAI Studio needs 64-bit Windows.'
}

# Latest version: GitHub first, the mirror second.
$version = $null
try { $version = (Invoke-RestMethod -TimeoutSec 15 "https://api.github.com/repos/$Repo/releases/latest").tag_name -replace '^v', '' } catch {}
if (-not $version) {
  $version = (Invoke-RestMethod -TimeoutSec 15 "$Mirror/latest.json").version
}
if (-not $version) { throw 'could not determine the latest version' }

$file = "ExecAI-Studio-$Platform-$version.zip"
$tmp = Join-Path $env:TEMP "execai-studio-$version.zip"
Write-Host "==> ExecAI Studio $version ($Platform)"

try {
  Invoke-WebRequest "https://github.com/$Repo/releases/download/v$version/$file" -OutFile $tmp
} catch {
  Write-Host '==> GitHub failed, trying the mirror'
  Invoke-WebRequest "$Mirror/$file" -OutFile $tmp
}

$dest = Join-Path $env:LOCALAPPDATA 'Programs\ExecAI Studio'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null

$extract = Join-Path $env:TEMP "execai-studio-$version"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive $tmp -DestinationPath $extract
Move-Item (Join-Path $extract "ExecAI-Studio-$Platform") $dest
Remove-Item $tmp -Force
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue

$exe = Join-Path $dest 'ExecAI Studio.exe'
if (-not (Test-Path $exe)) { throw "unexpected archive layout: no 'ExecAI Studio.exe'" }

# Start Menu shortcut.
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'ExecAI Studio.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcut)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $dest
$lnk.Save()

Write-Host "==> installed: $dest"
Write-Host '    find "ExecAI Studio" in the Start Menu'
