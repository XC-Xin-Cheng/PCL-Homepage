# PCL custom homepage: one file installer for PCL2 and PCL CE.
# Runs from the %TEMP% copy that the batch header of the package makes.
# Installs the page, its helper scripts and the shared background into the
# selected launcher's data folder.  The user chooses PCL2 (Setup.ini) or
# PCL CE (config.v1.yml) before the folder picker, so the two launchers can
# be installed independently without one overwriting the other's settings.
#
# Inputs come through the environment (set by the batch header, no command
# line quoting involved):
#   SELF           path of the package .bat (the payload lives there)
#   PCLHOME_MODE1  empty, "pcl", "ce", a target folder, or "uninstall"
#   PCLHOME_MODE2  optional explicit target folder
#
# Sandbox switch: PCLTOOLS_INSTALL_TEST=1 makes every interactive step
# noninteractive and never touches the registry or the real watcher, so the
# sandbox test can drive it inside a throwaway folder.
$ErrorActionPreference = 'Stop'

$script:self = [string]$env:SELF
$script:arg1 = ([string]$env:PCLHOME_MODE1).Trim()
$script:arg2 = ([string]$env:PCLHOME_MODE2).Trim()
$script:testMode = [bool]$env:PCLTOOLS_INSTALL_TEST
$script:flavor = ''

function Normalize-Flavor([string]$f) {
    switch ($f.Trim().ToLowerInvariant()) {
        'pcl'    { return 'pcl' }
        'pcl2'   { return 'pcl' }
        'pcl-2'  { return 'pcl' }
        'ce'     { return 'ce' }
        'pclce'  { return 'ce' }
        'pcl-ce' { return 'ce' }
        default  { return '' }
    }
}
function Get-FlavorLabel([string]$f) {
    if ($f -eq 'ce') { return 'PCL CE' }
    if ($f -eq 'pcl') { return 'PCL2（原版）' }
    return 'PCL / PCL CE'
}

# The UI keys the custom page was designed around (values taken from the
# working install): custom homepage on, see through launcher, full strength
# background, no logo, colourful background, default theme.
# PCL2 reads Setup.ini.  PCL CE reads the flat YAML file PCL\config.v1.yml,
# where booleans are lower case and HintCustomCommand suppresses its first
# "run a homepage command?" prompt.
$script:uiKeysIni = [ordered]@{
    'UiCustomType'          = '1'
    'UiLauncherTransparent' = '596'
    'UiBackgroundOpacity'   = '1000'
    'UiLauncherLogo'        = 'False'
    'UiBackgroundColorful'  = 'True'
    'UiLauncherTheme'       = '0'
}
$script:uiKeysYaml = [ordered]@{
    'UiCustomType'          = '1'
    'UiLauncherTransparent' = '596'
    'UiBackgroundOpacity'   = '1000'
    'UiLauncherLogo'        = 'false'
    'UiBackgroundColorful'  = 'true'
    'UiLauncherTheme'       = '0'
    'HintCustomCommand'     = 'true'
}

function Say([string]$s) { Write-Host $s }
function SayErr([string]$s) { Write-Host $s -ForegroundColor Red }
function End-Pause {
    if ($script:testMode) { return }
    try { if ([Console]::IsInputRedirected) { return } } catch { }
    Write-Host ''
    Write-Host '按任意键关闭…'
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}
function Die([string]$s) {
    SayErr ('无法继续：' + $s)
    End-Pause
    exit 3
}

# ==== payload ====
$lines = [IO.File]::ReadAllLines($script:self, [Text.Encoding]::UTF8)
$di = [Array]::IndexOf($lines, '::DATA-BEGIN')
$dj = [Array]::IndexOf($lines, '::DATA-END')
if ($di -lt 0 -or $dj -le $di) { Die '安装包似乎不完整（找不到数据段），请重新获取本文件。' }
$b64 = New-Object Text.StringBuilder
for ($k = $di + 1; $k -lt $dj; $k++) {
    if ($lines[$k].Length -gt 2) { [void]$b64.Append($lines[$k].Substring(2)) }
}
$data = $null
try { $data = [Convert]::FromBase64String($b64.ToString()) } catch { $data = $null }
if (-not $data -or $data.Length -lt 1000) { Die '安装包似乎已损坏（数据段无法解码），请重新获取本文件。' }

