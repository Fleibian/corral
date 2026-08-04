#!/usr/bin/env bash
#
# Builds the golden base image for agent workspaces. Runs ONCE, inside a
# throwaway distro, during Build-BaseImage.ps1. The result is exported to a
# tarball that every project instance is cloned from, so all of this cost is
# paid once rather than on every launch.
#
# Everything here must be idempotent - the base image can be rebuilt over an
# existing instance during development.

set -euo pipefail

DEV_USER="${DEV_USER:-dev}"
DOTFILES_SRC="${DOTFILES_SRC:-/tmp/dotfiles}"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[0;32mOK\033[0m   %s\n' "$*"; }
warn() { printf '    \033[0;33mWARN\033[0m %s\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------- base system

log "Base packages"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    git openssh-client \
    build-essential pkg-config \
    unzip zip xz-utils \
    ripgrep fd-find fzf \
    neovim \
    jq \
    python3 python3-venv python3-pip \
    sudo locales tzdata tmux \
    wl-clipboard xclip \
    bubblewrap \
    iproute2 iputils-ping dnsutils \
    watchman 2>/dev/null || \
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    git openssh-client build-essential pkg-config \
    unzip zip xz-utils ripgrep fd-find fzf neovim jq \
    python3 python3-venv python3-pip sudo locales tzdata \
    bubblewrap iproute2 iputils-ping dnsutils
ok "apt packages"

# wl-clipboard is what makes Neovim's `clipboard=unnamedplus` actually reach
# Windows. WSLg provides a Wayland socket (WAYLAND_DISPLAY=wayland-0) and
# bridges its clipboard to the host - verified to work even with interop
# disabled, so no win32yank and no /mnt/c are needed. xclip is the fallback for
# the X11 path, since without either Neovim silently falls back to its own
# registers and yanks appear to do nothing.

# bubblewrap is Codex's sandbox. Without bwrap on PATH it warns on every start
# and falls back to the copy vendored in its npm package, which then goes stale
# independently of the distro's security updates.

# Debian/Ubuntu ship fd as fdfind to avoid a name clash; everyone expects fd.
if [ -x /usr/bin/fdfind ] && [ ! -e /usr/local/bin/fd ]; then
    ln -sf /usr/bin/fdfind /usr/local/bin/fd
    ok "fd -> fdfind"
fi

locale-gen en_US.UTF-8 >/dev/null 2>&1 || true

# ------------------------------------------------------------------ dev user

log "User '$DEV_USER'"
if ! id -u "$DEV_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$DEV_USER"
    ok "created"
else
    ok "exists"
fi
# Passwordless sudo: the instance is disposable and the agent needs to install
# packages without an interactive prompt it cannot answer.
echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-"$DEV_USER"
chmod 0440 /etc/sudoers.d/90-"$DEV_USER"

HOME_DIR="/home/$DEV_USER"
mkdir -p "$HOME_DIR/workspace"

# ---------------------------------------------------------------------- node

log "Node.js (via nvm, so agents can switch versions per project)"
NVM_DIR="$HOME_DIR/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    su - "$DEV_USER" -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
fi
su - "$DEV_USER" -c '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm alias default "lts/*"
    corepack enable || true
'
ok "node $(su - "$DEV_USER" -c '. "$HOME/.nvm/nvm.sh"; node --version' 2>/dev/null || echo '?')"

# --------------------------------------------------------------------- tools

log "starship prompt"
if ! command -v starship >/dev/null 2>&1; then
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes >/dev/null
fi
ok "starship"

log "Herdr session manager"
# Linux is Herdr's stable platform, unlike the Windows preview build.
if ! su - "$DEV_USER" -c 'command -v herdr' >/dev/null 2>&1; then
    su - "$DEV_USER" -c 'curl -fsSL https://herdr.dev/install.sh | bash' || warn "herdr install failed"
fi
su - "$DEV_USER" -c 'command -v herdr >/dev/null' && ok "herdr" || warn "herdr not on PATH"

# -------------------------------------------------------------------- docker

log "Docker engine (per-instance daemon, not shared with the host)"
if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
usermod -aG docker "$DEV_USER"
systemctl enable docker >/dev/null 2>&1 || true
ok "docker $(docker --version 2>/dev/null | head -1 || echo '?')"

# -------------------------------------------------------------------- agents

log "Coding agents"
# npm writes warnings to stderr constantly; judge success by exit code only.
su - "$DEV_USER" -c '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    set +e
    for spec in \
        "claude:@anthropic-ai/claude-code:" \
        "codex:@openai/codex:" \
        "pi:@earendil-works/pi-coding-agent:--ignore-scripts"
    do
        cmd="${spec%%:*}"; rest="${spec#*:}"; pkg="${rest%%:*}"; opts="${rest#*:}"
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "    --   $cmd (already present)"
            continue
        fi
        # shellcheck disable=SC2086
        if npm install -g $opts "$pkg" >/tmp/npm-$cmd.log 2>&1; then
            echo "    OK   $cmd"
        else
            echo "    WARN $cmd failed (exit $?):"
            tail -5 /tmp/npm-$cmd.log | sed "s/^/         /"
        fi
    done
'

# ------------------------------------------------------------------ dotfiles

log "GitHub CLI"
# Host SSH keys are deliberately not exposed to instances, so gh is how a
# project pushes: `gh auth login` inside an instance stores a token scoped to
# that instance alone. A compromised project cannot reach your machine-wide
# credentials, and revoking one project's access does not affect the others.
if ! command -v gh >/dev/null 2>&1; then
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
    apt-get install -y -qq gh
fi
ok "$(gh --version 2>/dev/null | head -1 || echo 'gh install failed')"

log "1Password CLI (beta channel)"
# Secrets never live in the project tree, and never reach the agent. `op`
# resolves them at the moment a command runs and injects them straight into the
# subprocess environment.
#
# Two things about this environment force the design, and both were verified
# against the real binaries rather than assumed:
#
#   1. The 1Password *MCP server* cannot be used here. It is not part of the
#      CLI - `op mcp-server` does not exist in stable (2.38.1) or beta
#      (2.38.2-beta.01). It is a separate `1password-mcp` binary supplied by
#      the 1Password desktop app and enabled in Settings > Labs, and every call
#      needs an approval prompt in that app. Interop is off and there is no
#      /mnt/c, so an instance has no route to it. Bridging it from the host
#      would not help either: its "run with credentials" tool injects into a
#      *Windows* process, and the project's app runs in Linux. Something inside
#      this instance has to put the secret into a Linux process, and `op` is
#      the only thing that can.
#
#   2. The BETA channel is required. 1Password Environments - `op environment
#      read` and `op run --environment` - are absent from stable. Stable 2.38.1
#      has neither, beta 2.38.2-beta.01 has both. Since Environments are the
#      unit of access here, beta is not optional.
#
# debsig is 1Password's package signature policy. Their published install
# instructions set it up, and the package expects it, so it is reproduced here
# rather than trimmed to just the apt keyring.
if ! command -v op >/dev/null 2>&1; then
    OP_ARCH="$(dpkg --print-architecture)"
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
        | gpg --dearmor --yes --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$OP_ARCH signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$OP_ARCH beta main" \
        > /etc/apt/sources.list.d/1password.list

    mkdir -p /etc/debsig/policies/AC2D62742012EA22
    curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
        -o /etc/debsig/policies/AC2D62742012EA22/1password.pol
    mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
        | gpg --dearmor --yes --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

    apt-get update -qq
    apt-get install -y -qq 1password-cli
fi
ok "op $(op --version 2>/dev/null || echo 'install failed')"

log "Secret injection (op-env)"
# The agent must be able to USE secrets without ever being handed their values.
#
# The shape that achieves this: the service account token is stored root-owned
# under /etc/agentdev/op, never in the agent's environment and never in its home
# directory. The agent runs `op-env -- <cmd>`, which re-enters as root just long
# enough for `op run` to resolve the project's 1Password Environment, then drops
# straight back to the agent's own uid to exec the command. The command lands
# with the variables in its environment and WITHOUT the token, so the agent can
# use every credential and read none of them out of 1Password.
#
# Honest limit, stated here because it belongs next to the code: the agent has
# passwordless sudo, so a deliberate `sudo cat` of the token file still works.
# This is defense in depth - it removes every accidental path and the whole
# `op read` surface - not a boundary that survives an adversarial agent. Making
# it absolute means replacing NOPASSWD:ALL with an allowlist; see the README.
mkdir -p /etc/agentdev/op /usr/local/libexec
chmod 0711 /etc/agentdev/op

# Runs as root (via sudo), drops to the caller before exec'ing their command.
cat > /usr/local/libexec/op-env-run <<'OPENVRUN'
#!/usr/bin/env bash
# Resolve this project's 1Password Environment and run a command with it.
# Invoked only through `op-env`, which supplies sudo.
set -euo pipefail

TOKEN_FILE=/etc/agentdev/op/token
ENV_ID_FILE=/etc/agentdev/op/environment-id

if [ ! -r "$TOKEN_FILE" ] || [ ! -r "$ENV_ID_FILE" ]; then
    echo "op-env: not configured. Ask the user to run 'op-login'." >&2
    exit 78   # EX_CONFIG
fi

# sudo tells us who called, which is how the command gets back to the agent's
# own uid rather than staying root. Fall back to the dev user if invoked
# directly as root.
target_uid="${SUDO_UID:-$(id -u dev)}"
target_gid="${SUDO_GID:-$(id -g dev)}"

mode="${1:-}"
shift || true

case "$mode" in
    --names)
        # The value side never leaves this process. Printing only the keys is
        # what lets an agent discover what exists without learning any secret.
        OP_SERVICE_ACCOUNT_TOKEN="$(cat "$TOKEN_FILE")" \
            op environment read "$(cat "$ENV_ID_FILE")" \
            | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort
        ;;
    --exec)
        [ "$#" -gt 0 ] || { echo "op-env: no command given" >&2; exit 64; }
        # `op run` stays the parent so its output masking still applies to the
        # child. setpriv drops privilege, and `env -u` strips the token so the
        # command cannot read the credential that fetched its secrets.
        OP_SERVICE_ACCOUNT_TOKEN="$(cat "$TOKEN_FILE")" \
        exec op run --environment "$(cat "$ENV_ID_FILE")" -- \
            setpriv --reuid="$target_uid" --regid="$target_gid" --init-groups \
            env -u OP_SERVICE_ACCOUNT_TOKEN -- "$@"
        ;;
    *)
        echo "op-env: internal mode '$mode' not recognised" >&2
        exit 64
        ;;
