# Project agent instructions

Your global policy in `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and
`~/.pi/agent/AGENTS.md` still applies. This file adds environment context.

## Where you are

You are running inside a disposable Windows Sandbox.

- `C:\Workspace` is the project. It is the **only** host directory you can write
  to, and it is the only thing that survives when this sandbox closes.
- `C:\Dotfiles` and `C:\Bootstrap` are mounted read-only. Do not try to modify
  them - changes belong in the host repo at `C:\AgentDev`.
- `C:\Cache` is a shared package cache (Scoop, npm). Treat it as machine state,
  not as project state.
- Everything else - the OS, the user profile, installed tools - is thrown away
  on exit. Nothing outside `C:\Workspace` persists.

## Consequences for how you work

- Put anything worth keeping under `C:\Workspace`, and commit it.
- Host SSH keys and git credentials are deliberately not available here. Commit
  locally; pushing happens from the host.
- Tools are installed with Scoop (`scoop install <pkg>`). Node packages with
  `npm i -g`. Both are cached to `C:\Cache`, so installs are cheap.
- If you need a tool that is missing, install it - this machine is disposable.
