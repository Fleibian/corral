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
running Herdr in `~/workspace`, with `claude`, `codex` and `pi` on PATH. The
window is titled with the project name, so several open projects stay tellable
apart on the taskbar.

Your personal `~/.wezterm.lua` is never modified. `Start-Project` points
`WEZTERM_CONFIG_FILE` at `provision\wezterm.lua`, which inherits your config
(theme, font, opacity) and only adds the title handling - every other terminal
you open behaves exactly as before.

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

### What holds, and what does not

**Isolation from the host is solid.** With `automount` and `interop` off there
is no `/mnt/c`, no way to launch Windows binaries, and no path to your profile,
Documents or SSH keys. The host filesystem is not a block device inside the WSL
VM, so there is nothing to reach even as root. This has been verified directly.

**Isolation between projects is not absolute.** All WSL2 distros share a single
utility VM, and every instance's virtual disk is attached to it as a block
device visible to all of them. Ordinary filesystem access is properly
contained - one project cannot browse, list, or open another's files, and a
non-root user cannot read the raw devices at all. But **root inside any
instance can read every other instance's disk directly**, bypassing the
filesystem entirely:

```bash
sudo debugfs -R "cat /home/dev/workspace/secret.txt" /dev/sde   # succeeds
```

This was tested, not assumed. It holds even after the other instance is
terminated, because WSL leaves the disk attached for the lifetime of the VM.

The agent has passwordless `sudo` and is in the `docker` group, so in practice
the agent is root and this path is open to it. Removing `sudo` closes it - a
non-root `dev` user genuinely cannot read the devices - but also removes the
ability to install packages or use Docker.

**So the accurate threat model is:** this reliably stops an agent from wandering
into another project or the host through normal means, and it stops a
misbehaving dependency. It does not stop a deliberately malicious root-capable
process from reading a sibling project's disk.

**This is an accepted tradeoff, not an oversight.** Keeping passwordless `sudo`
and the `docker` group is a deliberate choice: agents need to install packages,
and per-instance Docker is a requirement. Removing them would close the gap but
would also remove both capabilities. If a future project genuinely must not be
reachable from the others, the options are to run it alone with a
`wsl --shutdown` between switches, or to put it on a separate machine or VM.

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

Commit often, and push to a remote for anything you would be upset to lose.

## Pushing to GitHub

Host SSH keys are never exposed to an instance. Each instance authenticates
itself instead, once, with the GitHub CLI:

```bash
gh auth login          # HTTPS; browser or token both work
gh auth setup-git      # makes git push use that token
git push
```

The token lives only in that instance. A project cannot reach your
machine-wide credentials, and revoking one project's access leaves every other
project untouched. `gh repo create` also works for publishing a new project.

The project `AGENTS.md` tells agents to commit freely but to leave pushing to
you.

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
image build copies it to every agent's global instruction path **inside the
instance**:

- `/home/dev/.claude/CLAUDE.md`
- `/home/dev/.codex/AGENTS.md`
- `/home/dev/.pi/agent/AGENTS.md`

These are copies deployed into the image. An agent reads its policy from inside
its own instance; your host's `C:\Users\<you>\.claude\` is never touched and is
not reachable from an instance at all. Editing `Dotfiles\AGENTS.md` changes
what *future* instances receive - rebuild the base image to propagate it, since
existing projects keep the copy they were created with.

The legacy Sandbox path reads the same source file. Projects additionally get
their own `AGENTS.md` describing the instance environment.

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

## Known rough edges

- **Agent login is once per project**, not once per session. The base image
  carries no credentials, so the first `claude` in a new instance prompts you.
  It then persists for the life of that instance.
- **Instances are cloned from the base image at creation time.** Rebuilding the
  base image does not update existing projects; they keep the toolchain they
  were created with.

## Requirements

WSL2. Verify with `wsl --version`; update with `wsl --update` (2.7+ recommended
for reliable mirrored networking).
