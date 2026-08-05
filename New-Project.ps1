<#
.SYNOPSIS
    Creates an isolated WSL2 instance for one project and opens it.

.DESCRIPTION
    Clones the base image into a fresh distro, locks down its WSL configuration
    so it cannot see the Windows filesystem or execute Windows binaries,
    initialises a git repository in the workspace, and opens a terminal.

    Isolation comes from three things:
      - a dedicated distro per project, each with its own root filesystem
      - automount disabled, so C:\ is not mounted at /mnt/c
      - interop disabled, so Windows executables cannot be launched

    Project files live on ext4 inside the instance. That is deliberate:
    cross-OS file access via drvfs is WSL's slowest path, and React Native's
    Metro bundler plus a large node_modules make it painful.

    Note that \\wsl.localhost\agentdev-<name>\ does NOT resolve - the isolation
    settings below also stop WSL serving the filesystem to Windows. Move files
    with wsl.exe instead; see "Moving files in and out" in the README.

.PARAMETER Name
    Project name. Becomes the distro 'agentdev-<name>'.

.PARAMETER NoLaunch
    Create the instance but do not open a terminal.

.EXAMPLE
    .\New-Project.ps1 invoice-service
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-ProjectName $Name | Out-Null
$distro = Get-DistroName $Name

if (-not (Test-WslAvailable)) { throw 'wsl.exe not found. Install WSL with: wsl --install' }

if (-not (Test-Path $AgentDev.BaseImage)) {
    throw "No base image at $($AgentDev.BaseImage). Build it first with: corral build"
}
if (Test-WslDistro $distro) {
    throw "Project '$Name' already exists. Open it with: corral open $Name"
}

$instanceDir = Join-Path $AgentDev.Instances $Name
New-Item -ItemType Directory -Path $instanceDir -Force | Out-Null

Write-Host ''
Write-Host "  Creating '$Name' from base image..." -ForegroundColor Cyan

& wsl.exe --import $distro $instanceDir $AgentDev.BaseImage --version 2
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed (exit $LASTEXITCODE)" }
Write-Host "  instance   $instanceDir" -ForegroundColor Gray

# Lock the instance down before it is ever used interactively.
$wslConf = (Get-Content (Join-Path $AgentDev.Provision 'wsl.conf') -Raw) -replace '__HOSTNAME__', $Name
Write-DistroFile -DistroName $distro -Path '/etc/wsl.conf' -Content $wslConf

# wsl.conf is read at boot, so the instance must be restarted for automount and
# interop to actually be disabled.
& wsl.exe --terminate $distro | Out-Null
Write-Host '  isolation  automount off, interop off, systemd on' -ForegroundColor Gray

# Seed the workspace. Done as a single login shell so nvm and PATH are present.
$seed = @'
set -e

# The base image carries empty /mnt/c, /mnt/d ... directories, created by WSL
# in the build distro where automount is enabled. Nothing is mounted on them
# here - automount is off - but leaving them makes it look like the Windows
# drives are exposed, which is exactly the thing this setup must be
# unambiguous about. /mnt/wsl and /mnt/wslg are WSL's own and must stay.
sudo find /mnt -mindepth 1 -maxdepth 1 -type d -empty \
     -not -name wsl -not -name wslg -delete 2>/dev/null || true

# Refresh the onepassword skill from the host's copy. The base image ships one
# already, so a project is never without it - but an image is a snapshot, and
# without this an edit to the skill would not reach new projects until the next
# 25-minute `corral build`. Doing it at creation time makes the host copy
# authoritative and the rebuild optional.
#
# The relative symlinks are exactly the layout the `skills` CLI produces, so a
# hand-placed skill and an installed one are indistinguishable and a later
# `skills` run has nothing to trip over.
if [ -f /etc/agentdev/onepassword-SKILL.md ]; then
    mkdir -p "$HOME/.agents/skills/onepassword"
    cp /etc/agentdev/onepassword-SKILL.md "$HOME/.agents/skills/onepassword/SKILL.md"
    chmod 0644 "$HOME/.agents/skills/onepassword/SKILL.md"
    for pair in ".claude/skills:../.." ".codex/skills:../.." ".pi/agent/skills:../../.."; do
        dir="${pair%%:*}"; rel="${pair#*:}"
        mkdir -p "$HOME/$dir"
        ln -sfn "$rel/.agents/skills/onepassword" "$HOME/$dir/onepassword"
    done
