#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables WinRM with NTLM over HTTP on the local machine for PoC testing.
    DO NOT use this config in production — HTTP + basic/NTLM is for local dev only.

.HOW TO RUN
    Open PowerShell as Administrator, then:
        Set-ExecutionPolicy RemoteSigned -Scope Process -Force
        .\poc\scripts\setup-winrm-local.ps1

.WHAT IT DOES
    1. Runs Quick Config (enables WinRM service + default HTTP listener on 5985)
    2. Sets auth to NTLM only (no Kerberos needed for local PoC)
    3. Opens firewall for port 5985 from the Podman/WSL2 subnet
    4. Creates a local user 'ansible-poc' for Ansible to authenticate with
    5. Prints connection info for the .env file
#>

param(
    [string]$WinRMUser     = 'ansible-poc',
    [string]$WinRMPassword = 'changeme123!'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n[1/5] Enabling WinRM..." -ForegroundColor Cyan
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
winrm quickconfig -q

Write-Host "[2/5] Configuring NTLM auth on HTTP listener..." -ForegroundColor Cyan
Set-Item WSMan:\localhost\Service\Auth\Basic   -Value $false
Set-Item WSMan:\localhost\Service\Auth\NTLM    -Value $true
Set-Item WSMan:\localhost\Service\Auth\CredSSP -Value $false
Set-Item WSMan:\localhost\Service\Auth\Kerberos -Value $false

# Allow unencrypted is required for HTTP transport (PoC only)
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

Write-Host "[3/5] Opening firewall for Podman WSL2 subnet (172.16.0.0/12)..." -ForegroundColor Cyan
$ruleName = 'WinRM-HTTP-Podman-PoC'
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   5985 `
        -RemoteAddress '172.16.0.0/12' `
        -Action      Allow `
        -Profile     Any | Out-Null
    Write-Host "    Firewall rule created: $ruleName"
} else {
    Write-Host "    Firewall rule already exists: $ruleName"
}

Write-Host "[4/5] Creating local user '$WinRMUser'..." -ForegroundColor Cyan
$secPwd = ConvertTo-SecureString $WinRMPassword -AsPlainText -Force
if (Get-LocalUser -Name $WinRMUser -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $WinRMUser -Password $secPwd
    Write-Host "    User '$WinRMUser' password reset."
} else {
    New-LocalUser -Name $WinRMUser -Password $secPwd -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Write-Host "    User '$WinRMUser' created."
}
# Add to Administrators so Ansible can manage the machine
if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $WinRMUser -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Administrators' -Member $WinRMUser
    Write-Host "    Added '$WinRMUser' to Administrators."
}

Write-Host "[5/5] Verifying WinRM listener..." -ForegroundColor Cyan
winrm enumerate winrm/config/Listener

Write-Host "`n=== PoC WinRM setup complete ===" -ForegroundColor Green
Write-Host "Update your poc/.env with:"
Write-Host "  WINRM_USER=$WinRMUser"
Write-Host "  WINRM_PASSWORD=$WinRMPassword"
Write-Host ""
Write-Host "To undo: run 'Disable-PSRemoting -Force' and remove firewall rule '$ruleName'"
