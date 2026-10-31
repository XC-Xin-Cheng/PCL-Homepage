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
$script:guiMode = $false
$script:guiLang = 'zh-CN'
$script:homeLang = 'zh-CN'
$script:guiBusy = $false
$script:guiSelectingFlavor = $false
$script:guiUpdatingLanguage = $false
$script:guiStatusKey = 'status_ready'
$script:guiStatusTone = 'muted'
$script:guiStatusArgs = @()
$script:guiTarget = ''
$script:ui = $null
# PCL versions at or above this are incompatible: their built-in homepage
# handling makes this custom homepage obsolete.  2.99.0.0 itself is not supported.
$script:MinUnsupportedPclVersion = [version]'2.99.0.0'
$script:incompatiblePcl = $false
$script:incompatiblePclVersion = ''
$script:pclCloseCancelled = $false

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

function Say([string]$s) {
    if ($script:guiMode) { return }
    Write-Host $s
}
function SayErr([string]$s) {
    if ($script:guiMode) { return }
    Write-Host $s -ForegroundColor Red
}
function End-Pause {
    if ($script:testMode -or $script:guiMode) { return }
    try { if ([Console]::IsInputRedirected) { return } } catch { }
    Write-Host ''
    Write-Host '按任意键关闭…'
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}
function Die([string]$s) {
    if ($script:guiMode) { throw ('无法继续：' + $s) }
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

# ==== launcher version guard ====
# The launcher exe is normally next to the data folder, but some users select
# the data folder directly.  Search both, without writing anything.
function Get-PclLauncherExe([string]$dir, [string]$flavor) {
    if (-not $dir) { return @() }
    $roots = @($dir)
    try {
        $parent = Split-Path -Path $dir -Parent
        if ($parent -and $parent -ne $dir -and $parent -notin $roots) { $roots += $parent }
    } catch { }

    $result = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter *.exe -File -ErrorAction SilentlyContinue)) {
            $full = $f.FullName
            if ($seen.ContainsKey($full)) { continue }
            $name = $f.Name
            $match = $false
            if ($flavor -eq 'ce') {
                $match = $name -match '^PCL2_CE|^PCLCE|^PCL CE'
            } elseif ($flavor -eq 'pcl') {
                $match = $name -match '^PCL(\.exe)?$|^PCL2(?!_CE)|^Plain Craft Launcher 2'
            } else {
                $match = $name -match '^PCL(\.exe)?$|^PCL2|^Plain Craft Launcher 2|^PCLCE|^PCL CE'
            }
            if ($match) {
                $seen[$full] = $true
                [void]$result.Add($f)
            }
        }
    }
    return @($result.ToArray())
}

