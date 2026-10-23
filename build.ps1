# Build PCL主页安装[支持CE].bat from src\.
# The .bat keeps the original one-file layout:
#   header + ::SCRIPT-BEGIN installer + base64 Custom.xaml + optional lock image.
# Custom.xaml itself embeds the helper scripts and the background image inside
# a trailing XML comment, which CustomTools.bat can self-heal from.
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$srcDir = Join-Path $root 'src'
$toolsDir = Join-Path $srcDir 'tools'
$buildDir = Join-Path $root 'build'
$distDir = Join-Path $root 'dist'
[void][IO.Directory]::CreateDirectory($buildDir)
[void][IO.Directory]::CreateDirectory($distDir)

function Read-Utf8([string]$path) {
    $t = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false))
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t = $t.Replace("`r`n", "`n").Replace("`r", "`n")
    return $t
}
function Trim-FinalNewlines([string]$t) {
    return $t.TrimEnd("`n")
}
function Get-B64Lines([byte[]]$bytes, [int]$width) {
    $b64 = [Convert]::ToBase64String($bytes)
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $b64.Length; $i += $width) {
        $n = [Math]::Min($width, $b64.Length - $i)
        $out.Add($b64.Substring($i, $n))
    }
    return $out
}
function Assert-True([bool]$cond, [string]$message) {
    if (-not $cond) { throw $message }
}

# ==== read inputs ====
$pageText = Trim-FinalNewlines (Read-Utf8 (Join-Path $srcDir 'page.xaml'))
$installerText = Trim-FinalNewlines (Read-Utf8 (Join-Path $srcDir 'installer.ps1'))
$headerText = Read-Utf8 (Join-Path $srcDir 'header.bat')
$readmeText = Trim-FinalNewlines (Read-Utf8 (Join-Path $srcDir 'readme.txt'))
$toolFiles = @(
    @{ Name = 'CustomTools.bat'; Marker = 'BAT' },
    @{ Name = 'RefreshLog.ps1'; Marker = 'PS1' },
    @{ Name = 'BgRefresh.ps1'; Marker = 'PS2' },
    @{ Name = 'Egg.ps1'; Marker = 'PS3' },
    @{ Name = 'VideoWall.ps1'; Marker = 'PS4' }
)
$tools = @{}
foreach ($t in $toolFiles) {
    $tools[$t.Name] = Trim-FinalNewlines (Read-Utf8 (Join-Path $toolsDir $t.Name))
    Assert-True (-not $tools[$t.Name].Contains('--')) ($t.Name + ' contains a double hyphen; it cannot be embedded in an XML comment')
    Assert-True (-not $tools[$t.Name].Contains('xmlns')) ($t.Name + ' contains the literal word xmlns')
}

# ==== trailing XML comment with the helper backups ====
$payloadLines = New-Object System.Collections.Generic.List[string]
foreach ($line in ($pageText -split "`n")) { $payloadLines.Add($line) }
$payloadLines.Add('')
$payloadLines.Add('<!--')
$payloadLines.Add('==== 工具文件内嵌备份 ====')
$payloadLines.Add('下面保存着 CustomTools.bat、RefreshLog.ps1、BgRefresh.ps1、Egg.ps1、VideoWall.ps1 的完整内容，')
$payloadLines.Add('以及共享背景图 CustomHomeBG.jpg 的 base64 内容；主页按钮或 CustomTools.bat')
$payloadLines.Add('发现这些文件缺失时，会自动从这份备份重建，并把背景图导入 PCL\Pictures 文件夹。')
$payloadLines.Add('请勿修改 @@ 标记行，也请勿在本注释内加入连续的两个减号。')
foreach ($t in $toolFiles) {
    $payloadLines.Add('@@YSM-TOOLS-' + $t.Marker + '@@')
    foreach ($line in ($tools[$t.Name] -split "`n")) { $payloadLines.Add($line) }
}
$payloadLines.Add('@@YSM-TOOLS-IMG@@')
$bgBytes = [IO.File]::ReadAllBytes((Join-Path $toolsDir 'CustomHomeBG.jpg'))
foreach ($line in (Get-B64Lines $bgBytes 100)) { $payloadLines.Add($line) }
$payloadLines.Add('@@YSM-TOOLS-END@@')
$payloadLines.Add('-->')
$payloadText = ($payloadLines -join "`n") + "`n"

