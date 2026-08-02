<#
.SYNOPSIS
    Lists agent workspace projects.

.DESCRIPTION
    Shows only distros this tool owns (the agentdev- prefix), never your own
    Ubuntu or docker-desktop distros. Reports whether each is running, its disk
    usage, and its git state.

.PARAMETER Detailed
    Also query each instance for branch and uncommitted-change count. This
    starts any stopped instance in order to ask, so it is off by default.

.EXAMPLE
    .\Get-Project.ps1
.EXAMPLE
    .\Get-Project.ps1 -Detailed
#>
[CmdletBinding()]
param(
    [switch]$Detailed,

    # Suppress the trailing "Open with: ..." line, for callers that want to
    # print their own contextual hint instead.
    [switch]$NoHint
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not (Test-WslAvailable)) { throw 'wsl.exe not found.' }

# wsl.exe emits UTF-16LE; --list --running is parsed the same way as --list.
$previousEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [Text.Encoding]::Unicode
    $running = @(& wsl.exe --list --running --quiet 2>$null |
                 ForEach-Object { $_.Trim() } | Where-Object { $_ })
} finally {
    [Console]::OutputEncoding = $previousEncoding
}

$projects = Get-WslDistro |
    Where-Object { $_.StartsWith($AgentDevPrefix) -and $_ -ne "${AgentDevPrefix}basebuild" }

if (-not $projects) {
    Write-Host ''
    Write-Host '  No projects yet. Create one with: corral new <name>' -ForegroundColor Yellow
    Write-Host ''
    return
}

$rows = foreach ($distro in $projects) {
    $name        = $distro.Substring($AgentDevPrefix.Length)
    $instanceDir = Join-Path $AgentDev.Instances $name

    $sizeGB = 0
    if (Test-Path $instanceDir) {
        $bytes = (Get-ChildItem $instanceDir -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        if ($bytes) { $sizeGB = [math]::Round($bytes / 1GB, 2) }
    }

    $row = [ordered]@{
        Name    = $name
        State   = if ($running -contains $distro) { 'running' } else { 'stopped' }
        DiskGB  = $sizeGB
    }

    if ($Detailed) {
        $git = Invoke-InDistro -DistroName $distro -AllowFailure -Command @'
cd ~/workspace 2>/dev/null || exit 0
printf '%s|%s' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(git status --porcelain 2>/dev/null | wc -l)"
'@
        $parts = ("$git" -split '\|')
        $row.Branch = if ($parts.Count -ge 1 -and $parts[0]) { $parts[0] } else { '?' }
        $row.Dirty  = if ($parts.Count -ge 2 -and $parts[1]) { [int]$parts[1] } else { 0 }
    }

    [pscustomobject]$row
}

# Rendered to a string first: Format-Table streams lazily, so writing it
# directly would let the trailing hint print above the table.
$table = $rows | Format-Table -AutoSize | Out-String

Write-Host $table.TrimEnd()
Write-Host ''
if (-not $NoHint) {
    Write-Host "  Open with: corral open <name>" -ForegroundColor DarkGray
    Write-Host ''
}
