# 将当前源码快照发布到 GitHub。
# 使用已登录的 GitHub CLI，通过 Git Data API 创建一次提交，不需要本地安装 Git。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1 -Message "Fix ..."
[CmdletBinding()]
param(
    [string]$Message = 'Update PCL homepage installer source'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $root

$owner = 'XC-Xin-Cheng'
$repo = 'PCL-Homepage'
$branch = 'main'
$apiBase = "repos/$owner/$repo"
$env:GH_NO_UPDATE_NOTIFIER = '1'
$env:GH_PAGER = ''

function Resolve-Gh {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    $fallback = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\gh.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw '未找到 GitHub CLI (gh)。请先安装 gh，并执行 gh auth login。'
}

function Write-Utf8Json([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-GhApi([string[]]$Arguments) {
    $errFile = Join-Path $script:temp 'gh-stderr.txt'
    $out = & $script:gh api @Arguments 2> $errFile
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $err = ''
        if (Test-Path -LiteralPath $errFile) {
            $err = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
        }
        throw ("gh api 失败（退出码 $code）：`n" + $err)
    }
    return (($out | Out-String).Trim())
}

function Get-RelativePath([string]$FullName) {
    $base = [IO.Path]::GetFullPath($script:root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($FullName)
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "文件不在项目目录内：$FullName"
    }
    return $full.Substring($base.Length).Replace('\', '/')
}

$script:root = $root
$script:gh = Resolve-Gh
$script:temp = Join-Path ([IO.Path]::GetTempPath()) ('pclhome-publish-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:temp -Force | Out-Null

try {
    $null = & $script:gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub CLI 尚未登录。请先运行：gh auth login'
    }

    $files = New-Object System.Collections.ArrayList
    foreach ($name in @('build.ps1', 'README.md', '源码说明.txt', '.gitignore', 'publish.ps1', 'AGENTS.md', 'LICENSE')) {
        $p = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            throw "缺少文件：$name"
        }
        [void]$files.Add((Get-Item -LiteralPath $p))
    }

    $srcDir = Join-Path $root 'src'
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
        throw '缺少 src 目录'
    }
    Get-ChildItem -LiteralPath $srcDir -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]InjectDll\.ps1$'
    } | ForEach-Object { [void]$files.Add($_) }

    $files = @($files | Sort-Object FullName -Unique)
    Write-Host ("准备发布 {0} 个文件..." -f $files.Count)

    $parentSha = Invoke-GhApi @("$apiBase/git/ref/heads/$branch", '--jq', '.object.sha')
    if (-not $parentSha) { throw '无法读取 main 分支当前提交。' }
    $baseTreeSha = Invoke-GhApi @("$apiBase/git/commits/$parentSha", '--jq', '.tree.sha')
    if (-not $baseTreeSha) { throw '无法读取当前提交的 tree。' }
    Write-Host ("当前提交：{0}" -f $parentSha)
    Write-Host ("基础 tree：{0}" -f $baseTreeSha)

    $treeUrl = "$apiBase/git/trees/" + $baseTreeSha + '?recursive=1'
    $treeJson = Invoke-GhApi @($treeUrl)
    $treeObject = $treeJson | ConvertFrom-Json
    $existing = @{}
    foreach ($item in @($treeObject.tree)) {
        if ($item.type -eq 'blob') { $existing[$item.path] = $true }
    }

    $entries = New-Object System.Collections.ArrayList
    $newPaths = @{}
    $i = 0
    foreach ($file in $files) {
        $i++
        $relative = Get-RelativePath $file.FullName
        $newPaths[$relative] = $true
        $payload = @{
            content  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
            encoding = 'base64'
        }
        $jsonPath = Join-Path $script:temp ("blob-{0:D3}.json" -f $i)
        Write-Utf8Json $jsonPath $payload
        $blobSha = Invoke-GhApi @('--method', 'POST', "$apiBase/git/blobs", '--input', $jsonPath, '--jq', '.sha')
        if (-not $blobSha) { throw "创建 blob 失败：$relative" }
        [void]$entries.Add(@{
            path = $relative
            mode = '100644'
            type = 'blob'
            sha  = $blobSha
        })
        Write-Host ("  + {0}" -f $relative)
    }

    $deletePaths = @(
        'BgRefresh.ps1',
        'CustomHomeBG.jpg',
        'CustomTools.bat',
        'Egg.ps1',
        'RefreshLog.ps1',
        'VideoWall.ps1',
        'header.bat',
        'img3.png',
        'installer.ps1',
        'page.xaml',
        'readme.txt',
        'src/tools/InjectDll.ps1'
    )
    $deleted = @{}
    foreach ($path in $deletePaths) {
        if ($existing.ContainsKey($path) -and -not $deleted.ContainsKey($path)) {
            [void]$entries.Add(@{
                path = $path
                mode = '100644'
                type = 'blob'
                sha  = $null
            })
            $deleted[$path] = $true
            Write-Host ("  - {0}" -f $path)
        }
    }
    foreach ($path in @($existing.Keys)) {
        if ($path -like 'src/*' -and -not $newPaths.ContainsKey($path) -and -not $deleted.ContainsKey($path)) {
            [void]$entries.Add(@{
                path = $path
                mode = '100644'
                type = 'blob'
                sha  = $null
            })
            $deleted[$path] = $true
            Write-Host ("  - {0}" -f $path)
        }
    }

    $treePayload = @{
        base_tree = $baseTreeSha
        tree      = @($entries)
    }
    $treePath = Join-Path $script:temp 'tree.json'
    Write-Utf8Json $treePath $treePayload
    $treeSha = Invoke-GhApi @('--method', 'POST', "$apiBase/git/trees", '--input', $treePath, '--jq', '.sha')
    if (-not $treeSha) { throw '创建 tree 失败。' }

    $commitPayload = @{
        message = $Message
        tree    = $treeSha
        parents = @($parentSha)
    }
    $commitPath = Join-Path $script:temp 'commit.json'
    Write-Utf8Json $commitPath $commitPayload
    $newCommit = Invoke-GhApi @('--method', 'POST', "$apiBase/git/commits", '--input', $commitPath, '--jq', '.sha')
    if (-not $newCommit) { throw '创建 commit 失败。' }

    $refPayload = @{
        sha   = $newCommit
        force = $false
    }
    $refPath = Join-Path $script:temp 'ref.json'
    Write-Utf8Json $refPath $refPayload
    $null = Invoke-GhApi @('--method', 'PATCH', "$apiBase/git/refs/heads/$branch", '--input', $refPath, '--jq', '.object.sha')

    Write-Host ''
    Write-Host ("已发布：{0}" -f $newCommit)
    Write-Host ("https://github.com/{0}/{1}/commit/{2}" -f $owner, $repo, $newCommit)
}
finally {
    if (Test-Path -LiteralPath $script:temp) {
        Remove-Item -LiteralPath $script:temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
