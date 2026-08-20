# All Users All Hosts PowerShell Profile
# Set-Content -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" -Value '. "C:\Users\<YourUsername>\Documents\Coding\WorkspaceMeta\PowerShellProfile\PowerShellProfile.ps1"' -Force

# Current User All Hosts PowerShell Profile
# Set-Content $PROFILE -Value '. "C:\Users\<YourUsername>\Documents\Coding\WorkspaceMeta\PowerShellProfile\PowerShellProfile.ps1"' -force

if ($script:workspaceMetaProfileLoaded) {
    return
}
$script:workspaceMetaProfileLoaded = $true

#region Fork Configuration (CHANGE THESE if you are not PostWarTacos - see README)

# GitHub account that hosts the profile/theme/module downloads used throughout this script
$repoOwner = "PostWarTacos"

# Only needed if your on-disk profile folder differs from $env:UserProfile (e.g. OneDrive-redirected profiles).
# Leave $userProfileOverrideName empty to always use the default Windows user profile path.
$userProfileOverrideName = ""
$userProfileOverridePath = ""

#endregion

#region TEMP Profile Timing Instrumentation (remove when done diagnosing load performance)

$script:profileTimings = [ordered]@{}
$script:profileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:lastCheckpoint = 0.0

function Write-ProfileCheckpoint {
    param([string]$Label)
    $elapsedMs = $script:profileStopwatch.Elapsed.TotalMilliseconds
    $script:profileTimings[$Label] = $elapsedMs - $script:lastCheckpoint
    $script:lastCheckpoint = $elapsedMs
}

#endregion

#region Telemetry Opt-Out

# Check if user account is in the local Administrators group (not if currently elevated)
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$adminSid = [Security.Principal.SecurityIdentifier]'S-1-5-32-544'

