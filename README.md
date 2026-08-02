# Agent Workspace

Isolated, disposable development environments for AI coding agents on Windows.
Each project gets its own WSL2 instance that can see that project and nothing
else on the machine.

## Usage

```powershell
# Once, or whenever you want to refresh the toolchain
C:\AgentDev\Build-BaseImage.ps1

# Create a project and open it
C:\AgentDev\New-Project.ps1 invoice-service

# Open it again on any later day (this is the everyday command)
C:\AgentDev\Start-Project.ps1 invoice-service

# Destroy it - backs up git history to Windows first
C:\AgentDev\Remove-Project.ps1 invoice-service
```

`Start-Project` opens WezTerm on the Windows host attached to the instance,
running Herdr in `~/workspace`, with `claude`, `codex` and `pi` on PATH.

## Why WSL2 rather than Windows Sandbox

The first implementation used Windows Sandbox. It worked, but re-provisioned an
entire toolchain on every launch:

| Phase | Windows Sandbox | WSL2 |
|---|---|---|
| Boot / start | ~40s | ~1-2s |
| Toolchain provisioning | ~11 min, **every launch** | once, into the base image |
| Project file I/O | VSMB mapped folder | native ext4 |
| Concurrent projects | **1** (hard limit) | many |

Windows Sandbox permits only one running instance, so two agents could never
work on two projects at the same time. That ceiling, plus paying twelve minutes
per launch to rebuild a byte-identical filesystem, is what motivated the move.

The Sandbox implementation is kept in `legacy\sandbox\` - working, but no
longer maintained.

## Isolation

Three settings in each instance's `/etc/wsl.conf` do the real work:

| Setting | Effect |
|---|---|
| `automount.enabled=false` | No `/mnt/c`. The agent cannot read your Windows drive, profile, SSH keys, or any other project. |
| `interop.enabled=false` | Windows executables cannot be launched from inside. Without this an agent could run `powershell.exe` and walk straight out. |
| `appendWindowsPath=false` | The Windows PATH is not inherited into the instance. |

Each project is a separate distro with its own root filesystem, so instances
cannot see each other's files. Docker runs *inside* each instance with its own
daemon - Docker Desktop's WSL integration is deliberately not used, because a
shared engine would let any agent reach every other project's containers and
mount the host filesystem with `-v /:/host`.

**Honest limitation:** all WSL2 distros share one utility VM and one kernel.
Isolation between instances is namespace-based, not a per-VM boundary like
Windows Sandbox had. It is a solid boundary against an agent doing something
careless or a dependency misbehaving; it is not a hard security boundary
against a determined kernel-level exploit.

## Where project files live

Inside the instance, on ext4, at `~/workspace`.

This is deliberate. Cross-OS file access through `drvfs` (`/mnt/c/...`) is
WSL's slowest path, and it is worst for exactly the workload here - Metro
watching thousands of files, and `node_modules` with tens of thousands of
small entries. Keeping the project on the Linux filesystem is Microsoft's own
recommendation and is the difference between a responsive and an unusable
React Native setup.

The consequence is that **the instance holds the only copy of your project**.
Mitigations:

- `Remove-Project.ps1` always writes a `git bundle` of the complete repository
  to `Projects\<name>-<timestamp>.bundle` before destroying anything, and
  refuses to proceed if that backup cannot be produced.
- Browse from Windows any time at `\\wsl.localhost\agentdev-<name>\home\dev\workspace`.
- Open in VS Code with `code --remote wsl+agentdev-<name> /home/dev/workspace`.

Commit often, and push to a remote from the host for anything you would be
upset to lose.

## Layout

```
C:\AgentDev\
├── Build-BaseImage.ps1   builds the golden image (slow, run once)
├── New-Project.ps1       clone base -> new instance -> open
├── Start-Project.ps1     open an existing instance (everyday command)
├── Remove-Project.ps1    safe teardown with git bundle backup
├── Common.ps1            paths, name validation, WSL helpers
├── Instances\            per-project VHDX (one directory per project)
├── Projects\             git bundle backups written by Remove-Project
├── Cache\base\           downloaded rootfs + exported base image
├── provision\
│   ├── provision.sh          runs once inside the base image build
│   ├── wsl.conf              per-instance isolation config
│   └── project-AGENTS.md     seeded into each new project
├── Dotfiles\
│   ├── AGENTS.md         single source of truth for agent instructions
│   ├── wsl\              mirrors the Linux home directory
│   └── windows\          used by the legacy Sandbox path
└── legacy\sandbox\       Windows Sandbox implementation (unmaintained)
```

`Dotfiles\wsl\` mirrors `$HOME`, so provisioning deploys it with one recursive
copy. To add a dotfile, drop it at the path it should occupy in the home
directory - no script change needed.

## One AGENTS.md, three agents

`Dotfiles\AGENTS.md` is the only place your agent instructions live. The base
image build copies it to every agent's global instruction path:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.pi/agent/AGENTS.md`

The legacy Sandbox path reads the same file. Projects additionally get their
own `AGENTS.md` describing the instance environment.

## What the base image contains

Ubuntu 24.04, plus: git, ripgrep, fd, fzf, neovim, starship, jq, build
essentials, Python 3, Node via `nvm` (LTS + corepack), Docker engine, Herdr,
and the `claude`, `codex` and `pi` agents.

Android SDK and JDK are deliberately **not** included - they would add roughly
8-10 GB to every project. Expo cloud builds and Expo Go need none of it. Add
them to a specific instance when a project genuinely needs local Android
builds.

## Expo and networking

`~\.wslconfig` sets `networkingMode=mirrored`, so instances share the host's
network interfaces and a phone on the same Wi-Fi can reach Metro directly.
Under WSL's default NAT mode the dev server sits behind a virtual switch and is
unreachable from the LAN.

Note that `.wslconfig` is global - it applies to your existing `Ubuntu` and
`docker-desktop` distros too.

Start Metro as usual with `npx expo start`.

## Requirements

WSL2. Verify with `wsl --version`; update with `wsl --update` (2.7+ recommended
for reliable mirrored networking).
