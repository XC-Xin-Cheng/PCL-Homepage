# RefreshLog.ps1 v10 - rebuilds PCL\LogView.xaml, the log snapshot behind the
# Custom.xaml homepage.  Works with PCL2 (Log1.txt) and PCL CE
# (Log\Launch-*.log).  Modes:
#   (default)     one shot: rebuild the snapshot, then press F5 in PCL.
#   -Watch        background watcher (single instance): keeps the snapshot
#                 fresh, presses F5 when the game starts or stops and when
#                 PCL itself is (re)started, and afterwards every three
#                 seconds while the GAME log keeps growing (only when
#                 the PCL window is in front and showing its home page, so
#                 a refresh never reloads another page the user is using;
#                 the launcher log never triggers a refresh, because page
#                 reloads themselves append to it);
#                 it also registers a logon task
#                 so it comes back after a reboot; while PCL is the focused
#                 window it listens for the Shift+X+C easter egg and then
#                 opens Egg.ps1 without a console window.
#   -OpenGameLog  open the running game log (latest.log) in Notepad.
#   -OpenLauncherLog N  open the N-th newest launcher log in Notepad; when it
#                       does not exist yet, open the launcher log folder.
#   -OpenGameLogDir     open the running game log folder, else the selected
#                       instance's logs folder.
#   -OpenFolder K  open the selected instance folder for game, or its
#                  mods/saves/schematics/logs folder.  Paths with &,
#                  parentheses or non-ASCII text never pass through batch FOR
#                  parsing.
#   -PageProbe    print which main page PCL shows (Launch/Download/Setup/...).
#   -Paths        print VER/MCDIR/INSTDIR/INDIEDIR/ISOLATED/LAUNCHLOG for
#                 CustomTools.bat (values are read from config.v1.yml when
#                 present, otherwise from Setup.ini).
# Snapshot keys (consumed by the homepage):
#   LogViewText     game log of the running Minecraft process ('' when none)
#   LauncherLogText launcher log of the current PCL session
#   LogHist1..3     start time labels for the previous launcher logs
# Offline test switches: PCLTOOLS_NO_REFRESH=1 skips F5, PCLTOOLS_NO_WATCH=1
# makes -Watch exit at once, PCLTOOLS_FAKE_MC=<dir> pretends a game runs,
# PCLTOOLS_NO_MC=1 pretends no game runs at all (the fake one wins),
# PCLTOOLS_OPEN_DRYRUN=1 prints the target path instead of opening it.
param(
    [string]$Base,
    [switch]$Watch,
    [switch]$OpenGameLog,
    [switch]$OpenGameLogDir,
    [switch]$PageProbe,
    [switch]$Paths,
    [string]$OpenFolder = '',
    [int]$OpenLauncherLog = 0
)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Base) { $Base = $PSScriptRoot }
if (-not $Base) { exit 1 }
if (-not $Base.EndsWith('\')) { $Base = $Base + '\' }

$script:outPath = $Base + 'LogView.xaml'
$script:logPath = $Base + 'CustomTools.log'
# The literal game directory flag is assembled from two pieces: this file is
# also embedded inside an XML comment of Custom.xaml, and the raw two hyphen
# sequence must not appear there.
$script:gflag = '-' + '-gameDir'
$script:mcCache = @{}
$script:watchMutexName = 'PCLCustomHomeLogWatcher'

function WLog([string]$s) {
    $line = '[' + (Get-Date).ToString('yy/MM/dd HH:mm:ss') + '] log: ' + $s + "`r`n"
    try { [IO.File]::AppendAllText($script:logPath, $line, [Text.UTF8Encoding]::new($true)) } catch { }
}

# ==== settings and paths ====
# Flat "key: value" reader used for Setup.ini, PCL.ini and config.v1.yml.
# The first matching key wins.  Surrounding quotes are removed.
function Get-ConfigValue([string]$path, [string]$key) {
    if (-not $path -or -not $key) { return '' }
    if (-not [IO.File]::Exists($path)) { return '' }
    try {
        foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
            $m = [regex]::Match($line, '^\s*' + [regex]::Escape($key) + '\s*:\s*(.*)$')
            if (-not $m.Success) { continue }
            $v = $m.Groups[1].Value.Trim()
            if ($v.Length -ge 2) {
                if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
                    $v = $v.Substring(1, $v.Length - 2)
                }
            }
            return $v
        }
    } catch { }
    return ''
}

