#!/usr/bin/env bash
set -euo pipefail

# bootstrap.sh — one-shot dotfiles install.
#
# Installs bw + chezmoi, authenticates with Bitwarden, writes the per-machine
# chezmoi config, clones the dotfiles repo, applies it, and sets zsh as the
# login shell.
#
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/bootstrap.sh | bash
#
# Headless (no TTY — servers/CI): set BW_CLIENTID, BW_CLIENTSECRET,
#   BW_PASSWORD, MACHINE_ROLE, GIT_NAME, GIT_EMAIL, then pipe to bash.
#
# Re-run without re-authing: export BW_SESSION='...' before running.

DOTS_REPO="${DOTS_REPO:-https://github.com/LukaszSztukiewicz/dots}"
DOTS_RAW="${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}"

# ── Color lib ──────────────────────────────────────────────────────────────
# Source the shared color lib if the repo is already on disk; otherwise fall
# back to TTY-aware inline shims so output is colored from line 1.
_COLORS_LIB="$HOME/.local/share/chezmoi/scripts/lib/colors.sh"
# shellcheck source=/dev/null
if [ -r "$_COLORS_LIB" ]; then
    . "$_COLORS_LIB"
else
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${DOTS_NO_COLOR:-}" ]; then
        _r=$'\033[0m'; _b=$'\033[1m'
        _rd=$'\033[31m'; _g=$'\033[32m'; _y=$'\033[33m'
        _bl=$'\033[34m'; _c=$'\033[36m'
    else
        _r=; _b=; _rd=; _g=; _y=; _bl=; _c=
    fi
    c_step() { printf '%s==>%s %s%s%s\n' "$_c"  "$_r" "$_b" "$*" "$_r"; }
    c_info() { printf '%s[dots]%s %s\n'  "$_bl" "$_r" "$*"; }
    c_ok()   { printf '%s[ ok ]%s %s\n'  "$_g"  "$_r" "$*"; }
    c_warn() { printf '%s[warn]%s %s\n'  "$_y"  "$_r" "$*" >&2; }
    c_err()  { printf '%s[ERR ]%s %s\n'  "$_rd" "$_r" "$*" >&2; }
fi

info()  { c_info "$*"; }
error() { c_err "$*"; exit 1; }
command_exists() { command -v "$1" &>/dev/null; }
_have_tty()      { (exec </dev/tty) 2>/dev/null; }

# ── Optional cleanup ───────────────────────────────────────────────────────
_CLEANUP_SCRIPT="$HOME/.local/share/chezmoi/scripts/cleanup.sh"
if [ "${DOTS_NUKE:-0}" = "1" ]; then
    if [ ! -x "$_CLEANUP_SCRIPT" ]; then
        error "DOTS_NUKE=1 requires $_CLEANUP_SCRIPT. Clone the repo into \$HOME/.local/share/chezmoi first, then re-run."
    fi
    "$_CLEANUP_SCRIPT" --nuke ${DOTS_NUKE_FORCE:+--force}
elif [ "${DOTS_RESET:-0}" = "1" ]; then
    if [ -x "$_CLEANUP_SCRIPT" ]; then
        "$_CLEANUP_SCRIPT" --reset
    else
        # Repo isn't on disk yet — inline reset list, must stay in sync with
        # RESET_PATHS in scripts/cleanup.sh.
        info "DOTS_RESET=1: clearing install state (inline, repo was not cloned)..."
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
fi

# ── OS check ───────────────────────────────────────────────────────────────
if ! command_exists apt-get; then
    error "Only Ubuntu/apt-based systems are supported. Detected: $(uname -a)"
fi

_apt() {
    if [ "$(id -u)" -eq 0 ]; then
        apt-get "$@"
    elif command_exists sudo; then
        sudo apt-get "$@"
    else
        error "apt-get $1 needs root and sudo is unavailable."
    fi
}

# ── Bootstrap deps ─────────────────────────────────────────────────────────
_need_bootstrap=()
command_exists unzip || _need_bootstrap+=(unzip)
command_exists curl  || _need_bootstrap+=(curl)
if [ "${#_need_bootstrap[@]}" -gt 0 ]; then
    info "Installing bootstrap deps: ${_need_bootstrap[*]}"
    export DEBIAN_FRONTEND=noninteractive
    _apt update -qq
    _apt install -y "${_need_bootstrap[@]}"
