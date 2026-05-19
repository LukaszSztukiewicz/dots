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

_bw_session_valid() {
    # `bw unlock --check` returns 0 if *any* session is present (env or disk),
    # not "is BW_SESSION valid". A stale env token passes --check but fails on
    # real operations like `bw get item`. `bw list folders --raw` actually
    # decrypts vault data, which exercises the session end-to-end.
    [ -n "${BW_SESSION:-}" ] && bw list folders --raw >/dev/null 2>&1
}

_bw_unlock_interactive() {
    local pw err_file unlock_out unlock_rc

    if [ -n "${BW_PASSWORD:-}" ]; then
        pw="$BW_PASSWORD"
    elif _have_tty; then
        # Read the master password ourselves and hand it to bw via env.
        # `bw unlock --raw </dev/tty` reads from /dev/tty directly and has
        # been observed to mis-read the password under `curl | bash` (decrypt
        # fails on a correct password). Bash's `read -s` is reliable.
        printf '[dots] Bitwarden master password: ' >/dev/tty
        IFS= read -rs pw </dev/tty
        printf '\n' >/dev/tty
        [ -n "$pw" ] || error "Empty master password."
    else
        error "Bitwarden unlock required, but stdin is not a TTY and BW_PASSWORD is unset. Re-run from a terminal, or set BW_PASSWORD."
    fi

    # Capture stderr separately so we can show bw's actual error if unlock
    # fails (the previous version silenced stderr inside $(...) and gave us
    # nothing to debug from).
    err_file=$(mktemp)
    if unlock_out=$(BW_PASSWORD="$pw" bw unlock --passwordenv BW_PASSWORD --raw 2>"$err_file"); then
        unlock_rc=0
    else
        unlock_rc=$?
    fi
    unset pw

    if [ "$unlock_rc" -ne 0 ]; then
        local err_msg
        err_msg=$(cat "$err_file")
        rm -f "$err_file"
        error "bw unlock failed (exit $unlock_rc): ${err_msg:-<no stderr output>}"
    fi
    rm -f "$err_file"

    [ -n "$unlock_out" ] || error "bw unlock returned exit 0 but no session token."

    export BW_SESSION="$unlock_out"
}

_bw_ensure_session() {
    # Fast path: a working BW_SESSION already in env. Verify with --check
    # (don't trust `bw status` alone — it returns "unlocked" for stale
    # sessions too, which then mis-fall-through to a tty prompt inside
    # chezmoi's bw subprocess).
    if _bw_session_valid; then
        info "Bitwarden session valid."
        return
    fi

    # Drop any stale BW_SESSION so bw can't try to use it.
    unset BW_SESSION

    local status
    status=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

    case "$status" in
        unlocked|locked)
            # If status is "unlocked" but we got here, BW_SESSION wasn't valid in env.
            # Lock to force a clean re-unlock that gives us a fresh raw session.
            [ "$status" = "unlocked" ] && bw lock >/dev/null 2>&1 || true
            info "Unlocking Bitwarden vault..."
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

    _bw_unlock_interactive
}

_bw_ensure_session
info "Bitwarden ready (session length: ${#BW_SESSION} chars)."

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
    # Disable git's credential prompts so a wrong URL or a private repo fails
    # fast with a clear error instead of hanging on a password prompt that
    # can't succeed (GitHub no longer accepts passwords for HTTPS git ops).
    GIT_TERMINAL_PROMPT=0 git clone "$DOTS_REPO" "$REPO_PARENT" \
        || error "git clone $DOTS_REPO failed. If the repo is private, clone it manually into $REPO_PARENT (e.g. via SSH) and re-run."
else
    info "Chezmoi source already present at $REPO_PARENT."
fi

info "Applying dotfiles..."
chezmoi apply

info "Done. Run 'cap' to apply future changes."