# The tool backup must be legal inside an XML comment.
$start = -1
for ($i = 0; $i -lt $payloadLines.Count; $i++) {
    if ($payloadLines[$i] -eq '==== 工具文件内嵌备份 ====') { $start = $i - 1; break }
}
$end = -1
for ($i = $payloadLines.Count - 1; $i -ge 0; $i--) {
    if ($payloadLines[$i] -eq '-->') { $end = $i; break }
}
Assert-True ($start -ge 0 -and $end -gt $start) 'tool backup comment markers are missing'
$commentBody = ($payloadLines[($start + 1)..($end - 1)] -join "`n")
Assert-True (-not $commentBody.Contains('--')) 'tool backup comment contains --'
Assert-True (-not $commentBody.Contains('xmlns')) 'tool backup comment contains literal xmlns'

$payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes($payloadText)
$payloadPath = Join-Path $buildDir 'Custom.xaml'
[IO.File]::WriteAllBytes($payloadPath, $payloadBytes)

# ==== batch file ====
$headerCut = $headerText.IndexOf("`n::SCRIPT-BEGIN")
Assert-True ($headerCut -ge 0) 'header.bat has no ::SCRIPT-BEGIN marker'
$headerPart = $headerText.Substring(0, $headerCut + 1).TrimEnd("`n")
$installerLines = $installerText -split "`n"

$batLines = New-Object System.Collections.Generic.List[string]
foreach ($line in ($headerPart -split "`n")) { $batLines.Add($line) }
$batLines.Add('::SCRIPT-BEGIN')
foreach ($line in $installerLines) { $batLines.Add('::' + $line) }
$batLines.Add('::SCRIPT-END')
$batLines.Add('::DATA-BEGIN')
foreach ($line in (Get-B64Lines $payloadBytes 100)) { $batLines.Add('::' + $line) }
$batLines.Add('::DATA-END')
$batLines.Add('::IMG3-BEGIN')
$lockBytes = [IO.File]::ReadAllBytes((Join-Path $srcDir 'img3.png'))
foreach ($line in (Get-B64Lines $lockBytes 100)) { $batLines.Add('::' + $line) }
$batLines.Add('::IMG3-END')

$maxLen = ($batLines | Measure-Object -Property Length -Maximum).Maximum
Assert-True ($maxLen -lt 8192) ('batch line too long: ' + $maxLen)
$batText = ($batLines -join "`r`n") + "`r`n"
$batPath = Join-Path $distDir 'PCL主页安装[支持CE].bat'
[IO.File]::WriteAllText($batPath, $batText, [Text.UTF8Encoding]::new($false))

# ==== verify the generated file can be decoded exactly like the header does ====
$checkLines = [IO.File]::ReadAllLines($batPath, [Text.Encoding]::UTF8)
$di = [Array]::IndexOf($checkLines, '::DATA-BEGIN')
$dj = [Array]::IndexOf($checkLines, '::DATA-END')
$si = [Array]::IndexOf($checkLines, '::SCRIPT-BEGIN')
$sj = [Array]::IndexOf($checkLines, '::SCRIPT-END')
$ii = [Array]::IndexOf($checkLines, '::IMG3-BEGIN')
$ij = [Array]::IndexOf($checkLines, '::IMG3-END')
Assert-True ($di -ge 0 -and $dj -gt $di) 'generated data markers are missing'
Assert-True ($si -ge 0 -and $sj -gt $si) 'generated script markers are missing'
Assert-True ($ii -ge 0 -and $ij -gt $ii) 'generated image markers are missing'
Assert-True (@($checkLines | Where-Object { $_ -eq '::DATA-BEGIN' }).Count -eq 1) 'duplicate data marker'
Assert-True (@($checkLines | Where-Object { $_ -eq '::SCRIPT-BEGIN' }).Count -eq 1) 'duplicate script marker'
Assert-True (@($checkLines | Where-Object { $_ -eq '::IMG3-BEGIN' }).Count -eq 1) 'duplicate image marker'