# The theme ships two background images; the second one is optional.
$img2 = $null
$i2i = [Array]::IndexOf($lines, '::IMG2-BEGIN')
$i2j = [Array]::IndexOf($lines, '::IMG2-END')
if ($i2i -ge 0 -and $i2j -gt $i2i) {
    $b64img2 = New-Object Text.StringBuilder
    for ($k = $i2i + 1; $k -lt $i2j; $k++) {
        if ($lines[$k].Length -gt 2) { [void]$b64img2.Append($lines[$k].Substring(2)) }
    }
    try { $img2 = [Convert]::FromBase64String($b64img2.ToString()) } catch { $img2 = $null }
}

# The lock screen still that ships with the theme.
$lockImg = $null
$i3i = [Array]::IndexOf($lines, '::IMG3-BEGIN')
$i3j = [Array]::IndexOf($lines, '::IMG3-END')
if ($i3i -ge 0 -and $i3j -gt $i3i) {
    $b64lock = New-Object Text.StringBuilder
    for ($k = $i3i + 1; $k -lt $i3j; $k++) {
        if ($lines[$k].Length -gt 2) { [void]$b64lock.Append($lines[$k].Substring(2)) }
    }
    try { $lockImg = [Convert]::FromBase64String($b64lock.ToString()) } catch { $lockImg = $null }
}

