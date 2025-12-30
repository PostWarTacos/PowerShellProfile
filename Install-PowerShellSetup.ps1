#Requires -Version 5.1

<#
.SYNOPSIS
    Installs PowerShell profile, modules, and prerequisites.

.DESCRIPTION
    This script installs and configures a complete PowerShell environment including:
    - Custom PowerShell profile
    - Custom PowerShell modules
    - Prerequisites (winget, git, Oh My Posh, Terminal-Icons, PSReadLine)

.PARAMETER GitHubUser
    GitHub username where the repositories are hosted.

.PARAMETER ProfileRepo
    Name of the PowerShellProfile repository (default: PowerShellProfile)

.PARAMETER ModulesRepo
    Name of the Powershell-Modules repository (default: Powershell-Modules)

.EXAMPLE
    irm https://raw.githubusercontent.com/USERNAME/PowerShellProfile/main/Install-PowerShellSetup.ps1 | iex

.NOTES
    Author: PostWarTacos
    Date: 2025-12-24
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitHubUser = "PostWarTacos",
    
    [Parameter()]
    [string]$ProfileRepo = "PowerShellProfile",
    
    [Parameter()]
    [string]$ModulesRepo = "Powershell-Modules",
    
    [Parameter()]
    [string]$Branch = "main",
    
    [Parameter()]
    [string]$TempScriptPath = ""
)

$ErrorActionPreference = 'Stop'

