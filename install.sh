#!/usr/bin/env bash
set -euo pipefail

# install.sh — stage 2 of the dots install.
#
# Assumes bootstrap.sh has already installed bw + chezmoi and produced a valid
# BW_SESSION in env. This script writes the per-machine chezmoi config, clones
# the dotfiles repo if missing, applies it, and sets zsh as the login shell.
#
# Run bootstrap.sh first:
#   curl -fsSL https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main/bootstrap.sh | bash
# It will print the two lines you copy here.

DOTS_REPO="${DOTS_REPO:-https://github.com/LukaszSztukiewicz/dots}"
DOTS_RAW="${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}"

# Source the shared color lib if the repo is already on disk; otherwise fall
# back to TTY-aware inline shims. Same code block as bootstrap.sh.
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

_apt() {
    if [ "$(id -u)" -eq 0 ]; then
        apt-get "$@"
    elif command_exists sudo; then
        sudo apt-get "$@"
    else
        error "apt-get $1 needs root and sudo is unavailable."
    fi
}

# 1. Validate prerequisites — bootstrap.sh must have run.
#
# bootstrap.sh installs bw + chezmoi into ~/.local/bin and prepends that dir
# to PATH inside its own subshell. When bootstrap.sh exits, that PATH change
# is gone. On a fresh machine the user's interactive shell typically does
# NOT have ~/.local/bin in PATH (our dot_zshrc.tmpl hasn't been applied yet,
# and bash's stock .profile only adds it if the dir existed at login time),
# so install.sh inherits a PATH without it. Prepend ourselves so the bw and
# chezmoi checks below find them.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

command_exists bw      || error "bw not found in PATH. Run bootstrap.sh first: curl -fsSL ${DOTS_RAW}/bootstrap.sh | bash"
command_exists chezmoi || error "chezmoi not found in PATH. Run bootstrap.sh first."
[ -n "${BW_SESSION:-}" ] || error "BW_SESSION not set. Run bootstrap.sh first; it prints the export line."

# Verify the session actually works against the vault (stale tokens pass
# bw's --check but fail on real operations).
if ! bw --nointeraction --session "$BW_SESSION" list folders >/dev/null 2>&1; then
    error "BW_SESSION is set but the vault is not accessible. Re-run bootstrap.sh to refresh the session."
fi
info "Bitwarden session valid."

# 2. Write per-machine chezmoi config (skip if already exists).
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

# 2a. Migrate older configs that don't yet wire chezmoi's bitwarden integration
# through the bw-with-session.sh wrapper. Idempotent.
if [ -f "$CHEZMOI_CFG" ] && ! grep -q '^\[bitwarden\]' "$CHEZMOI_CFG"; then
    info "Adding [bitwarden] wrapper to existing chezmoi.toml..."
    cat >> "$CHEZMOI_CFG" << EOF

[bitwarden]
  command = "$HOME/.local/share/chezmoi/scripts/bw-with-session.sh"
EOF
fi

# 3. Clone the dotfiles repo into the chezmoi source dir (if not already there).
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

# Repo is on disk now — pick up the real color lib if we were running with
# the fallback shims.
if [ "${_DOTS_COLORS_SH:-0}" != "1" ] && [ -r "$REPO_PARENT/scripts/lib/colors.sh" ]; then
    # shellcheck source=/dev/null
    . "$REPO_PARENT/scripts/lib/colors.sh"
fi

# 4. Bootstrap the Bitwarden items the dotfiles depend on. dot_gitconfig.tmpl
# reads `credential_helper` from dots-git-secrets at render time; if the item
# is missing, the very next `chezmoi apply` would fail.
info "Ensuring Bitwarden items exist..."
"$REPO_PARENT/scripts/setup-bw-items.sh"

info "Applying dotfiles..."
chezmoi apply

# 5. Make zsh the login shell so any session (tmux, ssh, console) starts in
#    zsh. Best-effort with a bash trampoline fallback for locked-down clusters.
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
