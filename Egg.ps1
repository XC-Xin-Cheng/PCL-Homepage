# Egg.ps1 v4 - easter egg of the custom homepage.
# Press Shift+X+C while the PCL window is focused: the background watcher
# (RefreshLog.ps1 -Watch) opens a blank cmd window running this script.
# Type Yes + Enter and the theme picture (Pictures\CustomHomeBG.jpg) becomes
# the Windows desktop wallpaper, while the lock screen gets the matching
# still (Pictures\CustomHomeLock.png).  The video wallpaper experiment is
# gone for good: recent Explorer builds have no background layer to park a
# player window on, so a plain wallpaper is what actually shows up.
# While all this happens the window maximizes itself and a plain progress
# bar runs with no text; it closes on its own ten seconds after the job is
# done.  When the wallpaper cannot be set, the line under the bar reads:
# 可惜了
# Type No + Enter: nothing is changed, the window just closes.
#
# Sandbox switches (used by the sandbox test, never in normal use):
#   PCLTOOLS_EGG_MOCK=ok|fail  same flow, but nothing real is touched
#   PCLTOOLS_EGG_WAIT=<ms>     override the 10 second close delay
#
# This file is embedded inside an XML comment of Custom.xaml: never write
# two consecutive hyphens or the word that declares XML namespaces in it.
$ErrorActionPreference = 'SilentlyContinue'

