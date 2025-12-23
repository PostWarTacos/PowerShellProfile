# All Users All Hosts PowerShell Profile
# Set-Content -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" -Value '. "C:\Users\wurtzmt\Documents\Coding\PowerShellProfile\PowerShellProfile.ps1"' -Force

# Current User All Hosts PowerShell Profile
# Set-Content $PROFILE -Value '. "C:\Users\wurtzmt\Documents\Coding\PowerShellProfile\PowerShellProfile.ps1"' -force

$ErrorActionPreference = 'SilentlyContinue'

Clear-Host

Write-Host "Loading profile..." -ForegroundColor Cyan

#region Internet Connectivity Check

# Check if system reports internet connectivity (query Windows, don't actively test)
$hasInternet = $false
try {
    $connectionProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }
    if ($connectionProfile) {
        $hasInternet = $true
    }
} catch {
    $hasInternet = $false
}

#endregion

#region Create Coding Directory

If ( $(whoami) -match "wurtzmt" ){
    $user = "C:\users\wurtzmt"
} 
Else {
    $user = [System.Environment]::GetFolderPath("UserProfile")
}

If ( -not ( Test-Path "$user\Documents\Coding" )){
    mkdir "$user\Documents\Coding"
}

#endregion

#region Install/Update Winget

# Check if winget is available
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

function Sync-Winget {
    param($hasInternet)
    
    if (-not $hasInternet) {
        return
    }
    
    # Install winget if needed (Windows 10 1809+ / Server 2022+)
    If ( -not ( Get-Command winget -ErrorAction SilentlyContinue )) {
        try {
            Write-Host "Installing winget..."
            $progressPreference = 'silentlyContinue'
            Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
            Add-AppxPackage "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
        } catch {
            Write-Host "Failed to install winget. Please install manually via https://aka.ms/getwinget."
            return
        }
    }
    
    # Check if winget was updated in the last week
    $lastWingetUpdateFile = "$env:TEMP\.lastwingetupdate"
    $shouldUpdate = $true
    
    if (Test-Path $lastWingetUpdateFile) {
        $lastTimestamp = Get-Content $lastWingetUpdateFile -ErrorAction SilentlyContinue
        if ($lastTimestamp) {
            $lastUpdate = [DateTime]::ParseExact($lastTimestamp, "yyyyMMddHHmmss", $null)
            $daysSinceLastUpdate = ((Get-Date) - $lastUpdate).TotalDays
            if ($daysSinceLastUpdate -lt 7) {
                $shouldUpdate = $false
            }
        }
    }
    
    if ($shouldUpdate -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        winget upgrade --id Microsoft.AppInstaller -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        (Get-Date -Format "yyyyMMddHHmmss") | Out-File $lastWingetUpdateFile -Force
    }
}

# Sync winget in background (non-blocking)
Start-Job -ScriptBlock ${function:Sync-Winget} -ArgumentList $hasInternet | Out-Null

#endregion

#region PowerShell Modules Auto Git Sync

$repoURL = "https://github.com/PostWarTacos/Powershell-Modules.git"
$moduleClonePath = "$user\Documents\Coding\Powershell-Modules"

function Sync-GitModules {
    param($moduleClonePath, $repoURL, $hasInternet)
    
    if (-not $hasInternet) {
        return
    }
    
    # Check if git is installed, install if needed
    If ( -not ( Get-Command git -ErrorAction SilentlyContinue )) {
        If ( $hasWinget ) {
            try {
                Write-Host "Installing git..."
                winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Host "Failed to install git via winget. Please install manually via https://git-scm.com/download/win"
                return
            }
        }
        else {
            return
        }
    }
      
    If ( -not ( Test-Path "$moduleClonePath" )){
        New-Item -Path "$moduleClonePath" -ItemType Directory -Force | Out-Null
    }
    
    Set-Location $moduleClonePath
    
    if ( -not ( Test-Path "$moduleClonePath\.git" )) {
        git init 2>&1 | Out-Null
        git remote add origin $repoURL 2>&1 | Out-Null
        git pull origin main 2>&1 | Out-Null
        return
    }

    # Check if there are remote changes before pulling
    git fetch origin main 2>&1 | Out-Null
    $localHash = git rev-parse HEAD 2>&1
    $remoteHash = git rev-parse origin/main 2>&1
    
    if ($localHash -ne $remoteHash) {
        git pull origin main 2>&1 | Out-Null
    }
}