# FileVersion is the reliable field: PCL CE reports ProductVersion as
# "1.0.0+<commit>" while FileVersion is the actual release number.  Use
# ProductVersion only when FileVersion is missing or zero.
function Get-PclExeVersion([string]$path) {
    try {
        $vi = (Get-Item -LiteralPath $path -ErrorAction Stop).VersionInfo
        foreach ($raw in @([string]$vi.FileVersion, [string]$vi.ProductVersion)) {
            if (-not $raw) { continue }
            $m = [regex]::Match($raw, '(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?')
            if (-not $m.Success) { continue }
            $parts = @(0, 0, 0, 0)
            for ($i = 1; $i -le 4; $i++) {
                $g = $m.Groups[$i]
                if ($g.Success -and $g.Value) {
                    $n = 0
                    if ([int]::TryParse($g.Value, [ref]$n)) { $parts[$i - 1] = $n }
                }
            }
            $v = [version]($parts -join '.')
            if ($v -ne [version]'0.0.0.0') { return $v }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-PclVersionState([string]$dir, [string]$flavor) {
    $exes = @(Get-PclLauncherExe $dir $flavor)
    $best = $null
    $bestPath = ''
    foreach ($e in $exes) {
        $v = Get-PclExeVersion $e.FullName
        if ($v -and (-not $best -or $v -gt $best)) {
            $best = $v
            $bestPath = $e.FullName
        }
    }
    return [pscustomobject]@{
        Found       = ($exes.Count -gt 0)
        Version     = $best
        Path        = $bestPath
        Unsupported = [bool]($best -and $best -ge $script:MinUnsupportedPclVersion)
        Files       = @($exes | ForEach-Object { $_.FullName })
    }
}

function Show-IncompatiblePcl($state) {
    $script:incompatiblePcl = $true
    $script:incompatiblePclVersion = if ($state -and $state.Version) { [string]$state.Version } else { '' }
    if ($script:guiMode) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'incompatible_pcl'), (T 'app_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $lang = $script:guiLang
    if (-not $lang) { $lang = $script:homeLang }
    $msg = ''
    try {
        $script:guiLang = $lang
        $msg = [string](T 'incompatible_pcl')
    } catch { }
    if (-not $msg -or $msg -eq 'incompatible_pcl') {
        $msg = "你这个版本的PCL安装主页已经没有意义了`n未对您的计算机进行更改"
    }
    Say ''
    foreach ($line in ($msg -split "\r?\n")) { Say $line }
    Say ''
}

# GUI confirmation with literal YES / NO buttons.  A normal MessageBox would
# use the Windows display language for its buttons, but this prompt is
# intentionally YES / NO in every installer language.
function Show-ClosePclDialog {
    if (-not $script:ui) { return $false }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = T 'pcl_running_title'
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.MinimizeBox = $false
    $dlg.MaximizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.ShowIcon = $false
    $dlg.Font = $script:ui.form.Font
    $dlg.BackColor = $script:ui.form.BackColor
    $dlg.ForeColor = $script:ui.form.ForeColor
    $dlg.ClientSize = New-Object System.Drawing.Size(460, 160)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = T 'confirm_close_pcl'
    $label.AutoSize = $false
    $label.Location = New-Object System.Drawing.Point(18, 18)
    $label.Size = New-Object System.Drawing.Size(424, 78)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $label.Font = $script:ui.form.Font
    $label.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($label)

    $yes = New-Object System.Windows.Forms.Button
    $yes.Text = 'YES'
    $yes.Size = New-Object System.Drawing.Size(96, 32)
    $yes.Location = New-Object System.Drawing.Point(240, 108)
    $yes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $dlg.Controls.Add($yes)

    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'NO'
    $no.Size = New-Object System.Drawing.Size(96, 32)
    $no.Location = New-Object System.Drawing.Point(346, 108)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::No
    $dlg.Controls.Add($no)

    $dlg.AcceptButton = $yes
    $dlg.CancelButton = $no
    $r = $dlg.ShowDialog($script:ui.form)
    $dlg.Dispose()
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Confirm-ClosePcl([string]$flavor) {
    if ($script:testMode) { return $true }
    $script:pclCloseCancelled = $false
    if (-not (Test-PclRunning $flavor)) { return $true }

    if ($script:guiMode) {
        if (-not (Show-ClosePclDialog)) {
            $script:pclCloseCancelled = $true
            return $false
        }
    } else {
        Say ''
        $answer = Read-Host ((T 'confirm_close_pcl') + ' [YES/NO]')
        if ($answer -notmatch '^(?i:yes|y)$') {
            $script:pclCloseCancelled = $true
            Say '已取消。'
            return $false
        }
    }

    if ($script:guiMode -and $script:ui) {
        Set-GuiStatus 'status_closing_pcl' 'muted' @()
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
    }
    $closed = Close-PclProcesses $flavor
    if (-not $closed) {
        if ($script:guiMode) {
            [void][System.Windows.Forms.MessageBox]::Show((T 'pcl_running'), (T 'pcl_running_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        } else {
            Say (T 'pcl_running')
        }
    }
    return $closed
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

function Get-PclProcesses([string]$flavor = '') {
    $all = @(Get-Process -ErrorAction SilentlyContinue)
    if ($flavor -eq 'ce') {
        return @($all | Where-Object { $_.ProcessName -match '^(PCL2_CE|PCLCE|PCL CE|Plain Craft Launcher CE)' })
    }
    if ($flavor -eq 'pcl') {
        return @($all | Where-Object {
            $_.ProcessName -match '^(PCL|PCL2|Plain Craft Launcher)' -and
            $_.ProcessName -notmatch '^(PCL2_CE|PCLCE|PCL CE|Plain Craft Launcher CE)'
        })
    }
    return @($all | Where-Object { $_.ProcessName -match '^(PCL|PCL2|Plain Craft Launcher)' })
}

function Test-PclRunning([string]$flavor = '') {
    return (@(Get-PclProcesses $flavor).Count -gt 0)
}

# Ask first, then close only the selected launcher.  Other launcher instances
# (for example PCL CE while installing to PCL2) are deliberately left alone.
function Close-PclProcesses([string]$flavor) {
    $procs = @(Get-PclProcesses $flavor)
    if ($procs.Count -eq 0) { return $true }
    foreach ($p in $procs) {
        $sent = $false
        try {
            if ($p.MainWindowHandle -ne 0) { $sent = [bool]$p.CloseMainWindow() }
        } catch { }
        if (-not $sent) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-PclRunning $flavor)) { return $true }
        Start-Sleep -Milliseconds 200
    }
    foreach ($p in @(Get-PclProcesses $flavor)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
    }
    $deadline = (Get-Date).AddSeconds(4)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-PclRunning $flavor)) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return (-not (Test-PclRunning $flavor))
}

function Wait-PclClosed([string]$flavor = '') {
    if ($script:testMode) { return $true }
    if (-not (Test-PclRunning $flavor)) { return $true }
    if ($script:guiMode) { return $false }
    return (Confirm-ClosePcl $flavor)
}

function Stop-Watchers([string]$dir) {
    if ($script:testMode) { return }
    $me = $PID
    $needle = $dir.TrimEnd('\')
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.ProcessId -eq $me) { continue }
        $cl = [string]$p.CommandLine
        if ($cl -and
            $cl.IndexOf('RefreshLog.ps1', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $cl.IndexOf('-Watch', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $cl.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            try { Stop-Process -Id $p.ProcessId -Force } catch { }
        }
    }
    Start-Sleep -Milliseconds 400
}

# The watcher also refreshes this key, but update it directly as well so a
# missed old watcher (or a watcher that cannot start) can never leave the old
# console-subsystem command in the logon entry after a successful install.
function Set-WindowlessAutostart([string]$dir) {
    if ($script:testMode -or $env:PCLTOOLS_NO_AUTOSTART) { return }
    try {
        $vbs = Join-Path $dir 'PCLHomeLaunch.vbs'
        if (-not (Test-Path -LiteralPath $vbs)) { return }
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $cmd = 'wscript.exe //B //Nologo "' + $vbs + '" watch'
        Set-ItemProperty -Path $key -Name 'PCLCustomHomeWatch' -Value $cmd
        Remove-ItemProperty -Path $key -Name 'PCLCustomHomeVideoWall' -ErrorAction SilentlyContinue
    } catch { }
}

# ==== install / uninstall ====
function Get-Seg([string]$c, [string]$a, [string]$b) {
    $m = [regex]::Match($c, '(?sm)^@@YSM-TOOLS-' + [regex]::Escape($a) + '@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-' + [regex]::Escape($b) + '@@')
    if (-not $m.Success) { throw ('备份段缺失：' + $a) }
    return $m.Groups[1].Value
}

function Get-SegBytes([string]$c, [string]$a, [string]$b) {
    $s = Get-Seg $c $a $b
    $s = $s -replace '\s', ''
    return [Convert]::FromBase64String($s)
}

function Invoke-Install([string]$dir, [string]$flavor, [string]$lang = '') {
    $script:incompatiblePcl = $false
    $script:incompatiblePclVersion = ''
    $script:pclCloseCancelled = $false
    $flavor = Normalize-Flavor $flavor
    if (-not $flavor) { $flavor = Get-FlavorForDir $dir }
    if (-not $flavor) { Die ('无法判断要安装到 PCL2 还是 PCL CE：' + $dir) }

    # Preflight only.  Nothing has been written yet: do not wait for PCL to
    # close, stop a watcher, create a folder or touch the registry.  Returning
    # here therefore rolls back this install attempt completely.
    $versionState = Get-PclVersionState $dir $flavor
    if ($versionState.Unsupported) {
        Show-IncompatiblePcl $versionState
        return
    }

    if (-not (Wait-PclClosed $flavor)) {
        if ($script:pclCloseCancelled) { return }
        Die 'PCL 仍在运行，请退出 PCL / PCL CE 后再运行本安装器。'
    }
    if (-not $lang) { $lang = $script:homeLang }
    if (-not $lang) { $lang = Get-SystemGuiLanguage }
    Stop-Watchers $dir
    [void][IO.Directory]::CreateDirectory($dir)
    $cx = Join-Path $dir 'Custom.xaml'
    $c = [Text.Encoding]::UTF8.GetString($data)
    $c = Localize-CustomPage $c $lang
    [IO.File]::WriteAllText($cx, $c, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'CustomTools.bat'), (Get-Seg $c 'BAT' 'PS1'), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'RefreshLog.ps1'), (Get-Seg $c 'PS1' 'PS2'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'BgRefresh.ps1'), (Get-Seg $c 'PS2' 'PS3'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'Egg.ps1'), (Get-Seg $c 'PS3' 'PS4'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'VideoWall.ps1'), (Get-Seg $c 'PS4' 'PS5'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'CommandManager.ps1'), (Get-Seg $c 'PS5' 'PS6'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'Online.ps1'), (Get-Seg $c 'PS6' 'VBS'), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $dir 'PCLHomeLaunch.vbs'), (Get-Seg $c 'VBS' 'WVB1'), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'CommandManager.lang'), ($lang + "`r`n"), [Text.UTF8Encoding]::new($false))
    foreach ($old in @('InjectDll.ps1', 'InjectDll.lock')) {
        try { Remove-Item -LiteralPath (Join-Path $dir $old) -Force -ErrorAction SilentlyContinue } catch { }
    }
    $wvDir = Join-Path $dir 'WebView2'
    [void][IO.Directory]::CreateDirectory($wvDir)
    try { [IO.File]::WriteAllBytes((Join-Path $wvDir 'Microsoft.Web.WebView2.Core.dll'), (Get-SegBytes $c 'WVB1' 'WVB2')) } catch { }
    try { [IO.File]::WriteAllBytes((Join-Path $wvDir 'Microsoft.Web.WebView2.WinForms.dll'), (Get-SegBytes $c 'WVB2' 'WVB3')) } catch { }
    try { [IO.File]::WriteAllBytes((Join-Path $wvDir 'WebView2Loader.dll'), (Get-SegBytes $c 'WVB3' 'IMG')) } catch { }
    $picDir = Join-Path $dir 'Pictures'
    [void][IO.Directory]::CreateDirectory($picDir)
    $img = Get-Seg $c 'IMG' 'END'
    [IO.File]::WriteAllBytes((Join-Path $picDir 'CustomHomeBG.jpg'), [Convert]::FromBase64String(($img -replace '\s', '')))
    if ($img2) { [IO.File]::WriteAllBytes((Join-Path $picDir 'videoframe_2546.png'), $img2) }
    if ($lockImg) { [IO.File]::WriteAllBytes((Join-Path $picDir 'CustomHomeLock.png'), $lockImg) }
    Update-SelectedConfig $dir $flavor
    $env:PCLTOOLS_NO_REFRESH = '1'
    try {
        if ($script:guiMode) {
            # wscript.exe is a GUI-subsystem program; PCLHomeLaunch.vbs starts
            # PowerShell with window style 0.  No console is created.
            $refresh = Start-Process -FilePath 'wscript.exe' -ArgumentList ('//B //Nologo "' + (Join-Path $dir 'PCLHomeLaunch.vbs') + '" refresh') -WindowStyle Hidden -Wait -PassThru
            if ($refresh.ExitCode -ne 0) { throw 'LogView.xaml 生成失败' }
        } else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'RefreshLog.ps1') $dir | Out-Null
        }
    } finally {
        Remove-Item Env:\PCLTOOLS_NO_REFRESH -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'LogView.xaml'))) { throw 'LogView.xaml 生成失败' }
    Set-WindowlessAutostart $dir
    if (-not $script:testMode -and -not $env:PCLTOOLS_NO_WATCH) {
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('//B //Nologo "' + (Join-Path $dir 'PCLHomeLaunch.vbs') + '" watch') -WindowStyle Hidden | Out-Null
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
    $script:pclCloseCancelled = $false
    $flavor = Normalize-Flavor $flavor
    if (-not $flavor) { $flavor = Get-FlavorForDir $dir }
    if (-not $script:testMode -and -not $script:guiMode) {
        $a = Read-Host ('确定要从 ' + $dir + ' 卸载自定义主页吗？输入 y 回车确认')
        if ($a -notmatch '^\s*y') { Say '已取消。'; return }
    }
    if (-not (Wait-PclClosed $flavor)) {
        if ($script:pclCloseCancelled) { return }
        Die 'PCL 仍在运行，请退出 PCL / PCL CE 后再卸载。'
    }
    Stop-Watchers $dir
    if (-not $script:testMode) {
        foreach ($n in @('PCLCustomHomeWatch', 'PCLCustomHomeVideoWall')) {
            try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $n -ErrorAction SilentlyContinue } catch { }
        }
    }
    foreach ($f in @('Custom.xaml', 'LogView.xaml', 'CustomTools.bat', 'PCLHomeLaunch.vbs', 'RefreshLog.ps1', 'BgRefresh.ps1', 'Egg.ps1', 'VideoWall.ps1', 'CommandManager.ps1', 'Online.ps1', 'CommandManager.lang', 'CustomCommandTarget.json', 'CustomTools.log', 'VideoWall.ready', 'Pictures\CustomHomeBG.jpg', 'Pictures\videoframe_2546.png', 'Pictures\CustomHomeLock.png')) {
        try { Remove-Item -LiteralPath ($dir + '\' + $f) -Force -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-Item -LiteralPath ($dir + '\WebView2') -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    # Terracotta itself is a separate program the user may also run from HMCL,
    # so only the copy this installer downloaded is removed.
    foreach ($f in @(Get-ChildItem -LiteralPath ($dir + '\Online') -Filter 'terracotta*.exe' -File -ErrorAction SilentlyContinue) +
                    @(Get-ChildItem -LiteralPath ($dir + '\Online') -Filter 'VCRUNTIME140.DLL' -File -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-Item -LiteralPath ($dir + '\Online') -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item -LiteralPath ($dir + '\VideoWall') -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Reset-UiCustomType $dir $flavor
    Say ''
    Say ('已卸载：' + $dir)
    Say ('恢复的启动器：' + (Get-FlavorLabel $flavor))
    Say '（自带主页会恢复正常；如启动器正在运行，请重启它。界面设置保持不变。）'
}

# ==== GUI installer ====
$script:languageCodes = @('zh-CN', 'en', 'zh-TW', 'ja', 'ko', 'fr', 'de', 'es', 'pt-BR', 'ru', 'it', 'nl', 'pl', 'tr', 'vi')
$script:languageNames = @{
    'zh-CN' = '简体中文'
    'en'    = 'English'
    'zh-TW' = '繁體中文'
    'ja'    = '日本語'
    'ko'    = '한국어'
    'fr'    = 'Français'
    'de'    = 'Deutsch'
    'es'    = 'Español'
    'pt-BR' = 'Português (Brasil)'
    'ru'    = 'Русский'
    'it'    = 'Italiano'
    'nl'    = 'Nederlands'
    'pl'    = 'Polski'
    'tr'    = 'Türkçe'
    'vi'    = 'Tiếng Việt'
}

$script:guiText = @{
    'en' = @{
        app_title = 'PCL Custom Homepage Installer'
        app_subtitle = 'Supports PCL2 / PCL CE · Local install · 15 languages'
        step_launcher = 'Choose launcher'
        step_launcher_hint = 'Select the launcher to install to.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Original PCL2 · uses Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Community Edition · uses config.v1.yml'
        step_folder = 'Choose data folder'
        folder_hint = 'Folder with Setup.ini or config.v1.yml; the launcher root also works.'
        path_cue = 'e.g. D:\PCL-CE\PCL'
        browse = 'Browse...'
        detect = 'Detect'
        install = 'Install'
        reinstall = 'Reinstall'
        uninstall = 'Uninstall'
        exit = 'Exit'
        status_ready = 'Choose a launcher and data folder.'
        status_detected = 'Detected: {0} · {1}'
        status_folder_ready = 'Data folder ready: {0}'
        status_not_found = 'No PCL data folder found. Check the path.'
        status_switched = 'This folder belongs to {0}; switched automatically.'
        status_installing = 'Installing, please wait...'
        status_uninstalling = 'Uninstalling, please wait...'
        status_installed = 'Installed: {0}'
        status_uninstalled = 'Uninstalled: {0}'
        status_failed = 'Operation failed: {0}'
        confirm_overwrite_title = 'Already installed'
        confirm_overwrite = "A custom homepage is already installed.`n`nReinstall, or uninstall?"
        confirm_uninstall_title = 'Uninstall custom homepage'
        confirm_uninstall = "Remove the custom homepage from this folder?`n`n{0}`n`nThe launcher will return to its built-in homepage. Other UI settings are unchanged."
        pcl_running_title = 'Launcher is running'
        pcl_running = 'Fully exit PCL2 / PCL CE, then try again.'
        confirm_close_pcl = "Do you want me to close it?"
        status_closing_pcl = "Closing the selected launcher, please wait..."
        not_installed = 'The custom homepage is not installed in this folder.'
        select_target = 'Select a valid PCL data folder.'
        error_title = 'Installation failed'
        error_generic = 'Installation failed. Make sure the launcher is closed and the folder is writable, then retry.'
        err_running = 'PCL is still running. Exit it and retry.'
        err_flavor = 'Could not determine whether this folder is PCL2 or PCL CE.'
        err_logview = 'Failed to generate LogView.xaml.'
        err_payload = 'The installer package is incomplete or corrupted.'
        done_title = 'Done'
        done_install = "The custom homepage is installed.`n`n{0}`n`nOpen the launcher to see it. If it is already open, press F5 or reopen it."
        done_uninstall = "The custom homepage is uninstalled.`n`n{0}`n`nThe launcher will return to its built-in homepage. Restart it if it is running."
        browse_desc_pcl = 'Select the PCL2 data folder (contains Setup.ini)'
        browse_desc_ce = 'Select the PCL CE data folder (contains config.v1.yml)'
        browse_desc_any = 'Select the PCL data folder (contains Setup.ini or config.v1.yml)'
        footer = 'PCL Custom Homepage · v1.4 · 15 languages · only the selected launcher config is modified'
        incompatible_pcl = "Installing a custom homepage for this PCL version is no longer meaningful.`nNo changes have been made to your computer."
        status_incompatible = "This PCL version is not supported. No changes were made."
        flavor_pcl = 'PCL2 (Original)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Language'
        home_lang_note = 'Homepage: {0}'
    }
    'zh-CN' = @{
        app_title = 'PCL 自定义主页安装器'
        app_subtitle = '支持 PCL2 / PCL CE · 本地安装 · 15 种语言'
        step_launcher = '选择启动器'
        step_launcher_hint = '请选择要安装到的启动器。'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = '原版 PCL2 · 使用 Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = '社区版 · 使用 config.v1.yml'
        step_folder = '选择数据文件夹'
        folder_hint = '选择包含 Setup.ini 或 config.v1.yml 的 PCL 文件夹；也可以直接选择启动器根目录。'
        path_cue = '例如：D:\PCL-CE\PCL'
        browse = '浏览...'
        detect = '检测'
        install = '安装'
        reinstall = '覆盖安装'
        uninstall = '卸载'
        exit = '退出'
        status_ready = '请选择启动器和数据文件夹。'
        status_detected = '已识别：{0} · {1}'
        status_folder_ready = '数据文件夹已就绪：{0}'
        status_not_found = '未识别到 PCL 数据文件夹，请检查路径。'
        status_switched = '检测到该文件夹属于 {0}，已自动切换。'
        status_installing = '正在安装，请稍候...'
        status_uninstalling = '正在卸载，请稍候...'
        status_installed = '安装完成：{0}'
        status_uninstalled = '卸载完成：{0}'
        status_failed = '操作失败：{0}'
        confirm_overwrite_title = '已安装'
        confirm_overwrite = "该文件夹已经安装了自定义主页。`n`n要覆盖安装，还是卸载？"
        confirm_uninstall_title = '卸载自定义主页'
        confirm_uninstall = "确定要从以下文件夹卸载自定义主页吗？`n`n{0}`n`n卸载后启动器会恢复自带主页，其他界面设置保持不变。"
        pcl_running_title = '启动器正在运行'
        pcl_running = '请先完全退出 PCL2 / PCL CE，然后重试。'
        confirm_close_pcl = "要不要帮你关闭"
        status_closing_pcl = "正在关闭所选的启动器，请稍候..."
        not_installed = '该文件夹没有安装自定义主页。'
        select_target = '请选择有效的 PCL 数据文件夹。'
        error_title = '安装失败'
        error_generic = '安装失败。请确认启动器已退出、文件夹可写后重试。'
        err_running = 'PCL 仍在运行，请退出后重试。'
        err_flavor = '无法判断该文件夹是 PCL2 还是 PCL CE。'
        err_logview = 'LogView.xaml 生成失败。'
        err_payload = '安装包不完整或已损坏。'
        done_title = '完成'
        done_install = "自定义主页已安装。`n`n{0}`n`n打开启动器即可看到新主页；如果启动器已经打开，请按 F5 刷新或重新打开。"
        done_uninstall = "自定义主页已卸载。`n`n{0}`n`n启动器会恢复自带主页；如果它正在运行，请重启。"
        browse_desc_pcl = '请选择 PCL2 的数据文件夹（包含 Setup.ini）'
        browse_desc_ce = '请选择 PCL CE 的数据文件夹（包含 config.v1.yml）'
        browse_desc_any = '请选择 PCL 数据文件夹（包含 Setup.ini 或 config.v1.yml）'
        footer = 'PCL 自定义主页 · v1.4 · 15 种语言 · 仅修改所选启动器的配置'
        incompatible_pcl = "你这个版本的PCL安装主页已经没有意义了`n未对您的计算机进行更改"
        status_incompatible = "不支持此 PCL 版本。未对计算机进行更改。"
        flavor_pcl = 'PCL2（原版）'
        flavor_ce = 'PCL CE'
        lang_caption = '语言'
        home_lang_note = '主页语言：{0}'
    }
    'zh-TW' = @{
        app_title = 'PCL 自訂主頁安裝器'
        app_subtitle = '支援 PCL2 / PCL CE · 本機安裝 · 15 種語言'
        step_launcher = '選擇啟動器'
        step_launcher_hint = '請選擇要安裝到的啟動器。'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = '原版 PCL2 · 使用 Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = '社群版 · 使用 config.v1.yml'
        step_folder = '選擇資料夾'
        folder_hint = '選擇包含 Setup.ini 或 config.v1.yml 的 PCL 資料夾；也可以直接選擇啟動器根目錄。'
        path_cue = '例如：D:\PCL-CE\PCL'
        browse = '瀏覽...'
        detect = '偵測'
        install = '安裝'
        reinstall = '覆蓋安裝'
        uninstall = '解除安裝'
        exit = '結束'
        status_ready = '請選擇啟動器和資料夾。'
        status_detected = '已辨識：{0} · {1}'
        status_folder_ready = '資料夾已就緒：{0}'
        status_not_found = '找不到 PCL 資料夾，請檢查路徑。'
        status_switched = '偵測到資料夾屬於 {0}，已自動切換。'
        status_installing = '正在安裝，請稍候...'
        status_uninstalling = '正在解除安裝，請稍候...'
        status_installed = '安裝完成：{0}'
        status_uninstalled = '解除安裝完成：{0}'
        status_failed = '操作失敗：{0}'
        confirm_overwrite_title = '已安裝'
        confirm_overwrite = "此資料夾已安裝自訂主頁。`n`n要覆蓋安裝，還是解除安裝？"
        confirm_uninstall_title = '解除安裝自訂主頁'
        confirm_uninstall = "確定要從以下資料夾解除安裝自訂主頁嗎？`n`n{0}`n`n解除安裝後啟動器會恢復內建主頁，其他介面設定保持不變。"
        pcl_running_title = '啟動器正在執行'
        pcl_running = '請先完全結束 PCL2 / PCL CE，然後再試一次。'
        confirm_close_pcl = "要不要幫你關閉？"
        status_closing_pcl = "正在關閉所選的啟動器，請稍候..."
        not_installed = '此資料夾沒有安裝自訂主頁。'
        select_target = '請選擇有效的 PCL 資料夾。'
        error_title = '安裝失敗'
        error_generic = '安裝失敗。請確認啟動器已結束、資料夾可寫入後再試一次。'
        err_running = 'PCL 仍在執行，請結束後再試一次。'
        err_flavor = '無法判斷此資料夾是 PCL2 還是 PCL CE。'
        err_logview = 'LogView.xaml 產生失敗。'
        err_payload = '安裝包不完整或已損壞。'
        done_title = '完成'
        done_install = "自訂主頁已安裝。`n`n{0}`n`n開啟啟動器即可看到新主頁；如果啟動器已開啟，請按 F5 重新整理或重新開啟。"
        done_uninstall = "自訂主頁已解除安裝。`n`n{0}`n`n啟動器會恢復內建主頁；如果它正在執行，請重新啟動。"
        browse_desc_pcl = '請選擇 PCL2 的資料夾（包含 Setup.ini）'
        browse_desc_ce = '請選擇 PCL CE 的資料夾（包含 config.v1.yml）'
        browse_desc_any = '請選擇 PCL 資料夾（包含 Setup.ini 或 config.v1.yml）'
        footer = 'PCL 自訂主頁 · v1.4 · 15 種語言 · 僅修改所選啟動器的設定'
        incompatible_pcl = "你這個版本的 PCL 安裝主頁已經沒有意義了`n未對您的電腦進行任何變更"
        status_incompatible = "不支援此 PCL 版本。未對電腦進行任何變更。"
        flavor_pcl = 'PCL2（原版）'
        flavor_ce = 'PCL CE'
        lang_caption = '語言'
        home_lang_note = '主頁語言：{0}'
    }
    'ja' = @{
        app_title = 'PCL ホームページ インストーラー'
        app_subtitle = 'PCL2 / PCL CE 対応 · ローカルインストール · 15 言語'
        step_launcher = 'ランチャーを選択'
        step_launcher_hint = 'インストール先のランチャーを選択してください。'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'オリジナル PCL2 · Setup.ini を使用'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'コミュニティ版 · config.v1.yml を使用'
        step_folder = 'データフォルダーを選択'
        folder_hint = 'Setup.ini または config.v1.yml を含む PCL フォルダー（ランチャーのルートも可）。'
        path_cue = '例：D:\PCL-CE\PCL'
        browse = '参照...'
        detect = '検出'
        install = 'インストール'
        reinstall = '上書きインストール'
        uninstall = 'アンインストール'
        exit = '終了'
        status_ready = 'ランチャーとデータフォルダーを選択してください。'
        status_detected = '検出：{0} · {1}'
        status_folder_ready = 'データフォルダーの準備ができました：{0}'
        status_not_found = 'PCL データフォルダーが見つかりません。パスを確認してください。'
        status_switched = 'このフォルダーは {0} のものです。自動的に切り替えました。'
        status_installing = 'インストール中です。お待ちください...'
        status_uninstalling = 'アンインストール中です。お待ちください...'
        status_installed = 'インストール完了：{0}'
        status_uninstalled = 'アンインストール完了：{0}'
        status_failed = '操作に失敗しました：{0}'
        confirm_overwrite_title = 'インストール済み'
        confirm_overwrite = "このフォルダーには既にカスタムホームページがインストールされています。`n`n上書きインストールしますか、それともアンインストールしますか？"
        confirm_uninstall_title = 'カスタムホームページをアンインストール'
        confirm_uninstall = "次のフォルダーからカスタムホームページをアンインストールしますか？`n`n{0}`n`nランチャーは標準のホームページに戻ります。他の UI 設定は変更されません。"
        pcl_running_title = 'ランチャーが実行中です'
        pcl_running = 'PCL2 / PCL CE を完全に終了してから、もう一度お試しください。'
        confirm_close_pcl = "閉じてもいいですか？"
        status_closing_pcl = "選択したランチャーを終了しています。お待ちください..."
        not_installed = 'このフォルダーにはカスタムホームページがインストールされていません。'
        select_target = '有効な PCL データフォルダーを選択してください。'
        error_title = 'インストールに失敗しました'
        error_generic = 'インストールに失敗しました。ランチャーを終了し、フォルダーに書き込み権限があることを確認して再試行してください。'
        err_running = 'PCL がまだ実行中です。終了してから再試行してください。'
        err_flavor = 'このフォルダーが PCL2 か PCL CE かを判定できません。'
        err_logview = 'LogView.xaml の生成に失敗しました。'
        err_payload = 'インストーラーパッケージが不完全または破損しています。'
        done_title = '完了'
        done_install = "カスタムホームページをインストールしました。`n`n{0}`n`nランチャーを開いて確認してください。既に開いている場合は F5 または再起動してください。"
        done_uninstall = "カスタムホームページをアンインストールしました。`n`n{0}`n`nランチャーは標準のホームページに戻ります。実行中の場合は再起動してください。"
        browse_desc_pcl = 'PCL2 のデータフォルダーを選択（Setup.ini を含む）'
        browse_desc_ce = 'PCL CE のデータフォルダーを選択（config.v1.yml を含む）'
        browse_desc_any = 'PCL データフォルダーを選択（Setup.ini または config.v1.yml を含む）'
        footer = 'PCL カスタムホームページ · v1.4 · 15 言語 · 選択したランチャーの設定のみ変更'
        incompatible_pcl = "このバージョンの PCL では、カスタムホームページをインストールしても意味がありません。`nコンピューターには何も変更を加えていません。"
        status_incompatible = "この PCL バージョンはサポートされていません。変更は行われていません。"
        flavor_pcl = 'PCL2（オリジナル）'
        flavor_ce = 'PCL CE'
        lang_caption = '言語'
        home_lang_note = 'ホームページ：{0}'
    }
    'ko' = @{
        app_title = 'PCL 홈페이지 설치 프로그램'
        app_subtitle = 'PCL2 / PCL CE 지원 · 로컬 설치 · 15개 언어'
        step_launcher = '런처 선택'
        step_launcher_hint = '설치할 런처를 선택하세요.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = '원본 PCL2 · Setup.ini 사용'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = '커뮤니티 에디션 · config.v1.yml 사용'
        step_folder = '데이터 폴더 선택'
        folder_hint = 'Setup.ini 또는 config.v1.yml이 있는 PCL 폴더 (런처 루트도 가능).'
        path_cue = '예: D:\PCL-CE\PCL'
        browse = '찾아보기...'
        detect = '감지'
        install = '설치'
        reinstall = '덮어쓰기 설치'
        uninstall = '제거'
        exit = '종료'
        status_ready = '런처와 데이터 폴더를 선택하세요.'
        status_detected = '감지됨: {0} · {1}'
        status_folder_ready = '데이터 폴더가 준비되었습니다: {0}'
        status_not_found = 'PCL 데이터 폴더를 찾을 수 없습니다. 경로를 확인하세요.'
        status_switched = '이 폴더는 {0}에 속합니다. 자동으로 전환했습니다.'
        status_installing = '설치하는 중입니다. 잠시만 기다려 주세요...'
        status_uninstalling = '제거하는 중입니다. 잠시만 기다려 주세요...'
        status_installed = '설치 완료: {0}'
        status_uninstalled = '제거 완료: {0}'
        status_failed = '작업 실패: {0}'
        confirm_overwrite_title = '이미 설치됨'
        confirm_overwrite = "이 폴더에는 이미 사용자 지정 홈페이지가 설치되어 있습니다.`n`n덮어쓰기 설치할까요, 아니면 제거할까요?"
        confirm_uninstall_title = '사용자 지정 홈페이지 제거'
        confirm_uninstall = "다음 폴더에서 사용자 지정 홈페이지를 제거할까요?`n`n{0}`n`n런처는 기본 홈페이지로 돌아갑니다. 다른 UI 설정은 변경되지 않습니다."
        pcl_running_title = '런처가 실행 중입니다'
        pcl_running = 'PCL2 / PCL CE를 완전히 종료한 후 다시 시도하세요.'
        confirm_close_pcl = "종료해 드릴까요?"
        status_closing_pcl = "선택한 런처를 종료하는 중입니다. 잠시만 기다려 주세요..."
        not_installed = '이 폴더에는 사용자 지정 홈페이지가 설치되어 있지 않습니다.'
        select_target = '올바른 PCL 데이터 폴더를 선택하세요.'
        error_title = '설치 실패'
        error_generic = '설치에 실패했습니다. 런처를 종료하고 폴더에 쓸 수 있는지 확인한 후 다시 시도하세요.'
        err_running = 'PCL이 아직 실행 중입니다. 종료한 후 다시 시도하세요.'
        err_flavor = '이 폴더가 PCL2인지 PCL CE인지 확인할 수 없습니다.'
        err_logview = 'LogView.xaml 생성에 실패했습니다.'
        err_payload = '설치 패키지가 불완전하거나 손상되었습니다.'
        done_title = '완료'
        done_install = "사용자 지정 홈페이지가 설치되었습니다.`n`n{0}`n`n런처를 열어 확인하세요. 이미 열려 있으면 F5를 누르거나 다시 여세요."
        done_uninstall = "사용자 지정 홈페이지가 제거되었습니다.`n`n{0}`n`n런처는 기본 홈페이지로 돌아갑니다. 실행 중이면 다시 시작하세요."
        browse_desc_pcl = 'PCL2 데이터 폴더 선택 (Setup.ini 포함)'
        browse_desc_ce = 'PCL CE 데이터 폴더 선택 (config.v1.yml 포함)'
        browse_desc_any = 'PCL 데이터 폴더 선택 (Setup.ini 또는 config.v1.yml 포함)'
        footer = 'PCL 사용자 지정 홈페이지 · v1.4 · 15개 언어 · 선택한 런처 설정만 수정'
        incompatible_pcl = "이 버전의 PCL에서는 사용자 지정 홈페이지를 설치해도 의미가 없습니다.`n컴퓨터에 아무런 변경도 적용하지 않았습니다."
        status_incompatible = "이 PCL 버전은 지원되지 않습니다. 변경 사항은 없습니다."
        flavor_pcl = 'PCL2 (원본)'
        flavor_ce = 'PCL CE'
        lang_caption = '언어'
        home_lang_note = '홈페이지: {0}'
    }
    'fr' = @{
        app_title = 'Installateur de page d''accueil PCL'
        app_subtitle = 'PCL2 / PCL CE · Installation locale · 15 langues'
        step_launcher = 'Choisir le lanceur'
        step_launcher_hint = 'Sélectionnez le lanceur à installer.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'PCL2 original · utilise Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Édition communautaire · utilise config.v1.yml'
        step_folder = 'Choisir le dossier de données'
        folder_hint = 'Dossier contenant Setup.ini ou config.v1.yml ; la racine du lanceur convient aussi.'
        path_cue = 'ex. : D:\PCL-CE\PCL'
        browse = 'Parcourir...'
        detect = 'Détecter'
        install = 'Installer'
        reinstall = 'Réinstaller'
        uninstall = 'Désinstaller'
        exit = 'Quitter'
        status_ready = 'Choisissez un lanceur et un dossier de données.'
        status_detected = 'Détecté : {0} · {1}'
        status_folder_ready = 'Dossier de données prêt : {0}'
        status_not_found = 'Aucun dossier de données PCL trouvé. Vérifiez le chemin.'
        status_switched = 'Ce dossier appartient à {0} ; changement automatique.'
        status_installing = 'Installation en cours...'
        status_uninstalling = 'Désinstallation en cours...'
        status_installed = 'Installé : {0}'
        status_uninstalled = 'Désinstallé : {0}'
        status_failed = 'Échec de l''opération : {0}'
        confirm_overwrite_title = 'Déjà installé'
        confirm_overwrite = "Une page d''accueil personnalisée est déjà installée.`n`nRéinstaller ou désinstaller ?"
        confirm_uninstall_title = 'Désinstaller la page d''accueil'
        confirm_uninstall = "Supprimer la page d''accueil personnalisée de ce dossier ?`n`n{0}`n`nLe lanceur retrouvera sa page d''accueil intégrée. Les autres réglages d''interface restent inchangés."
        pcl_running_title = 'Le lanceur est en cours d''exécution'
        pcl_running = 'Quittez complètement PCL2 / PCL CE, puis réessayez.'
        confirm_close_pcl = "Voulez-vous que je le ferme ?"
        status_closing_pcl = "Fermeture du lanceur sélectionné..."
        not_installed = 'La page d''accueil personnalisée n''est pas installée dans ce dossier.'
        select_target = 'Sélectionnez un dossier de données PCL valide.'
        error_title = 'Échec de l''installation'
        error_generic = 'L''installation a échoué. Vérifiez que le lanceur est fermé et que le dossier est accessible en écriture, puis réessayez.'
        err_running = 'PCL est toujours en cours d''exécution. Quittez-le et réessayez.'
        err_flavor = 'Impossible de déterminer si ce dossier est PCL2 ou PCL CE.'
        err_logview = 'Échec de la génération de LogView.xaml.'
        err_payload = 'Le package d''installation est incomplet ou corrompu.'
        done_title = 'Terminé'
        done_install = "La page d''accueil personnalisée est installée.`n`n{0}`n`nOuvrez le lanceur pour la voir. S''il est déjà ouvert, appuyez sur F5 ou rouvrez-le."
        done_uninstall = "La page d''accueil personnalisée est désinstallée.`n`n{0}`n`nLe lanceur retrouvera sa page d''accueil intégrée. Redémarrez-le s''il est en cours d''exécution."
        browse_desc_pcl = 'Sélectionnez le dossier de données PCL2 (contient Setup.ini)'
        browse_desc_ce = 'Sélectionnez le dossier de données PCL CE (contient config.v1.yml)'
        browse_desc_any = 'Sélectionnez le dossier de données PCL (contient Setup.ini ou config.v1.yml)'
        footer = 'Page d''accueil PCL · v1.4 · 15 langues · seul le profil du lanceur choisi est modifié'
        incompatible_pcl = "Installer une page d'accueil personnalisée pour cette version de PCL n'a plus de sens.`nAucune modification n'a été apportée à votre ordinateur."
        status_incompatible = "Cette version de PCL n'est pas prise en charge. Aucune modification n'a été apportée."
        flavor_pcl = 'PCL2 (original)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Langue'
        home_lang_note = 'Page d''accueil : {0}'
    }
    'de' = @{
        app_title = 'PCL Startseiten-Installation'
        app_subtitle = 'PCL2 / PCL CE · Lokale Installation · 15 Sprachen'
        step_launcher = 'Launcher auswählen'
        step_launcher_hint = 'Wähle den Launcher, in den installiert werden soll.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Original PCL2 · verwendet Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Community Edition · verwendet config.v1.yml'
        step_folder = 'Datenordner auswählen'
        folder_hint = 'Ordner mit Setup.ini oder config.v1.yml; der Launcher-Stammordner geht auch.'
        path_cue = 'z. B. D:\PCL-CE\PCL'
        browse = 'Durchsuchen...'
        detect = 'Erkennen'
        install = 'Installieren'
        reinstall = 'Neu installieren'
        uninstall = 'Deinstallieren'
        exit = 'Beenden'
        status_ready = 'Wähle einen Launcher und einen Datenordner.'
        status_detected = 'Erkannt: {0} · {1}'
        status_folder_ready = 'Datenordner bereit: {0}'
        status_not_found = 'Kein PCL-Datenordner gefunden. Prüfe den Pfad.'
        status_switched = 'Dieser Ordner gehört zu {0}; automatisch umgeschaltet.'
        status_installing = 'Installation läuft, bitte warten...'
        status_uninstalling = 'Deinstallation läuft, bitte warten...'
        status_installed = 'Installiert: {0}'
        status_uninstalled = 'Deinstalliert: {0}'
        status_failed = 'Vorgang fehlgeschlagen: {0}'
        confirm_overwrite_title = 'Bereits installiert'
        confirm_overwrite = "In diesem Ordner ist bereits eine benutzerdefinierte Startseite installiert.`n`nNeu installieren oder deinstallieren?"
        confirm_uninstall_title = 'Benutzerdefinierte Startseite deinstallieren'
        confirm_uninstall = "Die benutzerdefinierte Startseite aus diesem Ordner entfernen?`n`n{0}`n`nDer Launcher kehrt zu seiner integrierten Startseite zurück. Andere UI-Einstellungen bleiben unverändert."
        pcl_running_title = 'Launcher läuft'
        pcl_running = 'Beende PCL2 / PCL CE vollständig und versuche es erneut.'
        confirm_close_pcl = "Soll ich es für dich schließen?"
        status_closing_pcl = "Der ausgewählte Launcher wird geschlossen..."
        not_installed = 'In diesem Ordner ist keine benutzerdefinierte Startseite installiert.'
        select_target = 'Wähle einen gültigen PCL-Datenordner.'
        error_title = 'Installation fehlgeschlagen'
        error_generic = 'Die Installation ist fehlgeschlagen. Stelle sicher, dass der Launcher geschlossen ist und der Ordner beschreibbar ist, und versuche es erneut.'
        err_running = 'PCL läuft noch. Beende es und versuche es erneut.'
        err_flavor = 'Es konnte nicht ermittelt werden, ob dieser Ordner zu PCL2 oder PCL CE gehört.'
        err_logview = 'LogView.xaml konnte nicht erzeugt werden.'
        err_payload = 'Das Installationspaket ist unvollständig oder beschädigt.'
        done_title = 'Fertig'
        done_install = "Die benutzerdefinierte Startseite wurde installiert.`n`n{0}`n`nÖffne den Launcher, um sie zu sehen. Wenn er bereits geöffnet ist, drücke F5 oder öffne ihn neu."
        done_uninstall = "Die benutzerdefinierte Startseite wurde deinstalliert.`n`n{0}`n`nDer Launcher kehrt zu seiner integrierten Startseite zurück. Starte ihn neu, falls er läuft."
        browse_desc_pcl = 'PCL2-Datenordner auswählen (enthält Setup.ini)'
        browse_desc_ce = 'PCL CE-Datenordner auswählen (enthält config.v1.yml)'
        browse_desc_any = 'PCL-Datenordner auswählen (enthält Setup.ini oder config.v1.yml)'
        footer = 'PCL Startseite · v1.4 · 15 Sprachen · nur die Konfiguration des gewählten Launchers wird geändert'
        incompatible_pcl = "Das Installieren einer benutzerdefinierten Startseite für diese PCL-Version ist nicht mehr sinnvoll.`nEs wurden keine Änderungen an Ihrem Computer vorgenommen."
        status_incompatible = "Diese PCL-Version wird nicht unterstützt. Es wurden keine Änderungen vorgenommen."
        flavor_pcl = 'PCL2 (Original)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Sprache'
        home_lang_note = 'Startseite: {0}'
    }
    'es' = @{
        app_title = 'Instalador de inicio PCL'
        app_subtitle = 'PCL2 / PCL CE · Instalación local · 15 idiomas'
        step_launcher = 'Elegir lanzador'
        step_launcher_hint = 'Selecciona el lanzador donde instalar.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'PCL2 original · usa Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Edición comunitaria · usa config.v1.yml'
        step_folder = 'Elegir carpeta de datos'
        folder_hint = 'Carpeta con Setup.ini o config.v1.yml; también sirve la raíz del lanzador.'
        path_cue = 'p. ej.: D:\PCL-CE\PCL'
        browse = 'Examinar...'
        detect = 'Detectar'
        install = 'Instalar'
        reinstall = 'Reinstalar'
        uninstall = 'Desinstalar'
        exit = 'Salir'
        status_ready = 'Elige un lanzador y una carpeta de datos.'
        status_detected = 'Detectado: {0} · {1}'
        status_folder_ready = 'Carpeta de datos lista: {0}'
        status_not_found = 'No se encontró una carpeta de datos de PCL. Comprueba la ruta.'
        status_switched = 'Esta carpeta pertenece a {0}; se cambió automáticamente.'
        status_installing = 'Instalando, espera...'
        status_uninstalling = 'Desinstalando, espera...'
        status_installed = 'Instalado: {0}'
        status_uninstalled = 'Desinstalado: {0}'
        status_failed = 'Error en la operación: {0}'
        confirm_overwrite_title = 'Ya instalado'
        confirm_overwrite = "Ya hay una página de inicio personalizada instalada en esta carpeta.`n`n¿Reinstalar o desinstalar?"
        confirm_uninstall_title = 'Desinstalar la página de inicio'
        confirm_uninstall = "¿Quitar la página de inicio personalizada de esta carpeta?`n`n{0}`n`nEl lanzador volverá a su página de inicio integrada. Los demás ajustes de la interfaz no cambian."
        pcl_running_title = 'El lanzador está en ejecución'
        pcl_running = 'Cierra completamente PCL2 / PCL CE y vuelve a intentarlo.'
        confirm_close_pcl = "¿Quieres que lo cierre?"
        status_closing_pcl = "Cerrando el lanzador seleccionado..."
        not_installed = 'La página de inicio personalizada no está instalada en esta carpeta.'
        select_target = 'Selecciona una carpeta de datos de PCL válida.'
        error_title = 'Error de instalación'
        error_generic = 'La instalación falló. Comprueba que el lanzador esté cerrado y que se pueda escribir en la carpeta, y vuelve a intentarlo.'
        err_running = 'PCL sigue en ejecución. Ciérralo y vuelve a intentarlo.'
        err_flavor = 'No se pudo determinar si esta carpeta es de PCL2 o PCL CE.'
        err_logview = 'No se pudo generar LogView.xaml.'
        err_payload = 'El paquete de instalación está incompleto o dañado.'
        done_title = 'Listo'
        done_install = "La página de inicio personalizada se ha instalado.`n`n{0}`n`nAbre el lanzador para verla. Si ya está abierto, pulsa F5 o vuelve a abrirlo."
        done_uninstall = "La página de inicio personalizada se ha desinstalado.`n`n{0}`n`nEl lanzador volverá a su página de inicio integrada. Reinícialo si está en ejecución."
        browse_desc_pcl = 'Selecciona la carpeta de datos de PCL2 (contiene Setup.ini)'
        browse_desc_ce = 'Selecciona la carpeta de datos de PCL CE (contiene config.v1.yml)'
        browse_desc_any = 'Selecciona la carpeta de datos de PCL (contiene Setup.ini o config.v1.yml)'
        footer = 'Página de inicio PCL · v1.4 · 15 idiomas · solo se modifica la configuración del lanzador elegido'
        incompatible_pcl = "Instalar una página de inicio personalizada para esta versión de PCL ya no tiene sentido.`nNo se ha realizado ningún cambio en su equipo."
        status_incompatible = "Esta versión de PCL no es compatible. No se realizó ningún cambio."
        flavor_pcl = 'PCL2 (original)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Idioma'
        home_lang_note = 'Página de inicio: {0}'
    }
    'pt-BR' = @{
        app_title = 'Instalador de página PCL'
        app_subtitle = 'PCL2 / PCL CE · Instalação local · 15 idiomas'
        step_launcher = 'Escolher launcher'
        step_launcher_hint = 'Selecione o launcher de instalação.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'PCL2 original · usa Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Edição da comunidade · usa config.v1.yml'
        step_folder = 'Escolher pasta de dados'
        folder_hint = 'Pasta com Setup.ini ou config.v1.yml; a raiz do launcher também serve.'
        path_cue = 'ex.: D:\PCL-CE\PCL'
        browse = 'Procurar...'
        detect = 'Detectar'
        install = 'Instalar'
        reinstall = 'Reinstalar'
        uninstall = 'Desinstalar'
        exit = 'Sair'
        status_ready = 'Escolha um launcher e uma pasta de dados.'
        status_detected = 'Detectado: {0} · {1}'
        status_folder_ready = 'Pasta de dados pronta: {0}'
        status_not_found = 'Nenhuma pasta de dados do PCL encontrada. Verifique o caminho.'
        status_switched = 'Esta pasta pertence ao {0}; alterado automaticamente.'
        status_installing = 'Instalando, aguarde...'
        status_uninstalling = 'Desinstalando, aguarde...'
        status_installed = 'Instalado: {0}'
        status_uninstalled = 'Desinstalado: {0}'
        status_failed = 'Falha na operação: {0}'
        confirm_overwrite_title = 'Já instalado'
        confirm_overwrite = "Já existe uma página inicial personalizada instalada nesta pasta.`n`nReinstalar ou desinstalar?"
        confirm_uninstall_title = 'Desinstalar página inicial personalizada'
        confirm_uninstall = "Remover a página inicial personalizada desta pasta?`n`n{0}`n`nO launcher voltará à página inicial integrada. As outras configurações de interface permanecem iguais."
        pcl_running_title = 'O launcher está em execução'
        pcl_running = 'Feche completamente o PCL2 / PCL CE e tente novamente.'
        confirm_close_pcl = "Quer que eu o feche?"
        status_closing_pcl = "Fechando o launcher selecionado..."
        not_installed = 'A página inicial personalizada não está instalada nesta pasta.'
        select_target = 'Selecione uma pasta de dados válida do PCL.'
        error_title = 'Falha na instalação'
        error_generic = 'A instalação falhou. Verifique se o launcher está fechado e se a pasta permite gravação, depois tente novamente.'
        err_running = 'O PCL ainda está em execução. Feche-o e tente novamente.'
        err_flavor = 'Não foi possível determinar se esta pasta é do PCL2 ou do PCL CE.'
        err_logview = 'Falha ao gerar LogView.xaml.'
        err_payload = 'O pacote de instalação está incompleto ou corrompido.'
        done_title = 'Concluído'
        done_install = "A página inicial personalizada foi instalada.`n`n{0}`n`nAbra o launcher para vê-la. Se já estiver aberto, pressione F5 ou abra novamente."
        done_uninstall = "A página inicial personalizada foi desinstalada.`n`n{0}`n`nO launcher voltará à página inicial integrada. Reinicie-o se estiver em execução."
        browse_desc_pcl = 'Selecione a pasta de dados do PCL2 (contém Setup.ini)'
        browse_desc_ce = 'Selecione a pasta de dados do PCL CE (contém config.v1.yml)'
        browse_desc_any = 'Selecione a pasta de dados do PCL (contém Setup.ini ou config.v1.yml)'
        footer = 'Página inicial do PCL · v1.4 · 15 idiomas · apenas a configuração do launcher selecionado é alterada'
        incompatible_pcl = "Instalar uma página inicial personalizada para esta versão do PCL não faz mais sentido.`nNenhuma alteração foi feita no seu computador."
        status_incompatible = "Esta versão do PCL não é compatível. Nenhuma alteração foi feita."
        flavor_pcl = 'PCL2 (original)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Idioma'
        home_lang_note = 'Página inicial: {0}'
    }
    'ru' = @{
        app_title = 'Установщик главной PCL'
        app_subtitle = 'PCL2 / PCL CE · Локальная установка · 15 языков'
        step_launcher = 'Выберите лаунчер'
        step_launcher_hint = 'Выберите лаунчер для установки.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Оригинальный PCL2 · использует Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Community Edition · использует config.v1.yml'
        step_folder = 'Выберите папку данных'
        folder_hint = 'Папка с Setup.ini или config.v1.yml; корень лаунчера тоже подходит.'
        path_cue = 'например: D:\PCL-CE\PCL'
        browse = 'Обзор...'
        detect = 'Определить'
        install = 'Установить'
        reinstall = 'Переустановить'
        uninstall = 'Удалить'
        exit = 'Выход'
        status_ready = 'Выберите лаунчер и папку данных.'
        status_detected = 'Определено: {0} · {1}'
        status_folder_ready = 'Папка данных готова: {0}'
        status_not_found = 'Папка данных PCL не найдена. Проверьте путь.'
        status_switched = 'Эта папка относится к {0}; выполнено автоматическое переключение.'
        status_installing = 'Установка, подождите...'
        status_uninstalling = 'Удаление, подождите...'
        status_installed = 'Установлено: {0}'
        status_uninstalled = 'Удалено: {0}'
        status_failed = 'Ошибка операции: {0}'
        confirm_overwrite_title = 'Уже установлено'
        confirm_overwrite = "В этой папке уже установлена пользовательская домашняя страница.`n`nПереустановить или удалить?"
        confirm_uninstall_title = 'Удалить домашнюю страницу'
        confirm_uninstall = "Удалить пользовательскую домашнюю страницу из этой папки?`n`n{0}`n`nЛаунчер вернётся к встроенной домашней странице. Остальные настройки интерфейса не изменятся."
        pcl_running_title = 'Лаунчер запущен'
        pcl_running = 'Полностью закройте PCL2 / PCL CE и повторите попытку.'
        confirm_close_pcl = "Закрыть его за вас?"
        status_closing_pcl = "Закрытие выбранного лаунчера..."
        not_installed = 'Пользовательская домашняя страница не установлена в этой папке.'
        select_target = 'Выберите правильную папку данных PCL.'
        error_title = 'Ошибка установки'
        error_generic = 'Установка не удалась. Убедитесь, что лаунчер закрыт и папка доступна для записи, затем повторите попытку.'
        err_running = 'PCL всё ещё запущен. Закройте его и повторите попытку.'
        err_flavor = 'Не удалось определить, относится ли эта папка к PCL2 или PCL CE.'
        err_logview = 'Не удалось создать LogView.xaml.'
        err_payload = 'Установочный пакет неполный или повреждён.'
        done_title = 'Готово'
        done_install = "Пользовательская домашняя страница установлена.`n`n{0}`n`nОткройте лаунчер, чтобы увидеть её. Если он уже открыт, нажмите F5 или откройте заново."
        done_uninstall = "Пользовательская домашняя страница удалена.`n`n{0}`n`nЛаунчер вернётся к встроенной домашней странице. Перезапустите его, если он запущен."
        browse_desc_pcl = 'Выберите папку данных PCL2 (содержит Setup.ini)'
        browse_desc_ce = 'Выберите папку данных PCL CE (содержит config.v1.yml)'
        browse_desc_any = 'Выберите папку данных PCL (содержит Setup.ini или config.v1.yml)'
        footer = 'Домашняя страница PCL · v1.4 · 15 языков · изменяется только конфигурация выбранного лаунчера'
        incompatible_pcl = "Устанавливать пользовательскую главную страницу для этой версии PCL больше не имеет смысла.`nВаш компьютер не был изменён."
        status_incompatible = "Эта версия PCL не поддерживается. Изменения не вносились."
        flavor_pcl = 'PCL2 (оригинал)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Язык'
        home_lang_note = 'Главная: {0}'
    }
    'it' = @{
        app_title = 'Installatore homepage PCL'
        app_subtitle = 'PCL2 / PCL CE · Installazione locale · 15 lingue'
        step_launcher = 'Scegli il launcher'
        step_launcher_hint = 'Seleziona il launcher su cui installare.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'PCL2 originale · usa Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Edizione community · usa config.v1.yml'
        step_folder = 'Scegli la cartella dati'
        folder_hint = 'Cartella con Setup.ini o config.v1.yml; va bene anche la radice del launcher.'
        path_cue = 'es.: D:\PCL-CE\PCL'
        browse = 'Sfoglia...'
        detect = 'Rileva'
        install = 'Installa'
        reinstall = 'Reinstalla'
        uninstall = 'Disinstalla'
        exit = 'Esci'
        status_ready = 'Scegli un launcher e una cartella dati.'
        status_detected = 'Rilevato: {0} · {1}'
        status_folder_ready = 'Cartella dati pronta: {0}'
        status_not_found = 'Nessuna cartella dati PCL trovata. Controlla il percorso.'
        status_switched = 'Questa cartella appartiene a {0}; cambio automatico.'
        status_installing = 'Installazione in corso...'
        status_uninstalling = 'Disinstallazione in corso...'
        status_installed = 'Installato: {0}'
        status_uninstalled = 'Disinstallato: {0}'
        status_failed = 'Operazione non riuscita: {0}'
        confirm_overwrite_title = 'Già installato'
        confirm_overwrite = "In questa cartella è già installata una homepage personalizzata.`n`nReinstallare o disinstallare?"
        confirm_uninstall_title = 'Disinstalla homepage personalizzata'
        confirm_uninstall = "Rimuovere la homepage personalizzata da questa cartella?`n`n{0}`n`nIl launcher tornerà alla homepage integrata. Le altre impostazioni dell''interfaccia restano invariate."
        pcl_running_title = 'Il launcher è in esecuzione'
        pcl_running = 'Chiudi completamente PCL2 / PCL CE, poi riprova.'
        confirm_close_pcl = "Vuoi che lo chiuda?"
        status_closing_pcl = "Chiusura del launcher selezionato..."
        not_installed = 'La homepage personalizzata non è installata in questa cartella.'
        select_target = 'Seleziona una cartella dati PCL valida.'
        error_title = 'Installazione non riuscita'
        error_generic = 'Installazione non riuscita. Verifica che il launcher sia chiuso e che la cartella sia scrivibile, poi riprova.'
        err_running = 'PCL è ancora in esecuzione. Chiudilo e riprova.'
        err_flavor = 'Impossibile determinare se questa cartella è PCL2 o PCL CE.'
        err_logview = 'Generazione di LogView.xaml non riuscita.'
        err_payload = 'Il pacchetto di installazione è incompleto o danneggiato.'
        done_title = 'Fatto'
        done_install = "La homepage personalizzata è stata installata.`n`n{0}`n`nApri il launcher per vederla. Se è già aperto, premi F5 o riaprilo."
        done_uninstall = "La homepage personalizzata è stata disinstallata.`n`n{0}`n`nIl launcher tornerà alla homepage integrata. Riavvialo se è in esecuzione."
        browse_desc_pcl = 'Seleziona la cartella dati PCL2 (contiene Setup.ini)'
        browse_desc_ce = 'Seleziona la cartella dati PCL CE (contiene config.v1.yml)'
        browse_desc_any = 'Seleziona la cartella dati PCL (contiene Setup.ini o config.v1.yml)'
        footer = 'Homepage PCL · v1.4 · 15 lingue · viene modificata solo la configurazione del launcher scelto'
        incompatible_pcl = "Installare una homepage personalizzata per questa versione di PCL non ha più senso.`nNessuna modifica è stata apportata al computer."
        status_incompatible = "Questa versione di PCL non è supportata. Nessuna modifica è stata apportata."
        flavor_pcl = 'PCL2 (originale)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Lingua'
        home_lang_note = 'Homepage: {0}'
    }
    'nl' = @{
        app_title = 'PCL startpagina-installatie'
        app_subtitle = 'PCL2 / PCL CE · Lokale installatie · 15 talen'
        step_launcher = 'Kies launcher'
        step_launcher_hint = 'Selecteer de launcher waarnaar je wilt installeren.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Originele PCL2 · gebruikt Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Community-editie · gebruikt config.v1.yml'
        step_folder = 'Kies gegevensmap'
        folder_hint = 'Map met Setup.ini of config.v1.yml; de launcherhoofdmap werkt ook.'
        path_cue = 'bijv. D:\PCL-CE\PCL'
        browse = 'Bladeren...'
        detect = 'Detecteren'
        install = 'Installeren'
        reinstall = 'Opnieuw installeren'
        uninstall = 'Verwijderen'
        exit = 'Afsluiten'
        status_ready = 'Kies een launcher en een gegevensmap.'
        status_detected = 'Gedetecteerd: {0} · {1}'
        status_folder_ready = 'Gegevensmap gereed: {0}'
        status_not_found = 'Geen PCL-gegevensmap gevonden. Controleer het pad.'
        status_switched = 'Deze map hoort bij {0}; automatisch overgeschakeld.'
        status_installing = 'Bezig met installeren...'
        status_uninstalling = 'Bezig met verwijderen...'
        status_installed = 'Geïnstalleerd: {0}'
        status_uninstalled = 'Verwijderd: {0}'
        status_failed = 'Bewerking mislukt: {0}'
        confirm_overwrite_title = 'Al geïnstalleerd'
        confirm_overwrite = "In deze map is al een aangepaste startpagina geïnstalleerd.`n`nOpnieuw installeren of verwijderen?"
        confirm_uninstall_title = 'Aangepaste startpagina verwijderen'
        confirm_uninstall = "De aangepaste startpagina uit deze map verwijderen?`n`n{0}`n`nDe launcher keert terug naar de ingebouwde startpagina. Andere UI-instellingen blijven ongewijzigd."
        pcl_running_title = 'Launcher is actief'
        pcl_running = 'Sluit PCL2 / PCL CE volledig af en probeer het opnieuw.'
        confirm_close_pcl = "Wil je dat ik het sluit?"
        status_closing_pcl = "De geselecteerde launcher wordt gesloten..."
        not_installed = 'De aangepaste startpagina is niet in deze map geïnstalleerd.'
        select_target = 'Selecteer een geldige PCL-gegevensmap.'
        error_title = 'Installatie mislukt'
        error_generic = 'De installatie is mislukt. Controleer of de launcher is gesloten en de map beschrijfbaar is, en probeer het opnieuw.'
        err_running = 'PCL is nog actief. Sluit het af en probeer het opnieuw.'
        err_flavor = 'Kan niet bepalen of deze map bij PCL2 of PCL CE hoort.'
        err_logview = 'LogView.xaml kon niet worden gegenereerd.'
        err_payload = 'Het installatiepakket is onvolledig of beschadigd.'
        done_title = 'Klaar'
        done_install = "De aangepaste startpagina is geïnstalleerd.`n`n{0}`n`nOpen de launcher om hem te bekijken. Als hij al open is, druk op F5 of open hem opnieuw."
        done_uninstall = "De aangepaste startpagina is verwijderd.`n`n{0}`n`nDe launcher keert terug naar de ingebouwde startpagina. Start hem opnieuw als hij actief is."
        browse_desc_pcl = 'Selecteer de PCL2-gegevensmap (bevat Setup.ini)'
        browse_desc_ce = 'Selecteer de PCL CE-gegevensmap (bevat config.v1.yml)'
        browse_desc_any = 'Selecteer de PCL-gegevensmap (bevat Setup.ini of config.v1.yml)'
        footer = 'PCL startpagina · v1.4 · 15 talen · alleen de configuratie van de gekozen launcher wordt gewijzigd'
        incompatible_pcl = "Een aangepaste startpagina installeren voor deze PCL-versie heeft geen zin meer.`nEr zijn geen wijzigingen aan je computer aangebracht."
        status_incompatible = "Deze PCL-versie wordt niet ondersteund. Er zijn geen wijzigingen aangebracht."
        flavor_pcl = 'PCL2 (origineel)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Taal'
        home_lang_note = 'Startpagina: {0}'
    }
    'pl' = @{
        app_title = 'Instalator strony głównej PCL'
        app_subtitle = 'PCL2 / PCL CE · Instalacja lokalna · 15 języków'
        step_launcher = 'Wybierz launcher'
        step_launcher_hint = 'Wybierz launcher, do którego chcesz zainstalować.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Oryginalny PCL2 · używa Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Wersja społecznościowa · używa config.v1.yml'
        step_folder = 'Wybierz folder danych'
        folder_hint = 'Folder z Setup.ini lub config.v1.yml; główny folder launchera też jest OK.'
        path_cue = 'np. D:\PCL-CE\PCL'
        browse = 'Przeglądaj...'
        detect = 'Wykryj'
        install = 'Zainstaluj'
        reinstall = 'Zainstaluj ponownie'
        uninstall = 'Odinstaluj'
        exit = 'Zamknij'
        status_ready = 'Wybierz launcher i folder danych.'
        status_detected = 'Wykryto: {0} · {1}'
        status_folder_ready = 'Folder danych jest gotowy: {0}'
        status_not_found = 'Nie znaleziono folderu danych PCL. Sprawdź ścieżkę.'
        status_switched = 'Ten folder należy do {0}; przełączono automatycznie.'
        status_installing = 'Trwa instalacja, czekaj...'
        status_uninstalling = 'Trwa odinstalowywanie, czekaj...'
        status_installed = 'Zainstalowano: {0}'
        status_uninstalled = 'Odinstalowano: {0}'
        status_failed = 'Operacja nie powiodła się: {0}'
        confirm_overwrite_title = 'Już zainstalowano'
        confirm_overwrite = "W tym folderze jest już zainstalowana niestandardowa strona główna.`n`nZainstalować ponownie czy odinstalować?"
        confirm_uninstall_title = 'Odinstaluj niestandardową stronę główną'
        confirm_uninstall = "Usunąć niestandardową stronę główną z tego folderu?`n`n{0}`n`nLauncher wróci do wbudowanej strony głównej. Pozostałe ustawienia interfejsu pozostaną bez zmian."
        pcl_running_title = 'Launcher jest uruchomiony'
        pcl_running = 'Całkowicie zamknij PCL2 / PCL CE i spróbuj ponownie.'
        confirm_close_pcl = "Czy mam go zamknąć?"
        status_closing_pcl = "Zamykanie wybranego launchera..."
        not_installed = 'Niestandardowa strona główna nie jest zainstalowana w tym folderze.'
        select_target = 'Wybierz prawidłowy folder danych PCL.'
        error_title = 'Instalacja nie powiodła się'
        error_generic = 'Instalacja nie powiodła się. Upewnij się, że launcher jest zamknięty, a folder można zapisywać, i spróbuj ponownie.'
        err_running = 'PCL nadal działa. Zamknij go i spróbuj ponownie.'
        err_flavor = 'Nie można ustalić, czy ten folder należy do PCL2, czy do PCL CE.'
        err_logview = 'Nie udało się wygenerować LogView.xaml.'
        err_payload = 'Pakiet instalacyjny jest niekompletny lub uszkodzony.'
        done_title = 'Gotowe'
        done_install = "Niestandardowa strona główna została zainstalowana.`n`n{0}`n`nOtwórz launcher, aby ją zobaczyć. Jeśli jest już otwarty, naciśnij F5 lub otwórz go ponownie."
        done_uninstall = "Niestandardowa strona główna została odinstalowana.`n`n{0}`n`nLauncher wróci do wbudowanej strony głównej. Uruchom go ponownie, jeśli działa."
        browse_desc_pcl = 'Wybierz folder danych PCL2 (zawiera Setup.ini)'
        browse_desc_ce = 'Wybierz folder danych PCL CE (zawiera config.v1.yml)'
        browse_desc_any = 'Wybierz folder danych PCL (zawiera Setup.ini lub config.v1.yml)'
        footer = 'Strona główna PCL · v1.4 · 15 języków · zmieniana jest tylko konfiguracja wybranego launchera'
        incompatible_pcl = "Instalowanie niestandardowej strony głównej dla tej wersji PCL nie ma już sensu.`nNie wprowadzono żadnych zmian na Twoim komputerze."
        status_incompatible = "Ta wersja PCL nie jest obsługiwana. Nie wprowadzono żadnych zmian."
        flavor_pcl = 'PCL2 (oryginalny)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Język'
        home_lang_note = 'Strona główna: {0}'
    }
    'tr' = @{
        app_title = 'PCL Ana Sayfa Yükleyicisi'
        app_subtitle = 'PCL2 / PCL CE · Yerel kurulum · 15 dil'
        step_launcher = 'Başlatıcı seç'
        step_launcher_hint = 'Kurulum yapılacak başlatıcıyı seçin.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'Orijinal PCL2 · Setup.ini kullanır'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Topluluk sürümü · config.v1.yml kullanır'
        step_folder = 'Veri klasörünü seç'
        folder_hint = 'Setup.ini veya config.v1.yml içeren PCL klasörü; başlatıcı kökü de olur.'
        path_cue = 'örn. D:\PCL-CE\PCL'
        browse = 'Gözat...'
        detect = 'Algıla'
        install = 'Kur'
        reinstall = 'Yeniden kur'
        uninstall = 'Kaldır'
        exit = 'Çıkış'
        status_ready = 'Bir başlatıcı ve veri klasörü seçin.'
        status_detected = 'Algılandı: {0} · {1}'
        status_folder_ready = 'Veri klasörü hazır: {0}'
        status_not_found = 'PCL veri klasörü bulunamadı. Yolu kontrol edin.'
        status_switched = 'Bu klasör {0} ait; otomatik olarak geçildi.'
        status_installing = 'Kuruluyor, lütfen bekleyin...'
        status_uninstalling = 'Kaldırılıyor, lütfen bekleyin...'
        status_installed = 'Kuruldu: {0}'
        status_uninstalled = 'Kaldırıldı: {0}'
        status_failed = 'İşlem başarısız: {0}'
        confirm_overwrite_title = 'Zaten kurulu'
        confirm_overwrite = "Bu klasörde zaten özel bir ana sayfa kurulu.`n`nYeniden kurulsun mu, kaldırılsın mı?"
        confirm_uninstall_title = 'Özel ana sayfayı kaldır'
        confirm_uninstall = "Özel ana sayfa bu klasörden kaldırılsın mı?`n`n{0}`n`nBaşlatıcı yerleşik ana sayfasına döner. Diğer arayüz ayarları değişmez."
        pcl_running_title = 'Başlatıcı çalışıyor'
        pcl_running = 'PCL2 / PCL CE''yi tamamen kapatıp tekrar deneyin.'
        confirm_close_pcl = "Sizin için kapatayım mı?"
        status_closing_pcl = "Seçili başlatıcı kapatılıyor..."
        not_installed = 'Bu klasörde özel ana sayfa kurulu değil.'
        select_target = 'Geçerli bir PCL veri klasörü seçin.'
        error_title = 'Kurulum başarısız'
        error_generic = 'Kurulum başarısız. Başlatıcının kapalı ve klasörün yazılabilir olduğundan emin olup tekrar deneyin.'
        err_running = 'PCL hâlâ çalışıyor. Kapatıp tekrar deneyin.'
        err_flavor = 'Bu klasörün PCL2 mi yoksa PCL CE mi olduğu belirlenemedi.'
        err_logview = 'LogView.xaml oluşturulamadı.'
        err_payload = 'Kurulum paketi eksik veya bozuk.'
        done_title = 'Tamam'
        done_install = "Özel ana sayfa kuruldu.`n`n{0}`n`nGörmek için başlatıcıyı açın. Zaten açıksa F5''e basın veya yeniden açın."
        done_uninstall = "Özel ana sayfa kaldırıldı.`n`n{0}`n`nBaşlatıcı yerleşik ana sayfasına döner. Çalışıyorsa yeniden başlatın."
        browse_desc_pcl = 'PCL2 veri klasörünü seçin (Setup.ini içerir)'
        browse_desc_ce = 'PCL CE veri klasörünü seçin (config.v1.yml içerir)'
        browse_desc_any = 'PCL veri klasörünü seçin (Setup.ini veya config.v1.yml içerir)'
        footer = 'PCL Ana Sayfa · v1.4 · 15 dil · yalnızca seçilen başlatıcının yapılandırması değiştirilir'
        incompatible_pcl = "Bu PCL sürümü için özel ana sayfa yüklemek artık anlamsız.`nBilgisayarınızda hiçbir değişiklik yapılmadı."
        status_incompatible = "Bu PCL sürümü desteklenmiyor. Hiçbir değişiklik yapılmadı."
        flavor_pcl = 'PCL2 (Orijinal)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Dil'
        home_lang_note = 'Ana sayfa: {0}'
    }
    'vi' = @{
        app_title = 'Trình cài đặt trang chủ PCL'
        app_subtitle = 'Hỗ trợ PCL2 / PCL CE · Cài đặt cục bộ · 15 ngôn ngữ'
        step_launcher = 'Chọn trình khởi chạy'
        step_launcher_hint = 'Chọn trình khởi chạy để cài đặt.'
        flavor_pcl_title = 'PCL2'
        flavor_pcl_desc = 'PCL2 gốc · dùng Setup.ini'
        flavor_ce_title = 'PCL CE'
        flavor_ce_desc = 'Bản cộng đồng · dùng config.v1.yml'
        step_folder = 'Chọn thư mục dữ liệu'
        folder_hint = 'Thư mục chứa Setup.ini hoặc config.v1.yml; thư mục gốc của launcher cũng được.'
        path_cue = 'ví dụ: D:\PCL-CE\PCL'
        browse = 'Duyệt...'
        detect = 'Phát hiện'
        install = 'Cài đặt'
        reinstall = 'Cài đặt lại'
        uninstall = 'Gỡ cài đặt'
        exit = 'Thoát'
        status_ready = 'Chọn trình khởi chạy và thư mục dữ liệu.'
        status_detected = 'Đã phát hiện: {0} · {1}'
        status_folder_ready = 'Thư mục dữ liệu đã sẵn sàng: {0}'
        status_not_found = 'Không tìm thấy thư mục dữ liệu PCL. Kiểm tra đường dẫn.'
        status_switched = 'Thư mục này thuộc {0}; đã tự động chuyển.'
        status_installing = 'Đang cài đặt, vui lòng chờ...'
        status_uninstalling = 'Đang gỡ cài đặt, vui lòng chờ...'
        status_installed = 'Đã cài đặt: {0}'
        status_uninstalled = 'Đã gỡ cài đặt: {0}'
        status_failed = 'Thao tác thất bại: {0}'
        confirm_overwrite_title = 'Đã cài đặt'
        confirm_overwrite = "Thư mục này đã có trang chủ tùy chỉnh.`n`nCài đặt lại hay gỡ cài đặt?"
        confirm_uninstall_title = 'Gỡ trang chủ tùy chỉnh'
        confirm_uninstall = "Gỡ trang chủ tùy chỉnh khỏi thư mục này?`n`n{0}`n`nTrình khởi chạy sẽ trở về trang chủ mặc định. Các cài đặt giao diện khác không thay đổi."
        pcl_running_title = 'Trình khởi chạy đang chạy'
        pcl_running = 'Hãy thoát hoàn toàn PCL2 / PCL CE rồi thử lại.'
        confirm_close_pcl = "Bạn có muốn tôi đóng nó không?"
        status_closing_pcl = "Đang đóng trình khởi chạy đã chọn..."
        not_installed = 'Trang chủ tùy chỉnh chưa được cài đặt trong thư mục này.'
        select_target = 'Chọn một thư mục dữ liệu PCL hợp lệ.'
        error_title = 'Cài đặt thất bại'
        error_generic = 'Cài đặt thất bại. Hãy đảm bảo trình khởi chạy đã đóng và thư mục có thể ghi, rồi thử lại.'
        err_running = 'PCL vẫn đang chạy. Hãy thoát rồi thử lại.'
        err_flavor = 'Không thể xác định thư mục này là PCL2 hay PCL CE.'
        err_logview = 'Tạo LogView.xaml thất bại.'
        err_payload = 'Gói cài đặt không đầy đủ hoặc bị hỏng.'
        done_title = 'Hoàn tất'
        done_install = "Trang chủ tùy chỉnh đã được cài đặt.`n`n{0}`n`nMở trình khởi chạy để xem. Nếu đang mở, nhấn F5 hoặc mở lại."
        done_uninstall = "Trang chủ tùy chỉnh đã được gỡ cài đặt.`n`n{0}`n`nTrình khởi chạy sẽ trở về trang chủ mặc định. Khởi động lại nếu đang chạy."
        browse_desc_pcl = 'Chọn thư mục dữ liệu PCL2 (chứa Setup.ini)'
        browse_desc_ce = 'Chọn thư mục dữ liệu PCL CE (chứa config.v1.yml)'
        browse_desc_any = 'Chọn thư mục dữ liệu PCL (chứa Setup.ini hoặc config.v1.yml)'
        footer = 'Trang chủ PCL · v1.4 · 15 ngôn ngữ · chỉ sửa cấu hình của trình khởi chạy đã chọn'
        incompatible_pcl = "Cài đặt trang chủ tùy chỉnh cho phiên bản PCL này không còn ý nghĩa nữa.`nKhông có thay đổi nào được thực hiện trên máy tính của bạn."
        status_incompatible = "Phiên bản PCL này không được hỗ trợ. Không có thay đổi nào được thực hiện."
        flavor_pcl = 'PCL2 (gốc)'
        flavor_ce = 'PCL CE'
        lang_caption = 'Ngôn ngữ'
        home_lang_note = 'Trang chủ: {0}'
    }
}

# Any key a translation does not override falls back to English.
foreach ($code in $script:languageCodes) {
    if (-not $script:guiText.ContainsKey($code)) { $script:guiText[$code] = @{} }
    $table = $script:guiText[$code]
    foreach ($key in @($script:guiText['en'].Keys)) {
        if (-not $table.ContainsKey($key)) { $table[$key] = $script:guiText['en'][$key] }
    }
}

$script:pageText = @{
    'en' = @{
        open_game = 'Open game folder'
        open_game_tip = 'Open the current instance folder'
        open_schematics = 'Open Schematics'
        open_schematics_tip = "Open this version's schematics folder"
        open_mods = 'Open Mods'
        open_mods_tip = "Open this version's mods folder"
        open_saves = 'Open Saves'
        open_saves_tip = "Open this version's saves folder"
        refresh_bg = 'Refresh background'
        refresh_bg_tip = 'Ask PCL to pick a new random background image'
        game_log = 'Game log'
        refresh_log = 'Refresh log'
        refresh_log_tip = 'Reload the game log and refresh the homepage'
        notepad = 'Notepad'
        open_game_log_tip = "Open the running game's latest.log in Notepad; unavailable when the game is not running"
        log_folder = 'Log folder'
        open_log_folder = 'Open log folder'
        commands = 'Custom commands'
        open_commands = 'Open command manager'
        commands_tip = 'Open the custom command manager'
        online = 'Multiplayer'
        open_online = 'Terracotta'
        online_tip = 'Open the Terracotta multiplayer window (room code, no port forwarding)'
        launcher_log = 'Launcher log'
        open_launcher_log_tip = "Open this launcher session's log in Notepad"
        previous_log = 'Previous launch'
        open_previous_log_tip = "Open the previous game launch's log in Notepad"
    }
    'zh-CN' = @{
        open_game = '打开游戏目录'
        open_game_tip = '打开当前实例的文件夹'
        open_schematics = '打开 Schematics 文件夹'
        open_schematics_tip = '打开当前版本的 schematics 文件夹'
        open_mods = '打开 Mod 文件夹'
        open_mods_tip = '打开当前版本的 mods 文件夹'
        open_saves = '打开 Saves 文件夹'
        open_saves_tip = '打开当前版本的 saves 文件夹'
        refresh_bg = '刷新背景图片'
        refresh_bg_tip = '让 PCL 重新随机选择一张背景图片'
        game_log = '游戏日志'
        refresh_log = '刷新日志'
        refresh_log_tip = '重新读取游戏日志并刷新主页'
        notepad = '在记事本打开'
        open_game_log_tip = '用记事本打开正在运行的游戏日志（latest.log）；游戏未运行时无效'
        log_folder = '日志文件夹'
        open_log_folder = '打开日志文件夹'
        commands = '自定义指令'
        open_commands = '打开指令管理'
        commands_tip = '打开自定义指令管理器'
        online = '联机'
        open_online = '陶瓦联机'
        online_tip = '打开陶瓦联机窗口（房间码联机，无需端口映射）'
        launcher_log = '启动器日志'
        open_launcher_log_tip = '用记事本打开本次启动器会话日志'
        previous_log = '上一次启动'
        open_previous_log_tip = '用记事本打开上一次游戏启动的日志'
    }
    'zh-TW' = @{
        open_game = '開啟遊戲目錄'
        open_game_tip = '開啟目前執行個體的資料夾'
        open_schematics = '開啟 Schematics 資料夾'
        open_schematics_tip = '開啟目前版本的 schematics 資料夾'
        open_mods = '開啟 Mod 資料夾'
        open_mods_tip = '開啟目前版本的 mods 資料夾'
        open_saves = '開啟 Saves 資料夾'
        open_saves_tip = '開啟目前版本的 saves 資料夾'
        refresh_bg = '重新整理背景圖片'
        refresh_bg_tip = '讓 PCL 重新隨機選擇一張背景圖片'
        game_log = '遊戲日誌'
        refresh_log = '重新整理日誌'
        refresh_log_tip = '重新讀取遊戲日誌並重新整理主頁'
        notepad = '在記事本開啟'
        open_game_log_tip = '用記事本開啟執行中的遊戲日誌（latest.log）；遊戲未執行時無效'
        log_folder = '日誌資料夾'
        open_log_folder = '開啟日誌資料夾'
        commands = '自訂指令'
        open_commands = '開啟指令管理'
        commands_tip = '開啟自訂指令管理器'
        online = '連線'
        open_online = '陶瓦聯機'
        online_tip = '開啟陶瓦聯機視窗（房間碼連線，無需連接埠轉送）'
        launcher_log = '啟動器日誌'
        open_launcher_log_tip = '用記事本開啟本次啟動器工作階段日誌'
        previous_log = '上一次啟動'
        open_previous_log_tip = '用記事本開啟上一次遊戲啟動的日誌'
    }
    'ja' = @{
        open_game = 'ゲームフォルダーを開く'
        open_game_tip = '現在のインスタンスフォルダーを開く'
        open_schematics = 'Schematics を開く'
        open_schematics_tip = 'このバージョンの schematics フォルダーを開く'
        open_mods = 'Mods を開く'
        open_mods_tip = 'このバージョンの mods フォルダーを開く'
        open_saves = 'Saves を開く'
        open_saves_tip = 'このバージョンの saves フォルダーを開く'
        refresh_bg = '背景を更新'
        refresh_bg_tip = 'PCL に背景画像をランダムに選び直させる'
        game_log = 'ゲームログ'
        refresh_log = 'ログを更新'
        refresh_log_tip = 'ゲームログを再読み込みしてホームページを更新'
        notepad = 'メモ帳で開く'
        open_game_log_tip = '実行中のゲームの latest.log をメモ帳で開く（ゲーム未実行時は無効）'
        log_folder = 'ログフォルダー'
        open_log_folder = 'ログフォルダーを開く'
        commands = 'カスタムコマンド'
        open_commands = 'コマンド管理を開く'
        commands_tip = 'カスタムコマンド管理を開く'
        online = 'マルチプレイ'
        open_online = 'Terracotta'
        online_tip = 'Terracotta のマルチプレイ画面を開きます（ルームコード接続、ポート開放不要）'
        launcher_log = 'ランチャーログ'
        open_launcher_log_tip = '今回のランチャーセッションのログをメモ帳で開く'
        previous_log = '前回の起動'
        open_previous_log_tip = '前回のゲーム起動時のログをメモ帳で開く'
    }
    'ko' = @{
        open_game = '게임 폴더 열기'
        open_game_tip = '현재 인스턴스 폴더 열기'
        open_schematics = 'Schematics 열기'
        open_schematics_tip = '현재 버전의 schematics 폴더 열기'
        open_mods = 'Mods 열기'
        open_mods_tip = '현재 버전의 mods 폴더 열기'
        open_saves = 'Saves 열기'
        open_saves_tip = '현재 버전의 saves 폴더 열기'
        refresh_bg = '배경 새로 고침'
        refresh_bg_tip = 'PCL이 새 배경 이미지를 무작위로 선택하도록 함'
        game_log = '게임 로그'
        refresh_log = '로그 새로 고침'
        refresh_log_tip = '게임 로그를 다시 읽고 홈페이지 새로 고침'
        notepad = '메모장으로 열기'
        open_game_log_tip = '실행 중인 게임의 latest.log를 메모장으로 열기 (게임이 실행 중이 아닐 때는 사용 불가)'
        log_folder = '로그 폴더'
        open_log_folder = '로그 폴더 열기'
        commands = '사용자 지정 명령'
        open_commands = '명령 관리 열기'
        commands_tip = '사용자 지정 명령 관리 열기'
        online = '멀티플레이'
        open_online = 'Terracotta'
        online_tip = 'Terracotta 멀티플레이 창을 엽니다(방 코드 연결, 포트 포워딩 불필요)'
        launcher_log = '런처 로그'
        open_launcher_log_tip = '이번 런처 세션 로그를 메모장으로 열기'
        previous_log = '이전 실행'
        open_previous_log_tip = '이전 게임 실행 로그를 메모장으로 열기'
    }
    'fr' = @{
        open_game = 'Ouvrir le dossier du jeu'
        open_game_tip = 'Ouvrir le dossier de cette instance'
        open_schematics = 'Ouvrir Schematics'
        open_schematics_tip = 'Ouvrir le dossier schematics de cette version'
        open_mods = 'Ouvrir Mods'
        open_mods_tip = 'Ouvrir le dossier mods de cette version'
        open_saves = 'Ouvrir Saves'
        open_saves_tip = 'Ouvrir le dossier saves de cette version'
        refresh_bg = 'Changer l''arrière-plan'
        refresh_bg_tip = 'Demander à PCL de choisir une nouvelle image d''arrière-plan au hasard'
        game_log = 'Journal du jeu'
        refresh_log = 'Actualiser le journal'
        refresh_log_tip = 'Relire le journal du jeu et actualiser la page'
        notepad = 'Bloc-notes'
        open_game_log_tip = 'Ouvrir latest.log du jeu en cours dans le Bloc-notes ; indisponible si le jeu ne tourne pas'
        log_folder = 'Dossier des journaux'
        open_log_folder = 'Ouvrir le dossier'
        commands = 'Commandes personnalisées'
        open_commands = 'Ouvrir le gestionnaire'
        commands_tip = 'Ouvrir le gestionnaire de commandes personnalisées'
        online = 'Multijoueur'
        open_online = 'Terracotta'
        online_tip = 'Ouvrir la fenêtre multijoueur Terracotta (code de salon, sans redirection de port)'
        launcher_log = 'Journal du lanceur'
        open_launcher_log_tip = 'Ouvrir le journal de cette session du lanceur dans le Bloc-notes'
        previous_log = 'Lancement précédent'
        open_previous_log_tip = "Ouvrir le journal du lancement précédent dans le Bloc-notes"
    }
    'de' = @{
        open_game = 'Spielordner öffnen'
        open_game_tip = 'Ordner der aktuellen Instanz öffnen'
        open_schematics = 'Schematics öffnen'
        open_schematics_tip = 'Schematics-Ordner dieser Version öffnen'
        open_mods = 'Mods öffnen'
        open_mods_tip = 'Mods-Ordner dieser Version öffnen'
        open_saves = 'Saves öffnen'
        open_saves_tip = 'Saves-Ordner dieser Version öffnen'
        refresh_bg = 'Hintergrund wechseln'
        refresh_bg_tip = 'PCL ein neues zufälliges Hintergrundbild auswählen lassen'
        game_log = 'Spiel-Log'
        refresh_log = 'Log aktualisieren'
        refresh_log_tip = 'Spiel-Log neu laden und Startseite aktualisieren'
        notepad = 'Editor'
        open_game_log_tip = 'latest.log des laufenden Spiels im Editor öffnen; nur bei laufendem Spiel verfügbar'
        log_folder = 'Log-Ordner'
        open_log_folder = 'Log-Ordner öffnen'
        commands = 'Eigene Befehle'
        open_commands = 'Befehlsverwaltung öffnen'
        commands_tip = 'Eigene Befehle verwalten'
        online = 'Mehrspieler'
        open_online = 'Terracotta'
        online_tip = 'Terracotta-Mehrspielerfenster öffnen (Raumcode, keine Portfreigabe)'
        launcher_log = 'Launcher-Log'
        open_launcher_log_tip = 'Log dieser Launcher-Sitzung im Editor öffnen'
        previous_log = 'Letzter Start'
        open_previous_log_tip = 'Log des letzten Spielstarts im Editor öffnen'
    }
    'es' = @{
        open_game = 'Abrir carpeta del juego'
        open_game_tip = 'Abrir la carpeta de la instancia actual'
        open_schematics = 'Abrir Schematics'
        open_schematics_tip = 'Abrir la carpeta schematics de esta versión'
        open_mods = 'Abrir Mods'
        open_mods_tip = 'Abrir la carpeta mods de esta versión'
        open_saves = 'Abrir Saves'
        open_saves_tip = 'Abrir la carpeta saves de esta versión'
        refresh_bg = 'Cambiar fondo'
        refresh_bg_tip = 'Pedir a PCL que elija otra imagen de fondo al azar'
        game_log = 'Registro del juego'
        refresh_log = 'Actualizar registro'
        refresh_log_tip = 'Volver a leer el registro del juego y actualizar la página'
        notepad = 'Bloc de notas'
        open_game_log_tip = 'Abrir latest.log del juego en ejecución en el Bloc de notas; no disponible si el juego no se está ejecutando'
        log_folder = 'Carpeta de registros'
        open_log_folder = 'Abrir carpeta'
        commands = 'Comandos personalizados'
        open_commands = 'Abrir gestor'
        commands_tip = 'Abrir el gestor de comandos personalizados'
        online = 'Multijugador'
        open_online = 'Terracotta'
        online_tip = 'Abrir la ventana multijugador de Terracotta (código de sala, sin abrir puertos)'
        launcher_log = 'Registro del lanzador'
        open_launcher_log_tip = 'Abrir el registro de esta sesión del lanzador en el Bloc de notas'
        previous_log = 'Inicio anterior'
        open_previous_log_tip = 'Abrir el registro del inicio anterior en el Bloc de notas'
    }
    'pt-BR' = @{
        open_game = 'Abrir pasta do jogo'
        open_game_tip = 'Abrir a pasta da instância atual'
        open_schematics = 'Abrir Schematics'
        open_schematics_tip = 'Abrir a pasta schematics desta versão'
        open_mods = 'Abrir Mods'
        open_mods_tip = 'Abrir a pasta mods desta versão'
        open_saves = 'Abrir Saves'
        open_saves_tip = 'Abrir a pasta saves desta versão'
        refresh_bg = 'Trocar plano de fundo'
        refresh_bg_tip = 'Pedir ao PCL para escolher uma nova imagem de fundo aleatória'
        game_log = 'Log do jogo'
        refresh_log = 'Atualizar log'
        refresh_log_tip = 'Reler o log do jogo e atualizar a página inicial'
        notepad = 'Bloco de notas'
        open_game_log_tip = 'Abrir o latest.log do jogo em execução no Bloco de notas; indisponível se o jogo não estiver rodando'
        log_folder = 'Pasta de logs'
        open_log_folder = 'Abrir pasta'
        commands = 'Comandos personalizados'
        open_commands = 'Abrir gerenciador'
        commands_tip = 'Abrir o gerenciador de comandos personalizados'
        online = 'Multijogador'
        open_online = 'Terracotta'
        online_tip = 'Abrir a janela multijogador do Terracotta (código de sala, sem liberar portas)'
        launcher_log = 'Log do launcher'
        open_launcher_log_tip = 'Abrir o log desta sessão do launcher no Bloco de notas'
        previous_log = 'Execução anterior'
        open_previous_log_tip = 'Abrir o log da execução anterior no Bloco de notas'
    }
    'ru' = @{
        open_game = 'Открыть папку игры'
        open_game_tip = 'Открыть папку текущего экземпляра'
        open_schematics = 'Открыть Schematics'
        open_schematics_tip = 'Открыть папку schematics этой версии'
        open_mods = 'Открыть Mods'
        open_mods_tip = 'Открыть папку mods этой версии'
        open_saves = 'Открыть Saves'
        open_saves_tip = 'Открыть папку saves этой версии'
        refresh_bg = 'Сменить фон'
        refresh_bg_tip = 'Попросить PCL выбрать новый случайный фон'
        game_log = 'Лог игры'
        refresh_log = 'Обновить лог'
        refresh_log_tip = 'Перечитать лог игры и обновить главную страницу'
        notepad = 'Блокнот'
        open_game_log_tip = 'Открыть latest.log запущенной игры в Блокноте; недоступно, если игра не запущена'
        log_folder = 'Папка логов'
        open_log_folder = 'Открыть папку'
        commands = 'Свои команды'
        open_commands = 'Открыть управление'
        commands_tip = 'Открыть управление своими командами'
        online = 'По сети'
        open_online = 'Terracotta'
        online_tip = 'Открыть окно сетевой игры Terracotta (код комнаты, без проброса портов)'
        launcher_log = 'Лог лаунчера'
        open_launcher_log_tip = 'Открыть лог этой сессии лаунчера в Блокноте'
        previous_log = 'Прошлый запуск'
        open_previous_log_tip = 'Открыть лог прошлого запуска игры в Блокноте'
    }
    'it' = @{
        open_game = 'Apri cartella del gioco'
        open_game_tip = 'Apri la cartella di questa istanza'
        open_schematics = 'Apri Schematics'
        open_schematics_tip = 'Apri la cartella schematics di questa versione'
        open_mods = 'Apri Mods'
        open_mods_tip = 'Apri la cartella mods di questa versione'
        open_saves = 'Apri Saves'
        open_saves_tip = 'Apri la cartella saves di questa versione'
        refresh_bg = 'Cambia sfondo'
        refresh_bg_tip = 'Chiedi a PCL di scegliere una nuova immagine di sfondo casuale'
        game_log = 'Log del gioco'
        refresh_log = 'Aggiorna log'
        refresh_log_tip = 'Rileggi il log del gioco e aggiorna la homepage'
        notepad = 'Blocco note'
        open_game_log_tip = 'Apri latest.log del gioco in esecuzione nel Blocco note; non disponibile se il gioco non è avviato'
        log_folder = 'Cartella log'
        open_log_folder = 'Apri cartella'
        commands = 'Comandi personalizzati'
        open_commands = 'Apri gestione'
        commands_tip = 'Apri la gestione dei comandi personalizzati'
        online = 'Multiplayer'
        open_online = 'Terracotta'
        online_tip = 'Apri la finestra multigiocatore di Terracotta (codice stanza, senza aprire porte)'
        launcher_log = 'Log del launcher'
        open_launcher_log_tip = 'Apri il log di questa sessione del launcher nel Blocco note'
        previous_log = 'Avvio precedente'
        open_previous_log_tip = "Apri il log dell'avvio precedente nel Blocco note"
    }
    'nl' = @{
        open_game = 'Spelmap openen'
        open_game_tip = 'Map van de huidige instantie openen'
        open_schematics = 'Schematics openen'
        open_schematics_tip = 'Schematics-map van deze versie openen'
        open_mods = 'Mods openen'
        open_mods_tip = 'Mods-map van deze versie openen'
        open_saves = 'Saves openen'
        open_saves_tip = 'Saves-map van deze versie openen'
        refresh_bg = 'Achtergrond vernieuwen'
        refresh_bg_tip = 'PCL een nieuwe willekeurige achtergrondafbeelding laten kiezen'
        game_log = 'Spellog'
        refresh_log = 'Log vernieuwen'
        refresh_log_tip = 'Spellog opnieuw lezen en startpagina vernieuwen'
        notepad = 'Kladblok'
        open_game_log_tip = 'latest.log van het actieve spel in Kladblok openen; niet beschikbaar als het spel niet draait'
        log_folder = 'Logmap'
        open_log_folder = 'Logmap openen'
        commands = 'Aangepaste opdrachten'
        open_commands = 'Opdrachtenbeheer openen'
        commands_tip = 'Aangepaste opdrachten beheren'
        online = 'Multiplayer'
        open_online = 'Terracotta'
        online_tip = 'Het Terracotta-multiplayer venster openen (kamercode, geen port forwarding)'
        launcher_log = 'Launcherlog'
        open_launcher_log_tip = 'Log van deze launchersessie in Kladblok openen'
        previous_log = 'Vorige start'
        open_previous_log_tip = 'Log van de vorige spelstart in Kladblok openen'
    }
    'pl' = @{
        open_game = 'Otwórz folder gry'
        open_game_tip = 'Otwórz folder bieżącej instancji'
        open_schematics = 'Otwórz Schematics'
        open_schematics_tip = 'Otwórz folder schematics tej wersji'
        open_mods = 'Otwórz Mods'
        open_mods_tip = 'Otwórz folder mods tej wersji'
        open_saves = 'Otwórz Saves'
        open_saves_tip = 'Otwórz folder saves tej wersji'
        refresh_bg = 'Zmień tło'
        refresh_bg_tip = 'Poproś PCL o wybranie nowego losowego tła'
        game_log = 'Dziennik gry'
        refresh_log = 'Odśwież dziennik'
        refresh_log_tip = 'Wczytaj ponownie dziennik gry i odśwież stronę główną'
        notepad = 'Notatnik'
        open_game_log_tip = 'Otwórz latest.log działającej gry w Notatniku; niedostępne, gdy gra nie działa'
        log_folder = 'Folder logów'
        open_log_folder = 'Otwórz folder'
        commands = 'Własne polecenia'
        open_commands = 'Otwórz menedżer'
        commands_tip = 'Otwórz menedżer własnych poleceń'
        online = 'Gra sieciowa'
        open_online = 'Terracotta'
        online_tip = 'Otwórz okno gry wieloosobowej Terracotta (kod pokoju, bez przekierowania portów)'
        launcher_log = 'Dziennik launchera'
        open_launcher_log_tip = 'Otwórz dziennik tej sesji launchera w Notatniku'
        previous_log = 'Poprzednie uruchomienie'
        open_previous_log_tip = 'Otwórz dziennik poprzedniego uruchomienia gry w Notatniku'
    }
    'tr' = @{
        open_game = 'Oyun klasörünü aç'
        open_game_tip = 'Geçerli örnek klasörünü aç'
        open_schematics = 'Schematics aç'
        open_schematics_tip = 'Bu sürümün schematics klasörünü aç'
        open_mods = 'Mods aç'
        open_mods_tip = 'Bu sürümün mods klasörünü aç'
        open_saves = 'Saves aç'
        open_saves_tip = 'Bu sürümün saves klasörünü aç'
        refresh_bg = 'Arka planı yenile'
        refresh_bg_tip = 'PCL''nin yeni bir rastgele arka plan resmi seçmesini sağla'
        game_log = 'Oyun günlüğü'
        refresh_log = 'Günlüğü yenile'
        refresh_log_tip = 'Oyun günlüğünü yeniden oku ve ana sayfayı yenile'
        notepad = 'Not Defteri'
        open_game_log_tip = 'Çalışan oyunun latest.log dosyasını Not Defteri''nde aç; oyun çalışmıyorsa kullanılamaz'
        log_folder = 'Günlük klasörü'
        open_log_folder = 'Klasörü aç'
        commands = 'Özel komutlar'
        open_commands = 'Komut yöneticisini aç'
        commands_tip = 'Özel komut yöneticisini aç'
        online = 'Birlikte oyna'
        open_online = 'Terracotta'
        online_tip = 'Terracotta çok oyunculu penceresini aç (oda kodu, port yönlendirme yok)'
        launcher_log = 'Başlatıcı günlüğü'
        open_launcher_log_tip = 'Bu başlatıcı oturumunun günlüğünü Not Defteri''nde aç'
        previous_log = 'Önceki başlatma'
        open_previous_log_tip = "Önceki oyun başlatmasının günlüğünü Not Defteri'nde aç"
    }
    'vi' = @{
        open_game = 'Mở thư mục game'
        open_game_tip = 'Mở thư mục phiên bản hiện tại'
        open_schematics = 'Mở Schematics'
        open_schematics_tip = 'Mở thư mục schematics của phiên bản này'
        open_mods = 'Mở Mods'
        open_mods_tip = 'Mở thư mục mods của phiên bản này'
        open_saves = 'Mở Saves'
        open_saves_tip = 'Mở thư mục saves của phiên bản này'
        refresh_bg = 'Đổi ảnh nền'
        refresh_bg_tip = 'Yêu cầu PCL chọn ngẫu nhiên một ảnh nền mới'
        game_log = 'Nhật ký game'
        refresh_log = 'Làm mới nhật ký'
        refresh_log_tip = 'Đọc lại nhật ký game và làm mới trang chủ'
        notepad = 'Notepad'
        open_game_log_tip = 'Mở latest.log của game đang chạy bằng Notepad; không dùng được khi game không chạy'
        log_folder = 'Thư mục nhật ký'
        open_log_folder = 'Mở thư mục'
        commands = 'Lệnh tùy chỉnh'
        open_commands = 'Mở quản lý lệnh'
        commands_tip = 'Mở trình quản lý lệnh tùy chỉnh'
        online = 'Nhiều người'
        open_online = 'Terracotta'
        online_tip = 'Mở cửa sổ nhiều người của Terracotta (mã phòng, không cần mở cổng)'
        launcher_log = 'Nhật ký trình khởi chạy'
        open_launcher_log_tip = 'Mở nhật ký phiên trình khởi chạy này bằng Notepad'
        previous_log = 'Lần chạy trước'
        open_previous_log_tip = 'Mở nhật ký lần chạy game trước bằng Notepad'
    }
}

function Get-GuiText([string]$key) {
    $lang = $script:guiLang
    if (-not $script:guiText.ContainsKey($lang)) { $lang = 'en' }
    $table = $script:guiText[$lang]
    if ($table.ContainsKey($key)) { return [string]$table[$key] }
    if ($script:guiText['en'].ContainsKey($key)) { return [string]$script:guiText['en'][$key] }
    return $key
}
function T([string]$key) { return Get-GuiText $key }

function Resolve-LanguageCode([string]$value) {
    $v = ([string]$value).Trim().ToLowerInvariant()
    if (-not $v) { return '' }
    $v = $v.Replace('_', '-')
    switch -regex ($v) {
        '^(zh-(tw|hk|mo|hant).*|tw|繁體中文)$' { return 'zh-TW' }
        '^(zh(-hans.*|-cn.*)?|cn|chinese|简体中文)$' { return 'zh-CN' }
        '^(en(-.*)?|english)$' { return 'en' }
        '^(ja(-.*)?|japanese|日本語)$' { return 'ja' }
        '^(ko(-.*)?|korean|한국어)$' { return 'ko' }
        '^(fr(-.*)?|french|français)$' { return 'fr' }
        '^(de(-.*)?|german|deutsch)$' { return 'de' }
        '^(es(-.*)?|spanish|español)$' { return 'es' }
        '^(pt(-.*)?|portuguese|português)$' { return 'pt-BR' }
        '^(ru(-.*)?|russian|русский)$' { return 'ru' }
        '^(it(-.*)?|italian|italiano)$' { return 'it' }
        '^(nl(-.*)?|dutch|nederlands)$' { return 'nl' }
        '^(pl(-.*)?|polish|polski)$' { return 'pl' }
        '^(tr(-.*)?|turkish|türkçe)$' { return 'tr' }
        '^(vi(-.*)?|vietnamese|tiếng việt)$' { return 'vi' }
    }
    return ''
}

function Get-LanguageName([string]$code) {
    if ($script:languageNames.ContainsKey($code)) { return [string]$script:languageNames[$code] }
    return $code
}

function Get-SystemGuiLanguage {
    $forced = Resolve-LanguageCode ([string]$env:PCLHOME_LANG)
    if ($forced) { return $forced }
    try {
        $code = Resolve-LanguageCode ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
        if ($code) { return $code }
    } catch { }
    return 'en'
}

function Get-HomepageText([string]$key, [string]$lang) {
    $code = Resolve-LanguageCode $lang
    if (-not $code) { $code = 'en' }
    if ($script:pageText.ContainsKey($code) -and $script:pageText[$code].ContainsKey($key)) {
        return [string]$script:pageText[$code][$key]
    }
    if ($script:pageText['en'].ContainsKey($key)) { return [string]$script:pageText['en'][$key] }
    return ''
}

function ConvertTo-XmlText([string]$value) {
    if ($null -eq $value) { return '' }
    return ([string]$value).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function Localize-CustomPage([string]$text, [string]$lang) {
    $code = Resolve-LanguageCode $lang
    if (-not $code) { $code = 'en' }
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $script:pageText['en'].Keys) { if (-not $keys.Contains([string]$k)) { $keys.Add([string]$k) } }
    if ($script:pageText.ContainsKey($code)) {
        foreach ($k in $script:pageText[$code].Keys) { if (-not $keys.Contains([string]$k)) { $keys.Add([string]$k) } }
    }
    foreach ($key in $keys) {
        $token = '@@PCLHOME_' + $key.ToUpperInvariant() + '@@'
        if ($text.Contains($token)) {
            $text = $text.Replace($token, (ConvertTo-XmlText (Get-HomepageText $key $code)))
        }
    }
    return [regex]::Replace($text, '@@PCLHOME_[A-Z0-9_]+@@', '')
}

function Get-LocalizedError([string]$message) {
    if ($message -match '仍在运行|still running') { return (T 'err_running') }
    if ($message -match '无法判断|could not determine') { return (T 'err_flavor') }
    if ($message -match 'LogView') { return (T 'err_logview') }
    if ($message -match '不完整|损坏|incomplete|corrupted') { return (T 'err_payload') }
    return (T 'error_generic')
}

function Set-CueBanner([System.Windows.Forms.TextBox]$box, [string]$text) {
    try {
        if (-not ('PclHomeCue' -as [type])) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class PclHomeCue { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam); }'
        }
        [void][PclHomeCue]::SendMessage($box.Handle, 0x1501, [IntPtr]::Zero, $text)
    } catch { }
}

function Test-StartedFromExplorer {
    try {
        $current = $PID
        for ($i = 0; $i -lt 8; $i++) {
            $proc = Get-CimInstance Win32_Process -Filter ("ProcessId=$current") -ErrorAction SilentlyContinue
            if (-not $proc) { return $false }
            $parentId = [int]$proc.ParentProcessId
            if ($parentId -le 0) { return $false }
            $parent = Get-CimInstance Win32_Process -Filter ("ProcessId=$parentId") -ErrorAction SilentlyContinue
            if (-not $parent) { return $false }
            $name = [string]$parent.Name
            if ($name -ieq 'explorer.exe') { return $true }
            if ($name -match '^(powershell|pwsh|cmd|conhost)\.exe$') {
                $current = $parentId
                continue
            }
            return $false
        }
    } catch { }
    return $false
}

function Hide-GuiConsole {
    try {
        if (-not ('PclHomeConsole' -as [type])) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class PclHomeConsole { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }'
        }
        $handle = [PclHomeConsole]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero -and (Test-StartedFromExplorer)) {
            [void][PclHomeConsole]::ShowWindow($handle, 0)
        }
    } catch { }
}

