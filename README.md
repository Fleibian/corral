# Agent Workspace

Isolated, disposable development environments for AI coding agents on Windows.
Each project gets its own WSL2 instance that can see that project and nothing
else on the machine.

## When to use this, and when not to

Corral buys containment. That is worth paying for when code might do something
you did not ask for, and not worth paying for otherwise.

| | |
|---|---|
| **Use corral** | untrusted or unfamiliar dependencies, throwaway experiments, anything you would rather run behind a wall than trust |
| **Use Windows natively** | mobile and app development - see [Templapp](https://github.com/Fleibian/Templapp) |

The split is not preference. Three things make an instance the wrong home for
an app project, all of them measured rather than assumed:

- **The Android emulator runs under nested virtualisation** inside an instance
  and says so itself: *"not recommended... typically the performance is not
  quite good"*. Natively it uses WHPX with host GPU passthrough.
- **Windows cannot read a project inside an instance.** The same `wsl.conf`
  that disables automount and interop also stops WSL serving the filesystem, so
  `\\wsl.localhost\agentdev-<name>\` does not resolve and no host tooling -
  Android Studio, a profiler, a device manager - can reach the code.
- **The host toolchain gets duplicated, worse.** A machine with Android Studio
  and its SDK already installed cannot share any of it with an instance.

What you give up on Windows is real: permission rules are pattern matching, not
a sandbox, and they will not stop a postinstall script running with your user
account. That is precisely the case corral still exists for.

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
        └── .agents\skills\onepassword\   the secrets skill; deployed to each new
                                          project by New-Project.ps1, so edits
                                          need no base-image rebuild
```

`Dotfiles\wsl\` mirrors `$HOME`, so provisioning deploys it with one recursive
copy. To add a dotfile, drop it at the path it should occupy in the home
directory - no script change needed, but rebuild the base image so new
instances pick it up.

Currently shipped: `.bashrc`, `.gitconfig`, `.config/nvim/`,
`.config/starship.toml`, `.config/herdr/config.toml` (Herdr keybindings - that
is where Herdr looks on Linux, unlike `%APPDATA%\herdr\` on Windows), and
`.agents/skills/onepassword/` (the [secrets](#secrets) skill, symlinked into all
three agents by `provision.sh`).

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
| **Coding agents** | `claude`, `codex`, `pi`, plus `bubblewrap` for Codex's sandbox |
| **Session** | `herdr` multiplexer with your keybindings; WezTerm runs on the Windows host and attaches |
| **Editor** | `nvim`, with your Neovim config and its plugin lockfile; `y` yanks straight to the Windows clipboard |
| **Search** | `ripgrep`, `fd`, `fzf` |
| **Shell** | `bash` with a `starship` prompt, `ll`/`gs` aliases, `ff` fuzzy directory jump, `dockerup` |
| **Version control** | `git`, `gh` (GitHub CLI, for pushing) |
| **Secrets** | `op-env` injects a 1Password Environment into a command; agents use secrets without seeing values - see [Secrets](#secrets) |
| **Android** | `android-setup` installs the SDK and a KVM-accelerated emulator into a project on demand - see [Android](#android-emulator-and-devices) |
| **Node** | `nvm` with the current LTS and `corepack`, so a project can pin its own version |
| **Containers** | Docker engine with `compose` and `buildx`, its own daemon per instance (`dockerup` starts it) |
| **Python** | `python3` with `venv` and `pip` |
| **Build** | `build-essential`, `pkg-config`, `jq`, `unzip`/`zip`/`xz` |
| **Network** | `iproute2`, `ping`, `dig` |
| **Parallel agents** | [firstmate](https://github.com/kunchenguid/firstmate) at `~/firstmate`, with this project registered under it |
| **Agent skills** | `onepassword` is shipped; the rest are not preinstalled - each project gets a `SKILLS.md` with the commands |
| **Config** | your `AGENTS.md` fanned out to all three agents, plus `.gitconfig`, `starship.toml`, `.bashrc`, `herdr/config.toml`, `.pi/agent`, `.claude/settings.json` |

The `dev` user has passwordless `sudo`, so anything missing is one
`sudo apt install` away - the instance is disposable, and installing into it is
expected rather than discouraged.

**Deliberately not included:** the Android SDK and a JDK. They would add roughly
8-10 GB to *every* project, and neither Expo Go nor EAS cloud builds need them.
Run `android-setup` in the one instance that genuinely does local Android
builds - see [Android](#android-emulator-and-devices).

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

**Prerequisites are already in the image**: herdr, `jq`, `python3`, `git`, `gh`,
and the three agent harnesses. `gh auth login` is still needed per instance
before its PR-shipping path works - see [Pushing to GitHub](#pushing-to-github).

The herdr installer always fetches the latest release, so the version moves with
each `corral build` - it is 0.8.0 as of the most recent one, up from the 0.7.5
that firstmate documents as its verified protocol-14 backend. Nothing has
misbehaved, but if a firstmate crew ever fails to spawn panes, that gap is the
first thing to suspect, and `FM_BACKEND=tmux` switches to firstmate's reference
path without installing anything.

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

### Claude configuration

`Dotfiles/wsl/.claude/settings.json` comes from the same
[dotfiles](https://github.com/kunchenguid/dotfiles): the `dark-ansi` theme and a
status line showing the model and how much of the context window is used.

The status line is a shell command reading Claude's JSON payload from stdin, so
it depends on `jq` - which is in the base image. If a Claude release stops
sending `context_window.used_percentage`, the `// empty` fallback drops the
percentage and keeps the model name rather than breaking the line.

This file is settings only. Credentials, sessions and trust decisions stay local
to each instance, and `CLAUDE.md` is written separately from your one
`AGENTS.md` - see [One AGENTS.md, three agents](#one-agentsmd-three-agents).

### Pi configuration

`Dotfiles/wsl/.pi/agent` carries the pi setup from
[kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), described in
[Kun's pi agent config](https://blog.kunchenguid.com/p/kuns-pi-agent-config).
It deploys with the rest of the dotfiles, so every project gets it.

| | |
|---|---|
| `settings.json` | `rose-pine-moon` theme, hidden thinking blocks, quiet startup, `steeringMode`/`followUpMode` set to `all`, and four pinned packages |
| `models.json` | pins the `openai-codex` `gpt-5.6-*` context windows to 272k so compaction triggers before a surprise bill |
| `themes/rose-pine-moon.json` | the colour scheme |
| `extensions/terminal-status-title.js` | terminal title shows a spinner while pi works, then a completion mark |
| `extensions/calm/` | `/calm` toggles a conversation-only view - hides collapsed thinking and built-in tool shells, replaces the working row with an animated boat. Off by default, presentation only |

The four pinned packages are third-party and run with your full user
permissions:

- `npm:pi-web-access@0.14.0` - stock pi cannot search or browse the web
- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - fast mode for GPT models
- `npm:pi-mcp-extension@1.5.0` - lets pi connect to MCP servers, which it cannot
  do out of the box. Claude and Codex already speak MCP natively. Note this does
  **not** provide 1Password access - see [Secrets](#secrets) for why
- `git:github.com/algal/pi-openai-server-compaction@c6d5930` - **experimental**;
  sends compaction and continuity data to OpenAI

They are pinned to exact versions and one exact commit, so pi will not move them
on its own. Changing a pin is a deliberate edit to `settings.json`, and the
isolated disposable instance is a large part of why running them is reasonable
here. To drop one, remove it from that file and rebuild.

`corral build` installs all four into the base image rather than leaving pi to
fetch them the first time it runs in each project. Pi's own runtime state -
authentication, sessions, trust decisions - stays local to each instance and is
not part of this config.

Upstream verifies against pi 0.82.0; the base image currently ships 0.83.0. The
API seams Calm patches are all still present, and if a future pi removes one,
Calm logs a diagnostic and disables only that adapter. Run `/reload` after
editing a local extension.

### Agent skills

With one exception, skills are **not** installed automatically. Every new project
gets a `SKILLS.md` in its workspace listing what to install and the commands to
run:

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

The exception is `onepassword`, which every project gets automatically. The rule
above is about optional, network-fetched, per-project picks; that skill is local,
adds no round-trip, and describes how this instance handles secrets - the same
category as `AGENTS.md`. `New-Project.ps1` deploys it from the host at creation,
so editing it reaches new projects without a rebuild. See [Secrets](#secrets).

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
- Open in VS Code with `code --remote wsl+agentdev-<name> /home/dev/workspace`.

**`\\wsl.localhost\agentdev-<name>\` does not work**, even while the instance is
running. The same `wsl.conf` that provides the isolation also stops WSL serving
the instance's filesystem to Windows - `\\wsl.localhost\Ubuntu` resolves, an
`agentdev-` instance does not. This was tested, not assumed. It is a fair trade:
the share would be a path back into an instance that is meant to be sealed.

### Moving files in and out

Windows cannot browse the instance, and the instance cannot see `C:\` - but
`wsl.exe` bridges the two from the Windows side, which is the direction that
stays safe. Copy a file **in**:

```powershell
cmd /c "wsl.exe -d agentdev-<name> -u dev -- bash -c ""cat > /home/dev/workspace/file.zip"" < ""C:\path\to\file.zip"""
```

and back **out**:

```powershell
cmd /c "wsl.exe -d agentdev-<name> -u dev -- bash -c ""cat /home/dev/workspace/file.zip"" > ""C:\path\to\file.zip"""
```

The `cmd /c` wrapper is not decoration - PowerShell has no input redirection
operator, so `<` has to come from `cmd`. This streams byte-for-byte with no
base64 inflation and no size ceiling; a transferred archive hashes identically on
both sides and arrives owned by `dev`. For a directory, pipe a tar instead of
copying file by file.

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

## Secrets

Agents here can **use** every secret a project is entitled to, and **read** none
of them. Values are injected into the process that needs them and never pass
through the agent's context.

```bash
op-env -- npm run dev      # runs with the project's 1Password Environment loaded
op-env --names             # STRIPE_SECRET_KEY, DATABASE_URL, ...  (names only)
op-env --status            # which Environment this project is wired to
```

There is no `op://` reference file to maintain and nothing secret in the repo.
The unit of access is a **1Password Environment** - a named set of environment
variables you manage in the 1Password app.

### How it works

`op-env` re-enters as root just long enough for `op run` to resolve the
Environment, then drops back to the agent's own uid to exec the command. The
command lands with the variables in its environment and **without** the token
that fetched them:

```
op-env -- npm run dev
  └─ sudo → op run --environment <id> --      (root; reads root-owned token)
       └─ setpriv --reuid=dev → env -u OP_SERVICE_ACCOUNT_TOKEN
            └─ npm run dev                    (uid dev; secrets yes, token no)
```

The token lives at `/etc/agentdev/op/token`, mode `0400`, owned by root. It is
never in a shell environment, never in the agent's home directory, and stripped
from the child process. `op run` stays the parent, so its output masking still
applies - a secret echoed by the command comes out as
`<concealed by 1Password>`.

Verified in a live instance: the child runs as `dev`, keeps its `docker` group,
sees the injected variables, and gets `Permission denied` on the token file.

**What this is and is not.** It removes the entire `op read` surface and every
accidental leak - an agent that never receives a value cannot print one, log
one, or commit one. It is *not* a boundary that survives an adversarial agent:
the `dev` user has passwordless `sudo`, so a deliberate `sudo cat` of the token
still works. That is the same tradeoff already documented under
[Isolation](#isolation), where the agent is effectively root.

To make it absolute, replace the blanket rule in `provision.sh` with an
allowlist that excludes the token path:

```sh
# instead of:  dev ALL=(ALL) NOPASSWD:ALL
dev ALL=(root) NOPASSWD: /usr/local/libexec/op-env-run, \
                         /usr/local/libexec/op-store-token, \
                         /usr/bin/apt-get, /bin/systemctl start docker
```

The cost is that anything needing unanticipated root access fails until you
extend the list, which is why it is not the default.

### Why not the 1Password MCP server

Reasonable first instinct - an MCP server that never returns values is exactly
the right shape, and 1Password ships one. **It cannot work here**, and the
reason is worth recording so it is not re-litigated:

- It is **not part of the CLI**. `op mcp-server` does not exist in stable
  (2.38.1) or beta (2.38.2-beta.01) - both binaries were checked directly.
- It is a separate `1password-mcp` binary **supplied by the 1Password desktop
  app**, switched on at Settings > Labs, and every call needs an approval prompt
  in that app. With `interop.enabled=false` and no `/mnt/c`, an instance has no
  route to it.
- Bridging it from the host would not help. Its "run with credentials" tool
  injects into a **Windows** process; the project's app runs in Linux.

Something inside the instance has to place the secret into a Linux process, and
`op` is the only thing that can. `op-env` reproduces the property that made the
MCP server attractive - values never reach the agent - using the piece that
actually runs here.

`pi-mcp-extension` is installed regardless, so pi can use other MCP servers;
Claude and Codex support MCP natively.

### The beta channel is required

`provision.sh` pulls `1password-cli` from the **beta** apt channel, not stable.
1Password Environments - `op environment read` and `op run --environment` - are
absent from stable 2.38.1 and present in beta 2.38.2-beta.01. Since Environments
are the unit of access, beta is not optional. Pinning back to `stable main` in
`provision.sh` removes the feature entirely.

### Setting up a project

Once, in the 1Password app on Windows:

1. **Developer > View Environments > New environment**, and add the project's
   variables (or import an existing `.env`).
2. **Manage environment > Copy environment ID.**
3. Create a service account with access to it:

```powershell
op service-account create corral-invoice-service --vault "corral-invoice-service:read_items"
```

Service accounts **cannot** be granted the built-in Personal, Private, Employee
or default Shared vault, so a purpose-made vault per project is required rather
than merely tidy. The token prints **once** - save it in 1Password.

Then, inside the instance:

```bash
op-login            # asks for the Environment ID, then the token (hidden)
```

`op-login` never echoes the token and never passes it as an argument, so it
stays out of `~/.bash_history` and `/proc/*/cmdline`; it is piped straight to a
root helper that verifies it against the Environment before storing. A bad paste
fails immediately rather than breaking the agent's first command.

**Rotating a token breaks every instance holding the old one.** Deleting or
replacing a service account makes the stored token return
`(403) Service Account Deleted`, and `op-env` stops working until `op-login` is
run again with the new token. There is no way for an agent to recover from this
on its own, which is why the skill tells it to ask rather than improvise.

Pasting the token **is** the act of choosing which environment a project gets -
scope is enforced by 1Password on the server, not by anything in the instance an
agent could edit. Like `gh auth login`, it is once per instance, and rebuilding
the base image does not carry tokens into it.

### What the agents know

Every instance ships a `onepassword` skill, linked into all three agents' skill
directories from one payload at `~/.agents/skills/onepassword/`. It covers
`op-env`, states plainly that plain `op` will fail and that this is intended
rather than a fault to fix, and rules out reading the token with `sudo`.

It also tells an agent that cannot reach a secret to **ask you to run
`op-login`** - the same way it is told to ask you to run `gh auth login` - rather
than hardcoding a credential or quietly disabling the code path that needed it.

Edit it at `Dotfiles\wsl\.agents\skills\onepassword\SKILL.md`. **The next
`corral new` picks it up - no base-image rebuild required.** `New-Project.ps1`
copies the host's version into each project at creation and relinks it for all
three agents, so the host copy is authoritative and the image copy is only a
fallback for a project created without it.

That is deliberate. The image is a snapshot, so a skill baked into it goes stale
the moment you edit the source, and a 25-minute rebuild to correct a sentence is
a poor trade. Deploying at creation time keeps the skill zero-setup - it is
present the moment a project opens, with nothing to install by hand - while
making edits land immediately. Existing projects keep the copy they were created
with, as with every other template here.

One trap worth recording, because it cost a debugging round: **the YAML
frontmatter is parsed strictly by some agents and leniently by others.** A bare
`Triggers:` inside the unquoted `description` value made pi refuse the skill with
`Nested mappings are not allowed in compact mappings`, while other agents
accepted it. The description is now quoted and contains no bare `: `. If you
edit it, keep it that way.


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

## Android: emulator and devices

```bash
android-setup            # once per project that needs Android
emulator -avd <name> &   # window appears on the Windows desktop
npx expo run:android
```

`android-setup` installs JDK 17, the Android SDK, platform-tools, the emulator
and an API 36 system image, then creates an AVD named after the project and
verifies KVM is really in use. `android-setup --check` reports what is present
without installing. It takes a few minutes and about 6 GB.

**The emulator runs inside the instance, not on Windows.** WSL2 exposes
`/dev/kvm` for hardware acceleration and WSLg puts the emulator window on the
Windows desktop, so source, Metro, `adb` and the device all stay on the same
side of the boundary. Measured in a real instance: `KVM (version 12) is
installed and usable`, and a Pixel 7 API 36 AVD cold-booting in **45 seconds**.
Software emulation takes minutes, so the acceleration is genuine.

The alternative - Android Studio and its emulator on Windows, connected with
`adb reverse` - is the usual WSL advice and is *worse here*, for two reasons
specific to this setup:

- Windows cannot read the project at all, since the isolation settings block
  `\\wsl.localhost`. Anything that needs repo files (Maestro flows, Gradle,
  `expo run:android`) cannot run on the Windows side.
- Windows resolves `localhost` to IPv6 `::1` first, and Metro binds IPv4 only,
  so `http://localhost:8081` from Windows **hangs** rather than failing. This is
  the same trap as the OAuth callback above. Verified: `127.0.0.1:8081` returns
  in 111 ms, `localhost:8081` times out.

Keeping the emulator in-instance sidesteps both.

**The SDK is deliberately not in the base image.** At ~6-10 GB it would be
carried by every project to benefit the few that build Android - the same
reasoning as [What's included](#whats-included). What the image *does* carry is
`android-setup` (a few KB), `kvm` group membership, and a conditional block in
`.bashrc` that sets `ANDROID_HOME` and PATH only when an SDK is actually
present, above the interactive guard so agent-run Gradle works.

**Physical devices.** Use wireless debugging rather than USB - WSL2 has no USB
passthrough without `usbipd-win`, but mirrored networking puts the instance on
your LAN, so `adb pair` and `adb connect <phone-ip>:5555` work from inside the
instance with no Windows involvement.

**iOS cannot be run locally at all.** Neither Windows nor WSL can host the iOS
Simulator, and building for iOS needs macOS. Use an EAS development build on a
registered iPhone, and EAS Workflows or a macOS runner for automation.

## Logging an agent in

Interop is off, so an agent cannot open a Windows browser. It prints the OAuth
URL instead; you open it on Windows, authorise, and the browser is redirected to
a callback the agent is listening for inside the instance.

**That redirect will hang, and the URL is misleading about why.** It points at
`http://localhost:<port>/callback?...`. Windows resolves `localhost` to the IPv6
`::1` before `127.0.0.1`, and the agent's callback server binds IPv4 only, so the
browser connects to nothing.

Edit the address bar, replace `localhost` with `127.0.0.1`, and press enter:

```
http://localhost:53692/callback?code=...     hangs
http://127.0.0.1:53692/callback?code=...     works
```

Mirrored networking already bridges the loopback - a listener inside an instance
answers on the host's `127.0.0.1` at the same port. Only the name resolution is
wrong. Codes are single-use and short-lived, so if one expires, start the login
again and swap the host on the fresh URL.

`claude setup-token` avoids the problem entirely: it redirects to
`platform.claude.com` rather than a local port, shows a code in the browser, and
you paste that into the terminal. Nothing has to reach back into the instance.

`gh auth login` is unaffected - it uses the device-code flow, where you type a
code at `github.com/login/device` and no callback comes back to you.

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