fi

cd ~/workspace
if [ ! -d .git ]; then
    git init -q
    # Skill payloads are installed artifacts, like node_modules - the base
    # image provides them, so they do not belong in the project's history.
    # skills-lock.json is the manifest and is deliberately left tracked.
    cat > .gitignore <<'GITIGNORE'
node_modules/
.expo/
dist/
build/
*.log
.DS_Store

# Agent skill payloads. The skills CLI writes a copy into every targeted
# agent's directory as well as the shared .agents/ one, so all of them are
# ignored. skills-lock.json stays tracked - it is the manifest, and these are
# the artifacts, the same split as package-lock.json versus node_modules.
.agents/
.claude/skills/
.codex/skills/
.pi/skills/

# Local checklist of skills to install, not project content.
SKILLS.md
GITIGNORE
    cp /etc/agentdev/project-AGENTS.md AGENTS.md 2>/dev/null || true

    # Register this project with firstmate. Its projects/ directory is
    # gitignored upstream, so the symlink leaves that repo clean. The hostname
    # is the project name, set in /etc/wsl.conf.
    if [ -d "$HOME/firstmate" ]; then
        mkdir -p "$HOME/firstmate/projects"
        ln -sfn "$HOME/workspace" "$HOME/firstmate/projects/$(hostname)"
    fi
    # Skills are installed by hand, per project. This is the checklist of what
    # to run; it is gitignored, being a local reminder rather than project
    # content.
    cp /etc/agentdev/project-SKILLS.md SKILLS.md 2>/dev/null || true

    git add -A
    git -c user.name='Agent Workspace' -c user.email='noreply@localhost' \
        commit -q -m 'Initial commit: project scaffold'
fi
'@
foreach ($template in 'project-AGENTS.md', 'project-SKILLS.md') {
    Write-DistroFile -DistroName $distro -Path "/etc/agentdev/$template" `
                     -Content (Get-Content (Join-Path $AgentDev.Provision $template) -Raw)
}

# Staged for the seed script above to install. Sourced from the dotfiles tree so
# the host copy is authoritative: editing the skill reaches the next new project
# without a base-image rebuild.
$skillSource = Join-Path $AgentDev.Dotfiles 'wsl\.agents\skills\onepassword\SKILL.md'
if (Test-Path $skillSource) {
    Write-DistroFile -DistroName $distro -Path '/etc/agentdev/onepassword-SKILL.md' `
                     -Content (Get-Content $skillSource -Raw)
} else {
    Write-Warning "No onepassword skill at $skillSource - the project will use the base image's copy."
}
Invoke-InDistro -DistroName $distro -Command $seed | Out-Null
Write-Host '  workspace  ~/workspace initialised with git' -ForegroundColor Gray
Write-Host '  skills     onepassword installed; the rest are in SKILLS.md' -ForegroundColor Gray

Write-Host ''
# Deliberately not advertising \\wsl.localhost - the isolation settings stop WSL
# serving the filesystem to Windows, so that path does not resolve. Printing it
# would send people to a dead end on every project they create.
Write-Host "  VS Code:   code --remote wsl+$distro /home/dev/workspace" -ForegroundColor DarkGray
Write-Host "  Copy a file in:" -ForegroundColor DarkGray
Write-Host "    cmd /c `"wsl.exe -d $distro -u dev -- bash -c `"`"cat > /home/dev/workspace/f.zip`"`" < `"`"C:\path\f.zip`"`"`"" -ForegroundColor DarkGray
Write-Host ''

if ($NoLaunch) {
    Write-Host "  Open it with: corral open $Name" -ForegroundColor Yellow
    return
}

& (Join-Path $PSScriptRoot 'Start-Project.ps1') -Name $Name