function Get-GuiSelectedFlavor {
    if ($script:ui -and $script:ui.selectedFlavor) { return [string]$script:ui.selectedFlavor }
    return 'pcl'
}

function Set-GuiStatus([string]$key, [string]$tone, [object[]]$fmtArgs) {
    $script:guiStatusKey = $key
    $script:guiStatusTone = $tone
    if ($null -eq $fmtArgs) { $fmtArgs = @() }
    $script:guiStatusArgs = @($fmtArgs)
    if (-not $script:ui -or -not $script:ui.statusLabel) { return }
    $text = Get-GuiText $key
    if ($script:guiStatusArgs.Count -gt 0) {
        try { $text = $text -f $script:guiStatusArgs } catch { }
    }
    $script:ui.statusLabel.Text = $text
    if ($script:ui.colors.ContainsKey($tone)) {
        $script:ui.statusLabel.ForeColor = $script:ui.colors[$tone]
    }
    if ($script:ui.form -and $script:ui.form.Visible) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
    }
}

function Set-GuiButtons {
    if (-not $script:ui -or -not $script:ui.installButton -or -not $script:ui.uninstallButton) { return }
    $installed = [bool]($script:guiTarget -and (Test-Path -LiteralPath ($script:guiTarget + '\Custom.xaml')))
    $script:ui.installButton.Enabled = (-not $script:guiBusy) -and [bool]$script:guiTarget
    $script:ui.uninstallButton.Enabled = (-not $script:guiBusy) -and $installed
    $script:ui.installButton.Text = if ($installed) { T 'reinstall' } else { T 'install' }
    $script:ui.uninstallButton.Text = T 'uninstall'
}

