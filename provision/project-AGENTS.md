# Project agent instructions

Your global policy still applies. It lives at `/home/dev/.claude/CLAUDE.md`,
`/home/dev/.codex/AGENTS.md` and `/home/dev/.pi/agent/AGENTS.md` - these are
copies placed inside this instance when its image was built, not files on the
host. The host's own configuration is not reachable from here. This file adds
environment context on top of that policy.

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
- `~/firstmate` holds the firstmate agent distro, and this project is registered
  under `~/firstmate/projects/`. Running a crew means starting an agent from
  inside `~/firstmate` (the `fm` shell function takes you there) - not from
  here. Leave that to the user unless asked.

## Consequences for how you work

- Everything worth keeping must be committed. The instance's history is the
  project - there is no copy on the Windows drive.
- Host SSH keys are deliberately unavailable. Pushing uses the GitHub CLI with
  a token scoped to this instance. If `gh auth status` reports you are not
  logged in, ask the user to run `gh auth login` - do not attempt to work
  around it or add credentials by other means.
- Do not push unless the user asks. Committing is yours to do freely; sending
  code to a remote is their call.
- Secrets come from 1Password, never from the project tree, and you never see
  their values. Run anything that needs a credential as `op-env -- <command>`;
  it injects this project's 1Password Environment into that command alone.
  `op-env --names` lists what is available, without values. There is no token in
  your environment, so plain `op` will fail - that is intended, not a fault to
  fix, and reading the root-owned token with `sudo` is out of bounds. If `op-env`
  reports it is not configured, ask the user to run `op-login` rather than
  hardcoding a credential. The `onepassword` skill has the details.
- Node is managed by `nvm`; run `nvm use` if the project pins a version.
- For Expo, start Metro with `npx expo start`. Networking is mirrored from the
  host, so a phone on the same Wi-Fi can reach it directly.