# Check if currently running elevated
$isAdmin = ([Security.Principal.WindowsPrincipal]$currentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Opt-out of PowerShell telemetry if currently running as admin
if ($isAdmin) {
    try {
        # Only set if not already configured to avoid unnecessary system calls
        $currentValue = [System.Environment]::GetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', [System.EnvironmentVariableTarget]::Machine)
        if ($currentValue -ne 'true') {
            [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
        }
    } catch {
        # Silently continue if unable to set (e.g., during race conditions with Terminal settings)
    }
}

#endregion
Write-ProfileCheckpoint 'Telemetry Opt-Out'

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
Write-ProfileCheckpoint 'Internet Connectivity Check'

#region Create Coding Directory

If ( $userProfileOverrideName -and ( $(whoami) -match $userProfileOverrideName ) ){
    $user = $userProfileOverridePath
} 
Else {
    $user = [System.Environment]::GetFolderPath("UserProfile")
}

If ( -not ( Test-Path "$user\Documents\Coding" )){
    mkdir "$user\Documents\Coding"
}

#endregion
Write-ProfileCheckpoint 'Create Coding Directory'

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
Write-ProfileCheckpoint 'Install/Update Winget'

#region Install/Update winfetch

function Sync-Winfetch {
    param($hasInternet)
    
    if (-not $hasInternet) {
        return
    }
    
    # Install winfetch if not installed
    if (-not (Get-Command winfetch -ErrorAction SilentlyContinue)) {
        try {
            Install-Script -Name winfetch -Force -Scope CurrentUser -ErrorAction Stop
        } catch {
            # Silent fail - not critical
            return
        }
    }
}

# Sync winfetch in background (non-blocking)
Start-Job -ScriptBlock ${function:Sync-Winfetch} -ArgumentList $hasInternet | Out-Null

#endregion
Write-ProfileCheckpoint 'Install/Update winfetch'

#region PowerShell Modules Auto Git Sync

$repoURL = "https://github.com/$repoOwner/Powershell-Modules.git"
$moduleClonePath = "$user\Documents\Coding\WorkspaceMeta\Powershell-Modules"

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
Write-ProfileCheckpoint 'PowerShell Modules Auto Git Sync'

#region Install/Update Sysinternals Suite

function Sync-Sysinternals {
    param($hasInternet, $isAdmin)

    # Extracting to System32 and editing the machine PATH both require elevation
    if (-not $hasInternet -or -not $isAdmin) {
        return
    }

    $sysinternalsPath = "$env:SystemRoot\System32\SysinternalsSuite"
    $hashMarkerPath = Join-Path $sysinternalsPath ".zipHash"
    $tempZipPath = "$env:TEMP\SysinternalsSuite.zip"

    try {
        Invoke-WebRequest -Uri "https://download.sysinternals.com/files/SysinternalsSuite.zip" -OutFile $tempZipPath -ErrorAction Stop
        $newHash = (Get-FileHash $tempZipPath -Algorithm SHA256).Hash

        # Hash comparison against the last extracted zip stands in for a version check
        $updateRequired = $true
        if (Test-Path $hashMarkerPath) {
            $oldHash = Get-Content $hashMarkerPath -ErrorAction SilentlyContinue
            if ($oldHash -eq $newHash) {
                $updateRequired = $false
            }
        }

        if ($updateRequired) {
            if (-not (Test-Path $sysinternalsPath)) {
                New-Item -Path $sysinternalsPath -ItemType Directory -Force | Out-Null
            }
            Expand-Archive -Path $tempZipPath -DestinationPath $sysinternalsPath -Force
            $newHash | Out-File $hashMarkerPath -Force
        }

        $machinePath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
        if ($machinePath -notlike "*$sysinternalsPath*") {
            [Environment]::SetEnvironmentVariable("Path", "$machinePath;$sysinternalsPath", [EnvironmentVariableTarget]::Machine)
            $env:Path = "$env:Path;$sysinternalsPath"
        }

        $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "Sysinternals Suite.lnk"
        if (-not (Test-Path $shortcutPath)) {
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $sysinternalsPath
            $shortcut.Save()
        }
    } catch {
        # Silent fail - not critical
    } finally {
        Remove-Item $tempZipPath -ErrorAction SilentlyContinue
    }
}

# Sync Sysinternals Suite in background (non-blocking)
Start-Job -ScriptBlock ${function:Sync-Sysinternals} -ArgumentList $hasInternet, $isAdmin | Out-Null

#endregion
Write-ProfileCheckpoint 'Install/Update Sysinternals Suite'

#region Custom Functions

# Profile Management
function Update-Profile {
    try {
        $profileUrl = "https://raw.githubusercontent.com/$repoOwner/PowerShellProfile/refs/heads/main/PowerShellProfile.ps1"
        $currentProfilePath = "$user\Documents\Coding\WorkspaceMeta\PowerShellProfile\PowerShellProfile.ps1"
        
        Write-Host "Checking for profile updates..." -ForegroundColor Cyan
        
        $oldhash = Get-FileHash $currentProfilePath -ErrorAction Stop
        Invoke-RestMethod $profileUrl -OutFile "$env:temp\PowerShellProfile.ps1"
        $newhash = Get-FileHash "$env:temp\PowerShellProfile.ps1"
        
        if ($newhash.Hash -ne $oldhash.Hash) {
            Copy-Item -Path "$env:temp\PowerShellProfile.ps1" -Destination $currentProfilePath -Force
            Write-Host "Profile has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Profile is up to date." -ForegroundColor Green
        }
    } catch {
        Write-Error "Unable to check for profile updates: $_"
    } finally {
        Remove-Item "$env:temp\PowerShellProfile.ps1" -ErrorAction SilentlyContinue
    }
}

# Lazy-load Terminal-Icons wrapper functions (aliases ls, gci, dir automatically use Get-ChildItem)
# Set alias for grep to findstr for Windows users
Set-Alias grep findstr

function Get-ChildItem {
    if (-not $script:terminalIconsLoaded) {
        try {
            if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
                # Try CurrentUser scope first, if that fails and we're admin, try AllUsers
                try {
                    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
                } catch {
                    $isCurrentlyElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if ($isCurrentlyElevated) {
                        Install-Module -Name Terminal-Icons -Scope AllUsers -Force -SkipPublisherCheck -ErrorAction Stop
                    } else {
                        throw
                    }
                }
            }
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
            if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
                # Try CurrentUser scope first, if that fails and we're admin, try AllUsers
                try {
                    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
                } catch {
                    $isCurrentlyElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if ($isCurrentlyElevated) {
                        Install-Module -Name Terminal-Icons -Scope AllUsers -Force -SkipPublisherCheck -ErrorAction Stop
                    } else {
                        throw
                    }
                }
            }
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
            if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
                # Try CurrentUser scope first, if that fails and we're admin, try AllUsers
                try {
                    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
                } catch {
                    $isCurrentlyElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if ($isCurrentlyElevated) {
                        Install-Module -Name Terminal-Icons -Scope AllUsers -Force -SkipPublisherCheck -ErrorAction Stop
                    } else {
                        throw
                    }
                }
            }
            Import-Module -Name Terminal-Icons -ErrorAction Stop
            $script:terminalIconsLoaded = $true
        } catch {
            # Module not available, continue without icons
        }
    }
    Microsoft.PowerShell.Management\Get-ItemProperty @args
}

#endregion
Write-ProfileCheckpoint 'Custom Functions'

#region Add Custom Module Path

