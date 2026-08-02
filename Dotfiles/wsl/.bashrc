# Agent workspace shell profile. This tree mirrors the home directory, so
# provision.sh deploys it with a single recursive copy.

# Non-interactive shells stop here, but nvm must still be on PATH for them -
# scripts and agents run plenty of non-interactive bash.
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

case $- in
    *i*) ;;
      *) return;;
esac

export EDITOR=nvim
export VISUAL=nvim
export LANG=en_US.UTF-8

HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend checkwinsize

alias ll='ls -alFh --color=auto'
alias la='ls -A --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias vi=nvim
alias vim=nvim
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

# fzf-backed directory jump, using fd for the listing.
ff() {
    local dir
    dir=$(fd --type d --hidden --exclude .git . 2>/dev/null | fzf) && cd "$dir" || return
}

# The Docker daemon is per-instance and systemd-managed; start it on demand so
# a project that never uses Docker does not pay for it.
dockerup() {
    sudo systemctl start docker && docker info >/dev/null 2>&1 && echo "docker ready"
}

# Firstmate is launched by starting an agent from inside its own directory,
# which is not obvious from anywhere else.
fm() {
    if [ ! -d "$HOME/firstmate" ]; then
        echo "firstmate is not installed in this instance." >&2
        return 1
    fi
    cd "$HOME/firstmate" || return 1
    echo "firstmate $(git rev-parse --short HEAD 2>/dev/null) - start a crew with: claude   (or codex / pi)"
}

command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

# Land in the project rather than the home directory.
[ -d "$HOME/workspace" ] && [ "$PWD" = "$HOME" ] && cd "$HOME/workspace"