# ==== target folder ====
function Test-IsPclData([string]$d) {
    if (Test-Path -LiteralPath ($d + '\Setup.ini')) { return $true }
    if (Test-Path -LiteralPath ($d + '\config.v1.yml')) { return $true }
    if (Test-Path -LiteralPath ($d + '\Custom.xaml')) { return $true }
    return $false
}
function Test-DirHasCeExe([string]$d) {
    if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { return $false }
    return (@(Get-ChildItem -LiteralPath $d -Filter *.exe -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^PCL2_CE|^PCLCE|^PCL CE' }).Count -gt 0)
}
function Test-DirHasPcl2Exe([string]$d) {
    if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { return $false }
    return (@(Get-ChildItem -LiteralPath $d -Filter *.exe -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^PCL(\.exe)?$|^PCL2(?!_CE)|^Plain Craft Launcher 2' }).Count -gt 0)
}
function Test-IsCeData([string]$d) {
    $hasYaml = Test-Path -LiteralPath ($d + '\config.v1.yml')
    $root = Split-Path -Path $d -Parent
    $rootCe = Test-DirHasCeExe $root
    $rootPcl = Test-DirHasPcl2Exe $root
    if ($hasYaml) {
        # A leftover config.v1.yml in a folder whose launcher is clearly PCL2
        # must not turn that folder into a PCL CE target.
        if ($rootPcl -and -not $rootCe) { return $false }
        return $true
    }
    return $rootCe
}
function Test-IsPcl2Data([string]$d) {
    $hasIni = Test-Path -LiteralPath ($d + '\Setup.ini')
    $root = Split-Path -Path $d -Parent
    $rootCe = Test-DirHasCeExe $root
    $rootPcl = Test-DirHasPcl2Exe $root
    if ($hasIni) {
        # A leftover Setup.ini in a PCL CE folder is not a PCL2 target.
        if ($rootCe -and -not $rootPcl) { return $false }
        return $true
    }
    return $rootPcl
}
function Test-IsFlavorData([string]$d, [string]$f) {
    if ($f -eq 'ce') { return (Test-IsCeData $d) }
    if ($f -eq 'pcl') { return (Test-IsPcl2Data $d) }
    return (Test-IsPclData $d)
}
function Test-IsFlavorExe([string]$d, [string]$f) {
    if ($f -eq 'ce') { return (Test-DirHasCeExe $d) }
    if ($f -eq 'pcl') { return (Test-DirHasPcl2Exe $d) }
    return ((Test-DirHasCeExe $d) -or (Test-DirHasPcl2Exe $d))
}
function Get-FlavorForDir([string]$d) {
    if (Test-IsCeData $d) { return 'ce' }
    if (Test-IsPcl2Data $d) { return 'pcl' }
    return ''
}
function Resolve-Target([string]$d, [string]$flavor) {
    if (-not $d) { return '' }
    $d = $d.Trim().Trim('"')
    if (-not $d) { return '' }
    $d = $d.TrimEnd('\')
    if ($d -match '^[A-Za-z]:$') { $d = $d + '\' }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return '' }

    $want = Normalize-Flavor $flavor
    $other = ''
    if ($want -eq 'ce') { $other = 'pcl' }
    if ($want -eq 'pcl') { $other = 'ce' }

    # The selected folder can be the data folder itself (contains Setup.ini or
    # config.v1.yml) or the launcher directory (contains the exe and \PCL).
    if ($want) {
        if (Test-IsFlavorData $d $want) { return $d }
    } else {
        if (Test-IsPclData $d) { return $d }
    }

    $sub = $d + '\PCL'
    if (Test-Path -LiteralPath $sub -PathType Container) {
        if ($want) {
            if (Test-IsFlavorData $sub $want) { return $sub }
        } else {
            if (Test-IsPclData $sub) { return $sub }
        }
    }

    if ($want) {
        if (Test-IsFlavorExe $d $want) { return $sub }
        # Do not silently install a PCL2 page into a PCL CE folder (or the
        # reverse) just because the other launcher happens to be nearby.
        if (Test-IsFlavorExe $d $other) { return '' }
    } else {
        if ((Test-IsFlavorExe $d 'ce') -or (Test-IsFlavorExe $d 'pcl')) { return $sub }
        $exe = @(Get-ChildItem -LiteralPath $d -Filter *.exe -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(PCL|Plain Craft Launcher)|Launcher' })
        if ($exe.Count -gt 0) { return $sub }
        if ((Test-Path -LiteralPath ($d + '\PCL.exe')) -or (Test-Path -LiteralPath ($d + '\Plain Craft Launcher 2.exe'))) { return $sub }
    }
    return ''
}
function Pick-Flavor {
    try { if ([Console]::IsInputRedirected) { return '' } } catch { }
    Say ''
    Say '请选择要安装到的启动器：'
    Say '  1. PCL2（原版，使用 Setup.ini）'
    Say '  2. PCL CE（使用 config.v1.yml）'
    Say ''
    while ($true) {
        $a = [string](Read-Host '输入 1 或 2，然后回车（输入 q 取消）')
        switch ($a.Trim().ToLowerInvariant()) {
            '1'    { return 'pcl' }
            'pcl'  { return 'pcl' }
            'pcl2' { return 'pcl' }
            '2'    { return 'ce' }
            'ce'   { return 'ce' }
            'pclce' { return 'ce' }
            'pcl-ce' { return 'ce' }
            'q'    { return '' }
            default { Say '请输入 1 或 2。' }
        }
    }
}
function Pick-Target([string]$flavor) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $label = Get-FlavorLabel $flavor
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($flavor -eq 'ce') {
        $dlg.Description = '请选择 PCL CE 的数据文件夹（包含 config.v1.yml，一般在 PCL2_CE_*.exe 旁边的 PCL 文件夹）'
    } elseif ($flavor -eq 'pcl') {
        $dlg.Description = '请选择 PCL2（原版）的数据文件夹（包含 Setup.ini，一般在 PCL.exe 旁边的 PCL 文件夹）'
    } else {
        $dlg.Description = '请选择 PCL 的数据文件夹（包含 Setup.ini 或 config.v1.yml，一般在启动器旁边的 PCL 文件夹）'
    }
    $dlg.ShowNewFolderButton = $false
    try { $dlg.SelectedPath = [IO.Path]::GetDirectoryName($script:self) } catch { }
    while ($true) {
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return '' }
        $r = Resolve-Target $dlg.SelectedPath $flavor
        if ($r) { return $r }
        $hint = if ($flavor -eq 'ce') {
            '这个文件夹不像是 PCL CE 的文件夹：里面没有 config.v1.yml，旁边也没有 PCL2_CE_*.exe。'
        } elseif ($flavor -eq 'pcl') {
            '这个文件夹不像是 PCL2 的文件夹：里面没有 Setup.ini，旁边也没有 PCL.exe。'
        } else {
            '这个文件夹不像是 PCL 的文件夹：里面没有 Setup.ini、config.v1.yml 或 PCL.exe。'
        }
        [void][System.Windows.Forms.MessageBox]::Show(($hint + [Environment]::NewLine +
            '请选择 ' + $label + ' 的数据文件夹，或它旁边的启动器目录。'), 'PCL 主页安装')
    }
}

# ==== Setup.ini (PCL2) ====
function Update-SetupIni([string]$dir, $keys) {
    $p = $dir + '\Setup.ini'
    $nl = "`r`n"
    $text = ''
    if (Test-Path -LiteralPath $p) {
        $text = [IO.File]::ReadAllText($p)
        if ($text.Contains("`n") -and -not $text.Contains("`r`n")) { $nl = "`n" }
    }
    $list = New-Object 'System.Collections.Generic.List[string]'
    if ($text) { foreach ($l in ($text -split "\r?\n")) { $list.Add($l) } }
    while ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    foreach ($key in $keys.Keys) {
        $found = $false
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i] -match ('^' + [regex]::Escape([string]$key) + ':')) {
                $list[$i] = [string]$key + ':' + [string]$keys[$key]
                $found = $true
            }
        }
        if (-not $found) { $list.Add([string]$key + ':' + [string]$keys[$key]) }
    }
    while ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    [IO.File]::WriteAllText($p, (($list -join $nl) + $nl), [Text.UTF8Encoding]::new($false))
}

# ==== config.v1.yml (PCL CE) ====
# Flat "key: value" YAML.  Only the lines we own are rewritten; comments and
# every other setting stay exactly as PCL CE wrote them.
function Update-Yaml([string]$p, $keys) {
    $nl = "`n"
    $text = ''
    if (Test-Path -LiteralPath $p) {
        $text = [IO.File]::ReadAllText($p)
        if ($text.Contains("`r`n")) { $nl = "`r`n" }
    }
    $list = New-Object 'System.Collections.Generic.List[string]'
    if ($text) { foreach ($l in ($text -split "\r?\n")) { $list.Add($l) } }
    while ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    foreach ($key in $keys.Keys) {
        $found = $false
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i] -match ('^' + [regex]::Escape([string]$key) + '\s*:')) {
                $list[$i] = [string]$key + ': ' + [string]$keys[$key]
                $found = $true
            }
        }
        if (-not $found) { $list.Add([string]$key + ': ' + [string]$keys[$key]) }
    }
    [IO.File]::WriteAllText($p, (($list -join $nl) + $nl), [Text.UTF8Encoding]::new($false))
}