esac
OPENVRUN
chmod 0750 /usr/local/libexec/op-env-run

# Stores the token. Reads it on stdin so it is never an argument and never a
# file the agent owns.
cat > /usr/local/libexec/op-store-token <<'OPSTORE'
#!/usr/bin/env bash
set -euo pipefail
ENV_ID="${1:?environment id required}"
token="$(cat)"

case "$token" in
    ops_*) ;;
    *) echo "That does not look like a service account token (expected 'ops_')." >&2
       exit 1 ;;
esac

# Verify against the real Environment before storing, so a bad paste fails now
# rather than on the agent's first command. Output is discarded - it contains
# values.
if ! OP_SERVICE_ACCOUNT_TOKEN="$token" op environment read "$ENV_ID" >/dev/null 2>&1; then
    echo "That token could not read Environment '$ENV_ID'. Nothing was stored." >&2
    echo "Check that the token is current and that its service account has" >&2
    echo "access to this Environment." >&2
    exit 1
fi

install -d -m 0711 /etc/agentdev/op
( umask 077; printf '%s' "$token" > /etc/agentdev/op/token )
chown root:root /etc/agentdev/op/token
chmod 0400 /etc/agentdev/op/token
printf '%s' "$ENV_ID" > /etc/agentdev/op/environment-id
chmod 0444 /etc/agentdev/op/environment-id
OPSTORE
chmod 0750 /usr/local/libexec/op-store-token

