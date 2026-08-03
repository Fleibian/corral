# Agent Workspace

Isolated, disposable development environments for AI coding agents on Windows.
Each project gets its own WSL2 instance that can see that project and nothing
else on the machine.

## Usage

```powershell
corral build                      # once, or to refresh the toolchain
corral new invoice-service        # create a project and open it
corral open invoice-service       # open it again (the everyday command)
corral ls                         # see what you have
corral rm invoice-service         # destroy it, bundling git history first
corral rm scratch-test -NoBackup  # destroy a throwaway, keeping nothing
corral help
```

**Project names tab-complete.** `corral open <TAB>` cycles the projects you
actually have, so nothing needs remembering or retyping. `corral <TAB>` lists
the commands, and after a project name it offers that command's switches.

**Forgot the name?** Run `corral open` or `corral rm` with no project and you
get the list instead of a prompt:

```
Name  State   DiskGB
----  -----   ------
alpha stopped   3.26
beta  running   3.26

  Which one?   corral open <name>
  Tab completes the name.
```

Short forms work where you'd guess: `create`/`n` for `new`, `start`/`o` for
`open`, `list`/`l` for `ls`, `remove`/`delete` for `rm`, `rebuild` for `build`.
Bare `corral` lists your projects.

`Start-Project` opens WezTerm on the Windows host attached to the instance,
running Herdr in `~/workspace`, with `claude`, `codex` and `pi` on PATH. The
window is titled with the project name, so several open projects stay tellable
apart on the taskbar.

Your personal `~/.wezterm.lua` is never modified. `Start-Project` points
`WEZTERM_CONFIG_FILE` at `provision\wezterm.lua`, which inherits your config
(theme, font, opacity) and only adds the title handling - every other terminal
you open behaves exactly as before.

### Under the hood

`corral` is a thin dispatcher - the `.ps1` scripts in the repository root are
the implementation and stay callable directly, which is useful for scripting or
for reading `Get-Help`:

| Command | Script |
|---|---|
| `corral new` | `New-Project.ps1` |
| `corral open` | `Start-Project.ps1` |
| `corral ls` | `Get-Project.ps1` |
| `corral rm` | `Remove-Project.ps1` |
| `corral build` | `Build-BaseImage.ps1` |

Switches pass straight through, so `corral rm x -NoBackup -Force` and
`.\Remove-Project.ps1 x -NoBackup -Force` are the same call. `-WhatIf` works on
`corral rm` and writes nothing at all.

The module lives in `Corral\` and is loaded by one line in your PowerShell
profile:

```powershell
Import-Module 'C:\AgentDev\Corral' -ErrorAction SilentlyContinue
```

## Layout

```
C:\AgentDev\
├── Build-BaseImage.ps1   builds the golden image (slow, run once)
├── New-Project.ps1       clone base -> new instance -> open
├── Start-Project.ps1     open an existing instance (everyday command)
├── Get-Project.ps1       list projects with state, disk usage, git status
├── Remove-Project.ps1    teardown; bundles history unless -NoBackup
├── Common.ps1            paths, name validation, WSL helpers
├── Corral\               the `corral` command (module, loaded from your profile)
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
directory - no script change needed, but rebuild the base image so new
instances pick it up.