function Update-PclConfig([string]$dir, $iniKeys, $yamlKeys, [bool]$createYaml) {
    $ini = $dir + '\Setup.ini'
    $y = $dir + '\config.v1.yml'
    $hasIni = Test-Path -LiteralPath $ini
    $hasYaml = Test-Path -LiteralPath $y
    # PCL2 folders always use Setup.ini; create it when the folder has no
    # config.v1.yml (a fresh/empty PCL2 data folder).  PCL CE only uses the
    # YAML file, so do not leave a stray Setup.ini there.
    if ($hasIni -or (-not $hasYaml -and -not $createYaml)) { Update-SetupIni $dir $iniKeys }
    if ($hasYaml -or $createYaml) { Update-Yaml $y $yamlKeys }
}

# Only the launcher the user picked is touched.  This keeps a PCL CE install
# from rewriting Setup.ini and a PCL2 install from rewriting config.v1.yml
# when both launchers happen to share a folder.
function Update-SelectedConfig([string]$dir, [string]$flavor) {
    if ($flavor -eq 'ce') {
        Update-Yaml ($dir + '\config.v1.yml') $script:uiKeysYaml
        return
    }
    if ($flavor -eq 'pcl') {
        Update-SetupIni $dir $script:uiKeysIni
        return
    }
    Update-PclConfig $dir $script:uiKeysIni $script:uiKeysYaml (Test-IsCeData $dir)
}

function Reset-UiCustomType([string]$dir, [string]$flavor) {
    if ($flavor -eq 'ce') {
        if (Test-Path -LiteralPath ($dir + '\config.v1.yml')) {
            Update-Yaml ($dir + '\config.v1.yml') ([ordered]@{ 'UiCustomType' = '0' })
        }
        return
    }
    if ($flavor -eq 'pcl') {
        if (Test-Path -LiteralPath ($dir + '\Setup.ini')) {
            Update-SetupIni $dir ([ordered]@{ 'UiCustomType' = '0' })
        }
        return
    }
    try { Update-PclConfig $dir ([ordered]@{ 'UiCustomType' = '0' }) ([ordered]@{ 'UiCustomType' = '0' }) $false } catch { }
}

