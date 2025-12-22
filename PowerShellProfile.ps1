# All Users All Hosts PowerShell Profile
# Set-Content -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" -Value '. "C:\Users\wurtzmt\Documents\Coding\PowerShellProfile\PowerShellProfile.ps1"' -Force

# Current User All Hosts PowerShell Profile
# Set-Content $PROFILE -Value '. "C:\Users\wurtzmt\Documents\Coding\PowerShellProfile\PowerShellProfile.ps1"' -force

Write-Host "Prepping Workspace..."

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

#region PowerShell Modules Auto Git Sync

# Check if git is installed, install if needed
If ( -not ( Get-Command git -ErrorAction SilentlyContinue )) {
    If ( Get-Command winget -ErrorAction SilentlyContinue ) {
        winget install --id Git.Git -e --source winget --silent
    } ElseIf ( Get-Command choco -ErrorAction SilentlyContinue ) {
        choco install git -y
    } Else {
        Write-Host "Please install Git manually from https://git-scm.com/download/win"
    }
}

$repoURL = "https://github.com/PostWarTacos/Powershell-Modules.git"
$clonePath = "$user\Documents\Coding\Powershell-Modules"

function Sync-GitModules {
    if (-not $hasInternet) {
        Write-Host "No internet connection detected. Skipping git sync."
        return
    }
      
    If ( -not ( Test-Path "$clonePath" )){
        mkdir "$clonePath" | Out-Null
    }
    if ( -not ( Test-Path "$clonePath\.git" )) {
        Set-Location $clonePath
        git init 2>&1 | Out-Null
        git remote add origin $repoURL 2>&1 | Out-Null
        git pull origin main 2>&1 | Out-Null
        return
    }

    Set-Location $clonePath
    # Check if there are remote changes before pulling
    git fetch origin main 2>&1 | Out-Null
    $localHash = git rev-parse HEAD 2>&1
    $remoteHash = git rev-parse origin/main 2>&1
    
    if ($localHash -ne $remoteHash) {
        git pull origin main 2>&1 | Out-Null
    }
}

# Sync custom PowerShell modules automatically when PowerShell starts
Sync-GitModules

#endregion

#region Linux-like Commands

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

#endregion

#region Import PSModules

If ( Test-Path $clonePath\Modules ){
    $modules = Get-ChildItem $clonePath
    foreach ( $module in $modules ){
        Import-Module $module.fullname
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

#region Cosmetics

# Test if machine is a server. Don't run these commands if it is
# Product type 1 = Workstation. 2 = Domain controller. 3 = non-DC server.
if (( Get-WmiObject -class win32_OperatingSystem ).ProductType -eq 1 ) {
    # Download configs and apply locally
    # Only load in modern terminals (not ISE)
    if ( $env:WT_SESSION ) {
	           
        # Install Nerd Font if not already installed
        $nerdFontInstalled = Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\JetBrainsMonoNerdFont*.ttf"
        if ( -not $nerdFontInstalled ) {
            winget install --id=DEVCOM.JetBrainsMonoNerdFont -e --source=winget --silent 2>&1 | Out-Null
        }
        
        # Terminal Icons
        Import-Module -Name Terminal-Icons

        # oh-my-posh
        If ( Get-Command oh-my-posh -ErrorAction SilentlyContinue ){
            $ompConfigPath = "$user\Documents\Coding\PowerShellProfile\OhMyPoshTheme.json"
            if ( -not ( Test-Path $ompConfigPath ) -and $hasInternet) {
                Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/OhMyPoshTheme.json"`
                    -OutFile $ompConfigPath
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                oh-my-posh init pwsh --config $ompConfigPath | Invoke-Expression
            } else {
                oh-my-posh init powershell --config $ompConfigPath | Invoke-Expression
            }
        }        

        # Windows Terminal Settings
        if ($hasInternet) {
            $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/WindowsTerminalSettings.json"`
                -OutFile $wtSettingsPath
        }
        
        # WinFetch
        if ( Get-Command WinFetch ){
            $winfetchConfigPath = "$user\.config\winfetch\Config.ps1"
            if ( -not ( Test-Path $winfetchConfigPath ) -and $hasInternet) {
                Invoke-WebRequest "https://raw.githubusercontent.com/PostWarTacos/PowerShellProfile/refs/heads/main/WinFetchConfig.ps1"`
                    -OutFile $winfetchConfigPath
            }
            winfetch -configpath $winfetchConfigPath
        }
    }
}
 
#endregion

set-location $user

#region Transcript

If ( -not ( Test-Path "$user\Documents\Coding\PowerShell-Transcripts" )){
	mkdir "$user\Documents\Coding\PowerShell-Transcripts" | Out-Null
}

Start-Transcript -OutputDirectory "$user\Documents\Coding\PowerShell-Transcripts" -NoClobber -IncludeInvocationHeader | Out-Null

#endregion