fi

# ── Install chezmoi ────────────────────────────────────────────────────────
if ! command_exists chezmoi; then
    info "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

# ── Install Bitwarden CLI ──────────────────────────────────────────────────
if ! command_exists bw; then
    info "Installing Bitwarden CLI..."
    bw_version="2026.4.1"
    curl -fsSL "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" \
        -o /tmp/bw.zip
    unzip -q /tmp/bw.zip -d /tmp/bw-bin
    install -m 755 /tmp/bw-bin/bw "$HOME/.local/bin/bw"
    rm -rf /tmp/bw.zip /tmp/bw-bin
fi

# Ensure ~/.local/bin is in PATH (chezmoi/bw may have just been installed there).
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# ── Bitwarden auth ─────────────────────────────────────────────────────────
_strip_ws() { printf '%s' "$1" | awk '{$1=$1; print}'; }
[ -n "${BW_CLIENTID:-}"     ] && BW_CLIENTID="$(_strip_ws "$BW_CLIENTID")"         && export BW_CLIENTID
[ -n "${BW_CLIENTSECRET:-}" ] && BW_CLIENTSECRET="$(_strip_ws "$BW_CLIENTSECRET")" && export BW_CLIENTSECRET
[ -n "${BW_PASSWORD:-}"     ] && BW_PASSWORD="$(_strip_ws "$BW_PASSWORD")"         && export BW_PASSWORD

_bw_have_apikey() { [ -n "${BW_CLIENTID:-}" ] && [ -n "${BW_CLIENTSECRET:-}" ]; }
_bw_status() {
    bw status 2>/dev/null | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' || true
}

_bw_session_valid() {
    [ -n "${BW_SESSION:-}" ] && bw --nointeraction --session "$BW_SESSION" list folders >/dev/null 2>&1
}

_bw_unlock_interactive() {
    local pw err_file unlock_out unlock_rc

    if [ -n "${BW_PASSWORD:-}" ]; then
        pw="$BW_PASSWORD"
    elif _have_tty; then
        printf '[dots] Bitwarden master password: ' >/dev/tty
        IFS= read -rs pw </dev/tty
        printf '\n' >/dev/tty
        [ -n "$pw" ] || error "Empty master password."
    else
        error "Bitwarden unlock required, but stdin is not a TTY and BW_PASSWORD is unset. Re-run from a terminal, or set BW_PASSWORD."
    fi

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
    if _bw_session_valid; then
        info "Bitwarden session already valid."
        return
    fi
    unset BW_SESSION

    local status
    status="$(_bw_status)"
    [ -n "$status" ] || status="error"

    case "$status" in
        unlocked|locked)
            [ "$status" = "unlocked" ] && bw lock >/dev/null 2>&1 || true
            info "Unlocking Bitwarden vault..."
            _bw_unlock_interactive
            ;;
        unauthenticated)
            if _bw_have_apikey; then
                info "Logging in to Bitwarden via API key..."
                bw login --apikey --quiet
                info "Login complete. Unlocking vault..."
                # API key login leaves the vault locked, so we must unlock it now.
                _bw_unlock_interactive
            elif _have_tty; then
                info "Not logged in to Bitwarden. Logging in (interactive)..."
                # Interactive login authenticates AND unlocks; capture the raw token
                # directly to skip the redundant unlock step.
                local login_out
                if login_out=$(bw login --raw </dev/tty); then
                    export BW_SESSION="$login_out"
                    info "Login and unlock complete."
                else
                    error "Bitwarden login failed."
                fi
                [ -n "$BW_SESSION" ] || error "bw login returned no session token."
            else
                error "Bitwarden login required, but stdin is not a TTY and BW_CLIENTID/BW_CLIENTSECRET are unset. Re-run from a terminal, or set the API-key env vars (see README -> Headless mode)."
            fi
            ;;
        *)
            error "Could not determine Bitwarden status (got: '$status'). Is bw installed?"
            ;;
    esac
}

_bw_ensure_session
info "Bitwarden ready."

