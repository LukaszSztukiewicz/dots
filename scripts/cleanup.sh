#!/usr/bin/env bash
set -euo pipefail

# scripts/cleanup.sh — destructive cleanup of dots-managed state.
#
# Modes:
#   --reset    Remove install-side state (chezmoi config + source dir, bw
#              and chezmoi binaries, bw vault data). Re-running bootstrap.sh
#              after this re-bootstraps cleanly. Applied dotfiles in $HOME
#              are untouched.
#
#   --nuke     Reset, plus applied dotfiles, Oh My Zsh + plugins, fzf,
#              language toolchains, p10k cache, shell history, and the
#              bash->zsh trampoline in ~/.bash_profile. Confirms with a
#              typed 'NUKE' prompt unless --force or DOTS_NUKE_FORCE=1.
#
#   --force    Skip the typed confirmation for --nuke.
#
# Every path is removed only after an `[ -e ]` check, so missing paths
# are no-ops. The path list is hard-coded — no glob-rm under $HOME.

c_step() { printf '==> %s
' "$*"; }
c_info() { printf '[dots] %s
' "$*"; }
c_ok()   { printf '[ ok ] %s
' "$*"; }
c_warn() { printf '[warn] %s
' "$*" >&2; }
c_err()  { printf '[ERR ] %s
' "$*" >&2; }
error()  { c_err "$*"; exit 1; }
# shellcheck source=lib/colors.sh
_lib="$(dirname "${BASH_SOURCE[0]:-$0}")/lib/colors.sh"
{ [ -r "$_lib" ] && . "$_lib"; } || {
    _tmp=$(mktemp)
    curl -fsSL "${DOTS_RAW:-https://raw.githubusercontent.com/LukaszSztukiewicz/dots/main}/scripts/lib/colors.sh" \
        -o "$_tmp" 2>/dev/null && . "$_tmp"
    rm -f "$_tmp"
}
unset _lib _tmp

MODE=""
FORCE="${DOTS_NUKE_FORCE:-0}"
for arg in "$@"; do
    case "$arg" in
        --reset) MODE=reset ;;
        --nuke)  MODE=nuke  ;;
        --force) FORCE=1 ;;
        -h|--help)
            sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            c_err "Unknown argument: $arg"
            c_err "Usage: cleanup.sh [--reset | --nuke] [--force]"
            exit 2
            ;;
    esac
done

if [ -z "$MODE" ]; then
    c_err "One of --reset or --nuke is required."
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")/.." >/dev/null 2>&1 && pwd)"
PACKAGES_YAML="$REPO_ROOT/packages.yaml"

packages_from_yaml() {
    if [ ! -f "$PACKAGES_YAML" ]; then
        return 0
    fi
    grep -E '^[[:space:]]*ubuntu:' "$PACKAGES_YAML" | sed -E 's/^[[:space:]]*ubuntu:[[:space:]]*//' | tr '\n' ' ' | xargs || true
}