function Select-GuiFlavor([string]$flavor, [switch]$NoRefresh) {
    if ($flavor -notin @('pcl', 'ce')) { return }
    if (-not $script:ui) { return }
    if ($script:guiSelectingFlavor) { return }
    $script:guiSelectingFlavor = $true
    try {
        $script:ui.selectedFlavor = $flavor
        foreach ($f in @('pcl', 'ce')) {
            $card = $script:ui.cards[$f]
            $card.BackColor = if ($f -eq $flavor) { $script:ui.colors.CardSelected } else { $script:ui.colors.Card }
            $card.Invalidate()
            $radio = $script:ui.radios[$f]
            $wanted = ($f -eq $flavor)
            if ($radio.Checked -ne $wanted) { $radio.Checked = $wanted }
        }
    } finally {
        $script:guiSelectingFlavor = $false
    }
    if (-not $NoRefresh) { Update-GuiTargetState -DeferFlavorSwitch }
}

function Update-GuiTargetState([switch]$DeferFlavorSwitch) {
    if (-not $script:ui -or $script:guiBusy) { return }
    $raw = ([string]$script:ui.pathBox.Text).Trim().Trim('"')
    if (-not $raw) {
        $script:guiTarget = ''
        Set-GuiStatus 'status_ready' 'muted' @()
        Set-GuiButtons
        return
    }

    $selected = Get-GuiSelectedFlavor
    $resolved = Resolve-Target $raw $selected
    $switched = $false
    if (-not $resolved) {
        $auto = Resolve-Target $raw ''
        if ($auto) {
            $detected = Get-FlavorForDir $auto
            if ($detected) {
                if ($detected -ne $selected -and -not $DeferFlavorSwitch) {
                    Select-GuiFlavor $detected -NoRefresh
                    $selected = $detected
                    $switched = $true
                }
                $resolved = $auto
            }
        }
    }
    if (-not $resolved) {
        $script:guiTarget = ''
        Set-GuiStatus 'status_not_found' 'warning' @()
        Set-GuiButtons
        return
    }

    $detected = Get-FlavorForDir $resolved
    if ($detected -and $detected -ne $selected -and -not $DeferFlavorSwitch) {
        Select-GuiFlavor $detected -NoRefresh
        $selected = $detected
        $switched = $true
    }
    $script:guiTarget = $resolved
    if ($script:ui.pathBox.Text -ne $resolved) { $script:ui.pathBox.Text = $resolved }
    if ($switched) {
        Set-GuiStatus 'status_switched' 'warning' @((Get-GuiText ('flavor_' + $selected)))
    } elseif ($DeferFlavorSwitch) {
        Set-GuiStatus 'status_folder_ready' 'muted' @($resolved)
    } else {
        Set-GuiStatus 'status_detected' 'success' @((Get-GuiText ('flavor_' + $selected)), $resolved)
    }
    Set-GuiButtons
}

