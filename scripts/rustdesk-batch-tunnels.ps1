#Requires -Version 5.1
<#
.SYNOPSIS
    Batch RustDesk tunnel manager for large-scale infrastructure.

.DESCRIPTION
    Reads a CSV file with server definitions and creates parallel
    RustDesk port-forward tunnels. Designed for ~1000 server deployments.

    CSV format (servers.csv):
        RemoteId,Password,LocalPort,RemotePort,RemoteHost,Label
        1265569195,123qweASD*,12222,22,localhost,web-server-01
        9876543210,MyPass123!,12223,22,localhost,db-server-01

.PARAMETER CsvPath
    Path to the CSV file with server definitions.

.PARAMETER RustDeskExe
    Path to the RustDesk CLI executable.

.PARAMETER MaxConcurrent
    Maximum number of tunnels to start in parallel batches (default: 50).

.PARAMETER DelayBetweenMs
    Milliseconds to wait between starting each tunnel (default: 200).

.EXAMPLE
    .\rustdesk-batch-tunnels.ps1 -CsvPath .\servers.csv

.EXAMPLE
    .\rustdesk-batch-tunnels.ps1 -CsvPath .\servers.csv -MaxConcurrent 100 -DelayBetweenMs 100
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$RustDeskExe = ".\rustdesk.exe",

    [Parameter(Mandatory = $false)]
    [int]$MaxConcurrent = 50,

    [Parameter(Mandatory = $false)]
    [int]$DelayBetweenMs = 200,

    [Parameter(Mandatory = $false)]
    [string]$IdServer = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

if (-not (Test-Path $RustDeskExe)) {
    Write-Error "RustDesk executable not found: $RustDeskExe"
    exit 1
}

$servers = Import-Csv $CsvPath
$total = $servers.Count
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " RustDesk Batch Tunnel Manager" -ForegroundColor Cyan
Write-Host " Servers: $total" -ForegroundColor Cyan
Write-Host " Max concurrent: $MaxConcurrent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results = [System.Collections.ArrayList]::new()
$processes = @{}
$counter = 0

foreach ($server in $servers) {
    $counter++
    $remoteId = $server.RemoteId
    $password = $server.Password
    $localPort = [int]$server.LocalPort
    $remotePort = if ($server.RemotePort) { [int]$server.RemotePort } else { 22 }
    $remoteHost = if ($server.RemoteHost) { $server.RemoteHost } else { "localhost" }
    $label = if ($server.Label) { $server.Label } else { $remoteId }

    $pfArg = "${remoteId}:${localPort}:${remotePort}"
    if ($remoteHost -ne "localhost") {
        $pfArg += ":${remoteHost}"
    }

    Write-Host "[$counter/$total] Starting tunnel: $label (localhost:$localPort -> $remoteId`:$remotePort)" -ForegroundColor Yellow

    try {
        $proc = Start-Process -FilePath $RustDeskExe `
            -ArgumentList (@("--port-forward", $pfArg, "--password", $password) + $(if ($IdServer) { @("--id-server", $IdServer) } else { @() })) `
            -PassThru -NoNewWindow

        $processes[$localPort] = @{
            Process = $proc
            Label   = $label
            Server  = $server
        }
    }
    catch {
        Write-Warning "Failed to start tunnel for $label`: $_"
        [void]$results.Add([PSCustomObject]@{
            Label      = $label
            RemoteId   = $remoteId
            LocalPort  = $localPort
            RemotePort = $remotePort
            PID        = $null
            Status     = "FAILED"
            Error      = $_.Exception.Message
        })
        continue
    }

    # Throttle: respect MaxConcurrent
    if ($counter % $MaxConcurrent -eq 0) {
        Write-Host "[*] Batch of $MaxConcurrent started, waiting 5s for connections..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }
    else {
        Start-Sleep -Milliseconds $DelayBetweenMs
    }
}

# --- Verify all tunnels ---
Write-Host "`n[*] Waiting 10s for all tunnels to establish..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Tunnel Status Report" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$active = 0
$failed = 0

foreach ($port in $processes.Keys | Sort-Object) {
    $info = $processes[$port]
    $proc = $info.Process
    $label = $info.Label
    $server = $info.Server

    $status = "UNKNOWN"
    $error = ""

    if ($proc.HasExited) {
        $status = "EXITED"
        $error = "Exit code: $($proc.ExitCode)"
        $failed++
    }
    else {
        $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($listener) {
            $status = "ACTIVE"
            $active++
        }
        else {
            $status = "NO_LISTENER"
            $failed++
        }
    }

    $color = switch ($status) {
        "ACTIVE" { "Green" }
        "EXITED" { "Red" }
        default  { "Yellow" }
    }

    Write-Host "  $label : localhost:$port -> $($server.RemoteId):$($server.RemotePort) [$status]" -ForegroundColor $color

    [void]$results.Add([PSCustomObject]@{
        Label      = $label
        RemoteId   = $server.RemoteId
        LocalPort  = $port
        RemotePort = $server.RemotePort
        PID        = $proc.Id
        Status     = $status
        Error      = $error
    })
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Summary: $active ACTIVE / $failed FAILED / $total TOTAL" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
Write-Host "========================================" -ForegroundColor Cyan

# Export results
$reportPath = "tunnel-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "`n[*] Report saved to: $reportPath" -ForegroundColor Green

# Output for pipeline consumption
$results
