# BgRefresh.ps1 v7 - asks the running PCL (PCL2 or PCL CE) to pick a fresh
# random background.  PCL exposes no event, switch or command line for
# refreshing the background, so the only complete way is to drive its own
# settings page:
#   设置 -> 个性化 -> 刷新背景图片 / 刷新背景内容 -> back to 启动
# PCL2 names the button 刷新背景图片 and logs 加载背景图片; PCL CE names it
# 刷新背景内容 and logs 加载背景内容, so both are handled here.
# Every click is a real mouse click on a UI Automation element rectangle.
# All steps are guarded: if the window is not in the foreground or an element
# cannot be found within the polling window, the script stops and leaves the
# user inside the settings page where the native button is one click away.
# A short trail is appended to CustomTools.log next to this file.
# -DryRun only lists the candidate elements (no focus, no clicks) and is
# meant for checking that the UI text is where the script expects it.
param(
    [string]$Base,
    [switch]$DryRun
)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Base) { $Base = $PSScriptRoot }
if (-not $Base) { exit 1 }
if (-not $Base.EndsWith('\')) { $Base = $Base + '\' }

$script:logPath = $Base + 'CustomTools.log'

function Log([string]$s) {
    $line = '[' + (Get-Date).ToString('yy/MM/dd HH:mm:ss') + '] bg: ' + $s + "`r`n"
    try { [IO.File]::AppendAllText($script:logPath, $line, [Text.UTF8Encoding]::new($true)) } catch { }
}

try {
    $fi = Get-Item -LiteralPath $script:logPath
    if ($fi.Length -gt 60000) {
        $t = [IO.File]::ReadAllText($script:logPath)
        [IO.File]::WriteAllText($script:logPath, $t.Substring($t.Length - 40000), [Text.UTF8Encoding]::new($true))
    }
} catch { }

# PCL CE keeps one log per launcher run, PCL2 keeps Log1.txt.  CE file names
# carry the launch time, so sort by that stamp (not just LastWriteTime, which
# a copy/touch can reorder).
function Get-LauncherLogPath {
    if (Test-Path -LiteralPath ($Base + 'config.v1.yml')) {
        $dir = $Base + 'Log'
        if (Test-Path -LiteralPath $dir) {
            $list = @()
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'Launch-*.log' -File -ErrorAction SilentlyContinue)) {
                $stamp = $f.LastWriteTime
                $m = [regex]::Match($f.Name, '^Launch-(\d{4})-(\d{1,2})-(\d{1,2})-(\d{9})\.log$')
                if ($m.Success) {
                    try {
                        $digits = $m.Groups[4].Value
                        $stamp = New-Object DateTime([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$digits.Substring(0, 2), [int]$digits.Substring(2, 2), [int]$digits.Substring(4, 2), [int]$digits.Substring(6, 3))
                    } catch { }
                }
                $list += [pscustomobject]@{ File = $f; Stamp = $stamp }
            }
            $sorted = @($list | Sort-Object Stamp -Descending)
            if ($sorted.Count -gt 0) { return $sorted[0].File.FullName }
        }
    }
    return ($Base + 'Log1.txt')
}

# Read only the part appended after $Offset.  A different (newer) log file is
# read from its beginning, so a rotation cannot hide the verification line.
function Read-LogPart([string]$path, [int64]$offset) {
    if (-not $path) { return '' }
    try {
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            if ($offset -lt 0 -or $offset -gt $fs.Length) { $offset = 0 }
            if ($fs.Length -le $offset) { return '' }
            $fs.Position = $offset
            $len = [int]($fs.Length - $offset)
            if ($len -gt 2097152) { $fs.Position = $fs.Length - 2097152; $len = 2097152 }
            $buf = New-Object byte[] $len
            $read = $fs.Read($buf, 0, $len)
            return [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        } finally { $fs.Close() }
    } catch { return '' }
}

$sig = 'using System;using System.Runtime.InteropServices;public static class CustomHomeMouse{[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);public static void Click(int x,int y){SetCursorPos(x,y);System.Threading.Thread.Sleep(70);mouse_event(2,0,0,0,UIntPtr.Zero);System.Threading.Thread.Sleep(50);mouse_event(4,0,0,0,UIntPtr.Zero);}}'
Add-Type -TypeDefinition $sig
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$pcl = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(PCL|Plain Craft Launcher)' -and $_.MainWindowHandle.ToInt64() -ne 0 })[0]
if (-not $pcl) { Log 'no PCL window, abort'; exit 1 }
$script:hwnd = [int64]$pcl.MainWindowHandle.ToInt64()

$root = [Windows.Automation.AutomationElement]::RootElement
$cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $pcl.Id)
$script:win = $root.FindFirst([Windows.Automation.TreeScope]::Children, $cond)
if (-not $script:win) { $script:win = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond) }
if (-not $script:win) { Log 'PCL window element not found, abort'; exit 1 }

$script:trueCond = [Windows.Automation.Condition]::TrueCondition

function Get-Hits([string]$name) {
    $res = @()
    $all = $script:win.FindAll([Windows.Automation.TreeScope]::Descendants, $script:trueCond)
    foreach ($e in $all) {
        $c = $e.Current
        if ($c.Name -eq $name) {
            $r = $c.BoundingRectangle
            if ([double]$r.Width -gt 1 -and [double]$r.Height -gt 1) {
                $res += @{ X = [double]$r.X; Y = [double]$r.Y; W = [double]$r.Width; H = [double]$r.Height; Off = [bool]$c.IsOffscreen }
            }
        }
    }
    return $res
}

