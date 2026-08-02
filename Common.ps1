# Shared paths, validation and WSL helpers for the project scripts.
# Dot-sourced, not a module - there is no state to manage.

$script:AgentDevRoot = Split-Path -Parent $PSCommandPath

$AgentDev = [pscustomobject]@{
    Root      = $script:AgentDevRoot
    Projects  = Join-Path $script:AgentDevRoot 'Projects'    # git bundles / exports
    Instances = Join-Path $script:AgentDevRoot 'Instances'   # per-project VHDX
    Cache     = Join-Path $script:AgentDevRoot 'Cache'
    Provision = Join-Path $script:AgentDevRoot 'provision'
    Dotfiles  = Join-Path $script:AgentDevRoot 'Dotfiles'
    BaseImage = Join-Path $script:AgentDevRoot 'Cache\base\agentdev-base.tar'
}

# Every instance is prefixed so it is obvious which distros this tool owns and
# so we never touch the user's own Ubuntu or docker-desktop distros.
$AgentDevPrefix = 'agentdev-'

$script:ReservedNames = @(
    'CON','PRN','AUX','NUL',
    'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
    'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'
)

<#
.SYNOPSIS
    Rejects any project name that could escape the instances directory or
    collide with an unrelated distro.
#>
function Assert-ProjectName {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -notmatch '^[a-z0-9][a-z0-9._-]{0,48}$') {
        throw "Invalid project name '$Name'. Use 1-49 characters: lowercase letters, digits, dot, underscore or hyphen, starting with a letter or digit."
    }
    if ($Name -match '\.\.') {
        throw "Invalid project name '$Name'. Path traversal is not allowed."
    }
    if ($script:ReservedNames -contains $Name.Split('.')[0].ToUpperInvariant()) {
        throw "Invalid project name '$Name'. That is a reserved Windows device name."
    }
    return $Name
}

function Get-DistroName {
    param([Parameter(Mandatory)][string]$Name)
    "$AgentDevPrefix$Name"
}

<#
.SYNOPSIS
    Lists registered WSL distributions.
.DESCRIPTION
    wsl.exe emits UTF-16LE, which turns every character into "c`0h`0a`0r`0"
    when PowerShell reads it as UTF-8. Forcing the output encoding for the
    duration of the call is the only reliable way to parse wsl.exe output.
#>
function Get-WslDistro {
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $lines = & wsl.exe --list --quiet 2>$null
    } finally {
        [Console]::OutputEncoding = $previous
    }
    $lines | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Test-WslDistro {
    param([Parameter(Mandatory)][string]$DistroName)
    (Get-WslDistro) -contains $DistroName
}

<#
.SYNOPSIS
    Runs a script inside an instance as the dev user, returning its output.
.DESCRIPTION
    The script is staged as a file rather than passed as an argument to
    `bash -lc`. Passing a multi-line script through wsl.exe's argument handling
    silently eats shell variable references - `$f` inside a for-loop arrives
    empty while `$(command)` substitution still works, which produces results
    that look plausible but are wrong. Writing the script to a file and running
    `bash -l <file>` sidesteps the whole class of problem.

    Runs as a login shell so nvm and PATH are set up.
#>
function Invoke-InDistro {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Command,
        [string]$User = 'dev',
        [switch]$AllowFailure
    )
    $remotePath = "/tmp/.agentdev-$([guid]::NewGuid().ToString('N')).sh"
    Write-DistroFile -DistroName $DistroName -Path $remotePath -Content $Command

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & wsl.exe -d $DistroName --user $User --cd '~' -- bash -l $remotePath 2>&1
        $exit   = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
        & wsl.exe -d $DistroName --user root -- rm -f $remotePath 2>&1 | Out-Null
    }

    if ($exit -ne 0 -and -not $AllowFailure) {
        throw "Script failed in '$DistroName' (exit $exit):`n$($output -join "`n")"
    }
    return $output
}

<#
.SYNOPSIS
    Writes a file into a distro without relying on Windows interop.
.DESCRIPTION
    \\wsl.localhost paths are unavailable while a distro is stopped, and
    instances deliberately have interop disabled, so content is piped in over
    stdin and written with tee.
#>
function Write-DistroFile {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Transferred as base64 rather than as raw text. Piping text to a native
        # command lets PowerShell append CRLF, which leaves a stray \r on the
        # final line - enough to silently break the last setting in
        # /etc/wsl.conf or corrupt a shell script. base64 is pure ASCII, and
        # stripping CR/LF before decoding makes the transfer immune to whatever
        # line endings the pipeline introduces.
        $normalised = $Content -replace "`r`n", "`n"
        $encoded    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalised))

        $escapedPath = $Path.Replace("'", "'\''")
        $encoded | & wsl.exe -d $DistroName --user root -- bash -c `
            "mkdir -p `"`$(dirname '$escapedPath')`" && tr -d '\r\n' | base64 -d > '$escapedPath'"
        if ($LASTEXITCODE -ne 0) { throw "Failed writing $Path in $DistroName (exit $LASTEXITCODE)" }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Test-WslAvailable {
    [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
}
