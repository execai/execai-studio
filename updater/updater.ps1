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


# Who holds files under $dir — the Restart Manager API answers that for any
# process, not only the ones we can read the path of. Used to name and close
# the culprit instead of retrying blind.
$rmSrc = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class RM {
  [StructLayout(LayoutKind.Sequential)] struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
    public int ApplicationType; public uint AppStatus; public uint TSSessionId; [MarshalAs(UnmanagedType.Bool)] public bool bRestartable; }
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
  [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint pSessionHandle);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, IntPtr rgApplications, uint nServices, string[] rgsServiceNames);
  [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
  public static List<int> Holders(string[] files) {
    var result = new List<int>(); uint h; string key = Guid.NewGuid().ToString();
    if (RmStartSession(out h, 0, key) != 0) return result;
    try {
      if (RmRegisterResources(h, (uint)files.Length, files, 0, IntPtr.Zero, 0, null) != 0) return result;
      uint needed = 0, n = 0, reasons = 0;
      int r = RmGetList(h, out needed, ref n, null, ref reasons);
      if (r == 234 /*ERROR_MORE_DATA*/) {
        var arr = new RM_PROCESS_INFO[needed]; n = needed;
        if (RmGetList(h, out needed, ref n, arr, ref reasons) == 0) for (int i = 0; i < n; i++) result.Add(arr[i].Process.dwProcessId);
      }
    } finally { RmEndSession(h); }
    return result;
  }
}
'@
try { Add-Type -TypeDefinition $rmSrc -ErrorAction Stop } catch {}
function Get-FileHolders([string]$dir) {
  # Register every file in the tree (Restart Manager wants file paths, not a folder).
  $files = @(Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  if ($files.Count -eq 0) { return @() }
  $pids = @()
  # RmRegisterResources has a limit per call; chunk it.
  for ($i = 0; $i -lt $files.Count; $i += 4000) {
    $chunk = $files[$i..([Math]::Min($i + 3999, $files.Count - 1))]
    try { $pids += [RM]::Holders([string[]]$chunk) } catch {}
  }
  $pids = $pids | Select-Object -Unique | Where-Object { $_ -ne $PID }
  foreach ($id in $pids) { try { Get-Process -Id $id -ErrorAction Stop } catch {} }
}

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
      $h = @(Get-Holders) + @(Get-FileHolders $Install)
      $h = $h | Sort-Object Id -Unique
      if ($h.Count -gt 0) {
        Write-Host ("        in use by: {0} - closing" -f (($h | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', ')) -ForegroundColor DarkGray
        $h | ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {} }
      } elseif ($n -eq 2) {
        Write-Host '        (no process found holding the folder - likely antivirus/indexer; waiting)' -ForegroundColor DarkGray
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
  $swapped = $false
  try {
    Retry 'could not move the current version aside' { if (Test-Path $old) { Remove-Item $old -Recurse -Force }; Move-Item $Install $old }
    Retry 'could not put the new version in place'   { Move-Item $fresh $Install }
    $swapped = $true
  } catch {
    # Plan B: the folder as a whole will not move (something outside our
    # reach holds one file) — copy the new tree over the old one in place.
    # robocopy /MIR updates everything it can and reports what it could not.
    Write-Host ''
    Write-Host '        folder swap blocked - installing file by file' -ForegroundColor DarkGray
    if ((Test-Path $old) -and -not (Test-Path $Install)) { Move-Item $old $Install }
    $rc = (Start-Process robocopy -ArgumentList @("`"$fresh`"", "`"$Install`"", '/MIR', '/R:15', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Wait -PassThru -NoNewWindow).ExitCode
    if ($rc -ge 8) { throw "file-by-file install failed (robocopy $rc)" }
    $swapped = $true
  }
  if (-not $swapped) { throw 'could not install' }
  Done

  Step 6 "starting ExecAI Studio $Version..."
  if (-not (Test-Path $exe)) { throw "the new build has no 'ExecAI Studio.exe' at $Install" }
  # Launch the way a double-click does: Explorer starts the program detached
  # from this console (no job, no quoting games). The editor restores its last
  # workspace itself; a folder argument is passed only when the shell allows.
  function Start-Studio {
    try {
      if ($Folder) { Start-Process -FilePath $exe -ArgumentList ('"' + $Folder + '"') -WorkingDirectory $env:TEMP -ErrorAction Stop | Out-Null }
      else { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $exe + '"') -ErrorAction Stop | Out-Null }
    } catch { Write-Host ("        start error: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray }
  }
  function Studio-Up {
    # Any process running from inside the install counts — do not depend on
    # what Windows calls the process.
    $ps = @(Get-Process | Where-Object { $p = $null; try { $p = $_.Path } catch {}; $p -and $p.StartsWith($Install, [StringComparison]::OrdinalIgnoreCase) })
    if ($ps.Count -gt 0) { return $true }
    return [bool](Get-Process -Name 'ExecAI Studio' -ErrorAction SilentlyContinue)
  }
  Start-Studio
  $up = $false; $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700
    if (Studio-Up) { $up = $true; break }
  }
  if (-not $up) {
    Write-Host ''
    Write-Host '  ExecAI Studio did not start on its own - starting it once more (via Explorer)' -ForegroundColor Yellow
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $exe + '"') | Out-Null
    Start-Sleep -Seconds 10
    $up = Studio-Up
  }
  if (-not $up) {
    # The update itself succeeded — only the launch did not. Say so plainly
    # instead of claiming a failed update and rolling a good install back.
    $names = (Get-Process | Where-Object { $_.ProcessName -like '*xec*' -or $_.ProcessName -like '*tudio*' } | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '
    Write-Host ''
    Write-Host "  ExecAI Studio $Version is installed, but it did not start automatically." -ForegroundColor Yellow
    if ($names) { Write-Host "  (running now: $names)" -ForegroundColor DarkGray }
    Write-Host "  Start it from the Start menu, or here: $exe"
    Write-Host ''
    Write-Host '  press Enter to close'
    [void](Read-Host)
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
  }
  Done
  Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
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