uninstall_packages_from_yaml() {
    local pkgs sudo_cmd=""
    if ! command -v apt-get >/dev/null 2>&1; then
        c_warn "apt-get unavailable; skipping packages.yaml uninstallation."
        return 0
    fi
    pkgs="$(packages_from_yaml)"
    [ -n "$pkgs" ] || return 0

    if [ "$(id -u)" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            c_warn "sudo unavailable; skipping packages.yaml uninstallation."
            return 0
        fi
        sudo_cmd=sudo
    fi

    c_step "Uninstalling apt packages from packages.yaml..."
    DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get remove -y --purge $pkgs || c_warn "apt-get remove failed; continuing."
    DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get autoremove -y || c_warn "apt-get autoremove failed; continuing."
    c_ok "Package cleanup complete."
}

RESET_PATHS=(
    "$HOME/.config/chezmoi"
    "$HOME/.local/share/chezmoi"
    "$HOME/.config/Bitwarden CLI"
    "$HOME/.local/bin/bw"
    "$HOME/.local/bin/chezmoi"
)

NUKE_EXTRA_PATHS=(
    # applied dotfiles
    "$HOME/.zshrc"
    "$HOME/.tmux.conf"
    "$HOME/.p10k.zsh"
    "$HOME/.gitconfig"
    "$HOME/.config/nvim"
    "$HOME/.config/tmux"
    "$HOME/.config/btop"
    # OMZ + plugins
    "$HOME/.oh-my-zsh"
    # fzf
    "$HOME/.fzf"
    "$HOME/.fzf.zsh"
    "$HOME/.fzf.bash"
    # manual runtimes installed by run_onchange scripts
    "$HOME/.local/bin/dua"
    "$HOME/.local/bin/btop"
    "$HOME/.local/bin/fd"
    "/usr/local/bin/nvim"
    "/opt/nvim-linux-x86_64"
    "/opt/nvim-linux-arm64"
    # language toolchains
    "$HOME/.local/share/uv"
    "$HOME/.cache/uv"
    "$HOME/.local/bin/uv"
    "$HOME/.local/bin/uvx"
    "$HOME/.nvm"
    "$HOME/miniconda3"
    "$HOME/.juliaup"
    "$HOME/.sdkman"
    # tmux static binary (item 2)
    "$HOME/.local/bin/tmux"
    # shell state
    "$HOME/.zsh_history"
)

remove_paths() {
    for p in "$@"; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            c_info "  rm -rf $p"
            rm -rf -- "$p" 2>/dev/null || command sudo rm -rf -- "$p" 2>/dev/null || c_warn "Failed to remove $p"
        fi
    done
}

# Remove glob-y caches/state separately. Kept narrow so we never expand
# into something unrelated.
remove_globs() {
    shopt -s nullglob
    local matches=(
        "$HOME/.cache/p10k-instant-prompt-"*
        "$HOME/.zcompdump"
        "$HOME/.zcompdump-"*
    )
    shopt -u nullglob
    [ "${#matches[@]}" -eq 0 ] && return
    for p in "${matches[@]}"; do
        [ -e "$p" ] || continue
        c_info "  rm -rf $p"
        rm -rf -- "$p" 2>/dev/null || command sudo rm -rf -- "$p" 2>/dev/null || c_warn "Failed to remove $p"
    done
}

# Surgically strip the bash trampoline marker block added by bootstrap.sh
# (item 3). Leaves the rest of ~/.bash_profile alone.
strip_bash_trampoline() {
    local bp="$HOME/.bash_profile"
    local marker="# dots: exec zsh on interactive bash login"
    [ -f "$bp" ] || return 0
    grep -qF "$marker" "$bp" || return 0
    c_info "  stripping bash->zsh trampoline from $bp"
    # Delete the marker line plus the following if-block ending at 'fi'.
    awk -v m="$marker" '
        BEGIN { skip = 0 }
        $0 ~ m { skip = 1; next }
        skip && $0 == "fi" { skip = 0; next }
        !skip { print }
    ' "$bp" > "$bp.tmp" && mv "$bp.tmp" "$bp" || c_warn "Failed to update $bp"
}

case "$MODE" in
    reset)
        c_step "Reset: clearing install-side state..."
        remove_paths "${RESET_PATHS[@]}"
        c_ok "Reset complete."
        ;;
    nuke)
        if [ "$FORCE" != "1" ]; then
            c_warn "About to NUKE every dots-managed file:"
            c_warn "  - install-side state (chezmoi, bw, vault data)"
            c_warn "  - applied dotfiles (~/.zshrc, ~/.tmux.conf, ~/.p10k.zsh, ~/.gitconfig)"
            c_warn "  - OMZ, fzf, p10k cache, ~/.zsh_history"
            c_warn "  - language toolchains (uv, nvm, conda, juliaup, sdkman)"
            c_warn "  - package installs from packages.yaml and run_onchange installers"
            c_warn "  - bash->zsh trampoline in ~/.bash_profile"
            printf 'Type NUKE to confirm: ' >&2
            IFS= read -r confirm
            [ "$confirm" = "NUKE" ] || { c_err "Aborted."; exit 1; }
        fi
        c_step "Nuke: removing all dots-managed state..."
        uninstall_packages_from_yaml
        remove_paths "${RESET_PATHS[@]}"
        remove_paths "${NUKE_EXTRA_PATHS[@]}"
        remove_globs
        strip_bash_trampoline
        c_ok "Nuke complete. The machine no longer has any dots-managed state."
        ;;
esac