function Test-ConfigTrue([string]$v) {
    if (-not $v) { return $false }
    return ($v -imatch '^(true|1|yes|on)$')
}

# PCL CE writes one log per launcher run; PCL2 keeps Log1.txt and rotates
# older logs to Log2.txt, Log3.txt and Log4.txt.  CE file names carry the
# launch time (Launch-2026-10-22-221352643.log), so sort by that stamp first;
# copying/touching files must not make an old session look newer.
function Get-CeLogs {
    $dir = $Base + 'Log'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'Launch-*.log' -File -ErrorAction SilentlyContinue)) {
        $stamp = $f.LastWriteTime
        $m = [regex]::Match($f.Name, '^Launch-(\d{4})-(\d{1,2})-(\d{1,2})-(\d{9})\.log$')
        if ($m.Success) {
            try {
                $digits = $m.Groups[4].Value
                $stamp = New-Object DateTime([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$digits.Substring(0, 2), [int]$digits.Substring(2, 2), [int]$digits.Substring(4, 2), [int]$digits.Substring(6, 3))
            } catch { }
        }
        $list.Add([pscustomobject]@{ File = $f; Stamp = $stamp })
    }
    return @($list | Sort-Object Stamp -Descending)
}

function Get-LauncherLogPath {
    if (Test-Path -LiteralPath ($Base + 'config.v1.yml')) {
        $f = @(Get-CeLogs)
        if ($f.Count -gt 0) { return $f[0].File.FullName }
    }
    return ($Base + 'Log1.txt')
}

function Get-LauncherLogPathN([int]$n) {
    if ($n -lt 1) { return '' }
    if (Test-Path -LiteralPath ($Base + 'config.v1.yml')) {
        $f = @(Get-CeLogs)
        if ($f.Count -ge $n) { return $f[$n - 1].File.FullName }
        return ''
    }
    return ($Base + 'Log' + [string]$n + '.txt')
}

