# VideoWall.ps1 - plays a video file as the desktop wallpaper.
# The player window is placed into the desktop's background host window
# (WorkerW), so icons, windows and the taskbar stay above it and the video
# just loops behind them. Nothing is installed and no driver is needed.
# Modes:
#   (default)  -Video <file>   start the wallpaper player, replacing one
#                              that may already be running
#   -AutoStart                 like -Video, but takes the video path from
#                              VideoWall\on.flag (written when the egg
#                              turned the wallpaper on); silent without it
#   -Stop                      stop the running wallpaper player and
#                              forget the saved video (deletes the flag)
#   -Probe                     open the video in an offscreen window and
#                              report what works; never touches the desktop
# The player writes VideoWall.ready ("ok" or "fail") so callers can wait
# for the result. Diagnostics go to CustomTools.log.
# This file is embedded inside an XML comment of Custom.xaml, so it must
# not contain two consecutive hyphens or the word that declares XML
# namespaces.
param(
    [string]$Video,
    [switch]$Stop,
    [switch]$Probe,
    [switch]$AutoStart
)
$ErrorActionPreference = 'SilentlyContinue'
$script:Base = $PSScriptRoot
if (-not $script:Base) { try { $script:Base = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { } }
if (-not $script:Base) { exit 1 }
$script:Base = $script:Base.TrimEnd('\') + '\'
$script:log = $script:Base + 'CustomTools.log'
$script:ready = $script:Base + 'VideoWall.ready'

function VLog([string]$s) {
    if ($env:PCLTOOLS_NO_LOG) { return }
    try { [IO.File]::AppendAllText($script:log, ('[' + (Get-Date).ToString('yy/MM/dd HH:mm:ss') + '] videowall: ' + $s + "`r`n"), [Text.UTF8Encoding]::new($true)) } catch { }
}

function Write-Ready([string]$s) {
    try { [IO.File]::WriteAllText($script:ready, $s, [Text.UTF8Encoding]::new($false)) } catch { }
}

function Add-VwNative {
    if ('VideoWallNative' -as [type]) { return }
    $cs = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class VideoWallNative {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
'@
    Add-Type -TypeDefinition $cs
}

# Ask Explorer for the wallpaper host layer, then locate it. The host is a
# WorkerW window that sits directly behind the icon view.
function Find-WallpaperHost {
    $nullStr = [NullString]::Value
    $progman = [VideoWallNative]::FindWindow('Progman', $nullStr)
    if ($progman -ne [IntPtr]::Zero) {
        $res = [IntPtr]::Zero
        [void][VideoWallNative]::SendMessageTimeout($progman, 0x052C, [IntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$res)
        Start-Sleep -Milliseconds 300
    }
    $script:defview = [IntPtr]::Zero
    $cb = [VideoWallNative+EnumProc]{
        param($h, $l)
        $sb = New-Object System.Text.StringBuilder 64
        [void][VideoWallNative]::GetClassName($h, $sb, 64)
        if ($sb.ToString() -eq 'WorkerW') {
            if ([VideoWallNative]::FindWindowEx($h, [IntPtr]::Zero, 'SHELLDLL_DefView', [NullString]::Value) -ne [IntPtr]::Zero) { $script:defview = $h }
        }
        return $true
    }
    [void][VideoWallNative]::EnumWindows($cb, [IntPtr]::Zero)
    if ($script:defview -ne [IntPtr]::Zero) {
        $hostW = [VideoWallNative]::FindWindowEx([IntPtr]::Zero, $script:defview, 'WorkerW', [NullString]::Value)
        if ($hostW -ne [IntPtr]::Zero) { return $hostW }
    }
    return $progman
}

function Get-OtherPlayers {
    $me = $PID
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains('VideoWall.ps1') -and -not $_.CommandLine.Contains('-Stop') -and -not $_.CommandLine.Contains('-Probe') -and $_.ProcessId -ne $me
    })
}

function Stop-Players {
    $n = 0
    foreach ($p in (Get-OtherPlayers)) {
        try { Stop-Process -Id $p.ProcessId -Force; $n++ } catch { }
    }
    return $n
}

# ==== player ====
function Start-Player {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Add-VwNative
    if (-not $Video) { VLog 'no video path'; Write-Ready 'fail'; return 1 }
    if (-not [IO.File]::Exists($Video)) { VLog ('video missing: ' + $Video); Write-Ready 'fail'; return 1 }
    $n = Stop-Players
    if ($n -gt 0) { VLog ('replaced ' + $n + ' old player(s)') }
    $hostW = Find-WallpaperHost
    $fallback = $false
    if ($hostW -eq [IntPtr]::Zero) { VLog 'no wallpaper host found'; Write-Ready 'fail'; return 1 }
    if ($hostW -eq [VideoWallNative]::FindWindow('Progman', [NullString]::Value)) { $fallback = $true }
    $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.ResizeMode = 'NoResize'
    $w.ShowInTaskbar = $false
    $w.ShowActivated = $false
    $w.WindowStartupLocation = 'Manual'
    $w.Left = -12000
    $w.Top = -12000
    $w.Width = 960
    $w.Height = 540
    $w.Background = [System.Windows.Media.Brushes]::Black
    $script:me = New-Object System.Windows.Controls.MediaElement
    $script:me.LoadedBehavior = 'Manual'
    $script:me.UnloadedBehavior = 'Manual'
    $script:me.Volume = 0
    $script:me.Stretch = 'UniformToFill'
    $script:failed = $false
    $script:me.add_MediaFailed({ $script:failed = $true; VLog 'media failed while playing'; Write-Ready 'fail' })
    $script:me.add_MediaEnded({ try { $script:me.Position = [TimeSpan]::Zero; $script:me.Play() } catch { } })
    $w.Content = $script:me
    $w.Show()
    $script:me.Source = New-Object System.Uri($Video)
    $script:me.Play()
    $open = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        try { $w.Dispatcher.Invoke([Action]{}, 'Background') } catch { }
        if ($script:me.NaturalVideoWidth -gt 0) { $open = $true; break }
        if ($script:failed) { break }
    }
    if (-not $open) {
        VLog 'media did not open'
        Write-Ready 'fail'
        $w.Close()
        return 1
    }
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle
    [void][VideoWallNative]::SetParent($hwnd, $hostW)
    [void][VideoWallNative]::MoveWindow($hwnd, $scr.Left, $scr.Top, $scr.Width, $scr.Height, $true)
    [void][VideoWallNative]::SetWindowPos($hwnd, [IntPtr]1, 0, 0, 0, 0, 0x0003)
    Write-Ready 'ok'
    VLog ('playing ' + $Video + ' on ' + $scr.Width + 'x' + $scr.Height + ' fallback=' + [string]$fallback)
    [System.Windows.Threading.Dispatcher]::Run()
    return 0
}

# ==== probe (offscreen, never changes the desktop) ====
function Show-Probe {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-VwNative
    $hostW = Find-WallpaperHost
    $progman = [VideoWallNative]::FindWindow('Progman', [NullString]::Value)
    "probe: workerw=" + $hostW.ToString() + " progman=" + $progman.ToString()
    if (-not $Video) { "probe: no video given"; $script:probeCode = 1; return }
    if (-not [IO.File]::Exists($Video)) { "probe: video missing"; $script:probeCode = 1; return }
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.ShowInTaskbar = $false
    $w.ShowActivated = $false
    $w.WindowStartupLocation = 'Manual'
    $w.Left = -12000
    $w.Top = -12000
    $w.Width = 640
    $w.Height = 360
    $script:me = New-Object System.Windows.Controls.MediaElement
    $script:me.LoadedBehavior = 'Manual'
    $script:me.Volume = 0
    $script:failed = $false
    $script:me.add_MediaFailed({ $script:failed = $true })
    $w.Content = $script:me
    $w.Show()
    $script:me.Source = New-Object System.Uri($Video)
    $script:me.Play()
    $open = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        try { $w.Dispatcher.Invoke([Action]{}, 'Background') } catch { }
        if ($script:me.NaturalVideoWidth -gt 0) { $open = $true; break }
        if ($script:failed) { break }
    }
    if ($open) { "probe: media OK " + $script:me.NaturalVideoWidth + "x" + $script:me.NaturalVideoHeight + " " + $script:me.NaturalDuration.TimeSpan.ToString(); $script:probeCode = 0 }
    else { "probe: media FAILED"; $script:probeCode = 1 }
    $w.Close()
}

# ==== main ====
if ($AutoStart) {
    # Coming back from a reboot: only resume when the egg left the flag.
    $saved = ''
    try { $saved = [IO.File]::ReadAllText($script:Base + 'VideoWall\on.flag').Trim() } catch { }
    if (-not $saved) { exit 0 }
    if (-not [IO.File]::Exists($saved)) { VLog ('autostart video missing: ' + $saved); exit 0 }
    $Video = $saved
}
if ($Stop) {
    $n = Stop-Players
    try { [IO.File]::Delete($script:Base + 'VideoWall\on.flag') } catch { }
    VLog ('stop requested, killed ' + $n)
    exit 0
}
if ($Probe) {
    $script:probeCode = 1
    Show-Probe
    exit $script:probeCode
}
$code = Start-Player
exit $code