Currently shipped: `.bashrc`, `.gitconfig`, `.config/nvim/`,
`.config/starship.toml`, and `.config/herdr/config.toml` (Herdr keybindings -
that is where Herdr looks on Linux, unlike `%APPDATA%\herdr\` on Windows).

### Clipboard

Your Neovim config sets `clipboard = unnamedplus`, so plain `y` yanks to the
system clipboard and `p` pastes from it - shared with Windows in both
directions.

That needs a clipboard provider, which the image supplies via `wl-clipboard`.
WSLg exposes a Wayland socket and bridges its clipboard to Windows, and this
works even with interop disabled, so no `win32yank` and no `/mnt/c` are
involved. `xclip` is installed as the X11 fallback. Without a provider Neovim
silently falls back to its own registers and yanks appear to do nothing.

| | |
|---|---|
| Yank from Neovim to the Windows clipboard | `y` |
| Paste into a herdr pane | **`Ctrl+Shift+V`** |
| Copy from a herdr pane | select with the mouse - herdr's `copy_on_select` is on by default |

**`Ctrl+V` does not paste**, even though WezTerm lists `CTRL V` as
`PasteFrom(Clipboard)`. herdr is a TUI and captures `ctrl+letter` chords for its
own bindings, so it swallows the key first - tested, not assumed. This is left
alone deliberately: binding it in `provision\wezterm.lua` would work, but
WezTerm would then intercept `Ctrl+V` before Neovim ever saw it, costing
blockwise visual mode.

## What's included

Every project starts from the same Ubuntu 24.04 base image, so all of this is
present the moment the instance opens - nothing installs on first use.

| | |
|---|---|
| **Coding agents** | `claude`, `codex`, `pi` |
| **Session** | `herdr` multiplexer with your keybindings; WezTerm runs on the Windows host and attaches |
| **Editor** | `nvim`, with your Neovim config and its plugin lockfile; `y` yanks straight to the Windows clipboard |
| **Search** | `ripgrep`, `fd`, `fzf` |
| **Shell** | `bash` with a `starship` prompt, `ll`/`gs` aliases, `ff` fuzzy directory jump, `dockerup` |
| **Version control** | `git`, `gh` (GitHub CLI, for pushing) |
| **Node** | `nvm` with the current LTS and `corepack`, so a project can pin its own version |
| **Containers** | Docker engine with `compose` and `buildx`, its own daemon per instance (`dockerup` starts it) |
| **Python** | `python3` with `venv` and `pip` |
| **Build** | `build-essential`, `pkg-config`, `jq`, `unzip`/`zip`/`xz` |
| **Network** | `iproute2`, `ping`, `dig` |
| **Parallel agents** | [firstmate](https://github.com/kunchenguid/firstmate) at `~/firstmate`, with this project registered under it |
| **Agent skills** | not preinstalled - each project gets a `SKILLS.md` with the commands |
| **Config** | your `AGENTS.md` fanned out to all three agents, plus `.gitconfig`, `starship.toml`, `.bashrc`, `herdr/config.toml`, `.pi/agent` |

The `dev` user has passwordless `sudo`, so anything missing is one
`sudo apt install` away - the instance is disposable, and installing into it is
expected rather than discouraged.

**Deliberately not included:** the Android SDK and a JDK. They would add roughly
8-10 GB to *every* project, and neither Expo Go nor EAS cloud builds need them.
Add them to the one instance that genuinely does local Android builds.

Also absent by design: your SSH keys, your Windows PATH, and any access to the
host filesystem. See [Isolation](#isolation).

### Firstmate

[firstmate](https://github.com/kunchenguid/firstmate) is an agent distro: one
supervising agent runs a crew of workers in parallel, each in its own git
worktree. It is cloned into every instance at `~/firstmate`, and each project is
registered under it automatically.

```bash
fm        # cd to ~/firstmate and print how to launch
claude    # or codex / pi - start the crew from inside that directory
```

The unit of work is a **task**, not a project: the crew runs several tasks at
once against the same repo, each in its own git worktree, shipping PRs or
returning scout reports. One project per firstmate is ordinary usage.

Firstmate can also hold several clones under `projects/` and span them, but that
capability simply goes unused here - instances are isolated, so a firstmate in
one cannot reach another project.

**Prerequisites are already in the image**: herdr 0.7.5 (which firstmate lists
as a verified protocol-14 backend), `jq`, `python3`, `git`, `gh`, and the three
agent harnesses. `gh auth login` is still needed per instance before its
PR-shipping path works - see [Pushing to GitHub](#pushing-to-github).

**Backend**: firstmate drives a multiplexer to spawn its crew. `FM_BACKEND` is
deliberately left unset so it auto-detects - herdr in a normal session, and
correctly *not* herdr under `corral open <name> -Shell`. `tmux` is installed but
idle; if the herdr backend misbehaves, `FM_BACKEND=tmux` switches to firstmate's
verified reference path without needing to install anything inside an isolated
instance.

`corral build` refreshes firstmate to the latest `main`. Existing projects keep
the revision they were created with.

`firstmate` is a reserved project name - firstmate labels its own primary home
that, and a colliding label refuses new spawns.

### Pi configuration

`Dotfiles/wsl/.pi/agent` carries the pi setup from
[kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), described in
[Kun's pi agent config](https://blog.kunchenguid.com/p/kuns-pi-agent-config).
It deploys with the rest of the dotfiles, so every project gets it.

| | |
|---|---|
| `settings.json` | `rose-pine-moon` theme, hidden thinking blocks, quiet startup, `steeringMode`/`followUpMode` set to `all`, and three pinned packages |
| `models.json` | pins the `openai-codex` `gpt-5.6-*` context windows to 272k so compaction triggers before a surprise bill |
| `themes/rose-pine-moon.json` | the colour scheme |
| `extensions/terminal-status-title.js` | terminal title shows a spinner while pi works, then a completion mark |
| `extensions/calm/` | `/calm` toggles a conversation-only view - hides collapsed thinking and built-in tool shells, replaces the working row with an animated boat. Off by default, presentation only |

The three pinned packages are third-party and run with your full user
permissions:

- `npm:pi-web-access@0.14.0` - stock pi cannot search or browse the web
- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - fast mode for GPT models
- `git:github.com/algal/pi-openai-server-compaction@c6d5930` - **experimental**;
  sends compaction and continuity data to OpenAI

They are pinned to exact versions and one exact commit, so pi will not move them
on its own. Changing a pin is a deliberate edit to `settings.json`, and the
isolated disposable instance is a large part of why running them is reasonable
here. To drop one, remove it from that file and rebuild.

`corral build` installs all three into the base image rather than leaving pi to
fetch them the first time it runs in each project. Pi's own runtime state -
authentication, sessions, trust decisions - stays local to each instance and is
not part of this config.

Upstream verifies against pi 0.82.0; the base image currently ships 0.83.0. The
API seams Calm patches are all still present, and if a future pi removes one,
Calm logs a diagnostic and disables only that adapter. Run `/reload` after
editing a local extension.

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
corral ls
```

```
Name            State   DiskGB
----            -----   ------
mobile-app      running   3.26
invoice-service stopped   3.26
```

Add `-Detailed` for git state:

```powershell
corral ls -Detailed
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
corral rm invoice-service

# Throwaway: destroy it and leave nothing behind
corral rm scratch-test -NoBackup

# Same, without the confirmation prompt
corral rm scratch-test -NoBackup -Force

# Show what would happen, changing nothing
corral rm scratch-test -WhatIf
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