function Set-GuiBusy([bool]$busy) {
    $script:guiBusy = $busy
    if (-not $script:ui) { return }
    $script:ui.form.UseWaitCursor = $busy
    $script:ui.pathBox.Enabled = -not $busy
    $script:ui.browseButton.Enabled = -not $busy
    $script:ui.detectButton.Enabled = -not $busy
    if ($script:ui.langCombo) { $script:ui.langCombo.Enabled = -not $busy }
    $script:ui.exitButton.Enabled = -not $busy
    foreach ($f in @('pcl', 'ce')) {
        $script:ui.cards[$f].Enabled = -not $busy
        $script:ui.radios[$f].Enabled = -not $busy
    }
    Set-GuiButtons
    if ($script:ui.form -and $script:ui.form.Visible) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
    }
}

function Set-GuiLanguage([string]$lang) {
    $lang = Resolve-LanguageCode $lang
    if (-not $lang) { return }
    $script:guiLang = $lang
    $script:homeLang = $lang
    if (-not $script:ui) { return }
    $script:guiUpdatingLanguage = $true
    try {
        $script:ui.form.Text = T 'app_title'
        $script:ui.headerTitle.Text = T 'app_title'
        $script:ui.headerSubtitle.Text = T 'app_subtitle'
        if ($script:ui.langCombo) {
            $idx = [Array]::IndexOf($script:languageCodes, $lang)
            if ($idx -ge 0 -and $script:ui.langCombo.SelectedIndex -ne $idx) {
                $script:ui.langCombo.SelectedIndex = $idx
            }
        }
        if ($script:ui.langCaption) { $script:ui.langCaption.Text = T 'lang_caption' }
        if ($script:ui.homeLangLabel) {
            $script:ui.homeLangLabel.Text = (T 'home_lang_note') -f (Get-LanguageName $lang)
        }
        $script:ui.sectionLauncher.Text = T 'step_launcher'
        $script:ui.launcherHint.Text = T 'step_launcher_hint'
        $script:ui.sectionFolder.Text = T 'step_folder'
        $script:ui.folderHint.Text = T 'folder_hint'
        $script:ui.browseButton.Text = T 'browse'
        $script:ui.detectButton.Text = T 'detect'
        $script:ui.exitButton.Text = T 'exit'
        $script:ui.footerLabel.Text = T 'footer'
        $script:ui.cardTitles['pcl'].Text = T 'flavor_pcl_title'
        $script:ui.cardTitles['ce'].Text = T 'flavor_ce_title'
        $script:ui.cardDescs['pcl'].Text = T 'flavor_pcl_desc'
        $script:ui.cardDescs['ce'].Text = T 'flavor_ce_desc'
        Set-CueBanner $script:ui.pathBox (T 'path_cue')
    } finally {
        $script:guiUpdatingLanguage = $false
    }
    Set-GuiButtons
    Set-GuiStatus $script:guiStatusKey $script:guiStatusTone $script:guiStatusArgs
}

