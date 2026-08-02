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

# See what you have
C:\AgentDev\Get-Project.ps1

# Destroy it - backs up git history to Windows first
C:\AgentDev\Remove-Project.ps1 invoice-service

# Destroy a throwaway - leaves nothing behind
C:\AgentDev\Remove-Project.ps1 scratch-test -NoBackup
```

`Start-Project` opens WezTerm on the Windows host attached to the instance,
running Herdr in `~/workspace`, with `claude`, `codex` and `pi` on PATH. The
window is titled with the project name, so several open projects stay tellable
apart on the taskbar.

Your personal `~/.wezterm.lua` is never modified. `Start-Project` points
`WEZTERM_CONFIG_FILE` at `provision\wezterm.lua`, which inherits your config
(theme, font, opacity) and only adds the title handling - every other terminal
you open behaves exactly as before.

## Layout

```
C:\AgentDev\
├── Build-BaseImage.ps1   builds the golden image (slow, run once)
├── New-Project.ps1       clone base -> new instance -> open
├── Start-Project.ps1     open an existing instance (everyday command)
├── Get-Project.ps1       list projects with state, disk usage, git status
├── Remove-Project.ps1    teardown; bundles history unless -NoBackup
├── Common.ps1            paths, name validation, WSL helpers
├── Instances\            per-project VHDX (one directory per project)
├── Projects\             git bundle backups written by Remove-Project
├── Cache\base\           downloaded rootfs + exported base image
├── provision\
│   ├── provision.sh          runs once inside the base image build
│   ├── wsl.conf              per-instance isolation config
│   ├── wezterm.lua           overlay config that titles project windows
│   ├── project-AGENTS.md     seeded into each new project
│   └── project-SKILLS.md     checklist of skills to install by hand
└── Dotfiles\
    ├── AGENTS.md         single source of truth for agent instructions
    └── wsl\              mirrors the Linux home directory