function Get-McRoot {
    $yaml = $Base + 'config.v1.yml'
    $ini = $Base + 'Setup.ini'
    $mc = ''
    if (Test-Path -LiteralPath $yaml) { $mc = Get-ConfigValue $yaml 'LaunchFolderSelect' }
    if (-not $mc -and (Test-Path -LiteralPath $ini)) { $mc = Get-ConfigValue $ini 'LaunchFolderSelect' }
    if (-not $mc) { $mc = '$.minecraft\' }
    $root = [IO.Path]::GetDirectoryName($Base.TrimEnd('\'))
    if (-not $root) { $root = $Base.TrimEnd('\') }
    # "$" in PCL settings means the launcher folder (the parent of PCL\);
    # keep the trailing separator so "$.minecraft\." never loses it.
    if (-not $root.EndsWith('\')) { $root = $root + '\' }
    $mc = $mc.Replace('$', $root)
    $mc = [Environment]::ExpandEnvironmentVariables($mc)
    if (-not [IO.Path]::IsPathRooted($mc)) { $mc = Join-Path $root $mc }
    try { $mc = [IO.Path]::GetFullPath($mc) } catch { }
    $mc = $mc.TrimEnd('\')
    if ($mc -match '^[A-Za-z]:$') { $mc = $mc + '\' }
    return $mc
}

function Get-SelectedVersion([string]$mc) {
    $yaml = $Base + 'config.v1.yml'
    $ini = $Base + 'Setup.ini'
    $ver = ''
    if (Test-Path -LiteralPath $yaml) { $ver = Get-ConfigValue $yaml 'LaunchInstanceSelect' }
    if (-not $ver -and (Test-Path -LiteralPath $ini)) { $ver = Get-ConfigValue $ini 'LaunchVersionSelect' }
    if (-not $ver -and $mc) { $ver = Get-ConfigValue (Join-Path $mc 'PCL.ini') 'Version' }
    return $ver
}

function Get-InstanceDir([string]$mc, [string]$ver) {
    if (-not $ver) { return '' }
    if ($ver -match '^[A-Za-z]:' -or $ver.StartsWith('\\')) { return $ver.TrimEnd('\') }
    $rel = $ver.Replace('/', '\')
    return (Join-Path (Join-Path $mc 'versions') $rel)
}

# PCL CE stores the isolation decision in the instance level PCL\config.v1.yml
# (VersionArgumentIndieV2, or the older VersionArgumentIndie).  When there is
# no instance setting, follow the same clues PCL itself uses: mods/saves in
# the instance folder mean isolated, otherwise the global LaunchArgumentIndieV2
# switch decides (0 = never isolated, anything else = isolated).
function Test-InstanceIsolated([string]$mc, [string]$inst, [string]$globalCfg) {
    if (-not $inst) { return $false }
    # PCL CE writes config.v1.yml, PCL2 writes Setup.ini in the instance's
    # own PCL folder; both are valid and must be checked.
    foreach ($name in @('config.v1.yml', 'Setup.ini')) {
        $cfg = Join-Path $inst ('PCL\' + $name)
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        $v2 = Get-ConfigValue $cfg 'VersionArgumentIndieV2'
        if ($v2) { return (Test-ConfigTrue $v2) }
        $v1 = Get-ConfigValue $cfg 'VersionArgumentIndie'
        if ($v1 -match '^-?\d+$') {
            if ([int]$v1 -ge 0) { return ([int]$v1 -eq 1) }
        }
    }
    $mods = Join-Path $inst 'mods'
    if (Test-Path -LiteralPath $mods) {
        if (@(Get-ChildItem -LiteralPath $mods -File -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    $saves = Join-Path $inst 'saves'
    if (Test-Path -LiteralPath $saves) {
        if (@(Get-ChildItem -LiteralPath $saves -Directory -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    foreach ($cfg in @($globalCfg, ($Base + 'Setup.ini'))) {
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        $g = Get-ConfigValue $cfg 'LaunchArgumentIndieV2'
        if ($g -match '^\d+$') { return ([int]$g -ne 0) }
    }
    return $true
}

function Resolve-PclPaths {
    $mc = Get-McRoot
    $ver = Get-SelectedVersion $mc
    $inst = Get-InstanceDir $mc $ver
    $isolated = Test-InstanceIsolated $mc $inst ($Base + 'config.v1.yml')
    $indie = $mc
    if ($isolated -and $inst) { $indie = $inst }
    $iso = '0'
    if ($isolated) { $iso = '1' }
    return [ordered]@{
        'VER'       = $ver
        'MCDIR'     = $mc
        'INSTDIR'   = $inst
        'INDIEDIR'  = $indie
        'ISOLATED'  = $iso
        'LAUNCHLOG' = (Get-LauncherLogPath)
    }
}

# ==== Minecraft process detection (cached per pid; new pids are probed) ====
function Get-McInfo {
    if ($env:PCLTOOLS_FAKE_MC) {
        return @{ Pid = 0; Dir = $env:PCLTOOLS_FAKE_MC; Start = $null }
    }
    if ($env:PCLTOOLS_NO_MC) { return $null }
    $best = $null
    $alive = @{}
    foreach ($p in @(Get-Process -Name java, javaw)) {
        $procId = [int]$p.Id
        $alive[$procId] = $true
        if (-not $script:mcCache.ContainsKey($procId)) {
            $isMc = $false
            $dir = $null
            $start = $null
            try { $start = $p.StartTime } catch { }
            try {
                $ci = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [string]$procId)
                $cl = ''
                if ($ci) { $cl = [string]$ci.CommandLine }
                if ($cl -and ($cl.Contains($script:gflag) -or $cl.Contains('net.minecraft.client.main.Main'))) {
                    $isMc = $true
                    $m = [regex]::Match($cl, [regex]::Escape($script:gflag) + '\s+("([^"]*)"|(\S+))')
                    if ($m.Success) {
                        if ($m.Groups[2].Success) { $dir = $m.Groups[2].Value } else { $dir = $m.Groups[3].Value }
                    }
                }
            } catch { }
            $script:mcCache[$procId] = @{ IsMc = $isMc; Dir = $dir; Start = $start }
        }
        $info = $script:mcCache[$procId]
        if ($info.IsMc) {
            if ($null -eq $best) { $best = @{ Pid = $procId; Dir = $info.Dir; Start = $info.Start } }
            elseif ($null -ne $info.Start -and $null -ne $best.Start -and $info.Start -gt $best.Start) {
                $best = @{ Pid = $procId; Dir = $info.Dir; Start = $info.Start }
            }
        }
    }
    foreach ($k in @($script:mcCache.Keys)) {
        if (-not $alive.ContainsKey($k)) { $script:mcCache.Remove($k) }
    }
    return $best
}

# The automatic F5 must follow the GAME log, not the launcher log: every
# homepage reload writes new lines to the launcher log, so treating that log
# as a trigger would reload the page forever.  Length plus write time is a
# cheap change stamp for the running game's latest.log.
function Get-GameLogStamp($mc) {
    if (-not $mc -or -not $mc.Dir) { return '' }
    try {
        $fi = Get-Item -LiteralPath (Join-Path (Join-Path $mc.Dir 'logs') 'latest.log') -ErrorAction SilentlyContinue
        if (-not $fi) { return '' }
        return ([string]$fi.Length + '|' + [string]$fi.LastWriteTimeUtc.Ticks)
    } catch { return '' }
}

# ==== readers ====
# Log text decoder.  The launcher log is plain UTF-8, but some mods write
# Chinese through the console code page, so a few lines in the game log are
# raw GBK.  Decoding the whole buffer as UTF-8 would show replacement
# characters there; lines that are not valid UTF-8 are decoded as GBK.
function Decode-LogText([byte[]]$buf, [int]$n) {
    if ($n -le 0) { return '' }
    $strict = [Text.UTF8Encoding]::new($false, $true)
    try { return $strict.GetString($buf, 0, $n) } catch { }
    $gbk = [Text.Encoding]::GetEncoding(936)
    $sb = New-Object Text.StringBuilder
    $start = 0
    for ($i = 0; $i -le $n; $i++) {
        if ($i -eq $n -or $buf[$i] -eq 10) {
            $len = $i - $start
            if ($len -gt 0) {
                try { [void]$sb.Append($strict.GetString($buf, $start, $len)) }
                catch { [void]$sb.Append($gbk.GetString($buf, $start, $len)) }
            }
            if ($i -lt $n) { [void]$sb.Append([char]10) }
            $start = $i + 1
        }
    }
    return $sb.ToString()
}

function Read-TailText([string]$path, [int]$cap) {
    $out = ''
    try {
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $len = [int64]$fs.Length
            $start = [int64]0
            if ($len -gt $cap) { $start = $len - $cap }
            $fs.Position = $start
            $buf = New-Object byte[] ([int]($len - $start))
            $read = $fs.Read($buf, 0, $buf.Length)
            $out = Decode-LogText $buf $read
            $out = $out.TrimStart([char]0xFEFF)
            if ($start -gt 0) {
                $i = $out.IndexOf([char]10)
                if ($i -ge 0) { $out = '[日志过长，仅显示最后 ' + [string]$cap + ' 字节]' + "`r`n`r`n" + $out.Substring($i + 1) }
            }
        } finally { $fs.Close() }
    } catch { $out = '' }
    return $out
}

function Get-HistLabel([string]$path) {
    $out = ''
    if (-not $path) { return $out }
    try {
        $fi = Get-Item -LiteralPath $path
        $buf = New-Object byte[] 4096
        $read = 0
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $read = $fs.Read($buf, 0, $buf.Length) } finally { $fs.Close() }
        $head = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $end = $fi.LastWriteTime
        $m = [regex]::Match($head, '^\[(\d{2}):(\d{2}):')
        if ($m.Success) {
            $hh = [int]$m.Groups[1].Value
            $mm = [int]$m.Groups[2].Value
            $d = $end.Date
            if (($hh * 60 + $mm) -gt ($end.Hour * 60 + $end.Minute)) { $d = $d.AddDays(-1) }
            $out = ($d.Year % 100).ToString('00') + '/' + $d.Month.ToString('00') + '/' + $d.Day.ToString('00') + ' ' + $m.Groups[1].Value + ':' + $m.Groups[2].Value
        } else {
            $out = ($end.Year % 100).ToString('00') + '/' + $end.Month.ToString('00') + '/' + $end.Day.ToString('00') + ' ' + $end.Hour.ToString('00') + ':' + $end.Minute.ToString('00')
        }
    } catch { $out = '' }
    return $out
}

# ==== snapshot document ====
function Esc([string]$s) {
    $t = [regex]::Replace([string]$s, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    $t = [System.Security.SecurityElement]::Escape($t)
    # Line breaks must go in as character references: raw newlines inside an
    # XML text node get collapsed by the XAML reader, which would glue every
    # log entry into one long line.  Character references survive untouched.
    $t = $t.Replace("`r`n", '&#13;&#10;').Replace("`r", '&#13;').Replace("`n", '&#10;')
    return $t
}

function Reverse-Lines([string]$s) {
    if (-not $s) { return $s }
    $t = $s.TrimEnd("`r", "`n")
    $lines = [string[]]($t -split "\r\n|\n|\r")
    [Array]::Reverse($lines)
    return ($lines -join "`r`n")
}

function New-Snapshot([string]$game, [string]$launcher, [string]$h1, [string]$h2, [string]$h3) {
    # The namespace prefix word is split on purpose; see the note near $gflag.
    $n = 'xm' + 'lns'
    $d = '<ResourceDictionary ' + $n + '="http://schemas.microsoft.com/winfx/2006/xaml/presentation" ' + $n + ':x="http://schemas.microsoft.com/winfx/2006/xaml" ' + $n + ':sys="clr-namespace:System;assembly=mscorlib">'
    $d = $d + '<sys:String x:Key="LogGen">YSMLOGG7</sys:String>'
    $d = $d + '<sys:String x:Key="LogViewText" xml:space="preserve">' + (Esc $game) + '</sys:String>'
    $d = $d + '<sys:String x:Key="LauncherLogText" xml:space="preserve">' + (Esc $launcher) + '</sys:String>'
    $d = $d + '<sys:String x:Key="LogHist1" xml:space="preserve">' + (Esc $h1) + '</sys:String>'
    $d = $d + '<sys:String x:Key="LogHist2" xml:space="preserve">' + (Esc $h2) + '</sys:String>'
    $d = $d + '<sys:String x:Key="LogHist3" xml:space="preserve">' + (Esc $h3) + '</sys:String>'
    $d = $d + '</ResourceDictionary>'
    return $d
}

function Compose-Snapshot {
    $game = ''
    $mc = Get-McInfo
    if ($mc -and $mc.Dir) {
        $game = Reverse-Lines (Read-TailText (Join-Path (Join-Path $mc.Dir 'logs') 'latest.log') 200000)
    }
    $launcherPath = Get-LauncherLogPath
    $launcher = ''
    if ($launcherPath) { $launcher = Reverse-Lines (Read-TailText $launcherPath 200000) }
    return New-Snapshot $game $launcher (Get-HistLabel (Get-LauncherLogPathN 2)) (Get-HistLabel (Get-LauncherLogPathN 3)) (Get-HistLabel (Get-LauncherLogPathN 4))
}

function Save-Snapshot([string]$doc) {
    $old = ''
    try { $old = [IO.File]::ReadAllText($script:outPath) } catch { }
    if ($old -eq $doc) { return $false }
    $tmp = $script:outPath + '.tmp'
    [IO.File]::WriteAllText($tmp, $doc, [Text.UTF8Encoding]::new($true))
    Move-Item -Force $tmp $script:outPath
    return $true
}

# ==== opening folders and logs ====
# Start-Process passes the quoted path straight to Explorer/Notepad, so a
# folder name with &, parentheses or non-ASCII text is never re-parsed by
# cmd.exe.  PCLTOOLS_OPEN_DRYRUN lets the offline tests verify the resolved
# target without opening a window.
function Open-Target([string]$path, [string]$kind) {
    if (-not $path) { return $false }
    $full = $path
    try { $full = [IO.Path]::GetFullPath($path) } catch { }
    if ($env:PCLTOOLS_OPEN_DRYRUN) {
        [Console]::Out.WriteLine('OPEN=' + $full)
        return $true
    }
    try {
        if ($kind -eq 'explorer') {
            if (-not [IO.Directory]::Exists($full)) { [void][IO.Directory]::CreateDirectory($full) }
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $full + '"') | Out-Null
        } else {
            if (-not [IO.File]::Exists($full)) { return $false }
            Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $full + '"') | Out-Null
        }
        return $true
    } catch { return $false }
}

# ==== F5 into PCL ====
function Test-PclForeground($hwnd) {
    if (-not ('PCLHomeNative' -as [type])) {
        $cs = 'using System;using System.Runtime.InteropServices;public static class PCLHomeNative{[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();}'
        Add-Type -TypeDefinition $cs
    }
    return ([PCLHomeNative]::GetForegroundWindow().ToInt64() -eq $hwnd.ToInt64())
}

# The launcher window, whatever the fork is called (PCL, PCL2 CE, ...).
function Get-PclWindow {
    try {
        return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(PCL|Plain Craft Launcher)' -and $_.MainWindowHandle.ToInt64() -ne 0 })[0]
    } catch { return $null }
}

function Send-F5([bool]$activate) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $p = Get-PclWindow
        if (-not $p) { return $false }
        if ($activate) {
            $shell = New-Object -ComObject WScript.Shell
            $ok = $shell.AppActivate($p.Id)
            Start-Sleep -Milliseconds 250
            if (-not $ok) { $ok = $shell.AppActivate($p.Id); Start-Sleep -Milliseconds 150 }
            if (-not $ok) { return $false }
        } elseif (-not (Test-PclForeground $p.MainWindowHandle)) {
            return $false
        }
        [System.Windows.Forms.SendKeys]::SendWait('{F5}')
        return $true
    } catch { return $false }
}

# ==== which PCL page is showing ====
# F5 reloads the page PCL has open, so the automatic refresh must hold still
# while the user is on another page (Download/Setup/...).  PCL logs every
# switch as "切换主要页面：<page>"; a session without any switch line still
# sits on the home page, so that is the default.
function Get-PclPage {
    $tail = Read-TailText (Get-LauncherLogPath) 1048576
    $page = $null
    foreach ($m in [regex]::Matches($tail, '切换主要页面[：:]\s*([A-Za-z]+)')) { $page = $m.Groups[1].Value }
    if ($page) { return $page }
    return 'Launch'
}

# ==== watch mode ====
# The launcher is a tiny VBS started by wscript.exe (a GUI-subsystem program).
# It starts PowerShell with window style 0, so the logon entry and every
# homepage button stay invisible.  If the VBS was deleted, rebuild it from
# the backup embedded in Custom.xaml first.
function Ensure-LauncherFile {
    $vbs = Join-Path $Base 'PCLHomeLaunch.vbs'
    if (Test-Path -LiteralPath $vbs) { return $vbs }
    $cx = Join-Path $Base 'Custom.xaml'
    if (-not (Test-Path -LiteralPath $cx)) { return '' }
    try {
        $c = [IO.File]::ReadAllText($cx, [Text.Encoding]::UTF8)
        $m = [regex]::Match($c, '(?sm)^@@YSM-TOOLS-VBS@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-IMG@@')
        if ($m.Success) {
            [IO.File]::WriteAllText($vbs, $m.Groups[1].Value, [Text.UTF8Encoding]::new($false))
            return $vbs
        }
    } catch { }
    return ''
}

function Ensure-Autostart {
    if ($env:PCLTOOLS_NO_AUTOSTART) { return }
    try {
        $vbs = Ensure-LauncherFile
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $cur = ''
        try { $cur = [string](Get-ItemProperty -Path $key -Name 'PCLCustomHomeWatch').PCLCustomHomeWatch } catch { }
        if (-not $vbs) {
            # Never fall back to a console-subsystem command: that is exactly
            # the window this launcher exists to avoid.  Drop the old entry.
            if ($cur) {
                Remove-ItemProperty -Path $key -Name 'PCLCustomHomeWatch' -ErrorAction SilentlyContinue
                WLog 'autostart entry removed (launcher missing)'
            }
        } else {
            $cmd = 'wscript.exe //B //Nologo "' + $vbs + '" watch'
            if ($cur -ne $cmd) {
                Set-ItemProperty -Path $key -Name 'PCLCustomHomeWatch' -Value $cmd
                WLog 'autostart entry updated'
            }
        }
        # The video wallpaper experiment is gone; make sure an entry left behind
        # by an older install does not bring the player back at logon.
        try {
            if (Get-ItemProperty -Path $key -Name 'PCLCustomHomeVideoWall' -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $key -Name 'PCLCustomHomeVideoWall' -ErrorAction SilentlyContinue
                WLog 'video wallpaper autostart entry removed'
            }
        } catch { }
    } catch { }
}

function Start-Egg {
    try {
        $egg = $Base + 'Egg.ps1'
        if (-not [IO.File]::Exists($egg)) { return }
        WLog 'egg launched'
        $vbs = Ensure-LauncherFile
        if ($vbs) {
            Start-Process -FilePath 'wscript.exe' -ArgumentList ('//B //Nologo "' + $vbs + '" egg') | Out-Null
        } else {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $egg + '"') -WindowStyle Hidden | Out-Null
        }
    } catch { }
}

# Shift+X+C held down while PCL runs.  Inside PCL it fires directly; outside
# it also fires, except when the Minecraft window is in front, so the egg
# never pops up in the middle of a game.  Polled a few times a second; a
# latch stops one long press from opening several windows.
$script:eggLatched = $false
function Test-EggHotkey {
    try {
        if (-not ('PCLHomeEgg' -as [type])) {
            $cs2 = 'using System;using System.Runtime.InteropServices;public static class PCLHomeEgg{[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int k);[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();[DllImport("user32.dll")]public static extern int GetWindowThreadProcessId(IntPtr h,out int p);}'
            Add-Type -TypeDefinition $cs2
        }
        $sh = [PCLHomeEgg]::GetAsyncKeyState(0x10) -band 0x8000
        $kx = [PCLHomeEgg]::GetAsyncKeyState(0x58) -band 0x8000
        $kc = [PCLHomeEgg]::GetAsyncKeyState(0x43) -band 0x8000
        if (-not ($sh -and $kx -and $kc)) { $script:eggLatched = $false; return }
        if ($script:eggLatched) { return }
        $script:eggLatched = $true
        $pcl = Get-PclWindow
        if (-not $pcl) { return }
        $fg = [PCLHomeEgg]::GetForegroundWindow()
        if ($fg.ToInt64() -ne $pcl.MainWindowHandle.ToInt64()) {
            $fp = 0
            [void][PCLHomeEgg]::GetWindowThreadProcessId($fg, [ref]$fp)
            $pn = ''
            try { $pn = [string](Get-Process -Id $fp -ErrorAction SilentlyContinue).ProcessName } catch { }
            if ($pn -ieq 'java' -or $pn -ieq 'javaw') { return }
        }
        Start-Egg
    } catch { }
}

function Start-Watch {
    if ($env:PCLTOOLS_NO_WATCH) { exit 0 }
    $mtx = New-Object Threading.Mutex($false, $script:watchMutexName)
    $got = $false
    try { $got = $mtx.WaitOne(0) } catch { $got = $true }
    if (-not $got) { exit 0 }
    WLog ('watcher started, pid ' + [string]$PID + ', base ' + $Base)
    Ensure-Autostart
    $lastMc = '<init>'
    $lastGameLog = '<init>'
    $pclWas = $null
    $f5Pending = $false
    $autoDue = $false
    $lastF5 = [DateTime]::MinValue
    $lastWrite = [DateTime]::MinValue
    $lastHeld = [DateTime]::MinValue
    while ($true) {
        for ($tick = 0; $tick -lt 10; $tick++) {
            Start-Sleep -Milliseconds 100
            Test-EggHotkey
        }
        $pcl = Get-PclWindow
        $pclNow = [bool]$pcl
        if ($null -eq $pclWas) {
            $pclWas = $pclNow
        } elseif ($pclNow -ne $pclWas) {
            $pclWas = $pclNow
            if ($pclNow) { $f5Pending = $true; WLog 'PCL window appeared' }
            else { WLog 'PCL window closed' }
        }
        $mc = Get-McInfo
        $mcKey = 'none'
        if ($mc) {
            $mcKey = [string]$mc.Pid
            if ($mc.Dir) { $mcKey = $mcKey + ' ' + $mc.Dir }
        }
        if ($mcKey -ne $lastMc) {
            if ($lastMc -ne '<init>') { $f5Pending = $true }
            WLog ('game state: ' + $mcKey)
            $lastMc = $mcKey
        }
        $gameLog = Get-GameLogStamp $mc
        if ($gameLog -ne $lastGameLog) {
            if ($lastGameLog -ne '<init>' -and $gameLog) { $autoDue = $true }
            $lastGameLog = $gameLog
        }
        # Keep the stored snapshot current, but only a change in the GAME log
        # schedules an automatic F5.  The launcher log grows with every page
        # reload, so it must never drive the refresh itself.
        if (([DateTime]::Now - $lastWrite).TotalSeconds -gt 3) {
            if (Save-Snapshot (Compose-Snapshot)) { $lastWrite = [DateTime]::Now }
        }
        # Keep the page fresh on its own: when nobody pressed F5 in the last
        # three seconds and the game log gained new content, press F5 again
        # (only while the PCL window is in front, so the game never loses
        # focus to a background refresh).
        if (($f5Pending -or $autoDue) -and $pclNow -and -not $env:PCLTOOLS_NO_REFRESH) {
            $gap = 3
            if (([DateTime]::Now - $lastF5).TotalSeconds -gt $gap) {
                $page = Get-PclPage
                if ($page -ne 'Launch') {
                    # The user is using another page: an F5 would reload that
                    # page under their hands, so hold the refresh until they
                    # come back to the home page.
                    if (([DateTime]::Now - $lastHeld).TotalSeconds -gt 60) {
                        WLog ('refresh held, PCL page: ' + $page)
                        $lastHeld = [DateTime]::Now
                    }
                } elseif (Send-F5 $false) {
                    $lastF5 = [DateTime]::Now
                    $f5Pending = $false
                    $autoDue = $false
                    WLog 'F5 sent'
                }
            }
        }
    }
}

# ==== main ====
if ($Paths) {
    $p = Resolve-PclPaths
    foreach ($k in $p.Keys) { [Console]::Out.WriteLine([string]$k + '=' + [string]$p[$k]) }
    exit 0
}

if ($OpenLauncherLog -gt 0) {
    $lp = Get-LauncherLogPathN $OpenLauncherLog
    if ($lp -and (Test-Path -LiteralPath $lp)) {
        if (Open-Target $lp 'notepad') { exit 0 }
    }
    # That log does not exist yet: show the folder that will hold it.
    $dir = $Base + 'Log'
    if (-not (Test-Path -LiteralPath $dir)) { $dir = $Base.TrimEnd('\') }
    if (Open-Target $dir 'explorer') { exit 0 }
    exit 1
}

if ($PageProbe) {
    Write-Output (Get-PclPage)
    exit 0
}

if ($OpenGameLog) {
    $mc = Get-McInfo
    if ($mc -and $mc.Dir) {
        $lp = Join-Path (Join-Path $mc.Dir 'logs') 'latest.log'
        if (Test-Path -LiteralPath $lp) {
            if (Open-Target $lp 'notepad') { exit 0 }
        }
    }
    exit 1
}

if ($OpenGameLogDir) {
    $mc = Get-McInfo
    if ($mc -and $mc.Dir) {
        if (Open-Target (Join-Path $mc.Dir 'logs') 'explorer') { exit 0 }
    }
    # No running game: fall back to the selected instance's logs folder.
    $p = Resolve-PclPaths
    $ld = ''
    if ($p['INDIEDIR']) { $ld = Join-Path $p['INDIEDIR'] 'logs' }
    elseif ($p['INSTDIR']) { $ld = Join-Path $p['INSTDIR'] 'logs' }
    elseif ($p['MCDIR']) { $ld = Join-Path $p['MCDIR'] 'logs' }
    if (-not $ld) { $ld = $Base.TrimEnd('\') + '\..' }
    if (Open-Target $ld 'explorer') { exit 0 }
    exit 1
}

if ($OpenFolder) {
    $p = Resolve-PclPaths
    $indie = [string]$p['INDIEDIR']
    $target = ''
    switch ($OpenFolder.ToLowerInvariant()) {
        'game' {
            # Keep the button label unchanged, but open the folder of the
            # currently selected instance instead of the global .minecraft.
            if ($p['INSTDIR']) { $target = [string]$p['INSTDIR'] }
            elseif ($indie) { $target = $indie }
            else { $target = [string]$p['MCDIR'] }
        }
        'mods' { $target = Join-Path $indie 'mods' }
        'saves' { $target = Join-Path $indie 'saves' }
        'schematics' { $target = Join-Path $indie 'schematics' }
        'logs' {
            $mc = Get-McInfo
            if ($mc -and $mc.Dir) { $target = Join-Path $mc.Dir 'logs' }
            elseif ($indie) { $target = Join-Path $indie 'logs' }
            elseif ($p['INSTDIR']) { $target = Join-Path ([string]$p['INSTDIR']) 'logs' }
            elseif ($p['MCDIR']) { $target = Join-Path ([string]$p['MCDIR']) 'logs' }
        }
    }
    if (-not $target) { $target = $Base.TrimEnd('\') + '\..' }
    if (Open-Target $target 'explorer') { exit 0 }
    exit 1
}

if ($Watch) {
    Start-Watch
    exit 0
}

Save-Snapshot (Compose-Snapshot) | Out-Null
if ($env:PCLTOOLS_NO_REFRESH) { exit 0 }
Send-F5 $true | Out-Null
exit 0
