# Windows Agent Workspace Blueprint

## Goal

Create a Windows-native development environment that feels as seamless
as working directly on Windows while isolating AI coding agents from the
rest of the machine.

The environment should provide:

-   Native Windows performance (no full Hyper-V VM workflow).
-   One command to create a new isolated project.
-   Persistent project files.
-   Disposable operating system state.
-   Reproducible developer tooling.
-   Shared personal configuration (Neovim, WezTerm, PowerShell, Git,
    Herdr, agent configs).
-   Isolation so an agent working on Project A cannot inspect Project B
    or the rest of the host.

------------------------------------------------------------------------

# High-Level Architecture

    Windows Host
    │
    ├── C:\AgentDev
    │   ├── Projects
    │   │   ├── project-a
    │   │   └── project-b
    │   │
    │   ├── Dotfiles
    │   │   ├── source      (fork of GitHub dotfiles)
    │   │   └── windows     (Windows adaptation)
    │   │
    │   └── Bootstrap
    │       └── bootstrap.ps1
    │
    └── Windows Sandbox
        ├── C:\Workspace  -> one project only
        ├── C:\Dotfiles   -> read-only
        ├── C:\Bootstrap  -> read-only
        ├── Herdr
        ├── Neovim
        └── AI agent

The important security rule is:

-   Never map `Projects`.
-   Only map one project directory.

That prevents an agent from walking to sibling projects.

------------------------------------------------------------------------

# Desired Workflow

The entire workflow should be:

``` powershell
New-Project invoice-service
```

The command should:

1.  Create a new project directory.
2.  Initialize Git.
3.  Generate a `.wsb` file.
4.  Launch Windows Sandbox.
5.  Mount only that project.
6.  Mount the Windows dotfiles read-only.
7.  Run a bootstrap script.
8.  Install or restore required tooling.
9.  Copy dotfiles into the sandbox profile.
10. Launch Herdr (or WezTerm) in the project.

After the sandbox closes:

-   project source persists
-   Git history persists
-   sandbox state disappears
-   Windows user profile disappears
-   temporary files disappear

------------------------------------------------------------------------

# Dotfiles

Use this repository as the starting point:

https://github.com/kunchenguid/dotfiles

Do **not** try to reproduce the Nix/macOS parts.

Instead reuse only portable configuration such as:

-   Neovim
-   WezTerm
-   Starship
-   AGENTS.md
-   Claude/Codex/OpenCode configuration

Create a Windows version of these dotfiles.

------------------------------------------------------------------------

# Herdr

Use Herdr as the terminal/session manager.

https://herdr.dev/

Bootstrap should install Herdr if missing and launch it inside the
project workspace.

------------------------------------------------------------------------

# Bootstrap Responsibilities

bootstrap.ps1 should:

-   install required developer tools
-   install Herdr
-   install Neovim
-   install Git
-   install ripgrep
-   install fd
-   install fzf
-   copy dotfiles into the sandbox user profile
-   place AGENTS.md into the project (if absent)
-   open the workspace

The bootstrap should be idempotent.

------------------------------------------------------------------------

# Security Goals

The agent should:

-   only see one project
-   not see sibling projects
-   not see the host user profile
-   not see Documents/Desktop
-   not access host SSH keys
-   not modify personal dotfiles

The canonical dotfiles should always be mounted read-only.

------------------------------------------------------------------------

# Future Improvements

After the basic workflow works:

1.  Persist package caches.
2.  Add language templates (Node, .NET, Rust, Python, PHP).
3.  Add agent installation profiles.
4.  Add portable tool bundles to reduce startup time.
5.  Investigate Windows Sandbox CLI for automation.
6.  Potentially investigate project-specific VHDX storage if it provides
    operational benefits.

------------------------------------------------------------------------

# Initial Deliverable

Implement a minimal working version that provides:

-   `New-Project.ps1`
-   `bootstrap.ps1`
-   Windows Sandbox configuration generation
-   Windows-adapted dotfiles
-   Herdr startup
-   Neovim configuration
-   Project isolation

Ignore advanced optimization until this baseline is working.
