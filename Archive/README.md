# Archive - Windows Sandbox implementation

The original implementation of this workspace, kept because it works and is a
useful reference. It is **not maintained**. The active implementation is the
WSL2 one at the repository root.

`Windows_Agent_Workspace_Blueprint.md` here is the founding specification. Its
goals still describe what this workspace is for; only its chosen mechanism
(Windows Sandbox) was replaced.

## Why it was replaced

| | Windows Sandbox | WSL2 |
|---|---|---|
| Boot / start | ~40s | ~1-2s |
| Toolchain provisioning | ~11 min, **every launch** | once, into a base image |
| Project file I/O | VSMB mapped folder | native ext4 |
| Concurrent projects | **1** (hard limit) | many |

Windows Sandbox discards all disk state on exit, so every launch reinstalled an
identical toolchain from scratch. It also permits only one running instance,
which made concurrent agents on separate projects impossible. Together those
were decisive.

It did have one genuine advantage: each sandbox was a real VM, so projects were
isolated from each other by a hardware boundary. The WSL2 implementation shares
one utility VM between instances, and root in one instance can read another
instance's disk. See the isolation section of the root `README.md` - that was a
deliberate, documented trade.

## Running it

Still functional, and self-contained within this directory:

```powershell
C:\AgentDev\Archive\New-Project.ps1  my-app
C:\AgentDev\Archive\Start-Project.ps1 my-app
```

Requires the Windows Sandbox feature:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
```

## Layout

```
Archive\
├── New-Project.ps1        create a project, generate its .wsb, launch
├── Start-Project.ps1      regenerate the .wsb and launch
├── Common.ps1             paths and project-name validation
├── Bootstrap\             runs inside the sandbox as the LogonCommand
├── dotfiles-windows\      Windows profile trees (was Dotfiles\windows)
├── Projects\              project sources (gitignored)
├── Sandboxes\             generated .wsb files (gitignored)
└── Cache\                 Scoop and npm download caches (gitignored)
```

Two details worth knowing if you ever run this again:

- **`Projects\` here is not the repository's `Projects\`.** The root one now
  holds git bundle backups for the WSL2 workflow. These are unrelated things
  that happen to share a name, so this implementation keeps its own.
- **`AGENTS.md` is still shared.** The repository's `Dotfiles\AGENTS.md` is
  mapped into the sandbox at `C:\DotfilesShared`, separately from the Windows
  profile trees at `C:\Dotfiles`, so there remains exactly one source of truth
  for agent instructions across both implementations.

## Known issues, unfixed

`codex` and `pi` never installed successfully here - npm reported
`Could not determine Node.js install directory` after the first agent install
failed. `claude` worked. All three install cleanly on the WSL2 path, which is
part of why the effort went there instead.
