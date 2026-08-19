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
# GitHub needs TLS 1.2; Windows PowerShell 5.1 on older systems does not enable it.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Mirror = 'https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable'
$Repo = 'execai/execai-studio'
$Platform = 'win32-x64'

if ([Environment]::Is64BitOperatingSystem -eq $false) {
  throw 'ExecAI Studio needs 64-bit Windows.'
}

# Version: $env:EXECAI_STUDIO_VERSION pins one (tests, rollbacks); otherwise the
# latest — GitHub first, the mirror second.
$version = $env:EXECAI_STUDIO_VERSION
if (-not $version) {
  try { $version = (Invoke-RestMethod -TimeoutSec 15 "https://api.github.com/repos/$Repo/releases/latest").tag_name -replace '^v', '' } catch {}
}
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
function Get-WithProgress([string]$url, [string]$out, [string]$label = "    downloading") {
  # Windows PowerShell 5.1 does not have System.Net.Http loaded; ask for it,
  # and if that fails too (very old .NET) fall back to WebClient.
  $client = $null
  try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop; $client = New-Object System.Net.Http.HttpClient } catch { $client = $null }
  if (-not $client) {
    $wc = New-Object System.Net.WebClient
    $done = 0L; $last = -1
    $null = Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dl -Action {
      $p = $EventArgs.ProgressPercentage
      Write-Host ("`r  $($Event.MessageData) {0,3}%  ({1:N0} / {2:N0} MB)" -f $p, ($EventArgs.BytesReceived/1MB), ($EventArgs.TotalBytesToReceive/1MB)) -NoNewline
    } -MessageData $label
    try { $wc.DownloadFileTaskAsync($url, $out).GetAwaiter().GetResult() }
    finally { Unregister-Event dl -ErrorAction SilentlyContinue; $wc.Dispose() }
    return
  }
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
          if ($pct -ne $last) { Write-Host ("`r  $label {0,3}%  ({1:N0} / {2:N0} MB)" -f $pct, ($done/1MB), ($total/1MB)) -NoNewline; $last = $pct }
        }
      }
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

# Checksum: SHA256SUMS from GitHub, then the mirror. .Content of an
# octet-stream response is a byte[] in Windows PowerShell 5.1 — decode it.
function Get-Text([string]$u) {
  $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 $u
  if ($r.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($r.Content) }
  return [string]$r.Content
}
$sums = $null
try { $sums = Get-Text "https://github.com/$Repo/releases/download/v$version/SHA256SUMS" } catch {}
if (-not $sums) { try { $sums = Get-Text "$Mirror/SHA256SUMS" } catch {} }
if ($sums) {
  $line = ($sums -split "[`r`n]+") | Where-Object { $_.Trim().EndsWith($file) } | Select-Object -First 1
  if ($line) {
    $want = ($line.Trim() -split '\s+')[0].ToLower()
    $got  = (Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLower()
    if ($want -ne $got) { throw 'checksum mismatch - the file is corrupted or tampered with' }
    Write-Host '==> checksum ok'
  }
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
