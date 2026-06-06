param(
    [switch]$Drafts,
    [switch]$Clean,
    [string]$Destination = "_site"
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

$repoRoot = (Run-Git -GitArgs @("rev-parse", "--show-toplevel")).Trim()
Set-Location $repoRoot

if (-not (Test-Path -LiteralPath "Gemfile")) {
    Fail "Gemfile not found at $repoRoot."
}

if ($Clean -and (Test-Path -LiteralPath $Destination)) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
}

$jekyllArgs = @("exec", "jekyll", "build", "--destination", $Destination)
if ($Drafts) {
    $jekyllArgs += "--drafts"
}

Write-Host "Building blog into $Destination..."
& bundle @jekyllArgs
if ($LASTEXITCODE -ne 0) {
    Fail "Blog build failed. If dependencies are missing, run: bundle install"
}

Write-Host "Build complete: $Destination"
