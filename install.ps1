# ExecAI Studio installer for Windows. One command (PowerShell):
#
#   irm https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable/install.ps1 | iex
#   # or
#   irm https://raw.githubusercontent.com/execai/execai-studio/main/install.ps1 | iex
#
# Downloads the zip (GitHub first, the Yandex mirror second), unpacks it into
# %LOCALAPPDATA%\Programs\ExecAI Studio and creates a Start Menu shortcut.
# No admin rights: everything stays in the user profile. Files are written by
# the script itself, so nothing carries the mark-of-the-web and the unsigned
# exe starts without the SmartScreen wall a downloaded installer would hit.

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

# Download with a percentage. Invoke-WebRequest's own progress bar makes the
# download several times slower, so the stream is copied by hand and the
# console line is updated in place.
function Get-WithProgress([string]$url, [string]$out) {
  $client = New-Object System.Net.Http.HttpClient
  $client.Timeout = [TimeSpan]::FromMinutes(20)
  try {
    $resp = $client.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode) - $url" }
    $total = $resp.Content.Headers.ContentLength
    $in = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $fs = [System.IO.File]::Create($out)
    try {
      $buf = New-Object byte[] (1MB); $done = 0L; $last = -1
      while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $fs.Write($buf, 0, $n); $done += $n
        if ($total) {
          $pct = [int](100 * $done / $total)
          if ($pct -ne $last) { Write-Host ("`r    downloading {0,3}%  ({1:N0} / {2:N0} MB)" -f $pct, ($done/1MB), ($total/1MB)) -NoNewline; $last = $pct }
        } else {
          Write-Host ("`r    downloading {0:N0} MB" -f ($done/1MB)) -NoNewline
        }
      }
      Write-Host ''
    } finally { $fs.Dispose(); $in.Dispose() }
  } finally { $client.Dispose() }
}

try {
  Get-WithProgress "https://github.com/$Repo/releases/download/v$version/$file" $tmp
} catch {
  Write-Host ''
  Write-Host '==> GitHub failed, trying the mirror'
  Get-WithProgress "$Mirror/$file" $tmp
}

$dest = Join-Path $env:LOCALAPPDATA 'Programs\ExecAI Studio'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null

$extract = Join-Path $env:TEMP "execai-studio-$version"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
# Unpack with a percentage: entry by entry through ZipFile, so the line
# above ticks instead of the console freezing on a 300 MB archive.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
try {
  $entries = $zip.Entries; $total = $entries.Count; $i = 0; $last = -1
  foreach ($e in $entries) {
    $target = Join-Path $extract $e.FullName
    if ($e.FullName.EndsWith('/')) {
      New-Item -ItemType Directory -Force -Path $target | Out-Null
    } else {
      $dir = Split-Path $target
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
    $i++
    $pct = [int](100 * $i / $total)
    if ($pct -ne $last) { Write-Host ("`r    unpacking {0,3}%" -f $pct) -NoNewline; $last = $pct }
  }
  Write-Host ''
} finally { $zip.Dispose() }
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

# «Open with ExecAI Studio» in the Explorer context menu — for folders, the
# folder background and files. HKCU only, so no admin rights and no clash
# with a machine-wide install; the editor re-checks these keys on every start.
$icon = "`"$exe`""
$menu = 'Open with ExecAI Studio'
foreach ($key in @('Software\Classes\Directory\shell\ExecAIStudio',
                   'Software\Classes\Directory\Background\shell\ExecAIStudio',
                   'Software\Classes\*\shell\ExecAIStudio')) {
  $k = "HKCU:\$key"
  New-Item -Path "$k\command" -Force | Out-Null
  Set-ItemProperty -Path $k -Name '(default)' -Value $menu
  Set-ItemProperty -Path $k -Name 'Icon' -Value $icon
  $arg = if ($key -like '*Background*') { '"%V"' } else { '"%1"' }
  Set-ItemProperty -Path "$k\command" -Name '(default)' -Value "`"$exe`" $arg"
}
# App Paths: lets «Run» and the shell find execai-studio by name.
$appPaths = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\execai-studio.exe'
New-Item -Path $appPaths -Force | Out-Null
Set-ItemProperty -Path $appPaths -Name '(default)' -Value $exe
Set-ItemProperty -Path $appPaths -Name 'Path' -Value $dest

Write-Host "==> installed: $dest"
Write-Host '    find "ExecAI Studio" in the Start Menu, or right-click a folder → Open with ExecAI Studio'
