# Sandbox PowerShell profile. Copied to Documents\PowerShell and
# Documents\WindowsPowerShell by bootstrap.ps1 so both pwsh and
# powershell.exe pick it up.

$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

# Package caches live on the mapped host folder so they survive sandbox teardown.
if (Test-Path 'C:\Cache') {
    $env:SCOOP_CACHE      = 'C:\Cache\scoop'
    $env:npm_config_cache = 'C:\Cache\npm'
}

Set-Alias -Name vi  -Value nvim -ErrorAction SilentlyContinue
Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue

function ll { Get-ChildItem -Force @args }
function gs { git status @args }

# fzf-backed directory jump, using fd for the listing.
function ff {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { Write-Warning 'fzf not installed'; return }
    $dir = fd --type d --hidden --exclude .git . | fzf
    if ($dir) { Set-Location $dir }
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

if (Test-Path 'C:\Workspace') { Set-Location 'C:\Workspace' }
