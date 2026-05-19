#!/usr/bin/env bash
set -euo pipefail

DOTS_REPO="${DOTS_REPO:-https://github.com/LukaszSztukiewicz/dots}"

info()  { echo "[dots] $*"; }
error() { echo "[dots] ERROR: $*" >&2; exit 1; }
command_exists() { command -v "$1" &>/dev/null; }

# 0. Optional reset — wipes install-side state so the rest of the script runs
#    as if on a fresh machine. Does NOT touch dotfiles already applied to $HOME
#    (those are owned by chezmoi). Set DOTS_RESET=1 to enable.
if [ "${DOTS_RESET:-0}" = "1" ]; then
    info "DOTS_RESET=1: clearing install state..."
    reset_paths=(
        "$HOME/.config/chezmoi"
        "$HOME/.local/share/chezmoi"
        "$HOME/.config/Bitwarden CLI"
        "$HOME/.local/bin/bw"
        "$HOME/.local/bin/chezmoi"
    )
    for p in "${reset_paths[@]}"; do
        if [ -e "$p" ]; then
            info "  rm -rf $p"
            rm -rf -- "$p"
        fi
    done
fi

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
    bw_version="2026.4.1"
    curl -fsSL "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" \
        -o /tmp/bw.zip
    unzip -q /tmp/bw.zip -d /tmp/bw-bin
    install -m 755 /tmp/bw-bin/bw "$HOME/.local/bin/bw"
    rm -rf /tmp/bw.zip /tmp/bw-bin
    export PATH="$HOME/.local/bin:$PATH"
fi

# 4. Bitwarden auth — interactive via /dev/tty (works under `curl | bash`),
#    or fully headless via BW_CLIENTID/BW_CLIENTSECRET (+ BW_PASSWORD) env vars.
_have_tty()      { (exec </dev/tty) 2>/dev/null; }
_bw_have_apikey() { [ -n "${BW_CLIENTID:-}" ] && [ -n "${BW_CLIENTSECRET:-}" ]; }

_bw_ensure_session() {
    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked)
            info "Bitwarden vault is already unlocked."
            return
            ;;
        locked)
            info "Bitwarden vault is locked. Unlocking..."
            ;;
        unauthenticated)
            if _bw_have_apikey; then
                info "Logging in to Bitwarden via API key..."
                bw login --apikey --quiet
            elif _have_tty; then
                info "Not logged in to Bitwarden. Logging in (interactive)..."
                bw login </dev/tty
            else
                error "Bitwarden login required, but stdin is not a TTY and BW_CLIENTID/BW_CLIENTSECRET are unset. Re-run from a terminal, or set the API-key env vars (see README -> Headless mode)."
            fi
            info "Login complete. Unlocking vault..."
            ;;
        *)
            error "Could not determine Bitwarden status (got: '$status'). Is bw installed?"
            ;;
    esac

    if [ -n "${BW_PASSWORD:-}" ]; then
        BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
    elif _have_tty; then
        BW_SESSION=$(bw unlock --raw </dev/tty)
    else
        error "Bitwarden unlock required, but stdin is not a TTY and BW_PASSWORD is unset. Re-run from a terminal, or set BW_PASSWORD."
    fi
    export BW_SESSION
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
        if _have_tty; then
            read -rp "Machine role (workstation/server/laptop) [workstation]: " machine_role </dev/tty
        fi
        machine_role="${machine_role:-workstation}"
    fi

    if [ -z "$git_name" ]; then
        if _have_tty; then
            read -rp "Git full name: " git_name </dev/tty
        else
            error "GIT_NAME is required (no TTY available). Set it as an environment variable."
        fi
    fi

    if [ -z "$git_email" ]; then
        if _have_tty; then
            read -rp "Git email: " git_email </dev/tty
        else
            error "GIT_EMAIL is required (no TTY available). Set it as an environment variable."
        fi
    fi

    if [ -z "$proxy" ]; then
        if _have_tty; then
            read -rp "HTTP proxy (leave blank if none): " proxy </dev/tty
        fi
    fi

    validate_no_quotes() {
        local val="$1" label="$2"
        if [[ "$val" == *'"'* ]] || [[ "$val" == *$'\\'* ]]; then
            error "$label must not contain double-quotes or backslashes"
        fi
    }
    validate_no_quotes "$machine_role" "Machine role"
    validate_no_quotes "$git_name" "Git name"
    validate_no_quotes "$git_email" "Git email"
    validate_no_quotes "$proxy" "Proxy"

    cat > "$CHEZMOI_CFG" << EOF
sourceDir = "$HOME/.local/share/chezmoi/home"

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

# 6. Clone the dotfiles repo into the chezmoi source dir (if not already there) and apply.
#    chezmoi.toml above sets sourceDir = $HOME/.local/share/chezmoi/home, so the repo
#    must live at $HOME/.local/share/chezmoi/ with the source state under home/.
REPO_PARENT="$HOME/.local/share/chezmoi"
if [ ! -d "$REPO_PARENT/.git" ]; then
    if ! command_exists git; then
        info "Installing git (required to clone the dotfiles repo)..."
        if [ "$(id -u)" -eq 0 ]; then
            apt-get update -qq && apt-get install -y git
        elif command_exists sudo; then
            sudo apt-get update -qq && sudo apt-get install -y git
        else
            error "git is required but not installed, and sudo is unavailable. Install git manually and re-run."
        fi
    fi
    info "Cloning $DOTS_REPO into $REPO_PARENT ..."
    mkdir -p "$(dirname "$REPO_PARENT")"
    git clone "$DOTS_REPO" "$REPO_PARENT"
else
    info "Chezmoi source already present at $REPO_PARENT."
fi

info "Applying dotfiles..."
chezmoi apply

info "Done. Run 'cap' to apply future changes."