# Check if running as administrator, if not, elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges. Attempting to elevate..." -ForegroundColor Yellow
    
    # Build arguments to pass to elevated process
    $scriptPath = $MyInvocation.MyCommand.Path
    $createdTempScript = $false
    
    # If script path is empty (running from iex), save script to temp file first
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = Join-Path $env:TEMP "Install-PowerShellSetup-$(Get-Date -Format 'yyyyMMdd-HHmmss').ps1"
        $createdTempScript = $true
        
        # Get the script content from the current invocation
        $scriptContent = $MyInvocation.MyCommand.ScriptBlock.ToString()
        
        # Save to temp file
        try {
            $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
        }
        catch {
            Write-Host "ERROR: Cannot elevate - script is running from pipeline and cannot be saved" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            exit 1
        }
    }
    
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`""
    )
    
    # Add parameter to track temp script cleanup
    if ($createdTempScript) {
        $arguments += "-TempScriptPath", "`"$scriptPath`""
    }
    
    # Add script parameters to arguments
    if ($PSBoundParameters.ContainsKey('GitHubUser')) {
        $arguments += "-GitHubUser", "`"$GitHubUser`""
    }
    if ($PSBoundParameters.ContainsKey('ProfileRepo')) {
        $arguments += "-ProfileRepo", "`"$ProfileRepo`""
    }
    if ($PSBoundParameters.ContainsKey('ModulesRepo')) {
        $arguments += "-ModulesRepo", "`"$ModulesRepo`""
    }
    if ($PSBoundParameters.ContainsKey('Branch')) {
        $arguments += "-Branch", "`"$Branch`""
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

Clear-Host
Write-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " PowerShell Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host
Write-Host "[+] Running with administrator privileges" -ForegroundColor Green
Write-Host

# Define paths
$documentsPath = [System.Environment]::GetFolderPath("MyDocuments")
$codingPath = Join-Path $documentsPath "Coding"
$profileRepoPath = Join-Path $codingPath $ProfileRepo
$modulesPath = Join-Path $codingPath $ModulesRepo
$profileFile = $PROFILE.AllUsersAllHosts

# Verify GitHub connectivity
Write-Host
Write-Host "[*] Verifying GitHub connectivity..." -ForegroundColor Cyan
try {
    $testConnection = Test-Connection -ComputerName github.com -Count 2 -Quiet -ErrorAction Stop
    if ($testConnection) {
        Write-Host "[+] GitHub is accessible" -ForegroundColor Green
    } else {
        Write-Host "[!] Cannot reach github.com" -ForegroundColor Red
        Write-Host "    Please check your internet connection and try again." -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "[!] Network connectivity test failed: $_" -ForegroundColor Red
    Write-Host "    Please check your internet connection and firewall settings." -ForegroundColor Yellow
    exit 1
}

# Verify git availability
Write-Host
Write-Host "[*] Checking for git..." -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Git is not installed. It will be installed with prerequisites." -ForegroundColor Yellow
} else {
    $gitVersion = (git --version) -replace 'git version ', ''
    Write-Host "[+] Git is installed: $gitVersion" -ForegroundColor Green
}

# Create directories
Write-Host
Write-Host "[*] Creating directory structure..." -ForegroundColor Cyan
if (-not (Test-Path $codingPath)) {
    New-Item -Path $codingPath -ItemType Directory -Force | Out-Null
    Write-Host "[+] Created: $codingPath" -ForegroundColor Green
} else {
    Write-Host "[+] Exists: $codingPath" -ForegroundColor Green
}

# Install prerequisites
Write-Host
Write-Host "[*] Installing prerequisites..." -ForegroundColor Cyan
    
    # Install winget
    Write-Host "  Checking winget..." -ForegroundColor Gray
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "  Installing winget..." -ForegroundColor Gray
            $progressPreference = 'silentlyContinue'
            Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
            Add-AppxPackage "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
            Write-Host "[+] Installed winget" -ForegroundColor Green
        } catch {
            Write-Host "[!] Could not install winget: $_" -ForegroundColor Yellow
            Write-Host "    Please install manually: https://aka.ms/getwinget" -ForegroundColor Gray
        }
    } else {
        Write-Host "[+] winget already installed" -ForegroundColor Green
    }
    
    # Install git
    Write-Host "  Checking git..." -ForegroundColor Gray
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Write-Host "  Installing git..." -ForegroundColor Gray
                winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
                Write-Host "[+] Installed git" -ForegroundColor Green
                Write-Host "[!] You may need to restart your terminal for git to be available in PATH" -ForegroundColor Yellow
            } catch {
                Write-Host "[!] Could not install git: $_" -ForegroundColor Yellow
                Write-Host "    Please install manually: https://git-scm.com/download/win" -ForegroundColor Gray
            }
        } else {
            Write-Host "[!] Winget not available, cannot install git" -ForegroundColor Yellow
            Write-Host "    Please install manually: https://git-scm.com/download/win" -ForegroundColor Gray
        }
    } else {
        Write-Host "[+] git already installed" -ForegroundColor Green
    }
    
    # Install PSReadLine
    Write-Host "  Checking PSReadLine..." -ForegroundColor Gray
    if (-not (Get-Module -ListAvailable PSReadLine)) {
        try {
            Install-Module -Name PSReadLine -Force -SkipPublisherCheck -Scope CurrentUser
            Write-Host "[+] Installed PSReadLine" -ForegroundColor Green
        } catch {
            Write-Host "[!] Could not install PSReadLine: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[+] PSReadLine already installed" -ForegroundColor Green
    }
    
    # Install Terminal-Icons
    Write-Host "  Checking Terminal-Icons..." -ForegroundColor Gray
    if (-not (Get-Module -ListAvailable Terminal-Icons)) {
        try {
            $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }
            Install-Module -Name Terminal-Icons -Force -Scope $scope
            Write-Host "[+] Installed Terminal-Icons ($scope scope)" -ForegroundColor Green
        } catch {
            Write-Host "[!] Could not install Terminal-Icons: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[+] Terminal-Icons already installed" -ForegroundColor Green
    }
    
    # Install Oh My Posh
    Write-Host "  Checking Oh My Posh..." -ForegroundColor Gray
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Write-Host "  Installing Oh My Posh..." -ForegroundColor Gray
                winget install JanDeDobbeleer.OhMyPosh -s winget --silent --accept-source-agreements --accept-package-agreements
                Write-Host "[+] Installed Oh My Posh" -ForegroundColor Green
                Write-Host "[!] You may need to restart your terminal for Oh My Posh to be available in PATH" -ForegroundColor Yellow
            } catch {
                Write-Host "[!] Could not install Oh My Posh: $_" -ForegroundColor Yellow
                Write-Host "    You can install it manually: winget install JanDeDobbeleer.OhMyPosh" -ForegroundColor Gray
            }
        } else {
            Write-Host "[!] Winget not available, cannot install Oh My Posh" -ForegroundColor Yellow
            Write-Host "    You can install it manually: winget install JanDeDobbeleer.OhMyPosh" -ForegroundColor Gray
        }
    } else {
        Write-Host "[+] Oh My Posh already installed" -ForegroundColor Green
    }
    
    # Install Nerd Font
    Write-Host "  Checking JetBrains Mono Nerd Font..." -ForegroundColor Gray
    $nerdFontInstalled = Test-Path "C:\Windows\Fonts\JetBrainsMonoNerdFont-Bold.ttf"
    if (-not $nerdFontInstalled) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Write-Host "  Installing JetBrains Mono Nerd Font..." -ForegroundColor Gray
                winget install --id=DEVCOM.JetBrainsMonoNerdFont -e --source=winget --silent --accept-source-agreements --accept-package-agreements
                Write-Host "[+] Installed JetBrains Mono Nerd Font" -ForegroundColor Green
            } catch {
                Write-Host "[!] Could not install Nerd Font: $_" -ForegroundColor Yellow
                Write-Host "    You can install it manually: winget install DEVCOM.JetBrainsMonoNerdFont" -ForegroundColor Gray
            }
        } else {
            Write-Host "[!] Winget not available, cannot install Nerd Font" -ForegroundColor Yellow
            Write-Host "    You can install it manually: winget install DEVCOM.JetBrainsMonoNerdFont" -ForegroundColor Gray
        }
    } else {
        Write-Host "[+] JetBrains Mono Nerd Font already installed" -ForegroundColor Green
    }
    
    # Install winfetch
    Write-Host "  Checking winfetch..." -ForegroundColor Gray
    if (-not (Get-Command winfetch -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "  Installing winfetch..." -ForegroundColor Gray
            Install-Script -Name winfetch -Force -Scope CurrentUser -ErrorAction Stop
            Write-Host "[+] Installed winfetch" -ForegroundColor Green
        } catch {
            Write-Host "[!] Could not install winfetch: $_" -ForegroundColor Yellow
            Write-Host "    You can install it manually: Install-Script -Name winfetch" -ForegroundColor Gray
        }
    } else {
        Write-Host "[+] winfetch already installed" -ForegroundColor Green
    }

