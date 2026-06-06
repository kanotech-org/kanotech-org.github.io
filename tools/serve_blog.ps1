param(
    [switch]$Drafts,
    [string]$HostName = "127.0.0.1",
    [int]$Port = 4000,
    [switch]$NoLiveReload,
    [switch]$Open
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

$url = "http://$HostName`:$Port/"
$jekyllArgs = @(
    "exec",
    "jekyll",
    "serve",
    "--host", $HostName,
    "--port", "$Port"
)

if ($Drafts) {
    $jekyllArgs += "--drafts"
}

if (-not $NoLiveReload) {
    $jekyllArgs += "--livereload"
}

Write-Host "Serving blog at $url"
Write-Host "Press Ctrl+C to stop."

if ($Open) {
    Start-Process $url
}

& bundle @jekyllArgs
if ($LASTEXITCODE -ne 0) {
    Fail "Blog server failed. If dependencies are missing, run: bundle install"
}