# ── Per-machine chezmoi config ─────────────────────────────────────────────
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
            read -rp "Machine role (remote/local/agent) [remote]: " machine_role </dev/tty
        fi
        machine_role="${machine_role:-remote}"
    fi
    case "$machine_role" in
        remote|local|agent) ;;
        *) error "Invalid machine role '$machine_role'. Use remote, local, or agent." ;;
    esac

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

# Route chezmoi's bitwarden integration through our wrapper, which
# always passes --session and --nointeraction. bw 2026.x has been
# observed to silently ignore BW_SESSION env in some flows; the
# wrapper makes the session explicit. Wrapper exits cleanly if
# BW_SESSION is unset, so a re-apply without unlocking the vault
# first fails loudly instead of dropping into bw's tty prompt.
[bitwarden]
  command = "$HOME/.local/share/chezmoi/scripts/bw-with-session.sh"
EOF
    info "Config written to $CHEZMOI_CFG"
else
    info "Chezmoi config already exists at $CHEZMOI_CFG — skipping prompts."
fi

# Migrate older configs missing the [bitwarden] wrapper. Idempotent.
if [ -f "$CHEZMOI_CFG" ] && ! grep -q '^\[bitwarden\]' "$CHEZMOI_CFG"; then
    info "Adding [bitwarden] wrapper to existing chezmoi.toml..."
    cat >> "$CHEZMOI_CFG" << EOF

[bitwarden]
  command = "$HOME/.local/share/chezmoi/scripts/bw-with-session.sh"
EOF
fi

# ── Clone dotfiles repo ────────────────────────────────────────────────────
REPO_PARENT="$HOME/.local/share/chezmoi"
if [ ! -d "$REPO_PARENT/.git" ]; then
    if ! command_exists git; then
        info "Installing git (required to clone the dotfiles repo)..."
        export DEBIAN_FRONTEND=noninteractive
        _apt update -qq
        _apt install -y git
    fi
    info "Cloning $DOTS_REPO into $REPO_PARENT ..."
    mkdir -p "$(dirname "$REPO_PARENT")"
    GIT_TERMINAL_PROMPT=0 git clone "$DOTS_REPO" "$REPO_PARENT" \
        || error "git clone $DOTS_REPO failed. If the repo is private, clone it manually into $REPO_PARENT (e.g. via SSH) and re-run."
else
    info "Chezmoi source already present at $REPO_PARENT."
fi

# Pick up the real color lib now that the repo is on disk.
if [ "${_DOTS_COLORS_SH:-0}" != "1" ] && [ -r "$REPO_PARENT/scripts/lib/colors.sh" ]; then
    # shellcheck source=/dev/null
    . "$REPO_PARENT/scripts/lib/colors.sh"
fi

# ── Apply dotfiles ─────────────────────────────────────────────────────────
# dot_gitconfig.tmpl reads `credential_helper` from dots-git-secrets at render
# time; if the item is missing, chezmoi apply would fail.
info "Ensuring Bitwarden items exist..."
"$REPO_PARENT/scripts/setup-bw-items.sh"

info "Applying dotfiles..."
chezmoi apply

# ── Login shell ────────────────────────────────────────────────────────────
_set_login_shell_zsh() {
    local zsh_path current_shell
    zsh_path="$(command -v zsh 2>/dev/null || true)"
    if [ -z "$zsh_path" ]; then
        c_warn "zsh not installed yet; skipping login-shell change."
        return
    fi
    current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
    if [ "$current_shell" = "$zsh_path" ]; then
        info "Login shell already zsh."
        return
    fi
    if grep -qxF "$zsh_path" /etc/shells 2>/dev/null && chsh -s "$zsh_path" 2>/dev/null; then
        info "Login shell set to $zsh_path via chsh."
        return
    fi
    info "chsh unavailable; installing bash -> zsh trampoline in ~/.bash_profile."
    local marker="# dots: exec zsh on interactive bash login"
    if ! grep -qF "$marker" "$HOME/.bash_profile" 2>/dev/null; then
        cat >> "$HOME/.bash_profile" << EOF

$marker
if [ -t 1 ] && [ -z "\$ZSH_VERSION" ] && command -v zsh >/dev/null; then
    exec zsh -l
fi
EOF
    fi
}
_set_login_shell_zsh

info "Done. Run 'cap' to apply future changes."