# The agent-facing command.
cat > /usr/local/bin/op-env <<'OPENV'
#!/usr/bin/env bash
# Run a command with this project's 1Password Environment loaded.
#
#   op-env -- npm run dev     run with every variable in the Environment
#   op-env --names            list variable NAMES (never values)
#   op-env --status           show whether secrets are configured
#
# Secret values are never printed and never enter this shell.
set -euo pipefail

case "${1:-}" in
    --names)
        exec sudo -n /usr/local/libexec/op-env-run --names
        ;;
    --status)
        if [ ! -e /etc/agentdev/op/token ]; then
            echo "secrets: not configured - run 'op-login'"
            exit 1
        fi
        echo "secrets:     configured"
        echo "environment: $(cat /etc/agentdev/op/environment-id)"
        echo "variables:"
        sudo -n /usr/local/libexec/op-env-run --names | sed 's/^/  /'
        ;;
    --help|-h|'')
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    --)
        shift
        exec sudo -n /usr/local/libexec/op-env-run --exec "$@"
        ;;
    *)
        # Tolerate `op-env npm run dev` without the separator.
        exec sudo -n /usr/local/libexec/op-env-run --exec "$@"
        ;;
esac
OPENV
chmod 0755 /usr/local/bin/op-env

cat > /usr/local/bin/op-login <<'OPLOGIN'
#!/usr/bin/env bash
# Give this project access to one 1Password Environment.
#
# Run once per instance. The token scopes what this project can reach, so
# pasting it is the act of choosing which environment this project gets.
set -euo pipefail

if [ -e /etc/agentdev/op/token ]; then
    echo "This project is already configured for Environment $(cat /etc/agentdev/op/environment-id)."
    printf 'Replace it? [y/N] '
    read -r reply
    case "$reply" in [yY]*) ;; *) echo "unchanged."; exit 0 ;; esac