# Add my ..\Coding\PowerShell-Modules folder for custom my modules to PSModulePath for auto-loading
# Note: Modules must be in subdirectories matching their names for auto-loading to work
# Example: Powershell-Modules\ModuleName\ModuleName.psd1
If ( Test-Path $moduleClonePath ){
    $env:PSModulePath = "$moduleClonePath;$env:PSModulePath"
}

#endregion
Write-ProfileCheckpoint 'Add Custom Module Path'

#region Cosmetics

# Test if machine is a server. Don't run these commands if it is
# Product type 1 = Workstation. 2 = Domain controller. 3 = non-DC server.
if (( Get-CimInstance -ClassName Win32_OperatingSystem ).ProductType -eq 1 ) {

    # VS Code sets TERM_PROGRAM=vscode in its integrated terminal; skip oh-my-posh there only
    if ( $env:TERM_PROGRAM -ne 'vscode' ) {

        # Install Nerd Font if not already installed (using .NET for faster check)
        $nerdFontInstalled = Test-Path "C:\Windows\Fonts\JetBrainsMonoNerdFont-Bold.ttf"
        if ( -not $nerdFontInstalled -and $hasInternet -and $hasWinget ) {
            Write-Host "Installing JetBrains Mono Nerd Font..."
            winget install --id=DEVCOM.JetBrainsMonoNerdFont -e --source=winget --silent 2>&1 | Out-Null
        }

        # oh-my-posh - loads in Windows Terminal, console host, and ISE
        If ( Get-Command oh-my-posh -ErrorAction SilentlyContinue ){
            $ompConfigPath = "$user\Documents\Coding\WorkspaceMeta\PowerShellProfile\OhMyPoshTheme.json"
            if ( -not ( Test-Path $ompConfigPath ) -and $hasInternet) {
                Invoke-WebRequest "https://raw.githubusercontent.com/$repoOwner/PowerShellProfile/refs/heads/main/OhMyPoshTheme.json"`
                    -OutFile $ompConfigPath
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Invoke-Expression (oh-my-posh init pwsh --config $ompConfigPath)
            } else {
                Invoke-Expression (oh-my-posh init powershell --config $ompConfigPath)
            }
            
            # # Set window title after oh-my-posh to ensure it doesn't get overridden
            # $isCurrentlyElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            # if ($isCurrentlyElevated) {
            #     $host.ui.RawUI.WindowTitle = "Admin: PowerShell"
            # } else {
            #     $host.ui.RawUI.WindowTitle = "User: PowerShell"
            # }
        }
    }

    # Windows Terminal specific extras (settings sync, winfetch) - only in modern terminals
    if ( $env:WT_SESSION ) {

        # Windows Terminal Settings - Check daily for updates using hash comparison
        if ($hasInternet) {
            $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            $lastWTCheckFile = "$env:TEMP\.lastwtcheck"
            $shouldCheck = $true
            
            if (Test-Path $lastWTCheckFile) {
                $lastTimestamp = Get-Content $lastWTCheckFile -ErrorAction SilentlyContinue
                if ($lastTimestamp) {
                    try {
                        $lastCheck = [DateTime]::ParseExact($lastTimestamp, "yyyyMMddHHmmss", $null)
                        $daysSinceLastCheck = ((Get-Date) - $lastCheck).TotalDays
                        if ($daysSinceLastCheck -lt 1) {
                            $shouldCheck = $false
                        }
                    } catch {
                        # Invalid timestamp, allow check
                    }
                }
            }
            
            if ($shouldCheck) {
                try {
                    $localHash = Get-FileHash $wtSettingsPath -ErrorAction Stop
                    Invoke-WebRequest "https://raw.githubusercontent.com/$repoOwner/PowerShellProfile/refs/heads/main/WindowsTerminalSettings.json"`
                        -OutFile "$env:TEMP\WindowsTerminalSettings.json" -ErrorAction Stop
                    $remoteHash = Get-FileHash "$env:TEMP\WindowsTerminalSettings.json"
                    
                    if ($localHash.Hash -ne $remoteHash.Hash) {
                        Copy-Item "$env:TEMP\WindowsTerminalSettings.json" -Destination $wtSettingsPath -Force
                    }
                    
                    Remove-Item "$env:TEMP\WindowsTerminalSettings.json" -ErrorAction SilentlyContinue
                    (Get-Date -Format "yyyyMMddHHmmss") | Out-File $lastWTCheckFile -Force
                } catch {
                    # Silently fail if file is locked or network error - will retry next time
                }
            }
        }
        
        # WinFetch - Only show once every 3 hours
        if ( Get-Command winfetch -ErrorAction SilentlyContinue ){
            $repoWinfetchConfigPath = "$user\Documents\Coding\WorkspaceMeta\PowerShellProfile\WinFetchConfig.ps1"
            $userWinfetchConfigDir = "$user\.config\winfetch"
            $userWinfetchConfigPath = Join-Path $userWinfetchConfigDir "Config.ps1"
            $activeWinfetchConfigPath = $repoWinfetchConfigPath

            # Prefer the repo config so startup always uses your tracked theme/settings.
            if (-not (Test-Path $activeWinfetchConfigPath)) {
                if (-not (Test-Path $userWinfetchConfigDir)) {
                    New-Item -Path $userWinfetchConfigDir -ItemType Directory -Force | Out-Null
                }

                if ( -not ( Test-Path $userWinfetchConfigPath ) -and $hasInternet) {
                    Invoke-WebRequest "https://raw.githubusercontent.com/$repoOwner/PowerShellProfile/refs/heads/main/WinFetchConfig.ps1"`
                        -OutFile $userWinfetchConfigPath
                }

                $activeWinfetchConfigPath = $userWinfetchConfigPath
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
            
            if ($showWinFetch -and (Test-Path $activeWinfetchConfigPath)) {
                winfetch -configpath $activeWinfetchConfigPath
                (Get-Date -Format "yyyyMMddHHmmss") | Out-File $lastWinFetchFile -Force
            }
        }
    }
}
 
#endregion
Write-ProfileCheckpoint 'Cosmetics'

#region PSReadLineOptions

# A previously-tested "!!" alias left bare "!!" lines in the PSReadLine history file;
# those don't parse as PowerShell and crash history loading in every new session, so scrub them.
try {
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if ($historyPath -and (Test-Path $historyPath)) {
        $historyLines = Get-Content $historyPath -ErrorAction Stop
        $cleanedLines = $historyLines | Where-Object { $_.Trim() -ne '!!' }
        if ($cleanedLines.Count -ne $historyLines.Count) {
            $cleanedLines | Set-Content $historyPath -Force
        }
    }
} catch {
    # Silently continue - not critical
}

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
        try {
            # Throws when there's no suggestion available to accept
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord( $key, $arg )
        } catch {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar( $key, $arg )
        }
    }
}

#endregion
Write-ProfileCheckpoint 'PSReadLineOptions'

$ErrorActionPreference = 'Continue'
$sessionHome = [System.Environment]::GetFolderPath("UserProfile")
set-location $sessionHome

#region Transcript

$transcriptDir = "$user\Documents\Coding\PowerShell-Transcripts"
If ( -not ( Test-Path $transcriptDir )){
	mkdir $transcriptDir | Out-Null
}

$transcriptFileName = "PowerShell_transcript_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss")
$transcriptPath = Join-Path $transcriptDir $transcriptFileName
Start-Transcript -Path $transcriptPath -NoClobber -IncludeInvocationHeader | Out-Null

# Stop-Transcript won't run on its own if the console window is closed instead of exited normally.
$transcriptState = @{
    Path = $transcriptPath
    TimingLines = $null
}

Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $transcriptState -Action {
    $state = $event.MessageData
    Stop-Transcript -ErrorAction SilentlyContinue

    if ($state.TimingLines -and (Test-Path $state.Path)) {
        try {
            $transcriptContent = [System.IO.File]::ReadAllText($state.Path)
            $timingText = $state.TimingLines -join [Environment]::NewLine
            [System.IO.File]::WriteAllText(
                $state.Path,
                "$timingText$([Environment]::NewLine)$([Environment]::NewLine)$transcriptContent",
                [System.Text.UTF8Encoding]::new($false)
            )
        } catch {
            # Silently continue - the transcript was already stopped.
        }
    }
} | Out-Null

#endregion
Write-ProfileCheckpoint 'Transcript'

#region TEMP Profile Timing Summary (remove when done diagnosing load performance)

$script:profileStopwatch.Stop()
$timingLines = [System.Collections.Generic.List[string]]::new()
$timingLines.Add("")
$timingLines.Add("Profile load timings:")
$script:profileTimings.GetEnumerator() | ForEach-Object {
    $ms = [math]::Round($_.Value, 1)
    $sec = [math]::Round($_.Value / 1000, 3)
    $timingLines.Add( ("  {0,-40} {1,8:N1} ms  ({2,6:N3} s)" -f $_.Key, $ms, $sec) )
}
$timingLines.Add( ("  {0,-40} {1,8:N1} ms  ({2,6:N3} s)" -f 'TOTAL', $script:profileStopwatch.Elapsed.TotalMilliseconds, $script:profileStopwatch.Elapsed.TotalSeconds) )

# The exit handler stops the transcript before prepending these timings, avoiding
# writes to a transcript file while Start-Transcript still has it open.
$transcriptState.TimingLines = $timingLines.ToArray()

#endregion