function Browse-GuiFolder {
    if (-not $script:ui -or $script:guiBusy) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.ShowNewFolderButton = $false
    $flavor = Get-GuiSelectedFlavor
    if ($flavor -eq 'ce') {
        $dlg.Description = T 'browse_desc_ce'
    } elseif ($flavor -eq 'pcl') {
        $dlg.Description = T 'browse_desc_pcl'
    } else {
        $dlg.Description = T 'browse_desc_any'
    }
    $current = ([string]$script:ui.pathBox.Text).Trim()
    if ($current -and (Test-Path -LiteralPath $current -PathType Container)) {
        try { $dlg.SelectedPath = $current } catch { }
    } else {
        try { $dlg.SelectedPath = [Environment]::GetFolderPath('UserProfile') } catch { }
    }
    if ($dlg.ShowDialog($script:ui.form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ui.pathBox.Text = $dlg.SelectedPath
        Update-GuiTargetState -DeferFlavorSwitch
    }
}

function Install-Gui {
    if (-not $script:ui -or $script:guiBusy) { return }
    Update-GuiTargetState
    $target = [string]$script:guiTarget
    if (-not $target) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'select_target'), (T 'app_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $flavor = Get-GuiSelectedFlavor
    $versionState = Get-PclVersionState $target $flavor
    if ($versionState.Unsupported) {
        Show-IncompatiblePcl $versionState
        Set-GuiStatus 'status_incompatible' 'warning' @()
        return
    }

    if (Test-PclRunning $flavor) {
        $closed = Confirm-ClosePcl $flavor
        Update-GuiTargetState
        if (-not $closed) { return }
    }
    if (Test-Path -LiteralPath ($target + '\Custom.xaml')) {
        $r = [System.Windows.Forms.MessageBox]::Show((T 'confirm_overwrite'), (T 'confirm_overwrite_title'), [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        if ($r -eq [System.Windows.Forms.DialogResult]::No) {
            Uninstall-Gui -Confirmed
            return
        }
    }

    Set-GuiBusy $true
    Set-GuiStatus 'status_installing' 'muted' @()
    $ok = $false
    try {
        Invoke-Install $target $flavor $script:guiLang
        if ($script:incompatiblePcl) {
            Set-GuiStatus 'status_incompatible' 'warning' @()
            return
        }
        Set-GuiStatus 'status_installed' 'success' @($target)
        $text = (T 'done_install').Replace('{0}', $target)
        [void][System.Windows.Forms.MessageBox]::Show($text, (T 'done_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $ok = $true
    } catch {
        $msg = Get-LocalizedError ([string]$_.Exception.Message)
        Set-GuiStatus 'status_failed' 'error' @($msg)
        [void][System.Windows.Forms.MessageBox]::Show($msg, (T 'error_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        Set-GuiBusy $false
        if ($ok) { Update-GuiTargetState } else { Set-GuiButtons }
    }
}

function Uninstall-Gui([switch]$Confirmed) {
    if (-not $script:ui -or $script:guiBusy) { return }
    Update-GuiTargetState
    $target = [string]$script:guiTarget
    if (-not $target) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'select_target'), (T 'app_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    if (-not (Test-Path -LiteralPath ($target + '\Custom.xaml'))) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'not_installed'), (T 'app_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $flavor = Get-GuiSelectedFlavor
    if (Test-PclRunning $flavor) {
        $closed = Confirm-ClosePcl $flavor
        Update-GuiTargetState
        if (-not $closed) { return }
    }
    if (-not $Confirmed) {
        $text = (T 'confirm_uninstall').Replace('{0}', $target)
        $r = [System.Windows.Forms.MessageBox]::Show($text, (T 'confirm_uninstall_title'), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    Set-GuiBusy $true
    Set-GuiStatus 'status_uninstalling' 'muted' @()
    $ok = $false
    try {
        Invoke-Uninstall $target $flavor
        Set-GuiStatus 'status_uninstalled' 'success' @($target)
        $text = (T 'done_uninstall').Replace('{0}', $target)
        [void][System.Windows.Forms.MessageBox]::Show($text, (T 'done_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $ok = $true
    } catch {
        $msg = Get-LocalizedError ([string]$_.Exception.Message)
        Set-GuiStatus 'status_failed' 'error' @($msg)
        [void][System.Windows.Forms.MessageBox]::Show($msg, (T 'error_title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        Set-GuiBusy $false
        if ($ok) { Update-GuiTargetState } else { Set-GuiButtons }
    }
}

function New-GuiLabel([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Font]$font, [System.Drawing.Color]$color) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, $h)
    $label.Font = $font
    $label.ForeColor = $color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.AutoSize = $false
    return $label
}

function New-GuiButton([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Color]$back, [System.Drawing.Color]$fore, [System.Drawing.Font]$font) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, $y)
    $button.Size = New-Object System.Drawing.Size($w, $h)
    $button.BackColor = $back
    $button.ForeColor = $fore
    $button.Font = $font
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.UseVisualStyleBackColor = $false
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function New-GuiLogo {
    $bmp = New-Object System.Drawing.Bitmap 104, 104
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush($script:ui.colors.Accent)
    $g.FillEllipse($brush, 4, 4, 96, 96)
    $font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString('PCL', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, 104, 104)), $fmt)
    $g.Dispose()
    $font.Dispose()
    $brush.Dispose()
    $fmt.Dispose()
    return $bmp
}

function New-GuiCard([string]$flavor, [int]$x, [int]$y, [int]$w, [int]$h) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, $y)
    $card.Size = New-Object System.Drawing.Size($w, $h)
    $card.BackColor = $script:ui.colors.Card
    $card.Tag = $flavor
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand
    $card.Add_Paint({
        param($s, $e)
        $selected = ($script:ui.selectedFlavor -eq [string]$s.Tag)
        $color = if ($selected) { $script:ui.colors.BorderSelected } else { $script:ui.colors.Border }
        $pen = New-Object System.Drawing.Pen($color, 1)
        try { $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1) } finally { $pen.Dispose() }
    })

    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Location = New-Object System.Drawing.Point(16, 16)
    $radio.Size = New-Object System.Drawing.Size(18, 18)
    $radio.Tag = $flavor
    $radio.BackColor = [System.Drawing.Color]::Transparent
    $radio.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $radio.Cursor = [System.Windows.Forms.Cursors]::Hand
    $radio.Add_CheckedChanged({
        param($s, $e)
        if ($s.Checked) { Select-GuiFlavor ([string]$s.Tag) }
    })

    $titleFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 10.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $descFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.8, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $title = New-GuiLabel '' 44 10 270 24 $titleFont $script:ui.colors.Text
    $desc = New-GuiLabel '' 44 36 270 40 $descFont $script:ui.colors.Muted
    $title.Tag = $flavor
    $desc.Tag = $flavor
    $title.Cursor = [System.Windows.Forms.Cursors]::Hand
    $desc.Cursor = [System.Windows.Forms.Cursors]::Hand
    $card.Add_Click({ param($s, $e) Select-GuiFlavor ([string]$s.Tag) })
    $title.Add_Click({ param($s, $e) Select-GuiFlavor ([string]$s.Tag) })
    $desc.Add_Click({ param($s, $e) Select-GuiFlavor ([string]$s.Tag) })

    $card.Controls.AddRange(@($radio, $title, $desc))
    $script:ui.cards[$flavor] = $card
    $script:ui.radios[$flavor] = $radio
    $script:ui.cardTitles[$flavor] = $title
    $script:ui.cardDescs[$flavor] = $desc
    return $card
}

function Show-InstallerGui {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing | Out-Null

    # The visible form runs in powershell.exe.  A unique AppUserModelID stops
    # the taskbar from using the PowerShell icon for the installer window.
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PCLHomeInstallerShell32 {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
'@
        [void][PCLHomeInstallerShell32]::SetCurrentProcessExplicitAppUserModelID('PCL.Homepage.Installer')
    } catch { }

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $script:guiMode = $true
    $script:guiLang = Get-SystemGuiLanguage
    $script:homeLang = $script:guiLang
    $script:ui = @{
        colors = @{
            Header = [System.Drawing.Color]::FromArgb(15, 23, 42)
            HeaderSoft = [System.Drawing.Color]::FromArgb(30, 41, 59)
            Accent = [System.Drawing.Color]::FromArgb(37, 99, 235)
            AccentDark = [System.Drawing.Color]::FromArgb(29, 78, 216)
            Background = [System.Drawing.Color]::FromArgb(248, 250, 252)
            Card = [System.Drawing.Color]::FromArgb(255, 255, 255)
            CardSelected = [System.Drawing.Color]::FromArgb(239, 246, 255)
            Border = [System.Drawing.Color]::FromArgb(226, 232, 240)
            BorderSelected = [System.Drawing.Color]::FromArgb(37, 99, 235)
            Text = [System.Drawing.Color]::FromArgb(15, 23, 42)
            Muted = [System.Drawing.Color]::FromArgb(100, 116, 139)
            Success = [System.Drawing.Color]::FromArgb(22, 163, 74)
            Warning = [System.Drawing.Color]::FromArgb(217, 119, 6)
            Error = [System.Drawing.Color]::FromArgb(220, 38, 38)
            White = [System.Drawing.Color]::White
        }
        cards = @{}
        radios = @{}
        cardTitles = @{}
        cardDescs = @{}
        selectedFlavor = 'pcl'
    }
    $ui = $script:ui

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T 'app_title'
    $form.ClientSize = New-Object System.Drawing.Size(760, 560)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.BackColor = $ui.colors.Background
    $form.ForeColor = $ui.colors.Text
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $form.ShowIcon = $true
    # Use the launcher EXE icon (the PCL logo shown on GitHub) for the
    # installer window and taskbar button.
    $launcher = [string]$env:PCLHOME_LAUNCHER
    if ($launcher -and (Test-Path -LiteralPath $launcher)) {
        try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($launcher) } catch { }
    }
    $form.Add_FormClosing({
        param($s, $e)
        if ($script:guiBusy) { $e.Cancel = $true }
    })
    $script:ui.form = $form

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = [System.Windows.Forms.DockStyle]::Top
    $header.Height = 120
    $header.BackColor = $ui.colors.Header
    $form.Controls.Add($header)

    $accentLine = New-Object System.Windows.Forms.Panel
    $accentLine.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $accentLine.Height = 3
    $accentLine.BackColor = $ui.colors.Accent
    $header.Controls.Add($accentLine)

    $logoImage = New-GuiLogo
    $script:ui.logoImage = $logoImage
    $logo = New-Object System.Windows.Forms.PictureBox
    $logo.Location = New-Object System.Drawing.Point(28, 30)
    $logo.Size = New-Object System.Drawing.Size(52, 52)
    $logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $logo.BackColor = [System.Drawing.Color]::Transparent
    $logo.Image = $logoImage
    $header.Controls.Add($logo)

    $headerTitleFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 18, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $headerSubFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $headerTitle = New-GuiLabel '' 96 26 440 34 $headerTitleFont $ui.colors.White
    $headerSubtitle = New-GuiLabel '' 98 62 440 22 $headerSubFont ([System.Drawing.Color]::FromArgb(203, 213, 225))
    $header.Controls.Add($headerTitle)
    $header.Controls.Add($headerSubtitle)
    $script:ui.headerTitle = $headerTitle
    $script:ui.headerSubtitle = $headerSubtitle

    $langCaptionFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $langCaption = New-GuiLabel '' 548 14 180 18 $langCaptionFont ([System.Drawing.Color]::FromArgb(148, 163, 184))
    $header.Controls.Add($langCaption)
    $script:ui.langCaption = $langCaption

    $langCombo = New-Object System.Windows.Forms.ComboBox
    $langCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $langCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $langCombo.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $langCombo.Location = New-Object System.Drawing.Point(548, 36)
    $langCombo.Size = New-Object System.Drawing.Size(180, 28)
    $langCombo.MaxDropDownItems = 15
    $langCombo.BackColor = $ui.colors.HeaderSoft
    $langCombo.ForeColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $langCombo.Cursor = [System.Windows.Forms.Cursors]::Hand
    foreach ($code in $script:languageCodes) { [void]$langCombo.Items.Add((Get-LanguageName $code)) }
    $langCombo.Add_SelectedIndexChanged({
        if ($script:guiUpdatingLanguage) { return }
        $idx = $script:ui.langCombo.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:languageCodes.Count) {
            Set-GuiLanguage $script:languageCodes[$idx]
        }
    })
    $header.Controls.Add($langCombo)
    $script:ui.langCombo = $langCombo

    $sectionFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 11.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $hintFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $badgeFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $statusFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $buttonFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)

    $badge1 = New-GuiLabel '1' 32 140 24 24 $badgeFont $ui.colors.White
    $badge1.BackColor = $ui.colors.Accent
    $badge1.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($badge1)
    $sectionLauncher = New-GuiLabel '' 66 138 660 26 $sectionFont $ui.colors.Text
    $form.Controls.Add($sectionLauncher)
    $launcherHint = New-GuiLabel '' 66 166 660 20 $hintFont $ui.colors.Muted
    $form.Controls.Add($launcherHint)
    $script:ui.sectionLauncher = $sectionLauncher
    $script:ui.launcherHint = $launcherHint

    $cardPcl = New-GuiCard 'pcl' 32 194 330 86
    $cardCe = New-GuiCard 'ce' 378 194 330 86
    $form.Controls.Add($cardPcl)
    $form.Controls.Add($cardCe)

    $badge2 = New-GuiLabel '2' 32 300 24 24 $badgeFont $ui.colors.White
    $badge2.BackColor = $ui.colors.Accent
    $badge2.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($badge2)
    $sectionFolder = New-GuiLabel '' 66 298 660 26 $sectionFont $ui.colors.Text
    $form.Controls.Add($sectionFolder)
    $folderHint = New-GuiLabel '' 66 326 660 20 $hintFont $ui.colors.Muted
    $form.Controls.Add($folderHint)
    $script:ui.sectionFolder = $sectionFolder
    $script:ui.folderHint = $folderHint

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(32, 352)
    $pathBox.Size = New-Object System.Drawing.Size(450, 28)
    $pathBox.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pathBox.BackColor = [System.Drawing.Color]::White
    $pathBox.ForeColor = $ui.colors.Text
    $pathBox.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $e.SuppressKeyPress = $true
            Update-GuiTargetState -DeferFlavorSwitch
        }
    })
    $form.Controls.Add($pathBox)
    $script:ui.pathBox = $pathBox

    $browseButton = New-GuiButton '' 490 352 120 30 $ui.colors.Card $ui.colors.Text $hintFont
    $browseButton.FlatAppearance.BorderSize = 1
    $browseButton.FlatAppearance.BorderColor = $ui.colors.Border
    $browseButton.Add_Click({ Browse-GuiFolder })
    $form.Controls.Add($browseButton)
    $script:ui.browseButton = $browseButton

    $detectButton = New-GuiButton '' 618 352 110 30 $ui.colors.Card $ui.colors.Text $hintFont
    $detectButton.FlatAppearance.BorderSize = 1
    $detectButton.FlatAppearance.BorderColor = $ui.colors.Border
    $detectButton.Add_Click({ Update-GuiTargetState -DeferFlavorSwitch })
    $form.Controls.Add($detectButton)
    $script:ui.detectButton = $detectButton

    $statusLabel = New-GuiLabel '' 32 394 696 40 $statusFont $ui.colors.Muted
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($statusLabel)
    $script:ui.statusLabel = $statusLabel

    $installButton = New-GuiButton '' 32 452 180 42 $ui.colors.Accent $ui.colors.White $buttonFont
    $installButton.Add_MouseEnter({ $script:ui.installButton.BackColor = $script:ui.colors.AccentDark })
    $installButton.Add_MouseLeave({ $script:ui.installButton.BackColor = $script:ui.colors.Accent })
    $installButton.Add_Click({ Install-Gui })
    $form.Controls.Add($installButton)
    $script:ui.installButton = $installButton

    $uninstallButton = New-GuiButton '' 224 452 140 42 ([System.Drawing.Color]::FromArgb(226, 232, 240)) $ui.colors.Text $buttonFont
    $uninstallButton.FlatAppearance.BorderSize = 1
    $uninstallButton.FlatAppearance.BorderColor = $ui.colors.Border
    $uninstallButton.Add_MouseEnter({ $script:ui.uninstallButton.BackColor = [System.Drawing.Color]::FromArgb(203, 213, 225) })
    $uninstallButton.Add_MouseLeave({ $script:ui.uninstallButton.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240) })
    $uninstallButton.Add_Click({ Uninstall-Gui })
    $form.Controls.Add($uninstallButton)
    $script:ui.uninstallButton = $uninstallButton

    $exitButton = New-GuiButton '' 638 452 90 42 ([System.Drawing.Color]::FromArgb(226, 232, 240)) $ui.colors.Text $buttonFont
    $exitButton.FlatAppearance.BorderSize = 1
    $exitButton.FlatAppearance.BorderColor = $ui.colors.Border
    $exitButton.Add_MouseEnter({ $script:ui.exitButton.BackColor = [System.Drawing.Color]::FromArgb(203, 213, 225) })
    $exitButton.Add_MouseLeave({ $script:ui.exitButton.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240) })
    $exitButton.Add_Click({ $script:ui.form.Close() })
    $form.Controls.Add($exitButton)
    $script:ui.exitButton = $exitButton

    $homeLangFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $homeLangLabel = New-GuiLabel '' 376 452 244 42 $homeLangFont $ui.colors.Muted
    $homeLangLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($homeLangLabel)
    $script:ui.homeLangLabel = $homeLangLabel

    $footerFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $footerLabel = New-GuiLabel '' 32 516 696 20 $footerFont $ui.colors.Muted
    $form.Controls.Add($footerLabel)
    $script:ui.footerLabel = $footerLabel

    $form.AcceptButton = $installButton
    $form.CancelButton = $exitButton

    Select-GuiFlavor 'pcl' -NoRefresh
    Set-GuiLanguage $script:guiLang
    Update-GuiTargetState
    Hide-GuiConsole
    [System.Windows.Forms.Application]::Run($form)
    try { $form.Dispose() } catch { }
    if ($script:ui.logoImage) { try { $script:ui.logoImage.Dispose() } catch { } }
}

# ==== main ====
$script:homeLang = Get-SystemGuiLanguage
if (-not $script:arg1 -and -not $script:testMode) {
    try {
        Show-InstallerGui
        exit 0
    } catch {
        $guiError = [string]$_.Exception.Message
        try {
            Add-Type -AssemblyName System.Windows.Forms | Out-Null
            [void][System.Windows.Forms.MessageBox]::Show($guiError, 'PCL Custom Homepage Installer / PCL 自定义主页安装器', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } catch {
            Write-Host $guiError -ForegroundColor Red
        }
        exit 3
    }
}

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

    # Same preflight as the GUI: reject an unsupported launcher before the
    # overwrite prompt, before waiting for PCL to close and before any writes.
    $versionState = Get-PclVersionState $target $script:flavor
    if ($versionState.Unsupported) {
        Show-IncompatiblePcl $versionState
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
    if ($script:incompatiblePcl) { End-Pause; exit 0 }
    End-Pause
    exit 0
} catch {
    SayErr ('出错：' + [string]$_.Exception.Message)
    Say '可以尝试：退出 PCL 后重试；或把 PCL 文件夹放到可写的位置；或以管理员身份运行。'
    End-Pause
    exit 3
}
