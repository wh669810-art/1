[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "整理结果目录不存在：$Root"
}

$imageExtensions = @('.jpg', '.jpeg', '.png', '.webp')
$videoExtensions = @('.mp4', '.mov', '.avi', '.mkv', '.wmv', '.webm')
$products = @(Get-ChildItem -LiteralPath $Root -Directory)
$records = @()
$issues = @()
$allImageFiles = @()

foreach ($product in $products) {
    $childDirs = @(Get-ChildItem -LiteralPath $product.FullName -Directory)
    $singleInnerDirs = @($childDirs | Where-Object { $_.Name -match '原图模特$' })

    if ($singleInnerDirs.Count -eq 1 -and $childDirs.Count -eq 1) {
        $leaves = @([pscustomobject]@{
            Product = $product
            Color = '单色'
            OuterRoot = $product.FullName
            InnerDir = $singleInnerDirs[0].FullName
        })
    }
    elseif ($singleInnerDirs.Count -eq 0 -and $childDirs.Count -gt 0) {
        $leaves = @()
        foreach ($colorDir in $childDirs) {
            $innerDirs = @(Get-ChildItem -LiteralPath $colorDir.FullName -Directory | Where-Object { $_.Name -match '原图模特$' })
            if ($innerDirs.Count -ne 1) {
                $issues += "颜色层缺少唯一图片子文件夹：$($product.Name) / $($colorDir.Name)"
                continue
            }
            $leaves += [pscustomobject]@{
                Product = $product
                Color = $colorDir.Name
                OuterRoot = $colorDir.FullName
                InnerDir = $innerDirs[0].FullName
            }
        }
    }
    else {
        $issues += "产品目录层级无法判定为单色或多色：$($product.Name)"
        continue
    }

    foreach ($leaf in $leaves) {
        $outer = @(Get-ChildItem -LiteralPath $leaf.OuterRoot -File | Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() })
        $inner = @(Get-ChildItem -LiteralPath $leaf.InnerDir -File | Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() })
        $files = @($outer + $inner)
        $allImageFiles += $files
        $sizeFiles = @($inner | Where-Object { $_.Name -match '(?i)尺码|规格|size' })

        if ($outer.Count -ne 1) {
            $issues += "外层主图数量不是 1：$($product.Name) / $($leaf.Color)，实际 $($outer.Count)"
        }
        if ($inner.Count -lt 4) {
            $issues += "内层精选图少于 4 张：$($product.Name) / $($leaf.Color)，实际 $($inner.Count)"
        }
        $duplicateGroups = @($files | Get-FileHash -Algorithm SHA256 | Group-Object Hash | Where-Object { $_.Count -gt 1 })
        if ($duplicateGroups.Count -gt 0) {
            $issues += "同一颜色内存在完全重复图片：$($product.Name) / $($leaf.Color)"
        }
        $records += [pscustomobject]@{
            Product = $product.Name
            Color = $leaf.Color
            OuterCount = $outer.Count
            InnerCount = $inner.Count
            SizeCount = $sizeFiles.Count
            OuterNames = ($outer.Name -join '; ')
            InnerNames = ($inner.Name -join '; ')
        }
    }
}

$videoFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $videoExtensions -contains $_.Extension.ToLowerInvariant() })
if ($videoFiles.Count -gt 0) {
    $issues += "整理结果中仍有视频文件：$($videoFiles.Count) 个"
}
$longFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Name -match '详情长图' })
if ($longFiles.Count -gt 0) {
    $issues += "整理结果中仍有详情长图文件：$($longFiles.Count) 个"
}

$crossLeafDuplicateGroups = @($allImageFiles | Get-FileHash -Algorithm SHA256 | Group-Object Hash | Where-Object { $_.Count -gt 1 })
$summary = [pscustomobject]@{
    Root = (Resolve-Path -LiteralPath $Root).Path
    Products = $products.Count
    ColorLeaves = $records.Count
    Outers = (($records | Measure-Object -Property OuterCount -Sum).Sum)
    MinInner = (($records | Measure-Object -Property InnerCount -Minimum).Minimum)
    MaxInner = (($records | Measure-Object -Property InnerCount -Maximum).Maximum)
    SameLeafDuplicateIssues = @($issues | Where-Object { $_ -match '完全重复' }).Count
    CrossLeafDuplicateGroups = $crossLeafDuplicateGroups.Count
    Videos = $videoFiles.Count
    LongImages = $longFiles.Count
    Issues = $issues.Count
}

if ($Json) {
    [pscustomobject]@{ Summary = $summary; Records = $records; Issues = $issues }
}
else {
    $summary | Format-List
    if ($issues.Count -eq 0) {
        'Issues: 0'
    }
    else {
        'Issues:'
        $issues | ForEach-Object { "- $_" }
    }
}

if ($issues.Count -gt 0) {
    exit 1
}
