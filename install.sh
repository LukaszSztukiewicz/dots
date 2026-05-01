#!/usr/bin/env bash
set -euo pipefail

DOTS_REPO="https://github.com/lsztuk/dots"

info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }
command_exists() { command -v "$1" &>/dev/null; }

# 1. Detect OS
if ! command_exists apt-get; then
    error "Only Ubuntu/apt-based systems are supported. Detected: $(uname -a)"
fi

# 2. Install chezmoi
if ! command_exists chezmoi; then
    info "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
fi

# 3. Install Bitwarden CLI
if ! command_exists bw; then
    info "Installing Bitwarden CLI..."
    bw_version="2024.3.1"
    curl -fsSL "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" \
        -o /tmp/bw.zip
    unzip -q /tmp/bw.zip -d /tmp/bw-bin
    install -m 755 /tmp/bw-bin/bw "$HOME/.local/bin/bw"
    rm -rf /tmp/bw.zip /tmp/bw-bin
    export PATH="$HOME/.local/bin:$PATH"
fi

# 4. Bitwarden auth — always interactive
_bw_ensure_session() {
    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked)
            info "Bitwarden vault is already unlocked."
            ;;
        locked)
            info "Bitwarden vault is locked. Unlocking..."
            BW_SESSION=$(bw unlock --raw)
            export BW_SESSION
            ;;
        unauthenticated)
            info "Not logged in to Bitwarden. Logging in..."
            BW_SESSION=$(bw login --raw)
            export BW_SESSION
            ;;
        *)
            error "Could not determine Bitwarden status (got: '$status'). Is bw installed?"
            ;;
    esac
}

_bw_ensure_session

# 5. Write per-machine chezmoi config (skip if already exists)
CHEZMOI_CFG="$HOME/.config/chezmoi/chezmoi.toml"

if [ ! -f "$CHEZMOI_CFG" ]; then
    info "Creating per-machine Chezmoi config..."
    mkdir -p "$(dirname "$CHEZMOI_CFG")"

    machine_role="${MACHINE_ROLE:-}"
    git_name="${GIT_NAME:-}"
    git_email="${GIT_EMAIL:-}"
    proxy="${PROXY:-}"

    if [ -z "$machine_role" ]; then
        read -rp "Machine role (workstation/server/laptop) [workstation]: " machine_role
        machine_role="${machine_role:-workstation}"
    fi

    if [ -z "$git_name" ]; then
        read -rp "Git full name: " git_name
    fi

    if [ -z "$git_email" ]; then
        read -rp "Git email: " git_email
    fi

    if [ -z "$proxy" ]; then
        read -rp "HTTP proxy (leave blank if none): " proxy
    fi

    cat > "$CHEZMOI_CFG" << EOF
[data]
  machineRole = "$machine_role"
  gitName     = "$git_name"
  gitEmail    = "$git_email"
  proxy       = "$proxy"
EOF
    info "Config written to $CHEZMOI_CFG"
else
    info "Chezmoi config already exists at $CHEZMOI_CFG — skipping prompts."
fi

# 6. Apply dotfiles
if chezmoi source-path &>/dev/null; then
    info "Chezmoi already initialised — running apply..."
    chezmoi apply
else
    info "Initialising Chezmoi from $DOTS_REPO ..."
    chezmoi init --apply "$DOTS_REPO"
fi

info "Done. Run 'cap' to apply future changes."
