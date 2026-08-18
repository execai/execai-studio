# ExecAI Studio updater for Windows. Started by the editor right before it
# quits; runs in its own console so the user sees what happens while the
# editor window is gone. Everything is done here — waiting for the editor to
# close, downloading (GitHub first, mirror second), SHA-256, unpacking, the
# folder swap with retries on busy files, starting the new build. On any
# failure it explains why, puts the previous version back and waits for Enter.
#
#   updater.ps1 -Version 0.1.21 -Install "C:\...\ExecAI Studio" [-Folder <workspace>]

param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$Install,
  [string]$Folder = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = "ExecAI Studio - updating to $Version"

$Repo   = 'execai/execai-studio'
$Mirror = 'https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable'
$file   = "ExecAI-Studio-win32-x64-$Version.zip"
$parent = Split-Path $Install
$leaf   = Split-Path $Install -Leaf
$staging = Join-Path $parent "$leaf.staging-$Version"
$old     = "$Install.old"
$exe     = Join-Path $Install 'ExecAI Studio.exe'

function Step($n, $t) { Write-Host ("  [{0}/6] {1}" -f $n, $t) -NoNewline }
function Done { Write-Host ' done' -ForegroundColor Green }
function Retry($what, $act) {
  # Defender / indexers hold freshly written files for a moment: keep trying.
  $deadline = (Get-Date).AddSeconds(90); $n = 0
  while ($true) {
    try { & $act; return } catch {
      $n++
      if ((Get-Date) -gt $deadline) { throw "$what : $($_.Exception.Message)" }
      if ($n -eq 1) { Write-Host ''; Write-Host '        (files still in use, retrying...)' -ForegroundColor DarkGray }
      Start-Sleep -Seconds 2
    }
  }
}
function Get-WithProgress([string]$url, [string]$out, [string]$label) {
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
          if ($pct -ne $last) { Write-Host ("`r  $label {0,3}%  ({1:N0} / {2:N0} MB)" -f $pct, ($done/1MB), ($total/1MB)) -NoNewline; $last = $pct }
        }
      }
    } finally { $fs.Dispose(); $in.Dispose() }
  } finally { $client.Dispose() }
}

Write-Host ''
Write-Host "  ExecAI Studio update $Version" -ForegroundColor Cyan
Write-Host '  ------------------------------'
try {
  Step 1 'waiting for ExecAI Studio to close...'
  $deadline = (Get-Date).AddMinutes(3)
  while ((Get-Date) -lt $deadline) {
    $running = Get-Process | Where-Object { try { $_.Path -and $_.Path.StartsWith($Install, [StringComparison]::OrdinalIgnoreCase) } catch { $false } }
    if (-not $running) { break }
    Start-Sleep -Milliseconds 500
  }
  Done

  # A previous attempt may have left a locked staging folder; never let it
  # block this one — sweep what we can, and use a version-specific name.
  Get-ChildItem $parent -Directory -Filter "$leaf.staging*" -ErrorAction SilentlyContinue |
    ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop } catch {} }
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  $zip = Join-Path $staging $file

  Write-Host "  [2/6] downloading $file"
  try {
    Get-WithProgress "https://github.com/$Repo/releases/download/v$Version/$file" $zip '[2/6] downloading'
  } catch {
    Write-Host ''; Write-Host '        GitHub failed, trying the mirror' -ForegroundColor DarkGray
    Get-WithProgress "$Mirror/$file" $zip '[2/6] downloading'
  }
  Done

  Step 3 'verifying checksum...'
  $sums = $null
  try { $sums = (Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/releases/download/v$Version/SHA256SUMS").Content } catch {}
  if (-not $sums) { $sums = (Invoke-WebRequest -UseBasicParsing "$Mirror/SHA256SUMS").Content }
  $line = ($sums -split "`n") | Where-Object { $_.Trim().EndsWith($file) } | Select-Object -First 1
  if (-not $line) { throw "$file is missing from SHA256SUMS" }
  $want = ($line.Trim() -split '\s+')[0].ToLower()
  $got  = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
  if ($want -ne $got) { throw 'checksum mismatch - the file is corrupted or tampered with' }
  Done

  Write-Host '  [4/6] unpacking...' -NoNewline
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $unpack = Join-Path $staging 'unpacked'
  New-Item -ItemType Directory -Force -Path $unpack | Out-Null
  $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $entries = $z.Entries; $total = $entries.Count; $i = 0; $last = -1
    foreach ($e in $entries) {
      $target = Join-Path $unpack $e.FullName
      if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
      else {
        $dir = Split-Path $target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
      }
      $i++; $pct = [int](100 * $i / $total)
      if ($pct -ne $last) { Write-Host ("`r  [4/6] unpacking... {0,3}%" -f $pct) -NoNewline; $last = $pct }
    }
  } finally { $z.Dispose() }
  Done
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  $fresh = (Get-ChildItem $unpack -Directory | Select-Object -First 1).FullName
  if (-not $fresh) { throw 'the archive is empty' }

  Step 5 'installing...'
  Retry 'could not move the current version aside' { if (Test-Path $old) { Remove-Item $old -Recurse -Force }; Move-Item $Install $old }
  Retry 'could not put the new version in place'   { Move-Item $fresh $Install }
  Done

  Step 6 "starting ExecAI Studio $Version..."
  if ($Folder) { Start-Process -FilePath $exe -ArgumentList "`"$Folder`"" -WorkingDirectory $Install }
  else { Start-Process -FilePath $exe -WorkingDirectory $Install }
  Done
  Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
} catch {
  Write-Host ''
  Write-Host "  update failed: $($_.Exception.Message)" -ForegroundColor Red
  if (-not (Test-Path $Install) -and (Test-Path $old)) {
    Move-Item $old $Install
    Write-Host '  the previous version was restored.' -ForegroundColor Yellow
  }
  Write-Host ''
  Write-Host '  press Enter to close'
  [void](Read-Host)
}