# Sync custom PowerShell modules in background (non-blocking)
Start-Job -ScriptBlock ${function:Sync-GitModules} -ArgumentList $moduleClonePath, $repoURL, $hasInternet | Out-Null

#endregion

#region Custom Functions

# grep
function grep($regex, $dir) {
    if ( $dir ) {
            Get-ChildItem $dir | select-string $regex
            return
    }
    $input | select-string $regex
}

# find-file
function find-file($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
            $place_path = $_.directory
            Write-Output "${place_path}\${_}"
    }
}

# Lazy-load Terminal-Icons wrapper functions (aliases ls, gci, dir automatically use Get-ChildItem)
function Get-ChildItem {
    if (-not $script:terminalIconsLoaded) {
        try {
            Import-Module -Name Terminal-Icons -ErrorAction Stop
            $script:terminalIconsLoaded = $true
        } catch {
            # Module not available, continue without icons
        }
    }
    Microsoft.PowerShell.Management\Get-ChildItem @args
}

function Get-Item {
    if (-not $script:terminalIconsLoaded) {
        try {
            Import-Module -Name Terminal-Icons -ErrorAction Stop
            $script:terminalIconsLoaded = $true
        } catch {
            # Module not available, continue without icons
        }
    }
    Microsoft.PowerShell.Management\Get-Item @args
}

function Get-ItemProperty {
    if (-not $script:terminalIconsLoaded) {
        try {
            Import-Module -Name Terminal-Icons -ErrorAction Stop
            $script:terminalIconsLoaded = $true
        } catch {
            # Module not available, continue without icons
        }
    }
    Microsoft.PowerShell.Management\Get-ItemProperty @args
}

#endregion

#region Add Custom Module Path

# Add custom module path to PSModulePath for auto-loading
# Note: Modules must be in subdirectories matching their names for auto-loading to work
# Example: Powershell-Modules\ModuleName\ModuleName.psd1
If ( Test-Path $moduleClonePath ){
    $env:PSModulePath = "$moduleClonePath;$env:PSModulePath"
}

#endregion

#region Cosmetics

# Test if machine is a server. Don't run these commands if it is
# Product type 1 = Workstation. 2 = Domain controller. 3 = non-DC server.
if (( Get-CimInstance -ClassName Win32_OperatingSystem ).ProductType -eq 1 ) {
    # Download configs and apply locally
    # Only load in modern terminals (not ISE)
    if ( $env:WT_SESSION ) {
	           
        # Install Nerd Font if not already installed (using .NET for faster check)
        $nerdFontInstalled = Test-Path "C:\Windows\Fonts\JetBrainsMonoNerdFont-Bold.ttf"
        if ( -not $nerdFontInstalled -and $hasInternet -and $hasWinget ) {
            Write-Host "Installing JetBrains Mono Nerd Font..."
            winget install --id=DEVCOM.JetBrainsMonoNerdFont -e --source=winget --silent 2>&1 | Out-Null
        }

        # oh-my-posh
        If ( Get-Command oh-my-posh -ErrorAction SilentlyContinue ){
            $ompConfigPath = "$user\Documents\Coding\PowerShellProfile\OhMyPoshTheme.json"
            if ( -not ( Test-Path $ompConfigPath ) -and $hasInternet) {
                Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/OhMyPoshTheme.json"`
                    -OutFile $ompConfigPath
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Invoke-Expression (oh-my-posh init pwsh --config $ompConfigPath)
            } else {
                Invoke-Expression (oh-my-posh init powershell --config $ompConfigPath)
            }
        }        

        # Windows Terminal Settings
        if ($hasInternet) {
            $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/WindowsTerminalSettings.json"`
                -OutFile $wtSettingsPath
        }
        
        # WinFetch - Only show once every 3 hours
        if ( Get-Command WinFetch ){
            $winfetchConfigPath = "$user\.config\winfetch\Config.ps1"
            if ( -not ( Test-Path $winfetchConfigPath ) -and $hasInternet) {
                Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/WinFetchConfig.ps1"`
                    -OutFile $winfetchConfigPath
            }
            
            # Check if WinFetch was shown in the last 3 hours
            $lastWinFetchFile = "$env:TEMP\.lastwinfetch"
            $showWinFetch = $true
            
            if (Test-Path $lastWinFetchFile) {
                $lastTimestamp = Get-Content $lastWinFetchFile -ErrorAction SilentlyContinue
                if ($lastTimestamp) {
                    $lastRun = [DateTime]::ParseExact($lastTimestamp, "yyyyMMddHHmmss", $null)
                    $hoursSinceLastRun = ((Get-Date) - $lastRun).TotalHours
                    if ($hoursSinceLastRun -lt 3) {
                        $showWinFetch = $false
                    }
                }
            }
            
            if ($showWinFetch) {
                winfetch -configpath $winfetchConfigPath
                (Get-Date -Format "yyyyMMddHHmmss") | Out-File $lastWinFetchFile -Force
            }
        }
    }
}
 
