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
# Our own working directory must not be inside the install: the editor starts
# us from there, and a folder that is somebody's cwd cannot be moved.
Set-Location $env:TEMP
# GitHub needs TLS 1.2; Windows PowerShell 5.1 on older systems does not enable it.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$Host.UI.RawUI.WindowTitle = "ExecAI Studio - updating to $Version"

$Repo   = 'execai/execai-studio'
$Mirror = 'https://storage.yandexcloud.net/execai-agent-prod/execai-studio/stable'
$file   = "ExecAI-Studio-win32-x64-$Version.zip"
$parent = Split-Path $Install
$leaf   = Split-Path $Install -Leaf
$staging = Join-Path $parent "$leaf.staging-$Version"
$old     = "$Install.old"
$exe     = Join-Path $Install 'ExecAI Studio.exe'

function Get-Holders {
  # Anything that runs from inside the install: the editor and its helpers,
  # the bundled agent (execai.exe) — by path when readable, by name otherwise.
  Get-Process | Where-Object {
    $p = $null; try { $p = $_.Path } catch {}
    ($p -and $p.StartsWith($Install, [StringComparison]::OrdinalIgnoreCase)) -or
    (-not $p -and ($_.ProcessName -eq 'ExecAI Studio' -or $_.ProcessName -eq 'execai'))
  }
}
function Step($n, $t) { Write-Host ("  [{0}/6] {1}" -f $n, $t) -NoNewline }
function Done { Write-Host ' done' -ForegroundColor Green }
function Retry($what, $act) {
  # Defender / indexers hold freshly written files for a moment: keep trying;
  # a process that re-appeared inside the install is closed on the way.
  $deadline = (Get-Date).AddSeconds(90); $n = 0
  while ($true) {
    try { & $act; return } catch {
      $n++
      if ((Get-Date) -gt $deadline) { throw "$what : $($_.Exception.Message)" }
      if ($n -eq 1) { Write-Host ''; Write-Host '        (files still in use, retrying...)' -ForegroundColor DarkGray }
      $h = @(Get-Holders)
      if ($h.Count -gt 0) {
        Write-Host ("        closing: {0}" -f (($h | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', ')) -ForegroundColor DarkGray
        $h | ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {} }
      }
      Start-Sleep -Seconds 2
    }
  }
}
function Get-WithProgress([string]$url, [string]$out, [string]$label) {
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

# The updater itself may be fixed in the release being installed. Unless this
# copy is already that fresh one, fetch updater.ps1 from the target release
# and hand over to it; on any failure keep going with this copy.
if (-not $env:EXECAI_UPDATER_FRESH) {
  try {
    $self = Join-Path $env:TEMP "execai-studio-updater-$Version.ps1"
    $src = "https://raw.githubusercontent.com/$Repo/v$Version/updater/updater.ps1"
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 $src -OutFile $self }
    catch { Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 "$Mirror/updater.ps1" -OutFile $self }
    if ((Get-Item $self).Length -gt 1000) {
      $env:EXECAI_UPDATER_FRESH = '1'
      $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $self, '-Version', $Version, '-Install', $Install)
      if ($Folder) { $argv += @('-Folder', $Folder) }
      & powershell.exe @argv
      exit $LASTEXITCODE
    }
  } catch { }
}

Write-Host ''
Write-Host "  ExecAI Studio update $Version" -ForegroundColor Cyan
Write-Host '  ------------------------------'
try {
  Step 1 'waiting for ExecAI Studio to close...'
  $deadline = (Get-Date).AddMinutes(3)
  while ((Get-Date) -lt $deadline) {
    $running = @(Get-Holders)
    if ($running.Count -eq 0) { break }
    Start-Sleep -Milliseconds 500
  }
  $left = @(Get-Holders)
  if ($left.Count -gt 0) {
    # The editor did not go away by itself (a stuck helper, an agent still
    # serving) — end what is left so the swap can proceed; say so.
    Write-Host ''
    Write-Host ("        still running: {0} - closing" -f (($left | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', ')) -ForegroundColor DarkGray
    $left | ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Seconds 2
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
  # .Content of an octet-stream response is a byte[] in Windows PowerShell 5.1
  # (the mirror serves SHA256SUMS that way) — decode it as text explicitly.
  function Get-Text([string]$u) {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 $u
    if ($r.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($r.Content) }
    return [string]$r.Content
  }
  $sums = $null
  try { $sums = Get-Text "https://github.com/$Repo/releases/download/v$Version/SHA256SUMS" } catch {}
  if (-not $sums) { $sums = Get-Text "$Mirror/SHA256SUMS" }
  $line = ($sums -split "[`r`n]+") | Where-Object { $_.Trim().EndsWith($file) } | Select-Object -First 1
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
