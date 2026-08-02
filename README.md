# Windows Agent Workspace

A Windows-native development environment that isolates AI coding agents from
the rest of the machine. Each project gets a disposable Windows Sandbox that
can see that project and nothing else.

Implements `Windows_Agent_Workspace_Blueprint.md`.

## Usage

```powershell
# Create a project and launch its sandbox (once per project)
C:\AgentDev\New-Project.ps1 invoice-service

# Launch the sandbox again on any later day
C:\AgentDev\Start-Project.ps1 invoice-service
```

Inside the sandbox, WezTerm opens on `C:\Workspace` running Herdr, with
`claude`, `codex` and `pi` on PATH.

When you close the sandbox: the project source and its git history persist on
the host; everything else - the OS, the user profile, installed tools,
temporary files - is destroyed.

Useful switches: `-MemoryMB 16384` for a bigger sandbox, `-NoLaunch` to write
the `.wsb` without starting it.

## What gets mapped

| Sandbox path  | Host path                        | Access |
|---------------|----------------------------------|--------|
| `C:\Workspace`| `Projects\<name>`                | rw     |
| `C:\Dotfiles` | `Dotfiles\windows`               | ro     |
| `C:\Bootstrap`| `Bootstrap`                      | ro     |
| `C:\Cache`    | `Cache`                          | rw     |

`C:\AgentDev\Projects` is **never** mapped - only the single selected project
is. That is what stops an agent working on project A from reading project B.
The host user profile, Documents, Desktop and SSH keys are not mapped at all,
and the dotfiles are read-only so an agent cannot rewrite your own config.

## Layout

```
C:\AgentDev\
├── New-Project.ps1       create a project, then launch it
├── Start-Project.ps1     generate the .wsb and launch (the everyday command)
├── Common.ps1            shared paths + project-name validation
├── Projects\             one directory per project (never mapped as a whole)
├── Sandboxes\            generated .wsb files, rewritten on every launch
├── Cache\                Scoop and npm download caches, shared across projects
├── Bootstrap\
│   ├── bootstrap.ps1         runs inside the sandbox as the LogonCommand
│   ├── project-AGENTS.md     seeded into each new project
│   └── project-gitignore.txt seeded into each new project
└── Dotfiles\
    ├── source\           upstream kunchenguid/dotfiles, reference only
    └── windows\          the real Windows dotfiles (mapped read-only)
        ├── AGENTS.md         single source of truth for agent instructions
        ├── profile\          mirrors %USERPROFILE%
        ├── localappdata\     mirrors %LOCALAPPDATA% (Neovim config)
        └── Documents\PowerShell\
```

`Dotfiles\windows\profile\` and `localappdata\` mirror the real profile layout,
so `bootstrap.ps1` deploys them with a plain recursive copy per root instead of
maintaining a source-to-target mapping table. To add a dotfile, drop it at the
path it should occupy in the profile - no script change needed.

## One AGENTS.md, three agents

`Dotfiles\windows\AGENTS.md` is the only place your agent instructions live.
`bootstrap.ps1` copies it to every agent's global instruction path:

- `~\.claude\CLAUDE.md`
- `~\.codex\AGENTS.md`
- `~\.pi\agent\AGENTS.md`

Projects get their own `AGENTS.md` (from `Bootstrap\project-AGENTS.md`)
describing the sandbox environment. An existing project `AGENTS.md` is never
overwritten.

## What bootstrap installs

Scoop provides `git`, `neovim`, `ripgrep`, `fd`, `fzf`, `starship`,
`nodejs-lts` and `wezterm`; npm provides `claude`, `codex` and `pi`; Herdr
comes from its own installer. Windows Sandbox has no winget, which is why
Scoop is used.

Every step is idempotent and guarded on "already present", and a single failed
package logs a warning instead of aborting the run - a missing tool should not
cost you the whole sandbox.

## Caching

`Cache\` is mapped read-write so Scoop and npm downloads survive sandbox
teardown. First launch downloads everything; later launches reuse it.

This is the one channel shared between projects. It is safe because both
consumers verify integrity - Scoop checks each download against the manifest
hash, npm's cacache verifies sha512 per entry - so a tampered cache entry fails
verification and is re-fetched rather than executed.

For the same reason `%LOCALAPPDATA%\nvim-data` is deliberately **not** cached:
plugin trees are executable code with no integrity check, so sharing them
between projects would be a genuine cross-project escape hatch. Neovim
re-fetches plugins on first launch in each sandbox.

## Logs

`bootstrap.ps1` writes to `C:\Workspace\.agentdev-bootstrap.log`, which means
the log lands in the project on the host and is readable during and after the
run. A log written inside the sandbox would be unreachable and would vanish on
close. It is gitignored.

## Known limitations

- Only one Windows Sandbox can run at a time; `Start-Project.ps1` refuses to
  launch a second one rather than failing obscurely.
- Agents are unauthenticated on every launch, because host credentials are
  deliberately not mapped in. Expect to log into each agent per session.
- No pushing from inside the sandbox - host SSH keys are not exposed. Commit
  inside, push from the host.
- `ProtectedClient` has been flaky on some 24H2 builds. If the sandbox refuses
  to start, removing that element from `Start-Project.ps1` is the first thing
  to try.

## Requirements

Windows Sandbox must be enabled. From an elevated PowerShell:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
```

then reboot.