#endregion

#region PSReadLineOptions

# Searching for commands with up/down arrow is really handy.  The
# option "moves to end" is useful if you want the cursor at the end
# of the line while cycling through history like it does w/o searching,
# without that option, the cursor will remain at the position it was
# when you used up arrow, which can be useful if you forget the exact
# string you started the search on.
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# This key handler shows the entire or filtered history using Out-GridView. The
# typed text is used as the substring pattern for filtering. A selected command
# is inserted to the command line without invoking. Multiple command selection
# is supported, e.g. selected by Ctrl + Click.
# As another example, the module 'F7History' does something similar but uses the
# console GUI instead of Out-GridView. Details about this module can be found at
# PowerShell Gallery: https://www.powershellgallery.com/packages/F7History.
Set-PSReadLineKeyHandler -Key F7 `
                         -BriefDescription History `
                         -LongDescription 'Show command history' `
                         -ScriptBlock {
    $pattern = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
    if ($pattern)
    {
        $pattern = [regex]::Escape($pattern)
    }

    $history = [System.Collections.ArrayList]@(
        $last = ''
        $lines = ''
        foreach ( $line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath ))
        {
            if ($line.EndsWith('`'))
            {
                $line = $line.Substring( 0, $line.Length - 1 )
                $lines = if ( $lines )
                {
                    "$lines`n$line"
                }
                else
                {
                    $line
                }
                continue
            }

            if ( $lines )
            {
                $line = "$lines`n$line"
                $lines = ''
            }

            if (( $line -cne $last ) -and ( !$pattern -or ( $line -match $pattern )))
            {
                $last = $line
                $line
            }
        }
    )
    $history.Reverse()

    $command = $history | Out-GridView -Title History -PassThru
    if ( $command )
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
    }
}

# `ForwardChar` accepts the entire suggestion text when the cursor is at the end of the line.
# This custom binding makes `RightArrow` behave similarly - accepting the next word instead of the entire suggestion text.
Set-PSReadLineKeyHandler -Key RightArrow `
                         -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
                         -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
                         -ScriptBlock {
    param( $key, $arg )

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState( [ref]$line, [ref]$cursor )

    if ( $cursor -lt $line.Length ) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar( $key, $arg )
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord( $key, $arg )
    }
}

#endregion

$ErrorActionPreference = 'Continue'
set-location $user

#region Transcript

If ( -not ( Test-Path "$user\Documents\Coding\PowerShell-Transcripts" )){
	mkdir "$user\Documents\Coding\PowerShell-Transcripts" | Out-Null
}

Start-Transcript -OutputDirectory "$user\Documents\Coding\PowerShell-Transcripts" -NoClobber -IncludeInvocationHeader | Out-Null

#endregion