```

`Dotfiles\wsl\` mirrors `$HOME`, so provisioning deploys it with one recursive
copy. To add a dotfile, drop it at the path it should occupy in the home
directory - no script change needed.

## What's included

Every project starts from the same Ubuntu 24.04 base image, so all of this is
present the moment the instance opens - nothing installs on first use.

| | |
|---|---|
| **Coding agents** | `claude`, `codex`, `pi` |
| **Session** | `herdr` multiplexer; WezTerm runs on the Windows host and attaches |
| **Editor** | `nvim`, with your Neovim config and its plugin lockfile |
| **Search** | `ripgrep`, `fd`, `fzf` |
| **Shell** | `bash` with a `starship` prompt, `ll`/`gs` aliases, `ff` fuzzy directory jump, `dockerup` |
| **Version control** | `git`, `gh` (GitHub CLI, for pushing) |
| **Node** | `nvm` with the current LTS and `corepack`, so a project can pin its own version |
| **Containers** | Docker engine with `compose` and `buildx`, its own daemon per instance (`dockerup` starts it) |
| **Python** | `python3` with `venv` and `pip` |
| **Build** | `build-essential`, `pkg-config`, `jq`, `unzip`/`zip`/`xz` |
| **Network** | `iproute2`, `ping`, `dig` |
| **Agent skills** | not preinstalled - each project gets a `SKILLS.md` with the commands |
| **Config** | your `AGENTS.md` fanned out to all three agents, plus `.gitconfig`, `starship.toml`, `.bashrc` |

The `dev` user has passwordless `sudo`, so anything missing is one
`sudo apt install` away - the instance is disposable, and installing into it is
expected rather than discouraged.

**Deliberately not included:** the Android SDK and a JDK. They would add roughly
8-10 GB to *every* project, and neither Expo Go nor EAS cloud builds need them.
Add them to the one instance that genuinely does local Android builds.

Also absent by design: your SSH keys, your Windows PATH, and any access to the
host filesystem. See [Isolation](#isolation).

### Agent skills

Skills are **not** installed automatically. Every new project gets a
`SKILLS.md` in its workspace listing what to install and the commands to run:

```bash
npx skills add kunchenguid/chrome-devtools-axi --skill chrome-devtools-axi -g
npx skills add kunchenguid/lavish-axi --skill lavish
npx skills add kunchenguid/gh-axi --skill gh-axi -g
```

`-g` covers the whole instance, so it is a one-off; without it the skill is
project-scoped and needs running in each new project. `skills list` and
`skills list -g` show what is present.

This is a deliberate choice, not a limitation - automating it worked, but
installing by hand keeps project creation at ~40s with no network dependency,
and lets you pick skills per project.

To change the list, edit `provision\project-SKILLS.md`. New projects pick it
up; existing ones keep the copy they were created with.

`SKILLS.md` and the skill payloads (`.agents/`, `.claude/skills/`,
`.codex/skills/`, `.pi/skills/`) are gitignored, so nothing leaks into a
project's history. `skills-lock.json` stays tracked once you install
something - it is the manifest, the same split as `node_modules` versus
`package-lock.json`.

If you do script it, three things the CLI is particular about: `-y` is required
or it opens an interactive picker and hangs; agent names are repeated as
separate `-a` flags and the identifier is `claude-code`, not `claude`; and
several `-a` flags in one invocation reports success while installing for only
some of them, so install one agent at a time. `SKILLS.md` has a working loop.

## Seeing what you have

```powershell
C:\AgentDev\Get-Project.ps1
```

```
Name            State   DiskGB
----            -----   ------
mobile-app      running   3.26
invoice-service stopped   3.26
```

Add `-Detailed` for git state:

```powershell
C:\AgentDev\Get-Project.ps1 -Detailed
```

```
Name            State   DiskGB Branch Dirty
----            -----   ------ ------ -----
mobile-app      running   3.26 master     0
invoice-service stopped   3.26 master     0
```

`Dirty` is the number of uncommitted changes - worth checking before
`Remove-Project`, which refuses to destroy a project whose tree is dirty.
`-Detailed` is opt-in rather than the default because it has to *start* every
stopped instance in order to ask git, which the plain listing avoids.

Two things worth knowing:

- It lists only `agentdev-` distributions. Your own `Ubuntu` and
  `docker-desktop` never appear, and nothing here will ever touch them. The
  raw equivalent, `wsl -l -v`, mixes them in and shows the prefix.
- It emits objects, not text, so it pipes:
  `Get-Project.ps1 | Where-Object State -eq 'running'`.

The `DiskGB` column is worth watching. Every project is a full clone of the
~2.9 GB base image, so ten projects is roughly 30 GB. That is inherent to
giving each project its own instance.


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

- `Remove-Project.ps1` writes a `git bundle` of the complete repository to
  `Projects\<name>-<timestamp>.bundle` before destroying anything, and refuses
  to proceed if that backup cannot be produced. Opt out per project with
  `-NoBackup` - see below.
- Browse from Windows any time at `\\wsl.localhost\agentdev-<name>\home\dev\workspace`.
- Open in VS Code with `code --remote wsl+agentdev-<name> /home/dev/workspace`.

### Destroying a project

```powershell
# Default: bundle the history to Windows, then destroy
C:\AgentDev\Remove-Project.ps1 invoice-service

# Throwaway: destroy it and leave nothing behind
C:\AgentDev\Remove-Project.ps1 scratch-test -NoBackup

# Same, without the confirmation prompt
C:\AgentDev\Remove-Project.ps1 scratch-test -NoBackup -Force
```

Not every project is worth a bundle. Scratch and test instances would just
accumulate files in `Projects\` that you will never restore, so `-NoBackup`
destroys the instance and writes nothing to Windows at all.

Because that is irreversible, it tells you what you are about to lose and asks
first:

```
  'scratch-test' will be destroyed with no backup.
  losing    12 commit(s), 3 uncommitted change(s)
  note      no git remote is configured, so this history exists nowhere else
```

The remote note only appears when there is no git remote - if you have pushed
somewhere, the history is not actually gone and the warning would be noise.
`-Force` skips the prompt for scripted teardown, and `-WhatIf` shows what would
happen without touching anything.

Without `-NoBackup`, an uncommitted working tree still stops the removal
outright, since a bundle captures committed history only.

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

Projects additionally get their own `AGENTS.md` describing the instance
environment.

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
