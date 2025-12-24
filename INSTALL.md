# PowerShell Environment Installation

Quick installation script for setting up a complete PowerShell environment with custom profile, modules, and prerequisites.

## Quick Install

### One-Line Installation

**Important:** Replace `USERNAME` with your actual GitHub username before running!

```powershell
irm https://raw.githubusercontent.com/USERNAME/PowerShellProfile/main/Install-PowerShellSetup.ps1 | iex
```

## What Gets Installed

### Prerequisites
- **winget** - Windows Package Manager
- **git** - Version control system
- **PSReadLine** - Enhanced command-line editing
- **Terminal-Icons** - File and folder icons in the terminal
- **Oh My Posh** - Theme engine for PowerShell prompt
- **JetBrains Mono Nerd Font** - Font with icon support
- **winfetch** - System information tool

### Repositories
The script clones two repositories into `~\Documents\Coding\`:
- **PowerShellProfile** - Profile scripts, Oh My Posh theme, and configurations
- **Powershell-Modules** - Custom PowerShell modules

## Installation Locations

- **Profile Files:** `~\Documents\Coding\PowerShellProfile\`
- **Modules:** `~\Documents\Coding\Powershell-Modules\`
- **PowerShell Profile:** `$PROFILE.CurrentUserAllHosts`

## Parameters

The installation script supports several parameters:

```powershell
Install-PowerShellSetup.ps1 [-GitHubUser <string>] [-SkipPrerequisites] [-ProfileRepo <string>] [-ModulesRepo <string>] [-Branch <string>]
```

### Parameters

- `-GitHubUser` - Your GitHub username (default: USERNAME)
- `-SkipPrerequisites` - Skip installing prerequisites if already installed
- `-ProfileRepo` - Name of the profile repository (default: PowerShellProfile)
- `-ModulesRepo` - Name of the modules repository (default: Powershell-Modules)
- `-Branch` - Git branch to download from (default: main)

### Examples

Skip prerequisites:
```powershell
irm https://raw.githubusercontent.com/USERNAME/PowerShellProfile/main/Install-PowerShellSetup.ps1 | iex -ArgumentList @{SkipPrerequisites=$true}
```

Custom branch:
```powershell
irm https://raw.githubusercontent.com/USERNAME/PowerShellProfile/main/Install-PowerShellSetup.ps1 | iex -ArgumentList @{Branch='dev'}
```

## Post-Installation

After installation completes:

1. **Restart PowerShell** or run:
   ```powershell
   . $PROFILE
   ```

2. **Verify modules are available:**
   ```powershell
   Get-Module -ListAvailable
   ```

3. **Check Oh My Posh:**
   ```powershell
   oh-my-posh --version
   ```
   
   If not found, restart your terminal to refresh the PATH.

## Updating

To update your installation, simply run the installation command again. It will overwrite existing files with the latest versions from GitHub.

## Manual Installation

If you prefer to install manually:

1. Install prerequisites:
   ```powershell
   # Install winget (if not already installed)
   Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
   Add-AppxPackage "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
   
   # Install git, Oh My Posh, and Nerd Font
   winget install Git.Git JanDeDobbeleer.OhMyPosh DEVCOM.JetBrainsMonoNerdFont
   
   # Install PowerShell modules
   Install-Module PSReadLine, Terminal-Icons -Force -Scope CurrentUser
   ```

2. Clone the repositories:
   ```powershell
   cd ~\Documents\Coding
   git clone https://github.com/PostWarTacos/PowerShellProfile.git
   git clone https://github.com/PostWarTacos/Powershell-Modules.git
   ```

3. Set up your profile:
   
   **Current User (recommended):**
   ```powershell
   $content = '. "' + (Join-Path $HOME 'Documents\Coding\PowerShellProfile\PowerShellProfile.ps1') + '"'
   Set-Content $PROFILE.CurrentUserAllHosts -Value $content -Force
   ```
   
   **All Users (requires Administrator):**
   ```powershell
   $content = '. "' + (Join-Path $HOME 'Documents\Coding\PowerShellProfile\PowerShellProfile.ps1') + '"'
   Set-Content $PROFILE.AllUsersAllHosts -Value $content -Force
   ```

4. Add modules to path:
   ```powershell
   $modulePath = Join-Path $HOME 'Documents\Coding\Powershell-Modules'
   $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
   [Environment]::SetEnvironmentVariable("PSModulePath", "$modulePath;$currentPath", "User")
   ```

## Troubleshooting

### Script Execution Policy

If you get an execution policy error:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Oh My Posh Not Found

If Oh My Posh is not found after installation:
1. Restart your terminal
2. Or manually add to PATH: `C:\Users\<username>\AppData\Local\Programs\oh-my-posh\bin`

### Module Not Loading

If custom modules aren't loading:
```powershell
# Check PSModulePath
$env:PSModulePath -split ';'

# Manually add the path for current session
$env:PSModulePath += ";$HOME\Documents\Coding\Powershell-Modules"

# Import a module manually
Import-Module "$HOME\Documents\Coding\Powershell-Modules\ModuleName"
```

## Requirements

- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** or **PowerShell 7+**
- **Internet connection** for downloading files and prerequisites
- **Administrator rights** (optional, but recommended for full feature set)

## Security Note

Always review scripts before running them with `irm | iex`. You can download and inspect the script first:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/USERNAME/PowerShellProfile/main/Install-PowerShellSetup.ps1" -OutFile ".\Install-PowerShellSetup.ps1"
# Review the file
notepad .\Install-PowerShellSetup.ps1
# Then run it
.\Install-PowerShellSetup.ps1
```

## Uninstallation

To remove the installation:

1. Remove profile reference:
   ```powershell
   Remove-Item $PROFILE.CurrentUserAllHosts -Force
   ```

2. Remove directories:
   ```powershell
   Remove-Item "$HOME\Documents\Coding\PowerShellProfile" -Recurse -Force
   Remove-Item "$HOME\Documents\Coding\Powershell-Modules" -Recurse -Force
   ```

3. Clean up PSModulePath:
   ```powershell
   $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
   $newPath = ($currentPath -split ';' | Where-Object { $_ -notlike "*Powershell-Modules*" }) -join ';'
   [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")
   ```