fi

ENV_ID="${1:-}"
if [ -z "$ENV_ID" ]; then
    echo "1Password Environment ID."
    echo "Find it in the 1Password app: Developer > View Environments >"
    echo "  select the environment > Manage environment > Copy environment ID."
    printf 'Environment ID: '
    read -r ENV_ID
fi
[ -n "$ENV_ID" ] || { echo "No Environment ID given." >&2; exit 1; }

echo
echo "Paste the service account token for that Environment (input is hidden):"
read -rs token
echo
[ -n "$token" ] || { echo "No token entered - nothing stored." >&2; exit 1; }

# Piped, so the token is never an argument and never lands in a file this user
# owns. It is verified and stored by a root helper.
printf '%s' "$token" | sudo -n /usr/local/libexec/op-store-token "$ENV_ID"
unset token

echo "Stored. The token is root-owned and is not in your environment."
echo
op-env --status
OPLOGIN
chmod 0755 /usr/local/bin/op-login

# Redundant while the dev user holds NOPASSWD:ALL, but this is the seam the
# README's hardening step needs: restrict that blanket rule and these two lines
# are what keep `op-env` working.
cat > /etc/sudoers.d/91-op-env <<SUDOERS
$DEV_USER ALL=(root) NOPASSWD: /usr/local/libexec/op-env-run
$DEV_USER ALL=(root) NOPASSWD: /usr/local/libexec/op-store-token
SUDOERS
chmod 0440 /etc/sudoers.d/91-op-env
visudo -cf /etc/sudoers.d/91-op-env >/dev/null && ok "op-env, op-login, sudoers"

# Agent skills are deliberately NOT installed here. They are chosen per project
# and installed by hand - each new workspace gets a SKILLS.md listing the
# commands. Keeping them out of the image also keeps project creation free of a
# network round-trip.

log "Firstmate agent distro"
# Not a package - the repo *is* the distribution, pure bash run in place. Cloned
# into the image so every project has it without a network round-trip at
# creation time. `corral build` is what refreshes it; existing projects keep the
# revision they were created with.
#
# The backend is deliberately NOT pinned here. Firstmate auto-detects from $TMUX
# then HERDR_ENV=1, and agentdev-session always execs herdr, so detection lands
# on herdr in normal use - while a `-Shell` session without herdr still resolves
# correctly. Setting FM_BACKEND globally would force herdr where it cannot work.
su - "$DEV_USER" -c '
    if [ -d "$HOME/firstmate/.git" ]; then
        echo "    --   firstmate (already present)"
    elif git clone --depth 1 --quiet https://github.com/kunchenguid/firstmate "$HOME/firstmate" 2>/tmp/fm.log; then
        echo "    OK   firstmate $(git -C "$HOME/firstmate" rev-parse --short HEAD)"
    else
        echo "    WARN firstmate clone failed:"
        tail -3 /tmp/fm.log | sed "s/^/         /"
    fi
    # Gitignored upstream, so registering a project here leaves the repo clean.
    mkdir -p "$HOME/firstmate/projects"
'
rm -f /tmp/fm.log

log "Session launcher"
# Start-Project invokes this by name. Keeping the session logic in a script
# means the launch command is a single argument with no spaces, quotes or
# shell operators - PowerShell's Start-Process does not quote arguments that
# contain spaces, so an inline `cmd && exec herdr || exec bash` gets split
# into separate tokens and the terminal dies on startup.
cat > /usr/local/bin/agentdev-session <<'LAUNCHER'
#!/usr/bin/env bash
# This script has a shebang, so it does not read .bashrc even when started from
# a login shell. herdr lives in ~/.local/bin and node in ~/.nvm, so set both up
# explicitly rather than depending on the caller's environment.
export PATH="$HOME/.local/bin:$PATH"
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

cd "$HOME/workspace" 2>/dev/null || cd "$HOME"

# Tell the terminal which project this is, so the window can be titled with the
# project name instead of "wslhost.exe". This is a user var rather than an OSC
# window title because herdr is a multiplexer and manages the pane title
# itself - a title set here would be overwritten the moment it starts. The
# instance hostname is the project name (set in /etc/wsl.conf).
printf '\033]1337;SetUserVar=agentdev_project=%s\007' "$(printf '%s' "$(hostname)" | base64 -w0)"

if command -v herdr >/dev/null 2>&1; then
    exec herdr
fi
echo "herdr is not installed - falling back to a login shell." >&2
exec bash -l
LAUNCHER
chmod 0755 /usr/local/bin/agentdev-session
ok "agentdev-session"