function Wait-PclClosed {
    if ($script:testMode) { return $true }
    $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(PCL|Plain Craft Launcher)' })
    if ($p.Count -eq 0) { return $true }
    Say 'PCL / PCL CE 正在运行，请先完全退出（安装需要写入它的设置文件）。'
    Say '退出后本窗口会自动继续，最多等待 60 秒…'
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 500
        if (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(PCL|Plain Craft Launcher)' }).Count -eq 0) { return $true }
    }
    return $false
}

function Stop-Watchers([string]$dir) {
    if ($script:testMode) { return }
    $me = $PID
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.ProcessId -eq $me) { continue }
        $cl = [string]$p.CommandLine
        if ($cl -and $cl.Contains('RefreshLog.ps1') -and $cl.Contains('-Watch') -and $cl.Contains($dir)) {
            try { Stop-Process -Id $p.ProcessId -Force } catch { }
        }
    }
    Start-Sleep -Milliseconds 400
}

# ==== install / uninstall ====
function Get-Seg([string]$c, [string]$a, [string]$b) {
    $m = [regex]::Match($c, '(?sm)^@@YSM-TOOLS-' + [regex]::Escape($a) + '@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-' + [regex]::Escape($b) + '@@')
    if (-not $m.Success) { throw ('备份段缺失：' + $a) }
    return $m.Groups[1].Value
}

function Invoke-Install([string]$dir, [string]$flavor) {
    $flavor = Normalize-Flavor $flavor
    if (-not $flavor) { $flavor = Get-FlavorForDir $dir }
    if (-not $flavor) { Die ('无法判断要安装到 PCL2 还是 PCL CE：' + $dir) }
    if (-not (Wait-PclClosed)) { Die 'PCL 仍在运行，请退出 PCL / PCL CE 后再运行本安装器。' }
    Stop-Watchers $dir
    [void][IO.Directory]::CreateDirectory($dir)
    $cx = Join-Path $dir 'Custom.xaml'
    [IO.File]::WriteAllBytes($cx, $data)
    $c = [IO.File]::ReadAllText($cx)
    [IO.File]::WriteAllText((Join-Path $dir 'CustomTools.bat'), (Get-Seg $c 'BAT' 'PS1'), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'RefreshLog.ps1'), (Get-Seg $c 'PS1' 'PS2'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'BgRefresh.ps1'), (Get-Seg $c 'PS2' 'PS3'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'Egg.ps1'), (Get-Seg $c 'PS3' 'PS4'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'VideoWall.ps1'), (Get-Seg $c 'PS4' 'IMG'), [Text.UTF8Encoding]::new($true))
    foreach ($old in @('InjectDll.ps1', 'InjectDll.lock')) {
        try { Remove-Item -LiteralPath (Join-Path $dir $old) -Force -ErrorAction SilentlyContinue } catch { }
    }
    $picDir = Join-Path $dir 'Pictures'
    [void][IO.Directory]::CreateDirectory($picDir)
    $img = Get-Seg $c 'IMG' 'END'
    [IO.File]::WriteAllBytes((Join-Path $picDir 'CustomHomeBG.jpg'), [Convert]::FromBase64String(($img -replace '\s', '')))
    if ($img2) { [IO.File]::WriteAllBytes((Join-Path $picDir 'videoframe_2546.png'), $img2) }
    if ($lockImg) { [IO.File]::WriteAllBytes((Join-Path $picDir 'CustomHomeLock.png'), $lockImg) }
    Update-SelectedConfig $dir $flavor
    $env:PCLTOOLS_NO_REFRESH = '1'
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'RefreshLog.ps1') $dir | Out-Null
    } finally {
        Remove-Item Env:\PCLTOOLS_NO_REFRESH -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'LogView.xaml'))) { throw 'LogView.xaml 生成失败' }
    if (-not $script:testMode -and -not $env:PCLTOOLS_NO_WATCH) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dir 'RefreshLog.ps1') + '" -Watch') -WindowStyle Hidden
    }
    Say ''
    Say ('已安装到：' + $dir)
    Say ('安装目标：' + (Get-FlavorLabel $flavor))
    Say '打开对应的启动器就能看到自定义主页。'
    Say '（如果启动器已经开着：按 F5 刷新主页，或退出重开。）'
    Say ''
    Say '再次运行本文件可以覆盖安装或卸载。'
}

