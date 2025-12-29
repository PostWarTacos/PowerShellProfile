<#
.SYNOPSIS
Uninstalls the PowerShell Profile and custom modules setup.

.DESCRIPTION
Removes all PowerShell profile configurations, custom modules, and resets Windows Terminal settings
installed by Install-PowerShellSetup.ps1.

.PARAMETER SkipTerminalReset
Skip resetting Windows Terminal settings to defaults.

.EXAMPLE
.\Uninstall-PowerShellSetup.ps1

.EXAMPLE
.\Uninstall-PowerShellSetup.ps1 -SkipTerminalReset

.NOTES
This script will:
- Clear all PowerShell profile files
- Remove PowerShellProfile and Powershell-Modules directories
- Clean up PSModulePath environment variable
- Reset Windows Terminal settings (optional)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipTerminalReset
)

# Check if running as administrator, if not, elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges. Attempting to elevate..." -ForegroundColor Yellow
    
    # Build arguments to pass to elevated process
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`""
    )
    
    # Add script parameters to arguments
    if ($PSBoundParameters.ContainsKey('SkipTerminalReset')) {
        $arguments += "-SkipTerminalReset"
    }
    
    # Determine which PowerShell to use
    $powershellCmd = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
    
    # Start elevated process
    try {
        Start-Process $powershellCmd -ArgumentList $arguments -Verb RunAs -Wait
        exit
    }
    catch {
        Write-Host "Failed to elevate. Error: $_" -ForegroundColor Red
        Write-Host "Please run this script as administrator manually." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host
Write-Host "=== PowerShell Profile Uninstallation ===" -ForegroundColor Cyan
Write-Host "This will remove your PowerShell profile setup." -ForegroundColor Yellow
Write-Host

# Step 1: Clear profile files
Write-Host "[1/4] Clearing profile files for: $env:USERNAME" -ForegroundColor Cyan

$profiles = @(
    $PROFILE.AllUsersAllHosts,
    $PROFILE.AllUsersCurrentHost,
    $PROFILE.CurrentUserAllHosts,
    $PROFILE.CurrentUserCurrentHost
)

foreach ($profilePath in $profiles) {
    Write-Host "  Checking: $profilePath" -ForegroundColor Yellow
    if (Test-Path $profilePath) {
        Set-Content -Path $profilePath -Value "" -Force
        Write-Host "  Cleared: $profilePath" -ForegroundColor Green
    } else {
        Write-Host "  Not found: $profilePath" -ForegroundColor Gray
    }
}

# Also clear any PowerShell 5.1 profiles
$ps51Profiles = @(
    "$HOME\Documents\WindowsPowerShell\profile.ps1",
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
)

foreach ($profilePath in $ps51Profiles) {
    Write-Host "  Checking PS 5.1: $profilePath" -ForegroundColor Yellow
    if (Test-Path $profilePath) {
        Set-Content -Path $profilePath -Value "" -Force
        Write-Host "  Cleared: $profilePath" -ForegroundColor Green
    } else {
        Write-Host "  Not found: $profilePath" -ForegroundColor Gray
    }
}

# Step 2: Remove directories
Write-Host
Write-Host "[2/4] Removing directories..." -ForegroundColor Cyan

$profileDir = "$HOME\Documents\Coding\PowerShellProfile"
$modulesDir = "$HOME\Documents\Coding\Powershell-Modules"

if (Test-Path $profileDir) {
    Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: $profileDir" -ForegroundColor Green
} else {
    Write-Host "  Not found: $profileDir" -ForegroundColor Gray
}

if (Test-Path $modulesDir) {
    Remove-Item $modulesDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: $modulesDir" -ForegroundColor Green
} else {
    Write-Host "  Not found: $modulesDir" -ForegroundColor Gray
}

# Step 3: Clean up PSModulePath
Write-Host
Write-Host "[3/4] Cleaning up PSModulePath..." -ForegroundColor Cyan

$currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
$newPath = ($currentPath -split ';' | Where-Object { $_ -notlike "*Powershell-Modules*" }) -join ';'
[Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")
Write-Host "  Removed Powershell-Modules from PSModulePath" -ForegroundColor Green

# Step 4: Reset Windows Terminal settings
if (-not $SkipTerminalReset) {
    Write-Host
    Write-Host "[4/4] Resetting Windows Terminal settings..." -ForegroundColor Cyan
    
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $settingsPath) {
        # Backup current settings
        $backupPath = "$settingsPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $settingsPath $backupPath -Force
        Write-Host "  Backed up settings to: $backupPath" -ForegroundColor Yellow
        
        # Remove settings file
        Remove-Item $settingsPath -Force
        Write-Host "  Removed Windows Terminal settings" -ForegroundColor Green
        Write-Host "  Settings will regenerate with defaults on next launch" -ForegroundColor Yellow
    } else {
        Write-Host "  Windows Terminal settings not found" -ForegroundColor Gray
    }
} else {
    Write-Host
    Write-Host "[4/4] Skipping Windows Terminal reset (as requested)" -ForegroundColor Yellow
}

# Final message
Write-Host
Write-Host "=== Uninstallation Complete ===" -ForegroundColor Green
Write-Host
Write-Host "Please restart PowerShell for all changes to take effect." -ForegroundColor Cyan
Write-Host
Write-Host "Note: This script does not uninstall prerequisites like:" -ForegroundColor Yellow
Write-Host "  - Git" -ForegroundColor Gray
Write-Host "  - Oh My Posh" -ForegroundColor Gray
Write-Host "  - JetBrains Mono Nerd Font" -ForegroundColor Gray
Write-Host "  - PowerShell modules (PSReadLine, Terminal-Icons)" -ForegroundColor Gray
Write-Host
Write-Host "To remove these, use: winget uninstall <package-name>" -ForegroundColor Gray
Write-Host