log "Dotfiles"
if [ -d "$DOTFILES_SRC" ]; then
    # The wsl/ tree mirrors the home directory, so deployment is one copy.
    if [ -d "$DOTFILES_SRC/wsl" ]; then
        cp -r "$DOTFILES_SRC/wsl/." "$HOME_DIR/"
        # The source sits on the Windows drive, which reports every file as
        # executable, so a plain copy leaves config files at 755. Scoped to
        # exactly the files just deployed - nothing else in the home directory
        # is touched.
        ( cd "$DOTFILES_SRC/wsl" && find . -type f -print ) | while read -r rel; do
            chmod 0644 "$HOME_DIR/${rel#./}" 2>/dev/null || true
        done
        ok "wsl dotfiles -> $HOME_DIR"
    fi

    # One AGENTS.md, fanned out to every agent's global instruction path.
    if [ -f "$DOTFILES_SRC/AGENTS.md" ]; then
        install -D -m 0644 "$DOTFILES_SRC/AGENTS.md" "$HOME_DIR/.claude/CLAUDE.md"
        install -D -m 0644 "$DOTFILES_SRC/AGENTS.md" "$HOME_DIR/.codex/AGENTS.md"
        install -D -m 0644 "$DOTFILES_SRC/AGENTS.md" "$HOME_DIR/.pi/agent/AGENTS.md"
        ok "AGENTS.md -> claude, codex, pi"
    else
        warn "no AGENTS.md in $DOTFILES_SRC"
    fi
else
    warn "no dotfiles at $DOTFILES_SRC"
fi

# The onepassword skill ships with the dotfiles (deployed by the copy above, at
# ~/.agents/skills/onepassword) and is linked into each agent's skill directory
# here. Relative symlinks into .agents/ are exactly the layout the `skills` CLI
# produces, so a hand-placed skill and an installed one look identical and a
# later `skills` run has nothing to trip over.
#
# This is not a contradiction of "skills are installed by hand". That rule is
# about optional, network-fetched, per-project picks. This one is local, costs
# no round-trip, and describes the instance's own secret handling - the same
# category as AGENTS.md, which is also shipped rather than chosen.
if [ -d "$HOME_DIR/.agents/skills/onepassword" ]; then
    link_skill() {  # $1 = agent skills dir, $2 = relative prefix back to $HOME
        mkdir -p "$1"
        ln -sfn "$2/.agents/skills/onepassword" "$1/onepassword"
    }
    link_skill "$HOME_DIR/.claude/skills"    "../.."
    link_skill "$HOME_DIR/.codex/skills"     "../.."
    link_skill "$HOME_DIR/.pi/agent/skills"  "../../.."
    ok "onepassword skill -> claude, codex, pi"
else
    warn "no onepassword skill in dotfiles"
fi

chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR"

# ---------------------------------------------------------------- pi packages

# The pi settings deployed above pin three third-party packages by exact
# version or commit. Pi installs anything missing on its first startup, so this
# step is only about *when* that happens: doing it here bakes them into the
# base image, which keeps project creation offline-capable and drops a ~15s
# stall off the first `pi` run in every project. The pins are immutable, so a
# baked copy and a freshly fetched one are the same code either way.
#
# `pi --help` is the cheapest command that still triggers package resolution.
log "Pi packages"
if [ -f "$HOME_DIR/.pi/agent/settings.json" ]; then
    su - "$DEV_USER" -c '
        export NVM_DIR="$HOME/.nvm"
        . "$NVM_DIR/nvm.sh"
        pi --help >/dev/null 2>/tmp/pi-warm.log
    ' || true
    # Judge by what actually landed, not by exit code - pi returns 0 whether or
    # not a package resolved.
    if su - "$DEV_USER" -c '
        export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; pi list 2>/dev/null
    ' | grep -q "$HOME_DIR/.pi/agent"; then
        ok "pinned pi packages resolved"
    else
        warn "pi packages did not resolve - they will install on first run:"
        tail -3 /tmp/pi-warm.log 2>/dev/null | sed 's/^/         /'
    fi
    chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR/.pi"
else
    warn "no pi settings.json - skipping package warm-up"
fi

# ------------------------------------------------------------------- cleanup

log "Cleanup"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/npm-*.log /tmp/pi-warm.log
ok "apt caches removed"

# Note: cleaning /mnt here would be pointless. The build distro has automount
# enabled, and WSL recreates the drive mount points every time it starts - the
# export step restarts it, so they come straight back. New-Project.ps1 removes
# them inside each instance instead, where automount is off and they stay gone.

log "Base image ready"