function Get-NavHits([string]$name) {
    $wr = $script:win.Current.BoundingRectangle
    $lim = [double]$wr.X + 175
    $res = @()
    foreach ($h in @(Get-Hits $name)) {
        if (-not $h.Off -and $h.X -ge [double]$wr.X -and $h.X -lt $lim) { $res += $h }
    }
    return $res
}

function Click-Hit($h) {
    $x = [int]($h.X + $h.W / 2)
    $y = [int]($h.Y + $h.H / 2)
    [CustomHomeMouse]::Click($x, $y)
    return 'clicked @' + [string]$x + ',' + [string]$y
}

function Focus-Pcl {
    if ([CustomHomeMouse]::GetForegroundWindow().ToInt64() -eq $script:hwnd) { return $true }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.AppActivate($pcl.Id) | Out-Null
    } catch { }
    Start-Sleep -Milliseconds 400
    return ([CustomHomeMouse]::GetForegroundWindow().ToInt64() -eq $script:hwnd)
}

# ==== dry run: list what the script sees, click nothing ====
if ($DryRun) {
    $wr = $script:win.Current.BoundingRectangle
    Log ('dry window ' + [string][int]$wr.X + ',' + [string][int]$wr.Y + ' ' + [string][int]$wr.Width + 'x' + [string][int]$wr.Height)
    foreach ($nm in @('设置', '启动', '下载', '个性化', '刷新背景图片', '刷新背景内容', '启动器', '游戏', '其他', '联机', '更多')) {
        $hits = @(Get-Hits $nm)
        Log ('dry ' + $nm + ' hits=' + [string]$hits.Count)
        foreach ($h in $hits) {
            Log ('  @' + [string][int]$h.X + ',' + [string][int]$h.Y + ' ' + [string][int]$h.W + 'x' + [string][int]$h.H + ' off=' + [string]$h.Off)
        }
    }
    exit 0
}

# ==== real run ====
$old = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    $old = [System.Windows.Forms.Cursor]::Position
} catch { }

if (-not (Focus-Pcl)) { Log 'cannot bring PCL to the foreground, abort'; exit 1 }

# step 1: main navigation 设置
$done = $false
for ($i = 0; $i -lt 12 -and -not $done; $i++) {
    $hits = @(Get-NavHits '设置')
    if ($hits.Count -gt 0) { Log ('step1 ' + (Click-Hit $hits[0])); $done = $true } else { Start-Sleep -Milliseconds 350 }
}
if (-not $done) { Log 'step1: nav 设置 not found, nothing clicked'; exit 2 }
Start-Sleep -Milliseconds 500

# step 2: settings sub navigation 个性化 (left column of the settings page)
$done = $false
for ($i = 0; $i -lt 14 -and -not $done; $i++) {
    $wr = $script:win.Current.BoundingRectangle
    $lim = [double]$wr.X + 350
    $hits = @()
    foreach ($h in @(Get-Hits '个性化')) { if (-not $h.Off -and $h.X -lt $lim) { $hits += $h } }
    if ($hits.Count -gt 0) { Log ('step2 ' + (Click-Hit $hits[0])); $done = $true } else { Start-Sleep -Milliseconds 350 }
}
if (-not $done) { Log 'step2: 个性化 tab not found, user can pick it manually'; exit 3 }
Start-Sleep -Milliseconds 500

# remember the log position so the verification below only reads new lines
$logBefore = Get-LauncherLogPath
$lenBefore = [int64]0
try { $lenBefore = (Get-Item -LiteralPath $logBefore).Length } catch { }

# step 3: the native refresh button (PCL2: 刷新背景图片, PCL CE: 刷新背景内容)
$done = $false
for ($i = 0; $i -lt 14 -and -not $done; $i++) {
    foreach ($name in @('刷新背景图片', '刷新背景内容')) {
        $hits = @(Get-Hits $name)
        if ($hits.Count -gt 0) { Log ('step3 ' + (Click-Hit $hits[0]) + ' (' + $name + ')'); $done = $true; break }
    }
    if (-not $done) { Start-Sleep -Milliseconds 350 }
}
if (-not $done) { Log 'step3: refresh background button not found, user is on 个性化, click it manually'; exit 4 }
Start-Sleep -Milliseconds 800

try {
    $logAfter = Get-LauncherLogPath
    $offset = $lenBefore
    if ($logAfter -ne $logBefore) { $offset = 0 }
    $tail = Read-LogPart $logAfter $offset
    if ($tail.Contains('加载背景内容') -or $tail.Contains('加载背景图片')) {
        Log 'verified: PCL logged a new background'
    } elseif ($tail) {
        Log 'note: no background line in the new launcher log yet'
    } else {
        Log 'note: launcher log did not grow after the click'
    }
} catch { }

# step 4: back to the launch page
$done = $false
for ($i = 0; $i -lt 12 -and -not $done; $i++) {
    $hits = @(Get-NavHits '启动')
    if ($hits.Count -gt 0) { Log ('step4 ' + (Click-Hit $hits[0])); $done = $true } else { Start-Sleep -Milliseconds 350 }
}
if (-not $done) { Log 'step4: nav 启动 not found, user can navigate manually' }

if ($old) { try { [System.Windows.Forms.Cursor]::Position = $old } catch { } }
Log 'done'
exit 0
