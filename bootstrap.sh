#!/usr/bin/env bash
set -euo pipefail

# bootstrap.sh — stage 1 of the dots install.
#
# Installs the bw + chezmoi binaries, logs in to Bitwarden, unlocks the vault,
# and prints the BW_SESSION export plus the curl|bash line for install.sh.
# Copy and run those two lines to continue with stage 2 (config prompts,
# clone, apply, login-shell setup).
#
# Why a split: lets you inspect the session, edit env vars, or re-run stage 2
# without re-authing every time. The single-shot install.sh is now stage 2 —
# it expects BW_SESSION already in env.

DOTS_REPO="${DOTS_REPO:-https://github.com/LukaszSztukiewicz/dots}"
DOTS_RAW="${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}"

# Source the shared color lib if the repo is already on disk; otherwise fall
# back to TTY-aware inline shims so bootstrap output is colored from line 1.
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

# 0. Optional cleanup. Lives in bootstrap (not install.sh) because cleanup
#    blows away the bw session that install.sh would otherwise validate.
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
        info "DOTS_RESET=1: clearing install state (inline, repo not yet cloned)..."
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

# 1. Detect OS.
if ! command_exists apt-get; then
    error "Only Ubuntu/apt-based systems are supported. Detected: $(uname -a)"
fi

# 1a. apt-get wrapper that picks sudo only when needed.
_apt() {
    if [ "$(id -u)" -eq 0 ]; then
        apt-get "$@"
    elif command_exists sudo; then
        sudo apt-get "$@"
    else
        error "apt-get $1 needs root and sudo is unavailable."
    fi
}

# 1b. Bootstrap dependencies bootstrap.sh itself needs.
_need_bootstrap=()
command_exists unzip || _need_bootstrap+=(unzip)
command_exists curl  || _need_bootstrap+=(curl)
if [ "${#_need_bootstrap[@]}" -gt 0 ]; then
    info "Installing bootstrap deps: ${_need_bootstrap[*]}"
    export DEBIAN_FRONTEND=noninteractive
    _apt update -qq
    _apt install -y "${_need_bootstrap[@]}"
fi

# 2. Install chezmoi.
if ! command_exists chezmoi; then
    info "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
fi

# 3. Install Bitwarden CLI.
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

# 4. Bitwarden auth — interactive via /dev/tty, or headless via
#    BW_CLIENTID/BW_CLIENTSECRET (+ BW_PASSWORD) env vars.
_strip_ws() { printf '%s' "$1" | awk '{$1=$1; print}'; }
[ -n "${BW_CLIENTID:-}"     ] && BW_CLIENTID="$(_strip_ws "$BW_CLIENTID")"         && export BW_CLIENTID
[ -n "${BW_CLIENTSECRET:-}" ] && BW_CLIENTSECRET="$(_strip_ws "$BW_CLIENTSECRET")" && export BW_CLIENTSECRET
[ -n "${BW_PASSWORD:-}"     ] && BW_PASSWORD="$(_strip_ws "$BW_PASSWORD")"         && export BW_PASSWORD

_have_tty()      { (exec </dev/tty) 2>/dev/null; }
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
            [ "$status" = "unlocked" ] && bw lock>/dev/null 2>&1 || true
            info "Unlocking Bitwarden vault..."
            _bw_unlock_interactive
            ;;
        unauthenticated)
            if _bw_have_apikey; then
                info "Logging in to Bitwarden via API key..."
                bw login --apikey --quiet
                info "Login complete. Unlocking vault..."
                # API key login leaves the vault locked, so we must unlock it now
                _bw_unlock_interactive
            elif _have_tty; then
                info "Not logged in to Bitwarden. Logging in (interactive)..."
                # Interactive login authenticates AND unlocks. We capture the raw token
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

info "Bitwarden ready (session length: ${#BW_SESSION} chars)."
echo
c_step "Bootstrap complete. Copy and run the two lines below to apply your dotfiles:"
echo
printf 'export BW_SESSION="%q"\n' "$BW_SESSION"
printf 'curl -fsSL %s/install.sh | bash\n' "$DOTS_RAW"
echo