$script:Base = $PSScriptRoot
if (-not $script:Base) { try { $script:Base = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { } }
if (-not $script:Base) { exit 1 }
$script:Base = $script:Base.TrimEnd('\') + '\'
$script:wallJpg = $script:Base + 'Pictures\CustomHomeBG.jpg'
$script:lockImg = $script:Base + 'Pictures\CustomHomeLock.png'
$script:log     = $script:Base + 'CustomTools.log'
$script:mock    = [string]$env:PCLTOOLS_EGG_MOCK
$script:wait    = 10000
try { if ($env:PCLTOOLS_EGG_WAIT) { $script:wait = [int]$env:PCLTOOLS_EGG_WAIT } } catch { }
$script:redirected = $true
try { $script:redirected = [bool][Console]::IsOutputRedirected } catch { }

function ELog([string]$s) {
    try { [IO.File]::AppendAllText($script:log, ('[' + (Get-Date).ToString('yy/MM/dd HH:mm:ss') + '] egg: ' + $s + "`r`n"), [Text.UTF8Encoding]::new($true)) } catch { }
}

function Add-EggNative {
    if (-not ('EggNative' -as [type])) {
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class EggNative{[DllImport("kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);[DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr h);[DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool SystemParametersInfo(int a,int b,string c,int d);}'
    }
}

function Show-BarFrame([int]$pct, [int]$width, [int]$x, [int]$y) {
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $fill = [int][Math]::Round($width * $pct / 100.0)
    if ($script:redirected) {
        Write-Output ('#' + $pct.ToString('000') + ' ' + ('=' * $fill) + ('.' * ($width - $fill)))
        return
    }
    try { [Console]::SetCursorPosition($x, $y) } catch { }
    try { [Console]::ForegroundColor = 'Green' } catch { }
    try { [Console]::Write(('#' * $fill)) } catch { }
    try { [Console]::ForegroundColor = 'DarkGray' } catch { }
    try { [Console]::Write(('-' * ($width - $fill))) } catch { }
    try { [Console]::ResetColor() } catch { }
}

# Desktop wallpaper through the shell API; the picture fills the screen.
function Set-DesktopWallpaper([string]$imgPath) {
    try {
        if (-not [IO.File]::Exists($imgPath)) { return $false }
        Add-EggNative
        try {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Force
        } catch { }
        $r = [EggNative]::SystemParametersInfo(20, 0, $imgPath, 3)
        ELog ('wallpaper: ' + [string]$r)
        return $r
    } catch {
        ELog ('wallpaper failed: ' + [string]$_.Exception.Message)
        return $false
    }
}

# Lock screen picture (Windows gives no video option there).
function Set-LockPicture([string]$imgPath) {
    try {
        if (-not [IO.File]::Exists($imgPath)) { return $false }
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $ext = [System.WindowsRuntimeSystemExtensions].GetMethods()
        $asOp = @($ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $asAct = @($ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
        if (-not $asOp -or -not $asAct) { return $false }
        $sfT = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]::GetFileFromPathAsync($imgPath)
        $nt = $asOp.MakeGenericMethod([Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]).Invoke($null, @($sfT))
        $nt.Wait(-1) | Out-Null
        $act = [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]::SetImageFileAsync($nt.Result)
        $nt2 = $asAct.Invoke($null, @($act))
        $nt2.Wait(-1) | Out-Null
        return $true
    } catch {
        ELog ('lock screen failed: ' + [string]$_.Exception.Message)
        return $false
    }
}

# ==== main ====
try { [Console]::Title = 'C:\Windows\system32\cmd.exe' } catch { }
# Make sure the window really shows up in front even when the watcher that
# started it lives in the background.
if (-not $script:redirected) {
    try {
        Add-EggNative
        $ch0 = [EggNative]::GetConsoleWindow()
        if ($ch0.ToInt64() -ne 0) {
            [void][EggNative]::ShowWindow($ch0, 9)
            [void][EggNative]::BringWindowToTop($ch0)
            [void][EggNative]::SetForegroundWindow($ch0)
        }
    } catch { }
}

$ans = $null
try { $ans = [Console]::ReadLine() } catch { }
while ($null -ne $ans) {
    $t = ([string]$ans).Trim()
    if ($t -ieq 'yes') { break }
    if ($t -ieq 'no') {
        ELog 'declined'
        exit 0
    }
    try { $ans = [Console]::ReadLine() } catch { $ans = $null }
}
if ($null -eq $ans) { exit 0 }
ELog 'accepted'

if (-not $script:redirected) {
    try {
        Add-EggNative
        $ch = [EggNative]::GetConsoleWindow()
        if ($ch.ToInt64() -ne 0) { [void][EggNative]::ShowWindow($ch, 3) }
    } catch { }
    Start-Sleep -Milliseconds 300
    try { [Console]::Clear() } catch { }
}

$winW = 80; $winH = 25
try { $winW = [Console]::WindowWidth } catch { }
try { $winH = [Console]::WindowHeight } catch { }
$barW = [int][Math]::Min(80, [Math]::Max(20, $winW - 16))
$barX = [int][Math]::Floor(($winW - $barW) / 2)
$barY = [int][Math]::Floor($winH / 2)
if (-not $script:redirected) { try { [Console]::CursorVisible = $false } catch { } }

foreach ($p in @(0, 6, 12, 18, 24, 30)) { Show-BarFrame $p $barW $barX $barY; Start-Sleep -Milliseconds 60 }

$ok = $false
if ($script:mock) {
    ELog ('mock: ' + $script:mock)
    for ($p = 36; $p -le 66; $p += 10) { Show-BarFrame $p $barW $barX $barY; Start-Sleep -Milliseconds 40 }
    $ok = ($script:mock -eq 'ok')
} else {
    $wall = $script:wallJpg
    if (-not [IO.File]::Exists($wall)) { $wall = $script:lockImg }
    if (-not [IO.File]::Exists($wall)) {
        ELog 'no wallpaper image found'
    } else {
        ELog ('wallpaper image: ' + $wall)
        Show-BarFrame 40 $barW $barX $barY
        $ok = Set-DesktopWallpaper $wall
        $lockOk = Set-LockPicture $script:lockImg
        ELog ('lock screen: ' + [string]$lockOk)
    }
}
ELog ('result: ' + [string]$ok)

if ($ok) {
    for ($p = 75; $p -le 100; $p += 5) { Show-BarFrame $p $barW $barX $barY; Start-Sleep -Milliseconds 70 }
} else {
    if ($script:redirected) { Write-Output '可惜了' }
    else {
        try { [Console]::SetCursorPosition($barX, $barY + 1) } catch { }
        try { [Console]::ForegroundColor = 'Red' } catch { }
        try { [Console]::Write('可惜了') } catch { }
        try { [Console]::ResetColor() } catch { }
    }
}

if (-not $script:redirected) { try { [Console]::CursorVisible = $true } catch { } }
Start-Sleep -Milliseconds $script:wait
exit 0