# Clone repositories
Write-Host
Write-Host "[*] Cloning repositories..." -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Git is not available. Cannot clone repositories." -ForegroundColor Red
    Write-Host "    Please install git and run this script again." -ForegroundColor Yellow
    exit 1
}

# Clone PowerShell Profile
$profileRepoUrl = "https://github.com/$GitHubUser/$ProfileRepo.git"
if (Test-Path $profileRepoPath) {
    Write-Host "  Updating PowerShell Profile..." -ForegroundColor Gray
    Push-Location $profileRepoPath
    try {
        git pull origin $Branch 2>&1 | Out-Null
        Write-Host "[+] Updated: $ProfileRepo" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not update $ProfileRepo`: $_" -ForegroundColor Yellow
    }
    Pop-Location
} else {
    Write-Host "  Cloning PowerShell Profile..." -ForegroundColor Gray
    try {
        git clone $profileRepoUrl $profileRepoPath 2>&1 | Out-Null
        if ($Branch -ne "main") {
            Push-Location $profileRepoPath
            git checkout $Branch 2>&1 | Out-Null
            Pop-Location
        }
        Write-Host "[+] Cloned: $ProfileRepo" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not clone $ProfileRepo`: $_" -ForegroundColor Yellow
    }
}

# Clone PowerShell Modules
$modulesRepoUrl = "https://github.com/$GitHubUser/$ModulesRepo.git"
if (Test-Path $modulesPath) {
    Write-Host "  Updating PowerShell Modules..." -ForegroundColor Gray
    Push-Location $modulesPath
    try {
        git pull origin $Branch 2>&1 | Out-Null
        Write-Host "[+] Updated: $ModulesRepo" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not update $ModulesRepo`: $_" -ForegroundColor Yellow
    }
    Pop-Location
} else {
    Write-Host "  Cloning PowerShell Modules..." -ForegroundColor Gray
    try {
        git clone $modulesRepoUrl $modulesPath 2>&1 | Out-Null
        if ($Branch -ne "main") {
            Push-Location $modulesPath
            git checkout $Branch 2>&1 | Out-Null
            Pop-Location
        }
        Write-Host "[+] Cloned: $ModulesRepo" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not clone $ModulesRepo`: $_" -ForegroundColor Yellow
    }
}