function Invoke-Uninstall([string]$dir, [string]$flavor) {
    $flavor = Normalize-Flavor $flavor
    if (-not $script:testMode) {
        $a = Read-Host ('确定要从 ' + $dir + ' 卸载自定义主页吗？输入 y 回车确认')
        if ($a -notmatch '^\s*y') { Say '已取消。'; return }
    }
    if (-not (Wait-PclClosed)) { Die 'PCL 仍在运行，请退出 PCL / PCL CE 后再卸载。' }
    Stop-Watchers $dir
    if (-not $script:testMode) {
        foreach ($n in @('PCLCustomHomeWatch', 'PCLCustomHomeVideoWall')) {
            try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $n -ErrorAction SilentlyContinue } catch { }
        }
    }
    foreach ($f in @('Custom.xaml', 'LogView.xaml', 'CustomTools.bat', 'RefreshLog.ps1', 'BgRefresh.ps1', 'Egg.ps1', 'VideoWall.ps1', 'CustomTools.log', 'VideoWall.ready', 'Pictures\CustomHomeBG.jpg', 'Pictures\videoframe_2546.png', 'Pictures\CustomHomeLock.png')) {
        try { Remove-Item -LiteralPath ($dir + '\' + $f) -Force -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-Item -LiteralPath ($dir + '\VideoWall') -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Reset-UiCustomType $dir $flavor
    Say ''
    Say ('已卸载：' + $dir)
    Say ('恢复的启动器：' + (Get-FlavorLabel $flavor))
    Say '（自带主页会恢复正常；如启动器正在运行，请重启它。界面设置保持不变。）'
}

# ==== main ====
try {
    $mode = 'install'
    $want = ''
    if ($script:arg1) {
        if ($script:arg1 -ieq 'uninstall') {
            $mode = 'uninstall'
            $want = $script:arg2
        } else {
            $f = Normalize-Flavor $script:arg1
            if ($f) {
                $script:flavor = $f
                $want = $script:arg2
            } else {
                $want = $script:arg1
            }
        }
    }

    $target = ''
    if ($want) { $target = Resolve-Target $want $script:flavor }
    if (-not $target) {
        if ($script:testMode) { Die ('无法识别目标文件夹：' + $want) }
        if ($want) {
            Say ('这个文件夹不像是 ' + (Get-FlavorLabel $script:flavor) + ' 文件夹：' + $want)
        }

        if ($mode -eq 'uninstall') {
            Say '请选择要卸载的 PCL 数据文件夹（包含 Setup.ini 或 config.v1.yml）。'
            $target = Pick-Target ''
        } else {
            if (-not $script:flavor) {
                $script:flavor = Pick-Flavor
                if (-not $script:flavor) { Say '已取消。'; End-Pause; exit 1 }
            }
            Say ''
            Say ('安装目标：' + (Get-FlavorLabel $script:flavor))
            $target = Pick-Target $script:flavor
        }
        if (-not $target) { Say '已取消。'; End-Pause; exit 1 }
    }

    if ($mode -eq 'install' -and -not $script:flavor) {
        $script:flavor = Get-FlavorForDir $target
        if (-not $script:flavor) {
            if ($script:testMode) { Die ('无法判断要安装到 PCL2 还是 PCL CE：' + $target) }
            $script:flavor = Pick-Flavor
            if (-not $script:flavor) { Say '已取消。'; End-Pause; exit 1 }
        }
    }

    if ($mode -eq 'uninstall') {
        Invoke-Uninstall $target $script:flavor
        End-Pause
        exit 0
    }
    if (-not $script:testMode) {
        $interactive = $true
        try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { }
        if ($interactive -and (Test-Path -LiteralPath ($target + '\Custom.xaml'))) {
            Say ('这里已经有自定义主页：' + $target)
            Say ('当前安装目标：' + (Get-FlavorLabel $script:flavor))
            $a = Read-Host '直接回车 = 覆盖安装，输入 u 回车 = 卸载，输入其他 = 取消'
            if ($a -match '^\s*u') { Invoke-Uninstall $target $script:flavor; End-Pause; exit 0 }
            if ($a -and $a.Trim()) { Say '已取消。'; End-Pause; exit 1 }
        }
    }
    Invoke-Install $target $script:flavor
    End-Pause
    exit 0
} catch {
    SayErr ('出错：' + [string]$_.Exception.Message)
    Say '可以尝试：退出 PCL 后重试；或把 PCL 文件夹放到可写的位置；或以管理员身份运行。'
    End-Pause
    exit 3
}
