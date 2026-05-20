#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/colors.sh
. "$(dirname "${BASH_SOURCE[0]:-/dev/null}")/lib/colors.sh" 2>/dev/null || {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${DOTS_NO_COLOR:-}" ]; then
        _r=$'\033[0m'; _C=$'\033[36m'; _B=$'\033[34m'; _G=$'\033[32m'; _Y=$'\033[33m'; _R=$'\033[31m'
    else _r=; _C=; _B=; _G=; _Y=; _R=; fi
    c_step(){ printf '%s==>%s %s\n'    "$_C" "$_r" "$*"; }
    c_info(){ printf '%s[dots]%s %s\n' "$_B" "$_r" "$*"; }
    c_ok()  { printf '%s[ ok ]%s %s\n' "$_G" "$_r" "$*"; }
    c_warn(){ printf '%s[warn]%s %s\n' "$_Y" "$_r" "$*" >&2; }
    c_err() { printf '%s[ERR ]%s %s\n' "$_R" "$_r" "$*" >&2; }
}

# Install fzf from the upstream repo into ~/.fzf and run its installer to set up
# ~/.fzf.zsh (sourced by dot_zshrc.tmpl) with keybindings + completion.
# Re-runnable: pulls the latest if already cloned.
#
# Why upstream instead of OMZ's `fzf` plugin: that plugin tries to source
# /usr/share/doc/fzf/examples/key-bindings.zsh, which is missing or gzipped
# on several Ubuntu/Debian images and breaks shell startup.

FZF_DIR="$HOME/.fzf"

if ! command -v git >/dev/null 2>&1; then
    c_err "git is required to install fzf."
    exit 1
fi

if [ -d "$FZF_DIR/.git" ]; then
    c_info "Updating fzf in $FZF_DIR..."
    git -C "$FZF_DIR" pull --quiet --ff-only || c_warn "fzf pull failed; keeping existing clone."
else
    c_info "Cloning fzf to $FZF_DIR..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR"
fi

# --bin: compile/download the fzf binary into ~/.fzf/bin
# --key-bindings / --completion: enable Ctrl-T, Ctrl-R, Alt-C and tab completion
# --no-update-rc: don't touch ~/.zshrc — our dot_zshrc.tmpl already sources ~/.fzf.zsh
# --no-bash --no-fish: zsh only for this setup
"$FZF_DIR/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null

c_ok "fzf installed: $("$FZF_DIR/bin/fzf" --version)"
c_info "Open a new shell or run \`source ~/.fzf.zsh\` to pick up keybindings."
