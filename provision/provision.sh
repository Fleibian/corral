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
    sudo locales tzdata \
    iproute2 iputils-ping dnsutils \
    watchman 2>/dev/null || \
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    git openssh-client build-essential pkg-config \
    unzip zip xz-utils ripgrep fd-find fzf neovim jq \
    python3 python3-venv python3-pip sudo locales tzdata \
    iproute2 iputils-ping dnsutils
ok "apt packages"

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

chown -R "$DEV_USER:$DEV_USER" "$HOME_DIR"

# ------------------------------------------------------------------- cleanup

log "Cleanup"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/npm-*.log
ok "apt caches removed"

# Note: cleaning /mnt here would be pointless. The build distro has automount
# enabled, and WSL recreates the drive mount points every time it starts - the
# export step restarts it, so they come straight back. New-Project.ps1 removes
# them inside each instance instead, where automount is off and they stay gone.

log "Base image ready"