# Add custom modules to PSModulePath
Write-Host
Write-Host "[*] Configuring module path..." -ForegroundColor Cyan
$currentPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", [EnvironmentVariableTarget]::User)
if ($currentPSModulePath -notlike "*$modulesPath*") {
    try {
        $newPSModulePath = "$modulesPath;$currentPSModulePath"
        [Environment]::SetEnvironmentVariable("PSModulePath", $newPSModulePath, [EnvironmentVariableTarget]::User)
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
        Write-Host "[+] Added $modulesPath to PSModulePath" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not update PSModulePath: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "[+] $modulesPath already in PSModulePath" -ForegroundColor Green
}

# Clear existing profiles for clean slate
Write-Host
Write-Host "[*] Clearing existing profiles..." -ForegroundColor Cyan
$profilesToClear = @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)
foreach ($profile in $profilesToClear) {
    if (Test-Path $profile) {
        Set-Content -Path $profile -Value "" -Force
        Write-Host "[+] Cleared: $profile" -ForegroundColor Green
    }
}

# Also clear PowerShell 5.1 profiles
$ps51Profiles = @(
    "$HOME\Documents\WindowsPowerShell\profile.ps1",
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
)
foreach ($profile in $ps51Profiles) {
    if (Test-Path $profile) {
        Set-Content -Path $profile -Value "" -Force
        Write-Host "[+] Cleared PS 5.1: $profile" -ForegroundColor Green
    }
}

# Configure PowerShell Profile
Write-Host
Write-Host "[*] Configuring PowerShell Profile..." -ForegroundColor Cyan
$profileDir = Split-Path $profileFile -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

$profileContent = @"
# Auto-generated profile loader
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

# Load the main PowerShell profile
. "$profileRepoPath\PowerShellProfile.ps1"
"@

try {
    Set-Content -Path $profileFile -Value $profileContent -Force
    Write-Host "[+] Configured profile at: $profileFile" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not configure profile: $_" -ForegroundColor Yellow
}

# Summary
Write-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host

Write-Host "Profile Location: " -ForegroundColor White -NoNewline
Write-Host $profileRepoPath -ForegroundColor Yellow

Write-Host "Modules Location: " -ForegroundColor White -NoNewline
Write-Host $modulesPath -ForegroundColor Yellow

Write-Host
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Restart your PowerShell session" -ForegroundColor Gray
Write-Host "  2. Run: " -ForegroundColor Gray -NoNewline
Write-Host ". `$PROFILE" -ForegroundColor Yellow -NoNewline
Write-Host " to load the new profile" -ForegroundColor Gray
Write-Host "  3. Verify modules: " -ForegroundColor Gray -NoNewline
Write-Host "Get-Module -ListAvailable" -ForegroundColor Yellow

if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host
    Write-Host "  Note: If Oh My Posh is not available, restart your terminal or add it to PATH" -ForegroundColor Yellow
}

Write-Host
Write-Host "To update in the future, run this script again!" -ForegroundColor Cyan
Write-Host

# Clean up temp script if it was created
if (-not [string]::IsNullOrEmpty($TempScriptPath) -and (Test-Path $TempScriptPath)) {
    try {
        Remove-Item -Path $TempScriptPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Silently ignore cleanup errors
    }
}

Read-Host "Press Enter to exit"