$b64 = New-Object Text.StringBuilder
for ($k = $di + 1; $k -lt $dj; $k++) {
    if ($checkLines[$k].Length -gt 2) { [void]$b64.Append($checkLines[$k].Substring(2)) }
}
Assert-True ([Convert]::FromBase64String($b64.ToString()).Length -eq $payloadBytes.Length) 'data segment length mismatch'
Assert-True ([Convert]::ToBase64String([Convert]::FromBase64String($b64.ToString())) -eq [Convert]::ToBase64String($payloadBytes)) 'data segment roundtrip mismatch'

$ins = New-Object Text.StringBuilder
for ($k = $si + 1; $k -lt $sj; $k++) {
    if ($checkLines[$k].Length -ge 2) { [void]$ins.AppendLine($checkLines[$k].Substring(2)) }
}
$insText = $ins.ToString().Replace("`r`n", "`n").TrimEnd("`n")
Assert-True ($insText -eq $installerText) 'installer segment roundtrip mismatch'

$img = New-Object Text.StringBuilder
for ($k = $ii + 1; $k -lt $ij; $k++) {
    if ($checkLines[$k].Length -gt 2) { [void]$img.Append($checkLines[$k].Substring(2)) }
}
Assert-True ([Convert]::FromBase64String($img.ToString()).Length -eq $lockBytes.Length) 'lock image segment length mismatch'

# ==== verify the trailing comment still yields the same tool files ====
$payloadCheck = [IO.File]::ReadAllText($payloadPath, [Text.Encoding]::UTF8)
for ($ti = 0; $ti -lt $toolFiles.Count; $ti++) {
    $t = $toolFiles[$ti]
    $next = if ($ti -lt $toolFiles.Count - 1) { $toolFiles[$ti + 1].Marker } else { 'IMG' }
    $m = [regex]::Match($payloadCheck, '(?sm)^@@YSM-TOOLS-' + [regex]::Escape($t.Marker) + '@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-' + [regex]::Escape($next) + '@@')
    Assert-True ($m.Success) ('tool marker missing in Custom.xaml: ' + $t.Marker)
    Assert-True ($m.Groups[1].Value -eq $tools[$t.Name]) ('tool text mismatch in Custom.xaml: ' + $t.Name)
}

# ==== launcher executable ====
$launcherSource = Join-Path $srcDir 'launcher.cs'
$iconPath = Join-Path $srcDir 'app.ico'
Assert-True (Test-Path -LiteralPath $launcherSource) 'src\launcher.cs is missing'
Assert-True (Test-Path -LiteralPath $iconPath) 'src\app.ico is missing'

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Assert-True ([bool]$csc) 'csc.exe (.NET Framework 4.x) was not found'

$exePath = Join-Path $distDir 'PCL主页安装[支持CE].exe'
if (Test-Path -LiteralPath $exePath) { Remove-Item -LiteralPath $exePath -Force }
$cscArgs = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    ('/out:' + $exePath),
    ('/resource:' + $batPath + ',PCLHomePayload.bat'),
    ('/win32icon:' + $iconPath),
    '/r:System.dll',
    '/r:System.Core.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.Drawing.dll',
    $launcherSource
)
& $csc $cscArgs
Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exePath)) 'launcher compile failed'

# ==== readme and zip ====
$readmePath = Join-Path $distDir 'PCL主页安装[支持CE]-使用说明.txt'
[IO.File]::WriteAllText($readmePath, ($readmeText -replace "`n", "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
$zipPath = Join-Path $distDir 'PCL主页安装[支持CE].zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @($exePath, $readmePath)) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $file,
            [System.IO.Path]::GetFileName($file),
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
}

Write-Output ('built: ' + $exePath)
Write-Output ('payload: ' + $payloadBytes.Length + ' bytes, data lines: ' + (Get-B64Lines $payloadBytes 100).Count)
Write-Output ('batch: ' + (Get-Item -LiteralPath $batPath).Length + ' bytes, max line: ' + $maxLen)
Write-Output ('exe: ' + (Get-Item -LiteralPath $exePath).Length + ' bytes')
Write-Output ('zip: ' + $zipPath)
