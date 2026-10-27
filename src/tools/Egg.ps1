# Egg.ps1 v5 - easter egg of the custom homepage.
# Press Shift+X+C while the PCL window is focused: the background watcher
# (RefreshLog.ps1 -Watch) opens this script through PCLHomeLaunch.vbs.
# A small WinForms dialog asks whether to use the theme picture
# (Pictures\CustomHomeBG.jpg) as the Windows desktop wallpaper and the
# matching still (Pictures\CustomHomeLock.png) as the lock screen picture.
# There is no console window at any point.  The dialog closes by itself
# ten seconds after the job is done; on failure the status reads: 可惜了
#
# Sandbox switches (used by the sandbox test, never in normal use):
#   PCLTOOLS_EGG_MOCK=ok|fail  same flow, but nothing real is touched
#   PCLTOOLS_EGG_AUTO=yes|no   answer without showing the dialog
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
$script:auto    = [string]$env:PCLTOOLS_EGG_AUTO
$script:wait    = 10000
try { if ($env:PCLTOOLS_EGG_WAIT) { $script:wait = [int]$env:PCLTOOLS_EGG_WAIT } } catch { }
if ($script:wait -lt 1) { $script:wait = 1 }

function ELog([string]$s) {
    try { [IO.File]::AppendAllText($script:log, ('[' + (Get-Date).ToString('yy/MM/dd HH:mm:ss') + '] egg: ' + $s + "`r`n"), [Text.UTF8Encoding]::new($true)) } catch { }
}

function Add-EggNative {
    if (-not ('EggNative' -as [type])) {
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class EggNative{[DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool SystemParametersInfo(int a,int b,string c,int d);}'
    }
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

function Invoke-Theme {
    if ($script:mock) {
        ELog ('mock: ' + $script:mock)
        return ($script:mock -eq 'ok')
    }
    $wall = $script:wallJpg
    if (-not [IO.File]::Exists($wall)) { $wall = $script:lockImg }
    if (-not [IO.File]::Exists($wall)) {
        ELog 'no wallpaper image found'
        return $false
    }
    ELog ('wallpaper image: ' + $wall)
    $ok = Set-DesktopWallpaper $wall
    $lockOk = Set-LockPicture $script:lockImg
    ELog ('lock screen: ' + [string]$lockOk)
    return $ok
}

# Some tests and command-line checks do not have a desktop to show a form on.
# They can answer through PCLTOOLS_EGG_AUTO and get the same result silently.
if ($script:mock -and -not $script:auto) { $script:auto = 'yes' }
if ($script:auto -match '^(?i:yes|no)$') {
    if ($script:auto -match '^(?i:no)$') {
        ELog 'declined'
        exit 0
    }
    ELog 'accepted'
    $ok = Invoke-Theme
    ELog ('result: ' + [string]$ok)
    Start-Sleep -Milliseconds $script:wait
    exit 0
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $script:form = New-Object Windows.Forms.Form
    $script:form.Text = 'PCL 自定义主页'
    $script:form.StartPosition = 'CenterScreen'
    $script:form.FormBorderStyle = 'FixedDialog'
    $script:form.MaximizeBox = $false
    $script:form.MinimizeBox = $false
    $script:form.ShowInTaskbar = $true
    $script:form.TopMost = $true
    $script:form.ClientSize = New-Object Drawing.Size(420, 180)

    $title = New-Object Windows.Forms.Label
    $title.Text = '要把主题图片设为 Windows 桌面壁纸吗？'
    $title.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Regular)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(24, 24)
    $script:form.Controls.Add($title)

    $detail = New-Object Windows.Forms.Label
    $detail.Text = '桌面和锁屏都会使用这张主题图片；选择 No 则不做任何修改。'
    $detail.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Regular)
    $detail.ForeColor = [Drawing.Color]::DimGray
    $detail.AutoSize = $true
    $detail.Location = New-Object Drawing.Point(26, 58)
    $script:form.Controls.Add($detail)

    $script:yes = New-Object Windows.Forms.Button
    $script:yes.Text = 'Yes'
    $script:yes.Size = New-Object Drawing.Size(92, 30)
    $script:yes.Location = New-Object Drawing.Point(214, 120)
    $script:form.Controls.Add($script:yes)

    $script:no = New-Object Windows.Forms.Button
    $script:no.Text = 'No'
    $script:no.Size = New-Object Drawing.Size(92, 30)
    $script:no.Location = New-Object Drawing.Point(312, 120)
    $script:form.Controls.Add($script:no)

    $script:bar = New-Object Windows.Forms.ProgressBar
    $script:bar.Minimum = 0
    $script:bar.Maximum = 100
    $script:bar.Value = 0
    $script:bar.Size = New-Object Drawing.Size(372, 18)
    $script:bar.Location = New-Object Drawing.Point(24, 88)
    $script:bar.Visible = $false
    $script:form.Controls.Add($script:bar)

    $script:status = New-Object Windows.Forms.Label
    $script:status.Text = ''
    $script:status.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10, [Drawing.FontStyle]::Regular)
    $script:status.AutoSize = $false
    $script:status.TextAlign = 'MiddleCenter'
    $script:status.Size = New-Object Drawing.Size(372, 24)
    $script:status.Location = New-Object Drawing.Point(24, 112)
    $script:status.Visible = $false
    $script:form.Controls.Add($script:status)

    $script:timer = New-Object Windows.Forms.Timer
    $script:timer.Interval = $script:wait
    $script:timer.Add_Tick({
        $script:timer.Stop()
        $script:form.Close()
    })

    function Set-EggProgress([int]$value, [string]$text, [bool]$failed) {
        try {
            $script:bar.Value = [Math]::Min(100, [Math]::Max(0, $value))
            $script:status.Text = $text
            if ($failed) { $script:status.ForeColor = [Drawing.Color]::Firebrick }
            else { $script:status.ForeColor = [Drawing.Color]::ForestGreen }
            [Windows.Forms.Application]::DoEvents()
        } catch { }
    }

    $script:no.Add_Click({
        ELog 'declined'
        $script:form.Close()
    })

    $script:yes.Add_Click({
        ELog 'accepted'
        $script:yes.Visible = $false
        $script:no.Visible = $false
        $script:bar.Visible = $true
        $script:status.Visible = $true
        Set-EggProgress 25 '正在设置...' $false
        $ok = Invoke-Theme
        ELog ('result: ' + [string]$ok)
        if ($ok) { Set-EggProgress 100 '完成' $false }
        else { Set-EggProgress 100 '可惜了' $true }
        $script:timer.Start()
    })

    $script:form.Add_Shown({
        $script:form.Activate()
        $script:form.BringToFront()
    })

    [void]$script:form.ShowDialog()
} catch {
    ELog ('dialog failed: ' + [string]$_.Exception.Message)
}
exit 0
