# Project agent instructions

Your global policy in `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and
`~/.pi/agent/AGENTS.md` still applies. This file adds environment context.

## Where you are

You are inside a dedicated WSL2 instance created for this project alone.

- `~/workspace` is the project, on ext4. It is fast - treat it as a normal
  local disk, not a network mount.
- The Windows filesystem is **not** mounted. There is no `/mnt/c`, and Windows
  executables cannot be launched. This is deliberate: you can see this project
  and nothing else on the machine.
- You have passwordless `sudo`. The instance is disposable, so installing
  packages is fine and expected.
- Docker runs inside this instance with its own daemon. Start it on demand with
  `dockerup` (or `sudo systemctl start docker`). Containers and images here are
  not shared with any other project.

## Consequences for how you work

- Everything worth keeping must be committed. The instance's history is the
  project - there is no copy on the Windows drive.
- Host SSH keys are deliberately unavailable. Pushing uses the GitHub CLI with
  a token scoped to this instance. If `gh auth status` reports you are not
  logged in, ask the user to run `gh auth login` - do not attempt to work
  around it or add credentials by other means.
- Do not push unless the user asks. Committing is yours to do freely; sending
  code to a remote is their call.
- Node is managed by `nvm`; run `nvm use` if the project pins a version.
- For Expo, start Metro with `npx expo start`. Networking is mirrored from the
  host, so a phone on the same Wi-Fi can reach it directly.
