#!/usr/bin/env bash
set -euo pipefail

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
