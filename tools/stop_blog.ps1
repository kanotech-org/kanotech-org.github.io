param(
    [int]$Port = 4000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listeners) {
    Write-Host "No local server is listening on port $Port."
    exit 0
}

$processIds = $listeners |
    Select-Object -ExpandProperty OwningProcess -Unique |
    Where-Object { $_ -gt 0 }

foreach ($processId in $processIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) {
        continue
    }

    Write-Host "Stopping $($process.ProcessName) on port $Port (PID $processId)..."
    Stop-Process -Id $processId
}

Write-Host "Stopped local blog server on port $Port."
