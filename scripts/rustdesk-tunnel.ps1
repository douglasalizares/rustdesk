#Requires -Version 5.1
<#
.SYNOPSIS
    RustDesk SSH tunnel manager for mass infrastructure automation.

.DESCRIPTION
    Creates and manages RustDesk port-forward tunnels headlessly via CLI.
    Requires the RustDesk CLI binary compiled with: cargo build --features cli

.PARAMETER RustDeskExe
    Path to the RustDesk CLI executable.

.PARAMETER RemoteId
    RustDesk peer ID of the remote machine.

.PARAMETER Password
    Connection password for the remote peer.

.PARAMETER LocalPort
    Local port to listen on (the tunnel entry point).

.PARAMETER RemotePort
    Remote port to forward to (e.g., 22 for SSH).

.PARAMETER RemoteHost
    Remote host to forward to (default: localhost).

.PARAMETER WaitSeconds
    Seconds to wait for tunnel to become ready (default: 10).

.PARAMETER TestConnection
    If set, tests the tunnel with Test-NetConnection after establishing.

.EXAMPLE
    .\rustdesk-tunnel.ps1 -RemoteId 1265569195 -Password "123qweASD*" -LocalPort 12222 -RemotePort 22

.EXAMPLE
    # Batch mode from CSV
    Import-Csv servers.csv | ForEach-Object {
        .\rustdesk-tunnel.ps1 -RemoteId $_.Id -Password $_.Pass -LocalPort $_.Port -RemotePort 22
    }
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RustDeskExe = ".\rustdesk.exe",

    [Parameter(Mandatory = $true)]
    [string]$RemoteId,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $true)]
    [int]$LocalPort,

    [Parameter(Mandatory = $false)]
    [int]$RemotePort = 22,

    [Parameter(Mandatory = $false)]
    [string]$RemoteHost = "localhost",

    [Parameter(Mandatory = $false)]
    [string]$IdServer = "",

    [Parameter(Mandatory = $false)]
    [int]$WaitSeconds = 10,

    [switch]$TestConnection
)

$ErrorActionPreference = "Stop"

# --- Validate executable ---
if (-not (Test-Path $RustDeskExe)) {
    Write-Error "RustDesk executable not found at: $RustDeskExe"
    exit 1
}

# --- Build the port-forward argument ---
$pfArg = "${RemoteId}:${LocalPort}:${RemotePort}"
if ($RemoteHost -ne "localhost") {
    $pfArg += ":${RemoteHost}"
}

Write-Host "[*] Starting tunnel: localhost:$LocalPort -> $RemoteId ($RemoteHost`:$RemotePort)" -ForegroundColor Cyan

# --- Launch RustDesk as background process ---
$procArgs = @("--port-forward", $pfArg, "--password", $Password)
if ($IdServer) {
    $procArgs += @("--id-server", $IdServer)
}
$proc = Start-Process -FilePath $RustDeskExe -ArgumentList $procArgs -PassThru -NoNewWindow

if (-not $proc) {
    Write-Error "Failed to start RustDesk process"
    exit 1
}

Write-Host "[*] RustDesk PID: $($proc.Id)" -ForegroundColor Green

# --- Wait for tunnel to be ready ---
Write-Host "[*] Waiting up to ${WaitSeconds}s for port $LocalPort to be ready..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt $WaitSeconds; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        Write-Error "RustDesk process exited prematurely (exit code: $($proc.ExitCode))"
        exit 1
    }
    $listener = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Warning "Port $LocalPort not yet listening after ${WaitSeconds}s (tunnel may still be connecting)"
} else {
    Write-Host "[OK] Tunnel ACTIVE on localhost:$LocalPort" -ForegroundColor Green
}

# --- Optional: Test the connection ---
if ($TestConnection) {
    Write-Host "[*] Testing connection to localhost:$LocalPort..." -ForegroundColor Yellow
    $test = Test-NetConnection -ComputerName localhost -Port $LocalPort -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        Write-Host "[OK] TCP connection successful" -ForegroundColor Green
    } else {
        Write-Warning "TCP connection to localhost:$LocalPort failed"
    }
}

# --- Output structured result ---
[PSCustomObject]@{
    RemoteId   = $RemoteId
    LocalPort  = $LocalPort
    RemotePort = $RemotePort
    RemoteHost = $RemoteHost
    PID        = $proc.Id
    Status     = if ($ready) { "Active" } else { "Pending" }
}
