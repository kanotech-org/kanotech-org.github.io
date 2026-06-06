param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Draft,

    [string]$SourceBranch = "draft-blog-posts",

    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),

    [string]$Slug,

    [switch]$Force,

    [switch]$NoAssets,

    [switch]$AllowNonMain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail($Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Run-Git([string[]]$GitArgs) {
    $output = & git @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "git $($GitArgs -join ' ') failed: $output"
    }
    return $output
}

function Test-GitObject([string]$Spec) {
    & git cat-file -e $Spec 2>$null
    return $LASTEXITCODE -eq 0
}

function Copy-GitBlobToFile([string]$Spec, [string]$Destination) {
    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir | Out-Null
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "git"
    $startInfo.Arguments = "show `"$Spec`""
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $process.StandardOutput.BaseStream.CopyTo($output)
    } finally {
        $output.Dispose()
    }

    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $errorText = $process.StandardError.ReadToEnd()
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        Fail "Could not copy $Spec. git show said: $errorText"
    }
}

function ConvertTo-RepoAssetPath([string]$RawPath, [string]$SourceMarkdownPath) {
    $path = $RawPath.Trim()
    if ($path -eq "") {
        return $null
    }

    if ($path.StartsWith("<") -and $path.EndsWith(">")) {
        $path = $path.Substring(1, $path.Length - 2)
    } else {
        $path = ($path -split "\s+", 2)[0]
    }

    $path = $path -replace "[?#].*$", ""
    if ($path -eq "" -or
        $path.StartsWith("#") -or
        $path -match "^[a-zA-Z][a-zA-Z0-9+.-]*:" -or
        $path.StartsWith("//")) {
        return $null
    }

    $path = [System.Uri]::UnescapeDataString($path)
    $path = $path -replace "\\", "/"

    if ($path.StartsWith("/")) {
        $path = $path.TrimStart("/")
    } elseif (-not $path.StartsWith("assets/")) {
        $sourceDir = Split-Path -Parent ($SourceMarkdownPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        if ($sourceDir) {
            $path = (($sourceDir -replace "\\", "/").TrimEnd("/") + "/" + $path)
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($path -split "/")) {
        if ($part -eq "" -or $part -eq ".") {
            continue
        }
        if ($part -eq "..") {
            if ($parts.Count -eq 0) {
                return $null
            }
            $parts.RemoveAt($parts.Count - 1)
            continue
        }
        $parts.Add($part)
    }

    if ($parts.Count -eq 0) {
        return $null
    }

    return ($parts -join "/")
}

function Get-EmbeddedAssetPaths([string]$Markdown, [string]$SourceMarkdownPath) {
    $paths = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($match in [regex]::Matches($Markdown, '!\[[^\]]*\]\(([^)]+)\)')) {
        $assetPath = ConvertTo-RepoAssetPath -RawPath $match.Groups[1].Value -SourceMarkdownPath $SourceMarkdownPath
        if ($assetPath -and $seen.Add($assetPath)) {
            $paths.Add($assetPath)
        }
    }

    foreach ($match in [regex]::Matches($Markdown, '<img\b[^>]*\bsrc\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')) {
        $assetPath = ConvertTo-RepoAssetPath -RawPath $match.Groups[1].Value -SourceMarkdownPath $SourceMarkdownPath
        if ($assetPath -and $seen.Add($assetPath)) {
            $paths.Add($assetPath)
        }
    }

    return $paths
}

$repoRoot = (Run-Git -GitArgs @("rev-parse", "--show-toplevel")).Trim()
Set-Location $repoRoot

$currentBranch = (Run-Git -GitArgs @("branch", "--show-current")).Trim()
if (-not $AllowNonMain -and $currentBranch -ne "main") {
    Fail "Refusing to promote from '$currentBranch'. Check out main first, or pass -AllowNonMain if this is intentional."
}

$draftPath = $Draft -replace "\\", "/"
if (-not $draftPath.StartsWith("_drafts/")) {
    $draftPath = "_drafts/$draftPath"
}
if ([System.IO.Path]::GetExtension($draftPath) -eq "") {
    $draftPath = "$draftPath.md"
}

if (-not $Slug) {
    $Slug = [System.IO.Path]::GetFileNameWithoutExtension($draftPath)
    $Slug = $Slug -replace "^\d{4}-\d{2}-\d{2}-", ""
}

if ($Date -notmatch "^\d{4}-\d{2}-\d{2}$") {
    Fail "Date must use YYYY-MM-DD format."
}

if ($Slug -notmatch "^[a-z0-9][a-z0-9-]*$") {
    Fail "Slug must contain only lowercase letters, numbers, and hyphens."
}

$targetPath = "_posts/$Date-$Slug.md"
$targetFullPath = Join-Path $repoRoot ($targetPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)

if ((Test-Path -LiteralPath $targetFullPath) -and -not $Force) {
    Fail "$targetPath already exists. Pass -Force to overwrite it."
}

$draftFullPath = Join-Path $repoRoot ($draftPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
if (Test-Path -LiteralPath $draftFullPath) {
    $content = Get-Content -LiteralPath $draftFullPath -Raw
    $sourceLabel = $draftPath
} else {
    $content = & git show "$SourceBranch`:$draftPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "Could not read $draftPath from working tree or $SourceBranch. git show said: $content"
    }
    $content = $content -join [Environment]::NewLine
    $sourceLabel = "$SourceBranch`:$draftPath"
}

$targetDir = Split-Path -Parent $targetFullPath
if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

[System.IO.File]::WriteAllText(
    $targetFullPath,
    $content,
    [System.Text.UTF8Encoding]::new($false)
)

$assetPaths = @()
if (-not $NoAssets) {
    foreach ($assetPath in (Get-EmbeddedAssetPaths -Markdown $content -SourceMarkdownPath $draftPath)) {
        $assetFullPath = Join-Path $repoRoot ($assetPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $assetFullPath) {
            Write-Host "Asset exists: $assetPath"
            continue
        }

        $assetSpec = "$SourceBranch`:$assetPath"
        if (-not (Test-GitObject -Spec $assetSpec)) {
            Write-Host "Asset missing from $SourceBranch`: $assetPath"
            continue
        }

        Copy-GitBlobToFile -Spec $assetSpec -Destination $assetFullPath
        $assetPaths += $assetPath
        Write-Host "Copied asset: $assetPath"
    }
}

Write-Host "Promoted $sourceLabel"
Write-Host "Created  $targetPath"
if ($assetPaths.Count -gt 0) {
    Write-Host "Copied  $($assetPaths.Count) asset(s)"
}
Write-Host ""
Write-Host "Review it, then commit and push manually:"
Write-Host "  git diff -- $targetPath"
if ($assetPaths.Count -gt 0) {
    Write-Host "  git diff -- $($assetPaths -join ' ')"
}
Write-Host "  git add $targetPath"
if ($assetPaths.Count -gt 0) {
    Write-Host "  git add $($assetPaths -join ' ')"
}
Write-Host "  git commit -m `"Publish $Slug`""
Write-Host "  git push github main"
